import XCTest
@testable import Haiity

/// Phase-B-Logik: Drag-Reihenfolge (store.move) inkl. Persistenz und
/// Archiv-Interaktion.
final class ReorderTests: XCTestCase {
    private var url: URL!
    private var store: HabitStore!

    override func setUp() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-test-\(UUID().uuidString).json")
        store = HabitStore(url: url)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    func testMoveReordersActiveHabits() {
        store.add(Habit(name: "A")); store.add(Habit(name: "B")); store.add(Habit(name: "C"))
        store.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(store.activeHabits.map(\.name), ["B", "C", "A"])
    }

    func testMovePersistsAcrossReload() {
        store.add(Habit(name: "A")); store.add(Habit(name: "B")); store.add(Habit(name: "C"))
        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        let reloaded = HabitStore(url: url)
        XCTAssertEqual(reloaded.activeHabits.map(\.name), ["C", "A", "B"])
    }

    func testMoveOffsetsReferToActiveListArchivedKeepPosition() {
        let a = Habit(name: "A"), b = Habit(name: "B"), c = Habit(name: "C"), d = Habit(name: "D")
        store.add(a); store.add(b); store.add(c); store.add(d)
        store.archive(b.id)
        // Aktiv sichtbar: A, C, D — A ans Ende ziehen.
        store.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(store.activeHabits.map(\.name), ["C", "D", "A"])
        // B bleibt an seiner Position im Gesamtarray (Index 1).
        XCTAssertEqual(store.habits.map(\.name), ["C", "B", "D", "A"])
    }

    func testMoveVisibleReordersHeuteItemsWithoutMovingHiddenActiveItems() {
        let hiddenBefore = Habit(name: "Nicht heute")
        let first = Habit(name: "Erster")
        let hiddenBetween = Habit(name: "Auch nicht heute")
        let second = Habit(name: "Zweiter")
        let third = Habit(name: "Dritter")
        store.add(hiddenBefore)
        store.add(first)
        store.add(hiddenBetween)
        store.add(second)
        store.add(third)

        store.moveVisible([first.id, second.id, third.id],
                          fromOffsets: IndexSet(integer: 0),
                          toOffset: 3)

        XCTAssertEqual(store.habits.map(\.name),
                       ["Nicht heute", "Zweiter", "Auch nicht heute", "Dritter", "Erster"])
    }

    func testArchiveUnarchiveRoundTripKeepsSlot() {
        let a = Habit(name: "A"), b = Habit(name: "B"), c = Habit(name: "C")
        store.add(a); store.add(b); store.add(c)
        store.archive(b.id)
        XCTAssertEqual(store.activeHabits.map(\.name), ["A", "C"])
        store.unarchive(b.id)
        XCTAssertEqual(store.activeHabits.map(\.name), ["A", "B", "C"]) // Platz bleibt
    }

    func testAddingOneTimeCopyCanPlaceItImmediatelyAfterItsSource() {
        let source = Habit(name: "Quelle")
        let other = Habit(name: "Andere")
        store.add(source)
        store.add(other)

        store.add(source.oneTimeCopy(on: "2026-09-02"), after: source.id)

        XCTAssertEqual(store.activeHabits.map(\.name), ["Quelle", "Quelle", "Andere"])
        XCTAssertEqual(store.activeHabits[1].recurrence.frequency, .once)
    }
}

