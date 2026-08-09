import XCTest
@testable import Haiity

/// Der eine Satz, der im Editor über den Knöpfen steht. Er ist der einzige
/// Ort, an dem ein Mensch nachlesen kann, was er da gerade gebaut hat —
/// deshalb steht er hier Wort für Wort fest.
final class RecurrenceTextTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        c.firstWeekday = 2
        return c
    }()

    private func text(_ recurrence: Recurrence) -> String {
        RecurrenceText.summary(recurrence, calendar: calendar)
    }

    func testDaily() {
        XCTAssertEqual(text(.daily), "Jeden Tag")
        XCTAssertEqual(text(Recurrence(frequency: .daily, interval: 2)), "Alle 2 Tage")
    }

    func testWeekdaySets() {
        XCTAssertEqual(text(.weekdays([2, 5])), "Jeden Montag und Donnerstag")
        XCTAssertEqual(text(.weekdays([2, 4, 6])), "Jeden Montag, Mittwoch und Freitag")
        XCTAssertEqual(text(.weekdays([1])), "Jeden Sonntag")
    }

    /// Die Reihenfolge folgt dem Kalender des Nutzers, nicht der Zahl:
    /// beginnt die Woche am Sonntag, steht der Sonntag vorn.
    func testWeekdayOrderFollowsFirstWeekday() {
        var sunday = calendar
        sunday.firstWeekday = 1
        XCTAssertEqual(RecurrenceText.weekdayList([2, 1], calendar: calendar),
                       "Montag und Sonntag")
        XCTAssertEqual(RecurrenceText.weekdayList([2, 1], calendar: sunday),
                       "Sonntag und Montag")
    }

    func testWeeklyInterval() {
        XCTAssertEqual(text(.weekdays([2, 5], interval: 2)), "Jeden 2. Montag und Donnerstag")
    }

    func testWeeklyWithoutDaysIsHonestAboutIt() {
        XCTAssertEqual(text(Recurrence(frequency: .weekly)), "Keine Termine")
    }

    func testMonthly() {
        XCTAssertEqual(text(.monthly(.dayOfMonth(15))), "Am 15. jedes Monats")
        XCTAssertEqual(text(.monthly(.lastDayOfMonth)), "Am letzten Tag des Monats")
        XCTAssertEqual(text(.monthly(.nthWeekday(nth: 3, weekday: 3))), "Am 3. Dienstag im Monat")
        XCTAssertEqual(text(.monthly(.nthWeekday(nth: Recurrence.DayRule.last, weekday: 6))),
                       "Am letzten Freitag im Monat")
    }

    func testMonthlyInterval() {
        XCTAssertEqual(text(.monthly(.dayOfMonth(15), interval: 2)), "Alle 2 Monate am 15.")
        XCTAssertEqual(text(.monthly(.nthWeekday(nth: Recurrence.DayRule.last, weekday: 6), interval: 3)),
                       "Alle 3 Monate am letzten Freitag")
        XCTAssertEqual(text(.monthly(.lastDayOfMonth, interval: 2)), "Alle 2 Monate am letzten Tag")
    }

    func testYearly() {
        XCTAssertEqual(text(.yearly(month: 3, .dayOfMonth(15))), "Jedes Jahr am 15. März")
        XCTAssertEqual(text(.yearly(month: 8, .nthWeekday(nth: 3, weekday: 3), interval: 2)),
                       "Alle 2 Jahre am 3. Dienstag im August")
        XCTAssertEqual(text(.yearly(month: 2, .lastDayOfMonth)),
                       "Jedes Jahr am letzten Tag im Februar")
    }

    func testFlexibleGoals() {
        XCTAssertEqual(text(.times(3, per: .weekly)), "3× pro Woche")
        XCTAssertEqual(text(.times(1, per: .weekly, weekdays: [3])),
                       "Einmal pro Woche, gedacht am Dienstag")
        XCTAssertEqual(text(.times(5, per: .monthly, interval: 2)), "5× alle 2 Monate")
        XCTAssertEqual(text(.times(4, per: .yearly)), "4× pro Jahr")
    }

    func testEndClause() {
        XCTAssertEqual(text(Recurrence(frequency: .daily, end: .on("2026-12-31"))),
                       "Jeden Tag, bis 31.12.2026")
        XCTAssertEqual(text(Recurrence(frequency: .weekly, weekdays: [2],
                                       start: "2026-08-03", end: .after(10))),
                       "Jeden Montag, endet nach 10 Terminen")
        XCTAssertEqual(text(Recurrence(frequency: .weekly, weekdays: [2],
                                       start: "2026-08-03", end: .after(1))),
                       "Jeden Montag, endet nach 1 Termin")
    }
}

