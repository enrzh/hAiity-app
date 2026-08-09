import XCTest
@testable import Haiity

/// „Einmal pro Woche, am Dienstag um 19:00" — die Alt-Form, die die
/// Migration erhalten muss: Modell, Erfüllungsregel und die Wahl des
/// Benachrichtigungs-Triggers.
final class WeeklyWeekdayGoalTests: XCTestCase {

    // MARK: – Normalisierung des Alt-Ziels

    func testFixedWeekdayForcesTimesToOne() {
        // „3× pro Woche, jeden Dienstag" ist keine sinnvolle Kombination —
        // der feste Tag gewinnt und zieht die Zahl auf 1.
        let goal = LegacyGoal(cadence: .weekly(times: 3), weekday: 3)
        XCTAssertEqual(goal.cadence, LegacyGoal.Cadence.weekly(times: 1))
        XCTAssertEqual(goal.weekday, 3)
    }

    func testWeeklyWithoutWeekdayKeepsTimes() {
        let goal = LegacyGoal.weekly(times: 4)
        XCTAssertEqual(goal.cadence, LegacyGoal.Cadence.weekly(times: 4))
        XCTAssertNil(goal.weekday)
    }

    func testWeekdayOutOfRangeIsDropped() {
        XCTAssertNil(LegacyGoal(cadence: .weekly(times: 2), weekday: 0).weekday)
        XCTAssertNil(LegacyGoal(cadence: .weekly(times: 2), weekday: 8).weekday)
        XCTAssertNil(LegacyGoal(cadence: .weekly(times: 2), weekday: -3).weekday)
        // Und weil der Tag wegfällt, bleibt times unangetastet.
        XCTAssertEqual(LegacyGoal(cadence: .weekly(times: 2), weekday: 99).cadence,
                       LegacyGoal.Cadence.weekly(times: 2))
    }

    func testWeekdayIsMeaninglessForDailyCadence() {
        let goal = LegacyGoal(cadence: .daily, restDays: [1], weekday: 4)
        XCTAssertNil(goal.weekday)
    }

    // MARK: – Migration in die Wiederholungsregel

    /// Der feste Tag wird zur VERABREDUNG: flexibles Ziel 1× pro Woche, der
    /// Dienstag steht daneben (Erinnerung, Beschriftung) — genau die alte
    /// Bedeutung.
    func testFixedWeekdayMigratesToFlexibleWeekWithAnAgreedDay() {
        let r = Recurrence.from(legacy: .weekly(times: 1, weekday: 3))
        XCTAssertEqual(r.frequency, .weekly)
        XCTAssertEqual(r.interval, 1)
        XCTAssertEqual(r.timesPerPeriod, 1)
        XCTAssertEqual(r.weekdays, [3])
        XCTAssertNil(r.start)
        XCTAssertEqual(r.end, .never)
    }

    func testTimesPerWeekMigratesToFlexibleWeekWithoutDays() {
        let r = Recurrence.from(legacy: .weekly(times: 3))
        XCTAssertEqual(r.timesPerPeriod, 3)
        XCTAssertTrue(r.weekdays.isEmpty)
    }

    func testRestDaysMigrateToTheComplementaryWeekdaySet() {
        let r = Recurrence.from(legacy: LegacyGoal(restDays: [1, 7]))   // Sa/So frei
        XCTAssertEqual(r.frequency, .weekly)
        XCTAssertEqual(r.weekdays, [2, 3, 4, 5, 6])
        XCTAssertNil(r.timesPerPeriod)      // feste Termine, kein Zählziel
    }

    /// Alle sieben Tage Ruhetag hieß: nie ist etwas fällig. Als Regel ist
    /// das die LEERE Tagesmenge — nicht „jeden Tag".
    func testAllRestDaysMigrateToNoOccurrencesAtAll() {
        let r = Recurrence.from(legacy: LegacyGoal(restDays: [1, 2, 3, 4, 5, 6, 7]))
        XCTAssertTrue(r.weekdays.isEmpty)
        XCTAssertFalse(r.isScheduled(on: "2026-08-05"))
    }

    func testPlainDailyMigratesToDaily() {
        XCTAssertEqual(Recurrence.from(legacy: .daily), .daily)
        XCTAssertEqual(Recurrence.from(legacy: LegacyGoal(target: 5)), Recurrence(target: 5))
    }

    /// Ruhetage NEBEN einer Wochen-Kadenz haben nie etwas bewirkt
    /// (`isRestDay` galt nur für `.daily`) — sie fallen weg, ohne dass sich
    /// eine Antwort ändert.
    func testRestDaysOnWeeklyCadenceAreDroppedBecauseTheyNeverDidAnything() {
        let r = Recurrence.from(legacy: LegacyGoal(cadence: .weekly(times: 2), restDays: [1, 7]))
        XCTAssertEqual(r.timesPerPeriod, 2)
        XCTAssertTrue(r.weekdays.isEmpty)
    }

    // MARK: – Codable (tolerant, ohne Versionssprung)

