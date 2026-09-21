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

    func testTodayKeepsUnfinishedOverdueReminders() {
        var overdue = Habit(name: "Arzt", itemType: .reminder,
                            timeMinutes: 9 * 60,
                            recurrence: Recurrence(frequency: .once, start: "2026-08-20"))
        overdue.createdAt = "2026-08-20"
        var weekly = Habit(name: "Tabletten", itemType: .reminder,
                           timeMinutes: 9 * 60,
                           recurrence: .weekdays([2], start: "2026-08-17"))
        weekly.createdAt = "2026-08-17"
        var future = Habit(name: "Später", itemType: .reminder,
                           timeMinutes: 9 * 60,
                           recurrence: Recurrence(frequency: .once, start: "2026-08-30"))
        future.createdAt = "2026-08-20"
        let unscheduledHabit = Habit(name: "Montag",
                                     recurrence: .weekdays([2], start: "2026-08-01"))

        var filter = HabitListFilter(todayOnly: true)
        XCTAssertTrue(filter.matches(overdue,
                                     defaultTimeZoneIdentifier: nil,
                                     now: now,
                                     base: calendar))
        XCTAssertTrue(filter.matches(weekly,
                                     defaultTimeZoneIdentifier: nil,
                                     now: now,
                                     base: calendar))
        XCTAssertFalse(filter.matches(future,
                                      defaultTimeZoneIdentifier: nil,
                                      now: now,
                                      base: calendar))
        XCTAssertFalse(filter.matches(unscheduledHabit,
                                      defaultTimeZoneIdentifier: nil,
                                      now: now,
                                      base: calendar))

        filter.status = .notDone
        XCTAssertTrue(filter.matches(overdue,
                                     defaultTimeZoneIdentifier: nil,
                                     now: now,
                                     base: calendar))
        filter.status = .done
        XCTAssertFalse(filter.matches(overdue,
                                      defaultTimeZoneIdentifier: nil,
                                      now: now,
                                      base: calendar))

        overdue.log["2026-08-20"] = 1
        filter.status = .all
        XCTAssertFalse(filter.matches(overdue,
                                      defaultTimeZoneIdentifier: nil,
                                      now: now,
                                      base: calendar))
    }
}
