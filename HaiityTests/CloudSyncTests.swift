import CloudKit
import XCTest
@testable import Haiity

// MARK: – Fake

/// Bildet die zwei benutzten CloudKit-Operationen deterministisch nach —
/// derselbe Schnitt wie früher der Stub-Transport für die GitHub-API. KEIN
/// Test fasst echtes CloudKit an: `CKContainer` würde in diesem unsignierten
/// Test-Host (kein iCloud-Entitlement) eine ObjC-Exception werfen, die Swift
/// nicht fangen kann.
final class FakeCloudStore: CloudRecordStore, @unchecked Sendable {
    enum SaveOutcome {
        case success
        /// Der Server ist weiter — mit DIESEM Stand.
        case conflict(CKRecord)
        case failure(CKError)
    }

    private let lock = NSLock()
    /// Was `record(for:)` liefert; nil = `unknownItem` (noch nichts in iCloud).
    var stored: CKRecord?
    var fetchError: CKError?
    /// Der Reihe nach abgearbeitet; leer = Erfolg.
    var saveOutcomes: [SaveOutcome] = []

    private(set) var fetches: [CKRecord.ID] = []
    private(set) var savedTypes: [String] = []
    private(set) var savedIDs: [CKRecord.ID] = []
    /// Die Nutzlast wird beim Speichern KOPIERT: bei der Konfliktauflösung
    /// wird dasselbe CKRecord-Objekt erneut beschrieben, ein aufgehobener
    /// Verweis zeigte danach auf den letzten Stand statt auf den damaligen.
    private(set) var savedPayloads: [Data?] = []
    private(set) var savedSchemas: [Int?] = []

    func record(for id: CKRecord.ID) async throws -> CKRecord {
        lock.lock(); defer { lock.unlock() }
        fetches.append(id)
        if let fetchError { throw fetchError }
        guard let stored else { throw CloudFixtures.ckError(.unknownItem) }
        return stored
    }

    func save(_ record: CKRecord) async throws -> CKRecord {
        lock.lock(); defer { lock.unlock() }
        savedTypes.append(record.recordType)
        savedIDs.append(record.recordID)
        savedPayloads.append(CloudFixtures.payload(of: record))
        savedSchemas.append(record[CloudSync.schemaKey] as? Int)
        let outcome = saveOutcomes.isEmpty ? SaveOutcome.success : saveOutcomes.removeFirst()
        switch outcome {
        case .success:
            stored = record
            return record
        case .conflict(let server):
            throw CloudFixtures.ckError(.serverRecordChanged,
                                        userInfo: [CKRecordChangedErrorServerRecordKey: server])
        case .failure(let error):
            throw error
        }
    }
}

enum CloudFixtures {
    static func ckError(_ code: CKError.Code, userInfo: [String: Any] = [:]) -> CKError {
        CKError(_nsError: NSError(domain: CKErrorDomain, code: code.rawValue, userInfo: userInfo))
    }

    /// Ein Datensatz, wie CloudKit ihn liefert: Nutzlast als Asset auf einer
    /// echten Datei.
    static func record(carrying raw: Data?) -> CKRecord {
        let record = CKRecord(recordType: CloudSync.recordType, recordID: CloudSync.recordID)
        if let raw {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("haiity-fixture-\(UUID().uuidString).json")
            try? raw.write(to: url)
            record[CloudSync.payloadKey] = CKAsset(fileURL: url)
        }
        return record
    }

    static func record(carrying data: HabitData) -> CKRecord {
        record(carrying: try? JSONEncoder().encode(data))
    }

    static func payload(of record: CKRecord) -> Data? {
        guard let asset = record[CloudSync.payloadKey] as? CKAsset, let url = asset.fileURL else { return nil }
        return try? Data(contentsOf: url)
    }

    static func habitData(name: String, day: String, updatedAt: TimeInterval) -> HabitData {
        var habit = Habit(name: name)
        habit.log[day] = 1
        return HabitData(version: HabitData.currentVersion,
                         updatedAt: updatedAt,
                         summaryMinutes: nil,
                         habits: [habit])
    }
}

// MARK: – Nutzlast

