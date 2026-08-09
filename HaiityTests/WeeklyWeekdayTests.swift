import XCTest
@testable import Haiity

/// „Einmal pro Woche, am Dienstag um 19:00" — Modell, Erfüllungsregel und
/// die Wahl des Benachrichtigungs-Triggers.
final class WeeklyWeekdayGoalTests: XCTestCase {

    // MARK: – Normalisierung

    func testFixedWeekdayForcesTimesToOne() {
        // „3× pro Woche, jeden Dienstag" ist keine sinnvolle Kombination —
        // der feste Tag gewinnt und zieht die Zahl auf 1.
        let goal = Goal(cadence: .weekly(times: 3), weekday: 3)
        XCTAssertEqual(goal.cadence, Goal.Cadence.weekly(times: 1))
        XCTAssertEqual(goal.weekday, 3)
        XCTAssertEqual(goal.weeklyTimes, 1)
    }

    func testWeeklyWithoutWeekdayKeepsTimes() {
        let goal = Goal.weekly(times: 4)
        XCTAssertEqual(goal.cadence, Goal.Cadence.weekly(times: 4))
        XCTAssertNil(goal.weekday)
    }

    func testWeekdayOutOfRangeIsDropped() {
        XCTAssertNil(Goal(cadence: .weekly(times: 2), weekday: 0).weekday)
        XCTAssertNil(Goal(cadence: .weekly(times: 2), weekday: 8).weekday)
        XCTAssertNil(Goal(cadence: .weekly(times: 2), weekday: -3).weekday)
        // Und weil der Tag wegfällt, bleibt times unangetastet.
        XCTAssertEqual(Goal(cadence: .weekly(times: 2), weekday: 99).cadence,
                       Goal.Cadence.weekly(times: 2))
    }

    func testWeekdayIsMeaninglessForDailyCadence() {
        let goal = Goal(cadence: .daily, restDays: [1], weekday: 4)
        XCTAssertNil(goal.weekday)
        XCTAssertNil(goal.weeklyTimes)
    }

    func testFactoryTakesWeekday() {
        let goal = Goal.weekly(times: 7, weekday: 6)
        XCTAssertEqual(goal.weekday, 6)
        XCTAssertEqual(goal.weeklyTimes, 1)
    }

    // MARK: – Codable (tolerant, ohne Versionssprung)

    func testRoundTripKeepsWeekday() throws {
        let goal = Goal(cadence: .weekly(times: 1), target: 2, weekday: 5)
        let raw = try JSONEncoder().encode(goal)
        XCTAssertEqual(try JSONDecoder().decode(Goal.self, from: raw), goal)
    }

