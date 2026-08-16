import Foundation
import Observation

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

    private let vault: any GitHubCredentialVault
    private let authorizer: any GitHubDeviceAuthorizing
    private let contributions: any GitHubContributionsFetching
    private let cacheURL: URL
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    static let refreshInterval: TimeInterval = 60 * 60

    nonisolated static var defaultCacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("haiity", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("github-contributions.json")
    }

    init(vault: any GitHubCredentialVault = KeychainGitHubCredentialVault(),
         authorizer: any GitHubDeviceAuthorizing = GitHubDeviceFlow(),
         contributions: any GitHubContributionsFetching = GitHubContributionsClient(),
         cacheURL: URL = GitHubContributionStore.defaultCacheURL) {
        self.vault = vault
        self.authorizer = authorizer
        self.contributions = contributions
        self.cacheURL = cacheURL
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
        await refresh(now: now)
    }

    func connect() async {
        #if DEBUG
        if Self.isDemoLaunch {
            snapshot = Self.demoSnapshot(now: .now)
            phase = .connected
            return
        }
        #endif
        phase = .connecting
        deviceCode = nil
        do {
            let code = try await authorizer.requestCode()
            deviceCode = code
            let token = try await authorizer.pollForToken(code)
            let snap = try await contributions.fetch(token: token, now: .now)
            try vault.save(token)
            persist(snap)
            snapshot = snap
            deviceCode = nil
            phase = .connected
        } catch is CancellationError {
            deviceCode = nil
            phase = snapshot == nil ? .disconnected : .connected
        } catch let error as GitHubDeviceFlowError where error == .cancelled {
            deviceCode = nil
            phase = snapshot == nil ? .disconnected : .connected
        } catch {
            deviceCode = nil
            try? vault.delete()
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
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { await self.performRefresh(now: now, forced: forced) }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    func disconnect() {
        refreshTask?.cancel()
        refreshTask = nil
        try? vault.delete()
        try? FileManager.default.removeItem(at: cacheURL)
        snapshot = nil
        deviceCode = nil
        phase = .disconnected
    }

    private func performRefresh(now: Date, forced: Bool) async {
        let token: String
        do {
            guard let stored = try vault.read(), !stored.isEmpty else {
                if snapshot == nil { phase = .disconnected }
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

        do {
            let snap = try await contributions.fetch(token: token, now: now)
            persist(snap)
            snapshot = snap
            phase = .connected
        } catch let error as GitHubContributionsError where error == .unauthorized {
            disconnect()
        } catch is CancellationError {
            if snapshot != nil { phase = .connected }
        } catch {
            if snapshot != nil {
                phase = .connected
            } else {
                phase = .failed(Self.message(for: error))
            }
        }
    }

    private func persist(_ snapshot: GitHubContributionSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        let directory = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func loadCache() -> GitHubContributionSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GitHubContributionSnapshot.self, from: data)
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
