# Graph Widget, GitHub Refresh, and Apple Reminders Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the pure graph widget selectable and colorable with built-in or custom palettes, give GitHub refresh a visible animated result, and synchronize only hAiity reminders with Apple Reminders in both directions.

**Architecture:** Keep widget configuration and palette resolution in the existing AppIntent/widget data path. Keep GitHub connection phase separate from refresh feedback. Add a dedicated `ReminderSync` EventKit service with its own permission, hAiity-owned list, ID links, fingerprints, and change observer; reuse the existing `CalendarEventPlan` recurrence shape without reusing calendar-event storage.

**Tech Stack:** Swift 5.9, SwiftUI, WidgetKit, AppIntents, EventKit, XCTest, XcodeGen, iOS 17 minimum.

## Global Constraints

- Existing `HabitData` and `PaletteRef` formats remain backward compatible.
- Native Reminders owns only a dedicated `hAiity` list and never imports or edits unrelated reminders.
- The existing Apple Calendar event mirror remains unchanged in behavior.
- Existing Pro gating applies to enabling native calendar/reminder integrations; disabling stays free.
- GitHub failures preserve a valid cached snapshot.
- A missing native reminder ID never deletes hAiity data.
- Use the existing `tools/release.sh` test floor of at least 1,091 tests; current baseline is 1,125.
- Preserve the dirty worktree; stage only files belonging to the current task when committing.

## File Map

- Modify `Haiity/Intents/SelectGraphIntent.swift`: source, dependent habit, and palette parameters.
- Create `Haiity/Intents/GraphPaletteEntity.swift`: AppEntity and shared App Group query for built-in/custom palettes.
- Modify `HaiityWidget/WidgetLogic.swift`, `HaiityWidget/HaiityWidget.swift`, and `HaiityWidget/GraphWidgetView.swift`: carry and resolve widget configuration.
- Modify `project.yml`: include the shared palette entity in the widget target and add the Reminders usage description.
- Modify `Haiity/Views/GitHubContributionGraph.swift`: render a supplied `PaletteStyle`.
- Modify `Haiity/Models/GitHubContributionStore.swift` and `Haiity/Views/GitHubSettingsView.swift`: refresh state and animated response.
- Create `Haiity/Services/ReminderSync.swift`: pure plans, preferences, EventKit list/reconcile, completion bridge, and change observer.
- Modify `Haiity/Services/CalendarSync.swift`: expose its recurrence conversion to the reminder service.
- Modify `Haiity/Views/MoreView.swift`, `Haiity/Views/ContentView.swift`, `Haiity/Localizable.xcstrings`, and `project.yml`: UI, lifecycle, strings, and permission metadata.
- Extend `HaiityTests/GitHubWidgetTests.swift`, `HaiityTests/GitHubContributionStoreTests.swift`, `HaiityTests/GitHubCardContractTests.swift`, and `HaiityTests/ProGateTests.swift`; create `HaiityTests/ReminderSyncTests.swift`.

---

### Task 1: Add the dynamic graph-palette AppEntity

**Files:**
- Create: `Haiity/Intents/GraphPaletteEntity.swift`
- Test: `HaiityTests/GitHubWidgetTests.swift`

**Interfaces:** `GraphPaletteEntity` has `id: String`, `name: String`, and a computed `paletteRef: PaletteRef`. Its `id` is exactly `PaletteRef.rawValue`. `GraphPaletteEntityQuery` has an injectable `dataURL` defaulting to `SharedStorage.dataURL()`.

- [ ] **Step 1: Write the failing tests**

```swift
func testGraphPaletteQueryIncludesBuiltInsAndCustomPalettes() async throws {
    let custom = CustomPalette(name: "Petrol", base: 0x0F766E)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("graph-palettes-\(UUID().uuidString).json")
    let data = HabitData(version: HabitData.currentVersion,
                         updatedAt: 1,
                         summaryMinutes: nil,
                         habits: [],
                         customPalettes: [custom])
    try JSONEncoder().encode(data).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let items = try await GraphPaletteEntityQuery(dataURL: url).suggestedEntities()

    XCTAssertEqual(items.count, GraphPalette.allCases.count + 1)
    XCTAssertTrue(items.contains { $0.id == PaletteRef.custom(custom.id).rawValue })
    XCTAssertTrue(items.contains { $0.id == GraphPalette.green.rawValue })
}

func testDeletedCustomPaletteFallsBackThroughPaletteRef() {
    let id = UUID()
    let entity = GraphPaletteEntity(ref: .custom(id), name: "Petrol")

    XCTAssertEqual(entity.paletteRef, .custom(id))
    XCTAssertNil(entity.paletteRef.style(customs: []))
}
```

