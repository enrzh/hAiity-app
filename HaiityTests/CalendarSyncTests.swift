import EventKit
import XCTest
@testable import Haiity

private func calendarSyncTestSource(_ relativePath: String,
                                    filePath: String = #filePath) throws -> String {
    let root = URL(fileURLWithPath: filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = root.appendingPathComponent(relativePath)
    if FileManager.default.fileExists(atPath: url.path) {
        return try String(contentsOf: url)
    }
    let resource = url.deletingPathExtension().lastPathComponent
    let extensionName = url.pathExtension
    let bundle = Bundle(for: CalendarSyncSelectionTests.self)
    guard let bundledURL = bundle.url(forResource: resource, withExtension: extensionName)
            ?? bundle.url(forResource: resource, withExtension: "txt") else {
        throw XCTSkip("Source contract unavailable in checkout and test bundle")
    }
    return try String(contentsOf: bundledURL)
}

final class CalendarSyncSelectionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "CalendarSyncSelectionTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testLegacyEnabledMigratesToHabitsOnly() {
        defaults.set(true, forKey: CalendarSyncPreferences.legacyEnabledKey)
        XCTAssertEqual(CalendarSyncPreferences.selection(in: defaults),
                       CalendarSyncSelection(habits: true, reminders: false))
    }

    func testLegacyDisabledMigratesToBothOff() {
        defaults.set(false, forKey: CalendarSyncPreferences.legacyEnabledKey)
        XCTAssertEqual(CalendarSyncPreferences.selection(in: defaults),
                       CalendarSyncSelection(habits: false, reminders: false))
    }

    func testAllSelectionCombinationsIncludeTheExpectedItemTypes() {
        let habit = Habit(name: "Lesen")
        let reminder = Habit(name: "Tabletten", itemType: .reminder)

        for habits in [false, true] {
            for reminders in [false, true] {
                let selection = CalendarSyncSelection(habits: habits, reminders: reminders)
                XCTAssertEqual(selection.includes(habit), habits)
                XCTAssertEqual(selection.includes(reminder), reminders)
            }
        }
    }

    func testIndividualOptOutOverridesEnabledType() {
        var habit = Habit(name: "Lesen")
        var reminder = Habit(name: "Tabletten", itemType: .reminder)
        habit.calendarSyncEnabled = false
        reminder.calendarSyncEnabled = false

        let selection = CalendarSyncSelection(habits: true, reminders: true)
        XCTAssertFalse(selection.includes(habit))
        XCTAssertFalse(selection.includes(reminder))
    }

    func testNewKeysOverrideLegacyPreference() {
        defaults.set(true, forKey: CalendarSyncPreferences.legacyEnabledKey)
        defaults.set(false, forKey: CalendarSyncPreferences.habitsEnabledKey)
        defaults.set(true, forKey: CalendarSyncPreferences.remindersEnabledKey)

        XCTAssertEqual(CalendarSyncPreferences.selection(in: defaults),
                       CalendarSyncSelection(habits: false, reminders: true))
    }

    func testCalendarDestinationsHaveStableCategoryNames() {
        XCTAssertEqual(CalendarSync.destinationTitle(isReminder: false), "hAiity Habits")
        XCTAssertEqual(CalendarSync.destinationTitle(isReminder: true), "hAiity Reminders")
        XCTAssertNotEqual(CalendarSync.habitsCalendarKey, CalendarSync.remindersCalendarKey)
        XCTAssertNotEqual(CalendarSync.habitsCalendarKey, CalendarSync.calendarKey)
        XCTAssertNotEqual(CalendarSync.remindersCalendarKey, CalendarSync.calendarKey)
    }

    func testCalendarCategoryIDsAreIndependent() {
        let suite = "calendar-category-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        CalendarSyncPreferences.setCalendarID("habit-id", isReminder: false, in: defaults)
        CalendarSyncPreferences.setCalendarID("reminder-id", isReminder: true, in: defaults)

        XCTAssertEqual(CalendarSyncPreferences.calendarID(isReminder: false, in: defaults), "habit-id")
        XCTAssertEqual(CalendarSyncPreferences.calendarID(isReminder: true, in: defaults), "reminder-id")
    }

    func testCalendarPlansRouteByItemType() {
        let habit = CalendarEventPlan(habit: Habit(name: "Lesen"), today: "2026-08-09")
        let reminder = CalendarEventPlan(habit: Habit(name: "Tabletten", itemType: .reminder),
                                         today: "2026-08-09")

        XCTAssertEqual(CalendarSync.destinationTitle(isReminder: habit?.isReminder ?? true), "hAiity Habits")
        XCTAssertEqual(CalendarSync.destinationTitle(isReminder: reminder?.isReminder ?? false), "hAiity Reminders")
    }

    func testCalendarSyncKeepsLegacyKeySeparateFromCategoryKeys() throws {
        let source = try calendarSyncTestSource("Haiity/Services/CalendarSync.swift")

        XCTAssertTrue(source.contains("static let calendarKey = \"calendarSyncCalendar\""))
        XCTAssertTrue(source.contains("static let habitsCalendarKey"))
        XCTAssertTrue(source.contains("static let remindersCalendarKey"))
        XCTAssertTrue(source.contains("func ensureCalendar(isReminder:"))
        XCTAssertTrue(source.contains("ownedEvents()"))
    }

    func testCalendarCleanupClearsBothCategoryIDsAndLegacyID() throws {
        let source = try calendarSyncTestSource("Haiity/Services/CalendarSync.swift")

        let cleanup = try XCTUnwrap(source.range(of: "static func removeAllOwnedItems()"))
        let tail = source[cleanup.lowerBound...]
        XCTAssertTrue(tail.contains("habitsCalendarKey"))
        XCTAssertTrue(tail.contains("remindersCalendarKey"))
        XCTAssertTrue(tail.contains("calendarKey"))
        XCTAssertTrue(tail.contains("fallbackCalendarKey"))
    }

    func testCalendarMigrationBlocksRecreationAfterRemovalFailure() throws {
        let source = try calendarSyncTestSource("Haiity/Services/CalendarSync.swift")

        XCTAssertTrue(source.contains("var blockedKeys"))
        XCTAssertTrue(source.contains("var removalFailed"))
        XCTAssertTrue(source.contains("if !removeOwnedEvent("))
        XCTAssertTrue(source.contains("blockedKeys.contains(key)"))
    }

    func testCalendarReconcileUsesStoredIDInventoryWhenDatePredicateOmitsAnEvent() throws {
        let source = try calendarSyncTestSource("Haiity/Services/CalendarSync.swift")

        XCTAssertTrue(source.contains("eventsIncludingStoredMappings(map)"))
        XCTAssertTrue(source.contains("let mappedOwners"))
        XCTAssertTrue(source.contains("mappedOwners[$0]"))
    }

    func testCalendarCleanupUsesStoredIDsWhenOwnershipMetadataIsMissing() throws {
        let source = try calendarSyncTestSource("Haiity/Services/CalendarSync.swift")

        XCTAssertTrue(source.contains("let mappedNativeIDs = Set(storedMap.values)"))
        XCTAssertTrue(source.contains("isMappedCalendarEvent"))
        XCTAssertTrue(source.contains("event.eventIdentifier.map"))
        XCTAssertTrue(source.contains("isMappedCalendarEvent || SyncWatermark.isCalendarOwned"))
    }

    func testCalendarInventoryUsesTenYearWindowsAcrossTheFullCleanupHorizon() throws {
        let source = try calendarSyncTestSource("Haiity/Services/CalendarSync.swift")

        XCTAssertTrue(source.contains("var startYear = -100"))
        XCTAssertTrue(source.contains("while startYear < 100"))
        XCTAssertTrue(source.contains("value: startYear + 10"))
    }

    func testCalendarCleanupRecognizesTheStableHaiityURLWhenNotesAreMissing() {
        XCTAssertTrue(SyncWatermark.isCalendarOwned(notes: nil,
                                                    urlString: "haiity://habits"))
        XCTAssertFalse(SyncWatermark.isCalendarOwned(notes: nil,
                                                     urlString: "https://example.com"))
    }

    func testCalendarCleanupRejectsNativeReminderWatermarks() {
        let note = SyncWatermark.note(for: UUID(), kind: .nativeReminder)
        XCTAssertFalse(SyncWatermark.isCalendarOwned(notes: note, urlString: nil))
    }

    func testInteractionReminderFixtureOptsOutOfNativeSync() throws {
        let content = try calendarSyncTestSource("Haiity/Views/ContentView.swift")
        let fixture = try XCTUnwrap(content.range(of: "var reminder = Habit(name: \"UI test reminder\""))
        let tail = content[fixture.lowerBound...]
        XCTAssertTrue(tail.contains("reminder.calendarSyncEnabled = false"),
                      "the UI-test fixture must never create native Calendar or Reminder entries")
    }

    func testCalendarDisableUsesMarkerInventoryForStaleLinks() throws {
        let source = try calendarSyncTestSource("Haiity/Services/CalendarSync.swift")
        let disable = try XCTUnwrap(source.range(of: "static func disable()"))
        let tail = source[disable.lowerBound...]
        XCTAssertTrue(tail.contains("_ = removeAllOwnedItems()"))
    }

    func testLegacyCalendarCleanupMustSucceedBeforeRecreation() throws {
        let source = try calendarSyncTestSource("Haiity/Services/CalendarSync.swift")

        XCTAssertTrue(source.contains("guard removeLegacyOwnedItems() else"))
        XCTAssertTrue(source.contains("private static func removeLegacyOwnedItems() -> Bool"))
        let cleanup = try XCTUnwrap(source.range(of: "guard removeLegacyOwnedItems() else"))
        let calendarSetup = try XCTUnwrap(source.range(of: "var calendars: [Bool: EKCalendar] = [:]"))
        XCTAssertLessThan(cleanup.lowerBound, calendarSetup.lowerBound)
    }

    func testCalendarCreationTriesAnotherWritableSourceAfterPreferredFailure() throws {
        XCTAssertEqual(CalendarSync.orderedSourceIDs(preferredID: "gmail",
                                                     fallbackIDs: ["local", "gmail"]),
                       ["gmail", "local"])
    }

    func testCalendarSyncHasAnExistingWritableCalendarFallback() throws {
        let source = try calendarSyncTestSource("Haiity/Services/CalendarSync.swift")

        XCTAssertTrue(source.contains("fallbackCalendarKey"))
        XCTAssertTrue(source.contains("store.defaultCalendarForNewEvents"))
        XCTAssertTrue(source.contains("allowsContentModifications"))
        XCTAssertTrue(source.contains("flatMap { $0.allowsContentModifications ? $0 : nil }"),
                      "a read-only default must fall through to another writable calendar")
        XCTAssertTrue(source.contains("defaults.string(forKey: fallbackCalendarKey)"))
    }

    func testMoreScreenExposesTheActualCalendarDestinationPicker() throws {
        let source = try calendarSyncTestSource("Haiity/Views/MoreView.swift")
        XCTAssertTrue(source.contains("calendarDestinationPicker"))
        XCTAssertTrue(source.contains("CalendarSync.writableCalendarOptions"))
        XCTAssertTrue(source.contains("calendar-sync-habits-destination"))
        XCTAssertTrue(source.contains("calendar-sync-reminders-destination"))
    }

    func testMoreScreenExposesIndependentCalendarToggles() throws {
        let source = try calendarSyncTestSource("Haiity/Views/MoreView.swift")
        XCTAssertTrue(source.contains("calendar-sync-habits-toggle"))
        XCTAssertTrue(source.contains("calendar-sync-reminders-toggle"))
        XCTAssertTrue(source.contains("CalendarSync.syncHabits"))
        XCTAssertTrue(source.contains("CalendarSync.syncReminders"))
    }

    func testEveryCalendarEnablePathRequiresPro() throws {
        XCTAssertFalse(CalendarFeatureGate.canEnable(unlocked: false))
        XCTAssertTrue(CalendarFeatureGate.canEnable(unlocked: true))

        let source = try calendarSyncTestSource("Haiity/Views/MoreView.swift")
        XCTAssertTrue(source.contains("guard CalendarFeatureGate.canEnable(unlocked: unlocked)"))
        XCTAssertTrue(source.contains("paywall = .calendar"))
    }

    func testMoreViewReminderToggleUsesItsBinding() throws {
        let source = try calendarSyncTestSource("Haiity/Views/MoreView.swift")
        XCTAssertTrue(source.contains("Toggle(isOn: reminderSyncBinding)"))
    }
}

