import XCTest
@testable import Haiity

/// The store's guarantees about not losing data, and about not growing without
/// bound.
///
/// These are the properties that are invisible until they fail. Every one of
/// them used to be broken in a way the rest of the suite did not catch, because
/// none of them had a test: an unreadable file was treated as an empty store and
/// then overwritten, a failed write was swallowed, deleted habits came back after
/// a sync, and session history was never trimmed.
@MainActor
final class HabitStoreIntegrityTests: XCTestCase {

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("store-integrity-\(UUID().uuidString)/\(name)")
    }

    // MARK: - Not losing what is on disk

    /// A file that will not decode must NOT be treated as an empty store. The
    /// next write would then overwrite it, and everything in it would be gone.
    /// The store starts empty so the app stays usable, but the failure is
    /// recorded rather than swallowed, and a copy is kept.
    func testAnUndecodableFileIsPreservedNotOverwritten() throws {
        let url = tempURL("data.json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try Data("dies ist kein gültiges JSON".utf8).write(to: url)

        let outcome = HabitStore.readResult(url)
        XCTAssertTrue(outcome.corrupted, "an unreadable file must be recognised as such")
        XCTAssertNil(outcome.payload)
        // Nothing there yet is a fresh install, not a failure.
        XCTAssertFalse(HabitStore.readResult(FileManager.default.temporaryDirectory
            .appendingPathComponent("never-created-\(UUID().uuidString)")).corrupted)

        // And the store both flags it and keeps the last trace of the payload.
        let store = HabitStore(url: url)
        XCTAssertTrue(store.readFailed)
        XCTAssertTrue(FileManager.default.fileExists(atPath:
            url.deletingLastPathComponent().appendingPathComponent("haiity.corrupt.json").path),
                      "the unreadable file must survive the next write")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// A write that does not land has to say so. The in-memory state is already
    /// mutated by then, so a swallowed failure means the person saw their change
    /// succeed and it simply was not there next launch.
    func testAFailedWriteIsReportedNotSwallowed() throws {
        // A path whose directory does not exist cannot be written to, which is
        // the cheapest way to force the failure without touching permissions.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)/data.json")
        let store = HabitStore(url: url, loadFromDisk: false)
        store.add(Habit(name: "Lesen"))

        XCTAssertFalse(store.persist(), "a write that did not land must report failure")
        XCTAssertNotNil(store.lastWriteError, "and say why")
        // Nothing was written, so there is nothing to clean up but the record.
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    /// A successful write clears the previous failure.
    func testASuccessfulWriteClearsTheError() throws {
        let url = tempURL("data.json")
        // The directory has to exist, or the write fails for a reason that has
        // nothing to do with what is being tested.
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let store = HabitStore(url: url, loadFromDisk: false)
        XCTAssertTrue(store.persist())
        XCTAssertNil(store.lastWriteError)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: - Deletions travelling between devices

    /// The merge is a union, so without tombstones a habit deleted on one device
    /// is restored by any other that still has it. Deletion is a primary action
    /// in a habit tracker, so this has to travel.
    func testADeletionOnOneDeviceReachesTheOther() throws {
        let url = tempURL("data.json")
        let store = HabitStore(url: url, loadFromDisk: false)
        let habit = Habit(name: "Lesen")
        store.add(habit)
        store.remove(habit.id)
        XCTAssertTrue(store.habits.isEmpty)

        // Another device, older, that still has the habit.
        let remote = try Self.payload(habits: [habit])
        store.merge(remote: remote)
        XCTAssertTrue(store.habits.isEmpty,
                      "the tombstone must keep a deleted habit from coming back")
        // And the tombstone survives for the next device.
        let saved = try XCTUnwrap(store.exportJSON())
        XCTAssertTrue(String(decoding: saved, as: UTF8.self).contains("deletedHabits"))
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// The reverse direction: a habit deleted elsewhere arrives as a tombstone and
    /// must remove the local copy. This is the half the first test cannot cover,
    /// because there is no local copy to remove.
    func testADeletionElsewhereRemovesTheLocalCopy() throws {
        let url = tempURL("data.json")
        let store = HabitStore(url: url, loadFromDisk: false)
        let habit = Habit(name: "Lesen")
        store.add(habit)

        let tombstone = try Self.payload(habits: [], deleted: [habit.id])
        store.merge(remote: tombstone)
        XCTAssertTrue(store.habits.isEmpty)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// Tombstones must not accumulate for ever either — they are the same kind of
    /// unbounded growth as the session history they sit beside.
    func testTombstonesArePrunedWithTheSameRetention() throws {
        var data = HabitData(version: 2, updatedAt: 0, summaryMinutes: nil, habits: [])
        let old = UUID()
        data.deletedHabits[old] = Date().timeIntervalSince1970 - 400 * 24 * 60 * 60
        let recent = UUID()
        data.deletedHabits[recent] = Date().timeIntervalSince1970

        HabitStore.pruneTombstones(in: &data)
        XCTAssertNil(data.deletedHabits[old], "a tombstone past the window goes")
        XCTAssertNotNil(data.deletedHabits[recent])
    }

    // MARK: - Not growing without bound

    /// Session records used to be appended on every merge with nothing removing
    /// them, so the array grew for the life of the install — persisted, mirrored
    /// to iCloud, and loaded every launch.
    func testSessionHistoryIsTrimmedToTheRetentionWindow() throws {
        var data = HabitData(version: 2, updatedAt: 0, summaryMinutes: nil, habits: [])
        let recent = UUID()
        data.sessionHistory.append(HabitSessionRecord(id: recent, habitID: UUID(), day: DayKey.today(),
                                                      startedAt: .now, finishedAt: .now, plannedMinutes: nil))
        let ancient = UUID()
        data.sessionHistory.append(HabitSessionRecord(id: ancient, habitID: UUID(), day: "2020-01-01",
                                                      startedAt: .now, finishedAt: .now, plannedMinutes: nil))

        HabitStore.trimSessionHistory(in: &data)
        XCTAssertEqual(data.sessionHistory.map(\.id), [recent],
                       "the recent record stays and the stale one goes")
    }

    func testAnUnparseableSessionDayIsNeverDropped() throws {
        var data = HabitData(version: 2, updatedAt: 0, summaryMinutes: nil, habits: [])
        let record = HabitSessionRecord(id: UUID(), habitID: UUID(), day: "garbage",
                                          startedAt: .now, finishedAt: .now, plannedMinutes: nil)
        data.sessionHistory = [record]
        HabitStore.trimSessionHistory(in: &data)
        XCTAssertEqual(data.sessionHistory.count, 1,
                       "an unreadable day is not proof of age, so it is kept")
    }

    // MARK: - A duplicate id must not crash the merge

    /// `Dictionary(uniqueKeysWithValues:)` crashes on a duplicate. It should not
    /// happen, but if one ever arrived the answer is to keep one entry, not to take
    /// the app down in the merge. Decoding tolerates duplicates, which is what
    /// makes this reachable.
    func testADuplicateHabitIdDoesNotCrashTheMerge() throws {
        let url = tempURL("data.json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let habit = Habit(name: "Lesen")
        let payload = try Self.payload(habits: [habit, habit])
        try Self.write(payload, to: url)

        let store = HabitStore(url: url)
        XCTAssertEqual(store.habits.count, 2, "two entries with one id: the guarded shape")

        // The merge used to abort the process outright here.
        store.merge(remote: try Self.payload(habits: [Habit(name: "Yoga")]))
        XCTAssertTrue(store.habits.contains { $0.name == "Lesen" })
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// The merge used to be one 150-line function that answered "which side is
    /// newer" separately for each section. Split per entity, with the two
    /// decisions made once and handed down — and this pins that, because a
    /// function like that tends to grow back together.
    func testTheMergeIsSplitPerEntity() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Models/HabitStore.swift"),
                                encoding: .utf8)
        for step in ["mergeHabits", "mergeSessionHistory", "mergeSummary",
                     "mergeAppearance", "mergeCloudPreferences",
                     "mergeViewPreferences", "mergeCustomPalettes"] {
            XCTAssertTrue(source.contains("static func \(step)("),
                          "\(step) should be its own step")
        }
        // And the decisions are made in one place, not per section.
        let merge = try XCTUnwrap(source.range(of: "func merge(remote: HabitData) {"))
        let body = source[merge.upperBound...].prefix(700)
        XCTAssertTrue(body.contains("appearanceIsNewer"),
                      "the appearance decision should be a named step")
        XCTAssertFalse(body.contains("for rh in remote.habits"),
                       "the habit loop should not live in the orchestrator")
    }

    private func sourceURL(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }

    // MARK: - Helpers

    /// Writes a payload to disk so a store can read it back, which is the only
    /// way to exercise the decode-then-merge path.
    private static func write(_ payload: HabitData, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(payload).write(to: url, options: .atomic)
    }

    private static func payload(habits: [Habit],
                                deleted: [UUID] = []) throws -> HabitData {
        // Built directly rather than through a JSON round-trip, which was both
        // slower to get right and a place for the test itself to be wrong.
        HabitData(version: HabitData.currentVersion,
                  updatedAt: Date().timeIntervalSince1970,
                  summaryMinutes: nil,
                  habits: habits,
                  deletedHabits: deleted.isEmpty
                      ? [:]
                      : Dictionary(uniqueKeysWithValues:
                          deleted.map { ($0, 1_000_000_000.0) }))
    }
}
