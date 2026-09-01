import Foundation
import XCTest
@testable import Haiity

final class MotivationFeedTests: XCTestCase {
    func testValidFeedIsFilteredAndCached() async throws {
        let suite = "MotivationFeedTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let response = HTTPURLResponse(url: URL(string: "https://example.com/feed.json")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let payload = Data("{\"data\":[{\"quote\":\"Keep going.\",\"author\":\"Author\"},{\"quote\":\"\",\"author\":null}]}".utf8)

        let result = try await MotivationFeed.refreshIfNeeded(enabled: true, now: Date(timeIntervalSince1970: 100_000), defaults: defaults) { _ in (payload, response) }

        XCTAssertEqual(result.map(\.text), ["Keep going."])
        XCTAssertEqual(MotivationFeedCache.load(in: defaults).map(\.text), ["Keep going."])
    }

    func testDisabledFeedNeverCallsTransportAndClearsCache() async throws {
        let suite = "MotivationFeedTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        MotivationFeedCache.save([MotivationFeedEntry(text: "Old", language: "en", author: nil)], receivedAt: .now, in: defaults)
        var calls = 0

        let result = try await MotivationFeed.refreshIfNeeded(enabled: false, now: .now, defaults: defaults) { _ in
            calls += 1
            throw URLError(.badServerResponse)
        }

        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(MotivationFeedCache.load(in: defaults).isEmpty)
    }

    func testFreshCacheDoesNotRefresh() async throws {
        let suite = "MotivationFeedTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 100_000)
        let entries = [MotivationFeedEntry(text: "Cached", language: "de", author: nil)]
        MotivationFeedCache.save(entries, receivedAt: now, in: defaults)
        var calls = 0

        let result = try await MotivationFeed.refreshIfNeeded(enabled: true, now: now.addingTimeInterval(60), defaults: defaults) { _ in
            calls += 1
            throw URLError(.badServerResponse)
        }

        XCTAssertEqual(result, entries)
        XCTAssertEqual(calls, 0)
    }

    func testRejectsInvalidLanguageLongTextAndOversizedList() async throws {
        let suite = "MotivationFeedTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let response = HTTPURLResponse(url: URL(string: "https://example.com/feed.json")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let entries = (0..<201).map { _ in "{\"quote\":\"Valid\",\"author\":null}" }.joined(separator: ",")
        let overlongQuote = String(repeating: "x", count: 141)
        let payloadText = "{\"data\":[\(entries),{\"quote\":\"\(overlongQuote)\",\"author\":null},{\"quote\":\"Unknown\",\"author\":null}]}"
        let payload = Data(payloadText.utf8)

        do {
            _ = try await MotivationFeed.refreshIfNeeded(enabled: true, now: .now, defaults: defaults) { _ in (payload, response) }
            XCTFail("Expected invalid feed")
        } catch {
            XCTAssertTrue(MotivationFeedCache.load(in: defaults).isEmpty)
        }
    }

    func testHTTPErrorKeepsExistingCache() async throws {
        let suite = "MotivationFeedTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cached = [MotivationFeedEntry(text: "Keep me", language: "en", author: nil)]
        MotivationFeedCache.save(cached, receivedAt: Date(timeIntervalSince1970: 0), in: defaults)
        let response = HTTPURLResponse(url: URL(string: "https://example.com/feed.json")!, statusCode: 503, httpVersion: nil, headerFields: nil)!

        do {
            _ = try await MotivationFeed.refreshIfNeeded(enabled: true, now: Date(timeIntervalSince1970: 700_000), defaults: defaults) { _ in
                (Data(), response)
            }
            XCTFail("Expected HTTP error")
        } catch {
            XCTAssertEqual(MotivationFeedCache.load(in: defaults), cached)
        }
    }
}