final class SyncWatermarkTests: XCTestCase {
    func testWatermarkKeepsReadableProductNameAndInvisibleItemMarker() {
        let id = UUID()
        let note = SyncWatermark.note(for: id, kind: .habitCalendar)

        XCTAssertTrue(note.hasPrefix("hAiity"))
        XCTAssertFalse(note.contains(id.uuidString))
        XCTAssertTrue(note.unicodeScalars.contains { $0.value == 0x2063 })
        XCTAssertTrue(note.unicodeScalars.contains { (0xE0000...0xE007F).contains($0.value) })
    }

    func testCopyTextIsStableForAllNativeIntegrations() {
        XCTAssertEqual(SyncWatermark.copyText(for: .habitCalendar), "hAiity")
        XCTAssertEqual(SyncWatermark.copyText(for: .reminderCalendar), "hAiity")
        XCTAssertEqual(SyncWatermark.copyText(for: .nativeReminder), "hAiity")
    }

    func testWatermarkDecodesOwnedItemIdentity() {
        let id = UUID()
        let note = SyncWatermark.note(for: id, kind: .nativeReminder)

        XCTAssertEqual(SyncWatermark.ownership(in: note),
                       SyncWatermark.Ownership(kind: .nativeReminder, id: id))
        XCTAssertEqual(SyncWatermark.ownership(in: "User note\n\(note)"),
                       SyncWatermark.Ownership(kind: .nativeReminder, id: id))
    }

