# Apple Design Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make hAiity's appearance, navigation, launch handoff, enlarged cards, and large widgets feel like one readable native Apple product without changing stored data or existing app behavior.

**Architecture:** Extend the existing `Theme.swift` environment and view modifiers instead of introducing a theme manager. Keep the native iOS 26 tab bar, the existing UIKit splash renderer, and the current card/widget renderers; fix their surface ownership and geometry at the existing call sites. Each task changes a disjoint set of source files and adds focused source-contract or rendering tests beside the current test suites.

**Tech Stack:** Swift 5.9, SwiftUI, UIKit/Core Animation, WidgetKit, AppIntents, XCTest, XcodeGen, `xcodebuild`.

## Global Constraints

- Preserve native SwiftUI architecture, iCloud/App Group payloads, App Intents, deep links, subscriptions, Calendar/Reminders behavior, and iOS 17+ compatibility.
- Use the existing appearance state and rendering primitives in `Theme.swift` as the source of truth.
- Do not add a new Manager, Service, Factory, Provider, Coordinator, or design framework.
- No changes to the habit, reminder, iCloud, or App Group payload formats.
- Keep the native iOS 26+ tab bar as the primary navigation and the existing fallback for older systems.
- The visible rounded shape owns its clipping, border, and shadow; source views must not leave a second shadow during enlargement.
- Large widgets remain glanceable, graph-first, and free of clipped titles, emojis, graphs, or action controls.
- Every new behavior gets a focused failing test before implementation and the existing suite remains enabled.
- Do not stage or revert unrelated dirty files: `.superpowers/sdd/task-1-report.md`, `.superpowers/sdd/task-2-report.md`, `.superpowers/sdd/task-3-report.md`, `.superpowers/sdd/task-4-report.md`, `.runtime-stats-fixture.json`, `.superpowers/brainstorm/`, or older plans.

## File Map

- `Haiity/Theme.swift`: shared appearance backgrounds, settings rows, navigation chrome, metrics, and image-cache access.
- `Haiity/Views/MoreView.swift`: Mehr, Verhalten & Teilen, Darstellung, and related settings surfaces.
- `Haiity/Views/MaterialPreviewPicker.swift`: material selection presentation.
- `Haiity/Views/ContentView.swift`: native/fallback navigation, search, create action, toast placement, and route transitions.
- `Haiity/Views/ReminderSetupView.swift`: setup pager layout, permission actions, and appearance-aware setup chrome.
- `Haiity/Models/ChromeLayout.swift`: shared chrome measurements and safe-area decisions.
- `Haiity/Views/StartupSplashView.swift`: tile animation and final app handoff.
- `Haiity/HaiityApp.swift`: mounting the prepared content beneath the splash.
- `Haiity/Models/StartupSplash.swift`: timeline and handoff math.
- `Haiity/Views/HabitCard.swift`: habit/reminder cards and UIKit context-menu preview surface.
- `Haiity/Views/StatsView.swift`: stats cards and enlarged previews.
- `HaiityWidget/WidgetLogic.swift`: stable large-widget geometry and item summaries.
- `HaiityWidget/WidgetGridViews.swift`: large graph-first widget renderer.
- `HaiityWidget/RosterWidgetView.swift`: large list/focus widget renderer.
- `HaiityWidget/HaiityWidgetView.swift`, `HaiityWidget/GraphWidgetView.swift`, `HaiityWidget/GitHubWidgetGraph.swift`: shared widget composition and graph rendering.
- `HaiityTests/ThemeAndPaletteTests.swift`, `HaiityTests/SetupFlowTests.swift`: appearance and setup contracts.
- `HaiityTests/ChromeLayoutTests.swift`: chrome, safe-area, and preview geometry contracts.
- `HaiityTests/StartupSplashTests.swift`: timeline and handoff contracts.
- `HaiityTests/GraphContextMenuRegressionTests.swift`: source ownership and one-shadow regressions.
- `HaiityTests/WidgetRenderingTests.swift`, `HaiityTests/WidgetLogicTests.swift`, `HaiityTests/GitHubWidgetTests.swift`: widget geometry, rendering, and configuration contracts.