final class CloudPayloadTests: XCTestCase {
    /// Was in iCloud landet, ist EXAKT die Datei, die auch auf der Platte
    /// liegt — hin und zurück ohne Verlust.
    func testPayloadRoundTripsThroughRecord() throws {
        var habit = Habit(name: "Lesen", emoji: "📖", recurrence: Recurrence(target: 3))
        habit.log["2026-08-01"] = 2
        habit.log["2026-08-02"] = 3
        let original = HabitData(version: HabitData.currentVersion,
                                 updatedAt: 1234,
                                 summaryMinutes: 20 * 60,
                                 habits: [habit],
                                 appearance: .dark,
                                 palette: .builtin(.violet))

        let record = CloudFixtures.record(carrying: original)
        let decoded = try XCTUnwrap(CloudSync.decode(record))

        XCTAssertEqual(decoded.habits.count, 1)
        XCTAssertEqual(decoded.habits[0].name, "Lesen")
        XCTAssertEqual(decoded.habits[0].emoji, "📖")
        XCTAssertEqual(decoded.habits[0].recurrence.target, 3)
        XCTAssertEqual(decoded.habits[0].log["2026-08-02"], 3)
        XCTAssertEqual(decoded.summaryMinutes, 20 * 60)
        XCTAssertEqual(decoded.appearance, .dark)
        XCTAssertEqual(decoded.palette, .builtin(.violet))
        XCTAssertEqual(decoded.updatedAt, 1234)
    }

    /// Ein Datensatz ohne Nutzlast ist „noch nichts geschrieben" — kein
    /// Fehler, aber auch keine erfundenen leeren Daten.
    func testRecordWithoutPayloadDecodesToNil() throws {
        XCTAssertNil(try CloudSync.decode(CloudFixtures.record(carrying: nil)))
    }

    /// Unlesbares WIRD GEMELDET. Als „leer" durchgereicht würde es beim
    /// nächsten Schreiben die Daten des anderen Geräts überschreiben — genau
    /// die Fehlerklasse, gegen die HabitData schon beim Dateilesen sperrt.
    func testUnreadablePayloadThrowsInsteadOfLookingEmpty() {
        let record = CloudFixtures.record(carrying: Data("kein json".utf8))
        XCTAssertThrowsError(try CloudSync.decode(record)) { error in
            XCTAssertEqual(error as? CloudSyncError, .unreadableRemote)
        }
    }

    /// Eine Datei aus einer künftigen Datenversion ist ebenfalls „unlesbar" —
    /// sie darf nicht von einem älteren Build zerschrieben werden.
    func testFutureSchemaVersionIsRejectedNotOverwritten() throws {
        let future = Data(#"{"version":99,"updatedAt":1,"habits":[]}"#.utf8)
        XCTAssertThrowsError(try CloudSync.decode(CloudFixtures.record(carrying: future))) { error in
            XCTAssertEqual(error as? CloudSyncError, .unreadableRemote)
        }
    }
}

// MARK: – Pull / Push

final class CloudSyncTests: XCTestCase {
    func testPullReturnsNilWhenNothingInCloudYet() async throws {
        let fake = FakeCloudStore()          // stored == nil -> unknownItem
        let sync = CloudSync(database: fake)
        let remote = try await sync.pull()
        XCTAssertNil(remote)
        XCTAssertEqual(fake.fetches.map(\.recordName), [CloudSync.recordName])
    }

    func testPullDecodesRemoteData() async throws {
        let fake = FakeCloudStore()
        fake.stored = CloudFixtures.record(carrying: CloudFixtures.habitData(
            name: "Anderswo", day: "2026-08-05", updatedAt: 9))
        let sync = CloudSync(database: fake)
        let remote = try await sync.pull()
        XCTAssertEqual(remote?.habits.first?.name, "Anderswo")
    }

    func testPullMapsNetworkFailureToTemporary() async {
        let fake = FakeCloudStore()
        fake.fetchError = CloudFixtures.ckError(.networkUnavailable)
        let sync = CloudSync(database: fake)
        do {
            _ = try await sync.pull()
            XCTFail("sollte werfen")
        } catch let error as CloudSyncError {
            XCTAssertTrue(error.isTemporary)
        } catch { XCTFail("falscher Fehler: \(error)") }
    }

