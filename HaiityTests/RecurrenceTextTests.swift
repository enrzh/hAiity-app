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

    func testOnceNamesItsSelectedDay() {
        let once = Recurrence(frequency: .once, start: "2026-08-09")
        XCTAssertEqual(text(once),
                       "Einmal am 09.08.2026")

        var english = calendar
        english.locale = Locale(identifier: "en_US")
        XCTAssertEqual(RecurrenceText.summary(once, calendar: english),
                       "Once on 09.08.2026")
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

    func testEndTitleIsIncludedInTheSummary() {
        let recurrence = Recurrence(frequency: .daily,
                                    end: .after(3),
                                    endTitle: "Sommer")
        XCTAssertEqual(text(recurrence), "Jeden Tag, endet nach 3 Terminen (Sommer)")
    }
}

/// Die Position im Monat als ORDNUNGSZAHL — und der Bruch eines Schlüssels
/// in zwei.
///
/// Zwei Fehler, die Deutsch verdeckt hat:
///
///  * `„3. Freitag"` und `„15. März"` sahen als Formatzeichenkette gleich aus
///    (`%lld. %@`) und teilten sich deshalb EINEN Katalogeintrag. Zwei
///    Grammatiken, ein Text: in keiner anderen Sprache lassen sich beide
///    daraus richtig bauen. Sie haben jetzt getrennte Schlüssel.
///  * Die Position war eine nackte Zahl. Englisch konnte daraus nur
///    „the 3. Friday" machen — nie „the 3rd Friday".
final class RecurrenceOrdinalTests: XCTestCase {

    /// Die 16 Übersetzungen (Deutsch ist die QUELLE und hat kein .lproj —
    /// dort steht der Satz als `defaultValue` im Binary).
    private static let languages = ["ar", "bn", "en", "es", "fr", "hi", "id", "it",
                                    "ja", "ko", "pt", "ru", "tr", "ur", "vi", "zh-Hans"]