---

### Task 1: Shared Appearance and Settings Surfaces

**Files:**
- Modify: `Haiity/Theme.swift`
- Modify: `Haiity/Views/MoreView.swift`
- Modify: `Haiity/Views/MaterialPreviewPicker.swift`
- Test: `HaiityTests/ThemeAndPaletteTests.swift`

**Interfaces:**
- Consumes: `AppearancePreferences`, `AppearanceBackground`, `SettingsRowSurface`, `SettingsSurfaceModifier`, `SettingsChromeModifier`, and existing environment key `appearancePreferences`.
- Produces: appearance-aware row and section rendering that all More subpages can apply without introducing a new type hierarchy.

- [ ] **Step 1: Write the failing appearance contract tests.** Add tests to `ThemeAndPaletteTests.swift` that assert the shared settings surface exposes the selected material, image/gradient mode uses a readable overlay, and the settings modifier is applied by the More subpages. Use the existing `source(_:)` helper and assert exact source strings such as `AppearanceBackground(preferences: appearancePreferences)`, `.settingsSurface()`, and `.settingsRowSurface()`.

- [ ] **Step 2: Run the focused tests to verify RED.** Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HaiityTests/ThemeAndPaletteTests
```

Expected result: the new source-contract assertions fail because at least one shared More surface does not yet use the appearance-aware modifier.

- [ ] **Step 3: Implement the smallest shared-surface change.** Keep `AppearanceBackground` as the only background renderer. Make the settings surface apply one material-aware fill, one readable foreground rule, and one shape-owned clip/border; do not attach a shadow to a larger parent. Update More's root and its Verhalten & Teilen, Darstellung, and setup-related sections to use the same existing modifiers. Keep `Bild auswählen` controls conditional on image mode and leave persisted `AppearancePreferences` fields unchanged. Make the material picker use the same preview and selected-state treatment as the settings rows.

- [ ] **Step 4: Run the focused tests to verify GREEN.** Re-run the command from Step 2, then run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HaiityTests/ThemeAndPaletteTests -only-testing:HaiityTests/SetupFlowTests
```

Expected result: all focused appearance and existing setup tests pass for solid, milky, liquid, adaptive, color, gradient, image, light, dark, and reduced-transparency source contracts.

- [ ] **Step 5: Commit the task.**

```bash
git add Haiity/Theme.swift Haiity/Views/MoreView.swift Haiity/Views/MaterialPreviewPicker.swift HaiityTests/ThemeAndPaletteTests.swift
git commit -m "polish shared appearance surfaces"
```

### Task 2: Native Chrome, Search, and Setup Presentation

**Files:**
- Modify: `Haiity/Views/ContentView.swift`
- Modify: `Haiity/Views/ReminderSetupView.swift`
- Modify: `Haiity/Models/ChromeLayout.swift`
- Test: `HaiityTests/ChromeLayoutTests.swift`
- Test: `HaiityTests/SetupFlowTests.swift`
- Test: `HaiityTests/SearchFlowTests.swift`

**Interfaces:**
- Consumes: the shared appearance modifiers from Task 1 and the current `AppTab`, `ChromeLayout`, and route presentation state.
- Produces: one native bottom navigation path on iOS 26+, one compatible fallback path, stable search open/close geometry, and a full-screen setup composition.

- [ ] **Step 1: Write the failing chrome contracts.** Add focused assertions for one bottom chrome owner, search close cleanup, safe-area-aware toast placement, and setup content using the available height without a second opaque footer. Reuse existing `ChromeLayout` and source helpers instead of adding a UI test-only abstraction.

