import XCTest
@testable import Haiity

/// Auswahl der Statistik-Karten: Standard, vollständige Auswahl, tolerantes
/// Codable und die Ablage in UserDefaults,
/// der aus Fingerweg und Zeilenbewegung entscheidet.
final class StatsCardPrefsTests: XCTestCase {
    func testViewPreferencesDefaultToExpandedWithAllStatsCards() {
        let prefs = ViewPreferences()

        XCTAssertFalse(prefs.compactMode)
        XCTAssertEqual(prefs.statsCards.active, StatsCardPrefs.defaultActive)
        XCTAssertFalse(prefs.statsCards.isCustomized)
        XCTAssertTrue(prefs.swipeActions.enabled)
        XCTAssertEqual(prefs.swipeActions.leading, .primary)
        XCTAssertEqual(prefs.swipeActions.trailing, .secondary)
        XCTAssertTrue(prefs.notificationActionsEnabled)
        XCTAssertTrue(prefs.autoArchiveCompletedItems)
    }

    func testViewPreferencesStorePersistsCompactModeAndCards() {
        let suite = "ViewPreferencesStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ViewPreferencesStore(defaults: defaults)
        store.compactMode = true
        store.setStatsCard(.streakFlame, active: false)

        let reloaded = ViewPreferencesStore(defaults: defaults)
        XCTAssertTrue(reloaded.compactMode)
        XCTAssertFalse(reloaded.statsCards.isActive(.streakFlame))
    }

    func testViewPreferencesStorePersistsSwipeActions() {
        let suite = "ViewPreferencesStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ViewPreferencesStore(defaults: defaults)
        store.update { $0.swipeActions = SwipeActionsPreferences(enabled: false,
                                                                   leading: .archive,
                                                                   trailing: .none) }

        XCTAssertEqual(ViewPreferencesStore(defaults: defaults).preferences.swipeActions,
                       SwipeActionsPreferences(enabled: false, leading: .archive, trailing: .none))
    }

    func testViewPreferencesStorePersistsNotificationActions() {
        let suite = "ViewPreferencesStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ViewPreferencesStore(defaults: defaults)
        store.update { $0.notificationActionsEnabled = false }

        XCTAssertFalse(ViewPreferencesStore(defaults: defaults)
            .preferences.notificationActionsEnabled)
    }

    func testViewPreferencesStorePersistsSelectedNotificationAction() {
        let suite = "ViewPreferencesNotificationActionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ViewPreferencesStore(defaults: defaults)
        store.update { $0.notificationAction = .archive }

        XCTAssertEqual(ViewPreferencesStore(defaults: defaults)
            .preferences.notificationAction, .archive)
    }

    func testViewPreferencesStorePersistsAutoArchivePreference() {
        let suite = "ViewPreferencesAutoArchiveTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ViewPreferencesStore(defaults: defaults)
        store.update { $0.autoArchiveCompletedItems = false }

        XCTAssertFalse(ViewPreferencesStore(defaults: defaults)
            .preferences.autoArchiveCompletedItems)
    }

    func testNotificationActionsDefaultToTwoVisibleSlotsAndAnOptionalThird() {
        XCTAssertEqual(ViewPreferences().notificationActions.slots,
                       [.primary, .secondary, .none])
    }

    func testViewPreferencesStorePersistsAllNotificationActionSlots() {
        let suite = "ViewPreferencesNotificationActionsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ViewPreferencesStore(defaults: defaults)
        store.update {
            $0.notificationActions = NotificationActionPreferences(
                slots: [.archive, .backfill, .none])
        }

        XCTAssertEqual(ViewPreferencesStore(defaults: defaults)
            .preferences.notificationActions.slots,
                       [.archive, .backfill, .none])
    }

    func testLegacySingleNotificationActionMigratesToTheFirstSlotOnly() throws {
        let raw = #"{"notificationAction":"archive"}"#.data(using: .utf8)!
        let preferences = try JSONDecoder().decode(ViewPreferences.self, from: raw)

        XCTAssertEqual(preferences.notificationActions.slots,
                       [.archive, .none, .none])
    }

    func testNotificationActionsOfferTheSameChoicesAsSwipeActions() {
        XCTAssertEqual(SwipeActionChoice.notificationSelectable, [
            .primary, .secondary, .archive, .backfill, .session, .edit, .none
        ])
    }

    func testNewerRemotePreferencesReplaceLocalPreferences() {
        let suite = "ViewPreferencesStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ViewPreferencesStore(defaults: defaults)
        store.adoptRemote(ViewPreferences(updatedAt: 100,
                                          statsCards: StatsCardPrefs(active: [.weekMomentum]),
                                          compactMode: true))

        XCTAssertTrue(store.compactMode)
        XCTAssertEqual(store.statsCards.active, [.weekMomentum])
    }

    func testOlderRemotePreferencesDoNotReplaceLocalPreferences() {
        let suite = "ViewPreferencesStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ViewPreferencesStore(defaults: defaults)
        store.adoptRemote(ViewPreferences(updatedAt: 100,
                                          statsCards: StatsCardPrefs(active: [.todayRing]),
                                          compactMode: true))
        store.adoptRemote(ViewPreferences(updatedAt: 99,
                                          statsCards: StatsCardPrefs(active: [.weekMomentum]),
                                          compactMode: false))

        XCTAssertTrue(store.compactMode)
        XCTAssertEqual(store.statsCards.active, [.todayRing])
    }


    // MARK: – Grundzustand und Auswahl

    func testDefaultIncludesEveryStatsCard() {
        XCTAssertEqual(StatsCardPrefs().active, [.yearPulse, .totals])
        XCTAssertEqual(StatsCardPrefs.defaultActive, [.yearPulse, .totals])
        XCTAssertFalse(StatsCardPrefs().isCustomized)
        XCTAssertTrue(StatsCardPrefs(active: StatsCard.allCases).isCustomized)
    }

