# Native Entry Categories Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Separate hAiity-created native entries into category-specific Calendar calendars and an app-specific Reminders list while preserving marker-based ownership, migration, cleanup, and duplicate safety.

**Architecture:** Keep EventKit reconciliation in the existing `CalendarSync` and `ReminderSync` types. Calendar destination selection is derived from `CalendarEventPlan.isReminder`; stored Calendar IDs use one key per destination, while the existing per-item IDs, fingerprints, and invisible `SyncWatermark` remain unchanged. Migration is achieved by scanning all native containers, removing or relocating only marked hAiity items, and never deleting native containers automatically.

**Tech Stack:** Swift 5.9, SwiftUI, EventKit, App Group `UserDefaults`, XCTest, XcodeGen, Xcode Cloud.

## Global Constraints

- Preserve all existing uncommitted work; do not reset, clean, or overwrite unrelated files.
- Test runtime behavior only on `詹。手机air` (`00008150-000120AC0287801C`); do not create or use simulator/device-hub coverage for this milestone.
- Use `hAiity Habits` for Calendar habit events, `hAiity Reminders` for Calendar reminder events, and `hAiity Reminders` for app reminder items in Apple Reminders.
- Keep `SyncWatermark` as the ownership source of truth; invisible item IDs and visible habit/reminder titles remain unchanged.
- Treat only current invisible markers and the exact legacy `hAiity` note as owned; never delete content based on a partial text match.
- Never delete a Calendar calendar or Reminders list automatically. Remove only marked hAiity entries and let users delete empty legacy containers manually.
- A failed permission, container creation, save, or removal operation must not erase local maps or recreate a duplicate in the same pass.
- Avoid adding a Manager, Service, Factory, Protocol, or other new abstraction layer; modify the existing sync and cleanup types directly.

## File Map

- `Haiity/Services/CalendarSync.swift`: category titles and keys, per-category Calendar lookup/creation, category-aware reconciliation, legacy migration, and Calendar cleanup.
- `Haiity/Services/ReminderSync.swift`: dedicated Apple Reminders list title/version handling, all-container migration, reconciliation, and cleanup.
- `Haiity/Services/NativeSyncInstallation.swift`: existing coordination boundary for the two EventKit stores; keep its public cleanup call stable.
- `Haiity/Views/MoreView.swift`: destination hints beside the native sync controls and category-aware cleanup feedback.
- `Haiity/Views/ContentView.swift`: Home Screen cleanup feedback; preserve the existing recovery ordering.
- `Haiity/Models/Diagnostics.swift`: report the actual new Calendar destination title without claiming a missing or legacy calendar exists.
- `HaiityTests/CalendarSyncTests.swift`: destination routing, key isolation, migration, and Calendar cleanup contracts.
- `HaiityTests/ReminderSyncTests.swift`: dedicated list behavior, migration, cleanup, and UI contract tests.
- `HaiityTests/DiagnosticsTests.swift`: diagnostic expectations for the two new Calendar titles.

---

### Task 1: Add Stable Category Contracts

**Files:**
- Modify: `Haiity/Services/CalendarSync.swift`
- Modify: `Haiity/Services/ReminderSync.swift`
- Test: `HaiityTests/CalendarSyncTests.swift`
- Test: `HaiityTests/ReminderSyncTests.swift`

**Interfaces:**
- Produce `CalendarSync.destinationTitle(isReminder:) -> String`.
- Produce `CalendarSyncPreferences.calendarID(isReminder:in:) -> String?` and `setCalendarID(_:isReminder:in:)` for injected-defaults tests.
- Produce `CalendarSync.habitsCalendarKey`, `CalendarSync.remindersCalendarKey`, `CalendarSync.habitsCalendarTitle`, `CalendarSync.remindersCalendarTitle`, and retain `CalendarSync.calendarKey` as the legacy key.
- Produce `ReminderSync.listTitle == "hAiity Reminders"`, `ReminderSync.legacyListTitle == "hAiity"`, and `ReminderSync.containerVersionKey`.