- [ ] **Step 2: Run the focused tests to verify RED.** Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HaiityTests/ChromeLayoutTests -only-testing:HaiityTests/SetupFlowTests -only-testing:HaiityTests/SearchFlowTests
```

Expected result: the newly added assertions fail on the current duplicate/transition or placement path.

- [ ] **Step 3: Align the native path and fallback.** Keep the native `TabView` as the sole bottom bar on supported OS versions. Keep search and create as actions, not extra content tabs; preserve the existing animation while removing the transient closing overlay, matched shadow, or blank frame. Make the toast reserve the expanded native bar's safe-area height before it appears. Keep the fallback chrome only for older OS versions and route both paths through the same `ChromeLayout` constants. Update setup to use the entire available height, a readable top composition, and a transparent footer while preserving all permission actions and accessibility identifiers.

- [ ] **Step 4: Run the focused tests to verify GREEN.** Re-run Step 2 and inspect the generated source diff for a single native chrome owner, no second `legacyBottomChrome` on iOS 26+, and no changed route/deep-link payload behavior.

- [ ] **Step 5: Commit the task.**

```bash
git add Haiity/Views/ContentView.swift Haiity/Views/ReminderSetupView.swift Haiity/Models/ChromeLayout.swift HaiityTests/ChromeLayoutTests.swift HaiityTests/SetupFlowTests.swift HaiityTests/SearchFlowTests.swift
git commit -m "align native navigation and setup chrome"
```

### Task 3: Splash Handoff Performance

**Files:**
- Modify: `Haiity/Views/StartupSplashView.swift`
- Modify: `Haiity/HaiityApp.swift`
- Modify: `Haiity/Models/StartupSplash.swift`
- Test: `HaiityTests/StartupSplashTests.swift`

**Interfaces:**
- Consumes: `StartupSplashTimeline`, `AppearanceImageCache`, and the existing prepared app content mounted beneath the splash.
- Produces: a single lightweight tile animation and a continuous fade/zoom handoff with no blank frame, while preserving reduced-motion behavior.

- [ ] **Step 1: Write the failing timeline/performance contracts.** Extend `StartupSplashTests.swift` with assertions that the final handoff has no zero-opacity gap before the app surface is visible, that the tile raster is reused, and that the reduced-motion path has one short handoff rather than a second animation.

- [ ] **Step 2: Run the focused tests to verify RED.** Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HaiityTests/StartupSplashTests
```

Expected result: the new handoff assertions fail against the current timing or visibility contract.

- [ ] **Step 3: Implement the handoff without synchronous image work.** Start/retain the actual `ContentView` beneath the splash immediately. Keep tile raster generation on the existing cache path, do not decode the appearance image synchronously from the splash body, and use one timeline phase at the end that scales the centered graph toward the app frame while fading the splash layer over it. Use the existing `accessibilityReduceMotion` branch to skip tile motion and perform only the short opacity handoff. Do not add a new coordinator or launch service.

- [ ] **Step 4: Run the focused tests to verify GREEN.** Re-run Step 2 and confirm the timeline remains monotonic, the launch raster probe is not incremented for duplicate reads, and the app content is mounted before the splash completes.

- [ ] **Step 5: Commit the task.**

```bash
git add Haiity/Views/StartupSplashView.swift Haiity/HaiityApp.swift Haiity/Models/StartupSplash.swift HaiityTests/StartupSplashTests.swift
git commit -m "smooth splash handoff"
```

### Task 4: Enlarged Cards and Large Widget Geometry

**Files:**
- Modify: `Haiity/Views/HabitCard.swift`
- Modify: `Haiity/Views/StatsView.swift`
- Modify: `HaiityWidget/WidgetLogic.swift`
- Modify: `HaiityWidget/WidgetGridViews.swift`
- Modify: `HaiityWidget/RosterWidgetView.swift`
- Modify: `HaiityWidget/HaiityWidgetView.swift`
- Modify: `HaiityWidget/GraphWidgetView.swift`
- Modify: `HaiityWidget/GitHubWidgetGraph.swift`
- Test: `HaiityTests/GraphContextMenuRegressionTests.swift`
- Test: `HaiityTests/WidgetRenderingTests.swift`
- Test: `HaiityTests/WidgetLogicTests.swift`
- Test: `HaiityTests/GitHubWidgetTests.swift`

