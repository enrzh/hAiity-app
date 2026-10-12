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

    func testSelectedMetricsKeepExactSnapshotValuesAndDoNotRepeatTheWeeklyRate() throws {
        var value = snapshot()
        let german = try bundle("de")
        let locale = Locale(identifier: "de")
        XCTAssertEqual(StatsView.statsMetricValue(.todayRing, snapshot: value, bundle: german, locale: locale), "2/3")
        XCTAssertEqual(StatsView.statsMetricValue(.streakFlame, snapshot: value), "0")
        XCTAssertEqual(StatsView.statsMetricValue(.totals, snapshot: value), "42")
        XCTAssertEqual(StatsView.statsMetricValue(.weekMomentum, snapshot: value, bundle: german, locale: locale),
                       "In der Wochenbilanz")
        let english = try bundle("en")
        XCTAssertEqual(StatsView.statsMetricValue(.weekMomentum, snapshot: value, bundle: english, locale: Locale(identifier: "en")),
                       "In the weekly summary")
        value.todayTotal = 0
        value.todayDone = 0
        XCTAssertEqual(StatsView.statsMetricValue(.todayRing, snapshot: value, bundle: german, locale: locale),
                       "Kein Habit fällig")
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

    func testPresentationKeepsQuantityAnswersAndFlexiblePeriodDenominatorsFromTheEngine() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let today = "2026-10-07"
        var daily = Habit(name: "Daily")
        daily.createdAt = "2026-10-05"
        daily.log = ["2026-10-05": 1, today: 1]
        var quantity = Habit(name: "Quantity", recurrence: Recurrence(target: 3), kind: .quantity)
        quantity.createdAt = daily.createdAt
        quantity.log = ["2026-10-05": 2, "2026-10-06": 3, today: 1]
        var answers = Habit(name: "Answers", kind: .yesNo)
        answers.createdAt = daily.createdAt
        answers.log = ["2026-10-05": Habit.Answer.yes, "2026-10-06": Habit.Answer.no, today: Habit.Answer.yes]
        var weekly = Habit(name: "Weekly", recurrence: .times(2, per: .weekly))
        weekly.createdAt = daily.createdAt
        weekly.log = ["2026-10-05": 1, "2026-10-06": 1]
        var monthly = Habit(name: "Monthly", recurrence: .times(2, per: .monthly))
        monthly.createdAt = daily.createdAt
        monthly.log = ["2026-10-06": 1, today: 1]
        var reminder = Habit(name: "Reminder", itemType: .reminder)
        reminder.createdAt = daily.createdAt
        reminder.log = [today: 1]
        let value = StatsEngine.snapshot(habits: [daily, quantity, answers, weekly, monthly, reminder],
                                         today: today, calendar: calendar)
        XCTAssertEqual(value.week, .init(done: 7, total: 11))
        XCTAssertEqual(StatsView.weekCompletionSummary(value.week, bundle: try bundle("en"), locale: Locale(identifier: "en")),
                       "7 of 11 completed · 64 %")
        XCTAssertEqual(StatsView.statsMetricValue(.todayRing, snapshot: value), "3/5")
        XCTAssertEqual(StatsView.statsMetricValue(.totals, snapshot: value), "9")
        XCTAssertEqual(value.mergedLevels.count, 20)
        XCTAssertEqual(value.perHabit.map(\.id), [daily, quantity, answers, weekly, monthly].map(\.id))
    }

    func testWeeklySummaryAndSelectedMetricsGrowAtAX5InBothAppearancesAndDirections() {
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
                let proposal = CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
                let normalSize = normal.sizeThatFits(in: proposal)
                let accessibleSize = accessible.sizeThatFits(in: proposal)
                XCTAssertLessThanOrEqual(accessibleSize.width, 320)
                XCTAssertGreaterThan(accessibleSize.height, normalSize.height)
                for card in [StatsCard.todayRing, .weekMomentum, .totals, .streakFlame] {
                    let normalMetric = UIHostingController(rootView: view.statsMetric(card, snapshot: value)
                        .environment(\.dynamicTypeSize, .large)
                        .environment(\.colorScheme, scheme)
                        .environment(\.layoutDirection, direction))
                    let accessibleMetric = UIHostingController(rootView: view.statsMetric(card, snapshot: value)
                        .environment(\.dynamicTypeSize, .accessibility5)
                        .environment(\.colorScheme, scheme)
                        .environment(\.layoutDirection, direction))
                    let metricSize = accessibleMetric.sizeThatFits(in: proposal)
                    XCTAssertLessThanOrEqual(metricSize.width, 320)
                    XCTAssertGreaterThan(metricSize.height, normalMetric.sizeThatFits(in: proposal).height)
                }
            }
        }
    }

    func testDetailActionPassesOnlyTheSelectedLiveIDToTheOwner() {
        let suite = "StatsNavigation-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HabitStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("stats-navigation-\(UUID()).json"), loadFromDisk: false)
        let preferences = ViewPreferencesStore(defaults: defaults)
        let id = UUID()
        var selectedID: UUID?
        var historyID: UUID?
        let view = StatsView(store: store, viewPreferences: preferences,
                             onOpenHabit: { selectedID = $0 },
                             onOpenHistory: { historyID = $0 })
        view.openHabit(id)
        XCTAssertEqual(selectedID, id)
        XCTAssertNil(historyID, "Details must not invoke full history")
        let otherID = UUID()
        view.openHistory(otherID)
        XCTAssertEqual(historyID, otherID)
        XCTAssertEqual(selectedID, id)
        XCTAssertTrue(store.data.habits.isEmpty, "The owner resolves the UUID from its live store")
    }

    func testCustomizedCardsSurviveExportDecodeAndNewerRemoteAdoption() throws {
        let suite = "StatsProductPreferences-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for selection in [StatsCard.allCases, [], [.weekMomentum, .todayRing],
                          [.todayRing, .totals, .yearPulse, .weekMomentum, .streakFlame], StatsCardPrefs.defaultActive] {
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
