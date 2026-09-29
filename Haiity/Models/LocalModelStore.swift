import Foundation

/// Where one model's weights are, and how far along they are.
///
/// A download of a gigabyte is not a thing that either happened or did not, and
/// the states here are the ones a person can actually be shown. The distinction
/// that matters most is `failed` carrying the reason: "nothing happened" and
/// "it ran out of space" are different problems with different fixes, and a
/// state that cannot tell them apart will be reported as the first one.
enum LocalModelState: Equatable, Sendable {
    case notDownloaded
    case downloading(received: Int64, total: Int64)
    case ready(byteCount: Int64)
    case failed(String)

    var isReady: Bool { if case .ready = self { return true }; return false }

    var isDownloading: Bool { if case .downloading = self { return true }; return false }

    /// 0…1, or nil when the total is not yet known — a progress bar that jumps
    /// back from 100 is worse than one that waits.
    var fraction: Double? {
        switch self {
        case .downloading(let received, let total) where total > 0:
            return min(1, Double(received) / Double(total))
        case .ready(let bytes) where bytes > 0:
            return 1
        default:
            return nil
        }
    }
}

/// Where downloaded weights live, and how much of the phone they take.
///
/// Kept apart from the store's own state on purpose: this is the only thing that
/// has to be right when the app is relaunched mid-download, because everything
/// else can be recomputed by looking at what is on disk.
struct LocalModelInventory: Equatable, Sendable {
    /// Model id to the directory its weights were written into.
    private(set) var directories: [String: String] = [:]

    /// Bytes actually on disk per model, as opposed to bytes the repository
    /// claims. These differ while a download is in flight, and after a failure.
    private(set) var byteCounts: [String: Int64] = [:]

    func directory(for modelID: String) -> String? { directories[modelID] }
    func byteCount(for modelID: String) -> Int64 { byteCounts[modelID] ?? 0 }
    func isPresent(_ modelID: String) -> Bool { directories[modelID] != nil }

    var totalBytes: Int64 { byteCounts.values.reduce(0, +) }

    var models: Set<String> { Set(directories.keys) }

    /// Records that a model's weights are on disk. This is the only way a model
    /// becomes ready, so it is deliberately the only way its bytes are recorded
    /// too — a count without a directory would be a model that occupies storage
    /// and can never load.
    mutating func record(modelID: String, directory: String, byteCount: Int64) {
        directories[modelID] = directory
        byteCounts[modelID] = byteCount
    }

    /// Forgets a model. Used both when a download is abandoned and when somebody
    /// deletes it to reclaim the space.
    mutating func remove(_ modelID: String) {
        directories[modelID] = nil
        byteCounts[modelID] = nil
    }
}

/// A download in flight, so it can be resumed, cancelled and reported on.
struct LocalModelDownload: Equatable, Sendable {
    let modelID: String
    var received: Int64
    var total: Int64

    var fraction: Double {
        total > 0 ? min(1, Double(received) / Double(total)) : 0
    }
}

/// The catalogue's current state, and the only thing allowed to change it.
///
/// Mutations are explicit methods rather than a settable dictionary, because the
/// interesting rule is the one about *transitions*: a model that is not on disk
/// must never report itself as ready, whatever a caller does. That is enforced
/// here once instead of at every call site.
struct LocalModelRegistry: Equatable, Sendable {

    private(set) var states: [String: LocalModelState] = [:]
    private(set) var inventory: LocalModelInventory

    init(inventory: LocalModelInventory = LocalModelInventory()) {
        self.inventory = inventory
        // What is on disk is the truth about readiness. Starting empty and
        // claiming `ready` is the one state a fresh relaunch must never invent.
        states = [:]
    }

    func state(for modelID: String) -> LocalModelState {
        if let known = states[modelID] { return known }
        return inventory.isPresent(modelID)
            ? .ready(byteCount: inventory.byteCount(for: modelID))
            : .notDownloaded
    }

    var readyModelIDs: [String] {
        LocalModelCatalogue.all.map(\.id).filter { state(for: $0).isReady }
    }

    var isDownloadingAnything: Bool {
        states.values.contains { $0.isDownloading }
    }

    mutating func markDownloading(_ modelID: String, received: Int64, total: Int64) {
        // A model already on disk stays ready. Re-downloading is a separate,
        // deliberate act, and progress must never make a working model vanish.
        guard !state(for: modelID).isReady else { return }
        states[modelID] = .downloading(received: received, total: total)
    }

    /// Called when the bytes are on disk. The byte count is taken from the
    /// inventory rather than from the download, so a short write cannot be
    /// reported as a finished model.
    mutating func markReady(_ modelID: String) {
        guard inventory.isPresent(modelID) else {
            // No directory means nothing was written. Saying "ready" here is
            // exactly the lie that makes a model fail at generation time with no
            // explanation, so it is refused rather than reported.
            states[modelID] = .failed(String(localized: "Die Dateien sind nicht vollständig."))
            return
        }
        states[modelID] = .ready(byteCount: inventory.byteCount(for: modelID))
    }

    mutating func markFailed(_ modelID: String, reason: String) {
        guard !state(for: modelID).isReady else { return }
        states[modelID] = .failed(reason)
    }

    mutating func markRemoved(_ modelID: String) {
        states[modelID] = nil
    }

    /// Re-reads the disk and rebuilds readiness from it. The single place where
    /// "what is on disk" may change, so a model cannot become ready by anything
    /// other than its files actually being there — and a model whose directory
    /// has gone loses its readiness here rather than staying ready forever.
    mutating func rebuildInventory(_ inventory: LocalModelInventory) {
        self.inventory = inventory
        for modelID in states.keys where !inventory.isPresent(modelID) {
            states[modelID] = nil
        }
    }
}
