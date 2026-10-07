import XCTest
@testable import Haiity

@MainActor
final class CreationProductTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "de_DE")
        value.timeZone = TimeZone(identifier: "Europe/Berlin")!
        value.firstWeekday = 2
        return value
    }

    private var today: Date {
        DayKey.date(from: "2026-10-05", calendar: calendar)!
    }

    private func roundTrip(_ habit: Habit) throws -> Habit {
        try JSONDecoder().decode(Habit.self, from: JSONEncoder().encode(habit))
    }

    func testProductDefaultsAreDailyHabitAndOnceReminderWithoutChangingGenericDraft() {
        let habit = RecurrenceDraft(itemType: .habit, today: today, calendar: calendar)
        let reminder = RecurrenceDraft(itemType: .reminder, today: today, calendar: calendar)
        XCTAssertEqual(habit.frequency, .daily)
        XCTAssertEqual(habit.recurrence(calendar: calendar).start, "2026-10-05")
        XCTAssertFalse(habit.hasTime)
        XCTAssertEqual(reminder.frequency, .once)
        XCTAssertEqual(reminder.recurrence(calendar: calendar).occurrences(
            in: "2026-10-05"..."2026-10-12", calendar: calendar), ["2026-10-05"])
        XCTAssertEqual(RecurrenceDraft(today: today, calendar: calendar).frequency, .once)
    }

    func testRepeatChoiceChangesOnlyScheduleAndRetainsAppointmentTime() throws {
        for type in HabitItemType.allCases {
            var draft = RecurrenceDraft(itemType: type, today: today, calendar: calendar)
            draft.hasTime = true
            draft.time = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: today)!
            var habit = Habit(name: "Read", itemType: type)
            habit.log = ["2026-10-04": 1]
            for enabled in [false, true, false] {
                draft.setRepeats(enabled, calendar: calendar)
                habit.recurrence = draft.recurrence(calendar: calendar)
                habit.timeMinutes = draft.timeMinutes(calendar: calendar)
                let saved = try roundTrip(habit)
                XCTAssertEqual(saved.itemType, type)
                XCTAssertEqual(saved.recurrence.frequency, enabled ? .daily : .once)
                XCTAssertEqual(saved.timeMinutes, 510)
                XCTAssertEqual(saved.log, ["2026-10-04": 1])
            }
        }
    }

    func testLoadingOnceKeepsBothSavedItemTypesAndTheirHistory() throws {
        for type in HabitItemType.allCases {
            var habit = Habit(name: "Read", itemType: type,
                              recurrence: Recurrence(frequency: .once, start: "2026-10-05"))
            habit.log = ["2026-10-04": 1]
            let draft = RecurrenceDraft(habit.recurrence, today: today, calendar: calendar)
            habit.recurrence = draft.recurrence(calendar: calendar)
            XCTAssertEqual(try roundTrip(habit), habit)
        }
    }

    func testFlexibleWeeklyCreationRoundTripsAndCountsAnyThreeDays() throws {
        var draft = RecurrenceDraft(itemType: .habit, today: today, calendar: calendar)
        draft.selectFrequency(.weekly, calendar: calendar)
        draft.setFlexibleWeek(true, calendar: calendar)
        draft.times = 3
        var habit = Habit(name: "Run", recurrence: draft.recurrence(calendar: calendar))
        habit.createdAt = "2026-10-05"
        habit.log = ["2026-10-05": 1, "2026-10-07": 1]
        XCTAssertFalse(GoalEngine.periodSatisfied(habit: habit, day: "2026-10-11",
                                                  today: "2026-10-11", calendar: calendar))
        habit.log["2026-10-10"] = 1
        let saved = try roundTrip(habit)
        let reloaded = RecurrenceDraft(saved.recurrence, today: today, calendar: calendar)
        XCTAssertEqual(reloaded.recurrence(calendar: calendar), habit.recurrence)
        XCTAssertEqual(saved.recurrence.timesPerPeriod, 3)
        XCTAssertTrue(saved.recurrence.weekdays.isEmpty)
        XCTAssertTrue(GoalEngine.periodSatisfied(habit: saved, day: "2026-10-11",
                                                 today: "2026-10-11", calendar: calendar))
        XCTAssertEqual(GoalEngine.streak(habit: saved, today: "2026-10-11", calendar: calendar), 1)
    }

    func testFlexibleChoiceIsExplicitAndTurningItOffRestoresAScheduledDay() {
        let rule = Recurrence.times(3, per: .weekly, weekdays: [3])
        var draft = RecurrenceDraft(rule, today: today, calendar: calendar)
        XCTAssertEqual(draft.weekdays, [3])
        draft.setFlexibleWeek(true, calendar: calendar)
        XCTAssertTrue(draft.weekdays.isEmpty)
        XCTAssertEqual(draft.recurrence(calendar: calendar).timesPerPeriod, 3)
        draft.setFlexibleWeek(false, calendar: calendar)
        XCTAssertNil(draft.recurrence(calendar: calendar).timesPerPeriod)
        XCTAssertEqual(draft.weekdays, [2])
        XCTAssertFalse(draft.hasStart)
        XCTAssertEqual(draft.times, 3)
    }

    func testFlexibleWeekNotificationsKeepIndependentClocksAndStopWhenQuotaIsMet() throws {
        var draft = RecurrenceDraft(itemType: .habit, today: today, calendar: calendar)
        draft.selectFrequency(.weekly, calendar: calendar)
        draft.setFlexibleWeek(true, calendar: calendar)
        draft.times = 3
        var habit = Habit(name: "Run", timeMinutes: 8 * 60,
                          recurrence: draft.recurrence(calendar: calendar),
                          notificationTimes: [9 * 60, 17 * 60])
        habit.createdAt = "2026-10-05"
        habit.log = ["2026-10-05": 1, "2026-10-06": 1]
        let now = calendar.date(bySettingHour: 7, minute: 0, second: 0,
                                of: DayKey.date(from: "2026-10-07", calendar: calendar)!)!
        let saved = try roundTrip(habit)
        let plans = Reminders.habitPlans(habits: [saved], now: now, calendar: calendar)
        XCTAssertEqual(plans.filter {
            Reminders.habitTarget(for: $0.identifier)?.day == "2026-10-07"
        }.map { $0.dateMatching.hour }, [9, 17])
        XCTAssertEqual(saved.timeMinutes, 8 * 60)
        habit.log["2026-10-07"] = 1
        let completed = Reminders.habitPlans(habits: [habit], now: now, calendar: calendar)
        XCTAssertFalse(completed.contains {
            guard let day = Reminders.habitTarget(for: $0.identifier)?.day else { return false }
            return day <= "2026-10-11"
        })
        XCTAssertTrue(completed.contains {
            Reminders.habitTarget(for: $0.identifier)?.day == "2026-10-12"
        })
    }

    func testLegacyFlexibleAndSilentSchedulesAreUnchangedByLoading() {
        for rule in [Recurrence.times(3, per: .weekly, weekdays: [3]),
                     .times(5, per: .monthly), .times(20, per: .yearly),
                     .weekdays([], end: .on("2026-12-31")),
                     .monthly(.lastDayOfMonth, interval: 2, end: .on("2026-12-31"))] {
            let draft = RecurrenceDraft(rule, timeMinutes: 8 * 60,
                                        today: today, calendar: calendar)
            XCTAssertEqual(draft.recurrence(calendar: calendar), rule)
            XCTAssertEqual(draft.timeMinutes(calendar: calendar), 8 * 60)
        }
    }

    func testDisabledHiddenNotificationTimesSurviveReloadAndReenable() throws {
        var habit = Habit(name: "Read", timeMinutes: 8 * 60,
                          notificationMode: .off, notificationTimes: [9 * 60, 17 * 60])
        habit = try roundTrip(habit)
        XCTAssertEqual(habit.notificationTimes, [9 * 60, 17 * 60])
        XCTAssertEqual(habit.timeMinutes, 8 * 60)
        let now = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: today)!
        XCTAssertTrue(Reminders.habitPlans(habits: [habit], now: now, calendar: calendar).isEmpty)
        habit.notificationMode = .standard
        XCTAssertEqual(Reminders.habitPlans(habits: [habit], now: now, calendar: calendar)
            .filter { Reminders.habitTarget(for: $0.identifier)?.day == "2026-10-05" }
            .map { $0.dateMatching.hour }, [9, 17])
    }
}
