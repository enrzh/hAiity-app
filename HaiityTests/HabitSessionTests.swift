import XCTest
@testable import Haiity

/// Sessions: die geplante Dauer am Habit, die tatsächlichen Minuten je Tag
/// und die reine Session-Arithmetik hinter der Live-Aktivität. Geprüft an
/// denselben drei Stellen wie jedes neue Feld: Platte, Merge, Rechnung —
/// plus der Trichter, durch den „Fertig" den Tag abhakt.
final class HabitSessionTests: XCTestCase {
    private var url: URL!
    private var store: HabitStore!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-\(UUID().uuidString).json")
        store = HabitStore(url: url)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    private func date(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    // MARK: – Platte (tolerant, kein Versionssprung)

    func testDurationSurvivesARoundTrip() throws {
        var habit = Habit(name: "Lesen", durationMinutes: 30)
        habit.minutes["2026-08-09"] = 25
        let raw = try JSONEncoder().encode(habit)
        let back = try JSONDecoder().decode(Habit.self, from: raw)
        XCTAssertEqual(back.durationMinutes, 30)
        XCTAssertEqual(back.minutes["2026-08-09"], 25)
    }

    func testNoSessionDataWritesNoKeys() throws {
        let raw = try JSONEncoder().encode(Habit(name: "Lesen"))
        let text = String(data: raw, encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("durationMinutes"))
        XCTAssertFalse(text.contains("\"minutes\""))
    }

    func testGarbageMinutesAreFilteredOnDecode() throws {
        var habit = Habit(name: "Lesen")
        habit.minutes = ["2026-08-09": 12]
        var raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(habit)) as! [String: Any]
        raw["minutes"] = ["2026-08-09": 12, "quatsch": 5, "2026-13-45": 9, "2026-08-08": 0]
        raw["durationMinutes"] = 100_000
        let back = try JSONDecoder().decode(Habit.self,
                                            from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertEqual(back.minutes, ["2026-08-09": 12])
        XCTAssertNil(back.durationMinutes, "Absurde Dauer liest als „ohne Dauer“, nicht als Fehler.")
    }

    func testSanitizedDurationBounds() {
        XCTAssertNil(Habit.sanitizedDuration(nil))
        XCTAssertNil(Habit.sanitizedDuration(0))
        XCTAssertNil(Habit.sanitizedDuration(-5))
        XCTAssertNil(Habit.sanitizedDuration(24 * 60 + 1))
        XCTAssertEqual(Habit.sanitizedDuration(1), 1)
        XCTAssertEqual(Habit.sanitizedDuration(24 * 60), 24 * 60)
    }

    // MARK: – Arithmetik

    func testElapsedMinutesRoundsDownWithFloorOfOne() {
        XCTAssertEqual(HabitSessionMath.elapsedMinutes(startedAt: date(0), endedAt: date(40)), 1,
                       "40 Sekunden sind eine Session, keine Null.")
        XCTAssertEqual(HabitSessionMath.elapsedMinutes(startedAt: date(0), endedAt: date(25 * 60 + 59)), 25)
        XCTAssertEqual(HabitSessionMath.elapsedMinutes(startedAt: date(100), endedAt: date(0)), 1,
                       "Zurückgestellte Uhr fällt auf 1, nicht auf Unsinn.")
    }

    func testStaleCutoffAtEightHours() {
        XCTAssertFalse(HabitSessionMath.isStale(startedAt: date(0), now: date(8 * 3600 - 1)))
        XCTAssertTrue(HabitSessionMath.isStale(startedAt: date(0), now: date(8 * 3600)))
    }

    func testPlannedEndAndProgress() {
        XCTAssertNil(HabitSessionMath.plannedEnd(startedAt: date(0), plannedMinutes: nil))
        XCTAssertEqual(HabitSessionMath.plannedEnd(startedAt: date(0), plannedMinutes: 30), date(1800))
        XCTAssertNil(HabitSessionMath.progress(actualMinutes: 10, plannedMinutes: nil),
                     "Limitless hat keinen Fortschritt, nur eine Dauer.")
        XCTAssertEqual(HabitSessionMath.progress(actualMinutes: 15, plannedMinutes: 30), 0.5)
        XCTAssertEqual(HabitSessionMath.progress(actualMinutes: 90, plannedMinutes: 30), 1,
                       "Überziehen deckelt bei 1.")
        XCTAssertEqual(HabitSessionMath.progress(actualMinutes: -5, plannedMinutes: 30), 0)
    }

    func testDurationText() {
        XCTAssertEqual(HabitSessionMath.durationText(minutes: 45), "45 Min")
        XCTAssertEqual(HabitSessionMath.durationText(minutes: 60), "1 Std")
        XCTAssertEqual(HabitSessionMath.durationText(minutes: 65), "1 Std 5 Min")
        XCTAssertEqual(HabitSessionMath.durationText(minutes: 120), "2 Std")
    }

    // MARK: – Store: Minuten schreiben

    func testRecordSessionMinutesTakesTheMaximum() {
        let habit = Habit(name: "Lesen", durationMinutes: 30)
        store.add(habit)
        store.recordSessionMinutes(habit.id, day: "2026-08-09", minutes: 25)
        store.recordSessionMinutes(habit.id, day: "2026-08-09", minutes: 10)
        XCTAssertEqual(store.habits[0].minutes["2026-08-09"], 25,
                       "Eine kürzere zweite Session rechnet die längere nicht klein.")
        store.recordSessionMinutes(habit.id, day: "2026-08-09", minutes: 40)
        XCTAssertEqual(store.habits[0].minutes["2026-08-09"], 40)
    }

    func testRecordSessionMinutesRejectsGarbage() {
        let habit = Habit(name: "Lesen")
        store.add(habit)
        store.recordSessionMinutes(habit.id, day: "quatsch", minutes: 10)
        store.recordSessionMinutes(habit.id, day: "2026-08-09", minutes: 0)
        store.recordSessionMinutes(UUID(), day: "2026-08-09", minutes: 10)
        XCTAssertTrue(store.habits[0].minutes.isEmpty)
    }

    // MARK: – Fertig: derselbe Trichter wie jeder Check-in

    func testFinishMarksDayAndRecordsMinutes() {
        let habit = Habit(name: "Lesen", durationMinutes: 30)
        store.add(habit)
        let session = HabitSession(habitID: habit.id, day: "2026-08-09",
                                   startedAt: date(0), plannedMinutes: 30)
        let minutes = HabitSessionCompletion.finish(store: store, session: session,
                                                    now: date(25 * 60))
        XCTAssertEqual(minutes, 25)
        XCTAssertEqual(store.habits[0].log["2026-08-09"], 1)
        XCTAssertEqual(store.habits[0].minutes["2026-08-09"], 25)
    }

    func testFinishPersistsExactRecordOnceAndIsIdempotent() {
        let habit = Habit(name: "Lesen", durationMinutes: 30)
        store.add(habit)
        let session = HabitSession(id: UUID(), habitID: habit.id, day: "2026-08-09",
                                   startedAt: date(10), plannedMinutes: 30)

        HabitSessionCompletion.finish(store: store, session: session, now: date(25 * 60 + 10))
        HabitSessionCompletion.finish(store: store, session: session, now: date(50 * 60 + 10))

        XCTAssertEqual(store.sessionHistory, [
            HabitSessionRecord(id: session.id, habitID: habit.id, day: "2026-08-09",
                               startedAt: date(10), finishedAt: date(25 * 60 + 10),
                               plannedMinutes: 30)
        ])
        XCTAssertEqual(store.habits[0].minutes["2026-08-09"], 25)
    }

    func testSessionHistoryDefaultsToEmptyAndMergesByStableID() throws {
        let habit = Habit(name: "Lesen")
        let oldPayload = HabitData(version: HabitData.currentVersion, updatedAt: 0,
                                   summaryMinutes: nil, habits: [habit])
        let decoded = try JSONDecoder().decode(HabitData.self,
                                               from: JSONEncoder().encode(oldPayload))
        XCTAssertTrue(decoded.sessionHistory.isEmpty)

        let record = HabitSessionRecord(id: UUID(), habitID: habit.id, day: "2026-08-09",
                                        startedAt: date(0), finishedAt: date(120),
                                        plannedMinutes: 30)
        store.add(habit)
        store.merge(remote: HabitData(version: HabitData.currentVersion, updatedAt: 1,
                                      summaryMinutes: nil, habits: [habit],
                                      sessionHistory: [record]))
        store.merge(remote: HabitData(version: HabitData.currentVersion, updatedAt: 2,
                                      summaryMinutes: nil, habits: [habit],
                                      sessionHistory: [record]))

        XCTAssertEqual(store.sessionHistory, [record])
        XCTAssertTrue(store.habits[0].minutes.isEmpty,
                      "Importing exact records must not double-add legacy day totals.")
    }

    func testCancellingOrDiscardingStaleSessionCreatesNoHistory() {
        let habit = Habit(name: "Lesen")
        store.add(habit)
        let session = HabitSession(id: UUID(), habitID: habit.id, day: "2026-08-09",
                                   startedAt: date(0), plannedMinutes: 30)

        HabitSessionCompletion.cancel(store: store, session: session)
        HabitSessionCompletion.discardStale(store: store, session: session)

        XCTAssertTrue(store.sessionHistory.isEmpty)
        XCTAssertNil(store.habits[0].log["2026-08-09"])
        XCTAssertNil(store.habits[0].minutes["2026-08-09"])
    }

    func testFinishOnQuantityIncrementsAndOnYesNoAffirms() {
        let quantity = Habit(name: "Wasser", recurrence: .init(frequency: .daily, target: 3))
        var yesNo = Habit(name: "Kein Zucker?", kind: .yesNo)
        yesNo.log["2026-08-09"] = Habit.Answer.no
        store.add(quantity)
        store.add(yesNo)
        HabitSessionCompletion.finish(
            store: store,
            session: HabitSession(habitID: quantity.id, day: "2026-08-09",
                                  startedAt: date(0), plannedMinutes: nil),
            now: date(600))
        HabitSessionCompletion.finish(
            store: store,
            session: HabitSession(habitID: yesNo.id, day: "2026-08-09",
                                  startedAt: date(0), plannedMinutes: nil),
            now: date(600))
        XCTAssertEqual(store.habits[0].log["2026-08-09"], 1, "Menge: +1 wie der Widget-Knopf.")
        XCTAssertEqual(store.habits[1].log["2026-08-09"], Habit.Answer.yes,
                       "Ja/Nein: „Fertig“ meint Ja — auch über ein Nein hinweg.")
        XCTAssertEqual(store.habits[1].minutes["2026-08-09"], 10)
    }

    func testFinishOnDoneCheckboxStillRecordsMinutes() {
        var habit = Habit(name: "Lesen")
        habit.log["2026-08-09"] = 1
        store.add(habit)
        HabitSessionCompletion.finish(
            store: store,
            session: HabitSession(habitID: habit.id, day: "2026-08-09",
                                  startedAt: date(0), plannedMinutes: nil),
            now: date(900))
        XCTAssertEqual(store.habits[0].log["2026-08-09"], 1, "Idempotent — nie ent-haken.")
        XCTAssertEqual(store.habits[0].minutes["2026-08-09"], 15)
    }

    // MARK: – Merge

    func testMergeUnionsMinutesAndCarriesDuration() {
        var local = Habit(name: "Lesen", durationMinutes: 30)
        local.minutes = ["2026-08-08": 20, "2026-08-09": 10]
        store.add(local)

        var remoteHabit = local
        remoteHabit.durationMinutes = 45
        remoteHabit.minutes = ["2026-08-09": 30, "2026-08-10": 5]
        let remote = HabitData(version: HabitData.currentVersion,
                               updatedAt: Date().timeIntervalSince1970 + 100,
                               summaryMinutes: nil, habits: [remoteHabit])
        store.merge(remote: remote)

        let merged = store.habits[0]
        XCTAssertEqual(merged.minutes, ["2026-08-08": 20, "2026-08-09": 30, "2026-08-10": 5],
                       "Union mit MAX pro Tag — nichts verschwindet.")
        XCTAssertEqual(merged.durationMinutes, 45, "Neuerer Stand gewinnt die Dauer.")
    }

    func testMergeOlderRemoteKeepsLocalDuration() {
        let local = Habit(name: "Lesen", durationMinutes: 30)
        store.add(local)
        var remoteHabit = local
        remoteHabit.durationMinutes = nil
        let remote = HabitData(version: HabitData.currentVersion, updatedAt: 0,
                               summaryMinutes: nil, habits: [remoteHabit])
        store.merge(remote: remote)
        XCTAssertEqual(store.habits[0].durationMinutes, 30)
    }

    // MARK: – Ablage der laufenden Session

    func testSessionStorageRoundTripAndClear() {
        let defaults = UserDefaults(suiteName: "session-tests")!
        defaults.removePersistentDomain(forName: "session-tests")
        XCTAssertNil(HabitSessionStorage.load(from: defaults))
        let session = HabitSession(habitID: UUID(), day: "2026-08-09",
                                   startedAt: date(1000), plannedMinutes: 30)
        HabitSessionStorage.save(session, to: defaults)
        XCTAssertEqual(HabitSessionStorage.load(from: defaults), session)
        HabitSessionStorage.clear(from: defaults)
        XCTAssertNil(HabitSessionStorage.load(from: defaults))
        defaults.removePersistentDomain(forName: "session-tests")
    }
}
