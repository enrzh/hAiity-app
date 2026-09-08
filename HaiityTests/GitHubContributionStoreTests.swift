import Foundation
import XCTest
@testable import Haiity

actor FakeGitHubAuthorizer: GitHubDeviceAuthorizing {
    var events: [String] = []
    var code = GitHubDeviceCode(deviceCode: "dc",
                                userCode: "WXYZ-9876",
                                verificationURL: URL(string: "https://github.com/login/device")!,
                                expiresIn: 900,
                                interval: 5)
    var tokenResult: Result<String, Error> = .success("gho_live")
    var requestError: Error?

    func requestCode() async throws -> GitHubDeviceCode {
        events.append("request")
        if let requestError { throw requestError }
        return code
    }

    func pollForToken(_ code: GitHubDeviceCode) async throws -> String {
        events.append("poll")
        return try tokenResult.get()
    }

    func setRequestError(_ error: Error?) {
        requestError = error
    }

    func setTokenResult(_ result: Result<String, Error>) {
        tokenResult = result
    }
}

actor BlockingGitHubAuthorizer: GitHubDeviceAuthorizing {
    let code = GitHubDeviceCode(deviceCode: "dc",
                                userCode: "WXYZ-9876",
                                verificationURL: URL(string: "https://github.com/login/device")!,
                                expiresIn: 900,
                                interval: 5)
    private(set) var didStartPolling = false
    private var pollingReleased = false
    private var waiters: [CheckedContinuation<String, Never>] = []

    func requestCode() async throws -> GitHubDeviceCode {
        code
    }

    func pollForToken(_ code: GitHubDeviceCode) async throws -> String {
        didStartPolling = true
        if pollingReleased { return "gho_live" }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func releasePolling() {
        pollingReleased = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(returning: "gho_live") }
    }
}

