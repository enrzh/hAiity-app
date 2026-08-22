# hAiity Integrations and Appearance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep reminder mode simple, make widgets and GitHub state reliable, mark owned system items, add cloud-synced DND and appearance controls, and verify the resulting UI.

**Architecture:** Extend the existing `HabitData`/`CloudPreferences` payload instead of introducing another persistence store. Keep graph-only entity queries separate from the main hAiity widget entity query, and keep EventKit ownership metadata in a shared Foundation helper while device-specific EventKit identifiers remain local.

**Tech Stack:** SwiftUI, WidgetKit/AppIntents, EventKit, UserNotifications, PhotosUI, CloudKit-backed JSON payload, XCTest, Xcode project generated from `project.yml`.

## Global Constraints

- Preserve unrelated worktree changes in `tools/release.sh`, `.superpowers/`, and `build/`.
- German is the source UI language; use `String(localized:)` for new visible strings.
- New Codable fields must decode safely when absent and participate in `HabitStore.merge(remote:)`.
- Graph widgets never receive reminders; the configurable `hAiity` widget may receive reminders and renders them without a graph.
- A failed GitHub refresh may leave cached data stale, but must never silently delete credentials or cache.
- Background GitHub refresh is best effort because iOS does not guarantee task execution.
- Do not claim UI behavior without running the app and inspecting screenshots.

### Task 1: Reminder-safe editor and widgets

**Files:**
- Modify: `Haiity/Views/EditHabitSheet.swift`
- Modify: `Haiity/Intents/SelectGraphIntent.swift`
- Modify: `HaiityWidget/WidgetLogic.swift`
- Modify: `HaiityWidget/HaiityWidget.swift`
- Modify: `HaiityWidget/HaiityWidgetView.swift`
- Modify: `HaiityTests/ReminderItemTests.swift`
- Modify: `HaiityTests/WidgetLogicTests.swift`
- Modify: `HaiityTests/GitHubWidgetTests.swift`

- [ ] Add source/logic tests proving reminder editor mode does not expose the habit-kind picker, graph entity queries return tracked habits only, and the main widget resolves a reminder.
- [ ] Run the targeted tests and observe the expected failures.
- [ ] Render `kindSection` only for `.habit`, normalize reminder `kind` to `.checkbox` on save, add `GraphHabitEntity`/query, and add a reminder branch to `HaiityWidgetView` with status/checkmark and no grid.
- [ ] Run targeted widget/editor tests and the widget rendering tests.

### Task 2: GitHub foreground/background refresh

**Files:**
- Modify: `Haiity/Models/GitHubContributionStore.swift`
- Modify: `Haiity/Views/ContentView.swift`
- Modify: `Haiity/Views/GitHubSettingsView.swift`
- Modify: `Haiity/HaiityApp.swift`
- Modify: `Haiity/Info.plist`
- Modify: `project.yml`
- Modify: `HaiityTests/GitHubContributionStoreTests.swift`

- [ ] Change the unauthorized-refresh regression test to require cached snapshot, token, and cache preservation.
- [ ] Run it to verify the current `disconnect()` behavior fails the new contract.
- [ ] Preserve credentials/cache on refresh failures, force a refresh on foreground activation, and register/schedule a best-effort `BGAppRefreshTask` using a fresh store.
- [ ] Make the failed settings state offer retry refresh when a credential remains, and keep explicit disconnect as the only logout path.
- [ ] Run GitHub tests and verify the app target builds with the background task identifier.

### Task 3: EventKit ownership watermark and hints

**Files:**
- Create: `Haiity/Services/SyncWatermark.swift`
- Modify: `Haiity/Services/CalendarSync.swift`
- Modify: `Haiity/Services/ReminderSync.swift`
- Modify: `Haiity/Views/MoreView.swift`
- Modify: `HaiityTests/CalendarSyncTests.swift`
- Modify: `HaiityTests/ReminderSyncTests.swift`

- [ ] Add pure tests for readable `hAiity` notes plus an invisible UUID marker and copy-text hints.
- [ ] Run them to verify the helper is absent.
- [ ] Attach the marker to actual hAiity calendar events and Apple reminders while preserving the readable prefix, then add three hint rows with copy buttons below the sync toggles.
- [ ] Verify copy feedback is visible and run EventKit/source contract tests.

### Task 4: DND notification preference

**Files:**
- Modify: `Haiity/Models/HabitStore.swift`
- Modify: `Haiity/Services/Reminders.swift`
- Modify: `Haiity/Views/MoreView.swift`
- Modify: `Haiity/Views/ContentView.swift`
- Modify: `HaiityTests/CloudSyncTests.swift`
- Modify: `HaiityTests/ReminderUpcomingTests.swift`

- [ ] Add failing Codable and expiry tests for timed and permanent DND, including migration from the old boolean.
- [ ] Run them and confirm the current boolean-only model cannot represent the requested choices.
- [ ] Add `NotificationDNDState`, keep the old boolean key as a compatibility mirror, make prompt suppression depend on active DND, and add 2h/8h/24h/custom/until-disabled controls without deleting scheduled settings.
- [ ] Apply synced DND state on foreground/cloud merge and run cloud/notification tests.

### Task 5: Appearance image and material preferences

**Files:**
- Modify: `Haiity/Theme.swift`
- Modify: `Haiity/Models/HabitStore.swift`
- Modify: `Haiity/Views/MoreView.swift`
- Modify: `Haiity/Views/ContentView.swift`
- Modify: `Haiity/Views/HabitCard.swift`
- Modify: `Haiity/Views/ReminderRow.swift`
- Modify: `Haiity/Views/GitHubContributionCard.swift`
- Modify: `HaiityTests/ThemeAndPaletteTests.swift`
- Modify: `HaiityTests/CloudSyncTests.swift`

- [ ] Add failing round-trip/merge tests for material mode and bounded background image data.
- [ ] Run them to confirm the fields are not currently persisted.
- [ ] Add `AppearanceMaterial` and bounded `AppearancePreferences`, `PhotosPicker` selection, image removal, and root/card surface rendering for solid, milky, and liquid glass modes with contrast overlays.
- [ ] Run persistence tests and launch the app in light/dark modes to inspect Darstellung, list cards, and readability screenshots.

### Task 6: Verification and release gate

**Files:**
- Modify: `HaiityTests/...` only where a regression test needs correction.
- Do not modify unrelated release artifacts.

- [ ] Run the targeted test set for every task.
- [ ] Run the repository release test gate from `tools/release.sh` without uploading.
- [ ] Launch the simulator, inspect the editor, main reminder widget preview, More/DND, sync hints, and Darstellung in light/dark appearances.
- [ ] Report any external TestFlight/App Store state as unverified unless directly confirmed.
