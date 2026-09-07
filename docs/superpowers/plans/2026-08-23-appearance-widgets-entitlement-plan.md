# Appearance, Widgets, and Entitlement Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Stats/Mehr use continuous native glass, restore reliable background controls, make widgets type-aware, and re-lock all existing Pro features after entitlement expiry.

**Architecture:** Keep one appearance model in `AppearancePreferences`, one pure widget display model in `WidgetLogic`, and one entitlement read point in `Pro.isUnlocked`. Remove the custom navigation-bar override, restore native SwiftUI controls for background selection, and trigger a downgrade-capable entitlement refresh only from launch/foreground lifecycle paths.

**Tech Stack:** Swift 5.9, SwiftUI, WidgetKit, StoreKit 2, XCTest, XcodeGen, iOS 17 deployment target, iOS 26/27 runtime verification.

## Global Constraints

- The product model, stored habit schema, widget configuration intents, and developer-owner bypass remain unchanged.
- Existing Solid, Milchglas, Liquid Glass, and Auto surface choices continue to theme settings rows and cards.
- Reminder items remain excluded from the overview roster and graph-only widget paths.
- Disabling integrations and exporting/importing data remain available after Pro expiry.
- Automatic entitlement checks do not call `AppStore.sync()`; the explicit Restore action remains the account-history refresh path.
- Use the existing `tools/release.sh` test floor and raise it only after the new tests are present and the full suite count is verified.
- Do not edit or delete pre-existing untracked `.superpowers/` or `build/` artifacts.

## File Map

- Modify `Haiity/Theme.swift`: make appearance mode transitions explicit and remove forced navigation-bar backgrounds.
- Modify `Haiity/Views/MoreView.swift`: use native background mode and image-picker controls.
- Modify `Haiity/Models/HabitStore.swift` only if an appearance persistence assertion exposes a real merge/write defect; do not refactor unrelated sync code.
- Modify `HaiityWidget/WidgetLogic.swift`: add the shared type-aware item summary.
- Modify `HaiityWidget/HaiityWidgetView.swift`: render the single-item summary.
- Modify `HaiityWidget/RosterWidgetView.swift`: render the overview summary.
- Modify `Haiity/HaiityApp.swift`: run downgrade-capable entitlement refresh on launch and foreground activation.
- Modify `HaiityTests/ThemeAndPaletteTests.swift`: navigation and appearance-control contracts.
- Modify `HaiityTests/StoreAndMergeTests.swift`: appearance persistence/merge regression coverage if needed.
- Modify `HaiityTests/WidgetLogicTests.swift` and `HaiityTests/WidgetRenderingTests.swift`: type-aware logic and image rendering coverage.
- Modify `HaiityTests/ProGateTests.swift`: lifecycle downgrade and shared-gate contracts.
- Modify `tools/release.sh`: update `MIN_TESTS` only after measuring the new full-suite count.

---

### Task 1: Restore Native Continuous Navigation Chrome

**Files:**
- Modify: `Haiity/Theme.swift:789-815`
- Test: `HaiityTests/ThemeAndPaletteTests.swift` near `testSettingsChromeKeepsNativeMaterialVisibleForGlassModes`

**Interfaces:**
- Consumes: `AppearanceBackground(preferences:)` and the existing `settingsChrome()` view modifier.
- Produces: a settings chrome modifier that supplies only the page background and leaves navigation-bar material ownership to the native navigation container.

- [ ] **Step 1: Write the failing source-contract test.**

Add a test that loads `Haiity/Theme.swift`, extracts the `SettingsChromeModifier` section, and requires the shared background while rejecting all forced navigation-bar visibility/material calls:

```swift
func testSettingsChromeLeavesNavigationBarMaterialToTheSystem() throws {
    let theme = try source("Haiity/Theme.swift")
    let start = try XCTUnwrap(theme.range(of: "private struct SettingsChromeModifier"))
    let chrome = String(theme[start.lowerBound...])
    XCTAssertTrue(chrome.contains("AppearanceBackground(preferences: preferences)"))
    XCTAssertFalse(chrome.contains("toolbarBackground(.visible"))
    XCTAssertFalse(chrome.contains("toolbarBackground(Color("))
    XCTAssertFalse(chrome.contains("toolbarBackground(.regularMaterial"))
    XCTAssertFalse(chrome.contains("toolbarBackground(.ultraThinMaterial"))
}
```

- [ ] **Step 2: Run the focused test and verify the expected failure.**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests/ThemeAndPaletteTests/testSettingsChromeLeavesNavigationBarMaterialToTheSystem \
  CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL because the current modifier contains explicit `toolbarBackground` calls.

