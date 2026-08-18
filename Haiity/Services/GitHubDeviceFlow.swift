import Foundation

struct GitHubDeviceCode: Codable, Equatable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let expiresIn: Int
    let interval: Int

    /// GitHub documents the device page, but not a prefilled query. Keep the
    /// documented URL as a fallback if URL construction ever fails.
    var verificationURLWithCode: URL {
        guard var components = URLComponents(url: verificationURL,
                                              resolvingAgainstBaseURL: false) else {
            return verificationURL
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "user_code" }
        queryItems.append(URLQueryItem(name: "user_code", value: userCode))
        components.queryItems = queryItems
        return components.url ?? verificationURL
    }
}

protocol GitHubDeviceAuthorizing: Sendable {
    func requestCode() async throws -> GitHubDeviceCode
    func pollForToken(_ code: GitHubDeviceCode) async throws -> String
}

protocol GitHubSleeper: Sendable {
    func sleep(seconds: Int) async throws
}

struct TaskGitHubSleeper: GitHubSleeper {
    func sleep(seconds: Int) async throws {
        try await Task.sleep(for: .seconds(max(0, seconds)))
    }
}

enum GitHubDeviceFlowError: Error, Equatable, Sendable {
    case unconfigured
    case httpStatus(Int)
    case denied
    case expired
    case cancelled
    case malformedPayload
}

struct GitHubDeviceFlow: GitHubDeviceAuthorizing {
    private static let codeURL = URL(string: "https://github.com/login/device/code")!
    private static let tokenURL = URL(string: "https://github.com/login/oauth/access_token")!
    private static let grantType = "urn:ietf:params:oauth:grant-type:device_code"

    private let transport: any GitHubHTTPTransport
    private let sleeper: any GitHubSleeper
    private let clientID: String

    init(transport: any GitHubHTTPTransport = URLSessionGitHubTransport(),
         sleeper: any GitHubSleeper = TaskGitHubSleeper(),
         clientID: String = GitHubAppConfig.clientID) {
        self.transport = transport
        self.sleeper = sleeper
        self.clientID = clientID
    }

    func requestCode() async throws -> GitHubDeviceCode {
        try checkNotCancelled()
        guard !clientID.isEmpty && clientID != GitHubAppConfig.placeholderClientID else {
            throw GitHubDeviceFlowError.unconfigured
        }
        var request = URLRequest(url: Self.codeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("hAiity", forHTTPHeaderField: "User-Agent")
        request.httpBody = form(["client_id": clientID])
        let json = try await send(request)
        guard let device = json["device_code"] as? String, !device.isEmpty,
              let user = json["user_code"] as? String, !user.isEmpty,
              let uri = json["verification_uri"] as? String,
              let url = URL(string: uri), url.scheme?.lowercased() == "https",
              let expires = intValue(json["expires_in"]), expires > 0 else {
            throw GitHubDeviceFlowError.malformedPayload
        }
        return GitHubDeviceCode(deviceCode: device,
                                userCode: user,
                                verificationURL: url,
                                expiresIn: expires,
                                interval: max(1, intValue(json["interval"]) ?? 5))
    }

    func pollForToken(_ code: GitHubDeviceCode) async throws -> String {
        var interval = max(1, code.interval)
        var remaining = max(1, code.expiresIn)
        while remaining > 0 {
            try checkNotCancelled()
            try await sleepOrCancel(seconds: interval)
            remaining -= interval
            try checkNotCancelled()
            var request = URLRequest(url: Self.tokenURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("hAiity", forHTTPHeaderField: "User-Agent")
            request.httpBody = form([
                "client_id": clientID,
                "device_code": code.deviceCode,
                "grant_type": Self.grantType
            ])
            let json = try await send(request)
            if let token = json["access_token"] as? String, !token.isEmpty {
                return token
            }
            switch json["error"] as? String {
            case "authorization_pending":
                continue
            case "slow_down":
                interval += 5
            case "access_denied":
                throw GitHubDeviceFlowError.denied
            case "expired_token":
                throw GitHubDeviceFlowError.expired
            case .none:
                throw GitHubDeviceFlowError.malformedPayload
            default:
                throw GitHubDeviceFlowError.malformedPayload
            }
        }
        throw GitHubDeviceFlowError.expired
    }

    private func checkNotCancelled() throws {
        if Task.isCancelled { throw GitHubDeviceFlowError.cancelled }
    }

    private func sleepOrCancel(seconds: Int) async throws {
        do {
            try await sleeper.sleep(seconds: seconds)
        } catch is CancellationError {
            throw GitHubDeviceFlowError.cancelled
        }
        try checkNotCancelled()
    }

    private func send(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw GitHubDeviceFlowError.httpStatus(response.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GitHubDeviceFlowError.malformedPayload
        }
        return json
    }

    private func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+="))
        return fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        .joined(separator: "&")
        .data(using: .utf8) ?? Data()
    }

    private func intValue(_ raw: Any?) -> Int? {
        if let n = raw as? Int { return n }
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String { return Int(s) }
        return nil
    }
}
