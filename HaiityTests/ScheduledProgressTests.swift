import XCTest
@testable import Haiity

final class ScheduledProgressTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        return calendar
    }
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 12))!
    }

    func testCountsScheduledHabitsAndKeepsFlexibleGoalsSeparate() {
        var fixed = Habit(name: "Reading")
        fixed.log["2026-09-07"] = 1
        var flexible = Habit(name: "Walk", recurrence: Recurrence(frequency: .weekly,
            start: "2026-09-07", timesPerPeriod: 1))
        flexible.log["2026-09-07"] = 1
        var archived = fixed
        archived.archivedAt = "2026-09-06"
        let reminder = Habit(name: "Call", itemType: .reminder)
        let free = Habit(name: "Tuesday", recurrence: .weekdays([3]))
        let progress = ScheduledProgress.today(habits: [fixed, flexible, archived, reminder, free],
            defaultTimeZoneIdentifier: nil, now: now, calendar: calendar)
        XCTAssertEqual(progress, .init(completed: 1, scheduled: 1, flexibleCompleted: 1, flexible: 1))
        let widget = WidgetLogic.progress(habits: [fixed, flexible, archived, reminder, free],
            defaultTimeZoneIdentifier: nil, now: now, calendar: calendar)
        XCTAssertEqual(widget.met, progress.completed)
        XCTAssertEqual(widget.due, progress.scheduled)
    }

    func testFlexibleProgressIgnoresReminderWeekdayAndHonorsActiveBounds() {
        var flexible = Habit(name: "Walk", recurrence: Recurrence(frequency: .weekly,
            weekdays: [3], start: "2026-09-01", timesPerPeriod: 1))
        flexible.log["2026-09-07"] = 1
        let future = Habit(name: "Future", recurrence: Recurrence(frequency: .weekly,
            start: "2026-09-08", timesPerPeriod: 1))
        let ended = Habit(name: "Ended", recurrence: Recurrence(frequency: .weekly,
            start: "2026-09-01", end: .on("2026-09-06"), timesPerPeriod: 1))
        let progress = ScheduledProgress.today(habits: [flexible, future, ended],
            defaultTimeZoneIdentifier: nil, now: now, calendar: calendar)
        XCTAssertEqual(progress, .init(completed: 0, scheduled: 0, flexibleCompleted: 1, flexible: 1))
    }

    func testQuantityAndDeclinedAnswersDoNotInflateCompletion() {
        var water = Habit(name: "Water", recurrence: Recurrence(target: 3), kind: .quantity)
        water.log["2026-09-07"] = 2
        var answer = Habit(name: "Question", kind: .yesNo)
        answer.log["2026-09-07"] = Habit.Answer.no
        XCTAssertEqual(ScheduledProgress.today(habits: [water, answer],
            defaultTimeZoneIdentifier: nil, now: now, calendar: calendar).completed, 0)
        water.log["2026-09-07"] = 3
        answer.log["2026-09-07"] = Habit.Answer.yes
        XCTAssertEqual(ScheduledProgress.today(habits: [water, answer],
            defaultTimeZoneIdentifier: nil, now: now, calendar: calendar).completed, 2)
        water.log.removeValue(forKey: "2026-09-07")
        XCTAssertEqual(ScheduledProgress.today(habits: [water, answer],
            defaultTimeZoneIdentifier: nil, now: now, calendar: calendar).completed, 1)
    }

    func testTodayFilterPreservesOrderWhenAnItemCompletes() {
        var habits = [Habit(name: "First"), Habit(name: "Second"), Habit(name: "Third")]
        let filter = HabitListFilter(todayOnly: true)
        let before = habits.filter { filter.matches($0, defaultTimeZoneIdentifier: nil, now: now, base: calendar) }.map(\.id)
        habits[1].log["2026-09-07"] = 1
        let after = habits.filter { filter.matches($0, defaultTimeZoneIdentifier: nil, now: now, base: calendar) }.map(\.id)
        XCTAssertEqual(before, after)
    }

    func testMidnightUsesHabitTimezoneAndRestDayHasNoPercentage() {
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 0, minute: 30))!
        var habit = Habit(name: "Monday", recurrence: .weekdays([2]))
        habit.timeZoneIdentifier = "America/Los_Angeles"
        habit.log["2026-09-07"] = 1
        let progress = ScheduledProgress.today(habits: [habit], defaultTimeZoneIdentifier: nil,
            now: midnight, calendar: calendar)
        XCTAssertEqual(progress.completed, 1)
        XCTAssertEqual(progress.scheduled, 1)
        XCTAssertEqual(ScheduledProgress.today(habits: [], defaultTimeZoneIdentifier: nil,
            now: now, calendar: calendar).fraction, 0)
    }
}
