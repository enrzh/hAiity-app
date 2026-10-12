import XCTest
import SwiftUI
@testable import Haiity

private typealias TodayPage = TodayView<EmptyView>

@MainActor
final class TodayViewTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 2
        return value
    }
    private var now: Date { DayKey.date(from: "2026-10-10", calendar: calendar)!.addingTimeInterval(10 * 3600) }

    private func group(_ habit: Habit, at date: Date? = nil) -> TodayPage.SectionKind? {
        TodayPage.section(for: habit, now: date ?? now, calendar: calendar)
    }

    func testDailyFlexibleAndReminderAreDifferentUnits() {
        let daily = Habit(name: "Read", recurrence: Recurrence())
        let flexible = Habit(name: "Run", recurrence: .times(3, per: .weekly))
        let reminder = Habit(name: "Call", itemType: .reminder,
                             recurrence: Recurrence(frequency: .once, start: "2026-10-10"))
        XCTAssertEqual(group(daily), .scheduled)
        XCTAssertEqual(group(flexible), .flexible)
        XCTAssertEqual(group(reminder), .reminders)
    }

    func testRestFutureEndedAndArchivedAreExcluded() {
        var habit = Habit(name: "Read", recurrence: Recurrence(frequency: .weekly, weekdays: [2]))
        XCTAssertNil(group(habit))
        habit.recurrence = Recurrence(start: "2026-10-11")
        XCTAssertNil(group(habit))
        habit.recurrence = Recurrence(end: .on("2026-10-09"))
        XCTAssertNil(group(habit))
        habit.recurrence = Recurrence()
        habit.archivedAt = "2026-10-10"
        XCTAssertNil(group(habit))
    }

    func testFutureTimeIsIncludedButFutureDayIsNotAndOverdueIsIncluded() {
        var reminder = Habit(name: "Call", itemType: .reminder,
                             recurrence: Recurrence(frequency: .once, start: "2026-10-10"))
        reminder.timeMinutes = 11 * 60
        XCTAssertEqual(group(reminder), .reminders)
        let early = ReminderOccurrenceEngine.state(for: reminder, now: now, calendar: calendar)
        let late = ReminderOccurrenceEngine.state(for: reminder, now: now.addingTimeInterval(7200), calendar: calendar)
        XCTAssertEqual(early.overdueCount, 0)
        XCTAssertEqual(late.overdueCount, 1)
        reminder.recurrence = Recurrence(frequency: .once, start: "2026-10-11")
        XCTAssertNil(group(reminder))
        reminder.recurrence = Recurrence(frequency: .once, start: "2026-10-09")
        XCTAssertEqual(group(reminder), .reminders)
    }

    func testDeclinedIsAnsweredWithoutSuccessfulCompletion() {
        var habit = Habit(name: "Coffee?", kind: .yesNo)
        habit.log["2026-10-10"] = Habit.Answer.no
        XCTAssertEqual(group(habit), .resolved)
        XCTAssertEqual(ScheduledProgress.today(habits: [habit], defaultTimeZoneIdentifier: "UTC", now: now, calendar: calendar).completed, 0)
        var quantity = Habit(name: "Water", recurrence: Recurrence(target: 3))
        quantity.log["2026-10-10"] = 2
        XCTAssertEqual(group(quantity), .scheduled)
    }

    func testVisitKeepsGroupsAndOrderAcrossCompletionUndoAndExternalArrivals() {
        let first = UUID(), second = UUID(), arriving = UUID()
        var order = TodayPage.VisitOrder()
        order.regroup([(first, .scheduled), (second, .resolved)])
        order.reconcile([(first, .resolved), (second, .scheduled), (arriving, .flexible)])
        XCTAssertEqual(order.ids, [first, second, arriving])
        XCTAssertEqual(order.sections[first], .scheduled)
        XCTAssertEqual(order.sections[second], .resolved)
        order.reconcile([(second, .scheduled), (arriving, .flexible)])
        XCTAssertEqual(order.ids, [second, arriving])
        order.regroup([(second, .scheduled), (arriving, .flexible)])
        XCTAssertEqual(order.sections[second], .scheduled)
    }

    func testEarlyConfirmationResolvesOnlyTheCurrentReminderOccurrence() {
        var reminder = Habit(name: "Call", itemType: .reminder,
            recurrence: Recurrence(frequency: .once, start: "2026-10-10"))
        reminder.timeMinutes = 11 * 60
        let pending = PendingReminderCompletion(habitID: reminder.id, day: "2026-10-10")
        XCTAssertEqual(pending.occurrence(for: reminder, now: now, calendar: calendar)?.dueDate,
            now.addingTimeInterval(3600))
        reminder.timeMinutes = 12 * 60
        XCTAssertEqual(pending.occurrence(for: reminder, now: now, calendar: calendar)?.dueDate,
            now.addingTimeInterval(7200), "confirmation uses the current appointment clock")
        reminder.recurrence = Recurrence(frequency: .once, start: "2026-10-11")
        XCTAssertNil(pending.occurrence(for: reminder, now: now, calendar: calendar))
        reminder.recurrence = Recurrence(frequency: .once, start: "2026-10-10")
        reminder.itemType = .habit
        XCTAssertNil(pending.occurrence(for: reminder, now: now, calendar: calendar))
        reminder.itemType = .reminder
        reminder.archivedAt = "2026-10-10"
        XCTAssertNil(pending.occurrence(for: reminder, now: now, calendar: calendar))
        reminder.archivedAt = nil
        reminder.log["2026-10-10"] = 1
        XCTAssertNil(pending.occurrence(for: reminder, now: now, calendar: calendar))
    }
}
