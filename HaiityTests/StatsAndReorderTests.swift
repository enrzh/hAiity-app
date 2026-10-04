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

    func testMoveVisibleFirstAndLastDestinationsPersistAcrossReload() {
        let habits = (0..<40).map {
            Habit(name: "Item \($0)", itemType: $0.isMultiple(of: 2) ? .habit : .reminder)
        }
        for habit in habits { store.add(habit) }
        let ids = habits.map(\.id)
        let lastFirst = [ids.last!] + Array(ids.dropLast())

        XCTAssertTrue(store.moveVisible(ids, fromOffsets: IndexSet(integer: 39), toOffset: 0))
        XCTAssertEqual(store.habits.map(\.id), lastFirst)
        XCTAssertEqual(HabitStore(url: url).habits.map(\.id), lastFirst)
        XCTAssertNil(store.lastWriteError)

        XCTAssertTrue(store.moveVisible(lastFirst, fromOffsets: IndexSet(integer: 0), toOffset: 40))
        XCTAssertEqual(store.habits.map(\.id), ids)
        XCTAssertEqual(HabitStore(url: url).habits.map(\.id), ids)
    }

    func testMoveVisibleReordersHeuteItemsWithoutMovingHiddenActiveOrArchivedSlots() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 12)))
        let hiddenBefore = Habit(name: "Nicht heute", recurrence: .weekdays([2]))
        let first = Habit(name: "Erster")
        let hiddenBetween = Habit(name: "Auch nicht heute", recurrence: .weekdays([2]))
        let archived = Habit(name: "Archiviert")
        let second = Habit(name: "Zweiter", itemType: .reminder)
        let third = Habit(name: "Dritter")
        store.add(hiddenBefore)
        store.add(first)
        store.add(hiddenBetween)
        store.add(archived)
        store.add(second)
        store.add(third)
        store.archive(archived.id)
        let archivedBefore = try XCTUnwrap(store.habits.first { $0.id == archived.id })
        let filter = HabitListFilter(todayOnly: true)
        let visibleIDs = store.activeHabits.filter {
            filter.matches($0, defaultTimeZoneIdentifier: nil, now: now, base: calendar)
        }.map(\.id)
        XCTAssertEqual(visibleIDs, [first.id, second.id, third.id])

        XCTAssertTrue(store.moveVisible(visibleIDs,
                                        fromOffsets: IndexSet(integer: 0),
                                        toOffset: 3))

        XCTAssertEqual(store.habits.map(\.name),
                       ["Nicht heute", "Zweiter", "Auch nicht heute", "Archiviert", "Dritter", "Erster"])
        XCTAssertEqual(store.habits[3].archivedAt, archivedBefore.archivedAt)
        XCTAssertEqual(HabitStore(url: url).habits.map(\.id), store.habits.map(\.id))
    }

    func testMoveVisibleRejectsSameMembershipStaleOrderBeforeMutation() throws {
        let a = Habit(name: "A"), b = Habit(name: "B"), c = Habit(name: "C")
        store.add(a); store.add(b); store.add(c)
        let staleIDs = [a.id, b.id, c.id]
        XCTAssertTrue(store.moveVisible(staleIDs, fromOffsets: IndexSet(integer: 2), toOffset: 0))
        let before = try Data(contentsOf: url)
        let timestamp = store.data.updatedAt
        var notifications = 0
        store.onChange = { notifications += 1 }

        XCTAssertFalse(store.moveVisible(staleIDs, fromOffsets: IndexSet(integer: 0), toOffset: 3))
        XCTAssertFalse(store.moveVisible(staleIDs, fromOffsets: IndexSet(integer: 0), toOffset: 3,
                                         persist: false))
        XCTAssertEqual(store.habits.map(\.id), [c.id, a.id, b.id])
        XCTAssertEqual(store.data.updatedAt, timestamp)
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(notifications, 0)
    }

    func testMoveVisibleNoOpsDoNotWriteOrNotify() throws {
        let a = Habit(name: "A"), b = Habit(name: "B"), c = Habit(name: "C")
        store.add(a); store.add(b); store.add(c)
        let ids = [a.id, b.id, c.id]
        // A fixed old mtime makes an accidental rewrite observable without sleeping.
        let mtime = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
        let before = try Data(contentsOf: url)
        let beforeMtime = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let timestamp = store.data.updatedAt
        var notifications = 0
        store.onChange = { notifications += 1 }

        for destination in [1, 2] {
            XCTAssertFalse(store.moveVisible(ids, fromOffsets: IndexSet(integer: 1), toOffset: destination))
        }
        XCTAssertFalse(store.moveVisible(ids, fromOffsets: IndexSet([0, 1]), toOffset: 2))
        XCTAssertFalse(store.moveVisible(ids, fromOffsets: IndexSet(integer: 0), toOffset: 0,
                                         persist: false))
        XCTAssertEqual(store.habits.map(\.id), ids)
        XCTAssertEqual(store.data.updatedAt, timestamp)
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                       beforeMtime)
        XCTAssertEqual(notifications, 0)
    }

    func testMoveVisibleWithoutPersistenceChangesOnlyMemory() throws {
        let a = Habit(name: "A"), b = Habit(name: "B")
        store.add(a); store.add(b)
        let before = try Data(contentsOf: url)
        let timestamp = store.data.updatedAt
        var notifications = 0
        store.onChange = { notifications += 1 }

        XCTAssertTrue(store.moveVisible([a.id, b.id], fromOffsets: IndexSet(integer: 0), toOffset: 2,
                                        persist: false))
        XCTAssertEqual(store.habits.map(\.id), [b.id, a.id])
        XCTAssertEqual(store.data.updatedAt, timestamp)
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(notifications, 0)
    }

    func testMoveVisibleStaleSaveRestoresDurableOrderAndReportsFailure() throws {
        let a = Habit(name: "A"), b = Habit(name: "B"), c = Habit(name: "C")
        store.add(a); store.add(b); store.add(c)
        let ids = [a.id, b.id, c.id]
        let stale = HabitStore(url: url)
        XCTAssertTrue(store.moveVisible(ids, fromOffsets: IndexSet(integer: 2), toOffset: 0))
        let durable = try Data(contentsOf: url)
        var notifications = 0
        stale.onChange = { notifications += 1 }

        XCTAssertFalse(stale.moveVisible(ids, fromOffsets: IndexSet(integer: 0), toOffset: 3))
        XCTAssertEqual(stale.habits.map(\.id), [c.id, a.id, b.id])
        XCTAssertEqual(stale.data.updatedAt, store.data.updatedAt)
        XCTAssertEqual(stale.lastWriteError,
                       String(localized: "Die Daten wurden inzwischen geändert. Bitte erneut sichern."))
        XCTAssertThrowsError(try stale.requireSuccessfulWrite())
        XCTAssertEqual(try Data(contentsOf: url), durable)
        XCTAssertEqual(notifications, 0)

        XCTAssertTrue(stale.moveVisible(stale.activeHabits.map(\.id),
                                        fromOffsets: IndexSet(integer: 0), toOffset: 3))
        XCTAssertNil(stale.lastWriteError)
        XCTAssertEqual(HabitStore(url: url).habits.map(\.id), ids)
        XCTAssertEqual(notifications, 1)
    }

    func testMoveVisibleFileWriteFailureRestoresLocalOrderAndKeepsErrorAvailable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("readonly-reorder-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let failingURL = directory.appendingPathComponent("data.json")
        let failing = HabitStore(url: failingURL)
        let a = Habit(name: "A"), b = Habit(name: "B")
        failing.add(a); failing.add(b)
        XCTAssertNil(failing.lastWriteError)
        let durable = try Data(contentsOf: failingURL)
        let timestamp = failing.data.updatedAt
        var notifications = 0
        failing.onChange = { notifications += 1 }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)

        XCTAssertFalse(failing.moveVisible([a.id, b.id], fromOffsets: IndexSet(integer: 0), toOffset: 2))
        XCTAssertEqual(failing.habits.map(\.id), [a.id, b.id])
        XCTAssertEqual(failing.data.updatedAt, timestamp)
        let message = try XCTUnwrap(failing.lastWriteError)
        XCTAssertFalse(message.isEmpty)
        XCTAssertNotEqual(message,
                          String(localized: "Die Daten wurden inzwischen geändert. Bitte erneut sichern."))
        XCTAssertThrowsError(try failing.requireSuccessfulWrite()) { error in
            XCTAssertEqual(error.localizedDescription, message)
        }
        XCTAssertEqual(try Data(contentsOf: failingURL), durable)
        XCTAssertEqual(HabitStore(url: failingURL).habits.map(\.id), [a.id, b.id])
        XCTAssertEqual(notifications, 0)

        let errorBeforeNoOp = failing.lastWriteError
        XCTAssertFalse(failing.moveVisible([a.id, b.id], fromOffsets: IndexSet(integer: 0), toOffset: 1))
        XCTAssertEqual(failing.lastWriteError, errorBeforeNoOp)
    }

    func testMoveVisibleRejectsInvalidMembershipAndBoundsWithoutWriting() throws {
        let a = Habit(name: "A"), b = Habit(name: "B"), archived = Habit(name: "Archived")
        store.add(a); store.add(b); store.add(archived)
        store.archive(archived.id)
        let before = try Data(contentsOf: url)
        let ids = store.habits.map(\.id)
        for visibleIDs in [[], [a.id, a.id], [a.id, UUID()], [a.id, archived.id]] {
            XCTAssertFalse(store.moveVisible(visibleIDs, fromOffsets: IndexSet(integer: 0), toOffset: 2))
        }
        XCTAssertFalse(store.moveVisible([a.id, b.id], fromOffsets: [], toOffset: 0))
        XCTAssertFalse(store.moveVisible([a.id, b.id], fromOffsets: IndexSet([0, 2]), toOffset: 0))
        for destination in [-1, 3] {
            XCTAssertFalse(store.moveVisible([a.id, b.id], fromOffsets: IndexSet(integer: 0), toOffset: destination))
        }
        XCTAssertEqual(store.habits.map(\.id), ids)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testMoveVisibleRejectsDuplicateStoredIDsWithoutTrapping() throws {
        let a = Habit(name: "A"), b = Habit(name: "B")
        store.add(a); store.add(b); store.add(a)
        let before = try Data(contentsOf: url)

        XCTAssertFalse(store.moveVisible([a.id, b.id], fromOffsets: IndexSet(integer: 0), toOffset: 2))
        XCTAssertEqual(store.habits.map(\.id), [a.id, b.id, a.id])
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testStaleOffsetsCannotCorruptTheOrderAfterAnItemIsRemoved() throws {
        let a = Habit(name: "A"), b = Habit(name: "B"), c = Habit(name: "C")
        store.add(a); store.add(b); store.add(c)
        store.remove(c.id)
        let before = try Data(contentsOf: url)
        XCTAssertFalse(store.moveVisible([a.id, b.id, c.id], fromOffsets: IndexSet(integer: 2), toOffset: 0))
        XCTAssertFalse(store.moveVisible([a.id, b.id], fromOffsets: IndexSet(integer: 2), toOffset: 0))
        XCTAssertFalse(store.moveVisible([a.id, b.id], fromOffsets: IndexSet(integer: 0), toOffset: 3))
        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        store.move(fromOffsets: IndexSet(integer: 0), toOffset: -1)
        XCTAssertEqual(store.habits.map(\.id), [a.id, b.id])
        XCTAssertEqual(try Data(contentsOf: url), before, "a stale move must not write a new snapshot")
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

    /// The seven-day strip reuses the contribution ramp, so a day fraction has
    /// to land on the same 0…4 buckets the graphs use. 0 stays "empty", 100% is
    /// the only level 4, and neighbouring days in the common 60–90% band must
    /// not collapse onto the same square.
    func testStatsDayLevelMapsFractionsOntoTheContributionRamp() {
        XCTAssertEqual(StatsView.statsDayLevel(0), 0)
        XCTAssertEqual(StatsView.statsDayLevel(0.01), 1)
        XCTAssertEqual(StatsView.statsDayLevel(0.25), 1)
        XCTAssertEqual(StatsView.statsDayLevel(0.5), 2)
        XCTAssertEqual(StatsView.statsDayLevel(0.67), 2)
        XCTAssertEqual(StatsView.statsDayLevel(0.75), 3)
        XCTAssertEqual(StatsView.statsDayLevel(0.99), 3)
        XCTAssertEqual(StatsView.statsDayLevel(1.0), 4)
        XCTAssertEqual(StatsView.statsDayLevel(4.0), 4)
        XCTAssertEqual(StatsView.statsDayLevel(-1), 0)
        XCTAssertNotEqual(StatsView.statsDayLevel(0.67), StatsView.statsDayLevel(0.75),
                          "a 67% and a 75% day must not look identical")
    }
}