- [ ] **Step 1: Write failing contract tests.** Add these tests to the existing test classes:

```swift
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

func testNativeReminderUsesTheDedicatedCategoryName() {
    XCTAssertEqual(ReminderSync.listTitle, "hAiity Reminders")
    XCTAssertEqual(ReminderSync.legacyListTitle, "hAiity")
}
```

- [ ] **Step 2: Run the focused tests and verify the new contracts fail.**

Run:

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/CalendarSyncTests -only-testing:HaiityTests/ReminderSyncTests
```

Expected: the build fails because the new destination constants and preference helpers do not exist, and `ReminderSync.listTitle` still equals `hAiity`.

- [ ] **Step 3: Add only the constants and injected-defaults helpers.** In `CalendarSyncPreferences`, add the two category keys and read/write helpers. In `CalendarSync`, expose the two category keys and implement:

```swift
static let habitsCalendarTitle = "hAiity Habits"
static let remindersCalendarTitle = "hAiity Reminders"

static func destinationTitle(isReminder: Bool) -> String {
    isReminder ? remindersCalendarTitle : habitsCalendarTitle
}
```

Keep `calendarKey = "calendarSyncCalendar"` unchanged for legacy cleanup and diagnostics migration. In `ReminderSync`, change `listTitle` to `"hAiity Reminders"`, add `legacyListTitle = "hAiity"`, and add `containerVersionKey = "nativeReminderSyncContainerVersion"`.

- [ ] **Step 4: Re-run the focused tests and verify they pass.**

Expected: all existing Calendar/Reminder tests and the new contract tests pass.

- [ ] **Step 5: Commit the contract slice.**

```bash
git add Haiity/Services/CalendarSync.swift Haiity/Services/ReminderSync.swift HaiityTests/CalendarSyncTests.swift HaiityTests/ReminderSyncTests.swift
git commit -m "Add native entry category contracts"
```

### Task 2: Route and Migrate Calendar Events

**Files:**
- Modify: `Haiity/Services/CalendarSync.swift`
- Test: `HaiityTests/CalendarSyncTests.swift`

**Interfaces:**
- Consume `CalendarSync.destinationTitle(isReminder:)` and the per-category ID helpers from Task 1.
- Keep `CalendarSync.reconcile(habits:defaultTimeZoneIdentifier:validate:)` unchanged for all callers.
- Produce `CalendarSync.activeCalendarTitles -> [String]` for settings/diagnostics display.

- [ ] **Step 1: Write failing routing and migration contract tests.** Add the following tests:

```swift
func testCalendarPlansRouteByItemType() {
    let habit = CalendarEventPlan(habit: Habit(name: "Lesen"), today: "2026-08-09")
    let reminder = CalendarEventPlan(habit: Habit(name: "Tabletten", itemType: .reminder),
                                     today: "2026-08-09")

    XCTAssertEqual(CalendarSync.destinationTitle(isReminder: habit?.isReminder ?? true), "hAiity Habits")
    XCTAssertEqual(CalendarSync.destinationTitle(isReminder: reminder?.isReminder ?? false), "hAiity Reminders")
}

func testCalendarSyncKeepsLegacyKeySeparateFromCategoryKeys() throws {
    let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Haiity/Services/CalendarSync.swift"))

    XCTAssertTrue(source.contains("static let calendarKey = \"calendarSyncCalendar\""))
    XCTAssertTrue(source.contains("static let habitsCalendarKey"))
    XCTAssertTrue(source.contains("static let remindersCalendarKey"))
    XCTAssertTrue(source.contains("func ensureCalendar(isReminder:"))
    XCTAssertTrue(source.contains("ownedEvents()"))
}

func testCalendarCleanupClearsBothCategoryIDsAndLegacyID() throws {
    let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Haiity/Services/CalendarSync.swift"))

    let cleanup = try XCTUnwrap(source.range(of: "static func removeAllOwnedItems()"))
    let tail = source[cleanup.lowerBound...]
    XCTAssertTrue(tail.contains("habitsCalendarKey"))
    XCTAssertTrue(tail.contains("remindersCalendarKey"))
    XCTAssertTrue(tail.contains("calendarKey"))
}
```

- [ ] **Step 2: Run the new tests and verify the routing/migration assertions fail.**

Run:

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/CalendarSyncTests
```

