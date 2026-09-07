# hAiity Apple-Native Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the highest-value visual and performance friction found in the current hAiity audit while preserving the existing Apple-native visual language and behavior.

**Architecture:** Reuse the existing `AppearancePreferences`, `AppearanceImageCache`, `appSurface`, `MenuHost`, and widget geometry helpers. Keep the changes in the existing files; no new managers, protocols, or rendering systems are needed. Each task owns a disjoint file set so workers can implement in parallel, followed by a focused integration review.

**Tech Stack:** Swift 6, SwiftUI, UIKit context-menu hosting, WidgetKit/AppIntents, XCTest, SimSlim.

## Global Constraints

- Preserve unrelated dirty reports, plans, fixtures, and untracked files.
- Use only the existing `/Users/enrico/.config/simslim/haiity.json` SimSlim path for simulator verification; never use DeviceHub.
- Keep at most one simulator booted.
- Preserve iOS 26+ native `TabView` navigation and existing localization/accessibility identifiers.
- Do not add a dependency or a new architecture layer.
- Do not remove legacy Fokus constants or migration code until a source search proves no persisted-widget migration depends on them.

### Task 1: Appearance Image and Shared Surface Performance

**Files:**
- Modify: `Haiity/Theme.swift`
- Modify: `Haiity/Views/MoreView.swift`
- Test: `HaiityTests/ThemeAndPaletteTests.swift`

**Interfaces:**
- Consumes the existing `AppearancePreferences` and `AppearanceImageCache` APIs.
- Produces the same `appearancePreferences` environment value and `appSurface` modifier, with smaller SwiftUI identity work and consistent settings surfaces.

- [x] **Step 1: Add a regression assertion for image identity cost.** Verify that the appearance identity used by view/task inputs does not require comparing the full image byte payload when a reset marker or mode already distinguishes the state.
- [x] **Step 2: Change the minimum existing appearance identity in `Theme.swift` to use mode, reset marker, and a stable bounded digest/size instead of embedding full `Data` in repeated SwiftUI identities.** Keep the original image bytes as the persistence source of truth and keep validation unchanged.
- [x] **Step 3: Update the More/Darstellung surfaces to call the existing shared surface helper for settings groups and controls so Solid, Milchglas, Liquid Glass, and Auto present one coherent hierarchy.** Keep labels, identifiers, and control behavior unchanged.
- [x] **Step 4: Run `xcodebuild test` for `ThemeAndPaletteTests` with the repository’s existing scheme and report any XCTest-runner limitation separately from compilation results.**

### Task 2: Stable Enlarged Previews

**Files:**
- Modify: `Haiity/Views/HabitCard.swift`
- Modify: `Haiity/Views/StatsView.swift`
- Modify: `Haiity/Views/GitHubContributionCard.swift`
- Modify: `Haiity/Views/GitHubContributionGraph.swift`
- Test: `HaiityTests/GraphContextMenuRegressionTests.swift`
- Test: `HaiityUITests/StatsContextMenuUITests.swift`

**Interfaces:**
- Consumes the existing `MenuHost` preview provider and preview metric helpers.
- Produces context-menu previews whose clipping, background, and shadow use one rounded card shape and whose graph content receives a stable, fully fitting frame.

- [x] **Step 1: Add or update regression checks for the preview width/height contract and for one shadow-owning rounded shape.**
- [x] **Step 2: Make `MenuHost` and the stats preview wrapper apply the same rounded shape to clipping, background, border, and shadow; remove any parent/container shadow that uses the host bounds.** Do not change the intended card radius, colors, or menu actions.
- [x] **Step 3: Replace fixed preview heights that clip graph content with the existing graph metrics plus safe vertical insets, keeping the preview width bounded by the hosting window.**
- [x] **Step 4: Ensure the GitHub preview uses a compact, complete contribution grid rather than a horizontally overflowing canvas in the enlarged state.
- [ ] **Step 5: Run the focused graph/context-menu tests and the existing UI test target where the simulator runner is available.**

### Task 3: Large Widget Readability