- [ ] **Step 3: Implement the smallest production change.**

Replace the material switch in `SettingsChromeModifier` with one body:

```swift
func body(content: Content) -> some View {
    content.background(AppearanceBackground(preferences: preferences))
}
```

Keep `SettingsSurfaceModifier` and all card/surface material behavior unchanged.

- [ ] **Step 4: Run the focused test and the existing chrome tests.**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests/ThemeAndPaletteTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: the new contract and all existing theme/palette tests pass.

- [ ] **Step 5: Commit the isolated change.**

```bash
git add Haiity/Theme.swift HaiityTests/ThemeAndPaletteTests.swift
git commit -m "Fix continuous native settings navigation glass"
```

---

### Task 2: Make Background Controls Native and Persistent

**Files:**
- Modify: `Haiity/Theme.swift:77-103`
- Modify: `Haiity/Views/MoreView.swift:81-84, 1012-1025, 1134-1164, 1250-1325`
- Test: `HaiityTests/ThemeAndPaletteTests.swift` and `HaiityTests/StoreAndMergeTests.swift`

**Interfaces:**
- Consumes: `AppearancePreferences`, `HabitStore.appearancePreferences`, and `PhotosPickerItem`.
- Produces: `AppearancePreferences.selectBackgroundMode(_:)`, native `Picker` mode selection, direct `PhotosPicker` selection, and a removal path that cancels stale imports.

- [ ] **Step 1: Write failing model and source-contract tests.**

Add a model test:

```swift
func testSelectingNonImageModeClearsTheStoredImage() {
    var preferences = AppearancePreferences(backgroundImageData: Data([1, 2, 3]),
                                             backgroundMode: .image)
    preferences.selectBackgroundMode(.gradient)
    XCTAssertEqual(preferences.backgroundMode, .gradient)
    XCTAssertNil(preferences.backgroundImageData)
}

func testSelectingImageModeDoesNotInventImageData() {
    var preferences = AppearancePreferences(backgroundMode: .color)
    preferences.selectBackgroundMode(.image)
    XCTAssertEqual(preferences.backgroundMode, .image)
    XCTAssertNil(preferences.backgroundImageData)
}
```

Add a source contract that requires `Picker(selection: backgroundModeBinding)`, direct `PhotosPicker(selection: $pickedBackgroundItem`, and `selectBackgroundMode`, while rejecting `.photosPicker(isPresented:`.

- [ ] **Step 2: Run the focused tests and verify RED.**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests/ThemeAndPaletteTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: the model test fails because `selectBackgroundMode` does not exist and the source contract fails because the current view uses custom buttons.

- [ ] **Step 3: Add the single appearance transition helper.**

In `AppearancePreferences`, add:

```swift
mutating func selectBackgroundMode(_ mode: AppearanceBackgroundMode) {
    backgroundMode = mode
    if mode != .image {
        backgroundImageData = nil
    }
}
```

Update `backgroundModeBinding` and the remove action to call this helper. Keep image bytes intact when selecting `.image`; the picker import supplies them asynchronously.

- [ ] **Step 4: Replace custom mode and picker interaction with native controls.**

Remove `showingBackgroundPhotoPicker`. Replace `backgroundModeSelector` with:

```swift
Picker(String(localized: "Hintergrund"), selection: backgroundModeBinding) {
    ForEach(AppearanceBackgroundMode.allCases, id: \.self) { mode in
        Label(mode.displayName, systemImage: backgroundSymbol(for: mode))
            .tag(mode)
    }
}
.pickerStyle(.segmented)
.labelsHidden()
.accessibilityIdentifier("appearance-background-mode-picker")
```

Use `PhotosPicker(selection: $pickedBackgroundItem, matching: .images)` directly for the `Bild auswählen` label. Keep the existing import token guard, error state, normalized image data, accessibility identifiers, and separate remove button.

- [ ] **Step 5: Run model, source, persistence, and merge tests.**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests/ThemeAndPaletteTests \
  -only-testing:HaiityTests/StoreAndMergeTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all appearance mode, JSON, local persistence, and newer-remote merge tests pass.

- [ ] **Step 6: Commit the isolated change.**

```bash
git add Haiity/Theme.swift Haiity/Views/MoreView.swift \
  HaiityTests/ThemeAndPaletteTests.swift HaiityTests/StoreAndMergeTests.swift
git commit -m "Restore native background appearance controls"
```

---

### Task 3: Share Type-Aware Widget Presentation

**Files:**
- Modify: `HaiityWidget/WidgetLogic.swift:79-245`
- Modify: `HaiityWidget/HaiityWidgetView.swift:55-243`
- Modify: `HaiityWidget/RosterWidgetView.swift:86-176`
- Test: `HaiityTests/WidgetLogicTests.swift` and `HaiityTests/WidgetRenderingTests.swift`