Expected: the source-contract tests fail because reconciliation still calls one `ensureCalendar()` and cleanup clears only `calendarKey`.

- [ ] **Step 3: Replace the single Calendar destination lookup.** Implement `ensureCalendar(isReminder:)` using the category key and `destinationTitle(isReminder:)`:

```swift
private static func ensureCalendar(isReminder: Bool) -> EKCalendar? {
    if let id = CalendarSyncPreferences.calendarID(isReminder: isReminder, in: defaults),
       let existing = store.calendar(withIdentifier: id) {
        return existing
    }
    let title = destinationTitle(isReminder: isReminder)
    if let existing = store.calendars(for: .event)
        .first(where: { $0.title == title && $0.allowsContentModifications }) {
        CalendarSyncPreferences.setCalendarID(existing.calendarIdentifier,
                                               isReminder: isReminder,
                                               in: defaults)
        return existing
    }
    let calendar = EKCalendar(for: .event, eventStore: store)
    calendar.title = title
    calendar.source = store.defaultCalendarForNewEvents?.source
        ?? store.sources.first { $0.sourceType == .calDAV }
        ?? store.sources.first { $0.sourceType == .local }
    guard calendar.source != nil else { return nil }
    do {
        try store.saveCalendar(calendar, commit: true)
        CalendarSyncPreferences.setCalendarID(calendar.calendarIdentifier,
                                               isReminder: isReminder,
                                               in: defaults)
        return calendar
    } catch {
        trace("calsync: save category calendar FAILED '\(title)': \(error)")
        return nil
    }
}
```

Do not fall back to the user’s default calendar. A category without a writable dedicated Calendar must remain unsynchronized rather than violating the category guarantee.

- [ ] **Step 4: Make reconciliation category-aware.** Build the active plans as today, then ensure only the categories represented by active plans. For each owned `SyncWatermark.Ownership`, choose its target from `owner.kind == .reminderCalendar`, compare candidates across every calendar returned by `ownedEvents()`, retain one canonical event only when its target category calendar exists, remove old shared-calendar events and duplicates, and create the replacement in the target calendar after successful removal. If a target category calendar cannot be created, leave that category’s stored map/fingerprint entries intact for retry and continue processing the other category.

Keep `removeLegacyOwnedItems()` before the ownership inventory so the exact bare `hAiity` note is removed during the first post-update pass. The current invisible markers are migrated automatically because `ownedEvents()` already scans every Calendar and the target filter now requires the new category calendar.

- [ ] **Step 5: Update cleanup and active-title reporting.** Make `removeAllOwnedItems()` clear `habitsCalendarKey`, `remindersCalendarKey`, and the legacy `calendarKey` only after every marked removal succeeds. Add:

```swift
static var activeCalendarTitles: [String] {
    [false, true].compactMap { isReminder in
        guard let id = CalendarSyncPreferences.calendarID(isReminder: isReminder, in: defaults),
              let calendar = store.calendar(withIdentifier: id) else { return nil }
        return calendar.title
    }
}
```

Keep `activeCalendarTitle` as a compatibility accessor returning the first actual active category title so existing diagnostics callers do not report a title that was never created.

- [ ] **Step 6: Run the Calendar test slice and verify it passes.**