    func testPushWritesTypedRecordWithPayload() async throws {
        let fake = FakeCloudStore()
        let sync = CloudSync(database: fake)
        let payload = Data(#"{"version":2,"updatedAt":1,"habits":[]}"#.utf8)

        try await sync.push(payload) { _ in payload }

        XCTAssertEqual(fake.savedTypes, [CloudSync.recordType])
        XCTAssertEqual(fake.savedIDs.map(\.recordName), [CloudSync.recordName])
        XCTAssertEqual(fake.savedPayloads.first ?? nil, payload)
        XCTAssertEqual(fake.savedSchemas.first ?? nil, HabitData.currentVersion)
    }

    /// Der Konfliktpfad: Serverstand nehmen, DEN Merge des Stores laufen
    /// lassen, Ergebnis erneut schreiben.
    func testServerRecordChangedMergesAndRetries() async throws {
        let server = CloudFixtures.habitData(name: "Anderswo", day: "2026-08-05", updatedAt: 9)
        let fake = FakeCloudStore()
        fake.saveOutcomes = [.conflict(CloudFixtures.record(carrying: server))]
        let sync = CloudSync(database: fake)

        let first = Data(#"{"first":true}"#.utf8)
        let merged = Data(#"{"merged":true}"#.utf8)
        var sawRemote: String?
        try await sync.push(first) { remote in
            sawRemote = remote?.habits.first?.name
            return merged
        }

        XCTAssertEqual(sawRemote, "Anderswo", "der Merge muss den SERVER-Stand sehen")
        XCTAssertEqual(fake.savedPayloads.count, 2)
        XCTAssertEqual(fake.savedPayloads[0], first)
        XCTAssertEqual(fake.savedPayloads[1], merged, "der zweite Schreibvorgang trägt das Merge-Ergebnis")
    }

    /// Begrenzt: nach `retryLimit` Runden wird der Fehler gemeldet, statt
    /// endlos gegen einen ständig weiterlaufenden Server zu schreiben.
    func testConflictRetriesAreBounded() async {
        let server = CloudFixtures.record(carrying: CloudFixtures.habitData(
            name: "Dauerkonflikt", day: "2026-08-05", updatedAt: 9))
        let fake = FakeCloudStore()
        fake.saveOutcomes = Array(repeating: .conflict(server), count: CloudSync.retryLimit + 3)
        let sync = CloudSync(database: fake)

        var merges = 0
        do {
            try await sync.push(Data("{}".utf8)) { _ in
                merges += 1
                return Data("{}".utf8)
            }
            XCTFail("sollte werfen")
        } catch let error as CloudSyncError {
            XCTAssertEqual(error, .conflictUnresolved(CloudSync.retryLimit))
        } catch { XCTFail("falscher Fehler: \(error)") }

        XCTAssertEqual(fake.savedPayloads.count, CloudSync.retryLimit)
        XCTAssertEqual(merges, CloudSync.retryLimit - 1)
    }

    /// Ist der Serverstand unlesbar, wird NICHT gemergt (und damit auch nicht
    /// überschrieben) — der Fehler geht nach oben.
    func testConflictWithUnreadableServerRecordDoesNotMerge() async {
        let fake = FakeCloudStore()
        fake.saveOutcomes = [.conflict(CloudFixtures.record(carrying: Data("kaputt".utf8)))]
        let sync = CloudSync(database: fake)

        var merged = false
        do {
            try await sync.push(Data("{}".utf8)) { _ in
                merged = true
                return Data("{}".utf8)
            }
            XCTFail("sollte werfen")
        } catch let error as CloudSyncError {
            XCTAssertEqual(error, .unreadableRemote)
        } catch { XCTFail("falscher Fehler: \(error)") }
        XCTAssertFalse(merged)
        XCTAssertEqual(fake.savedPayloads.count, 1, "kein zweiter Schreibvorgang")
    }

    func testPushSurfacesTerminalFailure() async {
        let fake = FakeCloudStore()
        fake.saveOutcomes = [.failure(CloudFixtures.ckError(.quotaExceeded))]
        let sync = CloudSync(database: fake)
        do {
            try await sync.push(Data("{}".utf8)) { _ in Data() }
            XCTFail("sollte werfen")
        } catch let error as CloudSyncError {
            XCTAssertFalse(error.isTemporary)
        } catch { XCTFail("falscher Fehler: \(error)") }
    }

    /// Das Ganze mit dem ECHTEN Merge des Stores: der Konflikt darf keinen
    /// Check-in kosten, egal auf welchem Gerät er entstanden ist.
    @MainActor
    func testConflictPathUsesStoreMergeAndLosesNoCheckIn() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-cloud-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url)
        var local = Habit(name: "Lesen")
        local.log["2026-08-01"] = 1
        store.add(local)

        // Auf dem anderen Gerät: dasselbe Habit, ein anderer Tag.
        var elsewhere = local
        elsewhere.log = ["2026-08-02": 1]
        let server = HabitData(version: HabitData.currentVersion,
                               updatedAt: store.data.updatedAt + 10,
                               summaryMinutes: nil,
                               habits: [elsewhere])

        let fake = FakeCloudStore()
        fake.saveOutcomes = [.conflict(CloudFixtures.record(carrying: server))]
        let sync = CloudSync(database: fake)

        let payload = try XCTUnwrap(store.exportJSON())
        try await sync.push(payload) { remote in
            if let remote { store.merge(remote: remote) }
            return store.exportJSON() ?? payload
        }

        let written = try XCTUnwrap(try CloudSync.decode(CloudFixtures.record(
            carrying: try XCTUnwrap(fake.savedPayloads[1]))))
        XCTAssertEqual(written.habits.count, 1)
        XCTAssertTrue(written.habits[0].isDone("2026-08-01"), "lokaler Check-in bleibt")
        XCTAssertTrue(written.habits[0].isDone("2026-08-02"), "fremder Check-in kommt dazu")
        XCTAssertTrue(store.habits[0].isDone("2026-08-02"), "und steht auch lokal")
    }
}

// MARK: - App sync ordering

final class ContentSyncOrderingTests: XCTestCase {
    func testStartupPullMergesBeforeLocalViewPreferencesTouchThePayloadTimestamp() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Haiity/Views/ContentView.swift"))

