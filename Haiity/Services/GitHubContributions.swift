import Foundation

protocol GitHubHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

protocol GitHubContributionsFetching: Sendable {
    func fetch(token: String, now: Date) async throws -> GitHubContributionSnapshot
}

enum GitHubContributionsError: Error, Equatable, Sendable {
    case unauthorized
    case httpStatus(Int)
    case graphQL([String])
    case malformedPayload
    case nonHTTPResponse
}

/// The one place the app talks to GitHub.
///
/// `URLSession.shared` has `waitsForConnectivity` switched OFF, which means a
/// request issued while the connection is still coming up fails *immediately*
/// rather than waiting for it. On a phone that has just unlocked, or on a
/// connection that is merely marginal, that is the whole story behind "the GitHub
/// page times out straight away" — nothing is timing out, the request never got
/// to try. The shared session's 60-second request timeout is also tight for a
/// GraphQL query over a phone connection.
struct URLSessionGitHubTransport: GitHubHTTPTransport {

    /// One session for both the contributions query and the device flow, so a
    /// blip during sign-in is treated the same way as one during a refresh.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        // The fix. Wait for the network instead of failing the instant it is not
        // there yet.
        configuration.waitsForConnectivity = true
        // Once connected, one request should not take a minute. The resource
        // timeout is the longer budget, and it also bounds how long the session
        // will sit waiting for connectivity to turn up.
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        // An authenticated request should not be served from a cache. The
        // Authorization header travels with it, so the response is left on the
        // wire and nowhere else.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// Injectable so the retry can be tested against a stubbed protocol rather
    /// than only asserted about in the source.
    private let session: URLSession

    init(session: URLSession = URLSessionGitHubTransport.session) {
        self.session = session
    }

    /// Only the failures worth trying again. A cancelled task, and anything the
    /// server actually answered, are answers rather than blips.
    private static let transient: Set<URLError.Code> = [
        .timedOut, .networkConnectionLost, .notConnectedToInternet,
        .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
        .internationalRoamingOff, .dataNotAllowed,
    ]

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var lastError: Error?
        // One retry. A phone drops a connection routinely — a tunnel, a lift, the
        // handover between cells — and a refresh that gives up on the first one
        // is indistinguishable from a broken integration.
        for attempt in 0...1 {
            do {
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse else {
                    throw GitHubContributionsError.nonHTTPResponse
                }
                return (data, response)
            } catch {
                lastError = error
                guard attempt == 0,
                      let urlError = error as? URLError,
                      Self.transient.contains(urlError.code) else { throw error }
                // A short beat, so the retry does not arrive while the network is
                // still down and spends the second attempt on the same moment.
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
        throw lastError ?? GitHubContributionsError.malformedPayload
    }
}

struct GitHubContributionsClient: GitHubContributionsFetching {
    private static let endpoint = URL(string: "https://api.github.com/graphql")!
    private static let query = """
    query Contributions($from: DateTime!, $to: DateTime!) {
      viewer {
        login
        contributionsCollection(from: $from, to: $to) {
          contributionCalendar {
            weeks {
              contributionDays {
                date
                contributionCount
                contributionLevel
              }
            }
          }
        }
      }
    }
    """

    private let transport: any GitHubHTTPTransport

    init(transport: any GitHubHTTPTransport = URLSessionGitHubTransport()) {
        self.transport = transport
    }

    func fetch(token: String, now: Date) async throws -> GitHubContributionSnapshot {
        let request = try Self.request(token: token, now: now)
        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200..<300:
            break
        case 401:
            throw GitHubContributionsError.unauthorized
        default:
            throw GitHubContributionsError.httpStatus(response.statusCode)
        }

        let envelope: GraphQLResponse
        do {
            envelope = try JSONDecoder().decode(GraphQLResponse.self, from: data)
        } catch {
            throw GitHubContributionsError.malformedPayload
        }
        if let errors = envelope.errors, !errors.isEmpty {
            throw GitHubContributionsError.graphQL(errors.map(\.message))
        }
        guard let viewer = envelope.data?.viewer,
              !viewer.login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubContributionsError.malformedPayload
        }

        var seen = Set<String>()
        var days: [GitHubContributionDay] = []
        for week in viewer.contributionsCollection.contributionCalendar.weeks {
            for day in week.contributionDays {
                guard Self.isValidDate(day.date), seen.insert(day.date).inserted else {
                    throw GitHubContributionsError.malformedPayload
                }
                days.append(GitHubContributionDay(date: day.date,
                                                  count: max(0, day.contributionCount),
                                                  level: day.contributionLevel.value))
            }
        }
        days.sort { $0.date < $1.date }
        return GitHubContributionSnapshot(username: viewer.login, days: days, fetchedAt: now)
    }

    private static func request(token: String, now: Date) throws -> URLRequest {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let from = calendar.date(byAdding: .year, value: -1, to: now) else {
            throw GitHubContributionsError.malformedPayload
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let body: [String: Any] = [
            "query": query,
            "variables": [
                "from": formatter.string(from: from),
                "to": formatter.string(from: now)
            ]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("hAiity", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func isValidDate(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }
}

private struct GraphQLResponse: Decodable {
    let data: GraphQLData?
    let errors: [GraphQLError]?
}

private struct GraphQLError: Decodable {
    let message: String
}

private struct GraphQLData: Decodable {
    let viewer: GraphQLViewer
}

private struct GraphQLViewer: Decodable {
    let login: String
    let contributionsCollection: GraphQLContributionsCollection
}

private struct GraphQLContributionsCollection: Decodable {
    let contributionCalendar: GraphQLContributionCalendar
}

private struct GraphQLContributionCalendar: Decodable {
    let weeks: [GraphQLContributionWeek]
}

private struct GraphQLContributionWeek: Decodable {
    let contributionDays: [GraphQLContributionDay]
}

private struct GraphQLContributionDay: Decodable {
    let date: String
    let contributionCount: Int
    let contributionLevel: GraphQLContributionLevel
}

private enum GraphQLContributionLevel: String, Decodable {
    case none = "NONE"
    case first = "FIRST_QUARTILE"
    case second = "SECOND_QUARTILE"
    case third = "THIRD_QUARTILE"
    case fourth = "FOURTH_QUARTILE"

    var value: Int {
        switch self {
        case .none: 0
        case .first: 1
        case .second: 2
        case .third: 3
        case .fourth: 4
        }
    }
}