    func testWatermarkRejectsUnrelatedOrMalformedNotes() {
        XCTAssertNil(SyncWatermark.ownership(in: "hAiity"))
        XCTAssertNil(SyncWatermark.ownership(in: "hAiity\u{2063}not-a-tag\u{2063}"))
        XCTAssertNil(SyncWatermark.ownership(in: "Other app\u{2063}marker\u{2063}"))

        let id = UUID()
        let note = SyncWatermark.note(for: id, kind: .nativeReminder)
        let userNoteWithCopiedMarker = note.replacingOccurrences(
            of: "hAiity\n",
            with: "User mentioned hAiity\n")
        XCTAssertNil(SyncWatermark.ownership(in: userNoteWithCopiedMarker),
                     "a copied marker must not make an otherwise unrelated note hAiity-owned")
    }

    func testWatermarkRequiresTheReadablePrefixImmediatelyBeforeInvisiblePayload() {
        let id = UUID()
        let note = SyncWatermark.note(for: id, kind: .nativeReminder)
        let payload = note.replacingOccurrences(of: "hAiity\n", with: "")

        XCTAssertEqual(SyncWatermark.ownership(in: "User note\n\(note)"),
                       SyncWatermark.Ownership(kind: .nativeReminder, id: id))
        XCTAssertNil(SyncWatermark.ownership(in: "User hAiity\n\(payload)"))
        XCTAssertNil(SyncWatermark.ownership(in: "hAiity note\n\(payload)"))
        XCTAssertNil(SyncWatermark.ownership(in: "User note\n hAiity\n\(payload)"))
    }

