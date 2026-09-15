import XCTest
@testable import Haiity

final class HabitListFilterTests: XCTestCase {
    private var calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return value
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 12))!
    }

    func testFiltersTodayStatusAndItemTypeTogether() {
        var habit = Habit(name: "Lesen", recurrence: Recurrence(frequency: .daily,
                                                                  start: "2026-08-01"))
        habit.log["2026-08-25"] = 1
        let reminder = Habit(name: "Wasser", itemType: .reminder,
                             recurrence: Recurrence(frequency: .daily,
                                                    start: "2026-08-01"))

        var filter = HabitListFilter(todayOnly: true, status: .done, itemType: .habit)
        XCTAssertTrue(filter.matches(habit,
                                     defaultTimeZoneIdentifier: nil,
                                     now: now,
                                     base: calendar))
        XCTAssertFalse(filter.matches(reminder,
                                      defaultTimeZoneIdentifier: nil,
                                      now: now,
                                      base: calendar))

        filter.status = .notDone
        XCTAssertFalse(filter.matches(habit,
                                      defaultTimeZoneIdentifier: nil,
                                      now: now,
                                      base: calendar))
        XCTAssertTrue(filter.isEmpty == false)
    }

    func testTodayOnlyRoundTripsThroughAppGroupDefaults() {
        let suite = "HabitListFilterTodayOnly-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(HabitListFilter.restored(from: defaults).todayOnly)
        HabitListFilterPreferences.setTodayOnly(true, in: defaults)
        XCTAssertTrue(HabitListFilter.restored(from: defaults).todayOnly)
        HabitListFilterPreferences.setTodayOnly(false, in: defaults)
        XCTAssertFalse(HabitListFilter.restored(from: defaults).todayOnly)
    }

    func testHabitsScreenRestoresAndPersistsTodayOnly() throws {
        let content = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Haiity/Views/ContentView.swift"))

        XCTAssertTrue(content.contains("HabitListFilter.restored()"),
                      "Heute/Alle must load the last saved viewing mode at launch")
        XCTAssertTrue(content.contains("HabitListFilterPreferences.persistTodayOnly(todayOnly)"),
                      "selecting Heute or Alle must write the viewing mode immediately")
        XCTAssertTrue(content.contains("HabitListFilter(todayOnly: habitFilter.todayOnly)"),
                      "resetting status/type filters must keep Heute/Alle")
    }

    func testStatusFiltersExcludeUnsheduledDays() {
        let habit = Habit(name: "Montag", recurrence: .weekdays([2], start: "2026-08-24"))
        let filter = HabitListFilter(status: .notDone)
        XCTAssertFalse(filter.matches(habit,
                                      defaultTimeZoneIdentifier: nil,
                                      now: now,
                                      base: calendar))
    }
}
