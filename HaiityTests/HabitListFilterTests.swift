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

    func testStatusFiltersExcludeUnsheduledDays() {
        let habit = Habit(name: "Montag", recurrence: .weekdays([2], start: "2026-08-24"))
        let filter = HabitListFilter(status: .notDone)
        XCTAssertFalse(filter.matches(habit,
                                      defaultTimeZoneIdentifier: nil,
                                      now: now,
                                      base: calendar))
    }
}
