import XCTest
@testable import Haiity

/// Stub-Transport: bildet die GitHub-API deterministisch nach, kein Netz.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    struct Call {
        let method: String
        let path: String
        let body: [String: Any]?
        /// Voller URL — der Device Flow spricht github.com, nicht api.github.com.
        let url: URL
    }
    private(set) var calls: [Call] = []
    var responses: [(Int, Any)] = []
    private let lock = NSLock()

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock(); defer { lock.unlock() }
        let body = request.httpBody.flatMap(Self.decodeBody)
        calls.append(Call(method: request.httpMethod ?? "GET",
                          path: request.url!.path,
                          body: body,
                          url: request.url!))
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        let (status, payload) = responses.removeFirst()
        let data = try JSONSerialization.data(withJSONObject: payload)
        let res = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, res)
    }

    /// JSON (Contents-API) ODER form-encoded (Device Flow) — beides landet
    /// als Dictionary in `calls`, damit Tests Felder prüfen können.
    private static func decodeBody(_ data: Data) -> [String: Any]? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return obj }
        guard let raw = String(data: data, encoding: .utf8), raw.contains("=") else { return nil }
        var out: [String: Any] = [:]
        for pair in raw.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let key = String(kv[0]).removingPercentEncoding ?? String(kv[0])
            out[key] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
        }
        return out.isEmpty ? nil : out
    }
}

/// In-Memory-Vault: unsignierte Test-Hosts dürfen nicht in den Keychain.
final class InMemoryVault: TokenVault, @unchecked Sendable {
    private var value: String?
    func get() -> String? { value }
    func set(_ v: String) { value = v }
    func delete() { value = nil }
}

final class GitHubSyncTests: XCTestCase {
    var vault: InMemoryVault!

    override func setUp() {
        vault = InMemoryVault()
        UserDefaults.standard.removeObject(forKey: "github-login")
    }
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "github-login")
    }

    private func b64(_ data: HabitData) -> String {
        try! JSONEncoder().encode(data).base64EncodedString()
    }

    func testConnectValidatesAndKeepsExistingRepo() async throws {
        let t = StubTransport()
        t.responses = [
            (200, ["login": "enrzh"]),           // /user
            (200, ["name": "haiity-data"]),      // repo existiert
        ]
        let sync = GitHubSync(transport: t, vault: vault)
        let login = try await sync.connect(token: "tok")
        XCTAssertEqual(login, "enrzh")
        XCTAssertEqual(vault.get(), "tok")
        XCTAssertEqual(t.calls.map(\.path), ["/user", "/repos/enrzh/haiity-data"])
    }

    func testConnectCreatesMissingRepo() async throws {
        let t = StubTransport()
        t.responses = [
            (200, ["login": "enrzh"]),
            (404, [:]),                          // repo fehlt
            (201, ["name": "haiity-data"]),      // angelegt
        ]
        let sync = GitHubSync(transport: t, vault: vault)
        _ = try await sync.connect(token: "tok")
        XCTAssertEqual(t.calls.last?.method, "POST")
        XCTAssertEqual(t.calls.last?.path, "/user/repos")
        XCTAssertEqual(t.calls.last?.body?["private"] as? Bool, true)
    }

    func testConnectRejectsBadToken() async {
        let t = StubTransport()
        t.responses = [(401, [:])]
        let sync = GitHubSync(transport: t, vault: vault)
        do {
            _ = try await sync.connect(token: "schlecht")
            XCTFail("sollte werfen")
        } catch let e as SyncError {
            XCTAssertEqual(e, .badToken(401))
        } catch { XCTFail("falscher Fehler: \(error)") }
        XCTAssertNil(vault.get())
    }

    func testPullReturnsNilWhenNoFile() async throws {
        let t = StubTransport()
        t.responses = [
            (200, ["login": "enrzh"]),
            (200, ["name": "haiity-data"]),
            (404, [:]),
        ]
        let sync = GitHubSync(transport: t, vault: vault)
        _ = try await sync.connect(token: "tok")
        let remote = try await sync.pull()
        XCTAssertNil(remote)
    }

    func testPullDecodesRemoteData() async throws {
        var habit = Habit(name: "Remote")
        habit.log["2026-08-01"] = 1
        let remoteData = HabitData(version: 1, updatedAt: 5, summaryMinutes: nil, habits: [habit])
        let t = StubTransport()
        t.responses = [
            (200, ["login": "enrzh"]),
            (200, ["name": "haiity-data"]),
            (200, ["sha": "abc", "content": b64(remoteData)]),
        ]
        let sync = GitHubSync(transport: t, vault: vault)
        _ = try await sync.connect(token: "tok")
        let pulled = try await sync.pull()
        XCTAssertEqual(pulled?.habits.first?.name, "Remote")
    }

    func testPushSendsShaAndCommitMessage() async throws {
        let t = StubTransport()
        t.responses = [
            (200, ["login": "enrzh"]),
            (200, ["name": "haiity-data"]),
            (200, ["sha": "abc", "content": b64(.empty)]),          // pull
            (200, ["content": ["sha": "def"]]),                      // put
        ]
        let sync = GitHubSync(transport: t, vault: vault)
        _ = try await sync.connect(token: "tok")
        _ = try await sync.pull()
        try await sync.push(Data("{}".utf8)) { _ in Data("{}".utf8) }
        let put = t.calls.last!
        XCTAssertEqual(put.method, "PUT")
        XCTAssertEqual(put.body?["sha"] as? String, "abc")
        XCTAssertTrue((put.body?["message"] as? String ?? "").hasPrefix("habits: "))
    }

    func testPushRetriesOnceOnShaConflict() async throws {
        var remoteHabit = Habit(name: "Anderswo")
        remoteHabit.log["2026-08-05"] = 1
        let remoteData = HabitData(version: 1, updatedAt: 9, summaryMinutes: nil, habits: [remoteHabit])
        let t = StubTransport()
        t.responses = [
            (200, ["login": "enrzh"]),
            (200, ["name": "haiity-data"]),
            (409, [:]),                                              // 1. PUT: Konflikt
            (200, ["sha": "neu", "content": b64(remoteData)]),       // pull
            (200, ["content": ["sha": "final"]]),                    // 2. PUT ok
        ]
        let sync = GitHubSync(transport: t, vault: vault)
        _ = try await sync.connect(token: "tok")

        var mergeSawRemote = false
        try await sync.push(Data("{}".utf8)) { remote in
            mergeSawRemote = remote?.habits.first?.name == "Anderswo"
            return Data("{\"merged\":true}".utf8)
        }
        XCTAssertTrue(mergeSawRemote)
        let secondPut = t.calls.last!
        XCTAssertEqual(secondPut.method, "PUT")
        XCTAssertEqual(secondPut.body?["sha"] as? String, "neu")
    }

    func testPushSurfacesTerminalFailure() async throws {
        let t = StubTransport()
        t.responses = [
            (200, ["login": "enrzh"]),
            (200, ["name": "haiity-data"]),
            (403, [:]),
        ]
        let sync = GitHubSync(transport: t, vault: vault)
        _ = try await sync.connect(token: "tok")
        do {
            try await sync.push(Data("{}".utf8)) { _ in Data() }
            XCTFail("sollte werfen")
        } catch let e as SyncError {
            XCTAssertEqual(e, .pushFailed(403))
        }
    }
}
