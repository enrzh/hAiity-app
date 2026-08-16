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

final class GitHubContributionsTests: XCTestCase {
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