Run:

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/CalendarSyncTests
```

Expected: all Calendar plan, duplicate, migration, and cleanup contract tests pass.

- [ ] **Step 7: Commit the Calendar slice.**

```bash
git add Haiity/Services/CalendarSync.swift HaiityTests/CalendarSyncTests.swift
git commit -m "Route Calendar entries by category"
```

### Task 3: Migrate Apple Reminders Into the Dedicated List

**Files:**
- Modify: `Haiity/Services/ReminderSync.swift`
- Test: `HaiityTests/ReminderSyncTests.swift`

**Interfaces:**
- Consume `ReminderSync.listTitle`, `legacyListTitle`, and `containerVersionKey` from Task 1.
- Keep `ReminderSync.reconcile(habits:defaultTimeZoneIdentifier:validate:) async` unchanged for all callers.
- Keep `ReminderSync.removeAllOwnedItems() async -> Bool` unchanged for `NativeSyncCleanup`.

- [ ] **Step 1: Write failing dedicated-list tests.** Add:

```swift
func testReminderListContractUsesTheDedicatedTitle() throws {
    let source = try source("Haiity/Services/ReminderSync.swift")
    XCTAssertTrue(source.contains("static let listTitle = \"hAiity Reminders\""))
    XCTAssertTrue(source.contains("static let legacyListTitle = \"hAiity\""))
    XCTAssertTrue(source.contains("containerVersionKey"))
}

func testReminderMigrationDoesNotReuseTheLegacyListOnTheFirstNewPass() throws {
    let source = try source("Haiity/Services/ReminderSync.swift")
    XCTAssertTrue(source.contains("legacyListTitle"))
    XCTAssertTrue(source.contains("containerVersionKey"))
    XCTAssertTrue(source.contains("fetchAllReminders()"))
    XCTAssertTrue(source.contains("reminder.calendar?.calendarIdentifier == list.calendarIdentifier"))
}

func testReminderCleanupStillScansEveryListAndClearsTheContainerState() throws {
    let source = try source("Haiity/Services/ReminderSync.swift")
    let cleanup = try XCTUnwrap(source.range(of: "static func removeAllOwnedItems()"))
    let tail = source[cleanup.lowerBound...]
    XCTAssertTrue(tail.contains("fetchAllReminders()"))
    XCTAssertTrue(tail.contains("containerVersionKey"))
    XCTAssertTrue(tail.contains("listKey"))
}
```

- [ ] **Step 2: Run the Reminder test slice and verify the new list tests fail.**

Run:

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/ReminderSyncTests
```

Expected: the source-contract tests fail because the list resolver still accepts the stored legacy `hAiity` list as the destination.

- [ ] **Step 3: Add first-pass container migration in `ensureList()`.** Use the existing stored list only when the stored container version is current. On an upgrade with no current version, resolve an exact writable `hAiity Reminders` list or create it; never use a stored list whose title is the legacy `hAiity` title as the new destination. After resolving or successfully creating the new list, persist `containerVersionKey = 2` and the new list ID. If resolution or creation fails, do not persist the version.

Keep the existing `ReminderListResolver` behavior for current renamed lists after version 2: a stored writable ID remains authoritative even when the user renamed that list. This preserves user renames while ensuring the old shared list is not reused during migration.

- [ ] **Step 4: Preserve all-list ownership scanning and recreate in the new list.** Leave `fetchAllReminders()` as the migration inventory. During validation, group every current marked `.nativeReminder` by owner regardless of list, discard exact legacy bare `hAiity` notes, retain a canonical item only in the new target list, remove old-list duplicates, and save the replacement to `hAiity Reminders`. Keep unrelated lists and reminders untouched. If a removal or save fails, preserve links/fingerprints for the retry path exactly as the current duplicate-safe flow does.

- [ ] **Step 5: Keep cleanup retry-safe.** Make `removeAllOwnedItems()` clear the list ID, links, fingerprints, and container version only after every marked reminder removal succeeds. It must continue fetching all reminder lists, not only `hAiity Reminders`, so reinstall recovery removes entries left in the old shared list or a user-renamed list.

- [ ] **Step 6: Run the Reminder test slice and verify it passes.**