    func testSetActivatesAndDeactivatesInOrder() {
        var prefs = StatsCardPrefs(active: [])
        prefs.set(.streakFlame, active: true)
        prefs.set(.todayRing, active: true)
        XCTAssertEqual(prefs.active, [.streakFlame, .todayRing])
        prefs.set(.streakFlame, active: false)
        XCTAssertEqual(prefs.active, [.todayRing])
    }

    func testAllStatsCardsCanBeSelected() {
        var prefs = StatsCardPrefs(active: [.yearPulse, .streakFlame])
        XCTAssertFalse(prefs.isFull)
        prefs.set(.todayRing, active: true)
        XCTAssertEqual(prefs.active, [.yearPulse, .streakFlame, .todayRing])
    }

    func testCanToggleAllowsActiveAndAvailableCards() {
        let full = StatsCardPrefs(active: StatsCard.allCases)
        XCTAssertTrue(full.canToggle(.yearPulse))
        XCTAssertTrue(full.canToggle(.totals))
        let free = StatsCardPrefs(active: [.yearPulse])
        XCTAssertTrue(free.canToggle(.todayRing))
    }

    func testInitSanitizesDuplicatesAndOverflow() {
        let prefs = StatsCardPrefs(active: [.todayRing, .todayRing, .yearPulse, .weekMomentum])
        XCTAssertEqual(prefs.active, [.todayRing, .yearPulse, .weekMomentum])
    }

    func testSetSameCardTwiceDoesNotDuplicate() {
        var prefs = StatsCardPrefs(active: [.yearPulse])
        prefs.set(.yearPulse, active: true)
        XCTAssertEqual(prefs.active, [.yearPulse])
    }

    // MARK: – Codable

    func testCodableRoundTripPreservesEmptySelection() throws {
        let empty = StatsCardPrefs(active: [])
        let raw = try JSONEncoder().encode(empty)
        let back = try JSONDecoder().decode(StatsCardPrefs.self, from: raw)
        // „Alle aus" ist eine Entscheidung — sie darf beim Lesen nicht zum
        // Standard (Rhythmus und Check-ins) zurückspringen.
        XCTAssertEqual(back.active, [])
    }

    func testDecodeDropsUnknownCardNames() throws {
        let raw = Data(#"{"active":["yearPulse","hologram","streakFlame","todayRing"]}"#.utf8)
        let prefs = try JSONDecoder().decode(StatsCardPrefs.self, from: raw)
        XCTAssertEqual(prefs.active, [.yearPulse, .streakFlame, .todayRing])
    }

    func testLegacyCustomizedSelectionSurvivesViewPreferencesMigration() throws {
        let raw = Data(#"{"updatedAt":42,"statsCards":{"active":["weekMomentum"]}}"#.utf8)
        let prefs = try JSONDecoder().decode(ViewPreferences.self, from: raw)

        XCTAssertEqual(prefs.statsCards.active, [.weekMomentum])
    }

    // MARK: – Ablage

    private func scratchDefaults() -> (UserDefaults, () -> Void) {
        let suite = "stats-prefs-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    func testLoadWithoutStoredValueIsDefault() {
        let (defaults, cleanup) = scratchDefaults()
        defer { cleanup() }
        XCTAssertEqual(StatsCardPrefs.load(from: defaults).active, StatsCardPrefs.defaultActive)
    }

    func testUncustomizedLoadUsesThePageDefaultAndKeepsAnExplicitAllFiveChoice() {
        let (defaults, cleanup) = scratchDefaults()
        defer { cleanup() }

        XCTAssertEqual(StatsCardPrefs.load(from: defaults).active, [.yearPulse, .totals])
        XCTAssertFalse(StatsCardPrefs.load(from: defaults).isCustomized)

        defaults.set(Data(#"{"active":["yearPulse"]}"#.utf8), forKey: StatsCardPrefs.storageKey)
        let legacy = StatsCardPrefs.load(from: defaults)
        XCTAssertEqual(legacy.active, [.yearPulse, .totals])
        XCTAssertFalse(legacy.isCustomized)

        let allFive = StatsCardPrefs(active: StatsCard.allCases, customized: true)
        allFive.save(to: defaults)
        let kept = StatsCardPrefs.load(from: defaults)
        XCTAssertEqual(kept.active, StatsCard.allCases)
        XCTAssertTrue(kept.isCustomized)
    }

    func testSaveThenLoadRoundTrips() {
        let (defaults, cleanup) = scratchDefaults()
        defer { cleanup() }
        var prefs = StatsCardPrefs(active: [])
        prefs.set(.weekMomentum, active: true)
        prefs.save(to: defaults)
        XCTAssertEqual(StatsCardPrefs.load(from: defaults).active, [.weekMomentum])
    }

    func testLoadWithCorruptDataFallsBackToDefault() {
        let (defaults, cleanup) = scratchDefaults()
        defer { cleanup() }
        defaults.set(Data("kaputt".utf8), forKey: StatsCardPrefs.storageKey)
        XCTAssertEqual(StatsCardPrefs.load(from: defaults).active, StatsCardPrefs.defaultActive)
    }

    func testStoreWritesEveryChange() {
        let (defaults, cleanup) = scratchDefaults()
        defer { cleanup() }
        let store = StatsCardStore(defaults: defaults)
        store.setStatsCard(.streakFlame, active: false)
        XCTAssertFalse(StatsCardPrefs.load(from: defaults).isActive(.streakFlame))
        let reloaded = StatsCardStore(defaults: defaults)
        XCTAssertFalse(reloaded.prefs.isActive(.streakFlame))
    }
}