    func testRoundTripKeepsWeekday() throws {
        let r = Recurrence.from(legacy: LegacyGoal(cadence: .weekly(times: 1), target: 2, weekday: 5))
        let raw = try JSONEncoder().encode(r)
        XCTAssertEqual(try JSONDecoder().decode(Recurrence.self, from: raw), r)
    }

    func testExistingWeeklyFileDecodesUnchanged() throws {
        // Ausgelieferte Datei OHNE weekday: exakt wie vorher, times bleibt 3.
        let r = try JSONDecoder().decode(
            Recurrence.self, from: Data(#"{"cadence":"weekly","times":3}"#.utf8))
        XCTAssertEqual(r.timesPerPeriod, 3)
        XCTAssertTrue(r.weekdays.isEmpty)
    }

    func testDecodeNormalizesTimesWhenWeekdayIsPresent() throws {
        let r = try JSONDecoder().decode(
            Recurrence.self, from: Data(#"{"cadence":"weekly","times":5,"weekday":3}"#.utf8))
        XCTAssertEqual(r.timesPerPeriod, 1)
        XCTAssertEqual(r.weekdays, [3])
    }

    func testDecodeDropsGarbageWeekday() throws {
        let r = try JSONDecoder().decode(
            Recurrence.self, from: Data(#"{"cadence":"weekly","times":2,"weekday":13}"#.utf8))
        XCTAssertTrue(r.weekdays.isEmpty)
        XCTAssertEqual(r.timesPerPeriod, 2)
    }

    /// Der Alt-Spiegel: was sich im alten Format ausdrücken lässt, steht auch
    /// dort — sonst liest ein ausgelieferter Build seine eigene Datei nicht
    /// mehr richtig.
    func testMirroredShapesKeepTheOldKeysInJSON() throws {
        func json(_ r: Recurrence) throws -> [String: Any] {
            let raw = try JSONEncoder().encode(r)
            return try XCTUnwrap(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
        }
        let weekly = try json(.times(1, per: .weekly, weekdays: [7]))
        XCTAssertEqual(weekly["cadence"] as? String, "weekly")
        XCTAssertEqual(weekly["times"] as? Int, 1)
        XCTAssertEqual(weekly["weekday"] as? Int, 7)

        let workdays = try json(.weekdays([2, 3, 4, 5, 6]))
        XCTAssertEqual(workdays["cadence"] as? String, "daily")
        XCTAssertEqual(workdays["restDays"] as? [Int], [1, 7])

        // Was sich NICHT spiegeln lässt, spiegelt auch nichts vor.
        let monthly = try json(.monthly(.lastDayOfMonth))
        XCTAssertNil(monthly["cadence"])
        XCTAssertEqual(monthly["freq"] as? String, "monthly")
    }

    func testDailyGoalNeverWritesWeekday() throws {
        let raw = try JSONEncoder().encode(Recurrence.from(legacy: LegacyGoal(restDays: [1])))
        XCTAssertFalse((String(data: raw, encoding: .utf8) ?? "").contains("\"weekday\""))
    }

    func testWeeklyWithoutWeekdayNeverWritesTheKey() throws {
        let raw = try JSONEncoder().encode(Recurrence.times(2, per: .weekly))
        XCTAssertFalse((String(data: raw, encoding: .utf8) ?? "").contains("\"weekday\""))
    }

    func testGoalWithWeekdaySurvivesTheHabitFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-weekday-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url)
        store.add(Habit(name: "Waschen", legacy: LegacyGoal.weekly(times: 1, weekday: 7)))
        XCTAssertEqual(HabitStore(url: url).habits[0].recurrence.weekdays, [7])
    }
}

/// Die Erfüllungsregel. Bewusst festgenagelt, weil sie eine ENTSCHEIDUNG
/// ist und keine Selbstverständlichkeit: der feste Tag steuert die
/// Erinnerung, er ist keine Prüfung — wer früher oder später abhakt,
/// verliert die Woche nicht.
final class WeeklyWeekdaySatisfactionTests: XCTestCase {
    /// Fester Kalender, damit die Wochengrenzen unabhängig von den
    /// Systemeinstellungen der Maschine liegen: Montag ist Wochenstart.
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    /// KW 2026-08-03 (Mo) … 2026-08-09 (So). 2026-08-04 ist ein Dienstag.
    private func habit(_ days: [String], weekday: Int?) -> Habit {
        var h = Habit(name: "Waschen",
                      legacy: LegacyGoal(cadence: .weekly(times: 1), weekday: weekday))
        h.createdAt = "2026-07-01"
        for d in days { h.log[d] = 1 }
        return h
    }

    func testCheckInOnTheChosenWeekdaySatisfiesTheWeek() {
        let h = habit(["2026-08-04"], weekday: 3) // Dienstag
        XCTAssertTrue(GoalEngine.periodSatisfied(habit: h, day: "2026-08-04",
                                                 today: "2026-08-09", calendar: calendar))
    }

    func testCheckInOnAnotherDayStillSatisfiesTheSameWeek() {
        // DIE Regel: kein Malus für zu früh oder zu spät. Der Dienstag war
        // verabredet, abgehakt wurde am Donnerstag — die Woche steht.
        let h = habit(["2026-08-06"], weekday: 3)
        XCTAssertTrue(GoalEngine.periodSatisfied(habit: h, day: "2026-08-04",
                                                 today: "2026-08-09", calendar: calendar))
        XCTAssertTrue(GoalEngine.periodSatisfied(habit: h, day: "2026-08-06",
                                                 today: "2026-08-09", calendar: calendar))
    }

    /// Und deshalb ist bei einem flexiblen Ziel JEDER Tag der Woche ein
    /// möglicher Termin — nicht nur der verabredete.
    func testEveryDayOfTheWeekCountsAsScheduledForFlexibleGoals() {
        let h = habit([], weekday: 3)
        for day in ["2026-08-03", "2026-08-04", "2026-08-08", "2026-08-09"] {
            XCTAssertTrue(GoalEngine.isScheduled(habit: h, day: day, calendar: calendar), day)
        }
    }

    func testEmptyWeekIsNotSatisfied() {
        let h = habit([], weekday: 3)
        XCTAssertFalse(GoalEngine.periodSatisfied(habit: h, day: "2026-08-04",
                                                  today: "2026-08-09", calendar: calendar))
    }

    func testCheckInInAnotherWeekDoesNotSatisfyThisOne() {
        let h = habit(["2026-07-28"], weekday: 3) // Vorwoche
        XCTAssertFalse(GoalEngine.periodSatisfied(habit: h, day: "2026-08-04",
                                                  today: "2026-08-09", calendar: calendar))
    }

    func testQuantityTargetStillHasToBeMet() {
        // Ein Mengenziel bleibt ein Mengenziel: ein einzelner Zähler
        // erfüllt die Woche nicht, wenn das Tagesziel 3 ist.
        var h = habit([], weekday: 3)
        h.recurrence = .from(legacy: LegacyGoal(cadence: .weekly(times: 1), target: 3, weekday: 3))
        h.log["2026-08-04"] = 2
        XCTAssertFalse(GoalEngine.periodSatisfied(habit: h, day: "2026-08-04",
                                                  today: "2026-08-09", calendar: calendar))
        h.log["2026-08-04"] = 3
        XCTAssertTrue(GoalEngine.periodSatisfied(habit: h, day: "2026-08-04",
                                                 today: "2026-08-09", calendar: calendar))
    }

    func testPeriodSatisfiedFallsBackToTheDayForFixedGoals() {
        var h = Habit(name: "Lesen")
        h.log["2026-08-04"] = 1
        XCTAssertTrue(GoalEngine.periodSatisfied(habit: h, day: "2026-08-04",
                                                 today: "2026-08-09", calendar: calendar))
        XCTAssertFalse(GoalEngine.periodSatisfied(habit: h, day: "2026-08-05",
                                                  today: "2026-08-09", calendar: calendar))
    }

    // MARK: – Serien über Wochen

    func testStreakCountsConsecutiveWeeksRegardlessOfTheDay() {
        // Drei Wochen hintereinander erledigt, jedes Mal an einem ANDEREN
        // Tag — die Serie ist trotzdem 3.
        let h = habit(["2026-07-21",  // Di, KW 20.–26.07.
                       "2026-07-30",  // Do, KW 27.07.–02.08.
                       "2026-08-04"], // Di, laufende Woche
                      weekday: 3)
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-09", calendar: calendar), 3)
    }

    func testMissedWeekBreaksTheStreak() {
        let h = habit(["2026-07-21", "2026-08-04"], weekday: 3) // KW dazwischen leer
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-09", calendar: calendar), 1)
    }

    func testOpenCurrentWeekDoesNotBreakTheStreakYet() {
        // Dienstag verpasst, aber die Woche läuft noch: die Vorwochen
        // bleiben stehen (kein Mitte-der-Woche-Malus).
        let h = habit(["2026-07-21", "2026-07-30"], weekday: 3)
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-05", calendar: calendar), 2)
    }

    func testBestStreakUsesTheSameWeekBuckets() {
        let h = habit(["2026-07-21", "2026-07-30", "2026-08-04"], weekday: 3)
        XCTAssertEqual(GoalEngine.bestStreak(habit: h, today: "2026-08-09", calendar: calendar), 3)
    }

    func testCompletionCountsWeeksNotDays() {
        // Fenster berührt drei Wochen: 20.07. (leer), 27.07. (erfüllt) und
        // die laufende (noch offen — zählt deshalb gar nicht mit). 1 von 2.
        let h = habit(["2026-07-30"], weekday: 3)
        let rate = GoalEngine.completion(habit: h, lastNDays: 21,
                                         today: "2026-08-09", calendar: calendar)
        XCTAssertEqual(rate, 0.5, accuracy: 0.001)
    }
}

// Hier stand `ReminderPlanTests`: die Auswahl des Triggers für die EIGENE
// Erinnerung eines Habits (ein Trigger je Wochentag, Rückfallebene für „am
// letzten Freitag", Berechtigungs-Gate beim Anlegen). Diese Erinnerung gibt
// es seit v5 nicht mehr — erinnert wird zentral über die Tages- und die
// Wochenzusammenfassung. Die Nachfolger stehen in SummaryTests.swift.
