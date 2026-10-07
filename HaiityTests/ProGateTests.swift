import XCTest
@testable import Haiity

/// v23: hAiity Pro — das Limit, das Kaufblatt und die sechs Stellen, an denen
/// gegated wird.
///
/// Zwei Sorten Test in einer Datei, bewusst:
///
/// 1. **Reine Logik** an `ProGate` und `PaywallContext` — kein StoreKit, kein
///    Hauptakteur, keine Defaults. Genau dafür wurde `ProGate` von `Pro`
///    getrennt.
/// 2. **Quell-Verträge** (Muster `IconStudioTests`) an den Gates selbst. Ein
///    Gate ist eine Verzweigung in einer Ansicht: kein Rückgabewert, den man
///    prüfen könnte, aber ein Quelltext, der es entweder tut oder nicht.
///    Diese Tests fangen den Fall ab, der im Simulator NICHT auffällt — ein
///    zweiter Weg zum selben Ziel, der am Gate vorbeiführt.
final class ProGateTests: XCTestCase {

    #if DEBUG
    @MainActor
    func testProStatusObserverSeesAnEntitlementTransition() async {
        Pro.setDebugUnlocked(false)
        defer { Pro.setDebugUnlocked(false) }

        let changed = expectation(description: "ProStatus publishes the entitlement transition")
        withObservationTracking({
            _ = ProStatus.shared.unlocked
        }, onChange: {
            changed.fulfill()
        })

        Pro.setDebugUnlocked(true)
        await fulfillment(of: [changed], timeout: 1)
        XCTAssertTrue(Pro.isUnlocked)
    }

    @MainActor
    private func withPersonalizationState(_ body: (UserDefaults) -> Void) {
        let defaults = UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard
        let keys = [PersonalName.appleUserIDKey, PersonalName.appleEmailKey,
                    HabitVisibility.proUnlockedKey, HabitVisibility.proEntitlementExpirationKey]
        let saved = keys.map { defaults.object(forKey: $0) }
        let override = Pro.debugOverride
        defer {
            for (key, value) in zip(keys, saved) { restore(value, forKey: key, in: defaults) }
            Pro.setDebugUnlocked(nil)
            if let override { Pro.setDebugUnlocked(override) }
            for (key, value) in zip(keys, saved) { restore(value, forKey: key, in: defaults) }
        }
        Pro.setDebugUnlocked(nil)
        body(defaults)
    }

    @MainActor
    func testOptionalAppleIdentityChangesPreserveCachedLifetimePurchase() {
        withPersonalizationState { defaults in
            defaults.set(true, forKey: HabitVisibility.proUnlockedKey)
            defaults.removeObject(forKey: HabitVisibility.proEntitlementExpirationKey)
            defaults.removeObject(forKey: PersonalName.appleEmailKey)
            for identity in ["personalization-account", "another-personalization-account", nil] as [String?] {
                restore(identity, forKey: PersonalName.appleUserIDKey, in: defaults)
                Pro.accountDidChange()
                XCTAssertTrue(Pro.isUnlocked)
                XCTAssertTrue(defaults.bool(forKey: HabitVisibility.proUnlockedKey))
                XCTAssertTrue(HabitVisibility.sharedEntitlementIsUnlocked)
            }
        }
    }

    @MainActor
    func testOwnerExemptionIsNotCachedAsAPurchaseAndEndsAtSignOut() {
        withPersonalizationState { defaults in
            defaults.set(false, forKey: HabitVisibility.proUnlockedKey)
            defaults.removeObject(forKey: PersonalName.appleEmailKey)
            defaults.set(DeveloperAccess.ownerAppleUserID, forKey: PersonalName.appleUserIDKey)
            Pro.accountDidChange()
            XCTAssertTrue(Pro.isUnlocked)
            XCTAssertTrue(HabitVisibility.sharedEntitlementIsUnlocked)
            XCTAssertFalse(defaults.bool(forKey: HabitVisibility.proUnlockedKey))

            defaults.removeObject(forKey: PersonalName.appleUserIDKey)
            Pro.accountDidChange()
            XCTAssertFalse(Pro.isUnlocked)
            XCTAssertFalse(HabitVisibility.sharedEntitlementIsUnlocked)
        }
    }

    @MainActor
    func testOwnerExemptionDoesNotErasePurchasedExpiration() {
        withPersonalizationState { defaults in
            let expiration = Date.now.addingTimeInterval(-60).timeIntervalSince1970
            defaults.set(true, forKey: HabitVisibility.proUnlockedKey)
            defaults.set(expiration, forKey: HabitVisibility.proEntitlementExpirationKey)
            defaults.removeObject(forKey: PersonalName.appleEmailKey)
            defaults.set(DeveloperAccess.ownerAppleUserID, forKey: PersonalName.appleUserIDKey)
            Pro.accountDidChange()
            XCTAssertTrue(Pro.isUnlocked)
            XCTAssertEqual(defaults.double(forKey: HabitVisibility.proEntitlementExpirationKey), expiration)

            defaults.removeObject(forKey: PersonalName.appleUserIDKey)
            Pro.accountDidChange()
            XCTAssertFalse(Pro.isUnlocked)
            XCTAssertFalse(HabitVisibility.sharedEntitlementIsUnlocked)
        }
    }

    @MainActor
    func testPersonalizationBoundaryKeepsDebugOverrideAuthoritative() {
        withPersonalizationState { defaults in
            for unlocked in [true, false] {
                Pro.setDebugUnlocked(unlocked)
                defaults.set(DeveloperAccess.ownerAppleUserID, forKey: PersonalName.appleUserIDKey)
                Pro.accountDidChange()
                XCTAssertEqual(Pro.isUnlocked, unlocked)
                defaults.removeObject(forKey: PersonalName.appleUserIDKey)
                Pro.accountDidChange()
                XCTAssertEqual(Pro.isUnlocked, unlocked)
            }
        }
    }
    #endif

    // MARK: – Reine Logik: das Limit

    func testFreeHabitLimitIsThree() {
        XCTAssertEqual(ProGate.freeHabitLimit, 3)
    }

    /// Die Grenze liegt zwischen 2 und 3: bei zwei aktiven Habits darf der
    /// dritte entstehen, bei dreien nicht mehr. Ein Zaunpfahl-Fehler hier ist
    /// entweder ein verschenktes Produkt oder ein gebrochenes Versprechen.
    func testMayAddHabitMatrixWhenLocked() {
        XCTAssertTrue(ProGate.mayAddHabit(activeCount: 0, unlocked: false))
        XCTAssertTrue(ProGate.mayAddHabit(activeCount: 2, unlocked: false))
        XCTAssertFalse(ProGate.mayAddHabit(activeCount: 3, unlocked: false))
        XCTAssertFalse(ProGate.mayAddHabit(activeCount: 4, unlocked: false))
    }

    /// Mit Pro gibt es keine Grenze — auch nicht weit oberhalb.
    func testMayAddHabitMatrixWhenUnlocked() {
        for count in [0, 2, 3, 4, 99] {
            XCTAssertTrue(ProGate.mayAddHabit(activeCount: count, unlocked: true),
                          "\(count) aktive Habits mit Pro abgelehnt")
        }
    }

    func testReminderConversionUsesTheSameTrackedHabitLimit() {
        XCTAssertFalse(ProGate.maySaveTrackedHabit(existingIsTracked: false,
                                                   targetIsTracked: true,
                                                   activeCount: 3,
                                                   unlocked: false))
        XCTAssertTrue(ProGate.maySaveTrackedHabit(existingIsTracked: false,
                                                  targetIsTracked: true,
                                                  activeCount: 2,
                                                  unlocked: false))
        XCTAssertTrue(ProGate.maySaveTrackedHabit(existingIsTracked: true,
                                                  targetIsTracked: true,
                                                  activeCount: 3,
                                                  unlocked: false),
                      "existing tracked habits remain usable after entitlement loss")
        XCTAssertTrue(ProGate.maySaveTrackedHabit(existingIsTracked: false,
                                                  targetIsTracked: false,
                                                  activeCount: 3,
                                                  unlocked: false),
                      "free reminders remain available")
    }

