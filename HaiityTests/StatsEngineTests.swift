import XCTest
@testable import Haiity

/// Die Gesamt-Statistik über alle Habits (StatsEngine): Tagesquote,
/// Gesamt-Serie mit allen Randfällen (keine Habits, Ruhetage, flexible
/// Ziele, Verneinung, heute offen), Wochenbilanz mit Montag-Wochenanfang
/// und das vereinigte Raster.
final class StatsEngineTests: XCTestCase {

    /// Fester Kalender: Montag als Wochenanfang (de), damit die
    /// Wochengrenzen nicht von der Maschine abhängen.
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }

    /// 2026-08-05 ist ein Mittwoch.
    private let wednesday = "2026-08-05"

    private func habit(_ name: String = "H",
                       recurrence: Recurrence = .daily,
                       kind: HabitKind = .checkbox,
                       created: String = "2026-07-01",
                       log: [String: Int] = [:]) -> Habit {
        var h = Habit(name: name, emoji: "✅", recurrence: recurrence)
        h.createdAt = created
        h.log = log
        h.kind = kind
        return h
    }

    private func days(_ from: String, _ to: String) -> [String] {
        var out: [String] = []
        var d = from
        while d <= to {
            out.append(d)
            guard let next = DayKey.shifted(d, by: 1, calendar: cal) else { break }
            d = next
        }
        return out
    }

    // MARK: – Tagesquote

    func testDailyCompletionCountsOnlyScheduledHabits() {
        let due = habit("Täglich", log: [wednesday: 1])
        // Nur Mo (2): am Mittwoch nicht fällig.
        let rest = habit("Montags", recurrence: .weekdays([2]))
        let open = habit("Offen")
        let c = StatsEngine.dailyCompletion(habits: [due, rest, open],
                                            day: wednesday, calendar: cal)
        XCTAssertEqual(c, StatsEngine.DayCompletion(done: 1, total: 2))
    }

    func testDailyCompletionEmptyHabitsIsZeroZeroAndFractionOne() {
        let c = StatsEngine.dailyCompletion(habits: [], day: wednesday, calendar: cal)
        XCTAssertEqual(c.total, 0)
        XCTAssertEqual(c.fraction, 1, accuracy: 0.0001)
    }

    // MARK: – Gesamt-Serie

    func testOverallStreakNoHabitsIsZero() {
        XCTAssertEqual(StatsEngine.overallStreak(habits: [], today: wednesday, calendar: cal), 0)
    }

    func testOverallStreakMatchesSingleDailyHabit() {
        var log: [String: Int] = [:]
        for d in days("2026-08-01", wednesday) { log[d] = 1 }
        let h = habit(log: log)
        XCTAssertEqual(StatsEngine.overallStreak(habits: [h], today: wednesday, calendar: cal),
                       GoalEngine.streak(habit: h, today: wednesday, calendar: cal))
        XCTAssertEqual(StatsEngine.overallStreak(habits: [h], today: wednesday, calendar: cal), 5)
    }

    func testOverallStreakBreaksWhenOneHabitMissesAScheduledDay() {
        var logA: [String: Int] = [:], logB: [String: Int] = [:]
        for d in days("2026-08-01", wednesday) { logA[d] = 1; logB[d] = 1 }
        logB["2026-08-03"] = nil   // B verfehlt den Montag
        let a = habit("A", log: logA), b = habit("B", log: logB)
        // 05., 04. zählen; 03. reißt.
        XCTAssertEqual(StatsEngine.overallStreak(habits: [a, b], today: wednesday, calendar: cal), 2)
    }

    func testOverallStreakBridgesRestDays() {
        // Beide Habits nur Mo (2) und Mi (4); Di ist für beide terminfrei.
        let rule = Recurrence.weekdays([2, 4])
        let log = ["2026-08-03": 1, "2026-08-05": 1]   // Mo + Mi
        let a = habit("A", recurrence: rule, log: log)
        let b = habit("B", recurrence: rule, log: log)
        XCTAssertEqual(StatsEngine.overallStreak(habits: [a, b], today: wednesday, calendar: cal), 2)
    }

    func testOverallStreakCountsExtraCheckInOnFreeDay() {
        let rule = Recurrence.weekdays([2, 4])
        // Mo, DI (geschenkt), Mi.
        let log = ["2026-08-03": 1, "2026-08-04": 1, "2026-08-05": 1]
        let h = habit(recurrence: rule, log: log)
        XCTAssertEqual(StatsEngine.overallStreak(habits: [h], today: wednesday, calendar: cal), 3)
    }

    func testOverallStreakTodayMayStayOpen() {
        var log: [String: Int] = [:]
        for d in days("2026-08-01", "2026-08-04") { log[d] = 1 }
        let h = habit(log: log)   // heute (05.) noch nichts
        XCTAssertEqual(StatsEngine.overallStreak(habits: [h], today: wednesday, calendar: cal), 4)
    }

    func testOverallStreakDeclineBreaksEvenToday() {
        var log: [String: Int] = [:]
        for d in days("2026-08-01", "2026-08-04") { log[d] = Habit.Answer.yes }
        log[wednesday] = Habit.Answer.no
        let h = habit(kind: .yesNo, log: log)
        XCTAssertEqual(StatsEngine.overallStreak(habits: [h], today: wednesday, calendar: cal), 0)
    }

    func testOverallStreakFlexibleCurrentPeriodIsTransparent() {
        // 3× pro Woche, diese Woche erst 1 zählender Tag: noch offen, reißt
        // nicht — die Serie lebt aus der (erfüllten) Vorwoche weiter.
        let rule = Recurrence.times(3, per: .weekly)
        var log: [String: Int] = [:]
        for d in ["2026-07-27", "2026-07-29", "2026-07-31"] { log[d] = 1 }   // Vorwoche: 3×
        log["2026-08-03"] = 1                                                // diese Woche: 1×
        let h = habit(recurrence: rule, log: log)
        let daily = habit("Täglich", log: {
            var l: [String: Int] = [:]
            for d in days("2026-07-27", wednesday) { l[d] = 1 }
            return l
        }())
        // Jeder Tag mit Check-in zählt, kein Tag reißt: 27.07.–05.08. = 10.
        XCTAssertEqual(StatsEngine.overallStreak(habits: [h, daily],
                                                 today: wednesday, calendar: cal), 10)
    }

    func testOverallStreakFlexibleExpiredPeriodBreaks() {
        // Vorwoche nur 1× statt 3×: jeder Tag der Vorwoche reißt.
        let rule = Recurrence.times(3, per: .weekly)
        var log: [String: Int] = ["2026-07-29": 1]
        for d in days("2026-08-03", wednesday) { log[d] = 1 }   // diese Woche 3× -> erfüllt
        let h = habit(recurrence: rule, log: log)
        XCTAssertEqual(StatsEngine.overallStreak(habits: [h], today: wednesday, calendar: cal), 3)
    }

    // MARK: – Beste Gesamt-Serie

    func testBestOverallStreakFindsHistoricRun() {
        var log: [String: Int] = [:]
        for d in days("2026-07-01", "2026-07-10") { log[d] = 1 }   // 10er-Lauf
        for d in days("2026-08-01", "2026-08-03") { log[d] = 1 }   // 3er-Lauf
        let h = habit(log: log)
        XCTAssertEqual(StatsEngine.bestOverallStreak(habits: [h], today: wednesday, calendar: cal), 10)
    }

    func testBestOverallStreakResetsWhenAnyHabitMisses() {
        var logA: [String: Int] = [:], logB: [String: Int] = [:]
        for d in days("2026-08-01", "2026-08-04") { logA[d] = 1; logB[d] = 1 }
        logB["2026-08-02"] = nil
        let a = habit("A", log: logA), b = habit("B", log: logB)
        // 01. zählt, 02. reißt (B verfehlt), 03.–04. = 2er-Lauf.
        XCTAssertEqual(StatsEngine.bestOverallStreak(habits: [a, b],
                                                     today: wednesday, calendar: cal), 2)
    }

    func testBestOverallStreakEmptyLogsIsZero() {
        XCTAssertEqual(StatsEngine.bestOverallStreak(habits: [habit()],
                                                     today: wednesday, calendar: cal), 0)
    }

    // MARK: – Wochenbilanz (Montag-Wochen)

    func testThisWeekCompletionClipsAtTodayWithMondayWeeks() {
        // Täglich, Mo–Mi erledigt: 3 von 3 fälligen Tagen (Mo 03. … Mi 05.).
        let h = habit(log: ["2026-08-03": 1, "2026-08-04": 1, "2026-08-05": 1])
        let c = StatsEngine.thisWeekCompletion(habits: [h], today: wednesday, calendar: cal)
        XCTAssertEqual(c, StatsEngine.DayCompletion(done: 3, total: 3))
    }

    func testThisWeekCompletionCountsMissedDaysInDenominator() {
        let h = habit(log: ["2026-08-04": 1])   // nur Di
        let c = StatsEngine.thisWeekCompletion(habits: [h], today: wednesday, calendar: cal)
        XCTAssertEqual(c, StatsEngine.DayCompletion(done: 1, total: 3))
    }

    func testFlexibleWeeklyGoalCountsAsItsTimes() {
        let h = habit(recurrence: .times(3, per: .weekly),
                      log: ["2026-08-03": 1, "2026-08-04": 1])
        let c = StatsEngine.thisWeekCompletion(habits: [h], today: wednesday, calendar: cal)
        XCTAssertEqual(c, StatsEngine.DayCompletion(done: 2, total: 3))
    }

    func testPreviousWeekCompletionIsTheFullWeek() {
        // Vorwoche Mo 27.07. – So 02.08., täglich, 4 von 7 erledigt.
        var log: [String: Int] = [:]
        for d in ["2026-07-27", "2026-07-28", "2026-07-30", "2026-08-01"] { log[d] = 1 }
        let h = habit(log: log)
        let c = StatsEngine.previousWeekCompletion(habits: [h], today: wednesday, calendar: cal)
        XCTAssertEqual(c, StatsEngine.DayCompletion(done: 4, total: 7))
    }

    func testMomentumDeltaPoints() {
        let up = StatsEngine.momentumDeltaPoints(
            current: .init(done: 4, total: 5), previous: .init(done: 3, total: 5))
        XCTAssertEqual(up, 20)
        XCTAssertNil(StatsEngine.momentumDeltaPoints(
            current: .init(done: 0, total: 0), previous: .init(done: 3, total: 5)))
        XCTAssertNil(StatsEngine.momentumDeltaPoints(
            current: .init(done: 1, total: 2), previous: .init(done: 0, total: 0)))
    }

    func testLast7DailyFractionsOrderAndValues() {
        let h = habit(log: [wednesday: 1])   // nur heute erledigt
        let fractions = StatsEngine.last7DailyFractions(habits: [h],
                                                        today: wednesday, calendar: cal)
        XCTAssertEqual(fractions.count, 7)
        XCTAssertEqual(fractions.last ?? -1, 1, accuracy: 0.0001)   // heute zuletzt
        XCTAssertEqual(fractions.first ?? -1, 0, accuracy: 0.0001)  // vor 6 Tagen offen
    }

    // MARK: – Vereinigtes Raster

    func testMergedLevelsScaleAgainstTheWindowMaximum() {
        let both = ["2026-08-04": 1]
        let a = habit("A", log: both.merging([wednesday: 1]) { a, _ in a })
        let b = habit("B", log: both)
        let levels = StatsEngine.mergedLevels(habits: [a, b], weeks: 2,
                                              today: wednesday, calendar: cal)
        let flat = levels.flatMap { $0 }
        XCTAssertEqual(flat.max(), 4)               // Di: beide -> Maximum
        XCTAssertTrue(flat.contains(1))             // Mi: einer -> Stufe 1
        XCTAssertEqual(levels.count, 2)             // Spalten = Wochen
        XCTAssertEqual(levels[0].count, GridCalendar.rows)
    }

    func testMergedLevelsEmptyHabitsAreAllZero() {
        let levels = StatsEngine.mergedLevels(habits: [], weeks: 3,
                                              today: wednesday, calendar: cal)
        XCTAssertTrue(levels.flatMap { $0 }.allSatisfy { $0 == 0 })
    }

    func testMergedLevelsSingleHabitIsFullIntensity() {
        let h = habit(log: [wednesday: 1])
        let levels = StatsEngine.mergedLevels(habits: [h], weeks: 1,
                                              today: wednesday, calendar: cal)
        XCTAssertEqual(levels.flatMap { $0 }.max(), 4)
    }

    // MARK: – Schnappschuss-Memo

    func testSnapshotIsMemoizedPerInputAndDay() {
        StatsEngine.resetCache()
        let h = habit(log: [wednesday: 1])
        _ = StatsEngine.snapshot(habits: [h], today: wednesday, calendar: cal)
        _ = StatsEngine.snapshot(habits: [h], today: wednesday, calendar: cal)
        XCTAssertEqual(StatsEngine.computeCount, 1)

        var changed = h
        changed.log["2026-08-04"] = 1
        _ = StatsEngine.snapshot(habits: [changed], today: wednesday, calendar: cal)
        XCTAssertEqual(StatsEngine.computeCount, 2)

        _ = StatsEngine.snapshot(habits: [changed], today: "2026-08-06", calendar: cal)
        XCTAssertEqual(StatsEngine.computeCount, 3)
    }

    func testSnapshotCarriesAllCardInputs() {
        StatsEngine.resetCache()
        var log: [String: Int] = [:]
        for d in days("2026-08-01", wednesday) { log[d] = 1 }
        let h = habit("Lesen", log: log)
        let snap = StatsEngine.snapshot(habits: [h], today: wednesday, calendar: cal)
        XCTAssertEqual(snap.todayDone, 1)
        XCTAssertEqual(snap.todayTotal, 1)
        XCTAssertEqual(snap.streak, 5)
        XCTAssertEqual(snap.bestStreak, 5)
        XCTAssertEqual(snap.last7.count, 7)
        XCTAssertEqual(snap.mergedLevels.count, StatsEngine.pulseWeeks)
        XCTAssertEqual(snap.perHabit.first?.name, "Lesen")
        XCTAssertEqual(snap.perHabit.first?.current, 5)
    }

    func testSnapshotExcludesReminderItems() {
        var tracked = habit("Lesen", log: [wednesday: 1])
        tracked.createdAt = wednesday
        var reminder = Habit(name: "Tabletten", itemType: .reminder)
        reminder.createdAt = wednesday
        reminder.log[wednesday] = 1

        let snap = StatsEngine.snapshot(habits: [tracked, reminder],
                                        today: wednesday, calendar: cal)

        XCTAssertEqual(snap.todayDone, 1)
        XCTAssertEqual(snap.todayTotal, 1)
        XCTAssertEqual(snap.perHabit.map(\.name), ["Lesen"])
    }

    /// Reine Nein-Tage tragen die Verneinungsstufe statt leer zu bleiben —
    /// wer täglich antwortet (auch mit Nein), sieht einen Puls. Ein
    /// zählender Tag GEWINNT gegen ein Nein desselben Tages.
    func testMergedLevelsShowDeclinedOnlyDaysAsNegative() {
        var yesNo = Habit(name: "Kein Zucker", kind: .yesNo)
        yesNo.log["2026-08-07"] = Habit.Answer.no
        yesNo.log["2026-08-08"] = Habit.Answer.no
        var done = Habit(name: "Lesen")
        done.log["2026-08-08"] = 1

        let levels = StatsEngine.mergedLevels(habits: [yesNo, done], weeks: 4,
                                              today: "2026-08-09")
        // Zukunftstage haben KEINEN Schlüssel (nil) — nur echte Tage zuordnen.
        var flat: [String: Int] = [:]
        for (keyColumn, levelColumn) in zip(GridCalendar.keys(weeks: 4, today: "2026-08-09"),
                                            levels) {
            for (key, level) in zip(keyColumn, levelColumn) where key != nil {
                flat[key!] = level
            }
        }

        XCTAssertEqual(flat["2026-08-07"], Habit.Answer.declinedLevel)
        // Das Ja von „Lesen" übermalt das Nein desselben Tages.
        XCTAssertGreaterThanOrEqual(flat["2026-08-08"] ?? 0, 1)
        XCTAssertEqual(flat["2026-08-06"], 0)
    }
}