    func testExistingWeeklyFileDecodesUnchanged() throws {
        // v2-Datei OHNE weekday: exakt wie vorher, times bleibt 3.
        let goal = try JSONDecoder().decode(
            Goal.self, from: Data(#"{"cadence":"weekly","times":3}"#.utf8))
        XCTAssertEqual(goal.cadence, Goal.Cadence.weekly(times: 3))
        XCTAssertNil(goal.weekday)
    }

    func testDecodeNormalizesTimesWhenWeekdayIsPresent() throws {
        let goal = try JSONDecoder().decode(
            Goal.self, from: Data(#"{"cadence":"weekly","times":5,"weekday":3}"#.utf8))
        XCTAssertEqual(goal.cadence, Goal.Cadence.weekly(times: 1))
        XCTAssertEqual(goal.weekday, 3)
    }

    func testDecodeDropsGarbageWeekday() throws {
        let goal = try JSONDecoder().decode(
            Goal.self, from: Data(#"{"cadence":"weekly","times":2,"weekday":13}"#.utf8))
        XCTAssertNil(goal.weekday)
        XCTAssertEqual(goal.cadence, Goal.Cadence.weekly(times: 2))
    }

    func testDailyGoalNeverWritesWeekday() throws {
        let raw = try JSONEncoder().encode(Goal(cadence: .daily, restDays: [1]))
        XCTAssertFalse((String(data: raw, encoding: .utf8) ?? "").contains("weekday"))
    }

    func testWeeklyWithoutWeekdayNeverWritesTheKey() throws {
        let raw = try JSONEncoder().encode(Goal.weekly(times: 2))
        XCTAssertFalse((String(data: raw, encoding: .utf8) ?? "").contains("weekday"))
    }

    func testGoalWithWeekdaySurvivesTheHabitFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-weekday-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url)
        store.add(Habit(name: "Waschen", goal: Goal.weekly(times: 1, weekday: 7)))
        XCTAssertEqual(HabitStore(url: url).habits[0].goal.weekday, 7)
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
                      goal: Goal(cadence: .weekly(times: 1), weekday: weekday))
        h.createdAt = "2026-07-01"
        for d in days { h.log[d] = 1 }
        return h
    }

    func testCheckInOnTheChosenWeekdaySatisfiesTheWeek() {
        let h = habit(["2026-08-04"], weekday: 3) // Dienstag
        XCTAssertTrue(GoalEngine.weekSatisfied(habit: h, day: "2026-08-04",
                                               today: "2026-08-09", calendar: calendar))
    }

    func testCheckInOnAnotherDayStillSatisfiesTheSameWeek() {
        // DIE Regel: kein Malus für zu früh oder zu spät. Der Dienstag war
        // verabredet, abgehakt wurde am Donnerstag — die Woche steht.
        let h = habit(["2026-08-06"], weekday: 3)
        XCTAssertTrue(GoalEngine.weekSatisfied(habit: h, day: "2026-08-04",
                                               today: "2026-08-09", calendar: calendar))
        XCTAssertTrue(GoalEngine.weekSatisfied(habit: h, day: "2026-08-06",
                                               today: "2026-08-09", calendar: calendar))
    }

    func testEmptyWeekIsNotSatisfied() {
        let h = habit([], weekday: 3)
        XCTAssertFalse(GoalEngine.weekSatisfied(habit: h, day: "2026-08-04",
                                                today: "2026-08-09", calendar: calendar))
    }

    func testCheckInInAnotherWeekDoesNotSatisfyThisOne() {
        let h = habit(["2026-07-28"], weekday: 3) // Vorwoche
        XCTAssertFalse(GoalEngine.weekSatisfied(habit: h, day: "2026-08-04",
                                                today: "2026-08-09", calendar: calendar))
    }

    func testQuantityTargetStillHasToBeMet() {
        // Ein Mengenziel bleibt ein Mengenziel: ein einzelner Zähler
        // erfüllt die Woche nicht, wenn das Tagesziel 3 ist.
        var h = habit([], weekday: 3)
        h.goal = Goal(cadence: .weekly(times: 1), target: 3, weekday: 3)
        h.log["2026-08-04"] = 2
        XCTAssertFalse(GoalEngine.weekSatisfied(habit: h, day: "2026-08-04",
                                                today: "2026-08-09", calendar: calendar))
        h.log["2026-08-04"] = 3
        XCTAssertTrue(GoalEngine.weekSatisfied(habit: h, day: "2026-08-04",
                                               today: "2026-08-09", calendar: calendar))
    }

    func testWeekSatisfiedFallsBackToTheDayForDailyGoals() {
        var h = Habit(name: "Lesen")
        h.log["2026-08-04"] = 1
        XCTAssertTrue(GoalEngine.weekSatisfied(habit: h, day: "2026-08-04",
                                               today: "2026-08-09", calendar: calendar))
        XCTAssertFalse(GoalEngine.weekSatisfied(habit: h, day: "2026-08-05",
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

/// Auswahl des Benachrichtigungs-Triggers — als reine Datenrechnung
/// prüfbar, ohne UNUserNotificationCenter.
final class ReminderPlanTests: XCTestCase {
    func testNoReminderNoPlan() {
        XCTAssertNil(Reminders.plan(for: Habit(name: "Lesen")))
    }

    func testDailyHabitGetsATriggerWithoutWeekday() {
        let h = Habit(name: "Lesen", reminderMinutes: 19 * 60 + 30)
        let plan = Reminders.plan(for: h)
        XCTAssertEqual(plan?.dateMatching.hour, 19)
        XCTAssertEqual(plan?.dateMatching.minute, 30)
        XCTAssertNil(plan?.dateMatching.weekday)
        XCTAssertEqual(plan?.isWeekly, false)
        XCTAssertEqual(plan?.repeats, true)
    }

    func testWeeklyWithFixedWeekdayGetsTheWeeklyTrigger() {
        let h = Habit(name: "Waschen", reminderMinutes: 9 * 60 + 5,
                      goal: Goal.weekly(times: 1, weekday: 7))
        let plan = Reminders.plan(for: h)
        XCTAssertEqual(plan?.dateMatching.weekday, 7)
        XCTAssertEqual(plan?.dateMatching.hour, 9)
        XCTAssertEqual(plan?.dateMatching.minute, 5)
        XCTAssertEqual(plan?.isWeekly, true)
        XCTAssertEqual(plan?.repeats, true)
    }

    func testWeeklyWithoutFixedWeekdayStaysDaily() {
        // „3× pro Woche" soll an allen Tagen erinnern — welche drei es
        // werden, entscheidet der Nutzer.
        let h = Habit(name: "Sport", reminderMinutes: 8 * 60, goal: .weekly(times: 3))
        XCTAssertEqual(Reminders.plan(for: h)?.isWeekly, false)
    }

    func testArchivedHabitsDoNotRing() {
        var h = Habit(name: "Alt", reminderMinutes: 60)
        h.archivedAt = "2026-08-01"
        XCTAssertNil(Reminders.plan(for: h))
    }

    func testGarbageMinutesAreIgnored() {
        var h = Habit(name: "Kaputt", reminderMinutes: 5000)
        XCTAssertNil(Reminders.plan(for: h))
        h.reminderMinutes = -1
        XCTAssertNil(Reminders.plan(for: h))
    }

    func testPlanCarriesEmojiAndName() {
        let h = Habit(name: "Lesen", emoji: "📚", reminderMinutes: 60)
        XCTAssertEqual(Reminders.plan(for: h)?.title, "📚 Lesen")
        XCTAssertEqual(Reminders.plan(for: h)?.identifier, Reminders.habitId(h.id))
        let plain = Habit(name: "Lesen", reminderMinutes: 60)
        XCTAssertEqual(Reminders.plan(for: plain)?.title, "Lesen")
    }

    func testSummaryPlanNeedsOpenHabitsAndAFutureTime() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 9, hour: 18))!

        XCTAssertNil(Reminders.summaryPlan(minutes: 20 * 60, openCount: 0, now: now, calendar: cal))
        XCTAssertNil(Reminders.summaryPlan(minutes: nil, openCount: 2, now: now, calendar: cal))
        // Zeit heute schon vorbei -> nichts planen.
        XCTAssertNil(Reminders.summaryPlan(minutes: 17 * 60, openCount: 2, now: now, calendar: cal))

        let plan = Reminders.summaryPlan(minutes: 20 * 60, openCount: 2, now: now, calendar: cal)
        XCTAssertEqual(plan?.identifier, Reminders.summaryId)
        XCTAssertEqual(plan?.repeats, false)
        XCTAssertEqual(plan?.dateMatching.hour, 20)
        XCTAssertEqual(plan?.dateMatching.day, 9)
    }
}
