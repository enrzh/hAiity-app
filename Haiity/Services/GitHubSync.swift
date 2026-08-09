import Foundation

/// Sync in das EIGENE GitHub-Repo des Nutzers (haiity-data/data.json) über
/// die Contents-API. Es gibt keinen hAiity-Server: Token im Schlüsselbund,
/// Requests gehen direkt zu api.github.com. Jeder Check-in ist ein echter
/// Commit — er füllt den echten Contribution-Graph.
protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, response as! HTTPURLResponse)
    }
}

enum SyncError: LocalizedError, Equatable {
    case badToken(Int)
    case repoUnavailable(Int)
    case pushFailed(Int)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .badToken(let s): return String(localized: "Token abgelehnt (HTTP \(s)) — Berechtigungen prüfen.")
        case .repoUnavailable(let s): return String(localized: "Repo nicht erreichbar (HTTP \(s)).")
        case .pushFailed(let s): return String(localized: "Sync fehlgeschlagen (HTTP \(s)).")
        case .network(let m): return String(localized: "Netzwerkfehler: \(m)")
        }
    }
}

actor GitHubSync {
    static let repoName = "haiity-data"
    static let dataPath = "data.json"
    static let tokenAccount = "github-token"

    private let transport: HTTPTransport
    private let vault: TokenVault
    private(set) var login: String?
    private var remoteSha: String?
    /// Session-Cache: hält das Token auch, wenn der Vault (z. B. im
    /// unsignierten Test-Host) nicht schreiben kann.
    private var token: String?

    init(transport: HTTPTransport = URLSessionTransport(),
         vault: TokenVault = KeychainVault(account: GitHubSync.tokenAccount)) {
        self.transport = transport
        self.vault = vault
    }

    var isConnected: Bool { login != nil && (token ?? vault.get()) != nil }

    private func request(_ path: String, method: String = "GET", body: Data? = nil, token: String) -> URLRequest {
        var r = URLRequest(url: URL(string: "https://api.github.com\(path)")!)
        r.httpMethod = method
        r.httpBody = body
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return r
    }

    /// Übernimmt ein Token — egal woher es kommt (eingefügtes PAT oder
    /// Device Flow): validiert es, stellt das private Repo sicher,
    /// speichert es im Schlüsselbund. Gibt den Login zurück.
    func connect(token: String) async throws -> String {
        let login = try await resolveLogin(token: token)
        try await ensureDataRepo(login: login, token: token)

        vault.set(token)
        self.token = token
        UserDefaults.standard.set(login, forKey: "github-login")
        self.login = login
        return login
    }

    /// Wer bin ich? Validiert das Token gleich mit.
    func resolveLogin(token: String) async throws -> String {
        let (userData, userRes) = try await sendCatching(request("/user", token: token))
        guard userRes.statusCode == 200,
              let user = try? JSONDecoder().decode(GHUser.self, from: userData) else {
            throw SyncError.badToken(userRes.statusCode)
        }
        return user.login
    }

    /// Stellt sicher, dass das private Repo `haiity-data` existiert — legt
    /// es sonst an. Eigener Schritt, damit BEIDE Anmeldewege (Token-Einfügen
    /// und Device Flow) dieselbe Logik benutzen statt sie zu doppeln.
    func ensureDataRepo(login: String, token: String) async throws {
        let (_, repoRes) = try await sendCatching(request("/repos/\(login)/\(Self.repoName)", token: token))
        if repoRes.statusCode == 404 {
            let body = try JSONSerialization.data(withJSONObject: [
                "name": Self.repoName,
                "private": true,
                "auto_init": true,
                "description": "hAiity habit data — yours, in your repo",
            ])
            let (_, createRes) = try await sendCatching(request("/user/repos", method: "POST", body: body, token: token))
            guard (200..<300).contains(createRes.statusCode) else {
                throw SyncError.repoUnavailable(createRes.statusCode)
            }
        } else if repoRes.statusCode != 200 {
            throw SyncError.repoUnavailable(repoRes.statusCode)
        }
    }

    func restore() {
        if let stored = vault.get() {
            token = stored
            login = UserDefaults.standard.string(forKey: "github-login")
        }
    }

    func disconnect() {
        vault.delete()
        token = nil
        UserDefaults.standard.removeObject(forKey: "github-login")
        login = nil
        remoteSha = nil
    }

    /// Holt den Remote-Stand; nil bei 404 (noch keine Daten).
    func pull() async throws -> HabitData? {
        guard let token = token ?? vault.get(), let login else { return nil }
        let (data, res) = try await sendCatching(request("/repos/\(login)/\(Self.repoName)/contents/\(Self.dataPath)", token: token))
        if res.statusCode == 404 { remoteSha = nil; return nil }
        guard res.statusCode == 200,
              let file = try? JSONDecoder().decode(GHFile.self, from: data) else {
            throw SyncError.repoUnavailable(res.statusCode)
        }
        remoteSha = file.sha
        guard let raw = Data(base64Encoded: file.content.replacingOccurrences(of: "\n", with: "")) else { return nil }
        return try? JSONDecoder().decode(HabitData.self, from: raw)
    }

    /// Schreibt den Stand; bei sha-Konflikt (409/422) einmal pull+merge+retry.
    /// `merge` läuft im Aufrufer (Store), damit die Union-Semantik EIN Ort ist.
    func push(_ payload: Data, mergeAndRetry: @Sendable (HabitData?) async -> Data) async throws {
        guard let token = token ?? vault.get(), let login else { return }
        func attempt(_ content: Data) async throws -> HTTPURLResponse {
            var obj: [String: Any] = [
                "message": "habits: \(DayKey.today())",
                "content": content.base64EncodedString(),
            ]
            if let remoteSha { obj["sha"] = remoteSha }
            let body = try JSONSerialization.data(withJSONObject: obj)
            let (data, res) = try await sendCatching(request("/repos/\(login)/\(Self.repoName)/contents/\(Self.dataPath)", method: "PUT", body: body, token: token))
            if (200..<300).contains(res.statusCode),
               let out = try? JSONDecoder().decode(GHPutResponse.self, from: data) {
                remoteSha = out.content.sha
            }
            return res
        }
        var res = try await attempt(payload)
        if res.statusCode == 409 || res.statusCode == 422 {
            let remote = try? await pull()
            let mergedPayload = await mergeAndRetry(remote)
            res = try await attempt(mergedPayload)
        }
        guard (200..<300).contains(res.statusCode) else { throw SyncError.pushFailed(res.statusCode) }
    }

    private func sendCatching(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do { return try await transport.send(r) }
        catch { throw SyncError.network(error.localizedDescription) }
    }
}

private struct GHUser: Decodable { let login: String }
private struct GHFile: Decodable { let sha: String; let content: String }
private struct GHPutResponse: Decodable {
    struct C: Decodable { let sha: String }
    let content: C
}