- [ ] **Step 2: Run the focused test and verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=haiity-v6,OS=26.4' -only-testing:HaiityTests/GitHubWidgetTests -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
```

Expected: compile failure because the entity/query do not exist.

- [ ] **Step 3: Implement the minimal entity/query**

Return `GraphPalette.allCases` in declaration order followed by `HabitData.customPalettes`. Decode IDs through `PaletteRef(rawValue:)`; invalid IDs return no entity. Use `DisplayRepresentation` with the existing localized built-in display name or the custom palette’s `displayName`. Do not add a second palette model.

```swift
struct GraphPaletteEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Farbe")
    static let defaultQuery = GraphPaletteEntityQuery()
    let id: String
    let name: String
    var paletteRef: PaletteRef { PaletteRef(rawValue: id) ?? .default }
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: .init(stringLiteral: name))
    }
    init(ref: PaletteRef, name: String) {
        id = ref.rawValue
        self.name = name
    }
}

struct GraphPaletteEntityQuery: EntityQuery {
    let dataURL: URL
    init(dataURL: URL = SharedStorage.dataURL()) { self.dataURL = dataURL }

    private func all() -> [GraphPaletteEntity] {
        let data = HabitStore.read(dataURL) ?? .empty
        let builtIns = GraphPalette.allCases.map {
            GraphPaletteEntity(ref: .builtin($0), name: $0.displayName)
        }
        let custom = data.customPalettes.map {
            GraphPaletteEntity(ref: .custom($0.id), name: $0.displayName)
        }
        return builtIns + custom
    }