    func testLegacyKeywordIsRecognizedOnlyAsAStandaloneCleanupNote() {
        XCTAssertTrue(SyncWatermark.containsMarker("hAiity"))
        XCTAssertFalse(SyncWatermark.containsMarker("hAiity - eigener Termin"))
        XCTAssertFalse(SyncWatermark.containsMarker("Ein eigener hAiity Hinweis"))
    }

    func testCanonicalNativeItemSelectionPrefersStoredIDAndReturnsOnlyDuplicates() {
        let selection = SyncWatermark.selectCanonicalItem(
            candidates: [
                (id: "older", sortKey: "2026-08-01"),
                (id: "stored", sortKey: "2026-08-03"),
                (id: "newer", sortKey: "2026-08-05")
            ],
            preferredID: "stored")

        XCTAssertEqual(selection.retainedID, "stored")
        XCTAssertEqual(selection.duplicateIDs, ["older", "newer"])
    }

    func testCanonicalNativeItemSelectionIsDeterministicWithoutStoredID() {
        let selection = SyncWatermark.selectCanonicalItem(
            candidates: [
                (id: "z", sortKey: "001"),
                (id: "a", sortKey: "001"),
                (id: "b", sortKey: "002")
            ],
            preferredID: nil)

        XCTAssertEqual(selection.retainedID, "a")
        XCTAssertEqual(selection.duplicateIDs, ["z", "b"])
    }

