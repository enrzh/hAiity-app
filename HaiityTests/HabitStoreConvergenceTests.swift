import XCTest
@testable import Haiity

/// Two stores, edited in parallel, merged in both directions.
///
/// This is the part of sync that is actually ours. Whether the bytes reach the
/// other phone is iCloud's problem; whether two devices that each made an edit
/// end up agreeing is a merge problem, and it can be settled here in milliseconds
/// instead of on two handsets.
///
/// The harness deliberately interleaves edits on both sides and then merges in
/// both directions, which is what a real sync cycle does. The properties it
/// pins are the ones that must hold or the app quietly loses somebody's work:
///
///  * the two stores CONVERGE — the same set of habits with the same field
///    values, whichever order the merges ran in;
///  * an edit to one habit is not undone by an unrelated edit to another, made
///    on another device while both were offline;
///  * re-merging the same payload changes nothing.
@MainActor
final class HabitStoreConvergenceTests: XCTestCase {

    private func makeStore() -> HabitStore {
        HabitStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("convergence-\(UUID().uuidString).json"),
            loadFromDisk: false)
    }

    /// A comparable, order-independent picture of a store. Field VALUES are what
    /// matter, not array order: two stores that hold the same habits with the
    /// same settings have converged, whatever order they happen to list them in.
    private func fingerprint(_ store: HabitStore) -> [UUID: [String: String]] {
        var out: [UUID: [String: String]] = [:]
        for habit in store.habits {
            out[habit.id] = [
                "name": habit.name,
                "emoji": habit.emoji,
                "kind": habit.kind.rawValue,
                "time": habit.timeMinutes.map(String.init) ?? "-",
                "recurrence": habit.recurrence.target.map(String.init) ?? "-",
                "archived": habit.archivedAt ?? "-",
            ]
        }
        return out
    }

    private func sync(_ a: HabitStore, _ b: HabitStore) {
        let toB = a.exportJSON()!
        let toA = b.exportJSON()!
        b.merge(remote: try! JSONDecoder().decode(HabitData.self, from: toB))
        a.merge(remote: try! JSONDecoder().decode(HabitData.self, from: toA))
    }

    // MARK: - Convergence

    /// The plain case: both devices end up holding the same habits.
    func testTwoStoresConvergeAfterInterleavedCheckIns() {
        let a = makeStore(), b = makeStore()
        let shared = Habit(name: "Lesen")
        a.add(shared)
        b.merge(remote: try! JSONDecoder().decode(HabitData.self, from: a.exportJSON()!))

        // Both check off, offline, on different days.
        let today = DayKey.today()
        a.setValue(shared.id, day: today, value: 1)
        b.setValue(shared.id, day: DayKey.shifted(today, by: -1)!, value: 1)

        sync(a, b)
        // One more round, because a merge can surface work the first pass did
        // not see. Two is the documented contract of the push path.
        sync(a, b)

        XCTAssertEqual(fingerprint(a), fingerprint(b),
                       "two stores that each made an edit must end up identical")
        let merged = a.habits.first { $0.id == shared.id }
        XCTAssertEqual(merged?.log.count, 2,
                       "check-ins on different days are a union and must both survive")
    }

    // MARK: - The one that was broken

    /// Editing habit A must not undo an edit to habit B made on another device.
    ///
    /// Both stores rename a DIFFERENT habit while offline, so neither edit is in
    /// conflict with the other and both are somebody's deliberate work. The
    /// habit-level field merge used to be decided by one whole-store timestamp,
    /// so the device whose clock was later overwrote both names and one of the
    /// two renames was simply gone — with nothing anywhere saying so.
    func testAnEditToOneHabitSurvivesAnUnrelatedEditOnAnotherDevice() throws {
        let a = makeStore(), b = makeStore()
        let one = Habit(name: "Eins")
        let two = Habit(name: "Zwei")
        a.add(one)
        a.add(two)
        // Same starting point on both sides.
        b.merge(remote: try! JSONDecoder().decode(HabitData.self, from: a.exportJSON()!))

        // Each device renames a different habit, offline.
        var editedOne = one
        editedOne.name = "Eins (Phone)"
        a.update(editedOne)
        var editedTwo = two
        editedTwo.name = "Zwei (iPad)"
        b.update(editedTwo)

        sync(a, b)
        sync(a, b)

        let names = Set(fingerprint(a).values.map { $0["name"] ?? "" })
        XCTAssertTrue(names.contains("Eins (Phone)"),
                      "the rename made on A must survive — it is in no conflict with B's work")
        XCTAssertTrue(names.contains("Zwei (iPad)"),
                      "the rename made on B must survive — it is in no conflict with A's work")
        XCTAssertEqual(fingerprint(a), fingerprint(b),
                       "and the two stores must agree once both edits have been seen")
    }

    /// Merging is a fixed point: the sync path re-merges on every conflict retry,
    /// so a merge that keeps changing things would never settle.
    func testMergingTheSamePayloadTwiceChangesNothing() {
        let a = makeStore()
        a.add(Habit(name: "Lesen"))
        let remote = try! JSONDecoder().decode(HabitData.self, from: a.exportJSON()!)

        a.merge(remote: remote)
        let afterFirst = a.exportJSON()
        a.merge(remote: remote)
        XCTAssertEqual(afterFirst, a.exportJSON(),
                       "a second merge of the same payload must be a no-op")
    }

    // MARK: - A wrong clock is not evidence of a newer edit

    /// A device whose clock runs a day fast must not win every merge.
    ///
    /// Both timestamps are just `Date()` on whichever device wrote them, so a
    /// wrong clock is indistinguishable from "newer" — and the side with the
    /// broken clock then discards the other side's work until it catches up.
    /// A stamp that far in the future is not evidence of anything, so it is not
    /// allowed to decide.
    func testAStampInTheFutureIsNotTreatedAsNewer() {
        let now = Date().timeIntervalSince1970
        // Real timezone drift has to keep working, so the tolerance is not zero.
        XCTAssertEqual(HabitStore.reliableStamp(now - 3600, now: now), now - 3600,
                       "a stamp in the past is perfectly good evidence")
        XCTAssertEqual(HabitStore.reliableStamp(now + 5 * 3600, now: now), now + 5 * 3600,
                       "five hours of drift is still a working clock")
        // Past the tolerance it stops being evidence.
        XCTAssertNil(HabitStore.reliableStamp(now + 86_400, now: now),
                     "a day ahead is a wrong clock, not a newer edit")
        XCTAssertNil(HabitStore.reliableStamp(now + 365 * 86_400, now: now),
                     "a year ahead must not win anything")
        XCTAssertNil(HabitStore.reliableStamp(nil, now: now))
    }

    /// The same rule, end to end: a remote payload stamped a day into the future
    /// must not overwrite local work.
    func testARemoteStampedInTheFutureDoesNotOverwriteLocalWork() {
        let a = makeStore()
        a.add(Habit(name: "Lesen"))
        var remote = try! JSONDecoder().decode(HabitData.self, from: a.exportJSON()!)
        remote.updatedAt = Date().timeIntervalSince1970 + 86_400
        remote.habits[0].name = "Übernommen von einer falschen Uhr"

        a.merge(remote: remote)
        XCTAssertEqual(a.habits.first?.name, "Lesen",
                       "a payload dated in the future is not proof that it is newer")
    }

    /// A deletion must not come back just because the device that made it has a
    /// slow clock. Pruning is measured against the reader's clock, so a
    /// future-dated tombstone has to survive it.
    func testAFutureDatedTombstoneIsNeverPruned() {
        let now = Date().timeIntervalSince1970
        var data = HabitData(version: HabitData.currentVersion, updatedAt: now,
                            summaryMinutes: nil, habits: [])
        let id = UUID()
        // A tombstone from a clock a year behind: older than the retention
        // window as seen by a correct clock, yet still carrying a deletion.
        data.deletedHabits[id] = now - 10 * 365 * 86_400

        HabitStore.pruneTombstones(in: &data, now: now)
        XCTAssertNil(data.deletedHabits[id],
                     "a tombstone genuinely older than the window is dropped")

        // And one from a clock a year ahead is definitely kept, however long the
        // reader's own clock says.
        data.deletedHabits[id] = now + 365 * 86_400
        HabitStore.pruneTombstones(in: &data, now: now)
        XCTAssertNotNil(data.deletedHabits[id],
                        "a future-dated tombstone must survive, or the habit comes back")
    }
}