        let syncStart = try XCTUnwrap(source.range(of: "private func syncNow"))
        let syncEnd = try XCTUnwrap(source.range(of: "private func flash",
                                                  range: syncStart.upperBound..<source.endIndex))
        let syncBody = source[syncStart.lowerBound..<syncEnd.lowerBound]
        let pull = try XCTUnwrap(syncBody.range(of: "if pullFirst, let remote = try await cloud.pull()"))
        let localPreferenceWrite = try XCTUnwrap(
            syncBody.range(of: "store.setViewPreferences(viewPreferences.preferences)"))

        XCTAssertLessThan(pull.lowerBound, localPreferenceWrite.lowerBound,
                          "remote data must be merged before a local preference write updates data.updatedAt")

        let bootStart = try XCTUnwrap(source.range(of: "private func boot()"))
        let bootBody = source[bootStart.lowerBound..<syncStart.lowerBound]
        XCTAssertFalse(bootBody.contains("        store.setViewPreferences(viewPreferences.preferences)\n        await rescheduleReminders()"),
                       "boot must let syncNow establish ordering instead of touching the timestamp first")

        let syncCall = try XCTUnwrap(bootBody.range(of: "await syncNow(announce: false)"))
        let firstReminderReconcile = try XCTUnwrap(bootBody.range(of: "\n        await rescheduleReminders()\n"))
        XCTAssertLessThan(syncCall.lowerBound, firstReminderReconcile.lowerBound,
                          "startup scheduling must use the iCloud-merged habit data")
    }

    func testForegroundPullCompletesBeforeSchedulingAndReminderReconciliation() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Haiity/Views/ContentView.swift"))

        let activeStart = try XCTUnwrap(source.range(of: ".onChange(of: scenePhase)"))
        let activeEnd = try XCTUnwrap(source.range(of: "private func boot()",
                                                  range: activeStart.upperBound..<source.endIndex))
        let activeBody = source[activeStart.lowerBound..<activeEnd.lowerBound]
        let sync = try XCTUnwrap(activeBody.range(of: "await syncNow(announce: false)"))
        let schedule = try XCTUnwrap(activeBody.range(of: "await rescheduleReminders()"))
        let pullReminders = try XCTUnwrap(activeBody.range(of: "ReminderSync.pullCompletions(into: store)"))