/// Der Weg Regel -> Formular -> Regel. Das Formular hat mehr Knöpfe als das
/// Modell Felder; genau in dieser Übersetzung stecken die Fehler, die man
/// sonst erst im Simulator sieht.
final class RecurrenceDraftTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        c.firstWeekday = 2
        return c
    }()

    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 9))!
    }

    private func roundTrip(_ recurrence: Recurrence) -> Recurrence {
        RecurrenceDraft(recurrence, today: today, calendar: calendar)
            .recurrence(calendar: calendar)
    }

    func testEveryShapeSurvivesTheForm() {
        let shapes: [Recurrence] = [
            Recurrence(frequency: .daily, start: "2026-08-09"),
            Recurrence(frequency: .daily, interval: 3, start: "2026-08-09"),
            .weekdays([2, 4, 6], start: "2026-08-09"),
            .weekdays([2], interval: 2, start: "2026-08-03"),
            .times(3, per: .weekly, start: "2026-08-09"),
            .times(1, per: .weekly, weekdays: [3], start: "2026-08-09"),
            .times(5, per: .monthly, interval: 2, start: "2026-08-09"),
            .monthly(.dayOfMonth(15), start: "2026-08-09"),
            .monthly(.lastDayOfMonth, start: "2026-08-09"),
            .monthly(.nthWeekday(nth: Recurrence.DayRule.last, weekday: 6), start: "2026-08-09"),
            .yearly(month: 3, .dayOfMonth(15), start: "2026-08-09"),
            Recurrence(frequency: .daily, start: "2026-08-09", end: .on("2026-12-31")),
            Recurrence(frequency: .daily, start: "2026-08-09", end: .after(20)),
            Recurrence(frequency: .daily, start: "2026-08-09", target: 4),
        ]
        for shape in shapes {
            XCTAssertEqual(roundTrip(shape), shape, "\(shape)")
        }
    }

    /// Ein migriertes Alt-Ziel hat KEINEN Start — und darf beim Bearbeiten
    /// auch keinen bekommen, sonst wären alle Tage davor plötzlich
    /// terminfrei und jede Quote eine andere.
    func testEditingALegacyGoalDoesNotInventAStart() {
        let legacy = Recurrence.from(legacy: LegacyGoal(restDays: [1, 7]))
        var draft = RecurrenceDraft(legacy, today: today, calendar: calendar)
        XCTAssertFalse(draft.hasStart)
        XCTAssertEqual(draft.recurrence(calendar: calendar), legacy)
        // Wer den Schalter umlegt, bekommt einen — aber nur dann.
        draft.hasStart = true
        XCTAssertEqual(draft.recurrence(calendar: calendar).start, "2026-08-09")
    }

    /// Umschalten verliert nichts: der 3. Dienstag steht nach einem Ausflug
    /// zu „wöchentlich" noch da.
    func testSwitchingFrequencyKeepsTheOtherFieldsAround() {
        var draft = RecurrenceDraft(.monthly(.nthWeekday(nth: 3, weekday: 3), start: "2026-08-09"),
                                    today: today, calendar: calendar)
        draft.frequency = .weekly
        draft.normalize(calendar: calendar)
        draft.frequency = .monthly
        draft.normalize(calendar: calendar)
        XCTAssertEqual(draft.recurrence(calendar: calendar).rule, .nthWeekday(nth: 3, weekday: 3))
    }

    /// Ein neues Habit startet heute, täglich, ohne Ende — und mit dem
    /// heutigen Wochentag vorgewählt, damit „wöchentlich" nie auf einer
    /// leeren Tagesmenge landet.
    func testFreshDraftDefaults() {
        var draft = RecurrenceDraft(today: today, calendar: calendar)
        XCTAssertEqual(draft.recurrence(calendar: calendar),
                       Recurrence(frequency: .daily, start: "2026-08-09"))
        draft.frequency = .weekly
        draft.normalize(calendar: calendar)
        XCTAssertEqual(draft.weekdays, [1])          // 09.08.2026 ist ein Sonntag
        XCTAssertEqual(draft.summary(calendar: calendar), "Jeden Sonntag")
    }

    /// „Täglich" kennt kein Zählziel — das IST das Mengenziel.
    func testDailyDropsTheFlexibleGoal() {
        var draft = RecurrenceDraft(today: today, calendar: calendar)
        draft.flexible = true
        draft.frequency = .daily
        draft.normalize(calendar: calendar)
        XCTAssertFalse(draft.flexible)
        XCTAssertNil(draft.recurrence(calendar: calendar).timesPerPeriod)
    }

    func testNormalizeClampsOutOfRangeValues() {
        var draft = RecurrenceDraft(today: today, calendar: calendar)
        draft.frequency = .weekly
        draft.interval = 0
        draft.times = 99
        draft.endCount = 0
        draft.normalize(calendar: calendar)
        XCTAssertEqual(draft.interval, 1)
        XCTAssertEqual(draft.times, 7)
        XCTAssertEqual(draft.endCount, 1)
    }
}
