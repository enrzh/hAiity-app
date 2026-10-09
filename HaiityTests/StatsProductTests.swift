import XCTest
import SwiftUI
import UIKit
@testable import Haiity

@MainActor
final class StatsProductTests: XCTestCase {
    private func snapshot() -> StatsEngine.Snapshot {
        .init(today: "2026-10-07", todayDone: 2, todayTotal: 3,
              streak: 0, bestStreak: 12,
              week: .init(done: 7, total: 9), previousWeek: .init(done: 5, total: 7),
              last7: [1, 0, 0.5, 1, 1, 0.5, 2.0 / 3],
              last7HasData: [true, false, true, true, true, true, true],
              mergedLevels: [], perHabit: [], totalCheckIns: 42)
    }

    private func bundle(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try XCTUnwrap(Bundle(path: path))
    }

    func testTodayFocusesOnRemainingWorkEvenWhenStreakIsZero() throws {
        var value = snapshot()
        let german = try bundle("de")
        let locale = Locale(identifier: "de")
        XCTAssertEqual(StatsView.statsTodaySentence(value, bundle: german, locale: locale), "Noch 1 offen")
        value.streak = 40
        XCTAssertEqual(StatsView.statsTodaySentence(value, bundle: german, locale: locale), "Noch 1 offen")
        value.todayDone = value.todayTotal
        XCTAssertEqual(StatsView.statsTodaySentence(value, bundle: german, locale: locale),
                       "Alles erledigt. Gute Arbeit.")
        value.todayTotal = 0
        value.todayDone = 0
        XCTAssertEqual(StatsView.statsTodaySentence(value, bundle: german, locale: locale), "Dein Tag ist frei.")
    }

    func testWeeklyPresentationUsesExistingCountsAndRoundingWithoutInventingAnEmptyRate() throws {
        let german = try bundle("de")
        let english = try bundle("en")
        let value = snapshot()
        XCTAssertEqual(StatsView.weekCompletionSummary(value.week, bundle: german, locale: Locale(identifier: "de")),
                       "7 von 9 erledigt · 78 %")
        XCTAssertEqual(StatsView.weekCompletionSummary(value.week, bundle: english, locale: Locale(identifier: "en")),
                       "7 of 9 completed · 78 %")
        XCTAssertEqual(StatsView.weekCompletionSummary(.init(done: 0, total: 3), bundle: german, locale: Locale(identifier: "de")),
                       "0 von 3 erledigt · 0 %")
        XCTAssertEqual(StatsView.weekCompletionSummary(.init(done: 0, total: 0), bundle: german, locale: Locale(identifier: "de")),
                       "Diese Woche ist nichts fällig")
    }

    func testNativeSummaryCardsGrowAtAX5InBothAppearancesAndDirections() {
        let suite = "StatsProductTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stats-product-\(UUID()).json")
        let store = HabitStore(url: url, loadFromDisk: false)
        let view = StatsView(store: store, viewPreferences: ViewPreferencesStore(defaults: defaults))
        let value = snapshot()

        for scheme in [ColorScheme.light, .dark] {
            for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                let normal = UIHostingController(rootView: view.statsWeekCard(value)
                    .environment(\.dynamicTypeSize, .large)
                    .environment(\.colorScheme, scheme)
                    .environment(\.layoutDirection, direction))
                let accessible = UIHostingController(rootView: view.statsWeekCard(value)
                    .environment(\.dynamicTypeSize, .accessibility5)
                    .environment(\.colorScheme, scheme)
                    .environment(\.layoutDirection, direction))
                let today = UIHostingController(rootView: view.statsTodayCard(value)
                    .environment(\.dynamicTypeSize, .accessibility5)
                    .environment(\.colorScheme, scheme)
                    .environment(\.layoutDirection, direction))
                let normalToday = UIHostingController(rootView: view.statsTodayCard(value)
                    .environment(\.dynamicTypeSize, .large)
                    .environment(\.colorScheme, scheme)
                    .environment(\.layoutDirection, direction))
                let proposal = CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
                let normalSize = normal.sizeThatFits(in: proposal)
                let accessibleSize = accessible.sizeThatFits(in: proposal)
                let todaySize = today.sizeThatFits(in: proposal)
                let normalTodaySize = normalToday.sizeThatFits(in: proposal)
                XCTAssertLessThanOrEqual(accessibleSize.width, 320)
                XCTAssertGreaterThan(accessibleSize.height, normalSize.height)
                XCTAssertGreaterThan(todaySize.height, 0)
                XCTAssertLessThanOrEqual(todaySize.width, 320)
                XCTAssertLessThan(normalTodaySize.height, normalSize.height,
                                  "Today stays lighter than the weekly summary")
            }
        }
    }

    func testCustomizedCardsSurviveExportDecodeAndNewerRemoteAdoption() throws {
        let suite = "StatsProductPreferences-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for selection in [StatsCard.allCases, [], [.weekMomentum, .todayRing], StatsCardPrefs.defaultActive] {
            let selected = StatsCardPrefs(active: selection, customized: true)
            let original = ViewPreferences(updatedAt: 123, statsCards: selected, compactMode: true)
            var export = HabitData.empty
            export.viewPreferences = original
            let decoded = try JSONDecoder().decode(HabitData.self, from: JSONEncoder().encode(export)).viewPreferences
            XCTAssertEqual(decoded, original)
            let store = ViewPreferencesStore(defaults: defaults)
            store.adoptRemote(decoded)
            XCTAssertEqual(store.statsCards, selected)
            XCTAssertEqual(ViewPreferencesStore(defaults: defaults).statsCards, selected)
            defaults.removePersistentDomain(forName: suite)
        }
        let future = Data(#"{"active":["future-card","weekMomentum","weekMomentum"],"customized":true}"#.utf8)
        let decoded = try JSONDecoder().decode(StatsCardPrefs.self, from: future)
        XCTAssertEqual(decoded.active, [.weekMomentum])
        XCTAssertTrue(decoded.isCustomized)
    }
}