        XCTAssertLessThan(sync.lowerBound, schedule.lowerBound,
                          "foreground scheduling must use the iCloud-merged habit data")
        XCTAssertLessThan(sync.lowerBound, pullReminders.lowerBound,
                          "foreground reminder reconciliation must use the iCloud-merged habit data")
    }
}

final class CloudPreferencePersistenceTests: XCTestCase {
    func testTimedDNDExpiresWithoutChangingTheStoredMode() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let dnd = NotificationDNDState.active(.twoHours, now: now)

        XCTAssertTrue(dnd.isActive(at: now.addingTimeInterval(60)))
        XCTAssertFalse(dnd.isActive(at: now.addingTimeInterval(2 * 60 * 60 + 1)))
        XCTAssertEqual(dnd.mode, .twoHours)
    }

    func testLegacySuppressionBooleanMigratesToPermanentDND() throws {
        let object: [String: Any] = [
            "version": HabitData.currentVersion,
            "updatedAt": 1,
            "habits": [],
            "cloudPreferences": ["notificationPromptsSuppressed": true]
        ]
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(HabitData.self, from: data)

        XCTAssertEqual(decoded.cloudPreferences?.notificationDND.mode, .untilDisabled)
        XCTAssertTrue(decoded.cloudPreferences?.notificationDND.isActive(at: .distantPast) ?? false)
    }

    func testCloudPreferencesSurviveHabitDataRoundTrip() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(HabitData.empty)) as? [String: Any])
        object["cloudPreferences"] = [
            "calendarSyncHabits": true,
            "calendarSyncReminders": false,
            "nativeReminderSync": true,
            "notificationPromptsSuppressed": true,
            "shakeToReportEnabled": false
        ]
        let imported = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(HabitData.self, from: imported)
        let roundTripped = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(decoded)) as? [String: Any])
        let preferences = try XCTUnwrap(roundTripped["cloudPreferences"] as? [String: Any])

        XCTAssertEqual(preferences["calendarSyncHabits"] as? Bool, true)
        XCTAssertEqual(preferences["calendarSyncReminders"] as? Bool, false)
        XCTAssertEqual(preferences["nativeReminderSync"] as? Bool, true)
        XCTAssertEqual(preferences["notificationPromptsSuppressed"] as? Bool, true)
        XCTAssertEqual(preferences["shakeToReportEnabled"] as? Bool, false)
        XCTAssertNotNil(preferences["notificationDND"] as? [String: Any])
    }

    func testNewerRemoteCloudPreferencesReplaceLocalPreferences() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-preferences-\(UUID().uuidString).json")
        let store = HabitStore(url: url)
        store.add(Habit(name: "Lesen"))

        let object: [String: Any] = [
            "version": HabitData.currentVersion,
            "updatedAt": Date().timeIntervalSince1970 + 999,
            "habits": [],
            "cloudPreferences": [
                "calendarSyncHabits": false,
                "calendarSyncReminders": true,
                "nativeReminderSync": true,
                "notificationPromptsSuppressed": true,
                "shakeToReportEnabled": false
            ]
        ]
        let remote = try JSONDecoder().decode(
            HabitData.self,
            from: JSONSerialization.data(withJSONObject: object))

        store.merge(remote: remote)

        let saved = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try XCTUnwrap(store.exportJSON())) as? [String: Any])
        let preferences = try XCTUnwrap(saved["cloudPreferences"] as? [String: Any])
        XCTAssertEqual(preferences["calendarSyncHabits"] as? Bool, false)
        XCTAssertEqual(preferences["calendarSyncReminders"] as? Bool, true)
        XCTAssertEqual(preferences["nativeReminderSync"] as? Bool, true)
    }

    func testPartiallyPopulatedCloudPreferencesUseSafeDefaults() throws {
        let object: [String: Any] = [
            "version": HabitData.currentVersion,
            "updatedAt": 1,
            "habits": [],
            "cloudPreferences": ["calendarSyncHabits": true]
        ]
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(HabitData.self, from: data)

        XCTAssertEqual(decoded.cloudPreferences,
                       CloudPreferences(calendarSyncHabits: true))
    }
}