**Interfaces:**
- Consumes: existing context-menu preview hosting, `HabitCard` preview metrics, `StatsCardPrefs`, `GraphLayout`, `WidgetLogic.LargeGeometry`, and all current App Intent/widget selection behavior.
- Produces: one visible rounded surface per enlarged card, full graph content within stable bounds, and glanceable large widgets with graph-first hierarchy and no clipped text.

- [ ] **Step 1: Write the failing surface and geometry contracts.** Add regression assertions that every enlarged preview owns its clip and shadow on the visible rounded shape, the source surface is hidden only for the active context menu, and the large graph region is large enough for all supported item kinds without month labels or clipped text. Keep the existing tests for reminders being graph-free and configured selection behavior.

- [ ] **Step 2: Run the focused tests to verify RED.** Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HaiityTests/GraphContextMenuRegressionTests -only-testing:HaiityTests/WidgetRenderingTests -only-testing:HaiityTests/WidgetLogicTests -only-testing:HaiityTests/GitHubWidgetTests
```

Expected result: the new shadow/geometry assertions fail before the source and destination surface ownership is normalized.

- [ ] **Step 3: Normalize enlarged card ownership.** In `HabitCard` and `StatsView`, apply the shadow and border after the rounded card content has its final frame and clip. Remove any shadow from an outer hosting/overlay container, avoid duplicate source and destination shadows during `UIContextMenuInteraction`, and preserve the active-source opacity behavior already covered by `GraphContextMenuRegressionTests`. Make enlarged graphs use stable width/height metrics and a full graph-first layout rather than a clipped half-grid; do not make the graph scrollable when the available data is already exhausted.

- [ ] **Step 4: Refine the large widget renderers.** Keep the three existing widget types and their configuration intents. Give each renderer a stable title/metric band, a dominant graph band, and compact actions that fit the family bounds. Use one-line title truncation and Dynamic Type-safe minimum scales instead of adding text. Keep reminders graph-free, preserve yes/no/count/reset actions, keep GitHub tiles in their dedicated graph surface, and leave existing App Group payloads untouched.

- [ ] **Step 5: Run the focused tests to verify GREEN.** Re-run Step 2, then render all large families with checkbox, quantity, yes/no, reminder, empty, sparse, light, dark, vibrant, custom palette, and accessibility-large fixtures. Expected result: `TEST SUCCEEDED`, nonblank pixels, no clipped graph/title/action, and no duplicate shadow contract failures.

- [ ] **Step 6: Commit the task.**

```bash
git add Haiity/Views/HabitCard.swift Haiity/Views/StatsView.swift HaiityWidget/WidgetLogic.swift HaiityWidget/WidgetGridViews.swift HaiityWidget/RosterWidgetView.swift HaiityWidget/HaiityWidgetView.swift HaiityWidget/GraphWidgetView.swift HaiityWidget/GitHubWidgetGraph.swift HaiityTests/GraphContextMenuRegressionTests.swift HaiityTests/WidgetRenderingTests.swift HaiityTests/WidgetLogicTests.swift HaiityTests/GitHubWidgetTests.swift
git commit -m "polish enlarged cards and large widgets"
```

## Final Verification

- [ ] Run `xcodegen generate` and ensure generated project changes are not committed unless the repository policy requires them.
- [ ] Run the focused tests from all four tasks and then the complete available `HaiityTests` suite on a supported iOS simulator.
- [ ] Run `git diff --check` and inspect `git status --short` to confirm unrelated dirty files were not staged.
- [ ] Run the generic device build gate:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing -project Haiity.xcodeproj -scheme Haiity -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation -skipMacroValidation
```

- [ ] Review the final branch diff for unchanged iCloud/App Group payloads, deep links, App Intents, subscriptions, Calendar/Reminders behavior, and iOS 17 compatibility.
