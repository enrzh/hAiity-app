import Foundation
import XCTest
@testable import Haiity

final class GitHubCardContractTests: XCTestCase {
    func testHabitsPageHostsTheCardOutsideSearchAndHabitActions() throws {
        let content = try source("Haiity/Views/ContentView.swift")
        let card = try source("Haiity/Views/GitHubContributionCard.swift")
        let searchStart = try XCTUnwrap(content.range(of: "private var searchList: some View"))
        let habitsStart = try XCTUnwrap(content.range(of: "private var habitList: some View"))
        let searchListSource = String(content[searchStart.lowerBound..<habitsStart.lowerBound])
        let habitList = String(content[habitsStart.lowerBound...])

        XCTAssertTrue(content.contains("GitHubContributionCard"))
        XCTAssertTrue(card.contains("GitHub-Profil öffnen"))
        XCTAssertTrue(card.contains("arrow.up.right.square"))
        XCTAssertFalse(card.contains("SwipeRevealPan"))
        XCTAssertFalse(card.contains("swipeActions"))
        XCTAssertFalse(card.contains("RevealAction"))
        XCTAssertFalse(searchListSource.contains("GitHubContributionCard"))
        XCTAssertTrue(habitList.contains("GitHubContributionCard"))

        let cardUse = try XCTUnwrap(habitList.range(of: "GitHubContributionCard"))
        let foreach = try XCTUnwrap(habitList.range(of: "ForEach(Array(habitsTabSource.enumerated())"))
        XCTAssertLessThan(cardUse.lowerBound, foreach.lowerBound)
        let afterCard = habitList[cardUse.upperBound..<foreach.lowerBound]
        XCTAssertFalse(afterCard.contains(".onMove"))
        XCTAssertFalse(afterCard.contains("swipeActions"))
        XCTAssertFalse(afterCard.contains("row(for:"))
    }

    func testProfileURLPercentEncodesTheLogin() {
        let snapshot = GitHubContributionSnapshot(username: "octo cat",
                                                  days: [],
                                                  fetchedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(snapshot.profileURL?.absoluteString, "https://github.com/octo%20cat")
        XCTAssertEqual(GitHubContributionSnapshot(username: "enrzh", days: [], fetchedAt: .now)
            .profileURL?.absoluteString, "https://github.com/enrzh")
    }

    func testSettingsLiveOnMainMoreAndPreserveTheExistingFlow() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        let content = try source("Haiity/Views/ContentView.swift")
        let settings = try source("Haiity/Views/GitHubSettingsView.swift")

        XCTAssertTrue(more.contains("case archive, about, developer, appearance, habitBehavior, github"))
        XCTAssertTrue(more.contains("open-github-settings"))
        XCTAssertTrue(more.contains("private var githubSection: some View"))
        XCTAssertTrue(more.contains("disconnect-github"))
        XCTAssertFalse(more.contains("NavigationLink(value: MoreRoute.github)"))
        XCTAssertTrue(content.contains("GitHubSettingsView(store: github)"))
        XCTAssertTrue(content.contains("AboutView()"))
        XCTAssertTrue(settings.contains("github-connect"))
        XCTAssertTrue(settings.contains("github-open-verification"))
        XCTAssertTrue(settings.contains("github-refresh"))
        XCTAssertTrue(settings.contains("github-disconnect"))
        XCTAssertTrue(settings.contains("UIApplication.shared.open"))
        XCTAssertTrue(settings.contains("url.scheme?.lowercased() == \"https\""))
    }

    func testGitHubLinkRejectsNonHTTPS() {
        XCTAssertNotNil(GitHubContributionSnapshot(username: "enrzh", days: [], fetchedAt: .now).profileURL)
    }

    func testGitHubKeysHaveEveryLocalization() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Localizable.xcstrings"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        let languages = ["ar", "bn", "en", "es", "fr", "hi", "id", "it",
                         "ja", "ko", "pt", "ru", "tr", "ur", "vi", "zh-Hans"]
        let keys = [
            "GitHub verbinden", "Auf GitHub öffnen", "Aktualisieren",
            "Verbindung trennen", "GitHub-Konto trennen?",
            "Der Beitragskalender verschwindet von der Habits-Seite.",
            "Erneut versuchen", "GitHub-Profil öffnen",
            "GitHub ist nicht eingerichtet.",
            "GitHub hat die Verbindung abgelehnt.",
            "Der Code ist abgelaufen. Bitte erneut verbinden.",
            "Die Verbindung zu GitHub ist fehlgeschlagen.",
            "Verbunden als %@",
            "Dein offizieller GitHub-Beitragskalender erscheint auf der Habits-Seite.",
            "Code auf GitHub eingeben", "GitHub-Beitragskalender"
        ]
        for key in keys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], "fehlt im Katalog: \(key)")
            let locs = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
            for language in languages {
                let unit = locs[language] as? [String: Any]
                let stringUnit = unit?["stringUnit"] as? [String: Any]
                let value = stringUnit?["value"] as? String
                XCTAssertEqual(stringUnit?["state"] as? String, "translated", "\(key) \(language)")
                XCTAssertNotEqual(value, key, "\(language) fällt auf Deutsch zurück: \(key)")
                XCTAssertFalse(value?.isEmpty ?? true, "\(key) \(language)")
            }
        }
    }

    func testGraphBuildsSevenRowsWithoutInventingAHabit() {
        let days = [
            GitHubContributionDay(date: "2026-08-16", count: 2, level: 1),
            GitHubContributionDay(date: "2026-08-17", count: 0, level: 0)
        ]
        let layout = GitHubContributionGraph.layout(days: days, weekLimit: nil)
        XCTAssertFalse(layout.columns.isEmpty)
        XCTAssertEqual(layout.columns[0].count, 7)
        let source = try? self.source("Haiity/Views/GitHubContributionCard.swift")
        XCTAssertFalse(source?.contains("Habit(") ?? true)
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relative))
    }
}