**Interfaces:**
- Consumes: `Habit.kind`, `Habit.itemType`, `Habit.log`, `GoalEngine`, and `WidgetStatus`.
- Produces: `WidgetItemSummary`, `WidgetAnswer`, `WidgetItemSummary.metricText`, and `WidgetItemSummary.metricSymbol`, consumed by both widget views.

- [ ] **Step 1: Write failing pure widget tests.**

Add these cases to `WidgetLogicTests`:

```swift
func testSummaryForCheckboxUsesStatusAndStreak() {
    let habit = named("Lesen", log: [today: 1])
    let summary = WidgetLogic.summary(habit: habit, today: today, calendar: cal)
    XCTAssertEqual(summary.kind, .checkbox)
    XCTAssertEqual(summary.status, .done)
    XCTAssertEqual(summary.metricText, String(localized: "✓ Heute erledigt"))
}

func testSummaryForQuantityShowsCurrentAndTargetBeforeCompletion() {
    let habit = named("Wasser", recurrence: Recurrence(target: 3), log: [today: 2])
    let summary = WidgetLogic.summary(habit: habit, today: today, calendar: cal)
    XCTAssertEqual(summary.kind, .quantity)
    XCTAssertEqual(summary.value, 2)
    XCTAssertEqual(summary.target, 3)
    XCTAssertEqual(summary.metricText, "2/3")
    XCTAssertEqual(summary.status, .open)
}

func testSummaryForYesNoDistinguishesYesNoAndOpen() {
    var yesNo = named("Zucker", kind: .yesNo)
    XCTAssertEqual(WidgetLogic.summary(habit: yesNo, today: today, calendar: cal).answer, .open)
    yesNo.log[today] = Habit.Answer.no
    XCTAssertEqual(WidgetLogic.summary(habit: yesNo, today: today, calendar: cal).answer, .no)
    yesNo.log[today] = Habit.Answer.yes
    XCTAssertEqual(WidgetLogic.summary(habit: yesNo, today: today, calendar: cal).answer, .yes)
}
```

- [ ] **Step 2: Run the focused widget tests and verify RED.**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests/WidgetLogicTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL because `WidgetItemSummary`, `WidgetAnswer`, and `WidgetLogic.summary` do not exist.

- [ ] **Step 3: Add the shared pure summary model and logic.**

Add an equatable `WidgetAnswer` enum with `.yes`, `.no`, and `.open`. Add an equatable `WidgetItemSummary` with:

```swift
enum Kind: Equatable { case checkbox, quantity, yesNo, reminder }
let kind: Kind
let status: WidgetStatus
let answer: WidgetAnswer?
let value: Int?
let target: Int?
let metricText: String
let metricSymbol: String
```

Implement `WidgetLogic.summary(habit:today:calendar:)` so reminders return the existing reminder status, quantity uses the stored daily value and recurrence target, yes/no maps `Habit.Answer.yes/no` to the three answer states, and checkbox uses the existing status text. Keep all schedule and status decisions in `WidgetLogic`.

- [ ] **Step 4: Route both widget views through the summary.**

In `HaiityWidgetView`, compute the summary once in `small` and `medium`; use its metric text/symbol and status color. Keep the existing quantity check button action and reminder layout, but remove duplicate yes/no and quantity display decisions from the view.

In `RosterWidgetView`, replace `streakRun(...)` plus generic `glyph(...)` with the shared summary metric text and symbol. Keep the graph, row sizing, overflow behavior, and reminder exclusion unchanged.

- [ ] **Step 5: Run logic and rendering verification.**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests/WidgetLogicTests \
  -only-testing:HaiityTests/WidgetRenderingTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: type-specific unit tests and light/dark/vibrant render tests pass, with no reminder rows added to the overview.

- [ ] **Step 6: Commit the isolated change.**

```bash
git add HaiityWidget/WidgetLogic.swift HaiityWidget/HaiityWidgetView.swift \
  HaiityWidget/RosterWidgetView.swift HaiityTests/WidgetLogicTests.swift \
  HaiityTests/WidgetRenderingTests.swift
git commit -m "Make widgets adapt to habit type"
```

---

### Task 4: Downgrade Pro on Expiry Across Existing Gates

**Files:**
- Modify: `Haiity/HaiityApp.swift:116-127`
- Test: `HaiityTests/ProGateTests.swift`

**Interfaces:**
- Consumes: `Pro.refresh(mayDowngrade:)`, `scenePhase`, and the existing `Pro.isUnlocked` read point.
- Produces: launch and foreground entitlement refreshes that can set the shared observable Pro state back to locked when StoreKit reports no current entitlement.