    func testCanonicalNativeItemSelectionCollapsesIdenticalOwnedIdentifiers() {
        let selection = SyncWatermark.selectCanonicalItem(
            candidates: [
                (id: "series", sortKey: "001"),
                (id: "series", sortKey: "001"),
                (id: "newer", sortKey: "002")
            ],
            preferredID: nil)

        XCTAssertEqual(selection.retainedID, "series")
        XCTAssertEqual(selection.duplicateIDs, ["newer"])
    }

    func testCanonicalNativeItemSelectionIgnoresStoredIdentifierFromAnotherItem() {
        let selection = SyncWatermark.selectCanonicalItem(
            candidates: [
                (id: "first", sortKey: "001"),
                (id: "second", sortKey: "002")
            ],
            preferredID: "missing")

        XCTAssertEqual(selection.retainedID, "first")
        XCTAssertEqual(selection.duplicateIDs, ["second"])
    }

    func testLegacyCleanupMarkerTrimsWhitespace() {
        XCTAssertTrue(SyncWatermark.containsMarker(" \n hAiity \n "))
    }

    func testCalendarReconciliationRepairsAllOwnedDuplicates() throws {
        let source = try calendarSyncTestSource("Haiity/Services/CalendarSync.swift")

        XCTAssertTrue(source.contains("selectCanonicalItem"))
        XCTAssertTrue(source.contains("SyncWatermark.ownership(in:"))
        XCTAssertTrue(source.contains("duplicateIDs"))
        XCTAssertTrue(source.contains("eventIdentifier"))
    }

    func testCalendarValidationReusesScannedCanonicalSeries() throws {
        let source = try calendarSyncTestSource("Haiity/Services/CalendarSync.swift")

        XCTAssertTrue(source.contains("var validatedEvents"),
                      "validation must carry the fetched canonical event into the save pass")
        XCTAssertTrue(source.contains("validatedKeys.insert(owner.id.uuidString)"),
                      "a scanned owner must be trusted even when EventKit ID lookup is unavailable")
        XCTAssertTrue(source.contains("validatedKeys.contains(key)"),
                      "the save pass must not recreate a validated recurring series")
        XCTAssertFalse(source.contains("!validate || store.event(withIdentifier: map[key]!) != nil"),
                       "recurring events must not be validated through event(withIdentifier:)")
    }

    func testCalendarRemovalPathDoesNotSilentlyDropFailedOwnedSeriesRemovals() throws {
        let source = try calendarSyncTestSource("Haiity/Services/CalendarSync.swift")

        XCTAssertTrue(source.contains("if !removeEvent("),
                      "failed event removal must abort recreation in the same pass")
        XCTAssertFalse(source.contains("try? store.remove(event, span: .futureEvents, commit: true)"),
                       "calendar sync must not silently ignore removal failures")
    }

    func testReinstallDetectionDoesNotTreatFirstInstallAsReinstall() {
        XCTAssertFalse(NativeSyncInstallation.needsCleanup(localID: nil,
                                                            persistentID: nil))
        XCTAssertFalse(NativeSyncInstallation.needsCleanup(localID: "same",
                                                            persistentID: "same"))
        XCTAssertTrue(NativeSyncInstallation.needsCleanup(localID: nil,
                                                           persistentID: "previous"))
        XCTAssertTrue(NativeSyncInstallation.needsCleanup(localID: "old",
                                                           persistentID: "current"))
    }