    func entities(for identifiers: [String]) async throws -> [GraphPaletteEntity] {
        all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [GraphPaletteEntity] { all() }
    func defaultResult() async -> GraphPaletteEntity? {
        all().first { $0.paletteRef == .default }
    }
}
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=haiity-v6,OS=26.4' -only-testing:HaiityTests/GitHubWidgetTests -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
```

Expected: all `GitHubWidgetTests` pass.

- [ ] **Step 5: Commit the isolated task**

```bash
git add Haiity/Intents/GraphPaletteEntity.swift HaiityTests/GitHubWidgetTests.swift
git commit -m "feat: expose custom graph palettes to widget settings"
```

### Task 2: Propagate graph source and palette into rendering

**Files:**
- Modify: `Haiity/Intents/SelectGraphIntent.swift`
- Modify: `HaiityWidget/WidgetLogic.swift`
- Modify: `HaiityWidget/HaiityWidget.swift`
- Modify: `HaiityWidget/GraphWidgetView.swift`
- Modify: `Haiity/Views/GitHubContributionGraph.swift`
- Modify: `project.yml`
- Test: `HaiityTests/GitHubWidgetTests.swift`

**Interfaces:** Add `selectedPalette: PaletteRef?` and `resolvedGraphPalette: PaletteStyle` to `HaiityEntry`. Add optional `palette: PaletteRef? = nil` to `WidgetData.entry` and `WidgetData.timeline`. `GraphWidgetView` passes its resolved style to both habit and GitHub graph renderers.

- [ ] **Step 1: Write the failing tests**

```swift
func testGitHubEntryCarriesCustomPaletteWithoutResolvingAHabit() {
    let custom = CustomPalette(name: "Petrol", base: 0x0F766E)
    let habit = Habit(name: "Laufen")
    let entry = HaiityEntry(date: .now,
                            habits: [habit],
                            palettes: PaletteBook(global: .default, customs: [custom]),
                            selected: habit.id,
                            graphSource: .github,
                            selectedPalette: .custom(custom.id),
                            githubSnapshot: nil)
    XCTAssertNil(entry.habit)
    XCTAssertEqual(entry.resolvedGraphPalette, custom.style)
}

func testMissingSelectedPaletteFallsBackToGlobalPalette() {
    let entry = HaiityEntry(date: .now,
                            habits: [],
                            palettes: PaletteBook(global: .blue),
                            graphSource: .github,
                            selectedPalette: .custom(UUID()))
    XCTAssertEqual(entry.resolvedGraphPalette, GraphPalette.blue.style)
}
```

Also add source assertions for `@IntentParameterDependency`, the `Farbe` parameter, and removal of `PaletteStyle.default` from the GitHub cell shading path.

- [ ] **Step 2: Run focused tests and verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=haiity-v6,OS=26.4' -only-testing:HaiityTests/GitHubWidgetTests -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
```

Expected: missing entry field/property and source-contract failures.

- [ ] **Step 3: Implement the configuration and renderer path**

Use these parameter wrappers in `SelectGraphIntent`:

```swift
@Parameter(title: "Quelle", default: .habit)
var source: GraphWidgetSource

@Parameter(title: "Farbe", default: nil)
var palette: GraphPaletteEntity?

@Parameter(title: "Habit", default: nil)
@IntentParameterDependency<SelectGraphIntent>(\.$source)
var habit: HabitEntity?
```

The graph provider passes `configuration.palette?.paletteRef`; `WidgetData.entry` stores it; `HaiityEntry.resolvedGraphPalette` first resolves the selected palette, then the existing habit/global/default chain. Add `Haiity/Intents/GraphPaletteEntity.swift` to the explicit `HaiityWidget` source list in `project.yml`, because the extension does not compile every app source. `GitHubContributionGraph` accepts `var palette: PaletteStyle = .default` and uses that value in `Theme.level` instead of `PaletteStyle.default`.

- [ ] **Step 4: Run tests and compile the widget**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=haiity-v6,OS=26.4' -only-testing:HaiityTests/GitHubWidgetTests -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=haiity-v6,OS=26.4' -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
```

Expected: focused tests pass and both app/widget targets compile.

- [ ] **Step 5: Commit the widget path**

```bash
git add Haiity/Intents/SelectGraphIntent.swift HaiityWidget/WidgetLogic.swift HaiityWidget/HaiityWidget.swift HaiityWidget/GraphWidgetView.swift Haiity/Views/GitHubContributionGraph.swift project.yml HaiityTests/GitHubWidgetTests.swift
git commit -m "fix: expose graph source and palette widget settings"
```

### Task 3: Add observable GitHub refresh feedback

**Files:**
- Modify: `Haiity/Models/GitHubContributionStore.swift`
- Modify: `Haiity/Views/GitHubSettingsView.swift`
- Modify: `Haiity/Localizable.xcstrings`
- Test: `HaiityTests/GitHubContributionStoreTests.swift`, `HaiityTests/GitHubCardContractTests.swift`

**Interfaces:** Add `GitHubRefreshFeedback: Equatable` with `.none`, `.success`, `.failure(String)`; expose `isRefreshing`, `refreshFeedback`, and `refreshAnimationToken` from the store. Preserve the existing task-joining and cache semantics.

- [ ] **Step 1: Write the failing tests**

```swift
@MainActor
func testForcedRefreshPublishesSuccessAndClearsLoading() async throws {
    try write(sample(fetchedAt: now.addingTimeInterval(-7200)))
    let fetcher = FakeGitHubContributions(result: .success(sample(fetchedAt: now)))
    let store = GitHubContributionStore(vault: MemoryGitHubCredentialVault(token: "gho_cached"),
                                         contributions: fetcher,
                                         cacheURL: cacheURL)
    await store.boot(now: now)
    await store.refresh(now: now, forced: true)
    XCTAssertFalse(store.isRefreshing)
    XCTAssertEqual(store.refreshFeedback, .success)
}

@MainActor
func testRefreshFailureKeepsCachedSnapshotAndPublishesFailure() async throws {
    let cached = sample(fetchedAt: now.addingTimeInterval(-7200))
    try write(cached)
    let fetcher = FakeGitHubContributions(result: .failure(URLError(.notConnectedToInternet)))
    let store = GitHubContributionStore(vault: MemoryGitHubCredentialVault(token: "gho_cached"),
                                         contributions: fetcher,
                                         cacheURL: cacheURL)
    await store.boot(now: now)
    await store.refresh(now: now, forced: true)
    XCTAssertEqual(store.snapshot, cached)
    if case .failure = store.refreshFeedback {} else { XCTFail("expected failure") }
}
```

- [ ] **Step 2: Run focused tests and verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=haiity-v6,OS=26.4' -only-testing:HaiityTests/GitHubContributionStoreTests -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
```

Expected: compile failure for the missing refresh properties.

- [ ] **Step 3: Implement the state and view**

Set `isRefreshing` around the existing store-owned refresh task. Clear feedback when a forced fetch starts; set `.success` after persistence and `.failure(message)` on ordinary fetch errors; increment `refreshAnimationToken` for terminal results. Keep `phase` and cached snapshots unchanged on ordinary failures.

Render the button as a progress icon while loading, disable it during the request, and show an animated checkmark or error line using `.contentTransition(.symbolEffect(.replace))` and `.transition(.opacity.combined(with: .move(edge: .top)))`. Use the existing `.symbolEffect(.bounce, value:)` fallback if the stable SDK rejects a rotate overload. Add short localized strings for the result.

- [ ] **Step 4: Run focused tests and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=haiity-v6,OS=26.4' -only-testing:HaiityTests/GitHubContributionStoreTests -only-testing:HaiityTests/GitHubCardContractTests -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
```

Expected: all focused tests pass.

```bash
git add Haiity/Models/GitHubContributionStore.swift Haiity/Views/GitHubSettingsView.swift Haiity/Localizable.xcstrings HaiityTests/GitHubContributionStoreTests.swift HaiityTests/GitHubCardContractTests.swift
git commit -m "fix: show GitHub refresh feedback"
```

### Task 4: Add pure native-reminder plans, links, and preferences

**Files:**
- Create: `Haiity/Services/ReminderSync.swift`
- Create: `HaiityTests/ReminderSyncTests.swift`

**Interfaces:** `ReminderSyncLink: Codable, Equatable` stores `habitID`, `reminderID`, and `occurrenceDay`. `ReminderSyncPlan: Equatable` stores `habitID`, `title`, `eventPlan: CalendarEventPlan`, `occurrenceDay`, and `fingerprint`. `ReminderSyncPreferences` provides `isEnabled(in:)`, `setEnabled(_:in:)`, `links(in:)`, `setLinks(_:in:)`, and `clearLinks(in:)`. `ReminderSyncSelection(enabled:)` includes only `.reminder` items with `calendarSyncEnabled`.

- [ ] **Step 1: Write the failing pure tests**

```swift
func testPlanRejectsTrackedHabitsAndUsesReminderOccurrence() {
    var reminder = Habit(name: "Tabletten", itemType: .reminder)
    reminder.calendarSyncEnabled = true
    let plan = ReminderSyncPlan(habit: reminder,
                                today: "2026-08-17",
                                calendar: berlin)
    XCTAssertEqual(plan?.habitID, reminder.id)
    XCTAssertEqual(plan?.title, "Tabletten")
    XCTAssertEqual(plan?.occurrenceDay, "2026-08-17")
    XCTAssertNil(ReminderSyncPlan(habit: Habit(name: "Laufen"),
                                  today: "2026-08-17",
                                  calendar: berlin))
}

func testReminderLinksRoundTrip() {
    let defaults = UserDefaults(suiteName: "reminder-sync-\(UUID().uuidString)")!
    let link = ReminderSyncLink(habitID: UUID(),
                                reminderID: "native-id",
                                occurrenceDay: "2026-08-17")
    ReminderSyncPreferences.setLinks([link.habitID.uuidString: link], in: defaults)
    XCTAssertEqual(ReminderSyncPreferences.links(in: defaults)[link.habitID.uuidString], link)
}

func testSelectionHonorsGlobalAndPerItemOptIn() {
    var reminder = Habit(name: "Tabletten", itemType: .reminder)
    reminder.calendarSyncEnabled = true
    var disabled = reminder
    disabled.calendarSyncEnabled = false
    XCTAssertTrue(ReminderSyncSelection(enabled: true).includes(reminder))
    XCTAssertFalse(ReminderSyncSelection(enabled: true).includes(disabled))
}
```

- [ ] **Step 2: Run the focused test and verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=haiity-v6,OS=26.4' -only-testing:HaiityTests/ReminderSyncTests -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
```

Expected: compile failure because the plan, link, selection, and preference types do not exist.

- [ ] **Step 3: Implement the pure boundary**

Build a reminder plan from `CalendarEventPlan(habit:today:calendar:)`, require `habit.isReminder`, and choose `occurrenceDay` from `ReminderOccurrenceEngine.state(for:now:calendar:).actionable?.day` with `eventPlan.firstDay` as the future fallback. Include habit UUID and occurrence day in the fingerprint so a new occurrence resets native completion. Encode the new link dictionary as JSON in App Group defaults; malformed/missing data reads as an empty map and the preference default is off.

- [ ] **Step 4: Run focused tests and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=haiity-v6,OS=26.4' -only-testing:HaiityTests/ReminderSyncTests -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
```

Expected: all pass without EventKit permission prompts. Then:

```bash
git add Haiity/Services/ReminderSync.swift HaiityTests/ReminderSyncTests.swift
git commit -m "feat: model owned native reminder links"
```

### Task 5: Implement the EventKit hAiity Reminders service

**Files:**
- Modify: `Haiity/Services/ReminderSync.swift`
- Modify: `Haiity/Services/CalendarSync.swift`
- Test: `HaiityTests/ReminderSyncTests.swift`

**Interfaces:** `@MainActor enum ReminderSync` exposes `isEnabled`, `hasAccess`, `requestAccess() async -> Bool`, `reconcile(habits:validate:)`, `pullCompletions(into:)`, `pushCompletion(for:habits:)`, `startObserving(store:)`, and `disable()`.

- [ ] **Step 1: Add failing service contracts**

```swift
func testReminderServiceUsesReminderPermissionAndOwnedList() throws {
    let source = try source("Haiity/Services/ReminderSync.swift")
    XCTAssertTrue(source.contains("requestFullAccessToReminders"))
    XCTAssertTrue(source.contains("authorizationStatus(for: .reminder)"))
    XCTAssertTrue(source.contains("hAiity"))
    XCTAssertTrue(source.contains("EKReminder"))
    XCTAssertFalse(source.contains("event(withIdentifier:"))
}
```

Also assert that `CalendarSync` exposes one recurrence-rule helper used by the reminder service, rather than duplicating the mapping.

- [ ] **Step 2: Run the focused test and verify RED**

Run `ReminderSyncTests`; expected: the permission/list contract fails before the EventKit implementation exists.

- [ ] **Step 3: Implement ownership and reconciliation**

Use a private `EKEventStore` and keys separate from `CalendarSync`. `ensureList()` first uses the stored list identifier, then creates an `.reminder` calendar named `hAiity` in the default reminder source. `reconcile` must return without side effects when disabled or access is missing; build active reminder plans; remove links not in the active set; update or replace only reminders found through stored IDs; create missing reminders in the owned list; set title, notes, due date components, recurrence, and completion from the plan/current log; then persist links atomically.

Expose `CalendarSync.recurrenceRule(for:)` as an internal helper and call it from `ReminderSync`. Do not change calendar event selection, event IDs, or calendar preferences.

- [ ] **Step 4: Implement two-way completion and loop protection**

For each stored link, resolve the `EKReminder` by ID and the matching hAiity reminder by UUID. Native changes compare `isCompleted` to the linked occurrence log and call `HabitStore.setReminderCompletion` only when different; completion uses `ReminderOccurrenceEngine.cursorAfterCompleting`, while a revert uses the linked day. App changes update only the linked native reminder when its state differs. When the actionable occurrence advances, update the link and reset native completion. Guard notification-driven pulls while a pull/reconcile is active and re-read links before writing.

- [ ] **Step 5: Run focused tests and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=haiity-v6,OS=26.4' -only-testing:HaiityTests/ReminderSyncTests -only-testing:HaiityTests/CalendarSyncTests -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
```

Expected: all pass without a permission prompt.

```bash
git add Haiity/Services/ReminderSync.swift Haiity/Services/CalendarSync.swift HaiityTests/ReminderSyncTests.swift
git commit -m "feat: sync hAiity reminders with Apple Reminders"
```

### Task 6: Wire settings, lifecycle, permissions, and localization

**Files:**
- Modify: `Haiity/Views/MoreView.swift`
- Modify: `Haiity/Views/ContentView.swift`
- Modify: `Haiity/Localizable.xcstrings`
- Modify: `project.yml`
- Test: `HaiityTests/ProGateTests.swift`, `HaiityTests/GitHubCardContractTests.swift`

**Interfaces:** Use settings identifier `native-reminder-sync-toggle` and permission hint identifier `open-reminder-settings`. Enabling uses `ReminderSync.requestAccess()` behind `paywall = .calendar`; disabling calls `ReminderSync.disable()` without the paywall. `ContentView.boot()` starts the observer and validates; `store.onChange` reconciles with `validate: false`.

- [ ] **Step 1: Write failing UI/source-contract tests**

```swift
func testNativeReminderToggleIsGatedAndHasPermissionMetadata() throws {
    let more = try source("Haiity/Views/MoreView.swift")
    let project = try source("project.yml")
    XCTAssertTrue(more.contains("native-reminder-sync-toggle"))
    XCTAssertTrue(more.contains("ReminderSync.requestAccess()"))
    XCTAssertTrue(more.contains("ReminderSync.disable()"))
    XCTAssertTrue(more.contains("paywall = .calendar"))
    XCTAssertTrue(more.contains("open-reminder-settings"))
    XCTAssertTrue(project.contains("NSRemindersFullAccessUsageDescription"))
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=haiity-v6,OS=26.4' -only-testing:HaiityTests/ProGateTests -only-testing:HaiityTests/GitHubCardContractTests -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
```

Expected: the new toggle, permission metadata, and service calls are missing.

- [ ] **Step 3: Add the toggle and permission behavior**

Place the native Reminders toggle directly under the existing calendar toggles. Turning it off removes only hAiity-owned reminders and never presents the paywall. Turning it on checks `Pro.isUnlocked`, requests Reminders access, sets the preference only after access succeeds, and shows an iOS Settings action when access is denied.

- [ ] **Step 4: Wire app lifecycle and store changes**

At boot, start the EventKit observer once and run a validating reconcile. In `store.onChange`, run non-validating native-reminder reconciliation beside the existing calendar reconciliation. Observer callbacks pull completion into the store on the main actor, then reconcile without touching unrelated calendar state.

- [ ] **Step 5: Add permission metadata and localized strings**

Add this project property:

```yaml
NSRemindersFullAccessUsageDescription: "hAiity synchronisiert deine eigenen Erinnerungen mit der Apple Erinnerungen-App."
```

Add the German source strings and translated entries for all 16 existing locales, matching the current localization tests.

- [ ] **Step 6: Run focused tests and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=haiity-v6,OS=26.4' -only-testing:HaiityTests/ProGateTests -only-testing:HaiityTests/GitHubCardContractTests -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
```

Expected: all focused tests pass.

```bash
git add Haiity/Views/MoreView.swift Haiity/Views/ContentView.swift Haiity/Localizable.xcstrings project.yml HaiityTests/ProGateTests.swift HaiityTests/GitHubCardContractTests.swift
git commit -m "feat: add native reminder sync settings"
```

### Task 7: Full verification and simulator inspection

**Files:** Modify only if verification exposes a real defect; do not add unrelated cleanup.

- [ ] **Step 1: Regenerate and run the full suite**

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer tools/release.sh
```

Expected: at least 1,125 tests execute, all release checks pass, and no debug seam/privacy-manifest regression appears. Do not upload in this task unless separately requested.

- [ ] **Step 2: Inspect the simulator UI**

Build/install the Debug app on the stable iOS 26.4 simulator and capture screenshots/logs for: a GitHub graph with a custom palette, refresh progress and animated success/failure feedback, and the native Reminders toggle with denied access. Record EventKit behavior as unverified if the simulator has no real Reminders account.

- [ ] **Step 3: Review the final diff**

```bash
git diff --check
git status --short --branch
git diff --stat origin/main...HEAD
git log --oneline --decorate -10
```

Confirm current-task commits contain only listed files and all pre-existing dirty changes remain present.

- [ ] **Step 4: Report verified and unverified behavior**

Report test count, build result, screenshot paths, EventKit limitations, and any remaining App Store/TestFlight processing state without implying that simulator EventKit proves physical-device two-way sync.
