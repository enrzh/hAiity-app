import XCTest
@testable import Haiity

final class StoreAndMergeTests: XCTestCase {
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

    func testPersistAndReload() {
        var h = Habit(name: "Lesen", emoji: "📖")
        h.log["2026-08-01"] = 1
        store.add(h)
        let reloaded = HabitStore(url: url)
        XCTAssertEqual(reloaded.habits.count, 1)
        XCTAssertEqual(reloaded.habits[0].name, "Lesen")
        XCTAssertTrue(reloaded.habits[0].isDone("2026-08-01"))
    }

    func testToggleSetsAndClears() {
        let h = Habit(name: "Sport")
        store.add(h)
        store.toggle(h.id, day: "2026-08-09")
        XCTAssertTrue(store.habits[0].isDone("2026-08-09"))
        store.toggle(h.id, day: "2026-08-09")
        XCTAssertFalse(store.habits[0].isDone("2026-08-09"))
    }

    func testOpenTodayListsUncheckedOnly() {
        let a = Habit(name: "A"), b = Habit(name: "B")
        store.add(a); store.add(b)
        store.toggle(a.id, day: DayKey.today())
        let open = store.openToday()
        XCTAssertEqual(open.map(\.name), ["B"])
    }

    // MARK: – Merge-Semantik (Union: ein Check-in irgendwo zählt)

    func testMergeUnionsLogs() {
        var local = Habit(name: "Lesen")
        local.log["2026-08-01"] = 1
        store.add(local)

        var remoteHabit = local
        remoteHabit.log = ["2026-08-02": 1]
        let remote = HabitData(version: 1, updatedAt: 0, summaryMinutes: nil, habits: [remoteHabit])
        store.merge(remote: remote)

        XCTAssertTrue(store.habits[0].isDone("2026-08-01"))
        XCTAssertTrue(store.habits[0].isDone("2026-08-02"))
    }

    func testMergeNeverDeletesADay() {
        var local = Habit(name: "Lesen")
        local.log["2026-08-01"] = 1
        local.log["2026-08-02"] = 1
        store.add(local)

        var remoteHabit = local
        remoteHabit.log = [:] // Remote hat NICHTS — darf lokal nichts löschen
        let remote = HabitData(version: 1, updatedAt: Date().timeIntervalSince1970 + 999, summaryMinutes: nil, habits: [remoteHabit])
        store.merge(remote: remote)

        XCTAssertTrue(store.habits[0].isDone("2026-08-01"))
        XCTAssertTrue(store.habits[0].isDone("2026-08-02"))
    }

    func testMergeAddsUnknownRemoteHabit() {
        store.add(Habit(name: "Lokal"))
        let remote = HabitData(version: 1, updatedAt: 0, summaryMinutes: nil, habits: [Habit(name: "Remote")])
        store.merge(remote: remote)
        XCTAssertEqual(store.habits.map(\.name), ["Lokal", "Remote"])
    }

    func testMergeRemoteNewerWinsRename() {
        let h = Habit(name: "Alt")
        store.add(h)
        var renamed = h
        renamed.name = "Neu"
        let remote = HabitData(version: 1, updatedAt: Date().timeIntervalSince1970 + 999, summaryMinutes: nil, habits: [renamed])
        store.merge(remote: remote)
        XCTAssertEqual(store.habits[0].name, "Neu")
    }

    func testMergeTieKeepsLocalRename() {
        let h = Habit(name: "Lokal")
        store.add(h)
        var renamed = h
        renamed.name = "Remote"
        // updatedAt exakt gleich -> lokal gewinnt (nie beidseitig verlieren)
        let remote = HabitData(version: 1, updatedAt: store.data.updatedAt, summaryMinutes: nil, habits: [renamed])
        store.merge(remote: remote)
        XCTAssertEqual(store.habits[0].name, "Lokal")
    }

    func testImportUsesUnionSemantics() throws {
        var h = Habit(name: "Lesen")
        h.log["2026-08-01"] = 1
        store.add(h)
        var other = h
        other.log = ["2026-08-03": 1]
        let payload = try JSONEncoder().encode(HabitData(version: 1, updatedAt: 0, summaryMinutes: nil, habits: [other]))
        try store.importJSON(payload)
        XCTAssertTrue(store.habits[0].isDone("2026-08-01"))
        XCTAssertTrue(store.habits[0].isDone("2026-08-03"))
    }

    func testExportIsValidAndSorted() throws {
        store.add(Habit(name: "B")); store.add(Habit(name: "A"))
        let raw = try XCTUnwrap(store.exportJSON())
        let decoded = try JSONDecoder().decode(HabitData.self, from: raw)
        XCTAssertEqual(decoded.habits.map(\.name), ["B", "A"]) // Ordnung bleibt Nutzer-Ordnung
    }

    func testCorruptFileFallsBackToEmpty() throws {
        try Data("kaputt".utf8).write(to: url)
        let s = HabitStore(url: url)
        XCTAssertTrue(s.habits.isEmpty)
    }
}

final class ReminderGateTests: XCTestCase {
    func testAuthorizedPosts() {
        XCTAssertEqual(ReminderGate.decision(for: .authorized), .post)
        XCTAssertEqual(ReminderGate.decision(for: .provisional), .post)
        XCTAssertEqual(ReminderGate.decision(for: .ephemeral), .post)
    }
    func testNotDeterminedAsks() {
        XCTAssertEqual(ReminderGate.decision(for: .notDetermined), .ask)
    }
    func testDeniedRefuses() {
        XCTAssertEqual(ReminderGate.decision(for: .denied), .refuse)
    }
}

extension ReminderGate.Decision: Equatable {}