    func testNativeCleanupResultReportsWhetherBothStoresSucceeded() {
        XCTAssertTrue(NativeSyncCleanup.Result(calendar: true, reminders: true).succeeded)
        XCTAssertFalse(NativeSyncCleanup.Result(calendar: true, reminders: false).succeeded)
        XCTAssertFalse(NativeSyncCleanup.Result(calendar: false, reminders: true).succeeded)
    }

    func testNativeCleanupResultMarksFailedPassesAsRetryable() {
        XCTAssertFalse(NativeSyncCleanup.Result(calendar: true, reminders: true).needsRetry)
        XCTAssertTrue(NativeSyncCleanup.Result(calendar: true, reminders: false).needsRetry)
        XCTAssertTrue(NativeSyncCleanup.Result(calendar: false, reminders: false).needsRetry)
    }

    func testNativeServicesUseTheSharedWatermark() throws {
        let calendar = try calendarSyncTestSource("Haiity/Services/CalendarSync.swift")
        let reminders = try calendarSyncTestSource("Haiity/Services/ReminderSync.swift")

        XCTAssertTrue(calendar.contains("SyncWatermark.note(for:"))
        XCTAssertTrue(reminders.contains("SyncWatermark.note(for:"))
    }

    func testNativeCleanupScansLegacyAndCurrentOwnershipFormats() throws {
        let calendar = try calendarSyncTestSource("Haiity/Services/CalendarSync.swift")
        let reminders = try calendarSyncTestSource("Haiity/Services/ReminderSync.swift")

        XCTAssertTrue(calendar.contains("SyncWatermark.isCalendarOwned"))
        XCTAssertTrue(reminders.contains("SyncWatermark.containsMarker"))
    }
}

/// Die Abbildung Habit -> Kalender-Termin (`CalendarEventPlan`) — pur, ohne
/// EventKit: welche Habits einen Termin bekommen, wann er beginnt, wie er
/// sich wiederholt und wann er endet.
final class CalendarEventPlanTests: XCTestCase {
    /// So, 09.08.2026 als „heute" — dieselbe Fixture-Wochenlage wie überall.
    private let today = "2026-08-09"

    func testNewItemsAreIncludedInCalendarByDefault() {
        XCTAssertTrue(Habit(name: "Lesen").calendarSyncEnabled)
        XCTAssertTrue(Habit(name: "Tabletten", itemType: .reminder).calendarSyncEnabled)
    }

    func testDailyHabitWithTimeBecomesTimedDailyEvent() {
        let habit = Habit(name: "Lesen", emoji: "📚", timeMinutes: 19 * 60,
                          recurrence: .daily)
        let plan = CalendarEventPlan(habit: habit, today: today)
        XCTAssertEqual(plan?.title, "📚 Lesen")
        XCTAssertEqual(plan?.firstDay, today)
        XCTAssertEqual(plan?.minutes, 19 * 60)
        XCTAssertEqual(plan?.frequency, .daily)
        XCTAssertEqual(plan?.interval, 1)
        XCTAssertFalse(plan?.isReminder ?? true)
    }

    func testReminderPlanCarriesReminderWatermarkKind() {
        let plan = CalendarEventPlan(habit: Habit(name: "Tabletten", itemType: .reminder,
                                                   recurrence: .daily), today: today)

        XCTAssertTrue(plan?.isReminder ?? false)
    }

    func testHabitWithoutTimeIsAllDay() {
        let plan = CalendarEventPlan(habit: Habit(name: "Lesen", recurrence: .daily),
                                     today: today)
        XCTAssertNil(plan?.minutes)
    }

    func testPlannedSessionDurationSetsEventLength() {
        var habit = Habit(name: "Sport", timeMinutes: 7 * 60, recurrence: .daily)
        habit.durationMinutes = 45
        XCTAssertEqual(CalendarEventPlan(habit: habit, today: today)?.durationMinutes, 45)
        XCTAssertEqual(CalendarEventPlan(habit: Habit(name: "X", timeMinutes: 60,
                                                      recurrence: .daily),
                                         today: today)?.durationMinutes, 30)
    }