    func testLockedOverLimitTrackedHabitsCannotBeEditedAsAProBypass() {
        XCTAssertTrue(ProGate.maySaveTrackedHabit(existingIsTracked: true,
                                                  targetIsTracked: true,
                                                  activeCount: 3,
                                                  unlocked: false),
                      "a normal free user must still be able to edit three habits")
        XCTAssertFalse(ProGate.maySaveTrackedHabit(existingIsTracked: true,
                                                   targetIsTracked: true,
                                                   activeCount: 4,
                                                   unlocked: false),
                       "an expired Pro set must not bypass the unlimited-habits gate by editing")
        XCTAssertTrue(ProGate.maySaveTrackedHabit(existingIsTracked: true,
                                                  targetIsTracked: true,
                                                  activeCount: 4,
                                                  unlocked: true))
    }

    func testLockedImportCannotAddTrackedHabitsPastTheFreeLimit() {
        let localHabits = [Habit(name: "A"), Habit(name: "B"), Habit(name: "C")]
        let local = HabitData(version: HabitData.currentVersion,
                              updatedAt: 10,
                              summaryMinutes: nil,
                              habits: localHabits)

        let newTracked = Habit(name: "D")
        let incoming = HabitData(version: HabitData.currentVersion,
                                  updatedAt: 20,
                                  summaryMinutes: nil,
                                  habits: [newTracked])

        XCTAssertFalse(ProGate.mayImport(incoming: incoming, into: local, unlocked: false))

        let reminder = Habit(name: "Reminder", itemType: .reminder)
        let reminderImport = HabitData(version: HabitData.currentVersion,
                                       updatedAt: 20,
                                       summaryMinutes: nil,
                                       habits: [reminder])
        XCTAssertTrue(ProGate.mayImport(incoming: reminderImport, into: local, unlocked: false))

        var archived = Habit(name: "Archived")
        archived.archivedAt = "2026-08-25"
        let archivedImport = HabitData(version: HabitData.currentVersion,
                                       updatedAt: 20,
                                       summaryMinutes: nil,
                                       habits: [archived])
        XCTAssertTrue(ProGate.mayImport(incoming: archivedImport, into: local, unlocked: false))

        var duplicate = Habit(name: "A updated")
        duplicate.id = localHabits[0].id
        let duplicateImport = HabitData(version: HabitData.currentVersion,
                                        updatedAt: 20,
                                        summaryMinutes: nil,
                                        habits: [duplicate])
        XCTAssertTrue(ProGate.mayImport(incoming: duplicateImport, into: local, unlocked: false))
        XCTAssertTrue(ProGate.mayImport(incoming: incoming, into: local, unlocked: true))
    }

