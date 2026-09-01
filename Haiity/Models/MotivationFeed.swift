import Foundation

struct MotivationFeedEntry: Codable, Equatable, Sendable {
    let text: String
    let language: String
    let author: String?
}

enum MotivationFeedCache {
    private static let entriesKey = "motivationFeed.entries"
    private static let receivedAtKey = "motivationFeed.receivedAt"

    static func load(in defaults: UserDefaults) -> [MotivationFeedEntry] {
        guard let data = defaults.data(forKey: entriesKey),
              let entries = try? JSONDecoder().decode([MotivationFeedEntry].self, from: data) else { return [] }
        return entries
    }

    static func save(_ entries: [MotivationFeedEntry], receivedAt: Date, in defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: entriesKey)
        defaults.set(receivedAt.timeIntervalSince1970, forKey: receivedAtKey)
    }

    static func clear(in defaults: UserDefaults) {
        defaults.removeObject(forKey: entriesKey)
        defaults.removeObject(forKey: receivedAtKey)
    }

    fileprivate static func receivedAt(in defaults: UserDefaults) -> Date? {
        guard defaults.object(forKey: receivedAtKey) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: receivedAtKey))
    }
}

enum MotivationFeed {
    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)

    private static let url = URL(string: "https://raw.githubusercontent.com/mubaris/motivate/ff66d015fe9f6017444ea709f8e3217a0537c4cd/200.json")!
    private static let maxBytes = 128 * 1024
    private static let maxScalars = 140
    private static let maxEntries = 200
    private static let cacheLifetime: TimeInterval = 7 * 24 * 60 * 60
    private static let supportedLanguages: Set<String> = ["de", "en", "es", "fr", "it", "pt", "zh", "ja", "ru", "ar", "hi", "bn", "ur", "id", "tr", "vi", "ko"]

    private struct Feed: Decodable {
        struct SourceEntry: Decodable {
            let quote: String
            let author: String?
        }
        let data: [SourceEntry]
    }

    static func refreshIfNeeded(enabled: Bool, now: Date, defaults: UserDefaults, transport: @escaping Transport) async throws -> [MotivationFeedEntry] {
        if !enabled {
            MotivationFeedCache.clear(in: defaults)
            return []
        }
        let cached = MotivationFeedCache.load(in: defaults)
        if let receivedAt = MotivationFeedCache.receivedAt(in: defaults), now.timeIntervalSince(receivedAt) < cacheLifetime, !cached.isEmpty {
            return cached
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        let (data, response) = try await transport(request)
        guard (200..<300).contains(response.statusCode), data.count <= maxBytes else { throw Error.invalidFeed }
        let feed = try JSONDecoder().decode(Feed.self, from: data)
        guard feed.data.count <= maxEntries else { throw Error.invalidFeed }
        let valid = feed.data.map { MotivationFeedEntry(text: $0.quote, language: "en", author: $0.author) }.filter { entry in
            !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && entry.text.unicodeScalars.count <= maxScalars && supportedLanguages.contains(entry.language.lowercased())
        }
        guard !valid.isEmpty else { throw Error.invalidFeed }
        MotivationFeedCache.save(valid, receivedAt: now, in: defaults)
        return valid
    }

    enum Error: Swift.Error { case invalidFeed }
}
