import Foundation
import XCTest
@testable import Haiity

actor ScriptedGitHubTransport: GitHubHTTPTransport {
    private var script: [(Data, Int)]
    private(set) var requests: [URLRequest] = []

    init(_ script: [(Data, Int)]) {
        self.script = script
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let next = script.isEmpty ? (Data(), 500) : script.removeFirst()
        let response = HTTPURLResponse(url: try XCTUnwrap(request.url),
                                       statusCode: next.1,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: [:])!
        return (next.0, response)
    }
}

actor RecordingGitHubSleeper: GitHubSleeper {
    private(set) var sleeps: [Int] = []

    func sleep(seconds: Int) async throws {
        try Task.checkCancellation()
        sleeps.append(seconds)
    }
}

final class GitHubDeviceFlowTests: XCTestCase {
    private let clientID = "public-client-id"

    func testRequestCodePostsFormWithoutScope() async throws {
        let payload = Data(#"""
        {"device_code":"dc","user_code":"ABCD-1234",
         "verification_uri":"https://github.com/login/device",
         "expires_in":900,"interval":5}
        """#.utf8)
        let transport = ScriptedGitHubTransport([(payload, 200)])
        let flow = GitHubDeviceFlow(transport: transport,
                                    sleeper: RecordingGitHubSleeper(),
                                    clientID: clientID)

        let code = try await flow.requestCode()
        XCTAssertEqual(code.deviceCode, "dc")
        XCTAssertEqual(code.userCode, "ABCD-1234")
        XCTAssertEqual(code.verificationURL.absoluteString, "https://github.com/login/device")
        XCTAssertEqual(code.expiresIn, 900)
        XCTAssertEqual(code.interval, 5)

        let recorded = await transport.requests
        let request = try XCTUnwrap(recorded.first)
        XCTAssertEqual(request.url?.absoluteString, "https://github.com/login/device/code")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"),
                       "application/x-www-form-urlencoded")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "hAiity")
        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("client_id=public-client-id"))
        XCTAssertFalse(body.contains("scope"))
        XCTAssertFalse(body.contains("client_secret"))
    }

    func testVerificationURLCanCarryTheUserCodeForPrefilledBrowsers() {
        let code = GitHubDeviceCode(deviceCode: "dc",
                                    userCode: "ABCD-1234",
                                    verificationURL: URL(string: "https://github.com/login/device")!,
                                    expiresIn: 900,
                                    interval: 5)

        XCTAssertEqual(code.verificationURLWithCode.absoluteString,
                       "https://github.com/login/device?user_code=ABCD-1234")
    }

    func testUnconfiguredClientIDFailsBeforeNetwork() async {
        let transport = ScriptedGitHubTransport([])
        let flow = GitHubDeviceFlow(transport: transport,
                                    sleeper: RecordingGitHubSleeper(),
                                    clientID: GitHubAppConfig.placeholderClientID)
        do {
            _ = try await flow.requestCode()
            XCTFail("expected unconfigured")
        } catch {
            XCTAssertEqual(error as? GitHubDeviceFlowError, .unconfigured)
        }
    }

    func testPollReturnsTokenAfterPendingAndSlowDown() async throws {
        let pending = Data(#"{"error":"authorization_pending"}"#.utf8)
        let slow = Data(#"{"error":"slow_down"}"#.utf8)
        let token = Data(#"{"access_token":"gho_secret","token_type":"bearer"}"#.utf8)
        let transport = ScriptedGitHubTransport([(pending, 200), (slow, 200), (token, 200)])
        let sleeper = RecordingGitHubSleeper()
        let flow = GitHubDeviceFlow(transport: transport, sleeper: sleeper, clientID: clientID)
        let code = GitHubDeviceCode(deviceCode: "dc",
                                    userCode: "ABCD-1234",
                                    verificationURL: URL(string: "https://github.com/login/device")!,
                                    expiresIn: 30,
                                    interval: 5)

        let access = try await flow.pollForToken(code)
        XCTAssertEqual(access, "gho_secret")
        let sleeps = await sleeper.sleeps
        XCTAssertEqual(sleeps, [5, 5, 10])

        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
        let body = String(data: try XCTUnwrap(requests[0].httpBody), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("client_id=public-client-id"))
        XCTAssertTrue(body.contains("device_code=dc"))
        XCTAssertTrue(body.contains("grant_type=urn:ietf:params:oauth:grant-type:device_code"))
        XCTAssertFalse(body.contains("scope"))
        XCTAssertEqual(requests[0].url?.absoluteString,
                       "https://github.com/login/oauth/access_token")
    }

    func testPollDeniedExpiredAndMalformed() async {
        let cases: [(Data, GitHubDeviceFlowError)] = [
            (Data(#"{"error":"access_denied"}"#.utf8), .denied),
            (Data(#"{"error":"expired_token"}"#.utf8), .expired),
            (Data(#"{"nope":true}"#.utf8), .malformedPayload),
            (Data("not-json".utf8), .malformedPayload)
        ]
        for (payload, expected) in cases {
            let transport = ScriptedGitHubTransport([(payload, 200)])
            let flow = GitHubDeviceFlow(transport: transport,
                                        sleeper: RecordingGitHubSleeper(),
                                        clientID: clientID)
            let code = GitHubDeviceCode(deviceCode: "dc",
                                        userCode: "X",
                                        verificationURL: URL(string: "https://github.com/login/device")!,
                                        expiresIn: 5,
                                        interval: 1)
            do {
                _ = try await flow.pollForToken(code)
                XCTFail("expected \(expected)")
            } catch {
                XCTAssertEqual(error as? GitHubDeviceFlowError, expected)
            }
        }
    }

    func testPollExpiresWhenBudgetRunsOut() async {
        let pending = Data(#"{"error":"authorization_pending"}"#.utf8)
        let transport = ScriptedGitHubTransport([(pending, 200), (pending, 200)])
        let flow = GitHubDeviceFlow(transport: transport,
                                    sleeper: RecordingGitHubSleeper(),
                                    clientID: clientID)
        let code = GitHubDeviceCode(deviceCode: "dc",
                                    userCode: "X",
                                    verificationURL: URL(string: "https://github.com/login/device")!,
                                    expiresIn: 2,
                                    interval: 1)
        do {
            _ = try await flow.pollForToken(code)
            XCTFail("expected expired")
        } catch {
            XCTAssertEqual(error as? GitHubDeviceFlowError, .expired)
        }
    }

    func testPollCancellationDoesNotExposeToken() async {
        let pending = Data(#"{"error":"authorization_pending"}"#.utf8)
        let transport = ScriptedGitHubTransport([(pending, 200)])
        let flow = GitHubDeviceFlow(transport: transport,
                                    sleeper: RecordingGitHubSleeper(),
                                    clientID: clientID)
        let code = GitHubDeviceCode(deviceCode: "dc",
                                    userCode: "X",
                                    verificationURL: URL(string: "https://github.com/login/device")!,
                                    expiresIn: 20,
                                    interval: 5)
        let task = Task { try await flow.pollForToken(code) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            let text = "\(error) \(String(describing: error)) \(error.localizedDescription)"
            XCTAssertFalse(text.contains("gho_"))
            XCTAssertTrue(error is CancellationError
                          || (error as? GitHubDeviceFlowError) == .cancelled)
        }
    }

    func testHTTPFailureAndNonHTTPSVerificationAreRejected() async {
        let transport = ScriptedGitHubTransport([(Data(), 503)])
        let flow = GitHubDeviceFlow(transport: transport,
                                    sleeper: RecordingGitHubSleeper(),
                                    clientID: clientID)
        do {
            _ = try await flow.requestCode()
            XCTFail("expected http status")
        } catch {
            XCTAssertEqual(error as? GitHubDeviceFlowError, .httpStatus(503))
        }

        let bad = Data(#"""
        {"device_code":"dc","user_code":"X",
         "verification_uri":"http://evil.example/login",
         "expires_in":15,"interval":5}
        """#.utf8)
        let insecure = ScriptedGitHubTransport([(bad, 200)])
        let insecureFlow = GitHubDeviceFlow(transport: insecure,
                                            sleeper: RecordingGitHubSleeper(),
                                            clientID: clientID)
        do {
            _ = try await insecureFlow.requestCode()
            XCTFail("expected malformed")
        } catch {
            XCTAssertEqual(error as? GitHubDeviceFlowError, .malformedPayload)
        }
    }

    func testErrorsNeverIncludeTokensOrBodies() {
        for error in [GitHubDeviceFlowError.denied, .expired, .cancelled,
                      .malformedPayload, .httpStatus(401), .unconfigured] {
            let text = "\(error) \(String(describing: error)) \(error.localizedDescription)"
            XCTAssertFalse(text.contains("gho_secret"))
            XCTAssertFalse(text.contains("access_token"))
            XCTAssertFalse(text.contains("device_code"))
        }
    }
}