    func testWeekdayHabitStartsOnItsNextAgreedDay() {
        // Dienstage (3); heute ist Sonntag -> erster Termin Di, 11.08.
        let habit = Habit(name: "Yoga", recurrence: .weekdays([3]))
        let plan = CalendarEventPlan(habit: habit, today: today)
        XCTAssertEqual(plan?.firstDay, "2026-08-11")
        XCTAssertEqual(plan?.frequency, .weekly)
        XCTAssertEqual(plan?.weekdays, [3])
    }

    /// Flexible Ziele MIT Verabredung: Wochenmuster an genau diesen Tagen.
    func testFlexibleWithAgreedWeekdaysBecomesWeeklyPattern() {
        let habit = Habit(name: "Schwimmen",
                          recurrence: .times(2, per: .weekly, weekdays: [2, 5]))
        let plan = CalendarEventPlan(habit: habit, today: today)
        XCTAssertEqual(plan?.frequency, .weekly)
        XCTAssertEqual(plan?.weekdays, [2, 5])
        XCTAssertEqual(plan?.firstDay, "2026-08-10")
    }

    /// Flexible Ziele OHNE Verabredung haben keinen Termin, den man
    /// eintragen könnte.
    func testFlexibleWithoutWeekdaysHasNoPlan() {
        let habit = Habit(name: "Irgendwann",
                          recurrence: .times(3, per: .weekly))
        XCTAssertNil(CalendarEventPlan(habit: habit, today: today))
    }

    func testArchivedHabitsHaveNoPlan() {
        var habit = Habit(name: "Alt", recurrence: .daily)
        habit.archivedAt = "2026-08-01"
        XCTAssertNil(CalendarEventPlan(habit: habit, today: today))
    }

    func testMonthlyDayRuleCarriesDayOfMonth() {
        let habit = Habit(name: "Miete",
                          recurrence: .monthly(.dayOfMonth(1)))
        let plan = CalendarEventPlan(habit: habit, today: today)
        XCTAssertEqual(plan?.frequency, .monthly)
        XCTAssertEqual(plan?.daysOfMonth, [1])
        XCTAssertEqual(plan?.firstDay, "2026-09-01")
    }

    func testLastDayOfMonthMapsToMinusOne() {
        let habit = Habit(name: "Rückblick",
                          recurrence: .monthly(.lastDayOfMonth))
        XCTAssertEqual(CalendarEventPlan(habit: habit, today: today)?.daysOfMonth, [-1])
    }

    func testEndDatePassesThrough() {
        let habit = Habit(name: "Kur",
                          recurrence: Recurrence(frequency: .daily,
                                                 end: .on("2026-09-01")))
        XCTAssertEqual(CalendarEventPlan(habit: habit, today: today)?.end, .on("2026-09-01"))
    }

    func testEndTitleIsVisibleInNativeEventTitle() {
        let habit = Habit(name: "Kur",
                          recurrence: Recurrence(frequency: .daily,
                                                 end: .on("2026-09-01"),
                                                 endTitle: "Sommer"))
        XCTAssertEqual(CalendarEventPlan(habit: habit, today: today)?.title, "Kur · Sommer")
    }