Run:

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/ReminderSyncTests
```

Expected: all plan, permission, duplicate, migration, cleanup, and UI contract tests pass.

- [ ] **Step 7: Commit the Apple Reminders slice.**

```bash
git add Haiity/Services/ReminderSync.swift HaiityTests/ReminderSyncTests.swift
git commit -m "Move native reminders into a dedicated list"
```

### Task 4: Surface Category Setup and Cleanup Safely

**Files:**
- Modify: `Haiity/Views/MoreView.swift`
- Modify: `Haiity/Views/ContentView.swift`
- Modify: `Haiity/Models/Diagnostics.swift`
- Test: `HaiityTests/ReminderSyncTests.swift`
- Test: `HaiityTests/DiagnosticsTests.swift`

**Interfaces:**
- Consume `CalendarSync.activeCalendarTitles` and the stable destination titles from Tasks 1 and 2.
- Keep `NativeSyncCleanup.run() async -> NativeSyncCleanup.Result` and both existing cleanup call sites unchanged.
- Produce UI text that names each destination without changing the shared visible watermark copy text.

- [ ] **Step 1: Write failing UI and diagnostics contract tests.** Add assertions that the settings and Home Screen cleanup feedback mention the separate destinations:

```swift
func testNativeSyncSettingsNamesBothCalendarDestinations() throws {
    let more = try source("Haiity/Views/MoreView.swift")
    XCTAssertTrue(more.contains("hAiity Habits"))
    XCTAssertTrue(more.contains("hAiity Reminders"))
    XCTAssertTrue(more.contains("cleanup-native-entries"))
}

func testNativeCleanupFeedbackNamesEachNativeDestination() throws {
    let content = try source("Haiity/Views/ContentView.swift")
    let more = try source("Haiity/Views/MoreView.swift")
    for source in [content, more] {
        XCTAssertTrue(source.contains("hAiity Habits"))
        XCTAssertTrue(source.contains("hAiity Reminders"))
    }
}

func testDiagnosticsRecognizesEitherNewCalendarTitle() throws {
    let source = try source("Haiity/Models/Diagnostics.swift")
    XCTAssertTrue(source.contains("CalendarSync.activeCalendarTitle"))
    XCTAssertTrue(source.contains("CalendarSync.habitsCalendarTitle"))
    XCTAssertTrue(source.contains("CalendarSync.remindersCalendarTitle"))
}
```

- [ ] **Step 2: Run the affected tests and verify the category UI assertions fail.**

Run:

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/ReminderSyncTests -only-testing:HaiityTests/DiagnosticsTests
```

Expected: the new source-contract tests fail because the UI still presents one generic Calendar destination and generic cleanup success text.

- [ ] **Step 3: Add compact destination hints beside the three native sync toggles.** Keep the existing toggle labels and watermark row. Add a secondary caption for each relevant control:

```swift
Text(String(localized: "Ziel: hAiity Habits"))
    .font(.caption)
    .foregroundStyle(.secondary)
```

Use `Ziel: hAiity Reminders` for the Calendar reminder toggle and the native Apple Reminders toggle. Do not add a second per-item watermark row or change the copied marker.

- [ ] **Step 4: Make cleanup feedback category-aware without changing the cleanup coordinator.** Keep `NativeSyncCleanup.Result` booleans and retry semantics intact. In both `MoreView.nativeCleanupMessage(for:)` and `ContentView.nativeCleanupMessage(for:)`, include the successful destinations in the success text:

```swift
var destinations: [String] = []
if result.calendar { destinations.append("hAiity Habits / hAiity Reminders") }
if result.reminders { destinations.append("hAiity Reminders") }
return String(localized: "Native Einträge bereinigt und neu synchronisiert: \(destinations.joined(separator: ", ")).")
```

Keep the existing partial-failure messages and retry button. A failed store must not trigger reconciliation for that store, preserving the current recovery ordering in `ContentView` and `MoreView`.

- [ ] **Step 5: Update diagnostics without exposing user data.** Keep `DiagnosticsFacts.calendarTitle` as the observed title of one actual category calendar for compatibility. Update `DiagnosticsReport.calendarTitleToken(_:)` to treat `CalendarSync.habitsCalendarTitle` and `CalendarSync.remindersCalendarTitle` as stable hAiity titles, and update the comments/source tests that currently assume only `CalendarSync.calendarTitle == "hAiity"`. Do not include habit names, native IDs, URLs, or full user-created calendar titles in diagnostics.

