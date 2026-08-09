import XCTest
@testable import Haiity

/// Serien und Quoten über TERMINE statt über Tage — die neuen Formen
/// (Wochentagsmengen, Intervalle, Monats-/Jahresregeln, Zeiträume). Die
/// Alt-Formen prüfen `GoalEngineTests` und `WeeklyWeekdayTests` weiter,
/// jeweils durch die Migration hindurch.
///
/// Verifizierte Eckdaten: 2026-07-27 Mo … 2026-08-09 So.
final class RecurrenceEngineTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }()

    private func habit(_ days: [String],
                       _ recurrence: Recurrence,
                       createdAt: String = "2026-07-27") -> Habit {
        var h = Habit(name: "Test", recurrence: recurrence)
        h.createdAt = createdAt
        for d in days { h.log[d] = 1 }
        return h
    }

    /// Mo, Mi, Fr.
    private let mwf = Recurrence.weekdays([2, 4, 6])
    private let twoWeeks = ["2026-07-27", "2026-07-29", "2026-07-31",
                            "2026-08-03", "2026-08-05", "2026-08-07"]

    // MARK: – Serie über Termine

    /// Sechs Termine in Folge; Dienstage, Donnerstage und Wochenenden sind
    /// durchsichtig — sie brechen nichts und zählen nicht mit.
    func testStreakCountsScheduledOccurrencesOnly() {
        let h = habit(twoWeeks, mwf)
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-09", calendar: calendar), 6)
    }

    func testMissedScheduledDayBreaksTheStreak() {
        let h = habit(twoWeeks.filter { $0 != "2026-08-05" }, mwf)
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-09", calendar: calendar), 1)
    }

    /// Mehrleistung wird nie bestraft: ein Check-in an einem terminfreien Tag
    /// zählt mit (genau die alte Ruhetag-Regel, nur verallgemeinert).
    func testBonusCheckInOnAFreeDayCountsAndNeverBreaks() {
        let h = habit(twoWeeks + ["2026-08-09"], mwf)
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-09", calendar: calendar), 7)
    }

    /// Heute ist gar kein Termin -> die Serie von vorgestern lebt weiter,
    /// ohne dass „heute offen" überhaupt eine Rolle spielt.
    func testFreeTodayLeavesTheStreakAlone() {
        let h = habit(twoWeeks, mwf)
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-08", calendar: calendar), 6)
    }

    func testBestStreakUsesTheSameOccurrences() {
        let h = habit(twoWeeks, mwf)
        XCTAssertEqual(GoalEngine.bestStreak(habit: h, today: "2026-08-09", calendar: calendar), 6)
        // Gegenprobe: als tägliches Habit sind dieselben Tage sechs
        // Einzelläufe von 1.
        let daily = habit(twoWeeks, .daily)
        XCTAssertEqual(GoalEngine.bestStreak(habit: daily, today: "2026-08-09", calendar: calendar), 1)
    }

    /// Ein Intervall überbrückt ganze Wochen: zwei Termine im Abstand von 14
    /// Tagen sind eine Serie von 2.
    func testStreakAcrossAnIntervalOfTwoWeeks() {
        let recurrence = Recurrence.weekdays([2], interval: 2, start: "2026-07-13")
        let h = habit(["2026-07-13", "2026-07-27"], recurrence, createdAt: "2026-07-13")
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-09", calendar: calendar), 2)
    }

    func testStreakOnAMonthlyRule() {
        let h = habit(["2026-05-31", "2026-06-30", "2026-07-31"],
                      .monthly(.lastDayOfMonth), createdAt: "2026-05-31")
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-09", calendar: calendar), 3)
    }

    /// Nach dem Ende ist nichts mehr fällig — die Serie steht, sie zerfällt
    /// nicht rückwirkend, nur weil die Regel ausgelaufen ist.
    func testDaysAfterTheEndAreTransparent() {
        let recurrence = Recurrence.weekdays([2, 4, 6], start: "2026-08-03",
                                             end: .on("2026-08-05"))
        let h = habit(["2026-08-03", "2026-08-05"], recurrence, createdAt: "2026-08-03")
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-09", calendar: calendar), 2)
    }

    // MARK: – Quote über fällige Tage

    func testCompletionIsMetOverScheduled() {
        // Fenster 03.–09.08.: fällig sind Mo, Mi, Fr; erledigt Mo und Mi.
        let h = habit(["2026-08-03", "2026-08-05"], mwf)
        XCTAssertEqual(GoalEngine.completion(habit: h, lastNDays: 7,
                                             today: "2026-08-09", calendar: calendar),
                       2.0 / 3.0, accuracy: 0.0001)
    }

    /// Tage VOR dem Start sind nicht fällig — ein zwei Tage altes Habit
    /// steht deshalb nicht bei 0,5 %, nur weil das Fenster 365 Tage misst.
    func testCompletionIgnoresDaysBeforeTheStart() {
        let h = habit(["2026-08-07", "2026-08-08", "2026-08-09"],
                      Recurrence(frequency: .daily, start: "2026-08-07"),
                      createdAt: "2026-08-07")
        XCTAssertEqual(GoalEngine.completion(habit: h, lastNDays: 365,
                                             today: "2026-08-09", calendar: calendar),
                       1.0, accuracy: 0.0001)
    }

    func testCompletionWithoutAnyScheduledDayIsZero() {
        let h = habit(["2026-08-05"], Recurrence(frequency: .weekly))   // leere Tagesmenge
        XCTAssertEqual(GoalEngine.completion(habit: h, lastNDays: 7,
                                             today: "2026-08-09", calendar: calendar), 0)
    }

    // MARK: – Flexible Ziele über andere Perioden

    func testFlexibleMonthlyGoalCountsMonths() {
        let june = (1...5).map { String(format: "2026-06-%02d", $0) }
        let july = (1...5).map { String(format: "2026-07-%02d", $0) }
        let h = habit(june + july, .times(5, per: .monthly), createdAt: "2026-06-01")
        // Der laufende August ist noch nicht erfüllt, aber auch noch nicht
        // verloren -> die beiden vollen Monate stehen.
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-09", calendar: calendar), 2)
        // Und in der Quote zählt er gar nicht mit: 2 von 2.
        XCTAssertEqual(GoalEngine.completion(habit: h, lastNDays: 62,
                                             today: "2026-08-09", calendar: calendar),
                       1.0, accuracy: 0.0001)
    }

    func testFlexibleGoalDiesWhenThePeriodCanNoLongerBeReached() {
        // 5× im Monat, aber der August ist am 30. schon fast vorbei und noch
        // nichts erledigt -> nicht mehr zu schaffen.
        let july = (1...5).map { String(format: "2026-07-%02d", $0) }
        let h = habit(july, .times(5, per: .monthly), createdAt: "2026-07-01")
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-30", calendar: calendar), 0)
    }

    func testFlexibleGoalWithIntervalSkipsPeriods() {
        // 2× alle zwei Wochen: die Woche dazwischen ist durchsichtig.
        let recurrence = Recurrence.times(2, per: .weekly, interval: 2, start: "2026-07-13")
        let h = habit(["2026-07-13", "2026-07-14", "2026-07-27", "2026-07-28"],
                      recurrence, createdAt: "2026-07-13")
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-09", calendar: calendar), 2)
        XCTAssertEqual(GoalEngine.bestStreak(habit: h, today: "2026-08-09", calendar: calendar), 2)
    }

    // MARK: – Raster

    /// Termine ändern an der Zellintensität NICHTS: eine leere Zelle bleibt
    /// eine leere Zelle, ein Check-in an einem terminfreien Tag leuchtet
    /// genauso wie jeder andere. (Ein eigener Grauton für „war nicht fällig"
    /// hätte 365 Zellen eine dritte Bedeutung gegeben.)
    func testIntensityDoesNotDependOnTheSchedule() {
        let h = habit(["2026-08-09"], mwf)                 // So, kein Termin
        XCTAssertEqual(GoalEngine.intensity(habit: h, key: "2026-08-09", calendar: calendar), 1)
        XCTAssertEqual(GoalEngine.intensity(habit: h, key: "2026-08-08", calendar: calendar), 0)
        let snapshot = GridCalendar.snapshot(habit: h, weeks: 4, today: "2026-08-09",
                                             calendar: calendar)
        XCTAssertEqual(snapshot.filledCount, 1)
    }

    // MARK: – „Heute offen"

    /// Was heute gar nicht dran ist, ist auch nicht offen — sonst mahnt die
    /// Abend-Zusammenfassung an etwas, das niemand versprochen hat.
    func testOpenTodaySkipsHabitsThatAreNotDue() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-open-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url)
        let today = DayKey.today()
        let weekday = Calendar.current.component(.weekday, from: Date())
        store.add(Habit(name: "Heute fällig", recurrence: .weekdays([weekday])))
        store.add(Habit(name: "Heute frei", recurrence: .weekdays([weekday % 7 + 1])))
        XCTAssertEqual(store.openToday(today).map(\.name), ["Heute fällig"])
    }
}