// MARK: – Fehlerabbildung

final class CloudSyncErrorTests: XCTestCase {
    func testNotAuthenticatedMapsToSignedOut() {
        XCTAssertEqual(CloudSyncError.map(CloudFixtures.ckError(.notAuthenticated)), .notSignedIn)
    }

    /// WÖRTLICH „vorübergehend": der routinemäßige Aufwach-Fehler von
    /// CloudKit ist ein Warte-Zustand — als „nicht angemeldet" gelesen,
    /// sprang der Status beim Start kurz um und der Fehlertext blitzte als
    /// Pille auf (vom Gerät gemeldet).
    func testAccountTemporarilyUnavailableIsTemporaryNotSignedOut() {
        let mapped = CloudSyncError.map(CloudFixtures.ckError(.accountTemporarilyUnavailable))
        XCTAssertTrue(mapped.isTemporary)
        XCTAssertNotEqual(mapped, .notSignedIn)
    }

    func testNetworkErrorsAreTemporary() {
        for code in [CKError.Code.networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited] {
            XCTAssertTrue(CloudSyncError.map(CloudFixtures.ckError(code)).isTemporary,
                          "\(code) sollte vorübergehend sein")
        }
    }

    func testQuotaExceededIsARealFailure() {
        let mapped = CloudSyncError.map(CloudFixtures.ckError(.quotaExceeded))
        XCTAssertFalse(mapped.isTemporary)
        XCTAssertNotNil(mapped.errorDescription)
    }

    func testAlreadyMappedErrorsPassThrough() {
        XCTAssertEqual(CloudSyncError.map(CloudSyncError.unreadableRemote), .unreadableRemote)
    }
}

// MARK: – Status

@MainActor
final class CloudSyncStatusTests: XCTestCase {
    /// Kein iCloud-Token = nicht angemeldet. Geprüft wird der TOKEN, nicht
    /// `CKContainer.accountStatus` — das wirft in genau diesem Test-Host.
    func testNoUbiquityTokenMeansSignedOut() {
        let status = CloudSyncStatus(accountCheck: { false }, observeAccountChanges: false)
        XCTAssertEqual(status.state, .signedOut)
        XCTAssertFalse(status.isSignedIn)
        XCTAssertEqual(status.state.systemImage, "icloud.slash")
    }

    func testTokenPresentMeansActive() {
        let status = CloudSyncStatus(accountCheck: { true }, observeAccountChanges: false)
        XCTAssertEqual(status.state, .active(nil))
        XCTAssertTrue(status.isSignedIn)
    }

    func testSuccessRecordsTimestamp() {
        let status = CloudSyncStatus(accountCheck: { true }, observeAccountChanges: false)
        let when = Date(timeIntervalSince1970: 1_770_000_000)
        status.noteSuccess(at: when)
        XCTAssertEqual(status.state, .active(when))
    }

    func testTemporaryFailureShowsWaitingNotError() {
        let status = CloudSyncStatus(accountCheck: { true }, observeAccountChanges: false)
        status.noteFailure(CloudFixtures.ckError(.networkUnavailable))
        guard case .waiting(let message) = status.state else {
            return XCTFail("erwartet: warten, bekommen: \(status.state)")
        }
        XCTAssertFalse(message.isEmpty)
    }

    /// Ein echter Fehler zeigt SEINE Meldung — nicht „irgendwas ist schief".
    func testRealFailureCarriesItsMessage() {
        let status = CloudSyncStatus(accountCheck: { true }, observeAccountChanges: false)
        status.noteFailure(CloudSyncError.unreadableRemote)
        guard case .failed(let message) = status.state else {
            return XCTFail("erwartet: Fehler, bekommen: \(status.state)")
        }
        XCTAssertEqual(message, CloudSyncError.unreadableRemote.errorDescription)
    }

    /// Ein Fehler, der in Wahrheit „nicht angemeldet" heißt, wird auch so
    /// angezeigt — nicht als roter Fehler.
    func testAuthenticationFailureShowsAsSignedOut() {
        let status = CloudSyncStatus(accountCheck: { true }, observeAccountChanges: false)
        status.noteFailure(CloudFixtures.ckError(.notAuthenticated))
        XCTAssertEqual(status.state, .signedOut)
    }

