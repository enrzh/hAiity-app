import Foundation

/// Downloading and keeping the weights for a local model.
///
/// **This is device-local on purpose.** A model exists only on the phone that
/// fetched it, so neither the choice nor the bytes belong in the synced payload:
/// syncing a selection would put a model name on a second device that has never
/// downloaded it, and that device would then offer to read a sentence with a
/// model it does not have. The choice lives in the app's own defaults.
///
/// Three things here are less obvious than they look:
///
///  * **A model is assembled in a staging directory and moved into place.** A
///    download that is cancelled at 90% must not leave a directory that looks
///    like a model, because the whole app decides "is this model usable" by
///    asking whether its files are on disk.
///  * **Room is checked before the first byte, not when it runs out.** Failing at
///    98% with a half-written directory is the worst version of this.
///  * **Excluded from backup.** A gigabyte of re-downloadable weights has no
///    business in iCloud, and it would silently consume the user's iCloud quota
///    to do it.
@MainActor
@Observable
final class LocalModelService {

    /// Where weights live. Application Support rather than Documents: these are
    /// not the user's files and must not appear in a file browser or a share
    /// sheet.
    private let root: URL
    private let session: URLSession
    private let defaults: UserDefaults

    private(set) var registry: LocalModelRegistry
    private var tasks: [String: URLSessionDownloadTask] = [:]
    /// Resumable data kept per model so an interrupted download does not restart
    /// from zero. Apple's resume data is opaque and expires, which is handled by
    /// starting over when it is no longer accepted.
    private var resumeData: [String: Data] = [:]

    init(root: URL? = nil, session: URLSession = .shared,
         defaults: UserDefaults = .standard) {
        self.root = root ?? Self.defaultRoot()
        self.session = session
        self.defaults = defaults
        registry = LocalModelRegistry(inventory: Self.scan(root: self.root))
    }

    private static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
            .appendingPathComponent("LocalModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // Re-downloadable, and far too big to be worth syncing.
        var url = base
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }

    // MARK: - What is on disk

