import Foundation
import XCTest
@testable import Haiity

actor RecordingGitHubTransport: GitHubHTTPTransport {
    private let responseData: Data
    private let statusCode: Int
    private(set) var request: URLRequest?

    init(responseData: Data, statusCode: Int = 200) {
        self.responseData = responseData
        self.statusCode = statusCode
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        let response = HTTPURLResponse(url: try XCTUnwrap(request.url),
                                       statusCode: statusCode,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: [:])!
        return (responseData, response)
    }
}

/// Fails the first N requests with a URLError, then succeeds. A phone dropping
/// its connection and getting it back is the normal case, not an edge one.
final class FlakyURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var failures = 0
    nonisolated(unsafe) static var code: URLError.Code = .networkConnectionLost
    nonisolated(unsafe) static var attempts = 0
    /// Fail every attempt, to model something the retry must NOT paper over.
    nonisolated(unsafe) static var alwaysFails = false

    static func reset(failures: Int,
                      code: URLError.Code = .networkConnectionLost,
                      alwaysFails: Bool = false) {
        Self.failures = failures
        Self.code = code
        Self.attempts = 0
        Self.alwaysFails = alwaysFails
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FlakyURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        FlakyURLProtocol.attempts += 1
        if FlakyURLProtocol.alwaysFails || FlakyURLProtocol.attempts <= FlakyURLProtocol.failures {
            client?.urlProtocol(self, didFailWithError: URLError(FlakyURLProtocol.code))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class GitHubContributionsTests: XCTestCase {

    // MARK: - Not timing out

    /// The actual complaint. `URLSession.shared` has `waitsForConnectivity` off,
    /// so a request made while the connection is still coming up fails instantly
    /// rather than waiting — which reads as "times out straight away" and is not a
    /// timeout at all.
    func testTheSessionWaitsForConnectivity() {
        let configuration = URLSessionGitHubTransport.session.configuration
        XCTAssertTrue(configuration.waitsForConnectivity,
                      "without this a request fails the instant the network is not ready")
        XCTAssertFalse(URLSession.shared.configuration.waitsForConnectivity,
                       "this is the default being escaped, so it had better stay true")
        // A phone connection is not a datacentre one, and a minute per request is
        // a long time to hold someone's refresh for.
        XCTAssertLessThanOrEqual(configuration.timeoutIntervalForRequest, 30)
    }

    /// The request carries an Authorization header, so it must not be answerable
    /// from a cache on disk.
    func testAnAuthenticatedRequestIsNotServedFromACache() {
        XCTAssertNil(URLSessionGitHubTransport.session.configuration.urlCache,
                     "a token-bearing request has no business in a URL cache")
    }

    /// One dropped connection should not end a refresh.
    func testATransientDropIsRetriedAndSucceeds() async throws {
        FlakyURLProtocol.reset(failures: 1, code: .networkConnectionLost)
        let transport = URLSessionGitHubTransport(session: FlakyURLProtocol.session())
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://api.github.com/graphql")))

        let (data, response) = try await transport.send(request)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "{}")
        XCTAssertEqual(FlakyURLProtocol.attempts, 2,
                       "one blip should cost one retry and then succeed")
    }

    /// A connection that stays down gives up rather than looping.
    func testAPermanentDropFailsAfterOneRetry() async throws {
        FlakyURLProtocol.reset(failures: 5, code: .notConnectedToInternet, alwaysFails: true)
        let transport = URLSessionGitHubTransport(session: FlakyURLProtocol.session())
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://api.github.com/graphql")))

        do {
            _ = try await transport.send(request)
            XCTFail("a network that never arrives should not succeed")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        } catch {
            XCTFail("expected a URLError, got \(error)")
        }
        XCTAssertEqual(FlakyURLProtocol.attempts, 2, "one retry, not a queue of them")
    }

    /// Only genuine blips are retried. An answer from the server, or a malformed
    /// request, is an answer — trying again only makes the wait longer.
    func testAnAnswerIsNotRetried() async throws {
        FlakyURLProtocol.reset(failures: 0, code: .badURL, alwaysFails: true)
        let transport = URLSessionGitHubTransport(session: FlakyURLProtocol.session())
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://api.github.com/graphql")))

        do {
            _ = try await transport.send(request)
            XCTFail("a bad URL should not succeed")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .badURL)
        } catch {
            XCTFail("expected a URLError, got \(error)")
        }
        XCTAssertEqual(FlakyURLProtocol.attempts, 1, "a non-blip is not worth a second try")
    }

    /// Every failure used to collapse into one sentence, so a phone with no signal
    /// reported that GitHub was down.
    @MainActor
    func testConnectivityFailuresSayWhatTheyAre() {
        let noNetwork = GitHubContributionStore.message(for: URLError(.notConnectedToInternet))
        let unreachable = GitHubContributionStore.message(for: URLError(.cannotFindHost))
        let slow = GitHubContributionStore.message(for: URLError(.timedOut))
        let generic = GitHubContributionStore.message(for: URLError(.badServerResponse))

        XCTAssertEqual(noNetwork, "Keine Internetverbindung.")
        XCTAssertEqual(unreachable, "GitHub ist gerade nicht erreichbar.")
        XCTAssertEqual(slow, "GitHub hat zu lange gebraucht. Später noch einmal versuchen.")
        XCTAssertNotEqual(noNetwork, unreachable)
        XCTAssertNotEqual(unreachable, slow)
        XCTAssertNotEqual(slow, generic)
    }
    private let now = ISO8601DateFormatter().date(from: "2026-08-16T12:34:56Z")!

    func testModelsKeepStableIdentityAndProfileURL() throws {
        let day = GitHubContributionDay(date: "2026-08-16", count: 3, level: 2)
        let snapshot = GitHubContributionSnapshot(username: "octocat",
                                                  days: [day],
                                                  fetchedAt: now)

        XCTAssertEqual(day.id, "2026-08-16")
        XCTAssertEqual(snapshot.profileURL?.absoluteString, "https://github.com/octocat")
        XCTAssertEqual(try JSONDecoder().decode(GitHubContributionSnapshot.self,
                                                from: JSONEncoder().encode(snapshot)),
                       snapshot)
    }

    func testRequestUsesReadOnlyGraphQLContractAndExactDateVariables() async throws {
        let transport = RecordingGitHubTransport(responseData: validPayload())
        _ = try await GitHubContributionsClient(transport: transport)
            .fetch(token: "secret-token", now: now)

        let capturedRequest = await transport.request
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/graphql")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"),
                       "Bearer secret-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "hAiity")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"),
                       "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let query = try XCTUnwrap(json["query"] as? String)
        let variables = try XCTUnwrap(json["variables"] as? [String: String])
        XCTAssertTrue(query.contains("viewer"))
        XCTAssertTrue(query.contains("login"))
        XCTAssertTrue(query.contains("contributionsCollection(from: $from, to: $to)"))
        XCTAssertFalse(query.lowercased().contains("mutation"))
        XCTAssertFalse(query.lowercased().contains("repository"))
        XCTAssertEqual(variables["from"], "2025-08-16T12:34:56Z")
        XCTAssertEqual(variables["to"], "2026-08-16T12:34:56Z")
    }

    func testFetchFlattensChronologicallyMapsLevelsAndClampsCounts() async throws {
        let payload = Data(#"""
        {
          "data": {"viewer": {
            "login": "octocat",
            "contributionsCollection": {"contributionCalendar": {"weeks": [
              {"contributionDays": [
                {"date":"2026-08-16","contributionCount":9,"contributionLevel":"FOURTH_QUARTILE"},
                {"date":"2026-08-14","contributionCount":3,"contributionLevel":"SECOND_QUARTILE"}
              ]},
              {"contributionDays": [
                {"date":"2026-08-15","contributionCount":-4,"contributionLevel":"NONE"},
                {"date":"2026-08-13","contributionCount":1,"contributionLevel":"FIRST_QUARTILE"},
                {"date":"2026-08-12","contributionCount":7,"contributionLevel":"THIRD_QUARTILE"}
              ]}
            ]}}
          }}
        }
        """#.utf8)
        let transport = RecordingGitHubTransport(responseData: payload)

        let snapshot = try await GitHubContributionsClient(transport: transport)
            .fetch(token: "token", now: now)

        XCTAssertEqual(snapshot.username, "octocat")
        XCTAssertEqual(snapshot.fetchedAt, now)
        XCTAssertEqual(snapshot.days, [
            GitHubContributionDay(date: "2026-08-12", count: 7, level: 3),
            GitHubContributionDay(date: "2026-08-13", count: 1, level: 1),
            GitHubContributionDay(date: "2026-08-14", count: 3, level: 2),
            GitHubContributionDay(date: "2026-08-15", count: 0, level: 0),
            GitHubContributionDay(date: "2026-08-16", count: 9, level: 4)
        ])
    }

    func testHTTP401IsClassifiedAsUnauthorized() async {
        let transport = RecordingGitHubTransport(responseData: Data(), statusCode: 401)

        await assertFetchError(.unauthorized, transport: transport)
    }

    func testOtherHTTPFailureKeepsItsStatusCode() async {
        let transport = RecordingGitHubTransport(responseData: Data(), statusCode: 503)

        await assertFetchError(.httpStatus(503), transport: transport)
    }

    func testGraphQLErrorsAreClassifiedWithMessages() async {
        let payload = Data(#"{"errors":[{"message":"Bad credentials"},{"message":"Denied"}]}"#.utf8)
        let transport = RecordingGitHubTransport(responseData: payload)

        await assertFetchError(.graphQL(["Bad credentials", "Denied"]),
                               transport: transport)
    }

    func testRejectsEmptyUsername() async {
        let transport = RecordingGitHubTransport(responseData: validPayload(username: "  "))

        await assertFetchError(.malformedPayload, transport: transport)
    }

    func testRejectsMalformedDate() async {
        let transport = RecordingGitHubTransport(
            responseData: validPayload(date: "2026-02-30"))

        await assertFetchError(.malformedPayload, transport: transport)
    }

    func testRejectsDuplicateDates() async {
        let payload = Data(#"""
        {
          "data": {"viewer": {
            "login": "octocat",
            "contributionsCollection": {"contributionCalendar": {"weeks": [
              {"contributionDays": [
                {"date":"2026-08-16","contributionCount":1,"contributionLevel":"FIRST_QUARTILE"}
              ]},
              {"contributionDays": [
                {"date":"2026-08-16","contributionCount":2,"contributionLevel":"SECOND_QUARTILE"}
              ]}
            ]}}
          }}
        }
        """#.utf8)
        let transport = RecordingGitHubTransport(responseData: payload)

        await assertFetchError(.malformedPayload, transport: transport)
    }

    func testRejectsUnknownContributionLevel() async {
        let transport = RecordingGitHubTransport(
            responseData: validPayload(level: "FIFTH_QUARTILE"))

        await assertFetchError(.malformedPayload, transport: transport)
    }

    func testRejectsMissingOrInvalidResponseShape() async {
        for payload in [Data(#"{"data":null}"#.utf8), Data("not json".utf8)] {
            let transport = RecordingGitHubTransport(responseData: payload)
            await assertFetchError(.malformedPayload, transport: transport)
        }
    }

    private func assertFetchError(_ expected: GitHubContributionsError,
                                  transport: RecordingGitHubTransport) async {
        do {
            _ = try await GitHubContributionsClient(transport: transport)
                .fetch(token: "token", now: now)
            XCTFail("fetch should throw \(expected)")
        } catch {
            XCTAssertEqual(error as? GitHubContributionsError, expected)
        }
    }

    private func validPayload(username: String = "octocat",
                              date: String = "2026-08-16",
                              level: String = "NONE") -> Data {
        let object: [String: Any] = [
            "data": [
                "viewer": [
                    "login": username,
                    "contributionsCollection": [
                        "contributionCalendar": [
                            "weeks": [[
                                "contributionDays": [[
                                    "date": date,
                                    "contributionCount": 0,
                                    "contributionLevel": level
                                ]]
                            ]]
                        ]
                    ]
                ]
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: object)
    }
}
