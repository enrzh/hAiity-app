import XCTest
@testable import Haiity

final class WeeklyInsightTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.firstWeekday = 2
        value.timeZone = TimeZone(identifier: "UTC")!
        return value
    }

    private func habit(_ recurrence: Recurrence = .daily, created: String = "2026-08-01",
                       kind: HabitKind = .checkbox, log: [String: Int] = [:]) -> Habit {
        var value = Habit(name: "H", recurrence: recurrence, kind: kind)
        value.createdAt = created
        value.log = log
        return value
    }

    func testFixedScheduleUsesOnlyScheduledDaysAndCountsOffScheduleAsBonus() {
        let value = habit(.weekdays([2, 4]), log: ["2026-08-03": 1, "2026-08-04": 1, "2026-08-05": 1])
        let result = StatsEngine.weeklyInsight(habits: [value], today: "2026-08-12", calendar: calendar)
        XCTAssertEqual(result.habits.first?.required, 2)
        XCTAssertEqual(result.habits.first?.done, 2)
    }

    func testCreatedAfterWeekAndQuantityAndYesNoAreHonest() {
        let newHabit = habit(created: "2026-08-11")
        XCTAssertTrue(StatsEngine.weeklyInsight(habits: [newHabit], today: "2026-08-12", calendar: calendar).habits.isEmpty)
        let quantityRule = Recurrence(frequency: .daily, target: 3)
        let below = habit(quantityRule, kind: .quantity, log: ["2026-08-03": 2])
        let atTarget = habit(quantityRule, kind: .quantity, log: ["2026-08-03": 3])
        XCTAssertEqual(StatsEngine.weeklyInsight(habits: [below], today: "2026-08-12", calendar: calendar).scheduledDone, 0)
        XCTAssertEqual(StatsEngine.weeklyInsight(habits: [atTarget], today: "2026-08-12", calendar: calendar).scheduledDone, 1)
        let yesNo = habit(kind: .yesNo, log: ["2026-08-03": Habit.Answer.no])
        XCTAssertEqual(StatsEngine.weeklyInsight(habits: [yesNo], today: "2026-08-12", calendar: calendar).habits.first?.done, 0)
    }

    func testFlexibleGoalIsPeriodProgressNotScheduledDayMetric() {
        let value = habit(.times(3, per: .weekly), log: ["2026-08-03": 1, "2026-08-04": 1])
        let result = StatsEngine.weeklyInsight(habits: [value], today: "2026-08-12", calendar: calendar)
        XCTAssertTrue(result.habits.isEmpty)
        XCTAssertEqual(result.excludedFlexibleCount, 1)
        XCTAssertEqual(result.scheduledTotal, 0)
    }

    func testArchivedAndReminderHabitsAreExcluded() {
        var archived = habit(log: ["2026-08-03": 1])
        archived.archivedAt = "2026-08-04"
        let reminder = Habit(name: "Reminder", itemType: .reminder)
        let result = StatsEngine.weeklyInsight(habits: [archived, reminder],
                                               today: "2026-08-12", calendar: calendar)
        XCTAssertEqual(result.scheduledTotal, 0)
        XCTAssertTrue(result.habits.isEmpty)
    }

    func testFlexibleMonthlyGoalAndInactiveWeekAreExcluded() {
        let monthly = habit(.times(3, per: .monthly))
        let inactive = habit(.weekdays([2]), created: "2026-08-10")
        let result = StatsEngine.weeklyInsight(habits: [monthly, inactive],
                                               today: "2026-08-12", calendar: calendar)
        XCTAssertEqual(result.excludedFlexibleCount, 1)
        XCTAssertEqual(result.scheduledTotal, 0)
    }

    func testFlexibleExclusionOnlyIncludesGoalsActiveInReviewedWeek() {
        let createdLater = habit(.times(3, per: .weekly), created: "2026-08-11")
        let startsLater = habit(Recurrence(frequency: .weekly, start: "2026-08-10", timesPerPeriod: 3))
        let ended = habit(Recurrence(frequency: .weekly, start: "2026-07-01",
                                    end: .on("2026-08-02"), timesPerPeriod: 3))
        let active = habit(.times(3, per: .monthly))
        let result = StatsEngine.weeklyInsight(habits: [createdLater, startsLater, ended, active],
                                               today: "2026-08-12", calendar: calendar)
        XCTAssertEqual(result.excludedFlexibleCount, 1)
        XCTAssertEqual(result.scheduledTotal, 0)
    }

    func testDefaultQuantityTargetCountsPositiveEntries() {
        var value = habit(kind: .quantity, log: ["2026-08-03": 2, "2026-08-04": 3])
        value = habit(kind: .quantity, log: value.log)
        XCTAssertEqual(StatsEngine.weeklyInsight(habits: [value], today: "2026-08-12", calendar: calendar).scheduledDone, 2)
        XCTAssertEqual(value.recurrence.target, nil)
    }

    func testSundayFirstWeekdayUsesSundayToSaturdayLastWeek() {
        var sunday = calendar
        sunday.firstWeekday = 1
        let value = habit(log: ["2026-08-02": 1])
        let result = StatsEngine.weeklyInsight(habits: [value], today: "2026-08-09", calendar: sunday)
        XCTAssertEqual(result.start, "2026-08-02")
        XCTAssertEqual(result.end, "2026-08-08")
    }

    func testTimezoneCalendarDeterminesScheduleAtWeekBoundary() {
        var value = habit(.weekdays([1]), log: ["2026-08-09": 1])
        value.timeZoneIdentifier = "Pacific/Kiritimati"
        let result = StatsEngine.weeklyInsight(habits: [value], today: "2026-08-12", defaultTimeZoneIdentifier: "UTC", calendar: calendar)
        XCTAssertEqual(result.habits.first?.required, 1)
        XCTAssertEqual(result.habits.first?.done, 1)
    }
}
