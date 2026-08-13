import XCTest
@testable import Haiity

/// Die Abbildung Habit -> Kalender-Termin (`CalendarEventPlan`) — pur, ohne
/// EventKit: welche Habits einen Termin bekommen, wann er beginnt, wie er
/// sich wiederholt und wann er endet.
final class CalendarEventPlanTests: XCTestCase {
    /// So, 09.08.2026 als „heute" — dieselbe Fixture-Wochenlage wie überall.
    private let today = "2026-08-09"

    func testDailyHabitWithTimeBecomesTimedDailyEvent() {
        let habit = Habit(name: "Lesen", emoji: "📚", timeMinutes: 19 * 60,
                          recurrence: .daily)
        let plan = CalendarEventPlan(habit: habit, today: today)
        XCTAssertEqual(plan?.title, "📚 Lesen")
        XCTAssertEqual(plan?.firstDay, today)
        XCTAssertEqual(plan?.minutes, 19 * 60)
        XCTAssertEqual(plan?.frequency, .daily)
        XCTAssertEqual(plan?.interval, 1)
    }

    func testHabitWithoutTimeIsAllDay() {
        let plan = CalendarEventPlan(habit: Habit(name: "Lesen", recurrence: .daily),
                                     today: today)
        XCTAssertNil(plan?.minutes)
    }

    func testPlannedSessionDurationSetsEventLength() {
        var habit = Habit(name: "Sport", timeMinutes: 7 * 60, recurrence: .daily)
        habit.durationMinutes = 45
        XCTAssertEqual(CalendarEventPlan(habit: habit, today: today)?.durationMinutes, 45)
        XCTAssertEqual(CalendarEventPlan(habit: Habit(name: "X", timeMinutes: 60,
                                                      recurrence: .daily),
                                         today: today)?.durationMinutes, 30)
    }

    func testWeekdayHabitStartsOnItsNextAgreedDay() {
        // Dienstage (3); heute ist Sonntag -> erster Termin Di, 11.08.
        let habit = Habit(name: "Yoga", recurrence: .weekdays([3]))
        let plan = CalendarEventPlan(habit: habit, today: today)
        XCTAssertEqual(plan?.firstDay, "2026-08-11")
        XCTAssertEqual(plan?.frequency, .weekly)
        XCTAssertEqual(plan?.weekdays, [3])
    }

    /// Flexible Ziele MIT Verabredung: Wochenmuster an genau diesen Tagen.
    func testFlexibleWithAgreedWeekdaysBecomesWeeklyPattern() {
        let habit = Habit(name: "Schwimmen",
                          recurrence: .times(2, per: .weekly, weekdays: [2, 5]))
        let plan = CalendarEventPlan(habit: habit, today: today)
        XCTAssertEqual(plan?.frequency, .weekly)
        XCTAssertEqual(plan?.weekdays, [2, 5])
        XCTAssertEqual(plan?.firstDay, "2026-08-10")
    }

    /// Flexible Ziele OHNE Verabredung haben keinen Termin, den man
    /// eintragen könnte.
    func testFlexibleWithoutWeekdaysHasNoPlan() {
        let habit = Habit(name: "Irgendwann",
                          recurrence: .times(3, per: .weekly))
        XCTAssertNil(CalendarEventPlan(habit: habit, today: today))
    }

    func testArchivedHabitsHaveNoPlan() {
        var habit = Habit(name: "Alt", recurrence: .daily)
        habit.archivedAt = "2026-08-01"
        XCTAssertNil(CalendarEventPlan(habit: habit, today: today))
    }

    func testMonthlyDayRuleCarriesDayOfMonth() {
        let habit = Habit(name: "Miete",
                          recurrence: .monthly(.dayOfMonth(1)))
        let plan = CalendarEventPlan(habit: habit, today: today)
        XCTAssertEqual(plan?.frequency, .monthly)
        XCTAssertEqual(plan?.daysOfMonth, [1])
        XCTAssertEqual(plan?.firstDay, "2026-09-01")
    }

    func testLastDayOfMonthMapsToMinusOne() {
        let habit = Habit(name: "Rückblick",
                          recurrence: .monthly(.lastDayOfMonth))
        XCTAssertEqual(CalendarEventPlan(habit: habit, today: today)?.daysOfMonth, [-1])
    }

    func testEndDatePassesThrough() {
        let habit = Habit(name: "Kur",
                          recurrence: Recurrence(frequency: .daily,
                                                 end: .on("2026-09-01")))
        XCTAssertEqual(CalendarEventPlan(habit: habit, today: today)?.end, .on("2026-09-01"))
    }

    /// Der Fingerabdruck ändert sich mit dem Sichtbaren — und nur damit.
    func testFingerprintTracksVisibleChanges() {
        let a = CalendarEventPlan(habit: Habit(name: "Lesen", timeMinutes: 19 * 60,
                                               recurrence: .daily), today: today)
        let b = CalendarEventPlan(habit: Habit(name: "Lesen", timeMinutes: 19 * 60,
                                               recurrence: .daily), today: today)
        let c = CalendarEventPlan(habit: Habit(name: "Lesen", timeMinutes: 20 * 60,
                                               recurrence: .daily), today: today)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
