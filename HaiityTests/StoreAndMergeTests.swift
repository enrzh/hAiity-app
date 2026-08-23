import XCTest
@testable import Haiity

final class StoreAndMergeTests: XCTestCase {
    func testHabitDataLegacyJSONDefaultsViewPreferences() throws {
        let data = try JSONEncoder().encode(HabitData.empty)
        let decoded = try JSONDecoder().decode(HabitData.self, from: data)

        XCTAssertEqual(decoded.viewPreferences, ViewPreferences())
    }

    func testHabitDataRoundTripsManualAppIconName() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(HabitData.empty)) as? [String: Any])
        object["manualAppIconName"] = "AppIcon-Blue"
        let imported = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(HabitData.self, from: imported)
        let roundTripped = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(decoded)) as? [String: Any])

        XCTAssertEqual(roundTripped["manualAppIconName"] as? String, "AppIcon-Blue")
    }

    func testNewerRemoteHabitDataWinsViewPreferences() {
        let local = HabitData(version: 2, updatedAt: 10, summaryMinutes: nil, habits: [],
                              viewPreferences: ViewPreferences(updatedAt: 10,
                                                               statsCards: StatsCardPrefs(active: [.yearPulse]),
                                                               compactMode: false))
        let remote = HabitData(version: 2, updatedAt: 20, summaryMinutes: nil, habits: [],
                               viewPreferences: ViewPreferences(updatedAt: 20,
                                                                statsCards: StatsCardPrefs(active: [.todayRing]),
                                                                compactMode: true))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-view-preferences-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try! JSONEncoder().encode(local).write(to: url)
        let store = HabitStore(url: url)

        store.merge(remote: remote)

        XCTAssertEqual(store.data.viewPreferences, remote.viewPreferences)
    }

    func testNewerUnrelatedRemotePayloadDoesNotReplaceNewerLocalAppearance() throws {
        let localAppearance = AppearancePreferences(
            backgroundMode: .gradient,
            gradientStartHex: 0x0D1117,
            gradientEndHex: 0x161B22)
        let remoteAppearance = AppearancePreferences(
            backgroundImageData: Data([0x01]),
            backgroundMode: .image)
        let local = HabitData(version: 2, updatedAt: 10, summaryMinutes: nil, habits: [],
                              appearancePreferences: localAppearance)
        let remote = HabitData(version: 2, updatedAt: 30, summaryMinutes: nil, habits: [],
                                appearancePreferences: remoteAppearance)
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-appearance-merge-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: localURL) }

        var localObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(local)) as? [String: Any])
        localObject["appearanceUpdatedAt"] = 20.0
        try JSONSerialization.data(withJSONObject: localObject).write(to: localURL)
        let store = HabitStore(url: localURL)

        var remoteObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(remote)) as? [String: Any])
        remoteObject["appearanceUpdatedAt"] = 15.0
        let remoteData = try JSONDecoder().decode(
            HabitData.self,
            from: JSONSerialization.data(withJSONObject: remoteObject))

        store.merge(remote: remoteData)

        XCTAssertEqual(store.appearancePreferences, localAppearance)
    }

    func testLegacyRemotePayloadDoesNotReplaceExplicitLocalAppearance() throws {
        let localAppearance = AppearancePreferences(
            backgroundMode: .gradient,
            gradientStartHex: 0x0D1117,
            gradientEndHex: 0x161B22)
        let remoteAppearance = AppearancePreferences(
            backgroundImageData: Data([0x01]),
            backgroundMode: .image)
        let local = HabitData(version: 2, updatedAt: 10, summaryMinutes: nil, habits: [],
                              appearanceUpdatedAt: 20,
                              appearancePreferences: localAppearance)
        let remote = HabitData(version: 2, updatedAt: 30, summaryMinutes: nil, habits: [],
                                appearancePreferences: remoteAppearance)
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-legacy-appearance-merge-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: localURL) }
        try JSONEncoder().encode(local).write(to: localURL)
        let store = HabitStore(url: localURL)

        store.merge(remote: remote)

        XCTAssertEqual(store.appearancePreferences, localAppearance)
    }

    func testNewerRemoteAppearanceTimestampWins() throws {
        let localAppearance = AppearancePreferences(backgroundMode: .gradient,
                                                     gradientStartHex: 0x0D1117,
                                                     gradientEndHex: 0x161B22)
        let remoteAppearance = AppearancePreferences(backgroundMode: .color,
                                                      backgroundColorHex: 0x2EA043)
        let local = HabitData(version: 2, updatedAt: 30, summaryMinutes: nil, habits: [],
                              appearanceUpdatedAt: 20,
                              appearancePreferences: localAppearance)
        let remote = HabitData(version: 2, updatedAt: 10, summaryMinutes: nil, habits: [],
                                appearanceUpdatedAt: 40,
                                appearancePreferences: remoteAppearance)
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-newer-appearance-merge-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: localURL) }
        try JSONEncoder().encode(local).write(to: localURL)
        let store = HabitStore(url: localURL)

        store.merge(remote: remote)

        XCTAssertEqual(store.appearancePreferences, remoteAppearance)
    }

    func testAppearancePersistenceUpdatesOnlyItsOwnTimestamp() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-appearance-timestamp-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let store = HabitStore(url: storeURL)

        var preferences = store.appearancePreferences
        preferences.backgroundMode = .gradient
        store.appearancePreferences = preferences
        let appearanceTimestamp = try XCTUnwrap(store.data.appearanceUpdatedAt)

        store.add(Habit(name: "Unrelated"))

        XCTAssertEqual(store.data.appearanceUpdatedAt, appearanceTimestamp)
    }

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

    // MARK: – reloadFromDisk (externe Schreiber: Widget-Intent)

    func testReloadFromDiskPicksUpExternalWrite() {
        let h = Habit(name: "Lesen")
        store.add(h)
        // Externer Schreiber (Widget-Extension-Prozess simuliert):
        // zweiter Store auf derselben Datei.
        let external = HabitStore(url: url)
        external.toggle(h.id, day: "2026-08-09")
        XCTAssertFalse(store.habits[0].isDone("2026-08-09")) // noch alter Stand
        store.reloadFromDisk()
        XCTAssertTrue(store.habits[0].isDone("2026-08-09"))
    }

    func testReloadFromDiskWithoutExternalChangeIsNoop() {
        store.add(Habit(name: "Lesen"))
        var fired = false
        store.onChange = { fired = true }
        store.reloadFromDisk()
        XCTAssertFalse(fired) // unveränderte mtime -> kein Re-Read, kein onChange
        XCTAssertEqual(store.habits.count, 1)
    }

    func testAppearancePersistenceReportsItsOwnChangeKind() {
        var genericChangeFired = false
        var changeKind: HabitStoreChange?
        store.onChange = { genericChangeFired = true }
        store.onChangeKind = { changeKind = $0 }

        var preferences = store.appearancePreferences
        preferences.backgroundMode = .gradient
        store.appearancePreferences = preferences

        XCTAssertTrue(genericChangeFired,
                      "appearance changes still need the normal persistence callback")
        XCTAssertEqual(changeKind, .appearance,
                       "appearance changes must not be treated like habit mutations")
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

    func testMergeRemoteNewerWinsCalendarPreference() {
        let habit = Habit(name: "Lesen")
        store.add(habit)
        var remoteHabit = habit
        remoteHabit.calendarSyncEnabled = false
        let remote = HabitData(version: 2, updatedAt: Date().timeIntervalSince1970 + 999,
                               summaryMinutes: nil, habits: [remoteHabit])

        store.merge(remote: remote)

        XCTAssertFalse(store.habits[0].calendarSyncEnabled)
    }

    func testMergeRemoteNewerWinsHabitSwipeOverride() {
        let habit = Habit(name: "Lesen")
        store.add(habit)
        var remoteHabit = habit
        remoteHabit.swipeActions = SwipeActionsOverride(leading: .archive, trailing: .edit)
        let remote = HabitData(version: 2,
                               updatedAt: Date().timeIntervalSince1970 + 999,
                               summaryMinutes: nil,
                               habits: [remoteHabit])

        store.merge(remote: remote)

        XCTAssertEqual(store.habits[0].swipeActions, remoteHabit.swipeActions)
    }

    func testMergeRemoteNewerWinsManualAppIconName() {
        let remote = HabitData(version: 2,
                               updatedAt: Date().timeIntervalSince1970 + 999,
                               summaryMinutes: nil,
                               habits: [],
                               matchAppIcon: false,
                               manualAppIconName: "AppIcon-Blue")

        store.merge(remote: remote)

        XCTAssertFalse(store.matchAppIcon)
        XCTAssertEqual(store.manualAppIconName, "AppIcon-Blue")
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

/// v2-Store-Semantik: Zähler (increment/clear), Max-Merge, Archiv, Version.
final class StoreV2Tests: XCTestCase {
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

    // MARK: – increment / clear

    func testIncrementCountsUpWithoutWrap() {
        let h = Habit(name: "Wasser", recurrence: Recurrence(target: 3))
        store.add(h)
        store.increment(h.id, day: "2026-08-09")
        store.increment(h.id, day: "2026-08-09")
        store.increment(h.id, day: "2026-08-09")
        store.increment(h.id, day: "2026-08-09")
        XCTAssertEqual(store.habits[0].log["2026-08-09"], 4) // kein Wrap am Ziel
    }

    func testClearRemovesDayEntry() {
        let h = Habit(name: "Wasser", recurrence: Recurrence(target: 3))
        store.add(h)
        store.increment(h.id, day: "2026-08-09")
        store.increment(h.id, day: "2026-08-09")
        store.clear(h.id, day: "2026-08-09")
        XCTAssertNil(store.habits[0].log["2026-08-09"])
        XCTAssertFalse(store.habits[0].isDone("2026-08-09"))
    }

    func testClearWithoutEntryDoesNotPersist() {
        let h = Habit(name: "Wasser")
        store.add(h)
        let stamp = store.data.updatedAt
        store.clear(h.id, day: "2026-08-09")
        XCTAssertEqual(store.data.updatedAt, stamp) // No-op schreibt nicht
        XCTAssertTrue(store.habits[0].log.isEmpty)
    }

    // MARK: – Max-Merge der Zähler

    func testMergeLogsByMax() {
        var local = Habit(name: "Wasser", recurrence: Recurrence(target: 5))
        local.log["2026-08-01"] = 2
        local.log["2026-08-02"] = 4
        store.add(local)

        var remoteHabit = local
        remoteHabit.log = ["2026-08-01": 5, "2026-08-02": 1, "2026-08-03": 3]
        let remote = HabitData(version: 2, updatedAt: 0, summaryMinutes: nil, habits: [remoteHabit])
        store.merge(remote: remote)

        XCTAssertEqual(store.habits[0].log["2026-08-01"], 5) // remote höher gewinnt
        XCTAssertEqual(store.habits[0].log["2026-08-02"], 4) // lokal höher bleibt
        XCTAssertEqual(store.habits[0].log["2026-08-03"], 3) // neuer Tag kommt dazu
    }

    func testMergeKeepsLocalCountWhenRemoteMissing() {
        var local = Habit(name: "Wasser")
        local.log["2026-08-01"] = 3
        store.add(local)

        var remoteHabit = local
        remoteHabit.log = [:]
        let remote = HabitData(version: 2, updatedAt: Date().timeIntervalSince1970 + 999,
                               summaryMinutes: nil, habits: [remoteHabit])
        store.merge(remote: remote)

        XCTAssertEqual(store.habits[0].log["2026-08-01"], 3) // nie einen Tag löschen
    }

    // MARK: – Merge von Ziel und Archiv

    func testMergeRecurrenceAndArchiveFollowNewerUpdatedAt() {
        let h = Habit(name: "Sport")
        store.add(h)
        var remoteHabit = h
        remoteHabit.recurrence = .times(3, per: .weekly)
        remoteHabit.archivedAt = "2026-08-05"
        let remote = HabitData(version: 2, updatedAt: Date().timeIntervalSince1970 + 999,
                               summaryMinutes: nil, habits: [remoteHabit])
        store.merge(remote: remote)
        XCTAssertEqual(store.habits[0].recurrence, .times(3, per: .weekly))
        XCTAssertEqual(store.habits[0].archivedAt, "2026-08-05")
    }

    func testMergeRecurrenceTieKeepsLocal() {
        let h = Habit(name: "Sport", recurrence: Recurrence(target: 2))
        store.add(h)
        var remoteHabit = h
        remoteHabit.recurrence = .times(3, per: .weekly)
        remoteHabit.archivedAt = "2026-08-05"
        // updatedAt exakt gleich -> lokal gewinnt
        let remote = HabitData(version: 2, updatedAt: store.data.updatedAt,
                               summaryMinutes: nil, habits: [remoteHabit])
        store.merge(remote: remote)
        XCTAssertEqual(store.habits[0].recurrence, Recurrence(target: 2))
        XCTAssertNil(store.habits[0].archivedAt)
    }

    // MARK: – Archiv

    func testArchivedHabitExcludedFromOpenToday() {
        let a = Habit(name: "Aktiv"), b = Habit(name: "Ruht")
        store.add(a); store.add(b)
        store.archive(b.id)
        XCTAssertEqual(store.openToday().map(\.name), ["Aktiv"])
    }

    func testActiveHabitsFiltersArchivedButHabitsKeepsAll() {
        let a = Habit(name: "Aktiv"), b = Habit(name: "Ruht")
        store.add(a); store.add(b)
        store.archive(b.id, day: "2026-08-09")
        XCTAssertEqual(store.activeHabits.map(\.name), ["Aktiv"])
        XCTAssertEqual(store.habits.count, 2) // Historie bleibt vollständig
        XCTAssertEqual(store.habits[1].archivedAt, "2026-08-09")
        store.unarchive(b.id)
        XCTAssertEqual(store.activeHabits.count, 2)
        XCTAssertNil(store.habits[1].archivedAt)
    }

    func testActiveItemsPartitionWithoutChangingCombinedOrder() {
        store.add(Habit(name: "Lesen"))
        store.add(Habit(name: "Tabletten", itemType: .reminder))
        store.add(Habit(name: "Sport"))

        XCTAssertEqual(store.activeHabits.map(\.name), ["Lesen", "Tabletten", "Sport"])
        XCTAssertEqual(store.activeTrackedHabits.map(\.name), ["Lesen", "Sport"])
        XCTAssertEqual(store.activeReminders.map(\.name), ["Tabletten"])
    }

    func testNewerMetadataChangesItemTypeAndTieKeepsLocalType() {
        let local = Habit(name: "Tabletten")
        store.add(local)

        var remoteHabit = local
        remoteHabit.itemType = .reminder
        store.merge(remote: HabitData(version: 2,
                                      updatedAt: Date().timeIntervalSince1970 + 999,
                                      summaryMinutes: nil,
                                      habits: [remoteHabit]))
        XCTAssertEqual(store.habits[0].itemType, .reminder)

        var tied = remoteHabit
        tied.itemType = .habit
        store.merge(remote: HabitData(version: 2,
                                      updatedAt: store.data.updatedAt,
                                      summaryMinutes: nil,
                                      habits: [tied]))
        XCTAssertEqual(store.habits[0].itemType, .reminder)
    }

    // MARK: – Version 2 auf der Platte

    func testPersistWritesVersionTwo() throws {
        store.add(Habit(name: "X"))
        let raw = try Data(contentsOf: url)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
        XCTAssertEqual(obj["version"] as? Int, 2)
    }

    func testReadAcceptsVersionOneFile() throws {
        try Data(ModelV2CodableTests.v1JSON.utf8).write(to: url)
        let s = HabitStore(url: url)
        XCTAssertEqual(s.habits.count, 1)
        XCTAssertEqual(s.habits[0].recurrence, .daily) // v1 lädt unverändert
        XCTAssertEqual(s.summaryMinutes, 1140)
    }

    func testImportRejectsFutureVersion() {
        let raw = Data(#"{"version":9,"updatedAt":0,"habits":[]}"#.utf8)
        XCTAssertThrowsError(try store.importJSON(raw))
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

    func testGlobalOptOutSuppressesEveryPermissionPrompt() {
        XCTAssertEqual(ReminderGate.decision(for: .notDetermined, promptsSuppressed: true),
                       .refuse)
        XCTAssertEqual(ReminderGate.decision(for: .denied, promptsSuppressed: true),
                       .refuse)
        XCTAssertEqual(ReminderGate.decision(for: .authorized, promptsSuppressed: true),
                       .post)
    }

    func testNotificationPromptPreferencePersistsInInjectedDefaults() {
        let suite = "NotificationPromptPreferenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(NotificationPromptPreference.isSuppressed(in: defaults))
        NotificationPromptPreference.setSuppressed(true, in: defaults)
        XCTAssertTrue(NotificationPromptPreference.isSuppressed(in: defaults))
        NotificationPromptPreference.setSuppressed(false, in: defaults)
        XCTAssertFalse(NotificationPromptPreference.isSuppressed(in: defaults))
    }
}

final class ReminderSetupTests: XCTestCase {
    func testIncompleteSetupIsPresented() {
        XCTAssertTrue(ReminderSetup.shouldPresent(completed: false))
    }

    func testCompletedSetupIsNotPresentedAgain() {
        XCTAssertFalse(ReminderSetup.shouldPresent(completed: true))
    }
}