**Files:**
- Modify: `HaiityWidget/RosterWidgetView.swift`
- Modify: `HaiityWidget/WidgetGridViews.swift`
- Modify: `HaiityWidget/HaiityWidgetView.swift`
- Modify: `HaiityWidget/WidgetLogic.swift`
- Test: `HaiityTests/WidgetRenderingTests.swift`
- Test: `HaiityTests/WidgetLogicTests.swift`

**Interfaces:**
- Consumes `WidgetLogic.LargeGeometry`, `WidgetItemSummary`, `HomeWidgetBackground`, and existing widget families.
- Produces compact large-widget layouts that preserve the graph as the primary visual, prevent title/icon clipping, and adapt list/grid content without changing widget kinds or configuration intents.

- [x] **Step 1: Add rendering-contract checks for the large widget’s maximum title length, graph minimum height, and per-family item count.
- [x] **Step 2: Adjust the existing large-widget geometry constants and layout priorities so identity text stays one concise line, metrics stay secondary, and the graph receives the dominant stable height.
- [x] **Step 3: Add Dynamic Type-safe fallback behavior using existing SwiftUI layout tools (`ViewThatFits`, wrapping, or conditional compact labels) instead of scaling text below readable sizes.
- [x] **Step 4: Verify the regular, large-list, and large-grid renderers with the existing widget rendering tests.

### Task 4: DND Refresh Cadence and Dead-Code Check

**Files:**
- Modify: `Haiity/Views/MoreView.swift`
- Modify: `Haiity/Models/HabitStore.swift` only if the shared DND expiration helper needs correction
- Test: `HaiityTests/ProGateTests.swift`
- Test: `HaiityTests/NotificationActionTests.swift`

**Interfaces:**
- Consumes `NotificationDNDState.isActive()` and the existing `dndNow` state.
- Produces identical minute-level DND text and expiration behavior without a one-second redraw loop.

- [x] **Step 1: Add a test that an active timed DND state expires at the stored boundary and that an until-disabled state remains active.
- [x] **Step 2: Replace the one-second timer used only for minute-level DND display with a minute-aligned update (`TimelineView` or an existing minute cadence), keeping immediate updates when the user changes the picker.
- [x] **Step 3: Search all references to `LargeWidgetLayout.focus` and the removed Fokus widget before deleting anything; leave migration-safe constants in place if any old configuration or test still references them.
- [ ] **Step 4: Run the focused notification/pro-gate tests.

### Task 5: Integration Review and Verification

**Files:**
- Modify: only files required to resolve review findings; do not touch unrelated dirty files.

- [x] **Step 1: Review every worker diff for scope, source consistency, accessibility identifiers, localization, and accidental duplicate rendering.
- [x] **Step 2: Run `git diff --check` and the focused XCTest command using a fresh DerivedData path if the existing build database is locked.
- [ ] **Step 3: Apply the configured SimSlim profile, boot only `SimSlim Verification`, and perform a smoke check for More/Darstellung, Stats, habit long-press preview, and large-widget previews.
- [x] **Step 4: Record compilation/test/simulator evidence without claiming TestFlight or release availability; distribution is outside this polish pass unless separately requested.

## Verification Record (2026-08-31)

- `build-for-testing`: succeeded with Xcode 26.6 and iOS 26.5 simulator SDK.
- Latest `build-for-testing` after the reveal-layer inset: succeeded with Xcode beta 27A5228h and iOS 27.0 SDK.
- `git diff --check`: passed after the reveal-layer inset and bridge reconciliation changes.
- Focused runtime suites: AppearanceSettingTests 60/60, StartupSplashTests 46/46, GraphContextMenuRegressionTests 12/12, WidgetRenderingTests 36/36, and the DND boundary test 1/1.
- SimSlim profile verification: passed before the launch smoke check; only `SimSlim Verification` was booted.
- Launch smoke check: `com.aiity.haiity` installed and launched; nonblank screenshot captured at 1206 x 2622.
- UI interaction attempt before the latest inset: the reminder UI suite reached the simulator, but the reset action was exposed outside the effective List hit area (`x=314...386`) and was not hittable. The bridge reconciliation change alone did not resolve that geometry.
- UI interaction attempt after the latest inset: the test runner stalled before XCTest execution while the shared simulator was carrying an unrelated session; no UI pass is claimed.
- Remaining verification: full navigation/long-press UI smoke remains open for a clean simulator session. No TestFlight or App Store release was created.