    func testFailureWhileSignedOutStaysSignedOut() {
        let status = CloudSyncStatus(accountCheck: { false }, observeAccountChanges: false)
        status.noteFailure(CloudFixtures.ckError(.networkFailure))
        XCTAssertEqual(status.state, .signedOut)
    }

    /// Abmelden am GERÄT, ohne dass die App etwas synchronisiert hat.
    func testRefreshFollowsAccountChanges() {
        let signedIn = SignedInFlag(value: true)
        let status = CloudSyncStatus(accountCheck: { signedIn.value }, observeAccountChanges: false)
        XCTAssertEqual(status.state, .active(nil))

        signedIn.value = false
        status.refresh()
        XCTAssertEqual(status.state, .signedOut)

        signedIn.value = true
        status.refresh()
        XCTAssertEqual(status.state, .active(nil))
    }

    /// Ein echter Fehler überlebt ein Neuprüfen des Kontos — er ist eine
    /// Aussage über den letzten Schreibvorgang, nicht über die Anmeldung.
    func testRefreshDoesNotWhitewashARealFailure() {
        let status = CloudSyncStatus(accountCheck: { true }, observeAccountChanges: false)
        status.noteFailure(CloudSyncError.unreadableRemote)
        status.refresh()
        guard case .failed = status.state else {
            return XCTFail("Fehler wurde weggeputzt: \(status.state)")
        }
    }

    /// Live: die Systembenachrichtigung allein muss die Zeile umstellen.
    func testUbiquityNotificationUpdatesState() async {
        let signedIn = SignedInFlag(value: true)
        let status = CloudSyncStatus(accountCheck: { signedIn.value })
        XCTAssertEqual(status.state, .active(nil))

        signedIn.value = false
        NotificationCenter.default.post(name: .NSUbiquityIdentityDidChange, object: nil)
        for _ in 0..<50 where status.state != .signedOut {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(status.state, .signedOut)
    }

    func testAllStatesSayWhatIsGoingOn() {
        let states: [CloudState] = [.active(nil), .active(.now), .signedOut,
                                    .waiting("offline"), .failed("kaputt")]
        for state in states {
            XCTAssertFalse(state.title.isEmpty)
            XCTAssertFalse(state.detail.isEmpty)
            XCTAssertFalse(state.systemImage.isEmpty)
        }
        // Nicht angemeldet MUSS sagen, dass nichts verloren geht.
        XCTAssertTrue(CloudState.signedOut.detail.contains("bleiben hier"))
    }
}

/// Veränderlicher Anmeldezustand für die Kontoprüfung (die Closure ist
/// `@Sendable`, darf also keine `var` einfangen).
final class SignedInFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Bool
    init(value: Bool) { storage = value }
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); storage = newValue; lock.unlock() }
    }
}

// MARK: – Entprellung

final class PushDebouncerTests: XCTestCase {
    /// Fünf Häkchen hintereinander sind EIN Upload.
    func testRapidChangesCoalesceIntoOneRun() async {
        let runs = RunCounter()
        let debouncer = PushDebouncer(delay: .milliseconds(80))
        for _ in 0..<5 {
            await debouncer.schedule { await runs.bump() }
        }
        await debouncer.drain()
        let count = await runs.count
        XCTAssertEqual(count, 1)
    }

    /// …aber der nächste Lauf danach wird nicht verschluckt.
    func testLaterChangeRunsAgain() async {
        let runs = RunCounter()
        let debouncer = PushDebouncer(delay: .milliseconds(40))
        await debouncer.schedule { await runs.bump() }
        await debouncer.drain()
        await debouncer.schedule { await runs.bump() }
        await debouncer.drain()
        let count = await runs.count
        XCTAssertEqual(count, 2)
    }

    func testCancelDropsThePendingRun() async {
        let runs = RunCounter()
        let debouncer = PushDebouncer(delay: .milliseconds(60))
        await debouncer.schedule { await runs.bump() }
        await debouncer.cancel()
        try? await Task.sleep(for: .milliseconds(140))
        let count = await runs.count
        XCTAssertEqual(count, 0)
    }
}

actor RunCounter {
    private(set) var count = 0
    func bump() { count += 1 }
}