/// Statistik-Mathematik: Monats-Bucketing, Summen und Quoten-Fenster gegen
/// Fixture-Logs. Kalender wie in den GoalEngine-Tests: Berlin, Montag.
final class StatsMathTests: XCTestCase {
    private var berlin: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }

    private func habit(_ days: [String: Int], recurrence: Recurrence = .daily, createdAt: String = "2025-01-01") -> Habit {
        var h = Habit(name: "Test", recurrence: recurrence)
        h.createdAt = createdAt
        for (d, v) in days { h.log[d] = v }
        return h
    }

    // MARK: – yearMonth

    func testYearMonthParsesValidKey() {
        XCTAssertEqual(StatsMath.yearMonth("2026-08-09")?.year, 2026)
        XCTAssertEqual(StatsMath.yearMonth("2026-08-09")?.month, 8)
    }

    func testYearMonthRejectsGarbage() {
        XCTAssertNil(StatsMath.yearMonth("kaputt"))
        XCTAssertNil(StatsMath.yearMonth("2026-13-01")) // Monat 13 gibt es nicht
        XCTAssertNil(StatsMath.yearMonth("2026-08"))    // kein Tagesschlüssel
    }

    // MARK: – monthlyCounts

    func testMonthlyCountsBucketsByMonth() {
        let h = habit(["2026-08-01": 1, "2026-08-09": 1, "2026-07-15": 1])
        let counts = StatsMath.monthlyCounts(habit: h, months: 12, today: "2026-08-09", calendar: berlin)
        XCTAssertEqual(counts.count, 12)
        XCTAssertEqual(counts[11], 2) // August (aktueller Monat, letzter Eintrag)
        XCTAssertEqual(counts[10], 1) // Juli
        XCTAssertEqual(counts[0...9].reduce(0, +), 0)
    }

    func testMonthlyCountsSpansYearBoundary() {
        // Fenster bei today=2026-02-10, 12 Monate: März 2025 … Februar 2026.
        let h = habit(["2025-12-24": 1, "2025-03-01": 1, "2025-02-28": 1])
        let counts = StatsMath.monthlyCounts(habit: h, months: 12, today: "2026-02-10", calendar: berlin)
        XCTAssertEqual(counts[9], 1)  // Dezember 2025
        XCTAssertEqual(counts[0], 1)  // März 2025 (ältester Monat im Fenster)
        XCTAssertEqual(counts.reduce(0, +), 2) // Februar 2025 fällt raus
    }

    func testMonthlyCountsExcludesFutureMonths() {
        let h = habit(["2026-09-01": 1, "2026-08-05": 1])
        let counts = StatsMath.monthlyCounts(habit: h, months: 12, today: "2026-08-09", calendar: berlin)
        XCTAssertEqual(counts.reduce(0, +), 1) // September (Zukunft) zählt nicht
    }

    func testMonthlyCountsRespectsQuantityTarget() {
        let h = habit(["2026-08-01": 2, "2026-08-02": 3, "2026-08-03": 5],
                      recurrence: Recurrence(target: 3))
        let counts = StatsMath.monthlyCounts(habit: h, months: 12, today: "2026-08-09", calendar: berlin)
        XCTAssertEqual(counts[11], 2) // nur Tage >= target zählen
    }

    func testMonthlyCountsIgnoresGarbageKeys() {
        let h = habit(["müll": 1, "2026-08-05": 1])
        let counts = StatsMath.monthlyCounts(habit: h, months: 12, today: "2026-08-09", calendar: berlin)
        XCTAssertEqual(counts.reduce(0, +), 1)
    }

    func testMonthlyCountsZeroMonthsIsEmpty() {
        XCTAssertEqual(StatsMath.monthlyCounts(habit: habit([:]), months: 0,
                                               today: "2026-08-09", calendar: berlin), [])
    }

    // MARK: – totalCheckIns

    func testTotalCheckInsSumsCountingDays() {
        let a = habit(["2026-08-01": 1, "2026-08-02": 1])
        let b = habit(["2026-08-01": 2, "2026-08-02": 5], recurrence: Recurrence(target: 3))
        // b: nur der 02. erreicht das Ziel.
        XCTAssertEqual(StatsMath.totalCheckIns([a, b], calendar: berlin), 3)
    }

    func testTotalCheckInsEmpty() {
        XCTAssertEqual(StatsMath.totalCheckIns([], calendar: berlin), 0)
        XCTAssertEqual(StatsMath.totalCheckIns([habit([:])], calendar: berlin), 0)
    }

    // MARK: – Quoten-Fenster (GoalEngine.completion, wie die Statistik sie nutzt)

    func testCompletionWindow30Days() {
        // 2026-08-01 … 2026-08-09 erledigt = 9 zählende Tage im 30er-Fenster.
        var days: [String: Int] = [:]
        for d in 1...9 { days[String(format: "2026-08-%02d", d)] = 1 }
        let h = habit(days)
        XCTAssertEqual(GoalEngine.completion(habit: h, lastNDays: 30, today: "2026-08-09", calendar: berlin),
                       9.0 / 30.0, accuracy: 0.0001)
    }

    func testCompletionWindow90Days() {
        var days: [String: Int] = [:]
        for d in 1...9 { days[String(format: "2026-08-%02d", d)] = 1 }
        let h = habit(days)
        XCTAssertEqual(GoalEngine.completion(habit: h, lastNDays: 90, today: "2026-08-09", calendar: berlin),
                       9.0 / 90.0, accuracy: 0.0001)
    }

    func testCompletionWindow365Days() {
        var days: [String: Int] = [:]
        for d in 1...9 { days[String(format: "2026-08-%02d", d)] = 1 }
        let h = habit(days)
        XCTAssertEqual(GoalEngine.completion(habit: h, lastNDays: 365, today: "2026-08-09", calendar: berlin),
                       9.0 / 365.0, accuracy: 0.0001)
    }
}
