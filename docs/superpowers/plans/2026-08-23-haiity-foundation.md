# hAiity Foundation Performance and Design Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the current hAiity build responsive and visually coherent across launch, appearance settings, habit pages, widgets, and persistence without adding a second source of truth.

**Architecture:** Keep the existing SwiftUI app, shared app-group JSON, CloudKit mirror, and WidgetKit targets. Improve the launch path by making decoded appearance assets bounded and non-blocking, centralize all surface decisions in `Theme`, and keep graph data/layout logic shared between the app and widgets. Use focused pure helpers and regression tests instead of a broad view rewrite.

**Tech Stack:** SwiftUI, UIKit/Core Animation, WidgetKit, CloudKit, XCTest, XcodeGen, Xcode Cloud.

## Global Constraints

- Preserve hAiity branding and existing build target names.
- Keep local app-group JSON as the widget/intents source of truth and CloudKit as its mirror.
- Do not remove existing untracked user/session artifacts.
- Do not claim physical-device or TestFlight behavior without direct verification.
- Keep UI copy concise and German where it is user-facing.

### Task 1: Establish measurable launch and appearance behavior

**Files:**
- Modify: `Haiity/Models/Theme.swift`
- Modify: `Haiity/HaiityApp.swift`
- Test: `HaiityTests/ThemeAndPaletteTests.swift`, `HaiityTests/StartupSplashTests.swift`

- [ ] Add pure tests for bounded background decoding inputs and launch readiness fallback.
- [ ] Run the focused tests and confirm the new cases fail for the current unbounded/blocking path.
- [ ] Implement downsampled image preparation and a bounded launch fallback without changing persisted appearance data.
- [ ] Run the focused tests and confirm all pass.

### Task 2: Reduce launch and graph rendering work

**Files:**
- Modify: `Haiity/Views/StartupSplashView.swift`
- Modify: `Haiity/Views/GitHubContributionGraph.swift`
- Modify: `HaiityWidget/GitHubWidgetGraph.swift`
- Modify: `Haiity/Views/HabitCard.swift`, `Haiity/Views/ReminderRow.swift`
- Test: `HaiityTests/StartupSplashTests.swift`, `HaiityTests/ContributionGridTests.swift`

- [ ] Add regression tests for stable grid geometry and cache-key behavior.
- [ ] Run them red, then cache derived geometry/palette work and retain Core Animation for splash motion.
- [ ] Verify the app and widget use the same graph geometry and palette resolution.
- [ ] Run focused tests and a Debug simulator build.

### Task 3: Unify adaptive surfaces and page chrome

**Files:**
- Modify: `Haiity/Theme.swift`
- Modify: `Haiity/Views/ContentView.swift`
- Modify: `Haiity/Views/MoreView.swift`
- Modify: `Haiity/Views/StatsView.swift`, `Haiity/Views/ReminderSetupView.swift`, `Haiity/Views/FeedbackSheet.swift`
- Test: `HaiityTests/ThemeAndPaletteTests.swift`, `HaiityTests/ChromeLayoutTests.swift`

- [ ] Add tests covering one resolved surface treatment for solid, milky, liquid, and adaptive modes.
- [ ] Run them red against page-specific styling divergence.
- [ ] Route settings, sheets, toasts, navigation chrome, stats, and setup through the existing shared theme modifiers.
- [ ] Keep interaction layers above decorative materials and preserve readable contrast.
- [ ] Verify the appearance controls and page surfaces through simulator screenshots.

### Task 4: Harden widget, iCloud, notification, and background-refresh contracts

**Files:**
- Modify: `Haiity/Models/HabitStore.swift`, `Haiity/Services/CloudSync.swift`
- Modify: `Haiity/Services/GitHubContributionStore.swift`, `Haiity/Services/Reminders.swift`
- Modify: `HaiityWidget/WidgetLogic.swift`, `HaiityWidget/HaiityWidget.swift`
- Test: `HaiityTests/StoreAndMergeTests.swift`, `HaiityTests/WidgetLogicTests.swift`, `HaiityTests/RemindersTests.swift`

- [ ] Add round-trip tests for appearance, timezone, calendar, reminder, notification, and GitHub fields.
- [ ] Run them red for any fields that are not preserved or refreshed.
- [ ] Make refresh and merge operations idempotent and ensure the separate GitHub widget receives a valid snapshot or an explicit empty state.
- [ ] Verify notification quick actions and background refresh do not regress existing data.
- [ ] Run the complete test suite.

### Task 5: Release verification

**Files:**
- Modify: `project.yml` only if the release build number must advance.

- [ ] Generate the Xcode project and run the complete test suite.
- [ ] Build the app and widget for the configured iOS 27 simulator destination.
- [ ] Run the physical-device smoke checklist for cold launch, background image switching/deletion, GitHub refresh, widget configuration, notification actions, and iCloud status.
- [ ] Push the verified commit and trigger the hAiity Xcode Cloud workflow.
- [ ] Confirm the exact build number in App Store Connect TestFlight before reporting upload completion.
