import Foundation

/// GitHub **Device Flow** (RFC 8628) — der Weg ohne Server und ohne
/// Token-Bastelei: die App schickt ihre öffentliche `client_id`, GitHub
/// antwortet mit einem kurzen Nutzer-Code, der Nutzer bestätigt ihn im
/// Browser, die App pollt derweil auf das Access-Token. Kein Client-Secret,
/// kein Callback-Server, kein hAiity-Backend.
///
/// Das Token landet am Ende über `GitHubSync.connect(token:)` im selben
/// Schlüsselbund-Slot wie ein eingefügtes Token — Pull/Push merken keinen
/// Unterschied.

/// Was GitHub auf `POST /login/device/code` zurückgibt.
struct DeviceCode: Equatable, Sendable {
    let deviceCode: String
    /// Der kurze Code, den der Nutzer im Browser eintippt (z. B. „WDJB-MJHT").
    let userCode: String
    let verificationURI: String
    /// Sekunden, bis der Code verfällt.
    let expiresIn: Int
    /// Mindestabstand zwischen zwei Polls, in Sekunden.
    let interval: Int

    var verificationURL: URL? { URL(string: verificationURI) }
}

enum DeviceFlowError: LocalizedError, Equatable {
    case notConfigured
    case requestFailed(Int)
    case malformed
    case expired
    case denied
    /// Alles, was GitHub als harten Fehlercode meldet
    /// (`incorrect_device_code`, `unsupported_grant_type`,
    /// `device_flow_disabled`, `incorrect_client_credentials` …).
    case rejected(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return String(localized: "Die Anmeldung über GitHub ist in dieser Version nicht eingerichtet — bitte den Token-Weg unter „Erweitert“ nutzen.")
        case .requestFailed(let s):
            return String(localized: "GitHub hat die Anfrage abgelehnt (HTTP \(s)). Bitte später erneut versuchen.")
        case .malformed:
            return String(localized: "Unerwartete Antwort von GitHub — bitte erneut versuchen.")
        case .expired:
            return String(localized: "Code abgelaufen, neu starten.")
        case .denied:
            return String(localized: "Zugriff in GitHub abgelehnt — es wurde nichts verbunden.")
        case .rejected(let code):
            return String(localized: "GitHub hat die Anmeldung abgelehnt (\(code)). Bitte neu starten.")
        case .network(let m):
            return String(localized: "Netzwerkfehler: \(m)")
        }
    }
}

/// Zeit-Seam. Produktion schläft echt; Tests injizieren eine Fake-Uhr,
/// damit Polling-Tests keine echten Sekunden verbrauchen — und damit
/// überhaupt prüfbar ist, WIE LANGE gewartet wurde (`slow_down`).
struct DeviceFlowClock: Sendable {
    var now: @Sendable () -> Date
    var sleep: @Sendable (Duration) async throws -> Void

    static let live = DeviceFlowClock(now: { Date() },
                                      sleep: { try await Task.sleep(for: $0) })
}