- [ ] **Step 6: Run the affected test slice and verify it passes.**

Run:

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/ReminderSyncTests -only-testing:HaiityTests/DiagnosticsTests
```

Expected: native sync UI, cleanup retry, marker, and diagnostics tests pass.

- [ ] **Step 7: Commit the setup/cleanup slice.**

```bash
git add Haiity/Views/MoreView.swift Haiity/Views/ContentView.swift Haiity/Models/Diagnostics.swift HaiityTests/ReminderSyncTests.swift HaiityTests/DiagnosticsTests.swift
git commit -m "Expose native entry categories in setup and cleanup"
```

### Task 5: Run End-to-End Recovery Verification

**Files:**
- Test: `HaiityTests/CalendarSyncTests.swift`
- Test: `HaiityTests/ReminderSyncTests.swift`
- Test: `HaiityTests/DiagnosticsTests.swift`

**Deliverable:** The category migration is proven against the existing duplicate-safe and reinstall-safe flows without using additional devices.

- [ ] **Step 1: Run the complete focused native-sync suite.**

Run:

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/CalendarSyncTests -only-testing:HaiityTests/ReminderSyncTests -only-testing:HaiityTests/DiagnosticsTests
```

Expected: all selected tests pass on the approved iOS 27 device.

- [ ] **Step 2: Verify the physical-device migration path.** On `00008150-000120AC0287801C` only:

1. Enable habit and reminder Calendar sync and native Reminders sync.
2. Confirm `hAiity Habits`, `hAiity Reminders`, and the `hAiity Reminders` list appear.
3. Confirm a habit event is in `hAiity Habits`, a reminder event is in the Calendar `hAiity Reminders`, and the app reminder is in the Apple Reminders `hAiity Reminders` list.
4. Run cleanup once and confirm the app reports the destinations separately.
5. Run setup/reconciliation twice and confirm no duplicate native entries appear.
6. Delete only the Calendar `hAiity Reminders` container, run reconciliation, and confirm only that category is recreated.
7. Confirm unrelated Calendar events, calendars, reminders, and lists remain unchanged.

- [ ] **Step 3: Verify reinstall recovery and failure ordering.** With the same device, reinstall the app or clear only the app-local native map through the existing recovery path, then launch once. Confirm marked entries from the old shared `hAiity` container are removed or recreated in the correct category, and a permission-denied or failed-save pass leaves retry state rather than creating duplicates.

- [ ] **Step 4: Run repository hygiene checks.**

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; only the intentional native-category commits and the pre-existing unrelated dirty files are present.

- [ ] **Step 5: Final acceptance review.** Confirm all of the following before declaring the implementation complete:

- Habit Calendar entries use `hAiity Habits`.
- Reminder Calendar entries use `hAiity Reminders`.
- App reminders use the Apple Reminders list `hAiity Reminders`.
- Existing current and legacy marked entries migrate from the old shared containers.
- Missing category containers are recreated independently.
- Cleanup scans all native containers and preserves unrelated content.
- Existing duplicate, retry, reinstall, and Home Screen cleanup flows remain intact.
- No device hub or additional physical device was used.

## Deliberate Non-Goals

- Do not add visible `[Habit]` or `[Reminder]` prefixes to native item titles.
- Do not add a new native category selector inside every habit/reminder editor.
- Do not automatically delete the old shared Calendar calendar or Reminders list.
- Do not change the invisible watermark format, app URL, recurrence rules, or per-item notification behavior.
- Do not upload a TestFlight build as part of this native categorization plan unless a separate release request is made.

## Self-Review

- The plan covers stable names, per-category Calendar IDs, old shared-container migration, dedicated Reminders-list migration, cleanup/setup UI, diagnostics, retries, duplicates, reinstall recovery, and the approved device constraint.
- Every implementation task names its files, interfaces, failing tests, test command, expected result, and commit boundary.
- No new service or manager layer is introduced.
- No step depends on deleting a user-owned native container.
