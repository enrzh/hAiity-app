import XCTest
@testable import Haiity

final class ReminderOccurrenceTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = Locale(identifier: "de_DE")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()

    func testExistingReminderDefaultsToContinuingWhileIncomplete() throws {
        let original = Habit(name: "Tabletten", itemType: .reminder)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any]
        )
        var legacy = object
        legacy.removeValue(forKey: "repeatsWhileIncomplete")

        let data = try JSONSerialization.data(withJSONObject: legacy)

        XCTAssertTrue(try JSONDecoder().decode(Habit.self, from: data).repeatsWhileIncomplete)
    }

    func testDisabledContinuationRoundTrips() throws {
        var reminder = Habit(name: "Tabletten", itemType: .reminder)
        reminder.repeatsWhileIncomplete = false

        let decoded = try JSONDecoder().decode(Habit.self, from: JSONEncoder().encode(reminder))

        XCTAssertFalse(decoded.repeatsWhileIncomplete)
    }

    func testFutureOccurrenceUsesScheduledDayAndTime() {
        var reminder = fixture(createdAt: "2026-08-16", timeMinutes: 18 * 60)
        reminder.recurrence = .weekdays([2], start: "2026-08-16")

        let state = ReminderOccurrenceEngine.state(
            for: reminder,
            now: date("2026-08-16", minutes: 12 * 60),
            calendar: calendar
        )

        XCTAssertEqual(state.actionable?.day, "2026-08-17")
        XCTAssertEqual(state.actionable?.dueDate, date("2026-08-17", minutes: 18 * 60))
        XCTAssertEqual(state.overdueCount, 0)
    }

    func testContinuationKeepsOldestOverdueAndCountsBacklog() {
        let reminder = fixture(createdAt: "2026-08-14", timeMinutes: 9 * 60)

        let state = ReminderOccurrenceEngine.state(
            for: reminder,
            now: date("2026-08-16", minutes: 12 * 60),
            calendar: calendar
        )

        XCTAssertEqual(state.actionable?.day, "2026-08-14")
        XCTAssertEqual(state.overdueCount, 3)
    }

    func testDisabledContinuationKeepsOneOverdueOccurrence() {
        var reminder = fixture(createdAt: "2026-08-14", timeMinutes: 9 * 60)
        reminder.repeatsWhileIncomplete = false

        let state = ReminderOccurrenceEngine.state(
            for: reminder,
            now: date("2026-08-16", minutes: 12 * 60),
            calendar: calendar
        )

        XCTAssertEqual(state.actionable?.day, "2026-08-14")
        XCTAssertEqual(state.overdueCount, 1)
    }

    func testCompletionCursorAdvancesPastMissedOccurrencesWhenContinuationIsDisabled() {
        var reminder = fixture(createdAt: "2026-08-14", timeMinutes: 9 * 60)
        reminder.repeatsWhileIncomplete = false
        reminder.log["2026-08-14"] = 1
        reminder.reminderCursor = "2026-08-17"

        let state = ReminderOccurrenceEngine.state(
            for: reminder,
            now: date("2026-08-16", minutes: 12 * 60),
            calendar: calendar
        )

        XCTAssertEqual(state.actionable?.day, "2026-08-17")
    }

    func testGermanOccurrenceLabelsUseActionableDatesInsteadOfRecurrenceText() {
        let locale = Locale(identifier: "de_DE")

        XCTAssertEqual(label("2026-08-16", 18 * 60, now: "2026-08-16", 12 * 60,
                             locale: locale),
                       "Heute, 18:00")
        XCTAssertEqual(label("2026-08-17", 9 * 60, now: "2026-08-16", 12 * 60,
                             locale: locale),
                       "Morgen, 09:00")
        XCTAssertEqual(label("2026-08-20", 9 * 60, now: "2026-08-16", 12 * 60,
                             locale: locale),
                       "20.08.2026, 09:00")
        XCTAssertEqual(label("2026-08-15", 9 * 60, now: "2026-08-16", 12 * 60,
                             locale: locale),
                       "Überfällig · 15.08.2026, 09:00")
    }

    func testCompletionCursorUsesTheFirstOccurrenceAfterTheCompletedDueTimeAndNow() {
        let reminder = fixture(createdAt: "2026-08-14", timeMinutes: 9 * 60)
        let overdue = ReminderOccurrence(day: "2026-08-14",
                                         dueDate: date("2026-08-14", minutes: 9 * 60))
        let early = ReminderOccurrence(day: "2026-08-17",
                                       dueDate: date("2026-08-17", minutes: 9 * 60))

        XCTAssertEqual(ReminderOccurrenceEngine.cursorAfterCompleting(
            overdue, reminder: reminder,
            now: date("2026-08-16", minutes: 12 * 60), calendar: calendar
        ), "2026-08-17")
        XCTAssertEqual(ReminderOccurrenceEngine.cursorAfterCompleting(
            early, reminder: reminder,
            now: date("2026-08-16", minutes: 12 * 60), calendar: calendar
        ), "2026-08-18")
    }

    func testOlderOpenOccurrencesBecomeExplicitlyMissedWhenTheNextOneIsDue() {
        let reminder = fixture(createdAt: "2026-08-14", timeMinutes: 9 * 60)

        let missed = ReminderOccurrenceEngine.missedDays(
            for: reminder,
            now: date("2026-08-16", minutes: 12 * 60),
            calendar: calendar)

        XCTAssertEqual(missed, ["2026-08-14", "2026-08-15"])
    }

    func testMissedOccurrenceIsStoredSeparatelyFromTheLog() throws {
        var reminder = fixture(createdAt: "2026-08-14", timeMinutes: 9 * 60)
        reminder.missedDays = ["2026-08-14"]

        let decoded = try JSONDecoder().decode(Habit.self,
                                                from: JSONEncoder().encode(reminder))

        XCTAssertEqual(decoded.missedDays, ["2026-08-14"])
        XCTAssertNil(decoded.log["2026-08-14"])
    }

    private func fixture(createdAt: String, timeMinutes: Int) -> Habit {
        var reminder = Habit(name: "Tabletten", itemType: .reminder,
                             timeMinutes: timeMinutes, recurrence: .daily)
        reminder.createdAt = createdAt
        return reminder
    }

    private func date(_ day: String, minutes: Int) -> Date {
        let start = DayKey.date(from: day, calendar: calendar)!
        return calendar.date(byAdding: .minute, value: minutes, to: start)!
    }

    private func label(_ dueDay: String, _ dueMinutes: Int,
                       now nowDay: String, _ nowMinutes: Int,
                       locale: Locale) -> String {
        ReminderOccurrenceText.label(
            for: ReminderOccurrence(day: dueDay,
                                    dueDate: date(dueDay, minutes: dueMinutes)),
            includesTime: true,
            now: date(nowDay, minutes: nowMinutes),
            calendar: calendar,
            locale: locale
        )
    }
}