- [ ] **Step 1: Write the failing lifecycle and gate regression tests.**

Add source contracts:

```swift
func testAppRefreshesProWithDowngradePermissionOnLaunchAndForeground() throws {
    let app = try source("Haiity/HaiityApp.swift")
    XCTAssertTrue(app.contains("Task { await Pro.refresh(mayDowngrade: true) }"))
    XCTAssertTrue(app.contains("case .active:"))
    XCTAssertTrue(app.contains("Pro.refresh(mayDowngrade: true)"))
}

func testAllExistingProFeatureHostsReadTheSharedEntitlement() throws {
    for file in ["Haiity/Views/MoreView.swift",
                 "Haiity/Views/StatsView.swift",
                 "Haiity/Views/EditHabitSheet.swift",
                 "Haiity/Views/ContentView.swift"] {
        let text = try source(file)
        XCTAssertTrue(text.contains("Pro.isUnlocked") || text.contains("unlocked"), file)
    }
}
```

Add a pure policy assertion around the existing `ProGate.mayUseProFeature(unlocked:)` matrix: false entitlement must reject and true entitlement must allow. Keep the existing developer-owner test.

- [ ] **Step 2: Run the focused Pro tests and verify RED.**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests/ProGateTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: the lifecycle test fails because the app currently calls only `Pro.refresh()` at boot and does not refresh Pro on `.active`.

- [ ] **Step 3: Add downgrade-capable launch and foreground checks.**

In `HaiityApp`, change the boot task to:

```swift
Task { await Pro.refresh(mayDowngrade: true) }
```

In the `.active` scene-phase branch, add:

```swift
Task { await Pro.refresh(mayDowngrade: true) }
```

Do not call `AppStore.sync()` here. Leave `Pro.restore()` as the explicit sync path and leave the transaction listener intact.

- [ ] **Step 4: Run the Pro tests and full existing gate contracts.**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests/ProGateTests \
  -only-testing:HaiityTests/CalendarSyncTests \
  -only-testing:HaiityTests/ReminderSyncTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all existing creation, palette, icon, calendar, native reminder, Stats, paywall, and developer-owner contracts pass.

- [ ] **Step 5: Commit the isolated change.**

```bash
git add Haiity/HaiityApp.swift HaiityTests/ProGateTests.swift
git commit -m "Refresh Pro entitlement when the app becomes active"
```

---

### Task 5: Full Verification and Runtime UI Audit

**Files:**
- Modify: `tools/release.sh` only if the measured test count increases.
- Build artifacts: `/tmp/haiity-appearance-widget-audit`

- [ ] **Step 1: Regenerate the project and run the full suite.**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests CODE_SIGNING_ALLOWED=NO
```

Expected: zero failures. Record the exact `Executed N tests` count before changing the release floor.

- [ ] **Step 2: Run the app and capture the affected screens.**

Install the Debug build on the same simulator and capture screenshots of:

1. Stats with the image background and Liquid Glass selected.
2. Mehr with the same background.
3. Darstellung while switching `Bild -> Farbe -> Verlauf -> Bild`.
4. Darstellung after selecting and then removing an image.
5. Widget previews for checkbox, quantity, and yes/no data.

Inspect the screenshots for one continuous navigation blur, no dark hard band, no detached overlay, readable text, and no blank or stale image state.

- [ ] **Step 3: Exercise the background controls at runtime.**

Use accessibility identifiers `appearance-background-mode-color`, `appearance-background-mode-gradient`, `appearance-background-mode-image`, `appearance-background-picker`, and `appearance-background-remove`. Verify each tap changes the visible control and that the next app launch loads the selected state from the app-group file.

- [ ] **Step 4: Verify the entitlement path in the StoreKit configuration.**

Run the app with the existing StoreKit test configuration and confirm that turning the simulated entitlement off followed by foreground activation makes the Pro row/paywall and all existing locked entry points appear again. Confirm the developer-owner identity still keeps Pro unlocked in the debug owner path.

- [ ] **Step 5: Update and run the release verification.**

If the full suite count is higher than the current `MIN_TESTS=1294`, update that constant to the measured count, then run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
OUT=/tmp/haiity-appearance-widget-audit \
tools/release.sh
```

Expected: release Xcode archive/export verification succeeds. Do not upload to TestFlight in this task because the approved scope did not request an upload.

- [ ] **Step 6: Commit release-floor changes only when required.**

```bash
git add tools/release.sh
git commit -m "Raise release test floor for appearance and widget coverage"
```

Skip this commit if the measured test count remains exactly 1294.