    /// Der Fingerabdruck ändert sich mit dem Sichtbaren — und nur damit.
    func testFingerprintTracksVisibleChanges() {
        let a = CalendarEventPlan(habit: Habit(name: "Lesen", timeMinutes: 19 * 60,
                                               recurrence: .daily), today: today)
        let b = CalendarEventPlan(habit: Habit(name: "Lesen", timeMinutes: 19 * 60,
                                               recurrence: .daily), today: today)
        let c = CalendarEventPlan(habit: Habit(name: "Lesen", timeMinutes: 20 * 60,
                                               recurrence: .daily), today: today)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    /// Kalendereinträge sind NUR Bild: erinnern tut hAiity selbst — ein
    /// Termin mit eigenem Wecker wäre der zweite Alarm für denselben Habit.
    func testCalendarEventsCarryNoAlarms() throws {
        let source = try calendarSyncTestSource("Haiity/Services/CalendarSync.swift")
        XCTAssertTrue(source.contains("event.alarms = nil"))
        XCTAssertFalse(source.contains("EKAlarm"), "kein Wecker am Termin")
        XCTAssertFalse(source.contains("addAlarm"), "kein Wecker am Termin")
    }
}

final class CalendarSyncRecurrenceRuleTests: XCTestCase {
    @MainActor
    func testOncePlanProducesNoEventKitRecurrenceRule() throws {
        let habit = Habit(name: "Einmal",
                          recurrence: Recurrence(frequency: .once,
                                                 start: "2026-08-18"))
        let plan = try XCTUnwrap(CalendarEventPlan(habit: habit, today: "2026-08-18"))

        XCTAssertNil(CalendarSync.recurrenceRule(for: plan))
    }

    @MainActor
    func testDailyPlanStillProducesDailyEventKitRecurrenceRule() throws {
        let habit = Habit(name: "Taeglich", recurrence: .daily)
        let plan = try XCTUnwrap(CalendarEventPlan(habit: habit, today: "2026-08-18"))

        let rule = try XCTUnwrap(CalendarSync.recurrenceRule(for: plan))

        XCTAssertEqual(rule.frequency, .daily)
    }

    @MainActor
    func testYearlyMultipleDatesUseExactNativeDayOfYearValues() throws {
        let recurrence = Recurrence(frequency: .yearly,
                                    rule: .multipleMonthDays([
                                        Recurrence.MonthDay(month: 3, day: 12),
                                        Recurrence.MonthDay(month: 10, day: 5)
                                    ]),
                                    start: "2026-03-12")
        let habit = Habit(name: "Mehrere Jahrestage", recurrence: recurrence)
        let plan = try XCTUnwrap(CalendarEventPlan(habit: habit,
                                                   today: "2026-01-01",
                                                   calendar: .current))

        let rule = try XCTUnwrap(CalendarSync.recurrenceRule(for: plan))

        XCTAssertEqual(rule.frequency, EKRecurrenceFrequency.yearly)
        XCTAssertEqual(rule.daysOfTheYear?.map { $0.intValue }, [72, 279])
        XCTAssertNil(rule.daysOfTheMonth)
        XCTAssertNil(rule.monthsOfTheYear)
    }
}

final class CalendarSyncNativeMappingTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = Locale(identifier: "de_DE")
        calendar.firstWeekday = 2
        return calendar
    }()

    @MainActor
    func testOneTimePlanConfiguresSingleNativeEventWithoutRecurrence() throws {
        let habit = Habit(name: "Einmal",
                          timeMinutes: 9 * 60 + 15,
                          recurrence: Recurrence(frequency: .once,
                                                 start: "2026-08-18"))
        let plan = try XCTUnwrap(CalendarEventPlan(habit: habit,
                                                   today: "2026-08-10",
                                                   calendar: calendar))
        let event = EKEvent(eventStore: EKEventStore())

        CalendarSync.configure(event: event, for: plan, calendar: calendar)

        XCTAssertEqual(DayKey.key(for: event.startDate, calendar: calendar), "2026-08-18")
        XCTAssertEqual(calendar.component(.hour, from: event.startDate), 9)
        XCTAssertEqual(calendar.component(.minute, from: event.startDate), 15)
        XCTAssertTrue(event.recurrenceRules?.isEmpty ?? true)
    }

    @MainActor
    func testRecurringPlanKeepsNativeRecurrenceRule() throws {
        let habit = Habit(name: "Taeglich",
                          timeMinutes: 8 * 60,
                          recurrence: .daily)
        let plan = try XCTUnwrap(CalendarEventPlan(habit: habit,
                                                   today: "2026-08-18",
                                                   calendar: calendar))
        let event = EKEvent(eventStore: EKEventStore())

        CalendarSync.configure(event: event, for: plan, calendar: calendar)

        XCTAssertEqual(event.recurrenceRules?.count, 1)
        XCTAssertEqual(event.recurrenceRules?.first?.frequency, .daily)
    }
}