actor GitHubDeviceFlow {
    static let codeEndpoint = URL(string: "https://github.com/login/device/code")!
    static let tokenEndpoint = URL(string: "https://github.com/login/oauth/access_token")!
    static let grantType = "urn:ietf:params:oauth:grant-type:device_code"

    private let transport: HTTPTransport
    private let sync: GitHubSync
    private let clientId: String
    private let configured: Bool
    private let clock: DeviceFlowClock

    init(sync: GitHubSync,
         transport: HTTPTransport = URLSessionTransport(),
         clientId: String = GitHubAppConfig.clientId,
         configured: Bool = GitHubAppConfig.isConfigured,
         clock: DeviceFlowClock = .live) {
        self.sync = sync
        self.transport = transport
        self.clientId = clientId
        self.configured = configured
        self.clock = clock
    }

    // MARK: – Schritt 1: Code holen

    func requestCode() async throws -> DeviceCode {
        guard configured else { throw DeviceFlowError.notConfigured }
        // `scope=repo` ist der Fallback für OAuth-Apps; GitHub Apps
        // ignorieren scope und nutzen ihre konfigurierten Permissions.
        let (data, res) = try await send(form(Self.codeEndpoint, [
            "client_id": clientId,
            "scope": "repo",
        ]))
        let obj = Self.json(data)
        if let err = obj["error"] as? String { throw Self.mapped(err) }
        guard (200..<300).contains(res.statusCode) else {
            throw DeviceFlowError.requestFailed(res.statusCode)
        }
        guard let device = obj["device_code"] as? String, !device.isEmpty,
              let user = obj["user_code"] as? String, !user.isEmpty,
              let uri = obj["verification_uri"] as? String, !uri.isEmpty else {
            throw DeviceFlowError.malformed
        }
        return DeviceCode(deviceCode: device,
                          userCode: user,
                          verificationURI: uri,
                          expiresIn: Self.int(obj["expires_in"]) ?? 900,
                          interval: max(1, Self.int(obj["interval"]) ?? 5))
    }

    // MARK: – Schritt 2: auf die Bestätigung pollen

    /// Pollt im vorgegebenen Takt, bis das Token da ist, GitHub hart
    /// ablehnt oder `expires_in` abgelaufen ist. Reagiert auf
    /// Task-Cancellation (die UI bricht damit ab).
    func pollForToken(_ code: DeviceCode) async throws -> String {
        guard configured else { throw DeviceFlowError.notConfigured }
        var interval = Duration.seconds(max(1, code.interval))
        let deadline = clock.now().addingTimeInterval(TimeInterval(max(1, code.expiresIn)))

        while true {
            try Task.checkCancellation()
            try await clock.sleep(interval)
            try Task.checkCancellation()
            // `expires_in` ist die harte Obergrenze — auch wenn GitHub
            // (noch) brav `authorization_pending` sagt.
            if clock.now() >= deadline { throw DeviceFlowError.expired }

            let (data, res) = try await send(form(Self.tokenEndpoint, [
                "client_id": clientId,
                "device_code": code.deviceCode,
                "grant_type": Self.grantType,
            ]))
            let obj = Self.json(data)

            if let token = obj["access_token"] as? String, !token.isEmpty { return token }

            guard let err = obj["error"] as? String else {
                // Weder Token noch Fehlercode: entweder Müll (200) oder ein
                // echter HTTP-Fehler.
                throw (200..<300).contains(res.statusCode)
                    ? DeviceFlowError.malformed
                    : DeviceFlowError.requestFailed(res.statusCode)
            }

            switch err {
            case "authorization_pending":
                continue                        // ganz normal: Nutzer tippt noch
            case "slow_down":
                // GitHub schickt ein neues, größeres `interval` mit; fehlt
                // es, schreibt die Spec +5 s vor. Nie kleiner werden.
                let announced = Self.int(obj["interval"]).map { Duration.seconds(max(1, $0)) }
                interval = max(announced ?? .zero, interval + .seconds(5))
                continue
            case "expired_token":
                throw DeviceFlowError.expired
            case "access_denied":
                throw DeviceFlowError.denied
            default:
                throw Self.mapped(err)          // incorrect_device_code etc.
            }
        }
    }

    // MARK: – Beides zusammen

    /// Kompletter Ablauf: Code holen → `onCode` (die UI zeigt ihn an) →
    /// pollen → Token übernehmen. Die Token-Übernahme (Schlüsselbund,
    /// `/user`, Repo `haiity-data` sicherstellen) macht bewusst
    /// `GitHubSync.connect(token:)` — EIN Ort für beide Wege.
    @discardableResult
    func authorize(onCode: @Sendable @escaping (DeviceCode) -> Void) async throws -> String {
        let code = try await requestCode()
        onCode(code)
        let token = try await pollForToken(code)
        try Task.checkCancellation()
        return try await sync.connect(token: token)
    }

    // MARK: – Draht

    private func form(_ url: URL, _ fields: [String: String]) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        // Ohne diesen Accept-Header antwortet GitHub form-encoded.
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = fields
            .map { "\(Self.esc($0.key))=\(Self.esc($0.value))" }
            .sorted()
            .joined(separator: "&")
        r.httpBody = Data(body.utf8)
        return r
    }

    private func send(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do { return try await transport.send(r) }
        catch is CancellationError { throw CancellationError() }
        catch let e as URLError where e.code == .cancelled { throw CancellationError() }
        catch { throw DeviceFlowError.network(error.localizedDescription) }
    }

    private static func esc(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private static func json(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// GitHub liefert Zahlen mal als Zahl, mal als String.
    private static func int(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String { return Int(s) }
        return nil
    }

    private static func mapped(_ code: String) -> DeviceFlowError {
        switch code {
        case "expired_token": return .expired
        case "access_denied": return .denied
        default: return .rejected(code)
        }
    }
}
