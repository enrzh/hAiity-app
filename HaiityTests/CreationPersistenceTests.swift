import XCTest
import UserNotifications
@testable import Haiity

@MainActor
final class CreationPersistenceTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("creation-persistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func encoded(_ data: HabitData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(data)
    }

    func testFailedCreationRestoresFreshStateAndRetryPersistsExactlyOneID() async throws {
        let directory = try temporaryDirectory()
        let missing = directory.appendingPathComponent("missing", isDirectory: true)
        let url = missing.appendingPathComponent("data.json")
        let store = HabitStore(url: url, loadFromDisk: false)
        let baseline = try encoded(store.data)
        var changes = 0
        var kinds = 0
        var calendarChanges = 0
        store.onChange = { changes += 1 }
        store.onChangeKind = { _ in kinds += 1 }
        store.onCalendarSyncNeeded = { _ in calendarChanges += 1 }
        let draft = CreateItemDraft(name: "Retry once", emoji: "", isReminder: true)

        for _ in 0..<2 {
            let outcome = await CreateItemSaver.save(draft, into: store)
            guard case .failed = outcome else { return XCTFail("the missing directory must reject the write") }
            XCTAssertNotNil(store.lastWriteError)
            XCTAssertEqual(try encoded(store.data), baseline)
            XCTAssertTrue(store.habits.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(kinds, 0)
        XCTAssertEqual(calendarChanges, 0)

        try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: false)
        let retry = await CreateItemSaver.save(draft, into: store)
        XCTAssertEqual(retry, .saved)
        XCTAssertNil(store.lastWriteError)
        let ids = store.habits.map(\.id)
        XCTAssertEqual(ids.count, 1)
        XCTAssertEqual(Set(ids).count, 1)
        XCTAssertEqual(HabitStore(url: url).habits.map(\.id), ids)
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(kinds, 1)
        XCTAssertEqual(calendarChanges, 1)
    }

    func testFailedExistingUpdateRestoresEveryDurableFieldAndAllowsRetry() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("data.json")
        let store = HabitStore(url: url)
        var original = Habit(name: "Existing", timeMinutes: 8 * 60,
            recurrence: Recurrence(frequency: .weekly, weekdays: [2, 5],
                start: "2026-10-01", end: .on("2026-12-31"), target: 3),
            durationMinutes: 17, notificationMode: .off, notificationTimes: [9 * 60, 17 * 60])
        original.log = ["2026-10-01": 2]
        original.minutes = ["2026-10-01": 11]
        original.calendarSyncEnabled = false
        original.timeZoneIdentifier = "Europe/Berlin"
        store.add(original)
        store.summaryMinutes = 12 * 60 + 17
        store.defaultTimeZoneIdentifier = "America/Los_Angeles"
        let bytes = try Data(contentsOf: url)
        let durable = try XCTUnwrap(HabitStore.read(url))
        let baseline = try encoded(durable)
        var changes = 0
        var kinds = 0
        var calendarChanges = 0
        store.onChange = { changes += 1 }
        store.onChangeKind = { _ in kinds += 1 }
        store.onCalendarSyncNeeded = { _ in calendarChanges += 1 }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)

        var edited = try XCTUnwrap(store.habits.first)
        edited.name = "Changed"
        edited.durationMinutes = 42
        edited.notificationTimes = []
        edited.log["2026-10-02"] = 1
        store.update(edited)
        let error = try XCTUnwrap(store.lastWriteError)
        XCTAssertNotEqual(error, String(localized: "Die Daten wurden inzwischen geändert. Bitte erneut sichern."))
        XCTAssertEqual(try encoded(store.data), baseline)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(kinds, 0)
        XCTAssertEqual(calendarChanges, 0)
        XCTAssertThrowsError(try store.requireSuccessfulWrite())

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        store.update(edited)
        XCTAssertNil(store.lastWriteError)
        let saved = HabitStore(url: url)
        XCTAssertEqual(saved.habits.map(\.id), [original.id])
        XCTAssertEqual(saved.habits.first?.name, "Changed")
        XCTAssertEqual(saved.habits.first?.notificationTimes, [])
        XCTAssertEqual(saved.habits.first?.durationMinutes, 42)
        XCTAssertEqual(saved.summaryMinutes, durable.summaryMinutes)
        XCTAssertEqual(saved.defaultTimeZoneIdentifier, durable.defaultTimeZoneIdentifier)
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(kinds, 1)
        XCTAssertEqual(calendarChanges, 1)
    }

    func testFailedWriteRetainsFreshOrCorruptEmptyBaselineAndRecoveryBytes() throws {
        for bytes in [Data(), Data("unreadable existing payload".utf8)] {
            let directory = try temporaryDirectory()
            let url = directory.appendingPathComponent("data.json")
            try bytes.write(to: url)
            let store = HabitStore(url: url)
            let baseline = try encoded(store.data)
            XCTAssertEqual(store.readFailed, !bytes.isEmpty)
            XCTAssertEqual(store.appearancePreferences.designStyle, bytes.isEmpty ? .quiet : .native)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)

            store.add(Habit(name: "Unsaved"))
            XCTAssertNotNil(store.lastWriteError)
            XCTAssertEqual(try encoded(store.data), baseline)
            XCTAssertTrue(store.habits.isEmpty)
            XCTAssertEqual(store.readFailed, !bytes.isEmpty)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            if !bytes.isEmpty {
                XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("haiity.corrupt.json")), bytes)
            }
        }
    }

    func testStaleFailureAdoptsNewerDurablePayloadBeforeRetry() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("data.json")
        let writer = HabitStore(url: url)
        let original = Habit(name: "Original", notificationMode: .off)
        writer.add(original)
        let stale = HabitStore(url: url)
        var changed = try XCTUnwrap(writer.habits.first)
        changed.name = "Newer durable name"
        writer.update(changed)
        let another = Habit(name: "Other writer", notificationMode: .off)
        writer.add(another)
        writer.summaryMinutes = 13 * 60 + 5
        let bytes = try Data(contentsOf: url)
        let baseline = try encoded(try XCTUnwrap(HabitStore.read(url)))
        var changes = 0
        stale.onChange = { changes += 1 }

        stale.add(Habit(name: "Rejected duplicate", notificationMode: .off))
        XCTAssertEqual(stale.lastWriteError,
                       String(localized: "Die Daten wurden inzwischen geändert. Bitte erneut sichern."))
        XCTAssertEqual(try encoded(stale.data), baseline)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(changes, 0)
        let retry = Habit(name: "Explicit retry", notificationMode: .off)
        stale.add(retry)
        XCTAssertNil(stale.lastWriteError)
        XCTAssertEqual(HabitStore(url: url).habits.map(\.id), [original.id, another.id, retry.id])
        XCTAssertEqual(stale.habits.first?.name, changed.name)
        XCTAssertEqual(changes, 1)
    }

    func testFailedWritesRetainDeletionMarkersForIDsAbsentFromTheDurableBaseline() throws {
        let directory = try temporaryDirectory()
        let missing = directory.appendingPathComponent("missing", isDirectory: true)
        let url = missing.appendingPathComponent("data.json")
        let store = HabitStore(url: url, loadFromDisk: false)
        let habit = Habit(name: "Deleted elsewhere", notificationMode: .off)
        store.add(habit)
        XCTAssertNotNil(store.lastWriteError)
        XCTAssertTrue(store.habits.isEmpty)
        store.remove(habit.id)
        XCTAssertNotNil(store.lastWriteError)
        let deletion = try XCTUnwrap(store.data.deletedHabits[habit.id])
        XCTAssertGreaterThan(deletion, Date().timeIntervalSince1970 - 60)

        let remote = HabitData(version: HabitData.currentVersion,
            updatedAt: Date().timeIntervalSince1970, summaryMinutes: nil, habits: [habit])
        store.merge(remote: remote)
        XCTAssertNotNil(store.lastWriteError)
        XCTAssertTrue(store.habits.isEmpty)
        XCTAssertEqual(store.data.deletedHabits[habit.id], deletion)
        let exported = try JSONDecoder().decode(HabitData.self, from: XCTUnwrap(store.exportJSON()))
        XCTAssertEqual(exported.deletedHabits[habit.id], deletion)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: false)
        XCTAssertTrue(store.persist())
        let durable = try JSONDecoder().decode(HabitData.self, from: Data(contentsOf: url))
        XCTAssertTrue(durable.habits.isEmpty)
        XCTAssertEqual(durable.deletedHabits[habit.id], deletion)
    }

    func testFailedDeletionRestoresTheExistingDurableHabitAndSuccessfulRetryPreventsResurrection() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("data.json")
        let store = HabitStore(url: url)
        let habit = Habit(name: "Delete after retry", notificationMode: .off)
        store.add(habit)
        let bytes = try Data(contentsOf: url)
        let baseline = try encoded(try XCTUnwrap(HabitStore.read(url)))
        var changes = 0
        store.onChange = { changes += 1 }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)

        store.remove(habit.id)
        XCTAssertNotNil(store.lastWriteError)
        XCTAssertEqual(try encoded(store.data), baseline)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(changes, 0)

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        store.remove(habit.id)
        XCTAssertNil(store.lastWriteError)
        let afterDelete = try JSONDecoder().decode(HabitData.self, from: Data(contentsOf: url))
        XCTAssertTrue(afterDelete.habits.isEmpty)
        let deletion = try XCTUnwrap(afterDelete.deletedHabits[habit.id])
        let remote = HabitData(version: HabitData.currentVersion,
            updatedAt: deletion - 60, summaryMinutes: nil, habits: [habit])
        store.merge(remote: remote)
        XCTAssertNil(store.lastWriteError)
        let afterMerge = try JSONDecoder().decode(HabitData.self, from: Data(contentsOf: url))
        XCTAssertTrue(afterMerge.habits.isEmpty)
        XCTAssertEqual(afterMerge.deletedHabits[habit.id], deletion)
        XCTAssertTrue(HabitStore(url: url).habits.isEmpty)
        XCTAssertEqual(changes, 2)
    }

    func testCancellationAfterTheWriteStillReturnsADurableSavedReceipt() async throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("data.json")
        let store = HabitStore(url: url)
        var writes = 0
        store.onChange = {
            writes += 1
            withUnsafeCurrentTask { $0?.cancel() }
        }
        let saving = Task { @MainActor in
            let outcome = await CreateItemSaver.save(
                CreateItemDraft(name: "Committed before cancellation", emoji: "", isReminder: true), into: store)
            return (outcome, Task.isCancelled)
        }
        let receipt = await saving.value
        XCTAssertEqual(receipt.0, .saved)
        XCTAssertTrue(receipt.1)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(store.habits.count, 1)
        XCTAssertEqual(HabitStore(url: url).habits.map(\.id), store.habits.map(\.id))
    }

    func testFailedCreationDoesNotDiscardAnInterruptedSessionsOriginalReceipt() async throws {
        let directory = try temporaryDirectory()
        let writable = directory.appendingPathComponent("writable", isDirectory: true)
        let parked = directory.appendingPathComponent("parked", isDirectory: true)
        try FileManager.default.createDirectory(at: writable, withIntermediateDirectories: false)
        let url = writable.appendingPathComponent("data.json")
        let store = HabitStore(url: url)
        var habit = Habit(name: "Water", recurrence: Recurrence(frequency: .daily, target: 4),
                          kind: .quantity, notificationMode: .off)
        let day = DayKey.today()
        habit.minutes[day] = 30
        store.add(habit)
        let started = Date().addingTimeInterval(-600)
        let session = HabitSession(habitID: habit.id, day: day, startedAt: started, plannedMinutes: nil)
        let finished = started.addingTimeInterval(600)
        let originalBytes = try Data(contentsOf: url)
        try FileManager.default.moveItem(at: writable, to: parked)
        try Data("blocked parent".utf8).write(to: writable)

        XCTAssertEqual(HabitSessionCompletion.finish(store: store, session: session, now: finished), 0)
        XCTAssertNotNil(store.lastWriteError)
        XCTAssertEqual(store.sessionHistory.map(\.id), [session.id])
        XCTAssertEqual(store.sessionHistory.first?.finishedAt, finished)
        let draft = CreateItemDraft(name: "Retry reminder", emoji: "", isReminder: true)
        let rejected = await CreateItemSaver.save(draft, into: store)
        guard case .failed = rejected else { return XCTFail("creation must still reject the blocked directory") }
        XCTAssertEqual(store.habits.map(\.id), [habit.id])
        XCTAssertEqual(store.sessionHistory.map(\.id), [session.id])
        XCTAssertEqual(store.value(habit.id, day: day), 1)
        XCTAssertEqual(try Data(contentsOf: parked.appendingPathComponent("data.json")), originalBytes)

        try FileManager.default.removeItem(at: writable)
        try FileManager.default.moveItem(at: parked, to: writable)
        XCTAssertEqual(HabitSessionCompletion.finish(store: store, session: session,
                                                     now: started.addingTimeInterval(1800)), 10)
        XCTAssertEqual(HabitStore(url: url).sessionHistory.first?.finishedAt, finished)
        XCTAssertEqual(HabitStore(url: url).value(habit.id, day: day), 1)
        let retry = await CreateItemSaver.save(draft, into: store)
        XCTAssertEqual(retry, .saved)
        let durable = HabitStore(url: url)
        XCTAssertEqual(durable.habits.count, 2)
        XCTAssertEqual(durable.habits.filter { $0.id != habit.id }.count, 1)
        XCTAssertEqual(durable.sessionHistory.map(\.id), [session.id])
    }

    func testAlreadyCancelledPermissionRequestDoesNotPromptOrChangeAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let before = await center.notificationSettings().authorizationStatus
        let request = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await Reminders.ensurePermission()
        }
        let granted = await request.value
        XCTAssertFalse(granted)
        let after = await center.notificationSettings().authorizationStatus
        XCTAssertEqual(after, before)
    }

    func testBatchValuesPersistMultipleDaysWithOneCoordinatedCallback() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("data.json")
        let store = HabitStore(url: url)
        let habit = Habit(name: "Batch history", notificationMode: .off)
        store.add(habit)
        var changes = 0
        var kinds = 0
        store.onChange = { changes += 1 }
        store.onChangeKind = { _ in kinds += 1 }
        store.setValues(habit.id, values: [("2026-10-01", 1), ("2026-10-02", 3), ("2026-10-03", 7)])

        XCTAssertNil(store.lastWriteError)
        let expected = ["2026-10-01": 1, "2026-10-02": 3, "2026-10-03": 7]
        XCTAssertEqual(store.habits.first?.log, expected)
        XCTAssertEqual(HabitStore(url: url).habits.first?.log, expected)
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(kinds, 1)
    }

    func testBatchRestoreKeepsExactCountsAnswersAndMissingValues() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("data.json")
        let store = HabitStore(url: url)
        var habit = Habit(name: "Mixed history", kind: .yesNo, notificationMode: .off)
        habit.log = ["2026-10-01": 1, "2026-10-02": 7,
                     "2026-10-03": Habit.Answer.no, "2026-10-04": Habit.Answer.yes]
        store.add(habit)
        let receipt: [(day: String, value: Int?)] = [
            ("2026-10-01", 1), ("2026-10-02", 7), ("2026-10-03", Habit.Answer.no),
            ("2026-10-04", Habit.Answer.yes), ("2026-10-05", nil)
        ]
        var changes = 0
        store.onChange = { changes += 1 }
        store.setValues(habit.id, values: [
            ("2026-10-01", 13), ("2026-10-02", 0), ("2026-10-03", Habit.Answer.yes),
            ("2026-10-04", -1), ("2026-10-05", Habit.Answer.no)
        ])
        XCTAssertNil(store.value(habit.id, day: "2026-10-02"))
        XCTAssertNil(store.value(habit.id, day: "2026-10-04"))
        XCTAssertEqual(store.value(habit.id, day: "2026-10-05"), Habit.Answer.no)
        store.setValues(habit.id, values: receipt)

        XCTAssertNil(store.lastWriteError)
        XCTAssertEqual(store.habits.first?.log, habit.log)
        XCTAssertEqual(HabitStore(url: url).habits.first?.log, habit.log)
        XCTAssertNil(store.value(habit.id, day: "2026-10-05"))
        XCTAssertEqual(changes, 2)
    }

    func testBatchNoOpsDoNotWriteOrClearAnExistingError() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("data.json")
        let store = HabitStore(url: url)
        var habit = Habit(name: "Unchanged history", notificationMode: .off)
        habit.log = ["2026-10-01": 4]
        store.add(habit)
        let bytes = try Data(contentsOf: url)
        let baseline = try encoded(store.data)
        var changes = 0
        store.onChange = { changes += 1 }
        let unchanged: [(day: String, value: Int?)] = [
            ("2026-10-01", 4), ("2026-10-02", nil), ("2026-10-03", 0), ("2026-10-04", -2)
        ]
        store.setValues(habit.id, values: unchanged)
        store.setValues(habit.id, values: [])
        store.setValues(UUID(), values: [("2026-10-01", 1)])
        XCTAssertEqual(try encoded(store.data), baseline)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(changes, 0)

        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        store.setValues(habit.id, values: [("2026-10-01", 5)])
        let error = try XCTUnwrap(store.lastWriteError)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        store.setValues(habit.id, values: unchanged)
        XCTAssertEqual(store.lastWriteError, error)
        XCTAssertEqual(try encoded(store.data), baseline)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(changes, 0)
    }

    func testBatchClearsMissedDaysEvenWhenTheExactValuesDoNotChange() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("data.json")
        let store = HabitStore(url: url)
        var habit = Habit(name: "Missed days", notificationMode: .off)
        habit.log = ["2026-10-01": 4]
        habit.missedDays = ["2026-10-01", "2026-10-02", "2026-10-03"]
        store.add(habit)
        var changes = 0
        store.onChange = { changes += 1 }
        store.setValues(habit.id, values: [("2026-10-01", 4), ("2026-10-02", nil)])

        XCTAssertNil(store.lastWriteError)
        XCTAssertEqual(store.habits.first?.log, habit.log)
        XCTAssertEqual(store.habits.first?.missedDays, ["2026-10-03"])
        XCTAssertEqual(HabitStore(url: url).habits.first?.missedDays, ["2026-10-03"])
        XCTAssertEqual(changes, 1)
    }

    func testStaleBatchRejectsAllDaysAndAdoptsTheNewerDurableValues() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("data.json")
        let writer = HabitStore(url: url)
        var habit = Habit(name: "Stale history", kind: .yesNo, notificationMode: .off)
        habit.log = ["2026-10-01": 1, "2026-10-02": 2, "2026-10-03": Habit.Answer.no]
        writer.add(habit)
        let stale = HabitStore(url: url)
        writer.setValue(habit.id, day: "2026-10-01", value: 11)
        let bytes = try Data(contentsOf: url)
        let baseline = try encoded(try XCTUnwrap(HabitStore.read(url)))
        var changes = 0
        stale.onChange = { changes += 1 }
        let requested: [(day: String, value: Int?)] = [
            ("2026-10-01", 7), ("2026-10-02", 8), ("2026-10-03", nil)
        ]
        stale.setValues(habit.id, values: requested)

        XCTAssertNotNil(stale.lastWriteError)
        XCTAssertEqual(try encoded(stale.data), baseline)
        XCTAssertEqual(stale.value(habit.id, day: "2026-10-01"), 11)
        XCTAssertEqual(stale.value(habit.id, day: "2026-10-02"), 2)
        XCTAssertEqual(stale.value(habit.id, day: "2026-10-03"), Habit.Answer.no)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(changes, 0)

        stale.setValues(habit.id, values: requested)
        XCTAssertNil(stale.lastWriteError)
        XCTAssertEqual(HabitStore(url: url).habits.first?.log, ["2026-10-01": 7, "2026-10-02": 8])
        XCTAssertEqual(changes, 1)
    }

    func testFailedDiskBatchRestoresAllValuesMissedDaysAndArchiveMetadata() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("data.json")
        let store = HabitStore(url: url)
        var preferences = store.data.viewPreferences
        preferences.autoArchiveCompletedItems = true
        store.setViewPreferences(preferences)
        var habit = Habit(name: "Finite history",
            recurrence: Recurrence(frequency: .daily, start: "2026-10-01", end: .after(3)),
            notificationMode: .off)
        habit.log = ["2026-10-01": 2]
        habit.missedDays = ["2026-10-02", "2026-10-03"]
        store.add(habit)
        let bytes = try Data(contentsOf: url)
        let baseline = try encoded(store.data)
        var changes = 0
        store.onChange = { changes += 1 }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let requested: [(day: String, value: Int?)] = [
            ("2026-10-01", nil), ("2026-10-02", 1), ("2026-10-03", 1)
        ]
        store.setValues(habit.id, values: requested)

        XCTAssertNotNil(store.lastWriteError)
        XCTAssertEqual(try encoded(store.data), baseline)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertNil(store.habits.first?.archivedAt)
        XCTAssertEqual(changes, 0)

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        store.setValues(habit.id, values: requested)
        XCTAssertNil(store.lastWriteError)
        let durable = HabitStore(url: url)
        XCTAssertEqual(durable.habits.first?.log, ["2026-10-02": 1, "2026-10-03": 1])
        XCTAssertTrue(durable.habits.first?.missedDays.isEmpty == true)
        XCTAssertEqual(durable.habits.first?.archivedAt, "2026-10-03")
        XCTAssertEqual(changes, 1)
    }

    func testBatchAndSingleSetterKeepYesNoAutoArchiveSemantics() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("data.json")
        let store = HabitStore(url: url)
        var preferences = store.data.viewPreferences
        preferences.autoArchiveCompletedItems = true
        store.setViewPreferences(preferences)
        let habit = Habit(name: "One answer", recurrence: Recurrence(frequency: .once, start: "2026-10-01"),
                          kind: .yesNo, notificationMode: .off)
        store.add(habit)
        var changes = 0
        store.onChange = { changes += 1 }
        store.setValues(habit.id, values: [("2026-10-01", Habit.Answer.no)])
        XCTAssertEqual(store.value(habit.id, day: "2026-10-01"), Habit.Answer.no)
        XCTAssertNil(store.habits.first?.archivedAt)
        store.setValue(habit.id, day: "2026-10-01", value: Habit.Answer.yes)
        XCTAssertEqual(HabitStore(url: url).habits.first?.archivedAt, "2026-10-01")
        XCTAssertEqual(changes, 2)
    }

    func testPendingSessionReceiptSurvivesFailedSingleAndBatchHistoryWrites() throws {
        let directory = try temporaryDirectory()
        let writable = directory.appendingPathComponent("writable", isDirectory: true)
        let parked = directory.appendingPathComponent("parked", isDirectory: true)
        try FileManager.default.createDirectory(at: writable, withIntermediateDirectories: false)
        let url = writable.appendingPathComponent("data.json")
        let store = HabitStore(url: url)
        var habit = Habit(name: "Session answer", kind: .yesNo, notificationMode: .off)
        let day = DayKey.today()
        let otherDay = try XCTUnwrap(DayKey.shifted(day, by: -1))
        habit.minutes[day] = 30
        store.add(habit)
        let bytes = try Data(contentsOf: url)
        let started = Date().addingTimeInterval(-600)
        let finished = started.addingTimeInterval(600)
        let session = HabitSession(habitID: habit.id, day: day, startedAt: started, plannedMinutes: nil)
        var changes = 0
        store.onChange = { changes += 1 }
        try FileManager.default.moveItem(at: writable, to: parked)
        try Data("blocked parent".utf8).write(to: writable)

        XCTAssertEqual(HabitSessionCompletion.finish(store: store, session: session, now: finished), 0)
        XCTAssertNotNil(store.lastWriteError)
        XCTAssertEqual(store.value(habit.id, day: day), Habit.Answer.yes)
        XCTAssertEqual(store.sessionHistory.first?.finishedAt, finished)
        let pendingReceipt = try encoded(store.data)
        let writes: [[(day: String, value: Int?)]] = [
            [(day, Habit.Answer.no)], [(day, Habit.Answer.no), (otherDay, 9)]
        ]
        for values in writes {
            store.setValues(habit.id, values: values)
            XCTAssertNotNil(store.lastWriteError)
            XCTAssertEqual(try encoded(store.data), pendingReceipt)
        }
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(try Data(contentsOf: parked.appendingPathComponent("data.json")), bytes)

        try FileManager.default.removeItem(at: writable)
        try FileManager.default.moveItem(at: parked, to: writable)
        XCTAssertEqual(HabitSessionCompletion.finish(store: store, session: session,
                                                     now: started.addingTimeInterval(1800)), 10)
        XCTAssertNil(store.lastWriteError)
        let durable = HabitStore(url: url)
        XCTAssertEqual(durable.value(habit.id, day: day), Habit.Answer.yes)
        XCTAssertEqual(durable.sessionHistory.first?.finishedAt, finished)
        XCTAssertNil(durable.value(habit.id, day: otherDay))
        XCTAssertEqual(changes, 1)
    }

    func testDurableReceiptIsRecordedBeforeTheViewsCancellationGuard() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Views/SpeakToCreateSheet.swift"), encoding: .utf8)
        let save = try XCTUnwrap(source.range(of: "let outcome = await CreateItemSaver.save(draft, into: store)"))
        let receipt = try XCTUnwrap(source.range(of: "didCreate = true", range: save.upperBound..<source.endIndex))
        let cancellation = try XCTUnwrap(source.range(of: "guard !Task.isCancelled", range: save.upperBound..<source.endIndex))
        XCTAssertLessThan(receipt.lowerBound, cancellation.lowerBound,
                          "a committed item must never become a retryable draft after UI cancellation")
    }

    func testWriteFailureReturnsBeforeWidgetReloadAndSuccessCallbacks() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Models/HabitStore.swift"), encoding: .utf8)
        let failure = try XCTUnwrap(source.range(of: "if let error = coordinationError ?? (writeError as NSError?)"))
        let stop = try XCTUnwrap(source.range(of: "return false", range: failure.upperBound..<source.endIndex))
        for effect in ["reloadWidgetsAfterPersist()", "onChange?()", "onChangeKind?(changeKind)", "onCalendarSyncNeeded?(calendarSync)"] {
            let call = try XCTUnwrap(source.range(of: effect, range: failure.upperBound..<source.endIndex))
            XCTAssertLessThan(stop.lowerBound, call.lowerBound, effect)
        }
    }
}
