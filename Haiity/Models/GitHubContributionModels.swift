import Foundation

struct GitHubContributionDay: Codable, Equatable, Sendable, Identifiable {
    let date: String
    let count: Int
    let level: Int
    var id: String { date }
}

struct GitHubContributionSnapshot: Codable, Equatable, Sendable {
    let username: String
    let days: [GitHubContributionDay]
    let fetchedAt: Date

    var profileURL: URL? {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "github.com"
        parts.percentEncodedPath = "/\(encoded)"
        return parts.url
    }

    static func sharedCacheURL(fileManager: FileManager = .default) -> URL {
        SharedStorage.dataURL(fileManager: fileManager)
            .deletingLastPathComponent()
            .appendingPathComponent("github-contributions.json")
    }

    static func saveShared(_ snapshot: GitHubContributionSnapshot, to url: URL? = nil) throws {
        let destination = url ?? sharedCacheURL()
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: destination, options: .atomic)
    }

    static func loadShared(from url: URL? = nil) -> GitHubContributionSnapshot? {
        let source = url ?? sharedCacheURL()
        guard let data = try? Data(contentsOf: source) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GitHubContributionSnapshot.self, from: data)
    }
}