    /// **Die API nimmt `activeCount`, nicht `habits.count`** — das IST die
    /// Stelle, an der „archivierte zählen nicht" entschieden wird. `ProGate`
    /// selbst kann das nicht wissen; es zählt, was man ihm gibt. Also wird
    /// hier beides geprüft: dass `store.activeHabits` Archiviertes auslässt,
    /// und (im Quell-Vertrag zu Gate 1) dass genau dieser Wert ankommt.
    func testArchivedHabitsDoNotCountTowardTheLimit() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url)

        let a = Habit(name: "A"), b = Habit(name: "B"), c = Habit(name: "C")
        store.add(a); store.add(b); store.add(c)
        XCTAssertEqual(store.activeHabits.count, 3)
        XCTAssertFalse(ProGate.mayAddHabit(activeCount: store.activeHabits.count,
                                           unlocked: false),
                       "drei aktive Habits: der vierte ist Pro")

        // Einen archivieren — er bleibt im Bestand, zählt aber nicht mehr.
        store.archive(b.id)
        XCTAssertEqual(store.habits.count, 3, "Archivieren darf nichts löschen")
        XCTAssertEqual(store.activeHabits.count, 2)
        XCTAssertTrue(ProGate.mayAddHabit(activeCount: store.activeHabits.count,
                                          unlocked: false),
                      "archivierte Habits dürfen den Platz nicht belegen")
    }

    func testRemindersDoNotCountTowardTheHabitLimit() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url)
        store.add(Habit(name: "A"))
        store.add(Habit(name: "B"))
        store.add(Habit(name: "Tabletten", itemType: .reminder))

        XCTAssertEqual(store.activeHabits.count, 3)
        XCTAssertEqual(store.activeTrackedHabits.count, 2)
        XCTAssertTrue(ProGate.mayAddHabit(activeCount: store.activeTrackedHabits.count,
                                          unlocked: false))
    }

    func testArchivedTrackedHabitRestoreUsesTheFreeLimit() {
        XCTAssertTrue(ProGate.mayUnarchiveTrackedHabit(isTracked: false,
                                                        activeCount: 99,
                                                        unlocked: false),
                      "reminders stay free when restored")
        XCTAssertTrue(ProGate.mayUnarchiveTrackedHabit(isTracked: true,
                                                        activeCount: 2,
                                                        unlocked: false))
        XCTAssertFalse(ProGate.mayUnarchiveTrackedHabit(isTracked: true,
                                                         activeCount: 3,
                                                         unlocked: false))
        XCTAssertTrue(ProGate.mayUnarchiveTrackedHabit(isTracked: true,
                                                       activeCount: 99,
                                                       unlocked: true))
    }

    func testArchiveRestoreCannotBypassTheSharedProGate() throws {
        let archive = try source("Haiity/Views/ArchiveView.swift")
        XCTAssertTrue(archive.contains("ProGate.mayUnarchiveTrackedHabit"))
        XCTAssertTrue(archive.contains("store.activeTrackedHabits.count"))
        XCTAssertTrue(archive.contains("paywall = .habits"))
        XCTAssertTrue(archive.contains("Pro.isUnlocked"))
    }

    /// Trivial, und trotzdem festgenagelt: `mayUseProFeature` ist die
    /// Berechtigung selbst — keine Ansicht darf hier eine zweite Bedingung
    /// hineinverhandeln.
    func testMayUseProFeatureIsExactlyTheEntitlement() {
        XCTAssertTrue(ProGate.mayUseProFeature(unlocked: true))
        XCTAssertFalse(ProGate.mayUseProFeature(unlocked: false))
    }

    func testNotificationDNDExpiresAtItsBoundaryButUntilDisabledRemainsActive() {
        let now = Date(timeIntervalSince1970: 10_000)
        let timed = NotificationDNDState.active(.twoHours, now: now)
        let permanent = NotificationDNDState.active(.untilDisabled, now: now)

        XCTAssertTrue(timed.isActive(at: now.addingTimeInterval(2 * 60 * 60 - 1)))
        XCTAssertFalse(timed.isActive(at: now.addingTimeInterval(2 * 60 * 60)))
        XCTAssertTrue(permanent.isActive(at: now.addingTimeInterval(365 * 24 * 60 * 60)))
    }

    func testLockedEntitlementDisablesEveryPaidCloudIntegration() {
        let requested = CloudPreferences(
            calendarSyncHabits: true,
            calendarSyncReminders: true,
            nativeReminderSync: true,
            shakeToReportEnabled: false,
            notificationDND: .active(.eightHours, now: Date(timeIntervalSince1970: 1_000)))

        let effective = ProGate.restrictedCloudPreferences(requested, unlocked: false)

        XCTAssertFalse(effective.calendarSyncHabits)
        XCTAssertFalse(effective.calendarSyncReminders)
        XCTAssertFalse(effective.nativeReminderSync)
        XCTAssertEqual(effective.notificationDND, requested.notificationDND)
        XCTAssertEqual(effective.shakeToReportEnabled, requested.shakeToReportEnabled)
    }

    func testPaidSyncServicesRecheckTheEntitlementAtTheirBoundaries() throws {
        let calendar = try source("Haiity/Services/CalendarSync.swift")
        let reminders = try source("Haiity/Services/ReminderSync.swift")

        XCTAssertGreaterThanOrEqual(
            calendar.components(separatedBy: "guard Pro.isUnlocked").count - 1,
            2,
            "calendar access and reconciliation must not be UI-only gates")
        XCTAssertGreaterThanOrEqual(
            reminders.components(separatedBy: "guard Pro.isUnlocked").count - 1,
            3,
            "reminder access, pull, and push must not be UI-only gates")
    }

    func testUnlockedEntitlementKeepsRequestedCloudIntegrations() {
        let requested = CloudPreferences(calendarSyncHabits: true,
                                         calendarSyncReminders: true,
                                         nativeReminderSync: true)

        XCTAssertEqual(ProGate.restrictedCloudPreferences(requested, unlocked: true), requested)
    }

    func testCloudApplicationAndToggleReadbackUseTheSharedEntitlement() throws {
        let content = try source("Haiity/Views/ContentView.swift")
        let more = try source("Haiity/Views/MoreCalendar.swift")

        XCTAssertTrue(content.contains("ProGate.restrictedCloudPreferences"),
                      "iCloud must not restore paid integrations after entitlement loss")
        XCTAssertTrue(more.contains("guard unlocked else { return false }"),
                      "paid sync toggles must render locked after entitlement loss")
    }

    /// Das Limit lebt an EINER Stelle. Rechnet eine Ansicht selbst mit der
    /// Drei, wandert sie beim nächsten Produktbeschluss nicht mit.
    func testOnlyProGateKnowsTheNumber() throws {
        for file in ["Haiity/Views/ContentView.swift",
                     "Haiity/Views/MoreView.swift",
                     "Haiity/Views/MorePro.swift",
                     "Haiity/Views/StatsView.swift",
                     "Haiity/Views/EditHabitSheet.swift"] {
            XCTAssertFalse(try source(file).contains("freeHabitLimit"),
                           "\(file) rechnet selbst mit dem Limit statt ProGate zu fragen")
        }
    }

    func testExpiredProShowsOnlyThreeTrackedHabitsButKeepsReminders() {
        let first = Habit(name: "A")
        let reminder = Habit(name: "Erinnerung", itemType: .reminder)
        let second = Habit(name: "B")
        let third = Habit(name: "C")
        let fourth = Habit(name: "D")

        let visible = ProGate.visibleActiveHabits(
            [first, reminder, second, third, fourth], unlocked: false)

        XCTAssertEqual(visible.map(\.name), ["A", "Erinnerung", "B", "C"])
        XCTAssertEqual(visible.filter(\.isTrackedHabit).count, 3)
    }

    func testUnlockedProKeepsEveryActiveHabitVisible() {
        let habits = [Habit(name: "A"), Habit(name: "B"), Habit(name: "C"), Habit(name: "D")]

        XCTAssertEqual(ProGate.visibleActiveHabits(habits, unlocked: true).count, habits.count)
    }

    func testMainSurfacesUseTheEntitlementFilteredHabitCollection() throws {
        let content = try source("Haiity/Views/ContentView.swift")
        let stats = try source("Haiity/Views/StatsView.swift")

        XCTAssertTrue(content.contains("ProGate.visibleActiveHabits"))
        XCTAssertTrue(stats.contains("ProGate.visibleActiveHabits"))
    }

    func testSharedVisibilityMatchesTheExpiredProPolicy() {
        let habits = [Habit(name: "A"),
                      Habit(name: "B"),
                      Habit(name: "C"),
                      Habit(name: "D"),
                      Habit(name: "Reminder", itemType: .reminder)]

        XCTAssertEqual(
            HabitVisibility.visibleActiveHabits(habits, unlocked: false).map(\.name),
            ["A", "B", "C", "Reminder"])
        XCTAssertEqual(
            HabitVisibility.visibleActiveHabits(habits, unlocked: true).count,
            habits.count)
    }

    func testWidgetAndIntentSurfacesUseSharedVisibility() throws {
        let intent = try source("Haiity/Intents/CheckOffHabitIntent.swift")
        let graphIntent = try source("Haiity/Intents/SelectGraphIntent.swift")
        let siri = try source("Haiity/Intents/SiriQueryIntents.swift")
        let widget = try source("HaiityWidget/HaiityWidget.swift")

        for text in [intent, graphIntent, siri, widget] {
            XCTAssertTrue(text.contains("HabitVisibility.visibleActiveHabits"),
                          "(text.prefix(40)) must use the shared entitlement filter")
        }
    }

    func testAppRefreshesProWithoutUnsafeDowngradeOnLaunchAndForeground() throws {
        let app = try source("Haiity/HaiityApp.swift")

        XCTAssertEqual(app.components(separatedBy: "Task { await Pro.refresh() }").count - 1,
                       2,
                       "launch and foreground must both re-check the current entitlement")
        XCTAssertTrue(app.contains("case .active:"))
        XCTAssertFalse(app.contains("mayDowngrade: true"),
                       "lifecycle reads must not erase cached offline Pro access")
    }

    func testAppUsesTransactionListenerWithoutContinuousEntitlementPolling() throws {
        let content = try source("Haiity/Views/ContentView.swift")
        let pro = try source("Haiity/Models/ProEntitlement.swift")

        XCTAssertTrue(content.contains("Pro.startTransactionListener()"),
                      "live StoreKit updates must remain active")
        XCTAssertFalse(content.contains("Pro.startEntitlementMonitor()"))
        XCTAssertFalse(pro.contains("static func startEntitlementMonitor()"))
        XCTAssertFalse(pro.contains("entitlementPollInterval"))
        XCTAssertFalse(pro.contains("Task.sleep(for:"))
        XCTAssertFalse(pro.contains("heartbeat"))
    }

    func testRootRequestsTheProGateWhenAnActiveSessionExpires() throws {
        let content = try source("Haiity/Views/ContentView.swift")

        XCTAssertTrue(content.contains(".onChange(of: proStatus.unlocked)"),
                      "the root must observe an entitlement downgrade while alive")
        XCTAssertTrue(content.contains("guard old && !new else { return }"),
                      "only an unlocked-to-locked transition should interrupt the user")
        XCTAssertTrue(content.contains("paywall = .settings"),
                      "an expiry must show the global Pro gate, not wait for a feature tap")
    }

    func testRootReappliesSharedCloudPreferencesWhenEntitlementChanges() throws {
        let content = try source("Haiity/Views/ContentView.swift")
        let start = try XCTUnwrap(content.range(of: ".onChange(of: proStatus.unlocked)"))
        let end = try XCTUnwrap(content.range(of: ".onChange(of: showAdd)",
                                              range: start.upperBound..<content.endIndex))
        let block = String(content[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(block.contains("applyCloudPreferences()"),
                      "an entitlement flip must immediately re-derive paid sync toggles from the shared Pro gate")
    }

    func testOptionalAppleSignInCannotRevokeStoreKitAccess() throws {
        let more = try source("Haiity/Views/MorePersonal.swift")

        XCTAssertTrue(more.contains("Task { await Pro.refresh() }"))
        XCTAssertFalse(more.contains("Pro.refresh(mayDowngrade: true)"),
                       "personalization is independent of the App Store purchase account")
    }

    func testAllExistingProFeatureHostsReadTheSharedEntitlement() throws {
        for file in ["Haiity/Views/MoreView.swift",
                     "Haiity/Views/StatsView.swift",
                     "Haiity/Views/EditHabitSheet.swift"] {
            let text = try source(file)
            XCTAssertTrue(text.contains("Pro.isUnlocked") || text.contains("unlocked"), file)
        }

        // ContentView owns navigation only. Creation is delegated to the
        // editor, which contains the single ProGate check before saving.
        let content = try source("Haiity/Views/ContentView.swift")
        XCTAssertTrue(content.contains("EditHabitSheet(store: store, asPage: true,"))
        XCTAssertTrue(content.contains("private func requestCreate()"))
    }

    func testPaidSurfacesObserveEntitlementChanges() throws {
        for file in ["Haiity/Views/MoreView.swift",
                     "Haiity/Views/StatsView.swift",
                     "Haiity/Views/PaywallView.swift"] {
            let text = try source(file)
            XCTAssertTrue(text.contains("@State private var proStatus = ProStatus.shared"), file)
            XCTAssertTrue(text.contains("proStatus.unlocked"),
                          "(file) must observe a downgrade from StoreKit")
        }
    }

    // MARK: – Reine Logik: das Kaufblatt

    /// Sechs Einstiege, sechs Sätze: der Kontext ändert die Kopfzeile, damit
    /// niemand raten muss, warum das Blatt aufging. Zwei gleiche Sätze wären
    /// ein vergessener Fall.
    func testEveryPaywallContextHasItsOwnHeadline() {
        let headlines = PaywallContext.allCases.map(\.headline)
        XCTAssertEqual(PaywallContext.allCases.count, 6)
        for headline in headlines {
            XCTAssertFalse(headline.isEmpty)
        }
        XCTAssertEqual(Set(headlines).count, headlines.count, "doppelte Kopfzeile")
        // Die Kennung ist der rohe Fall — daran hängt `.sheet(item:)`.
        XCTAssertEqual(Set(PaywallContext.allCases.map(\.id)).count, 6)
    }

    // MARK: – Quell-Verträge

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relative))
    }

    /// (a) Die Kennungen, an denen die Simulator-Automatisierung hängt, und
    /// der Kernsatz. Der Wiederherstellen-Knopf ist keine Geschmacksfrage,
    /// sondern App-Store-Regel 3.1.1 — ohne ihn wird abgelehnt.
    func testPaywallCarriesTheContractIdentifiersAndTheCoreSentence() throws {
        let paywall = try source("Haiity/Views/PaywallView.swift")
        for id in ["\"paywall-purchase\"", "\"paywall-restore\"", "\"paywall-close\""] {
            XCTAssertTrue(paywall.contains(id), id)
        }
        XCTAssertTrue(paywall.contains("Einmal kaufen. Kein Abo, kein Konto, kein Server."),
                      "der Kernsatz fehlt")
        XCTAssertTrue(paywall.contains("Käufe wiederherstellen"),
                      "Wiederherstellen ist Pflicht (App-Store-Regel 3.1.1)")
        // Schließen ab dem ersten Frame: der X-Knopf sitzt in der
        // Abbrechen-Position der Werkzeugleiste, nicht hinter einer Wartezeit.
        XCTAssertTrue(paywall.contains("placement: .cancellationAction"))
    }

    /// (a) Keine dunklen Muster und keine erfundene Zahl: der Betrag kommt
    /// aus dem Store. Ein hart geschriebener Preis ist in jeder anderen
    /// Währung und nach jeder Preisanpassung eine Lüge.
    func testPaywallPriceComesFromTheStoreNotTheSource() throws {
        let paywall = try source("Haiity/Views/PaywallView.swift")
        XCTAssertTrue(paywall.contains("product.displayPrice"))
        XCTAssertTrue(paywall.contains("Preis nicht verfügbar"),
                      "ohne Produkt muss der Knopf das sagen statt zu raten")
        XCTAssertTrue(paywall.contains("product == nil"),
                      "ohne Preis muss der Kaufknopf aus sein")
        for invented in ["9,99", "9.99", "€"] {
            XCTAssertFalse(paywall.contains(invented),
                           "hart geschriebener Preis im Quelltext: \(invented)")
        }
    }

    /// (a) **Die Icon-Zeile darf nicht mehr versprechen, als sie hält.** iOS
    /// kann nur MITGELIEFERTE Icons setzen, und alle 18 sind ohne Pro
    /// antippbar (`ForEach(AppIcons.hues)` in MoreView, ohne Gate). Eine
    /// Kaufzeile mit „freier" Farbe verkauft damit eine Ergebnismenge, die
    /// der Frei-Zustand längst hat — bezahlt wird das Farbrad als EINGABE.
    func testTheIconFeatureSellsTheColorWheelNotAFreeColor() throws {
        let paywall = try source("Haiity/Views/PaywallView.swift")
        XCTAssertTrue(paywall.contains("Icon per Farbrad"))
        XCTAssertTrue(paywall.contains("18 mitgelieferten Icons"),
                      "die Zeile muss das Runden auf die 18 nennen")
        for lie in ["Freie Icon-Farbe", "Freie Farbe fürs App-Icon"] {
            XCTAssertFalse(paywall.contains(lie),
                           "verspricht eine freie Icon-Farbe, die es nicht gibt: \(lie)")
        }
        // Dasselbe im Listing und auf der Produktseite — drei Texte über
        // dasselbe Produkt, die auseinanderlaufen, sind zwei zu viel.
        let listing = try source("docs/store-listing.md")
        XCTAssertFalse(listing.contains("freie Icon-Farbe"))
        XCTAssertFalse(listing.contains("a free icon color"))
        XCTAssertFalse(listing.contains("a free app-icon color"))
    }

    /// (b) **Gate 1 — Anlegen.** Der einzige harte Unterschied zwischen frei
    /// und Pro, und deshalb der Test mit dem meisten Wert: `showAdd = true`
    /// darf im GANZEN Bildschirm nur EINMAL vorkommen, nämlich hinter dem
    /// Wächter. Vier Einstiege (Werkzeugleiste, leerer Zustand, Chrom,
    /// Deep-Link) und ein vergessener wäre ein Weg am Limit vorbei, den kein
    /// Screenshot findet.
    func testGate1EveryCreatePathRunsThroughTheOneGuard() throws {
        let content = try source("Haiity/Views/ContentView.swift")
        let editor = try source("Haiity/Views/EditHabitSheet.swift")
        XCTAssertTrue(content.contains("private func requestCreate()"))
        XCTAssertFalse(content.contains("ProGate.mayAddHabit(activeCount:"),
                       "der Typ steht erst im Editor fest; der Einstieg darf Erinnerungen nicht blockieren")
        XCTAssertTrue(editor.contains("ProGate.maySaveTrackedHabit"))
        XCTAssertTrue(editor.contains("existingIsTracked: existing?.isTrackedHabit == true"),
                      "existing tracked habits must remain editable")
        XCTAssertTrue(editor.contains("targetIsTracked: itemType == .habit"),
                      "reminder-to-habit conversion must pass through the gate")
        XCTAssertTrue(editor.contains("store.activeTrackedHabits.count"),
                      "only active tracked habits count at the save boundary")
        XCTAssertTrue(editor.contains("paywall = .habits"))

        let assignments = content.components(separatedBy: "showAdd = true").count - 1
        XCTAssertEqual(assignments, 1,
                       "das Anlege-Cover darf nur aus requestCreate() aufgehen")
    }

    /// (b) **Gate 2 — eigene Farben.** Die Paywall verspricht eigene Farben
    /// als Pro; deshalb gilt der Zaun für Anlegen, Auswahl und Bearbeiten,
    /// auch wenn die Daten von einem früheren Pro-Zeitraum noch vorhanden sind.
    func testGate2EveryCustomPalettePathIsGated() throws {
        let more = try source("Haiity/Views/MoreAppearance.swift")
        let editor = try source("Haiity/Views/EditHabitSheet.swift")
        let content = try source("Haiity/Views/ContentView.swift")
        XCTAssertTrue(more.contains("func requestCustomPalette()"))
        XCTAssertTrue(more.contains("paywall = .palette"))
        // Zweimal: die Definition und der EINE Aufruf an „Eigene Farbe …".
        XCTAssertEqual(more.components(separatedBy: "requestCustomPalette()").count - 1, 2,
                       "„Eigene Farbe …\" muss durch den Wächter laufen")
        XCTAssertTrue(more.contains("\"palette-add-custom\""))
        let requestRange = try XCTUnwrap(more.range(of: "func requestCustomPalette()"))
        let body = more[requestRange.lowerBound...]
        XCTAssertTrue(body.contains("guard ProGate.mayUseProFeature(unlocked: unlocked)"))
        XCTAssertTrue(more.contains("func selectCustomPalette"),
                      "existing custom palettes need the same entitlement gate as creation")
        XCTAssertTrue(editor.contains("palettes: unlocked ? palettes : palettes.withoutCustoms"),
                      "locked editors must not expose old custom palettes")
        XCTAssertTrue(content.contains("store.palettes.withoutCustoms"),
                      "locked app surfaces must fall back from persisted custom palettes")
    }

    func testStatsAdjustmentsAreAProSurface() throws {
        let stats = try source("Haiity/Views/StatsView.swift")
        XCTAssertTrue(stats.contains("private func openStatsAdjustments()"))
        XCTAssertTrue(stats.contains("paywall = .stats"))
        XCTAssertTrue(stats.contains("openStatsAdjustments()"),
                      "toolbar, empty state, and long-press actions must share the gate")
    }

    /// (b) **Gate 3 — freie Icon-Farbe.** Gegated ist nur das SETZEN: die 18
    /// Kacheln, das Farbrad und die ehrliche Vorschau bleiben frei.
    func testGate3FreeIconColorIsGated() throws {
        let more = try source("Haiity/Views/MoreAppearance.swift")
        XCTAssertTrue(more.contains("var freeIconColorAction"))
        XCTAssertTrue(more.contains("paywall = .icon"))
        XCTAssertTrue(more.contains("\"icon-color-pro\""))
        // Der Anwenden-Knopf bleibt im freigeschalteten Zweig bestehen —
        // IconStudioTests verlangt die Kennung weiterhin.
        XCTAssertTrue(more.contains("\"icon-color-apply\""))
        // Das Farbrad ist NICHT gegated.
        XCTAssertTrue(more.contains("\"icon-color-picker\""))
    }

    /// (b) **Gate 4 — Kalender-Spiegel.** Nur das EINschalten ist Pro.
    /// Ausschalten bleibt immer frei (sonst bliebe nach einer Erstattung ein
    /// Schalter zurück, den niemand mehr umlegen kann), und das Gate greift
    /// VOR der Berechtigungsfrage — eine Nachfrage für eine Funktion, die
    /// danach doch nicht läuft, wäre unter falschem Vorwand gestellt.
    func testGate4CalendarMirrorIsGatedOnEnableOnly() throws {
        let more = try source("Haiity/Views/MoreCalendar.swift")
        let editor = try source("Haiity/Views/EditHabitSheet.swift")
        XCTAssertTrue(more.contains("paywall = .calendar"))
        XCTAssertTrue(editor.contains("private var calendarSyncBinding"),
                      "per-habit calendar access needs the same paid gate")
        XCTAssertTrue(editor.contains("pendingCalendarEnable = true"),
                      "a locked editor must resume the attempted calendar enable after purchase")
        XCTAssertTrue(editor.contains("habit.calendarSyncEnabled = unlocked && calendarSyncEnabled"),
                      "a locked save must not persist an active paid integration")
        let disableRange = try XCTUnwrap(more.range(of: "CalendarSync.disable()"))
        let gateRange = try XCTUnwrap(more.range(of: "paywall = .calendar"))
        let askRange = try XCTUnwrap(more.range(of: "CalendarSync.requestAccess()"))
        XCTAssertTrue(disableRange.upperBound < gateRange.lowerBound,
                      "Ausschalten muss VOR dem Gate liegen — es bleibt frei")
        XCTAssertTrue(gateRange.upperBound < askRange.lowerBound,
                      "das Gate muss VOR der Kalender-Berechtigung greifen")
    }

    func testNativeReminderSyncIsGatedAndOwnsItsPermissionMetadata() throws {
        let more = try source("Haiity/Views/MoreCalendar.swift")
        let project = try source("project.yml")

        XCTAssertFalse(CalendarFeatureGate.canEnable(unlocked: false))
        XCTAssertTrue(CalendarFeatureGate.canEnable(unlocked: true))
        XCTAssertTrue(more.contains("native-reminder-sync-toggle"))
        XCTAssertTrue(more.contains("ReminderSync.requestAccess()"))
        XCTAssertTrue(more.contains("ReminderSync.disable()"))
        XCTAssertTrue(more.contains("paywall = .calendar"))
        XCTAssertTrue(more.contains("open-reminder-settings"))
        XCTAssertTrue(project.contains("NSRemindersFullAccessUsageDescription"))
    }

    /// (b) **Gate 5 — Statistik.** Der Schnitt liegt auf der Sektion, nicht
    /// mitten in einer Karte. Held-Karte und Basis-Kacheln bleiben frei,
    /// gegated ist das ABLESEN — und zwar am echten, nur unscharfen Raster:
    /// ein erfundener Platzhalter wäre eine Behauptung über Daten, die längst
    /// da sind. Gerechnet und gespeichert wird unverändert weiter.
    func testGate5StatsGatesTheReadingNotTheData() throws {
        let stats = try source("Haiity/Views/StatsView.swift")
        XCTAssertTrue(stats.contains("paywall = .stats"))
        XCTAssertTrue(stats.contains("private var perHabitLockCard"))
        XCTAssertTrue(stats.contains(".blur(radius:"),
                      "der Puls wird unscharf gezeigt, nicht ersetzt")
        // The rebuilt rhythm card uses one shared raster path. The gate is
        // applied to the card's presentation, not by replacing its data.
        XCTAssertEqual(stats.components(separatedBy: "mergedGrid(snapshot.mergedLevels)").count - 1, 1,
                       "auch gesperrt wird das ECHTE Raster gezeichnet")
        XCTAssertTrue(stats.contains("ContributionTiles("),
                      "the rhythm card must reuse the shared canvas tiles")
        XCTAssertTrue(stats.contains("\"stats-rhythm-card\""))
    }

    /// (b) **Gate 6 — der Einstieg in den Einstellungen.** Ohne diese Zeile
    /// gäbe es keinen Weg zum Kauf, der nicht an einer Sperre hängt — wer
    /// kaufen WILL, soll nicht erst gegen eine Wand laufen müssen.
    func testGate6MoreViewOffersTheProSection() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        let pro = try source("Haiity/Views/MorePro.swift")
        let mainStart = try XCTUnwrap(more.range(of: "var mainSettings: some View"))
        let mainEnd = try XCTUnwrap(more.range(of: "var accentColor: Color",
                                               range: mainStart.upperBound..<more.endIndex))
        let main = more[mainStart.lowerBound..<mainEnd.lowerBound]
        XCTAssertTrue(main.contains("proSection"),
                      "the root hub must render the extracted Pro section")
        XCTAssertTrue(more.contains(".sheet(item: $paywall, onDismiss: resumeAfterPurchase)"),
                      "the root must retain the paywall presentation")
        XCTAssertTrue(pro.contains("extension MoreView {"))
        XCTAssertTrue(pro.contains("var proSection: some View"))
        XCTAssertTrue(pro.contains("\"open-paywall\""))
        XCTAssertTrue(pro.contains("\"pro-status\""))
        XCTAssertTrue(pro.contains("paywall = .settings"))
        XCTAssertTrue(pro.contains("Mehr Habits, Farben, Kalender und Statistik."))
        // Kein zweiter Kaufknopf für etwas, das schon gekauft ist.
        XCTAssertTrue(pro.contains("Freigeschaltet. Danke."))
        XCTAssertTrue(pro.contains("Text(verbatim: \"hAiity Pro\")"))
        XCTAssertTrue(pro.contains("var proLock: some View"))
        XCTAssertTrue(pro.contains(".accessibilityLabel(String(localized: \"Nur mit hAiity Pro\"))"))
        XCTAssertFalse(pro.contains("@State"),
                       "the extracted Pro page must use the root's state")
        XCTAssertFalse(pro.contains(".sheet("),
                       "the extracted Pro page must not own another presenter")
    }

    func testUnlockedProRowReopensTheFeatureSheet() throws {
        let pro = try source("Haiity/Views/MorePro.swift")
        let unlockedStart = try XCTUnwrap(pro.range(of: "if unlocked {"))
        let lockedStart = try XCTUnwrap(pro.range(of: "} else {", range: unlockedStart.upperBound..<pro.endIndex))
        let unlockedBranch = String(pro[unlockedStart.lowerBound..<lockedStart.lowerBound])

        XCTAssertTrue(unlockedBranch.contains("Button {"))
        XCTAssertTrue(unlockedBranch.contains("paywall = .settings"))
        XCTAssertTrue(unlockedBranch.contains("\"pro-status\""))
        XCTAssertTrue(unlockedBranch.contains("\"open-pro-details\""))
        XCTAssertTrue(unlockedBranch.contains("chevron.right"))
        XCTAssertTrue(pro.contains("\"open-paywall\""))
    }

    // MARK: – Der Merker: was er darf und was nicht

    /// **Der Bestandsabgleich stuft nur HOCH.** `currentEntitlements` ist
    /// eine lokale Aufzählung — ohne Netz ist sie genauso leer wie auf einem
    /// Gerät, das den Kauf wirklich nicht hat. Ein Merker, den der erste
    /// Start am Morgen löscht, ist keine Wahrheit, sondern eine zweite
    /// Kaufaufforderung an jemanden, der schon bezahlt hat.
    func testRefreshOnlyUpgradesUnlessTheStoreReallyAnswered() throws {
        let pro = try source("Haiity/Models/ProEntitlement.swift")
        XCTAssertTrue(pro.contains("static func refresh(mayDowngrade: Bool = false) async"))
        XCTAssertTrue(pro.contains("guard unlocked || mayDowngrade else { return }"))
        // Der explizite Restore und eine verifizierte Transaktionsmeldung
        // dürfen nach einer StoreKit-Antwort herabstufen. Der normale
        // Bestandsabgleich bleibt weiterhin upgrade-only.
        XCTAssertGreaterThanOrEqual(pro.components(separatedBy: "mayDowngrade: true").count - 1, 2)
        // Die Erstattung kommt weiterhin über den Lauscher an.
        XCTAssertTrue(pro.contains("transaction.revocationDate"))
        // Und ein nachlaufendes Ergebnis überschreibt ihn nicht.
        XCTAssertTrue(pro.contains("guard generation == writeGeneration else { return }"))
    }

    func testDowngradeStopsProCalendarIntegrations() throws {
        let pro = try source("Haiity/Models/ProEntitlement.swift")

        XCTAssertTrue(pro.contains("let effectiveUnlocked = unlocked || ownerDevice"))
        XCTAssertTrue(pro.contains("CalendarSync.disable()"))
        XCTAssertTrue(pro.contains("ReminderSync.disable()"))
    }

    /// **Wiederherstellen reicht seinen Fehler weiter.** „Keine Verbindung"
    /// und „auf diesem Konto liegt kein Kauf" sind zwei verschiedene
    /// Aussagen; wer die falsche liest, kauft ein zweites Mal.
    func testRestorePropagatesTheStoreError() throws {
        let pro = try source("Haiity/Models/ProEntitlement.swift")
        XCTAssertTrue(pro.contains("static func restore() async throws"))
        XCTAssertTrue(pro.contains("try await AppStore.sync()"))
        XCTAssertFalse(pro.contains("try? await AppStore.sync()"),
                       "der verschluckte Fehler wird zur Falschaussage über die Kaufhistorie")
        let paywall = try source("Haiity/Views/PaywallView.swift")
        XCTAssertTrue(paywall.contains("try await Pro.restore()"))
        XCTAssertTrue(paywall.contains("private func restoreFailed"))
        XCTAssertTrue(paywall.contains("note = .storeUnreachable"))
    }

    /// **Der Merker ist beobachtbar.** Der Kauf muss nicht in der Ansicht
    /// passieren, die ihn zeigt: anderes Blatt oder anderes Gerät. Ohne
    /// Beobachtung bliebe die Statistik gesperrt
    /// und die Einstellungen böten den Kauf weiter an — und genau das
    /// widerspräche dem Satz, den die Kaufseite über die Kaufanfrage sagt.
    func testTheEntitlementIsObservableAndStillHasOneReadPoint() throws {
        let pro = try source("Haiity/Models/ProEntitlement.swift")
        XCTAssertTrue(pro.contains("@Observable"))
        XCTAssertTrue(pro.contains("final class ProStatus"))
        XCTAssertTrue(pro.contains("DeveloperAccess.isOwnerDevice("),
                      "das verifizierte Entwicklerkonto muss Pro immer behalten")
        XCTAssertTrue(pro.contains("ProStatus.shared.unlocked"))
        XCTAssertTrue(pro.contains("expirationDate.map"),
                      "the live gate must account for expiring entitlements")
        for file in ["Haiity/Views/MoreView.swift", "Haiity/Views/StatsView.swift",
                     "Haiity/Views/PaywallView.swift", "Haiity/Views/EditHabitSheet.swift",
                     "Haiity/Views/ArchiveView.swift", "Haiity/Views/ReminderSetupView.swift",
                     "Haiity/Views/ContentView.swift"] {
            let text = try source(file)
            XCTAssertTrue(text.contains("Pro.isUnlocked"), file)
            XCTAssertFalse(text.contains("proStatus.unlocked || Pro.isUnlocked"),
                           "\(file) must not bypass expiry with the cached entitlement")
            XCTAssertFalse(text.contains("proUnlocked"),
                           "\(file) liest den Merker an StoreKit vorbei aus den Defaults")
        }
    }

    func testMoreViewDoesNotBypassExpiryWithTheCachedEntitlement() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        let pro = try source("Haiity/Views/MorePro.swift")
        XCTAssertTrue(more.contains("return Pro.isUnlocked"))
        XCTAssertFalse(more.contains("proStatus.unlocked || Pro.isUnlocked"),
                       "an expired cached entitlement must not keep paid settings enabled")
        XCTAssertTrue(pro.contains("if unlocked {"),
                      "the Pro page must use the root's live entitlement")
        for file in ["Haiity/Views/MorePro.swift",
                     "Haiity/Views/MoreCalendar.swift",
                     "Haiity/Views/MorePersonal.swift",
                     "Haiity/Views/MoreAppearance.swift",
                     "Haiity/Views/MoreNotifications.swift",
                     "Haiity/Views/MoreBehavior.swift",
                     "Haiity/Views/MoreLocalModel.swift"] {
            let page = try source(file)
            for bypass in ["Pro.isUnlocked", "proStatus.unlocked", "proUnlocked"] {
                XCTAssertFalse(page.contains(bypass),
                               "\(file) must not introduce a second entitlement read: \(bypass)")
            }
        }
    }

    func testSharedExtensionGateRecognizesTheVerifiedOwnerIdentity() {
        let defaults = UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard
        let oldUserID = defaults.object(forKey: PersonalName.appleUserIDKey)
        let oldEmail = defaults.object(forKey: PersonalName.appleEmailKey)
        let oldUnlocked = defaults.object(forKey: HabitVisibility.proUnlockedKey)
        let oldExpiration = defaults.object(forKey: HabitVisibility.proEntitlementExpirationKey)
        defer {
            restore(oldUserID, forKey: PersonalName.appleUserIDKey, in: defaults)
            restore(oldEmail, forKey: PersonalName.appleEmailKey, in: defaults)
            restore(oldUnlocked, forKey: HabitVisibility.proUnlockedKey, in: defaults)
            restore(oldExpiration, forKey: HabitVisibility.proEntitlementExpirationKey, in: defaults)
        }

        defaults.set(DeveloperAccess.ownerAppleUserID, forKey: PersonalName.appleUserIDKey)
        defaults.removeObject(forKey: PersonalName.appleEmailKey)
        defaults.removeObject(forKey: HabitVisibility.proUnlockedKey)

        XCTAssertTrue(HabitVisibility.sharedEntitlementIsUnlocked,
                      "widgets and intents must preserve the verified owner access")

        defaults.set("different-account", forKey: PersonalName.appleUserIDKey)
        defaults.removeObject(forKey: PersonalName.appleEmailKey)
        defaults.removeObject(forKey: HabitVisibility.proUnlockedKey)
        XCTAssertFalse(HabitVisibility.sharedEntitlementIsUnlocked,
                       "a replacement account must not inherit owner access")
    }

    func testStoreKitEntitlementContractChecksExpirationDate() throws {
        let pro = try source("Haiity/Models/ProEntitlement.swift")
        XCTAssertTrue(pro.contains("transaction.expirationDate"),
                      "an expired StoreKit entitlement must not remain unlocked")
        XCTAssertTrue(pro.contains("await refresh(mayDowngrade: true)"),
                      "transaction updates must aggregate the current entitlement set")
    }

    @MainActor
    func testCurrentEntitlementPolicyRejectsExpiredRevokedAndNonPurchasedTransactions() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertTrue(Pro.isCurrent(productID: Pro.productID,
                                    ownershipIsPurchased: true,
                                    revocationDate: nil,
                                    expirationDate: now.addingTimeInterval(60),
                                    now: now))
        XCTAssertTrue(Pro.isCurrent(productID: Pro.productID,
                                    ownershipIsPurchased: true,
                                    revocationDate: nil,
                                    expirationDate: nil,
                                    now: now),
                      "a lifetime purchase has no expiration date")
        XCTAssertFalse(Pro.isCurrent(productID: Pro.productID,
                                     ownershipIsPurchased: true,
                                     revocationDate: nil,
                                     expirationDate: now,
                                     now: now))
        XCTAssertFalse(Pro.isCurrent(productID: Pro.productID,
                                     ownershipIsPurchased: true,
                                     revocationDate: now,
                                     expirationDate: now.addingTimeInterval(60),
                                     now: now))
        XCTAssertFalse(Pro.isCurrent(productID: "other.product",
                                     ownershipIsPurchased: true,
                                     revocationDate: nil,
                                     expirationDate: nil,
                                     now: now))
        XCTAssertFalse(Pro.isCurrent(productID: Pro.productID,
                                     ownershipIsPurchased: false,
                                     revocationDate: nil,
                                     expirationDate: nil,
                                     now: now))
    }

    func testSharedEntitlementSnapshotExpiresWithoutTheAppProcess() {
        let suiteName = "haiity-pro-expiry-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 20_000)
        defaults.set(true, forKey: HabitVisibility.proUnlockedKey)
        defaults.set(now.addingTimeInterval(-1).timeIntervalSince1970,
                     forKey: HabitVisibility.proEntitlementExpirationKey)

        XCTAssertFalse(HabitVisibility.sharedEntitlementIsUnlocked(at: now,
                                                                    defaults: defaults))

        defaults.removeObject(forKey: HabitVisibility.proEntitlementExpirationKey)
        XCTAssertTrue(HabitVisibility.sharedEntitlementIsUnlocked(at: now,
                                                                   defaults: defaults),
                      "a non-expiring purchase remains unlocked")
    }

    func testAccountBoundaryResetIsWiredToAppleSignInAndSignOut() throws {
        let pro = try source("Haiity/Models/ProEntitlement.swift")
        XCTAssertTrue(pro.contains("static func accountDidChange()"))
        let more = try source("Haiity/Views/MorePersonal.swift")
        XCTAssertTrue(more.contains("Pro.accountDidChange()"))
        XCTAssertTrue(more.contains("PersonalName.appleUserID = credential.user"))
    }

    /// **Nach dem Kauf läuft weiter, wofür bezahlt wurde.** Sonst bleibt der
    /// klassische „bezahlt, und dann passierte nichts"-Moment: Blatt zu,
    /// dieselbe Wand, ein Haptik-Impuls als einziges Erfolgssignal.
    func testEveryPaywallHostResumesTheInterruptedIntent() throws {
        let content = try source("Haiity/Views/ContentView.swift")
        XCTAssertTrue(content.contains("onUnlocked: { purchasedIntent = context }"))
        XCTAssertTrue(content.contains("private func resumeAfterPurchase()"))
        XCTAssertTrue(content.contains("if intent == .habits { requestCreate() }"),
                      "der vierte Habit muss nach dem Kauf wirklich entstehen können")

        let more = try source("Haiity/Views/MoreView.swift")
        XCTAssertTrue(more.contains("onDismiss: resumeAfterPurchase"))
        XCTAssertTrue(more.contains("onUnlocked: { purchased = context }"))
        for resumed in ["calendarBinding(for: pendingCalendarItemType).wrappedValue = true",
                        "reminderSyncBinding.wrappedValue = true",
                        "creatingPalette = true",
                        "chooseIcon(named: snappedFreeIconName)"] {
            XCTAssertTrue(more.contains(resumed), resumed)
        }
    }

    /// Das Schloss am Kalender-Schalter meint das EINschalten. Läuft der
    /// Spiegel bereits (Erstattung, Bestandsgerät), stünde es neben einem
    /// Schalter, der an ist — VoiceOver läse „Nur mit hAiity Pro, Schalter,
    /// ein".
    func testCalendarLockYieldsWhileTheMirrorIsRunning() throws {
        let more = try source("Haiity/Views/MoreCalendar.swift")
        XCTAssertTrue(more.contains("if !unlocked && !enabled {"))
    }

    /// (c) **NIEMALS-Regel: Export und Import bleiben frei.** Die eigenen
    /// Daten hinter eine Kasse zu stellen wäre Geiselnahme — und ein Grund
    /// für Ablehnung. Geprüft wird der Abschnitt selbst, nicht die Datei:
    /// irgendwo in MoreView steht „paywall" natürlich.
    func testExportAndImportStayFree() throws {
        let transfer = try source("Haiity/Views/DataTransferView.swift")
        let more = try source("Haiity/Views/MoreView.swift")
        XCTAssertTrue(transfer.contains("\"export-data\""))
        XCTAssertTrue(transfer.contains("\"import-data\""))
        XCTAssertTrue(more.contains("\"open-data-transfer\""))

        let start = try XCTUnwrap(transfer.range(of: "var body: some View", range:
            try XCTUnwrap(transfer.range(of: "struct DataTransferSection")).upperBound..<transfer.endIndex))
        let end = try XCTUnwrap(transfer.range(of: "static func importJSON", range: start.upperBound..<transfer.endIndex))
        let section = String(transfer[start.lowerBound..<end.lowerBound])
        for forbidden in ["ProGate", "Pro.isUnlocked", "paywall", "proLock", "unlocked"] {
            XCTAssertFalse(section.contains(forbidden),
                           "Export/Import darf niemals gegated sein — gefunden: \(forbidden)")
        }
        // Auch der Export-Typ selbst kennt keine Berechtigung.
        XCTAssertFalse(more.contains("guard unlocked else { return Data()"))
    }

    func testBothTransferDestinationsUseTheSameImportBoundary() throws {
        let developer = try source("Haiity/Views/DeveloperView.swift")
        let transfer = try source("Haiity/Views/DataTransferView.swift")
        XCTAssertTrue(developer.contains("DataTransferSection(store: store)"))
        XCTAssertTrue(transfer.contains("ProGate.mayImport"),
                      "both transfer destinations must preserve the tracked-habit limit")
        XCTAssertTrue(transfer.contains("Pro.isUnlocked"),
                      "the import boundary must use the shared entitlement read point")
    }

    /// (d) Die StoreKit-Konfiguration beschreibt genau EIN nicht-verbrauchbares
    /// Produkt ohne Familienfreigabe.
    @MainActor
    func testStoreKitConfigurationDeclaresTheProduct() throws {
        let raw = try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity.storekit"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let products = try XCTUnwrap(json["products"] as? [[String: Any]])
        XCTAssertEqual(products.count, 1, "hAiity Pro ist EIN Kauf")
        let product = try XCTUnwrap(products.first)
        XCTAssertEqual(product["productID"] as? String, "com.aiity.haiity.pro")
        XCTAssertEqual(product["productID"] as? String, Pro.productID,
                       "Quelltext und Konfiguration müssen dieselbe ID nennen")
        XCTAssertEqual(product["type"] as? String, "NonConsumable",
                       "kein Abo — der Kernsatz verspricht das Gegenteil")
        XCTAssertEqual(product["familyShareable"] as? Bool, false)
        // Keine Abos, auch nicht versehentlich leer daneben stehend.
        XCTAssertEqual((json["subscriptionGroups"] as? [Any])?.count, 0)
        XCTAssertEqual((json["nonRenewingSubscriptions"] as? [Any])?.count, 0)
    }

    /// (d) Die Datei liegt bewusst NEBEN `Haiity/`. Unter dem Quellordner
    /// zöge `sources: - path: Haiity` sie als Ressource ins ausgelieferte
    /// Bundle — sie gehört zum SCHEMA, nicht zum Produkt.
    func testStoreKitFileLivesOutsideTheAppSources() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Haiity.storekit").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Haiity/Haiity.storekit").path),
            "eine .storekit unter Haiity/ landet im ausgelieferten Bundle")
    }

    /// (e) Ohne diese Verankerung kauft der Simulator gegen App Store Connect
    /// statt gegen die lokale Konfiguration — und die Kaufseite bleibt beim
    /// „Preis nicht verfügbar" stehen.
    func testProjectYamlAnchorsTheStoreKitConfigurationInTheScheme() throws {
        let yml = try source("project.yml")
        let schemes = try XCTUnwrap(yml.range(of: "\nschemes:"))
        let tail = String(yml[schemes.lowerBound...])
        XCTAssertTrue(tail.contains("storeKitConfiguration: Haiity.storekit"),
                      "die StoreKit-Konfiguration muss im SCHEMA hängen")
        // Sie darf nicht als Quelle/Ressource eingebunden sein.
        XCTAssertFalse(yml.contains("- Haiity.storekit"))
    }

    /// Die GitHub-Anbindung darf ausschliesslich Kontobeitraege lesen. Dieser
    /// Vertrag erlaubt API-Endpunkt und OAuth-Client-ID, sperrt aber jede
    /// Repository-Mutation und den frueheren proprietaeren Datenspeicher.
    func testGitHubIntegrationIsReadOnly() throws {
        let allGitHubSources = try [
            source("Haiity/Services/GitHubContributions.swift"),
            source("Haiity/Services/GitHubCredentials.swift"),
            source("Haiity/Services/GitHubDeviceFlow.swift"),
            source("Haiity/Models/GitHubContributionStore.swift"),
            source("Haiity/Views/GitHubContributionCard.swift"),
            source("Haiity/Views/GitHubSettingsView.swift")
        ].joined(separator: "\n")
        let forbidden = ["scope=repo", "\"scope\": \"repo\"", "createRepository",
                         "deleteRepository", "git/refs", "contents_url", "haiity-data"]
        for marker in forbidden {
            XCTAssertFalse(allGitHubSources.contains(marker), marker)
        }
    }

    /// (g) **Selbst-scharfschaltender Test.** Die Paywall-Schlüssel stehen
    /// zum Zeitpunkt dieser Runde noch NICHT im Katalog — der 16-Sprachen-Lauf
    /// ist ein eigener Schritt. Ein harter Test wäre heute rot und würde
    /// entweder den Lauf blockieren oder gleich wieder gelöscht.
    ///
    /// Deshalb der Aufhänger am Kernsatz: sobald der Lokalisierungs-Schritt
    /// ihn einträgt, hört dieser Test von selbst auf zu überspringen und
    /// prüft ab da die ganze Liste. Ein vergessener Schlüssel fällt dann auf,
    /// ohne dass jemand hier nachziehen muss.
    func testPaywallKeysAreInTheCatalog() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Localizable.xcstrings"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])

        let core = "Einmal kaufen. Kein Abo, kein Konto, kein Server."
        try XCTSkipUnless(strings[core] != nil, """
            Paywall-Schlüssel noch nicht im Katalog — der 16-Sprachen-Lauf \
            steht aus. Dieser Test schaltet sich selbst scharf, sobald der \
            Kernsatz eingetragen ist.
            """)

        // `PaywallContext.headline` is intentionally localized at runtime;
        // using it here would make the catalog-key check depend on the test
        // process locale and look for translated values instead of source keys.
        var keys = [core]
        keys += ["Mehr als drei Habits? Das ist Pro.",
                 "Eigene Farben? Das ist Pro.",
                 "Das App-Icon per Farbrad setzen? Das ist Pro.",
                 "Habits im Kalender? Das ist Pro.",
                 "Die ganze Statistik? Das ist Pro.",
                 "Alles freischalten — mit einem einzigen Kauf."]
        keys += ["Käufe wiederherstellen", "Freigeschaltet. Danke.",
                 "Preis wird geladen", "Preis nicht verfügbar",
                 "Kein Kauf abgeschlossen, nichts berechnet."]
        keys += ["Unbegrenzte Habits", "Eigene Farben", "Icon per Farbrad",
                 "Kalender-Spiegel", "Volle Statistik"]
        keys += ["Stell die Farbe am Rad ein — hAiity setzt das nächstliegende seiner 18 mitgelieferten Icons. Ohne Pro wählst du direkt aus den 18 Kacheln."]
        keys += ["Nur mit hAiity Pro", "Je Habit im Detail",
                 "Mit hAiity Pro freischalten"]
        for key in keys {
            XCTAssertNotNil(strings[key], "fehlt im Katalog: \(key)")
        }
        // Der Markenname steht in KEINEM Katalog — er heißt in jeder Sprache
        // gleich und läuft deshalb über `Text(verbatim:)`.
        XCTAssertNil(strings["hAiity Pro"], "der Markenname darf nicht übersetzbar sein")
    }

    private func restore(_ value: Any?, forKey key: String, in defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
