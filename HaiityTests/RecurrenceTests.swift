import XCTest
@testable import Haiity

/// Die Wiederholungsregel selbst: welcher Tag ein Termin ist, was am
/// Monatsende passiert, wie Intervalle ihre Phase halten und wann eine Regel
/// aufhört. Fester Kalender (Berlin, Montag als Wochenanfang), damit die
/// Antworten nicht von den Einstellungen der Maschine abhängen.
///
/// Verifizierte Eckdaten 2026: 03.08. Mo … 09.08. So; Dienstage im August:
/// 4., 11., 18., 25.; Februar hat 28 Tage; Sommerzeit beginnt am 29.03.,
/// endet am 25.10.
final class RecurrenceTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }()

    private func scheduled(_ recurrence: Recurrence, _ day: String) -> Bool {
        recurrence.isScheduled(on: day, calendar: calendar)
    }

    // MARK: – Täglich

    func testDailyIsEveryDay() {
        let r = Recurrence.daily
        XCTAssertTrue(scheduled(r, "2026-08-09"))
        XCTAssertTrue(scheduled(r, "2027-02-01"))
    }

    func testDailyIntervalKeepsItsPhaseFromTheStart() {
        let r = Recurrence(frequency: .daily, interval: 3, start: "2026-08-03")
        XCTAssertTrue(scheduled(r, "2026-08-03"))
        XCTAssertFalse(scheduled(r, "2026-08-04"))
        XCTAssertFalse(scheduled(r, "2026-08-05"))
        XCTAssertTrue(scheduled(r, "2026-08-06"))
        XCTAssertTrue(scheduled(r, "2026-08-09"))
    }

    func testNothingBeforeTheStart() {
        let r = Recurrence(frequency: .daily, start: "2026-08-05")
        XCTAssertFalse(scheduled(r, "2026-08-04"))
        XCTAssertTrue(scheduled(r, "2026-08-05"))
    }

    /// Sommerzeit: der 29.03.2026 hat 23 Stunden, der 25.10.2026 hat 25.
    /// Mit 24-Stunden-Arithmetik verrutschte die Phase genau hier.
    func testIntervalSurvivesDaylightSavingBoundaries() {
        let spring = Recurrence(frequency: .daily, interval: 2, start: "2026-03-27")
        XCTAssertTrue(scheduled(spring, "2026-03-29"))   // Umstellungstag
        XCTAssertFalse(scheduled(spring, "2026-03-30"))
        XCTAssertTrue(scheduled(spring, "2026-03-31"))
        let autumn = Recurrence(frequency: .daily, interval: 2, start: "2026-10-23")
        XCTAssertTrue(scheduled(autumn, "2026-10-25"))
        XCTAssertFalse(scheduled(autumn, "2026-10-26"))
        XCTAssertTrue(scheduled(autumn, "2026-10-27"))
    }

    // MARK: – Wöchentlich

    func testWeekdaySetMatchesExactlyThoseDays() {
        let r = Recurrence.weekdays([2, 4, 6])   // Mo, Mi, Fr
        XCTAssertTrue(scheduled(r, "2026-08-03"))
        XCTAssertFalse(scheduled(r, "2026-08-04"))
        XCTAssertTrue(scheduled(r, "2026-08-05"))
        XCTAssertTrue(scheduled(r, "2026-08-07"))
        XCTAssertFalse(scheduled(r, "2026-08-09"))
    }

    func testEmptyWeekdaySetSchedulesNothing() {
        let r = Recurrence(frequency: .weekly)
        for offset in 0..<7 {
            let day = DayKey.shifted("2026-08-03", by: offset, calendar: calendar)!
            XCTAssertFalse(scheduled(r, day), day)
        }
    }

    func testEveryOtherWeekCountsWeeksNotDays() {
        let r = Recurrence.weekdays([2, 5], interval: 2, start: "2026-08-03")
        XCTAssertTrue(scheduled(r, "2026-08-03"))    // Mo, Startwoche
        XCTAssertTrue(scheduled(r, "2026-08-06"))    // Do, Startwoche
        XCTAssertFalse(scheduled(r, "2026-08-10"))   // Mo, ausgelassene Woche
        XCTAssertTrue(scheduled(r, "2026-08-17"))    // Mo, wieder dran
        XCTAssertTrue(scheduled(r, "2026-08-20"))    // Do
    }

    /// Der Jahreswechsel darf keine Phase verschieben — über
    /// Wochennummern gerechnet risse sie hier (KW 53 -> KW 1).
    func testEveryOtherWeekAcrossTheYearBoundary() {
        let r = Recurrence.weekdays([2], interval: 2, start: "2026-12-21")
        XCTAssertTrue(scheduled(r, "2026-12-21"))
        XCTAssertFalse(scheduled(r, "2026-12-28"))
        XCTAssertTrue(scheduled(r, "2027-01-04"))
        XCTAssertFalse(scheduled(r, "2027-01-11"))
    }

    /// Ein flexibles Ziel benennt nur die PERIODE: jeder Tag einer aktiven
    /// Woche ist ein möglicher Termin.
    func testFlexibleGoalSchedulesEveryDayOfAnActivePeriod() {
        let r = Recurrence.times(3, per: .weekly, interval: 2, start: "2026-08-03")
        XCTAssertTrue(scheduled(r, "2026-08-04"))
        XCTAssertTrue(scheduled(r, "2026-08-09"))
        XCTAssertFalse(scheduled(r, "2026-08-11"))   // ausgelassene Woche
        XCTAssertTrue(scheduled(r, "2026-08-18"))
    }

    // MARK: – Monatlich

    func testMonthlyDayOfMonth() {
        let r = Recurrence.monthly(.dayOfMonth(15))
        XCTAssertTrue(scheduled(r, "2026-08-15"))
        XCTAssertTrue(scheduled(r, "2026-09-15"))
        XCTAssertFalse(scheduled(r, "2026-08-16"))
    }

    /// „Am 31." heißt am 31. — Monate ohne 31. fallen aus, der Termin rutscht
    /// NICHT auf den 28. oder 30.
    func testThirtyFirstSkipsMonthsThatDoNotHaveIt() {
        let r = Recurrence.monthly(.dayOfMonth(31))
        XCTAssertTrue(scheduled(r, "2026-01-31"))
        XCTAssertTrue(scheduled(r, "2026-03-31"))
        XCTAssertFalse(scheduled(r, "2026-02-28"))
        XCTAssertFalse(scheduled(r, "2026-04-30"))
        XCTAssertEqual(r.nextOccurrence(after: "2026-01-31", calendar: calendar), "2026-03-31")
    }

    func testLastDayOfMonthFindsEveryLength() {
        let r = Recurrence.monthly(.lastDayOfMonth)
        XCTAssertTrue(scheduled(r, "2026-02-28"))
        XCTAssertTrue(scheduled(r, "2026-04-30"))
        XCTAssertTrue(scheduled(r, "2026-08-31"))
        XCTAssertFalse(scheduled(r, "2026-08-30"))
    }

    func testLastDayInALeapYearIsTheTwentyNinth() {
        let r = Recurrence.monthly(.lastDayOfMonth)
        XCTAssertTrue(scheduled(r, "2028-02-29"))
        XCTAssertFalse(scheduled(r, "2028-02-28"))
    }

    func testNthWeekday() {
        let r = Recurrence.monthly(.nthWeekday(nth: 3, weekday: 3))   // 3. Dienstag
        XCTAssertTrue(scheduled(r, "2026-08-18"))
        XCTAssertFalse(scheduled(r, "2026-08-11"))
        XCTAssertTrue(scheduled(r, "2026-09-15"))
    }

    /// Der fünfte Dienstag existiert nur in Monaten, die ihn haben — sonst
    /// fällt der Termin aus (kein Ausweichen auf den vierten).
    func testFifthWeekdayOnlyInMonthsThatHaveOne() {
        let r = Recurrence.monthly(.nthWeekday(nth: 5, weekday: 3))
        XCTAssertTrue(scheduled(r, "2026-03-31"))    // fünfter Dienstag
        XCTAssertTrue(scheduled(r, "2026-06-30"))
        XCTAssertFalse(scheduled(r, "2026-08-25"))   // August hat nur vier
        XCTAssertEqual(r.nextOccurrence(after: "2026-06-30", calendar: calendar), "2026-09-29")
    }

    func testLastWeekdayOfMonth() {
        let r = Recurrence.monthly(.nthWeekday(nth: Recurrence.DayRule.last, weekday: 3))
        XCTAssertTrue(scheduled(r, "2026-08-25"))    // letzter Dienstag im August
        XCTAssertFalse(scheduled(r, "2026-08-18"))
        XCTAssertTrue(scheduled(r, "2026-03-31"))    // dort ist der letzte auch der fünfte
    }

    func testMonthlyIntervalKeepsItsPhase() {
        let r = Recurrence.monthly(.dayOfMonth(15), interval: 3, start: "2026-08-15")
        XCTAssertTrue(scheduled(r, "2026-08-15"))
        XCTAssertFalse(scheduled(r, "2026-09-15"))
        XCTAssertTrue(scheduled(r, "2026-11-15"))
        XCTAssertTrue(scheduled(r, "2027-02-15"))
    }

    /// Ohne eigene Regel meint „monatlich" den Tag des Starts — wie im
    /// Kalender.
    func testMonthlyWithoutARuleTakesTheDayOfTheStart() {
        let r = Recurrence(frequency: .monthly, start: "2026-08-07")
        XCTAssertEqual(r.rule, .dayOfMonth(7))
        XCTAssertTrue(scheduled(r, "2026-09-07"))
    }

    // MARK: – Jährlich

    func testYearlyMonthAndDay() {
        let r = Recurrence.yearly(month: 3, .dayOfMonth(15))
        XCTAssertTrue(scheduled(r, "2026-03-15"))
        XCTAssertTrue(scheduled(r, "2027-03-15"))
        XCTAssertFalse(scheduled(r, "2026-04-15"))
    }

    func testYearlyNthWeekday() {
        let r = Recurrence.yearly(month: 8, .nthWeekday(nth: 3, weekday: 3))
        XCTAssertTrue(scheduled(r, "2026-08-18"))
        XCTAssertFalse(scheduled(r, "2026-09-15"))
    }

    func testYearlyIntervalSkipsYears() {
        let r = Recurrence.yearly(month: 8, .dayOfMonth(9), interval: 2, start: "2026-08-09")
        XCTAssertTrue(scheduled(r, "2026-08-09"))
        XCTAssertFalse(scheduled(r, "2027-08-09"))
        XCTAssertTrue(scheduled(r, "2028-08-09"))
    }

    /// Der 29. Februar kommt nur im Schaltjahr — dazwischen fällt der Termin
    /// aus, statt auf den 1. März zu rutschen.
    func testYearlyOnLeapDayOnlyHitsLeapYears() {
        let r = Recurrence.yearly(month: 2, .dayOfMonth(29), start: "2028-02-29")
        XCTAssertTrue(scheduled(r, "2028-02-29"))
        XCTAssertFalse(scheduled(r, "2029-03-01"))
        XCTAssertEqual(r.nextOccurrence(after: "2028-02-29", calendar: calendar), "2032-02-29")
    }

    // MARK: – Ende

    func testEndOnDateIsInclusive() {
        let r = Recurrence(frequency: .daily, start: "2026-08-01", end: .on("2026-08-05"))
        XCTAssertTrue(scheduled(r, "2026-08-05"))
        XCTAssertFalse(scheduled(r, "2026-08-06"))
    }

    /// „Nach N Terminen" zählt TERMINE, nicht Tage: drei Mal Montag+Donnerstag
    /// ist nach anderthalb Wochen vorbei, nicht nach drei Tagen.
    func testEndAfterCountsOccurrencesNotDays() {
        let r = Recurrence.weekdays([2, 5], start: "2026-08-03", end: .after(3))
        XCTAssertTrue(scheduled(r, "2026-08-03"))    // 1. Termin (Mo)
        XCTAssertTrue(scheduled(r, "2026-08-06"))    // 2. Termin (Do)
        XCTAssertTrue(scheduled(r, "2026-08-10"))    // 3. Termin (Mo)
        XCTAssertFalse(scheduled(r, "2026-08-13"))   // wäre der 4.
        XCTAssertEqual(r.occurrences(in: "2026-08-01"..."2026-12-31", calendar: calendar),
                       ["2026-08-03", "2026-08-06", "2026-08-10"])
    }

    func testEndAfterOnAMonthlyRuleCountsMonths() {
        let r = Recurrence.monthly(.dayOfMonth(31), start: "2026-01-31", end: .after(2))
        XCTAssertTrue(scheduled(r, "2026-01-31"))
        // Der Februar hat keinen 31. — der zweite Termin ist deshalb der
        // 31. März, und danach ist Schluss.
        XCTAssertTrue(scheduled(r, "2026-03-31"))
        XCTAssertFalse(scheduled(r, "2026-05-31"))
    }

    /// Ohne Start lässt sich nichts abzählen — dann gilt kein Ende, statt
    /// stillschweigend beim ersten Termin abzubrechen.
    func testEndAfterWithoutAStartIsTreatedAsOpen() {
        let r = Recurrence(frequency: .daily, end: .after(3))
        XCTAssertTrue(scheduled(r, "2030-01-01"))
    }

    func testGarbageEndValuesAreDropped() {
        XCTAssertEqual(Recurrence(frequency: .daily, end: .on("morgen")).end, .never)
        XCTAssertEqual(Recurrence(frequency: .daily, end: .after(0)).end, .never)
        XCTAssertEqual(Recurrence(frequency: .daily, end: .after(9999)).end,
                       .after(Recurrence.maxOccurrences))
    }

    // MARK: – Aufzählen

    func testOccurrencesInAWindow() {
        let r = Recurrence.weekdays([2, 4, 6], start: "2026-08-01")
        XCTAssertEqual(r.occurrences(in: "2026-08-03"..."2026-08-09", calendar: calendar),
                       ["2026-08-03", "2026-08-05", "2026-08-07"])
    }

    func testNextOccurrenceSkipsToTheNextActivePeriod() {
        let r = Recurrence.weekdays([2], interval: 2, start: "2026-08-03")
        XCTAssertEqual(r.nextOccurrence(after: "2026-08-03", calendar: calendar), "2026-08-17")
    }

    func testNextOccurrenceBeforeTheStartIsTheStart() {
        let r = Recurrence.weekdays([2], start: "2026-08-03")
        XCTAssertEqual(r.nextOccurrence(after: "2026-07-01", calendar: calendar), "2026-08-03")
    }

    func testNoNextOccurrenceAfterTheEnd() {
        let r = Recurrence(frequency: .daily, start: "2026-08-01", end: .on("2026-08-05"))
        XCTAssertNil(r.nextOccurrence(after: "2026-08-05", calendar: calendar))
    }

    /// Eine Regel, die nie zutrifft, muss enden — nicht endlos suchen.
    func testImpossibleRuleTerminates() {
        let r = Recurrence.yearly(month: 2, .dayOfMonth(30), start: "2026-01-01")
        XCTAssertNil(r.nextOccurrence(after: "2026-01-01", calendar: calendar))
        XCTAssertTrue(r.occurrences(in: "2026-01-01"..."2036-01-01", calendar: calendar).isEmpty)
    }

    // MARK: – Normalisierung

    func testIntervalAndTimesAreClamped() {
        XCTAssertEqual(Recurrence(frequency: .daily, interval: 0).interval, 1)
        XCTAssertEqual(Recurrence(frequency: .daily, interval: 500).interval, Recurrence.maxInterval)
        XCTAssertEqual(Recurrence.times(99, per: .weekly).timesPerPeriod, 7)
        XCTAssertEqual(Recurrence.times(99, per: .monthly).timesPerPeriod, 31)
    }

    func testFieldsThatDoNotBelongToTheFrequencyAreDropped() {
        let r = Recurrence(frequency: .daily, weekdays: [2, 3], rule: .lastDayOfMonth,
                           month: 5, timesPerPeriod: 3)
        XCTAssertTrue(r.weekdays.isEmpty)
        XCTAssertNil(r.rule)
        XCTAssertNil(r.month)
        XCTAssertNil(r.timesPerPeriod)   // „n× pro Tag" IST das Mengenziel
    }

    func testInvalidRuleValuesAreDropped() {
        let r = Recurrence(frequency: .monthly, rule: .nthWeekday(nth: 9, weekday: 3),
                           start: "2026-08-07")
        XCTAssertEqual(r.rule, .dayOfMonth(7))   // zurück auf den Tag des Starts
        XCTAssertNil(Recurrence.DayRule.dayOfMonth(0).sanitized)
        XCTAssertNil(Recurrence.DayRule.nthWeekday(nth: 1, weekday: 8).sanitized)
    }

    func testGarbageStartIsDropped() {
        XCTAssertNil(Recurrence(frequency: .daily, start: "irgendwann").start)
    }

    // MARK: – Codable der neuen Formen

    func testEveryShapeRoundTripsThroughJSON() throws {
        let shapes: [Recurrence] = [
            .daily,
            Recurrence(frequency: .daily, interval: 3, start: "2026-08-03"),
            .weekdays([2, 4, 6]),
            .weekdays([2], interval: 2, start: "2026-08-03"),
            .times(3, per: .weekly),
            .times(1, per: .weekly, weekdays: [3]),
            .times(5, per: .monthly, interval: 2, start: "2026-08-01"),
            .monthly(.dayOfMonth(31)),
            .monthly(.lastDayOfMonth, interval: 2, start: "2026-08-31"),
            .monthly(.nthWeekday(nth: Recurrence.DayRule.last, weekday: 6)),
            .yearly(month: 3, .dayOfMonth(15)),
            .yearly(month: 8, .nthWeekday(nth: 3, weekday: 3), interval: 2, start: "2026-08-18"),
            Recurrence(frequency: .daily, start: "2026-08-01", end: .on("2026-09-01"), target: 4),
            Recurrence(frequency: .weekly, weekdays: [2], start: "2026-08-03", end: .after(10)),
        ]
        for shape in shapes {
            let raw = try JSONEncoder().encode(shape)
            XCTAssertEqual(try JSONDecoder().decode(Recurrence.self, from: raw), shape,
                           String(data: raw, encoding: .utf8) ?? "")
        }
    }

    func testEndTitleRoundTripsAndIsSanitized() throws {
        let recurrence = Recurrence(frequency: .daily,
                                    end: .on("2026-12-31"),
                                    endTitle: "  Winter  ")
        XCTAssertEqual(recurrence.endTitle, "Winter")

        let data = try JSONEncoder().encode(recurrence)
        let decoded = try JSONDecoder().decode(Recurrence.self, from: data)
        XCTAssertEqual(decoded.endTitle, "Winter")

        let never = Recurrence(frequency: .daily, endTitle: "ignored")
        XCTAssertNil(never.endTitle)
    }

    func testOldRecurrenceWithoutEndTitleStillDecodes() throws {
        let raw = #"{"freq":"daily","endDate":"2026-12-31"}"#
        let recurrence = try JSONDecoder().decode(Recurrence.self, from: Data(raw.utf8))
        XCTAssertEqual(recurrence.end, .on("2026-12-31"))
        XCTAssertNil(recurrence.endTitle)
    }

    /// Der Alt-Spiegel muss ZURÜCK auf dieselbe Regel führen — sonst
    /// verändert ein ausgelieferter Build beim nächsten Speichern still die
    /// Bedeutung.
    func testLegacyMirrorRoundTripsForEveryExpressibleShape() {
        let shapes: [Recurrence] = [
            .daily,
            Recurrence(target: 3),
            .weekdays([2, 3, 4, 5, 6]),
            .weekdays([7]),
            .times(3, per: .weekly),
            .times(1, per: .weekly, weekdays: [3]),
        ]
        for shape in shapes {
            let mirror = shape.legacyMirror
            XCTAssertNotNil(mirror, "\(shape) sollte sich spiegeln lassen")
            if let mirror { XCTAssertEqual(Recurrence.from(legacy: mirror), shape) }
        }
    }

    func testShapesThatCannotBeMirroredSaySo() {
        XCTAssertNil(Recurrence.monthly(.lastDayOfMonth).legacyMirror)
        XCTAssertNil(Recurrence.weekdays([2], interval: 2).legacyMirror)
        XCTAssertNil(Recurrence(frequency: .daily, start: "2026-08-01").legacyMirror)
        XCTAssertNil(Recurrence(frequency: .daily, end: .after(5)).legacyMirror)
        XCTAssertNil(Recurrence.times(3, per: .weekly, weekdays: [2, 5]).legacyMirror)
    }
}