actor CancellableGitHubAuthorizer: GitHubDeviceAuthorizing {
    let code = GitHubDeviceCode(deviceCode: "dc",
                                userCode: "WXYZ-9876",
                                verificationURL: URL(string: "https://github.com/login/device")!,
                                expiresIn: 900,
                                interval: 5)
    private(set) var didStartPolling = false
    private var pollingCancelled = false

    func requestCode() async throws -> GitHubDeviceCode {
        code
    }

    func pollForToken(_ code: GitHubDeviceCode) async throws -> String {
        didStartPolling = true
        while !pollingCancelled {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw GitHubDeviceFlowError.cancelled
    }

    func cancelPolling() {
        pollingCancelled = true
    }
}

actor RestartableGitHubAuthorizer: GitHubDeviceAuthorizing {
    let code = GitHubDeviceCode(deviceCode: "dc",
                                userCode: "WXYZ-9876",
                                verificationURL: URL(string: "https://github.com/login/device")!,
                                expiresIn: 900,
                                interval: 5)
    private(set) var pollCount = 0
    private var cancelFirstPoll = false

    func requestCode() async throws -> GitHubDeviceCode {
        code
    }

    func pollForToken(_ code: GitHubDeviceCode) async throws -> String {
        pollCount += 1
        if pollCount == 1 {
            while !cancelFirstPoll {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            throw GitHubDeviceFlowError.cancelled
        }
        return "gho_retry"
    }

    func cancelFirstPollNow() {
        cancelFirstPoll = true
    }
}

actor FakeGitHubContributions: GitHubContributionsFetching {
    var events: [String] = []
    var delayNanoseconds: UInt64 = 0
    var ignoresCancellation = false
    var fetchCount = 0
    var lastToken: String?
    var result: Result<GitHubContributionSnapshot, Error>

    init(result: Result<GitHubContributionSnapshot, Error>) {
        self.result = result
    }

    func fetch(token: String, now: Date) async throws -> GitHubContributionSnapshot {
        events.append("fetch")
        fetchCount += 1
        lastToken = token
        if delayNanoseconds > 0 {
            if ignoresCancellation {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            } else {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
        }
        return try result.get()
    }
}

final class GitHubContributionStoreTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-08-16T12:00:00Z")!
    private var cacheURL: URL!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("github-store-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cacheURL = dir.appendingPathComponent("github-contributions.json")
    }

    override func tearDown() {
        if let cacheURL {
            try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
        }
        super.tearDown()
    }

    @MainActor
    func testBootRestoresValidCacheAndSkipsFreshRefresh() async throws {
        let snap = sample(fetchedAt: now.addingTimeInterval(-60))
        try write(snap)
        let contributions = FakeGitHubContributions(result: .success(sample(fetchedAt: now)))
        let store = GitHubContributionStore(vault: MemoryGitHubCredentialVault(token: "gho_cached"),
                                            authorizer: FakeGitHubAuthorizer(),
                                            contributions: contributions,
                                            cacheURL: cacheURL)

        await store.boot(now: now)

        XCTAssertEqual(store.phase, .connected)
        XCTAssertEqual(store.snapshot?.username, "octocat")
        XCTAssertEqual(store.snapshot?.fetchedAt, snap.fetchedAt)
        let fetches = await contributions.fetchCount
        XCTAssertEqual(fetches, 0)
    }

    @MainActor
    func testParameterlessBootPublishesCacheBeforeBackgroundRefreshSettles() async throws {
        let cached = sample(fetchedAt: now.addingTimeInterval(-7200))
        try write(cached)
        let fresh = sample(username: "updated", fetchedAt: now)
        let contributions = FakeGitHubContributions(result: .success(fresh))
        await contributions.setDelay()
        let store = GitHubContributionStore(vault: MemoryGitHubCredentialVault(token: "gho_cached"),
                                            authorizer: FakeGitHubAuthorizer(),
                                            contributions: contributions,
                                            cacheURL: cacheURL)

        await store.boot()

        XCTAssertEqual(store.snapshot, cached)
        for _ in 0..<100 where await contributions.fetchCount == 0 {
            await Task.yield()
        }
        let fetches = await contributions.fetchCount
        XCTAssertEqual(fetches, 1)

        await store.refresh(now: now)
        XCTAssertEqual(store.snapshot, fresh)
    }

    @MainActor
    func testStaleCacheRefreshesAfterOneHour() async throws {
        try write(sample(fetchedAt: now.addingTimeInterval(-3601)))
        let fresh = sample(username: "octocat", fetchedAt: now)
        let contributions = FakeGitHubContributions(result: .success(fresh))
        let store = GitHubContributionStore(vault: MemoryGitHubCredentialVault(token: "gho_cached"),
                                            authorizer: FakeGitHubAuthorizer(),
                                            contributions: contributions,
                                            cacheURL: cacheURL)

        await store.boot(now: now)

        XCTAssertEqual(store.snapshot?.fetchedAt, now)
        let fetches = await contributions.fetchCount
        XCTAssertEqual(fetches, 1)
    }

    @MainActor
    func testConnectRequestsThenPollsThenFetchesThenSaves() async throws {
        let authorizer = FakeGitHubAuthorizer()
        let contributions = FakeGitHubContributions(result: .success(sample(fetchedAt: now)))
        let vault = MemoryGitHubCredentialVault()
        let store = GitHubContributionStore(vault: vault,
                                            authorizer: authorizer,
                                            contributions: contributions,
                                            cacheURL: cacheURL)

        await store.connect()

        XCTAssertEqual(store.phase, .connected)
        XCTAssertEqual(store.snapshot?.username, "octocat")
        XCTAssertEqual(try vault.read(), "gho_live")
        XCTAssertNotNil(try? Data(contentsOf: cacheURL))
        let authEvents = await authorizer.events
        let fetchEvents = await contributions.events
        XCTAssertEqual(authEvents + fetchEvents, ["request", "poll", "fetch"])
    }

    @MainActor
    func testPollNetworkCancellationKeepsLoginForForegroundResume() async throws {
        let authorizer = FakeGitHubAuthorizer()
        await authorizer.setTokenResult(.failure(URLError(.cancelled)))
        let store = GitHubContributionStore(vault: MemoryGitHubCredentialVault(),
                                            authorizer: authorizer,
                                            contributions: FakeGitHubContributions(result: .success(sample(fetchedAt: now))),
                                            cacheURL: cacheURL)

        await store.connect()

        XCTAssertEqual(store.phase, .connecting)
        XCTAssertEqual(store.deviceCode?.userCode, "WXYZ-9876")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL
            .deletingLastPathComponent()
            .appendingPathComponent("github-device-login.json").path))

        await authorizer.setTokenResult(.success("gho_live"))
        await store.resumeOrRefresh(now: now)

        XCTAssertEqual(store.phase, .connected)
        XCTAssertEqual(store.snapshot?.username, "octocat")
        XCTAssertNil(store.deviceCode)
    }

    @MainActor
    func testRefreshDoesNotResetAnInProgressDeviceLogin() async throws {
        let authorizer = BlockingGitHubAuthorizer()
        let store = GitHubContributionStore(vault: MemoryGitHubCredentialVault(),
                                            authorizer: authorizer,
                                            contributions: FakeGitHubContributions(result: .success(sample(fetchedAt: now))),
                                            cacheURL: cacheURL)

        let connection = Task { await store.connect() }
        for _ in 0..<100 where !(await authorizer.didStartPolling) {
            await Task.yield()
        }

        let pollingStarted = await authorizer.didStartPolling
        XCTAssertTrue(pollingStarted)
        XCTAssertEqual(store.phase, .connecting)
        XCTAssertEqual(store.deviceCode?.userCode, "WXYZ-9876")

        await store.refresh(now: now)

        XCTAssertEqual(store.phase, .connecting)
        XCTAssertEqual(store.deviceCode?.userCode, "WXYZ-9876")

        await authorizer.releasePolling()
        await connection.value
    }

    @MainActor
    func testCancellingCallerAfterCodeIsShownKeepsDeviceLoginPolling() async throws {
        let authorizer = BlockingGitHubAuthorizer()
        let store = GitHubContributionStore(vault: MemoryGitHubCredentialVault(),
                                            authorizer: authorizer,
                                            contributions: FakeGitHubContributions(result: .success(sample(fetchedAt: now))),
                                            cacheURL: cacheURL)

        let connection = Task { await store.connect() }
        for _ in 0..<100 where !(await authorizer.didStartPolling) {
            await Task.yield()
        }

        let pollingStarted = await authorizer.didStartPolling
        XCTAssertTrue(pollingStarted)
        XCTAssertEqual(store.phase, .connecting)

        connection.cancel()
        await Task.yield()
        await authorizer.releasePolling()
        await connection.value

        XCTAssertEqual(store.phase, .connected)
        XCTAssertNil(store.deviceCode)
    }

    @MainActor
    func testBootRestoresAndResumesDeviceLoginAfterThePollingTaskIsCancelled() async throws {
        let authorizer = CancellableGitHubAuthorizer()
        let first = GitHubContributionStore(vault: MemoryGitHubCredentialVault(),
                                             authorizer: authorizer,
                                             contributions: FakeGitHubContributions(result: .success(sample(fetchedAt: now))),
                                             cacheURL: cacheURL)
        let connection = Task { await first.connect() }
        for _ in 0..<100 where !(first.deviceCode?.userCode == "WXYZ-9876") {
            await Task.yield()
        }

        XCTAssertEqual(first.phase, .connecting)
        XCTAssertEqual(first.deviceCode?.userCode, "WXYZ-9876")

        connection.cancel()
        await authorizer.cancelPolling()
        await connection.value
        XCTAssertEqual(first.phase, .connecting)
        XCTAssertEqual(first.deviceCode?.userCode, "WXYZ-9876")

        let second = GitHubContributionStore(vault: MemoryGitHubCredentialVault(),
                                             authorizer: FakeGitHubAuthorizer(),
                                             contributions: FakeGitHubContributions(result: .success(sample(fetchedAt: now))),
                                             cacheURL: cacheURL)
        await second.boot(now: now.addingTimeInterval(1))

        XCTAssertEqual(second.phase, .connected)
        XCTAssertEqual(second.snapshot?.username, "octocat")
        XCTAssertNil(second.deviceCode)
    }

    @MainActor
    func testActiveResumeReloadsPendingLoginAfterStoreWasRecreated() async throws {
        let authorizer = CancellableGitHubAuthorizer()
        let first = GitHubContributionStore(vault: MemoryGitHubCredentialVault(),
                                             authorizer: authorizer,
                                             contributions: FakeGitHubContributions(result: .success(sample(fetchedAt: now))),
                                             cacheURL: cacheURL)
        let connection = Task { await first.connect() }
        for _ in 0..<100 where first.deviceCode == nil {
            await Task.yield()
        }

        XCTAssertEqual(first.phase, .connecting)
        XCTAssertNotNil(first.deviceCode)
        connection.cancel()
        await authorizer.cancelPolling()
        await connection.value

        let second = GitHubContributionStore(vault: MemoryGitHubCredentialVault(),
                                              authorizer: FakeGitHubAuthorizer(),
                                              contributions: FakeGitHubContributions(result: .success(sample(fetchedAt: now))),
                                              cacheURL: cacheURL)
        await second.resumePendingLogin()

        XCTAssertEqual(second.phase, .connected)
        XCTAssertEqual(second.snapshot?.username, "octocat")
        XCTAssertNil(second.deviceCode)
    }

    @MainActor
    func testRefreshResumesPersistedLoginInsteadOfDisconnecting() async throws {
        let firstAuthorizer = BlockingGitHubAuthorizer()
        let first = GitHubContributionStore(vault: MemoryGitHubCredentialVault(),
                                             authorizer: firstAuthorizer,
                                             contributions: FakeGitHubContributions(result: .success(sample(fetchedAt: now))),
                                             cacheURL: cacheURL)
        let connection = Task { await first.connect() }
        for _ in 0..<100 where !(await firstAuthorizer.didStartPolling) {
            await Task.yield()
        }

        let second = GitHubContributionStore(vault: MemoryGitHubCredentialVault(),
                                              authorizer: FakeGitHubAuthorizer(),
                                              contributions: FakeGitHubContributions(result: .success(sample(fetchedAt: now))),
                                              cacheURL: cacheURL)
        await second.refresh(now: .now)

        XCTAssertEqual(second.phase, .connected)
        XCTAssertEqual(second.snapshot?.username, "octocat")
        await firstAuthorizer.releasePolling()
        await connection.value
    }

    @MainActor
    func testForegroundRefreshRetriesAfterAnInFlightPollIsCancelled() async throws {
        let authorizer = RestartableGitHubAuthorizer()
        let contributions = FakeGitHubContributions(result: .success(sample(fetchedAt: now)))
        let store = GitHubContributionStore(vault: MemoryGitHubCredentialVault(),
                                            authorizer: authorizer,
                                            contributions: contributions,
                                            cacheURL: cacheURL)

        let connection = Task { await store.connect() }
        var pollCount = await authorizer.pollCount
        for _ in 0..<100 where pollCount == 0 {
            await Task.yield()
            pollCount = await authorizer.pollCount
        }

        let foreground = Task { @MainActor in
            await store.refresh(now: now)
        }
        await Task.yield()
        await authorizer.cancelFirstPollNow()

        await connection.value
        await foreground.value

        let polls = await authorizer.pollCount
        XCTAssertEqual(polls, 2)
        XCTAssertEqual(store.phase, .connected)
        XCTAssertEqual(store.snapshot?.username, "octocat")
    }

    @MainActor
    func testAuthorizationFailureLeavesNoToken() async throws {
        let contributions = FakeGitHubContributions(result: .failure(GitHubContributionsError.httpStatus(503)))
        let vault = MemoryGitHubCredentialVault()
        let authorizer = FakeGitHubAuthorizer()
        await authorizer.setRequestError(GitHubDeviceFlowError.denied)
        let store = GitHubContributionStore(vault: vault,
                                            authorizer: authorizer,
                                            contributions: contributions,
                                            cacheURL: cacheURL)

        await store.connect()

        XCTAssertNil(try vault.read())
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        if case .failed = store.phase {
        } else {
            XCTFail("expected failed phase, got \(store.phase)")
        }
    }

    @MainActor
    func testAuthorizedTokenSurvivesAContributionFetchFailure() async throws {
        let contributions = FakeGitHubContributions(result: .failure(GitHubContributionsError.httpStatus(503)))
        let vault = MemoryGitHubCredentialVault()
        let store = GitHubContributionStore(vault: vault,
                                            authorizer: FakeGitHubAuthorizer(),
                                            contributions: contributions,
                                            cacheURL: cacheURL)

        await store.connect()

        XCTAssertEqual(try vault.read(), "gho_live")
        if case .failed = store.phase {
        } else {
            XCTFail("expected failed phase, got \(store.phase)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    @MainActor
    func testCachedNetworkFailureKeepsTheCard() async throws {
        let cached = sample(fetchedAt: now.addingTimeInterval(-7200))
        try write(cached)
        let contributions = FakeGitHubContributions(result: .failure(GitHubContributionsError.httpStatus(503)))
        let vault = MemoryGitHubCredentialVault(token: "gho_cached")
        let store = GitHubContributionStore(vault: vault,
                                            authorizer: FakeGitHubAuthorizer(),
                                            contributions: contributions,
                                            cacheURL: cacheURL)

        await store.boot(now: now)

        XCTAssertEqual(store.phase, .connected)
        XCTAssertEqual(store.snapshot, cached)
        XCTAssertEqual(try vault.read(), "gho_cached")
    }

    @MainActor
    func testUnauthorizedRefreshRequestsLoginAndKeepsCachedCard() async throws {
        let cached = sample(fetchedAt: now.addingTimeInterval(-7200))
        try write(cached)
        let contributions = FakeGitHubContributions(result: .failure(GitHubContributionsError.unauthorized))
        let vault = MemoryGitHubCredentialVault(token: "gho_dead")
        let store = GitHubContributionStore(vault: vault,
                                            authorizer: FakeGitHubAuthorizer(),
                                            contributions: contributions,
                                            cacheURL: cacheURL)

        await store.boot(now: now)

        XCTAssertEqual(store.phase, .connected)
        XCTAssertEqual(store.snapshot, cached)
        XCTAssertEqual(try vault.read(), "gho_dead")
        XCTAssertEqual(store.refreshFeedback, .reauthenticationRequired)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    @MainActor
    func testReauthenticationClearsOnlyTheInvalidCredential() async throws {
        let cached = sample(fetchedAt: now.addingTimeInterval(-7200))
        try write(cached)
        let vault = MemoryGitHubCredentialVault(token: "gho_dead")
        let store = GitHubContributionStore(vault: vault,
                                            authorizer: FakeGitHubAuthorizer(),
                                            contributions: FakeGitHubContributions(
                                                result: .failure(GitHubContributionsError.unauthorized)),
                                            cacheURL: cacheURL)
        await store.boot(now: now)

        store.prepareForReauthentication()

        XCTAssertNil(try vault.read())
        XCTAssertEqual(store.snapshot, cached)
        XCTAssertEqual(store.refreshFeedback, .none)
        XCTAssertEqual(store.phase, .disconnected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    @MainActor
    func testMissingCredentialKeepsCachedCardDuringAutomaticRefresh() async throws {
        let cached = sample(fetchedAt: now.addingTimeInterval(-7200))
        try write(cached)
        let vault = MemoryGitHubCredentialVault()
        let store = GitHubContributionStore(vault: vault,
                                             authorizer: FakeGitHubAuthorizer(),
                                             contributions: FakeGitHubContributions(
                                                result: .success(sample(fetchedAt: now))),
                                             cacheURL: cacheURL)

        await store.boot(now: now)

        XCTAssertEqual(store.phase, .connected)
        XCTAssertEqual(store.snapshot, cached)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    @MainActor
    func testForcedResumeRefreshesEvenWhenCacheIsFresh() async throws {
        try write(sample(fetchedAt: now.addingTimeInterval(-60)))
        let contributions = FakeGitHubContributions(result: .success(sample(fetchedAt: now)))
        let store = GitHubContributionStore(vault: MemoryGitHubCredentialVault(token: "gho_cached"),
                                            authorizer: FakeGitHubAuthorizer(),
                                            contributions: contributions,
                                            cacheURL: cacheURL)

        await store.boot(now: now)
        let initialFetches = await contributions.fetchCount
        XCTAssertEqual(initialFetches, 0)

        await store.resumeOrRefresh(now: now, forced: true)

        let refreshedFetches = await contributions.fetchCount
        XCTAssertEqual(refreshedFetches, 1)
        XCTAssertEqual(store.snapshot?.fetchedAt, now)
    }

    @MainActor
    func testConcurrentRefreshCoalescesIntoOneFetch() async throws {
        try write(sample(fetchedAt: now.addingTimeInterval(-7200)))
        let contributions = FakeGitHubContributions(result: .success(sample(fetchedAt: now)))
        await contributions.setDelay()
        let store = GitHubContributionStore(vault: MemoryGitHubCredentialVault(token: "gho_cached"),
                                            authorizer: FakeGitHubAuthorizer(),
                                            contributions: contributions,
                                            cacheURL: cacheURL)

        async let first: Void = store.refresh(now: now, forced: true)
        async let second: Void = store.refresh(now: now, forced: true)
        _ = await (first, second)

        let fetches = await contributions.fetchCount
        XCTAssertEqual(fetches, 1)
    }

    @MainActor
    func testForcedRefreshPublishesSuccessAndClearsLoading() async throws {
        try write(sample(fetchedAt: now.addingTimeInterval(-7200)))
        let fetcher = FakeGitHubContributions(result: .success(sample(fetchedAt: now)))
        await fetcher.setDelay()
        let store = GitHubContributionStore(vault: MemoryGitHubCredentialVault(token: "gho_cached"),
                                            authorizer: FakeGitHubAuthorizer(),
                                            contributions: fetcher,
                                            cacheURL: cacheURL)

        let refresh = Task { await store.refresh(now: now, forced: true) }
        while !store.isRefreshing { await Task.yield() }
        XCTAssertTrue(store.isRefreshing)
        await refresh.value

        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(store.refreshFeedback, .success)
        XCTAssertGreaterThan(store.refreshAnimationToken, 0)
    }

    @MainActor
    func testRefreshFailureKeepsCachedSnapshotAndPublishesFailure() async throws {
        let cached = sample(fetchedAt: now.addingTimeInterval(-7200))
        try write(cached)
        let fetcher = FakeGitHubContributions(result: .failure(URLError(.notConnectedToInternet)))
        let store = GitHubContributionStore(vault: MemoryGitHubCredentialVault(token: "gho_cached"),
                                            authorizer: FakeGitHubAuthorizer(),
                                            contributions: fetcher,
                                            cacheURL: cacheURL)

        await store.boot(now: now)

        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(store.snapshot, cached)
        if case .failure(let message) = store.refreshFeedback {
            XCTAssertFalse(message.isEmpty)
        } else {
            XCTFail("expected refresh failure feedback")
        }
    }

    @MainActor
    func testDisconnectDeletesTokenCacheAndCard() async throws {
        try write(sample(fetchedAt: now))
        let vault = MemoryGitHubCredentialVault(token: "gho_live")
        let store = GitHubContributionStore(vault: vault,
                                            authorizer: FakeGitHubAuthorizer(),
                                            contributions: FakeGitHubContributions(result: .success(sample(fetchedAt: now))),
                                            cacheURL: cacheURL)
        await store.boot(now: now)
        XCTAssertNotNil(store.snapshot)

        store.disconnect()

        XCTAssertEqual(store.phase, .disconnected)
        XCTAssertNil(store.snapshot)
        XCTAssertNil(store.deviceCode)
        XCTAssertNil(try vault.read())
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    @MainActor
    func testDisconnectWinsAgainstCancellationInsensitiveRefresh() async throws {
        try write(sample(fetchedAt: now.addingTimeInterval(-7200)))
        let contributions = FakeGitHubContributions(result: .success(sample(username: "late", fetchedAt: now)))
        await contributions.setCancellationInsensitiveDelay()
        let vault = MemoryGitHubCredentialVault(token: "gho_live")
        let store = GitHubContributionStore(vault: vault,
                                            authorizer: FakeGitHubAuthorizer(),
                                            contributions: contributions,
                                            cacheURL: cacheURL)

        let refresh = Task { await store.refresh(now: now, forced: true) }
        while await contributions.fetchCount == 0 { await Task.yield() }
        store.disconnect()
        await refresh.value

        XCTAssertEqual(store.phase, .disconnected)
        XCTAssertNil(store.snapshot)
        XCTAssertNil(try vault.read())
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    @MainActor
    func testDisconnectFailureDoesNotReportSuccessOrHideTheCard() async throws {
        try write(sample(fetchedAt: now))
        let vault = MemoryGitHubCredentialVault(token: "gho_live")
        let store = GitHubContributionStore(vault: vault,
                                            authorizer: FakeGitHubAuthorizer(),
                                            contributions: FakeGitHubContributions(result: .success(sample(fetchedAt: now))),
                                            cacheURL: cacheURL)
        await store.boot(now: now)
        vault.failDeletes(with: GitHubCredentialError.keychain(errSecInteractionNotAllowed))

        store.disconnect()

        if case .failed = store.phase {
        } else {
            XCTFail("failed deletion must not be presented as disconnected")
        }
        XCTAssertNotNil(store.snapshot)
        XCTAssertEqual(try vault.read(), "gho_live")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    @MainActor
    func testBootKeepsCachedCardWhenCredentialIsMissing() async throws {
        try write(sample(fetchedAt: now))
        let store = GitHubContributionStore(vault: MemoryGitHubCredentialVault(),
                                            authorizer: FakeGitHubAuthorizer(),
                                            contributions: FakeGitHubContributions(result: .success(sample(fetchedAt: now))),
                                            cacheURL: cacheURL)

        await store.boot(now: now)

        XCTAssertEqual(store.phase, .connected)
        XCTAssertNotNil(store.snapshot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    func testDemoFixtureIsDeterministicAndDebugOnly() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Models/GitHubContributionStore.swift"))
        XCTAssertTrue(source.contains("-demo-github-card"))
        XCTAssertTrue(source.contains("#if DEBUG"))
        let demoIndex = try XCTUnwrap(source.range(of: "-demo-github-card"))
        let debugIndex = try XCTUnwrap(source.range(of: "#if DEBUG"))
        XCTAssertLessThan(debugIndex.lowerBound, demoIndex.lowerBound)
        XCTAssertFalse(source.contains("repo"))

        #if DEBUG
        let snap = GitHubContributionStore.demoSnapshot(now: now)
        XCTAssertEqual(snap.username, "enrzh")
        XCTAssertEqual(snap.days.count, 371)
        XCTAssertEqual(GitHubContributionStore.demoSnapshot(now: now), snap)
        XCTAssertEqual(snap.profileURL?.absoluteString, "https://github.com/enrzh")
        #endif
    }

    @MainActor
    func testCacheIsNotHabitData() throws {
        XCTAssertFalse(GitHubContributionStore.defaultCacheURL.lastPathComponent.contains("data.json"))
        XCTAssertEqual(cacheURL.lastPathComponent, "github-contributions.json")
    }

    private func sample(username: String = "octocat", fetchedAt: Date) -> GitHubContributionSnapshot {
        GitHubContributionSnapshot(username: username,
                                   days: [GitHubContributionDay(date: "2026-08-16", count: 2, level: 1)],
                                   fetchedAt: fetchedAt)
    }

    private func write(_ snapshot: GitHubContributionSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: cacheURL, options: .atomic)
    }
}

private extension FakeGitHubContributions {
    func setDelay() {
        delayNanoseconds = 80_000_000
    }

    func setCancellationInsensitiveDelay() {
        delayNanoseconds = 80_000_000
        ignoresCancellation = true
    }
}
