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
}

actor FakeGitHubContributions: GitHubContributionsFetching {
    var events: [String] = []
    var delayNanoseconds: UInt64 = 0
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
            try await Task.sleep(nanoseconds: delayNanoseconds)
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
    func testFailedFirstFetchLeavesNoToken() async throws {
        let contributions = FakeGitHubContributions(result: .failure(GitHubContributionsError.httpStatus(503)))
        let vault = MemoryGitHubCredentialVault()
        let store = GitHubContributionStore(vault: vault,
                                            authorizer: FakeGitHubAuthorizer(),
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
    func testUnauthorizedRefreshDeletesCredentialsAndCache() async throws {
        try write(sample(fetchedAt: now.addingTimeInterval(-7200)))
        let contributions = FakeGitHubContributions(result: .failure(GitHubContributionsError.unauthorized))
        let vault = MemoryGitHubCredentialVault(token: "gho_dead")
        let store = GitHubContributionStore(vault: vault,
                                            authorizer: FakeGitHubAuthorizer(),
                                            contributions: contributions,
                                            cacheURL: cacheURL)

        await store.boot(now: now)

        XCTAssertEqual(store.phase, .disconnected)
        XCTAssertNil(store.snapshot)
        XCTAssertNil(try vault.read())
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
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
}
