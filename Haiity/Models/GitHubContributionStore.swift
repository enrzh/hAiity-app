import Foundation
import Observation
import WidgetKit

enum GitHubRefreshFeedback: Equatable {
    case none
    case success
    case reauthenticationRequired
    case failure(String)
}

@MainActor
@Observable
final class GitHubContributionStore {
    enum Phase: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    private(set) var phase: Phase = .disconnected
    private(set) var deviceCode: GitHubDeviceCode?
    private(set) var snapshot: GitHubContributionSnapshot?
    private(set) var isRefreshing = false
    private(set) var refreshFeedback: GitHubRefreshFeedback = .none
    private(set) var refreshAnimationToken: UInt = 0

    private let vault: any GitHubCredentialVault
    private let authorizer: any GitHubDeviceAuthorizing
    private let contributions: any GitHubContributionsFetching
    private let cacheURL: URL
    private let pendingLoginURL: URL
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration: UInt = 0
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var connectionTaskID: UInt = 0
    @ObservationIgnored private var connectionGeneration: UInt = 0

    private struct PendingLogin: Codable {
        let code: GitHubDeviceCode
        let startedAt: Date
    }

    static let refreshInterval: TimeInterval = 60 * 60

    nonisolated static var defaultCacheURL: URL {
        GitHubContributionSnapshot.sharedCacheURL()
    }

    init(vault: any GitHubCredentialVault = KeychainGitHubCredentialVault(),
         authorizer: any GitHubDeviceAuthorizing = GitHubDeviceFlow(),
         contributions: any GitHubContributionsFetching = GitHubContributionsClient(),
         cacheURL: URL = GitHubContributionStore.defaultCacheURL) {
        self.vault = vault
        self.authorizer = authorizer
        self.contributions = contributions
        self.cacheURL = cacheURL
        self.pendingLoginURL = cacheURL.deletingLastPathComponent()
            .appendingPathComponent("github-device-login.json")
    }

    func boot(now: Date = .now) async {
        #if DEBUG
        if Self.isDemoLaunch {
            snapshot = Self.demoSnapshot(now: now)
            phase = .connected
            return
        }
        #endif
        snapshot = loadCache()
        if snapshot != nil { phase = .connected }
        await resumeOrRefresh(now: now)
    }

    func resumeOrRefresh(now: Date = .now, forced: Bool = false) async {
        await resumePendingLogin(now: now)
        guard phase != .connecting else { return }
        await refresh(now: now, forced: forced)
    }

    func resumePendingLogin(now: Date = .now) async {
        if let code = loadPendingLogin(now: now) {
            deviceCode = code
            phase = .connecting
        }
        guard phase == .connecting, deviceCode != nil else { return }
        await connect()
    }

    func connect() async {
        #if DEBUG
        if Self.isDemoLaunch {
            snapshot = Self.demoSnapshot(now: .now)
            phase = .connected
            return
        }
        #endif

        await withTaskCancellationHandler(operation: {
            await self.connectUntilSettled()
        }, onCancel: {
            Task { @MainActor [weak self] in
                // Once the code is visible, Safari is part of this flow. The
                // caller can be canceled while the app is backgrounded, but
                // the store-owned poll must stay alive for that login.
                guard let self, self.deviceCode == nil else { return }
                self.connectionTask?.cancel()
            }
        })
    }

