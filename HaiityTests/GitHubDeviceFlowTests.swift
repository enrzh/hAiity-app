import XCTest
@testable import Haiity

/// Fake-Uhr für den Device Flow: nichts schläft wirklich, aber jede
/// Wartezeit wird protokolliert — nur so ist prüfbar, dass `slow_down`
/// den Abstand tatsächlich VERGRÖSSERT und dass `expires_in` greift.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_700_000_000)
    private var slept: [Duration] = []
    /// Haken nach jedem „Schlafen" (Argument: wievieltes Mal) — Tests
    /// hängen hier z. B. ein `cancel()` ein.
    var onSleep: (@Sendable (Int) -> Void)?

    var seconds: [Int] { lock.withLock { slept.map { Int($0.components.seconds) } } }

    var clock: DeviceFlowClock {
        DeviceFlowClock(
            now: { [self] in lock.withLock { current } },
            sleep: { [self] duration in
                let n: Int = lock.withLock {
                    slept.append(duration)
                    current = current.addingTimeInterval(TimeInterval(duration.components.seconds))
                    return slept.count
                }
                onSleep?(n)
            })
    }
}

final class GitHubDeviceFlowTests: XCTestCase {
    private let clientId = "Iv23liTESTID"
    var vault: InMemoryVault!

    override func setUp() {
        vault = InMemoryVault()
        UserDefaults.standard.removeObject(forKey: "github-login")
    }
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "github-login")
    }

    private func makeFlow(_ t: StubTransport,
                          clock: TestClock = TestClock(),
                          configured: Bool = true) -> GitHubDeviceFlow {
        GitHubDeviceFlow(sync: GitHubSync(transport: t, vault: vault),
                         transport: t,
                         clientId: clientId,
                         configured: configured,
                         clock: clock.clock)
    }

    private var sampleCode: DeviceCode {
        DeviceCode(deviceCode: "dc-1",
                   userCode: "WDJB-MJHT",
                   verificationURI: "https://github.com/login/device",
                   expiresIn: 900,
                   interval: 5)
    }

    // MARK: – Schritt 1

    func testRequestsDeviceCodeAndParsesResponse() async throws {
        let t = StubTransport()
        t.responses = [(200, [
            "device_code": "dc-1",
            "user_code": "WDJB-MJHT",
            "verification_uri": "https://github.com/login/device",
            "expires_in": 899,
            "interval": 7,
        ])]
        let code = try await makeFlow(t).requestCode()

        XCTAssertEqual(code.deviceCode, "dc-1")
        XCTAssertEqual(code.userCode, "WDJB-MJHT")
        XCTAssertEqual(code.verificationURL?.absoluteString, "https://github.com/login/device")
        XCTAssertEqual(code.expiresIn, 899)
        XCTAssertEqual(code.interval, 7)

        let call = try XCTUnwrap(t.calls.first)
        XCTAssertEqual(call.method, "POST")
        XCTAssertEqual(call.url.absoluteString, "https://github.com/login/device/code")
        XCTAssertEqual(call.body?["client_id"] as? String, clientId)
        // scope ist der OAuth-App-Fallback; GitHub Apps ignorieren ihn.
        XCTAssertEqual(call.body?["scope"] as? String, "repo")
    }

    func testDeviceCodeRequestSurfacesGitHubError() async {
        let t = StubTransport()
        t.responses = [(200, ["error": "device_flow_disabled"])]
        do {
            _ = try await makeFlow(t).requestCode()
            XCTFail("sollte werfen")
        } catch let e as DeviceFlowError {
            XCTAssertEqual(e, .rejected("device_flow_disabled"))
            XCTAssertTrue(e.errorDescription?.contains("device_flow_disabled") == true)
        } catch { XCTFail("falscher Fehler: \(error)") }
    }

    // MARK: – Schritt 2: Polling

    func testPollingKeepsGoingWhileAuthorizationPending() async throws {
        let t = StubTransport()
        t.responses = [
            (200, ["error": "authorization_pending"]),
            (200, ["error": "authorization_pending"]),
            (200, ["access_token": "gho_abc", "token_type": "bearer"]),
        ]
        let clock = TestClock()
        let token = try await makeFlow(t, clock: clock).pollForToken(sampleCode)

        XCTAssertEqual(token, "gho_abc")
        XCTAssertEqual(t.calls.count, 3)
        XCTAssertEqual(clock.seconds, [5, 5, 5])
        let poll = try XCTUnwrap(t.calls.first)
        XCTAssertEqual(poll.url.absoluteString, "https://github.com/login/oauth/access_token")
        XCTAssertEqual(poll.body?["device_code"] as? String, "dc-1")
        XCTAssertEqual(poll.body?["grant_type"] as? String,
                       "urn:ietf:params:oauth:grant-type:device_code")
    }

    func testSlowDownIncreasesTheInterval() async throws {
        let t = StubTransport()
        t.responses = [
            (200, ["error": "authorization_pending"]),
            (200, ["error": "slow_down", "interval": 10]),  // GitHub nennt den neuen Takt
            (200, ["error": "slow_down"]),                  // ohne Angabe: +5 s
            (200, ["access_token": "gho_slow"]),
        ]
        let clock = TestClock()
        let token = try await makeFlow(t, clock: clock).pollForToken(sampleCode)

        XCTAssertEqual(token, "gho_slow")
        XCTAssertEqual(clock.seconds, [5, 5, 10, 15])
        // Kernaussage: nach jedem slow_down ist der Abstand größer.
        XCTAssertGreaterThan(clock.seconds[2], clock.seconds[1])
        XCTAssertGreaterThan(clock.seconds[3], clock.seconds[2])
    }

    func testExpiredTokenAsksForARestart() async {
        let t = StubTransport()
        t.responses = [(200, ["error": "expired_token"])]
        do {
            _ = try await makeFlow(t).pollForToken(sampleCode)
            XCTFail("sollte werfen")
        } catch let e as DeviceFlowError {
            XCTAssertEqual(e, .expired)
            XCTAssertEqual(e.errorDescription, "Code abgelaufen, neu starten.")
        } catch { XCTFail("falscher Fehler: \(error)") }
    }

    func testAccessDeniedMeansUserCancelled() async {
        let t = StubTransport()
        t.responses = [(200, ["error": "access_denied"])]
        do {
            _ = try await makeFlow(t).pollForToken(sampleCode)
            XCTFail("sollte werfen")
        } catch let e as DeviceFlowError {
            XCTAssertEqual(e, .denied)
            XCTAssertTrue(e.errorDescription?.contains("abgelehnt") == true)
        } catch { XCTFail("falscher Fehler: \(error)") }
    }

    func testHardErrorsAreNotRetried() async {
        for code in ["incorrect_device_code", "unsupported_grant_type"] {
            let t = StubTransport()
            t.responses = [(400, ["error": code]), (200, ["access_token": "nie"])]
            do {
                _ = try await makeFlow(t).pollForToken(sampleCode)
                XCTFail("sollte werfen (\(code))")
            } catch let e as DeviceFlowError {
                XCTAssertEqual(e, .rejected(code))
                XCTAssertEqual(t.calls.count, 1, "nach hartem Fehler darf nicht weitergepollt werden")
            } catch { XCTFail("falscher Fehler: \(error)") }
        }
    }

    func testDeadlineFromExpiresInStopsPolling() async {
        let t = StubTransport()
        t.responses = Array(repeating: (200, ["error": "authorization_pending"] as Any), count: 10)
        let clock = TestClock()
        // 12 s Gültigkeit bei 5 s Takt: nach zwei Polls ist Schluss.
        let short = DeviceCode(deviceCode: "dc-1", userCode: "WDJB-MJHT",
                               verificationURI: "https://github.com/login/device",
                               expiresIn: 12, interval: 5)
        do {
            _ = try await makeFlow(t, clock: clock).pollForToken(short)
            XCTFail("sollte werfen")
        } catch let e as DeviceFlowError {
            XCTAssertEqual(e, .expired)
            XCTAssertEqual(t.calls.count, 2)
        } catch { XCTFail("falscher Fehler: \(error)") }
    }

    func testCancellationStopsPolling() async {
        let t = StubTransport()
        t.responses = Array(repeating: (200, ["error": "authorization_pending"] as Any), count: 20)
        let clock = TestClock()
        let flow = makeFlow(t, clock: clock)
        let box = TaskBox()
        let code = sampleCode
        // Nach dem dritten Warten bricht die „UI" ab.
        clock.onSleep = { n in if n == 3 { box.cancel() } }

        // Startschranke: die Task darf erst loslaufen, wenn sie im Box
        // hängt — sonst wäre der Abbruchzeitpunkt ein Rennen.
        let gate = Gate()
        let task = Task { () async throws -> String in
            await gate.wait()
            return try await flow.pollForToken(code)
        }
        box.hold(task)
        await gate.open()
        let result = await task.result

        switch result {
        case .success: XCTFail("sollte abgebrochen werden")
        case .failure(let error): XCTAssertTrue(error is CancellationError, "\(error)")
        }
        // Zwei Polls vor dem Abbruch — danach kein einziger mehr.
        XCTAssertEqual(t.calls.count, 2)
    }

    // MARK: – Kompletter Ablauf

    func testAuthorizeStoresTokenAndResolvesLogin() async throws {
        let t = StubTransport()
        t.responses = [
            (200, ["device_code": "dc-1", "user_code": "WDJB-MJHT",
                   "verification_uri": "https://github.com/login/device",
                   "expires_in": 900, "interval": 5]),        // Code
            (200, ["error": "authorization_pending"]),         // Nutzer tippt noch
            (200, ["access_token": "gho_final"]),              // Freigabe
            (200, ["login": "enrzh"]),                         // /user
            (404, [:]),                                        // Repo fehlt
            (201, ["name": "haiity-data"]),                    // angelegt
        ]
        let clock = TestClock()
        let sync = GitHubSync(transport: t, vault: vault)
        let flow = GitHubDeviceFlow(sync: sync, transport: t, clientId: clientId,
                                    configured: true, clock: clock.clock)

        let seen = CodeBox()
        let login = try await flow.authorize { seen.set($0) }

        XCTAssertEqual(login, "enrzh")
        XCTAssertEqual(seen.value?.userCode, "WDJB-MJHT")
        XCTAssertEqual(vault.get(), "gho_final", "Token muss im Vault landen")
        let connected = await sync.login
        XCTAssertEqual(connected, "enrzh")
        XCTAssertEqual(t.calls.map(\.path), [
            "/login/device/code",
            "/login/oauth/access_token",
            "/login/oauth/access_token",
            "/user",
            "/repos/enrzh/haiity-data",
            "/user/repos",
        ])
    }

    // MARK: – Konfiguration

    func testUnconfiguredClientIdRefusesToStart() async {
        let t = StubTransport()
        t.responses = [(200, ["device_code": "dc-1"])]
        let flow = makeFlow(t, configured: false)
        do {
            _ = try await flow.requestCode()
            XCTFail("sollte werfen")
        } catch let e as DeviceFlowError {
            XCTAssertEqual(e, .notConfigured)
        } catch { XCTFail("falscher Fehler: \(error)") }
        do {
            _ = try await flow.pollForToken(sampleCode)
            XCTFail("sollte werfen")
        } catch let e as DeviceFlowError {
            XCTAssertEqual(e, .notConfigured)
        } catch { XCTFail("falscher Fehler: \(error)") }
        XCTAssertTrue(t.calls.isEmpty, "ohne Client-ID darf kein Request rausgehen")
    }

    func testPlaceholderClientIdCountsAsUnconfigured() {
        if GitHubAppConfig.clientId == GitHubAppConfig.placeholder {
            XCTAssertFalse(GitHubAppConfig.isConfigured)
        } else {
            XCTAssertTrue(GitHubAppConfig.isConfigured)
        }
    }
}

/// Startschranke für Tests: hält eine Task an, bis der Test bereit ist.
private actor Gate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        opened = true
        for w in waiters { w.resume() }
        waiters = []
    }

    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

/// Kleiner Halter, damit die Fake-Uhr die laufende Task abbrechen kann.
private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<String, Error>?
    private var cancelled = false

    func hold(_ t: Task<String, Error>) {
        let already: Bool = lock.withLock {
            task = t
            return cancelled
        }
        if already { t.cancel() }
    }

    func cancel() {
        let t: Task<String, Error>? = lock.withLock {
            cancelled = true
            return task
        }
        t?.cancel()
    }
}

/// Fängt den Code ein, den `authorize` an die UI durchreicht.
private final class CodeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: DeviceCode?
    var value: DeviceCode? { lock.withLock { stored } }
    func set(_ c: DeviceCode) { lock.withLock { stored = c } }
}