    private var german: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        c.firstWeekday = 2
        return c
    }()

    /// Die Formatzeichenkette, wie sie IM GEBAUTEN BUNDLE steht. Nicht aus
    /// dem Katalog gelesen, sondern aus dem Produkt — sonst prüft der Test
    /// eine Datei, die im Gerät niemand aufschlägt.
    private func format(_ key: String, _ language: String) -> String? {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        let miss = "\u{1}missing"
        let value = bundle.localizedString(forKey: key, value: miss, table: "Localizable")
        return value == miss ? nil : value
    }

    // MARK: – die Zahl

    func testOrdinalsFollowTheLanguage() {
        let expected: [String: [String]] = [
            "en": ["1st", "2nd", "3rd", "4th", "5th"],
            "de": ["1.", "2.", "3.", "4.", "5."],
            "tr": ["1.", "2.", "3.", "4.", "5."],
            "ja": ["第1", "第2", "第3", "第4", "第5"],
            "zh-Hans": ["第1", "第2", "第3", "第4", "第5"],
            "ko": ["1번째", "2번째", "3번째", "4번째", "5번째"],
            "id": ["ke-1", "ke-2", "ke-3", "ke-4", "ke-5"],
            "fr": ["1er", "2e", "3e", "4e", "5e"],
            "es": ["1.º", "2.º", "3.º", "4.º", "5.º"],
        ]
        for (code, want) in expected.sorted(by: { $0.key < $1.key }) {
            let locale = Locale(identifier: code)
            XCTAssertEqual((1...5).map { RecurrenceText.ordinal($0, locale: locale) }, want, code)
        }
    }

    /// Sprachen ohne eigene Form (ru, ar) bekommen die blanke Zahl — die
    /// Grammatik ringsherum steht im Katalog. Was NICHT passieren darf: leer,
    /// oder ein durchgereichter Platzhalter.
    func testEveryLanguageProducesSomethingUsable() {
        for language in Self.languages + ["de"] {
            let value = RecurrenceText.ordinal(3, locale: Locale(identifier: language))
            XCTAssertFalse(value.isEmpty, language)
            XCTAssertFalse(value.contains("%"), "\(language): \(value)")
            XCTAssertTrue(value.contains("3") || value.contains("٣"), "\(language): \(value)")
        }
    }

    // MARK: – der Satz

    /// Der Fehler, um den es ging: Englisch konnte „3rd" nie schreiben.
    func testEnglishWritesRealOrdinals() {
        let en = Locale(identifier: "en_US")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = en
        let friday = RecurrenceText.weekdayName(6, calendar: calendar)
        XCTAssertEqual(friday, "Friday")

        XCTAssertEqual(String(format: format("recurrence.nthWeekday.short", "en")!,
                              RecurrenceText.ordinal(3, locale: en), friday),
                       "the 3rd Friday")
        XCTAssertEqual(String(format: format("recurrence.nthWeekday.monthly", "en")!,
                              RecurrenceText.ordinal(1, locale: en), friday),
                       "On the 1st Friday of the month")
        XCTAssertEqual(String(format: format("recurrence.nthWeekday.inMonth", "en")!,
                              RecurrenceText.ordinal(2, locale: en), friday, "March"),
                       "the 2nd Friday in March")
    }

    /// Deutsch, Türkisch, Japanisch — drei Formen, die nur zusammen zeigen,
    /// dass die Ordnungszahl WIRKLICH aus der Sprache kommt: „3." steht vor
    /// dem Tag, „第3" klebt daran, und beide sitzen an verschiedenen Stellen
    /// des Satzes.
    func testGermanTurkishAndJapaneseSentences() {
        // Deutsch geht über die App selbst: der Satz steht dort als
        // defaultValue, nicht in einer .lproj.
        XCTAssertEqual(RecurrenceText.summary(.monthly(.nthWeekday(nth: 3, weekday: 6)),
                                              calendar: german),
                       "Am 3. Freitag im Monat")
        XCTAssertEqual(RecurrenceText.summary(.monthly(.nthWeekday(nth: 3, weekday: 6), interval: 4),
                                              calendar: german),
                       "Alle 4 Monate am 3. Freitag")

        let turkish = Locale(identifier: "tr_TR")
        XCTAssertEqual(String(format: format("recurrence.nthWeekday.monthly", "tr")!,
                              RecurrenceText.ordinal(3, locale: turkish), "Cuma"),
                       "Ayın 3. Cuma günü")

        let japanese = Locale(identifier: "ja_JP")
        XCTAssertEqual(String(format: format("recurrence.nthWeekday.monthly", "ja")!,
                              RecurrenceText.ordinal(3, locale: japanese), "金曜日"),
                       "毎月第3金曜日")
        XCTAssertEqual(String(format: format("recurrence.nthWeekday.inMonth", "ja")!,
                              RecurrenceText.ordinal(1, locale: japanese), "金曜日", "3月"),
                       "3月の第1金曜日")
    }

    // MARK: – ein Schlüssel je Bedeutung

    /// Das Datum behält seine ZAHL, die Position bekommt eine ORDNUNGSZAHL.
    /// Schon an den Spezifizierern muss sich das in JEDER Sprache ablesen
    /// lassen — sonst hängen die beiden Sätze wieder aneinander.
    func testTheYearlyDateAndTheNthWeekdayNoLongerShareAKey() {
        for language in Self.languages {
            guard let date = format("recurrence.date.dayInMonth", language),
                  let nth = format("recurrence.nthWeekday.short", language) else {
                XCTFail("\(language): one of the two keys is missing from the bundle")
                continue
            }
            XCTAssertTrue(date.contains("%1$lld"), "\(language) date: \(date)")
            XCTAssertFalse(nth.contains("lld"), "\(language) nth: \(nth)")
        }
    }

    func testEveryLanguageCarriesAllFourRuleKeys() {
        for language in Self.languages {
            for key in ["recurrence.date.dayInMonth", "recurrence.nthWeekday.short",
                        "recurrence.nthWeekday.monthly", "recurrence.nthWeekday.inMonth"] {
                XCTAssertNotNil(format(key, language), "\(language) is missing \(key)")
            }
        }
    }

    /// „Der letzte Freitag" ist ein EIGENER Satz und keine Ordnungszahl —
    /// sonst stünde dort „-1." bzw. „−1st".
    func testTheLastWeekdayNeverBecomesAnOrdinal() {
        let last = Recurrence.DayRule.last
        XCTAssertEqual(RecurrenceText.summary(.monthly(.nthWeekday(nth: last, weekday: 6)),
                                              calendar: german),
                       "Am letzten Freitag im Monat")
        XCTAssertEqual(RecurrenceText.summary(.monthly(.nthWeekday(nth: last, weekday: 6), interval: 3),
                                              calendar: german),
                       "Alle 3 Monate am letzten Freitag")
        XCTAssertEqual(RecurrenceText.summary(.yearly(month: 8, .nthWeekday(nth: last, weekday: 6)),
                                              calendar: german),
                       "Jedes Jahr am letzten Freitag im August")
        for language in Self.languages {
            for key in ["letzten %@", "Am letzten %@ im Monat", "letzten %@ im %@"] {
                let value = format(key, language)
                XCTAssertNotNil(value, "\(language) is missing \(key)")
                XCTAssertFalse(value?.contains("-1") ?? false, "\(language): \(value ?? "")")
            }
        }
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

    func testEndTitleSurvivesTheForm() {
        let recurrence = Recurrence(frequency: .daily,
                                    start: "2026-08-09",
                                    end: .on("2026-12-31"),
                                    endTitle: "Winter")
        XCTAssertEqual(roundTrip(recurrence), recurrence)
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

    func testSwitchingThroughOnceKeepsLegacyRecurringWithoutStart() {
        let legacy = Recurrence.weekdays([2], start: nil)
        var draft = RecurrenceDraft(legacy, today: today, calendar: calendar)

        XCTAssertFalse(draft.hasStart)
        draft.selectFrequency(.once, calendar: calendar)
        XCTAssertFalse(draft.hasStart)
        XCTAssertEqual(draft.recurrence(calendar: calendar).start, "2026-08-09")

        draft.selectFrequency(.weekly, calendar: calendar)
        XCTAssertFalse(draft.hasStart)
        XCTAssertNil(draft.recurrence(calendar: calendar).start)
        XCTAssertEqual(draft.recurrence(calendar: calendar).weekdays, [2])
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