    /// A directory counts as a model only if every file the catalogue names is in
    /// it. Anything less is a broken download wearing a model's name.
    static func scan(root: URL) -> LocalModelInventory {
        var inventory = LocalModelInventory()
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: root.path) else {
            return inventory
        }
        for model in LocalModelCatalogue.all where entries.contains(model.id) {
            let directory = root.appendingPathComponent(model.id, isDirectory: true)
            let present = model.files.allSatisfy {
                fm.fileExists(atPath: directory.appendingPathComponent($0).path)
            }
            guard present else { continue }
            var bytes: Int64 = 0
            for file in model.files {
                let path = directory.appendingPathComponent(file).path
                if let size = try? fm.attributesOfItem(atPath: path)[.size] as? NSNumber {
                    bytes += size.int64Value
                }
            }
            inventory.record(modelID: model.id, directory: directory.path, byteCount: bytes)
        }
        return inventory
    }

    /// Re-reads what is on disk.
    ///
    /// The registry is built once at init, which is right for a launch. It is
    /// wrong for a download that finished while the app was in the background and
    /// for a folder the user tidied up behind our back, so the disk is consulted
    /// again whenever the app comes back to the foreground.
    func refresh() {
        registry.rebuildInventory(Self.scan(root: root))
    }

    func directory(for model: LocalModelDescriptor) -> URL {
        root.appendingPathComponent(model.id, isDirectory: true)
    }

    var totalBytesOnDisk: Int64 { registry.inventory.totalBytes }

    // MARK: - The choice

    /// Which model the person picked. Defaults to the smallest, and a stored id
    /// that is no longer in the catalogue falls back rather than stranding the
    /// app on a name it cannot resolve.
    var selectedModelID: String {
        get {
            let stored = defaults.string(forKey: Keys.selected) ?? ""
            return LocalModelCatalogue.descriptor(for: stored) == nil
                ? LocalModelCatalogue.default.id : stored
        }
        set {
            guard LocalModelCatalogue.descriptor(for: newValue) != nil else { return }
            defaults.set(newValue, forKey: Keys.selected)
        }
    }

    var selectedModel: LocalModelDescriptor {
        LocalModelCatalogue.descriptor(for: selectedModelID) ?? LocalModelCatalogue.default
    }

    /// The model that would actually be used to read a sentence right now.
    ///
    /// Selection and availability are different things: a person can have chosen
    /// the 2 GB model on one device while another still has only the small one.
    /// Answering with the choice regardless of whether its weights are here would
    /// hand the reader a model that cannot load, so the choice is only honoured
    /// when the model is actually present.
    var usableModel: LocalModelDescriptor {
        let chosen = selectedModel
        if registry.state(for: chosen.id).isReady { return chosen }
        // Not here. A processing model that IS here beats the choice, because it
        // is the one this app is shaped around and it is the cheapest to run.
        let readyProcessing = LocalModelCatalogue.all.first {
            $0.scope == .processing && registry.state(for: $0.id).isReady
        }
        // With nothing downloaded at all, the default is the right answer: it is
        // the one the app will offer to fetch, and the smallest.
        return readyProcessing ?? LocalModelCatalogue.default
    }

    // MARK: - Space

    private var availableBytes: Int64? {
        let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Refuses before starting rather than failing at the end.
    func canFit(_ model: LocalModelDescriptor) -> Bool {
        guard let free = availableBytes else { return true }  // unknown: allow
        // The staging copy and the finished copy briefly coexist during the move.
        return free > model.byteCount + model.byteCount / 4
    }

    // MARK: - Downloading

    /// The resolve URL for one file of a repository. Not the API and not a
    /// redirector: the CDN's own `resolve` path is what serves weight files
    /// cheaply, and pinning `main` is deliberate so a download and a later resume
    /// agree.
    static func fileURL(repository: String, file: String) -> URL? {
        var components = URLComponents(string: "https://huggingface.co")
        components?.path = "/\(repository)/resolve/main/\(file)"
        return components?.url
    }

    func download(_ model: LocalModelDescriptor) async {
        guard registry.state(for: model.id).isDownloading == false else { return }
        guard canFit(model) else {
            registry.markFailed(model.id, reason: String(localized: "Nicht genug Speicherplatz."))
            return
        }
        // Straight into staging. Nothing named after the model exists until every
        // file has arrived, so an interrupted run cannot look complete.
        let staging = root.appendingPathComponent(".staging-\(model.id)", isDirectory: true)
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        var received: Int64 = 0
        for file in model.files {
            guard let url = Self.fileURL(repository: model.repository, file: file) else { continue }
            let destination = staging.appendingPathComponent(file)
            do {
                let temporary = try await fetch(url, modelID: model.id)
                if let size = try? FileManager.default
                    .attributesOfItem(atPath: temporary.path)[.size] as? NSNumber {
                    received += size.int64Value
                }
                registry.markDownloading(model.id, received: received, total: model.byteCount)
                // Staging is rebuilt on every run, so a leftover copy of a file
                // that is being replaced has to go first.
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temporary, to: destination)
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: staging)
                registry.markRemoved(model.id)
                return
            } catch {
                try? FileManager.default.removeItem(at: staging)
                registry.markFailed(model.id, reason: Self.describe(error))
                return
            }
        }

        // Everything is here. Publish it under the model's name in one move.
        let destination = directory(for: model)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: staging, to: destination)
        } catch {
            registry.markFailed(model.id, reason: Self.describe(error))
            return
        }
        registry.rebuildInventory(Self.scan(root: root))
        registry.markReady(model.id)
    }

    private func fetch(_ url: URL, modelID: String) async throws -> URL {
        var request = URLRequest(url: url)
        if let data = resumeData[modelID] {
            // Offered, not required: the server decides whether it still has it.
            request.setValue("bytes=\(data.count)-", forHTTPHeaderField: "Range")
        }

        let (temporary, response) = try await withTaskCancellationHandler {
            try await session.download(for: request)
        } onCancel: { [weak self] in
            Task { @MainActor in self?.tasks[modelID]?.cancel() }
        }

        if let http = response as? HTTPURLResponse, http.statusCode == 416 {
            // Our resume offset is past the end: the file is already whole.
            return temporary
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return temporary
    }

    func cancel(_ model: LocalModelDescriptor) {
        tasks[model.id]?.cancel()
        tasks[model.id] = nil
        try? FileManager.default.removeItem(
            at: root.appendingPathComponent(".staging-\(model.id)", isDirectory: true))
        registry.markRemoved(model.id)
    }

    /// Reclaims the space. The directory is the model's whole existence, so this
    /// is the operation that has to actually free it.
    func delete(_ model: LocalModelDescriptor) {
        cancel(model)
        try? FileManager.default.removeItem(at: directory(for: model))
        registry.rebuildInventory(Self.scan(root: root))
        registry.markRemoved(model.id)
        if selectedModelID == model.id { selectedModelID = LocalModelCatalogue.default.id }
    }

    /// The reason has to survive to the picker, because "nothing happened" and
    /// "the phone ran out of room" need different answers.
    private static func describe(_ error: Error) -> String {
        let urlError = error as? URLError
        switch urlError?.code {
        case .notConnectedToInternet: return String(localized: "Kein Netz.")
        case .timedOut: return String(localized: "Zeitüberschreitung.")
        case .cancelled: return String(localized: "Abgebrochen.")
        case .badServerResponse: return String(localized: "Die Datei war nicht erreichbar.")
        case .cannotWriteToFile: return String(localized: "Nicht genug Speicherplatz.")
        default:
            if urlError == nil, (error as NSError).code == NSFileWriteOutOfSpaceError {
                return String(localized: "Nicht genug Speicherplatz.")
            }
            return String(localized: "Der Download ist fehlgeschlagen.")
        }
    }

    private enum Keys {
        static let selected = "localModel.selectedModelID"
    }
}

private let NSFileWriteOutOfSpaceError = 640