    private func connectUntilSettled() async {
        var retried = false

        while true {
            let taskID: UInt
            if let existing = connectionTask {
                taskID = connectionTaskID
                await existing.value
            } else {
                connectionTaskID &+= 1
                taskID = connectionTaskID
                let generation = connectionGeneration
                let task = Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.performConnect(generation: generation)
                }
                connectionTask = task
                await task.value
            }

            if connectionTaskID == taskID {
                connectionTask = nil
            }

            guard !Task.isCancelled, phase == .connecting, !retried else { return }
            retried = true
        }
    }

    private func performConnect(generation: UInt) async {
        guard generation == connectionGeneration else { return }

        let savedCode = phase == .connecting ? deviceCode : nil
        phase = .connecting
        if savedCode == nil { deviceCode = nil }
        var code = savedCode
        var tokenSaved = false
        do {
            if code == nil {
                let requested = try await authorizer.requestCode()
                guard generation == connectionGeneration else { return }
                code = requested
                deviceCode = requested
                persistPendingLogin(requested, startedAt: .now)
                if Task.isCancelled {
                    preservePendingLogin(code)
                    return
                }
            }
            guard let code else { return }
            let token = try await authorizer.pollForToken(code)
            guard generation == connectionGeneration else { return }
            if Task.isCancelled {
                preservePendingLogin(code)
                return
            }
            try vault.save(token)
            tokenSaved = true
            let snap = try await contributions.fetch(token: token, now: .now)
            guard generation == connectionGeneration else { return }
            if Task.isCancelled {
                preservePendingLogin(code)
                return
            }
            persist(snap)
            removePendingLogin()
            snapshot = snap
            deviceCode = nil
            phase = .connected
        } catch is CancellationError {
            guard generation == connectionGeneration else { return }
            preservePendingLogin(code)
        } catch let error as GitHubDeviceFlowError where error == .cancelled {
            guard generation == connectionGeneration else { return }
            preservePendingLogin(code)
        } catch {
            guard generation == connectionGeneration else { return }
            if Task.isCancelled || (!tokenSaved && isResumableDeviceLoginError(error)) {
                preservePendingLogin(code)
                return
            }
            deviceCode = nil
            removePendingLogin()
            let unauthorized = (error as? GitHubContributionsError) == .unauthorized
            if !tokenSaved || unauthorized {
                try? vault.delete()
            }
            if snapshot != nil {
                phase = .connected
            } else {
                phase = .failed(Self.message(for: error))
            }
        }
    }

    func refresh(now: Date = .now, forced: Bool = false) async {
        #if DEBUG
        if Self.isDemoLaunch {
            snapshot = snapshot ?? Self.demoSnapshot(now: now)
            phase = .connected
            return
        }
        #endif
        if phase == .connecting {
            if connectionTask == nil {
                await connect()
            } else {
                Task { @MainActor [weak self] in
                    await self?.connect()
                }
            }
            return
        }
        if let pending = loadPendingLogin(now: now) {
            deviceCode = pending
            phase = .connecting
            await connect()
            return
        }
        if let refreshTask {
            await refreshTask.value
            return
        }
        let generation = refreshGeneration
        let task = Task {
            await self.performRefresh(now: now, forced: forced, generation: generation)
        }
        refreshTask = task
        await task.value
        if generation == refreshGeneration { refreshTask = nil }
    }

    func disconnect() {
        connectionGeneration &+= 1
        connectionTaskID &+= 1
        connectionTask?.cancel()
        connectionTask = nil
        refreshGeneration &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        do {
            try vault.delete()
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                try FileManager.default.removeItem(at: cacheURL)
            }
        } catch {
            phase = .failed(Self.message(for: error))
            return
        }
        snapshot = nil
        deviceCode = nil
        removePendingLogin()
        phase = .disconnected
    }

    func prepareForReauthentication() {
        try? vault.delete()
        refreshFeedback = .none
        phase = .disconnected
    }

    private func performRefresh(now: Date, forced: Bool, generation: UInt) async {
        let token: String
        do {
            guard let stored = try vault.read(), !stored.isEmpty else {
                // Keychain access can be temporarily unavailable during app
                // resume. Keep the cached graph until the user explicitly
                // disconnects, otherwise a background refresh looks like a
                // logout and the card disappears.
                if snapshot == nil { snapshot = loadCache() }
                phase = snapshot == nil ? .disconnected : .connected
                return
            }
            token = stored
        } catch {
            if snapshot == nil { phase = .failed(Self.message(for: error)) }
            return
        }

        if !forced, let snapshot, now.timeIntervalSince(snapshot.fetchedAt) < Self.refreshInterval {
            phase = .connected
            return
        }

        refreshFeedback = .none
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let snap = try await contributions.fetch(token: token, now: now)
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            persist(snap)
            snapshot = snap
            phase = .connected
            recordRefresh(.success)
        } catch let error as GitHubContributionsError where error == .unauthorized {
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            recordRefresh(.reauthenticationRequired)
            // A background refresh must not turn a transiently rejected API
            // request into a logout. Keep the token and cached graph visible;
            // only the explicit disconnect action clears credentials.
            phase = snapshot == nil ? .failed(Self.message(for: error)) : .connected
        } catch is CancellationError {
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            if snapshot != nil { phase = .connected }
        } catch {
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            recordRefresh(.failure(Self.message(for: error)))
            if snapshot != nil {
                phase = .connected
            } else {
                phase = .failed(Self.message(for: error))
            }
        }
    }

    private func recordRefresh(_ feedback: GitHubRefreshFeedback) {
        refreshFeedback = feedback
        refreshAnimationToken &+= 1
    }

    private func persist(_ snapshot: GitHubContributionSnapshot) {
        guard (try? GitHubContributionSnapshot.saveShared(snapshot, to: cacheURL)) != nil else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: "HaiityGraphWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "HaiityGitHubWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "HaiityWidget")
    }

    private func loadCache() -> GitHubContributionSnapshot? {
        GitHubContributionSnapshot.loadShared(from: cacheURL)
    }

    var hasStoredCredentials: Bool {
        do {
            return try vault.read()?.isEmpty == false
        } catch {
            return false
        }
    }

    private func persistPendingLogin(_ code: GitHubDeviceCode, startedAt: Date) {
        let pending = PendingLogin(code: code, startedAt: startedAt)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(pending) else { return }
        let directory = pendingLoginURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: pendingLoginURL, options: .atomic)
    }

    private func loadPendingLogin(now: Date) -> GitHubDeviceCode? {
        guard let data = try? Data(contentsOf: pendingLoginURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let pending = try? decoder.decode(PendingLogin.self, from: data),
              pending.code.expiresIn > 0,
              now < pending.startedAt.addingTimeInterval(TimeInterval(pending.code.expiresIn)) else {
            removePendingLogin()
            return nil
        }
        return pending.code
    }

    private func preservePendingLogin(_ code: GitHubDeviceCode?) {
        guard let code else {
            deviceCode = nil
            phase = snapshot == nil ? .disconnected : .connected
            return
        }
        deviceCode = code
        phase = .connecting
    }

    private func isResumableDeviceLoginError(_ error: Error) -> Bool {
        if error is URLError { return true }
        guard let error = error as? GitHubDeviceFlowError else { return false }
        switch error {
        case .httpStatus(let status):
            return status == 408 || status == 429 || status >= 500
        case .unconfigured, .denied, .expired, .cancelled, .malformedPayload:
            return false
        }
    }

    private func removePendingLogin() {
        try? FileManager.default.removeItem(at: pendingLoginURL)
    }

    static func message(for error: Error) -> String {
        if let error = error as? GitHubDeviceFlowError {
            switch error {
            case .unconfigured:
                return String(localized: "GitHub ist nicht eingerichtet.")
            case .denied:
                return String(localized: "GitHub hat die Verbindung abgelehnt.")
            case .expired:
                return String(localized: "Der Code ist abgelaufen. Bitte erneut verbinden.")
            case .cancelled, .httpStatus, .malformedPayload:
                return String(localized: "Die Verbindung zu GitHub ist fehlgeschlagen.")
            }
        }
        if error as? GitHubContributionsError == .unauthorized {
            return String(localized: "Die Verbindung zu GitHub ist fehlgeschlagen.")
        }
        return String(localized: "Die Verbindung zu GitHub ist fehlgeschlagen.")
    }

    #if DEBUG
    nonisolated static var isDemoLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("-demo-github-card")
    }

    nonisolated static func demoSnapshot(now: Date) -> GitHubContributionSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let end = calendar.startOfDay(for: now)
        var days: [GitHubContributionDay] = []
        days.reserveCapacity(371)
        for offset in (0..<371).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: end) else { continue }
            let key = formatter.string(from: date)
            let seed = key.utf8.reduce(0) { ($0 &* 33) &+ Int($1) }
            let level = abs(seed) % 5
            let count = level == 0 ? 0 : (abs(seed) % 12) + 1
            days.append(GitHubContributionDay(date: key, count: count, level: level))
        }
        return GitHubContributionSnapshot(username: "enrzh", days: days, fetchedAt: now)
    }
    #endif
}
