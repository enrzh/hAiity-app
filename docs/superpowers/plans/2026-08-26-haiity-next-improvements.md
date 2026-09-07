# hAiity Next Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make hAiity dependable for daily use and release, with trustworthy native sync, complete Pro enforcement, durable iCloud state, fast startup, and type-correct widgets.

**Architecture:** Keep the existing local-first JSON store, App Group widget data, CloudKit mirror, EventKit marker model, and centralized `Pro.isUnlocked`/`ProGate` policy. Fix behavior at those existing boundaries instead of adding managers, a backend, or a broad view-layer refactor. Every slice gets pure tests first, then one physical-phone verification pass.

**Tech Stack:** Swift 5.9, SwiftUI, StoreKit 2, CloudKit, EventKit, UserNotifications, WidgetKit/App Intents, ActivityKit, XCTest, XcodeGen, Xcode Cloud.

## Global Constraints

- Preserve all existing uncommitted work; do not reset, clean, or overwrite unrelated files.
- Test runtime behavior only on `詹。手机air` (`00008150-000120AC0287801C`); do not create or use simulator/device-hub coverage for this milestone.
- Keep hAiity serverless. Automatic Live Activity startup after termination is not available with local notifications; do not add a backend unless this product decision changes explicitly.
- Keep the current App Store product and family-sharing-disabled policy unchanged until App Store Connect is separately verified.
- Keep all user data local-first and merge-safe; a failed CloudKit or EventKit operation must not silently delete local data.
- Avoid new Manager/Service/Factory/Protocol layers unless an existing file already has multiple real implementations that require one.
- Release only through Xcode Cloud from a release-supported macOS/Xcode environment; never report TestFlight success from a local beta-macOS build.

## Priority Order

1. Native calendar/reminder correctness and recovery.
2. Complete Pro expiry enforcement.
3. iCloud persistence and conflict durability.
4. Startup/background-image performance.
5. Widget behavior and deep links.
6. Notification and Live Activity reliability.
7. Accessibility, localization, appearance consistency, and release hardening.

---

### Task 1: Finish and Prove Native Sync Is Idempotent

**Files:**
- Modify: `Haiity/Services/CalendarSync.swift`
- Modify: `Haiity/Services/ReminderSync.swift`
- Modify: `Haiity/Services/SyncWatermark.swift`
- Modify: `Haiity/Services/NativeSyncInstallation.swift`
- Test: `HaiityTests/CalendarSyncTests.swift`
- Test: `HaiityTests/ReminderSyncTests.swift`

**Deliverable:** Re-running reconciliation, reinstall recovery, external deletion, and duplicate cleanup leave exactly one hAiity-owned calendar series/reminder per active item and never touch unrelated native entries.

- [ ] Review the existing dirty sync diff before changing it; identify which behavior is already implemented and preserve it.
- [ ] Add pure tests for two identical owned entries, a legacy marker, a stored native identifier pointing to the wrong item, and a failed cleanup pass.
- [ ] Ensure canonical selection is deterministic and that the retained native object is reused by the same reconciliation pass.
- [ ] Return enough success/failure state for the UI to show retryable cleanup status; replace only sync-related silent failures, not unrelated error handling.
- [ ] Run focused tests with `xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/CalendarSyncTests -only-testing:HaiityTests/ReminderSyncTests`.
- [ ] On the physical phone, run cleanup, reconcile twice, edit one item, delete one native item, and reinstall/recover. Verify no duplicate is created and unrelated entries remain.

**Acceptance:** Two consecutive reconciliation passes are stable; the cleanup result is visible; the phone contains one owned object per active item after recovery.

### Task 2: Apply One Pro Policy to Every Pro Entry Point

**Files:**
- Modify: `Haiity/Models/ProEntitlement.swift`
- Modify: `Haiity/Models/HabitStore.swift`
- Modify: `Haiity/HaiityApp.swift`
- Modify: every view or service found by the Pro-gate audit, initially `Haiity/Views/ContentView.swift`, `Haiity/Views/StatsView.swift`, `Haiity/Views/MoreView.swift`, `Haiity/Views/ArchiveView.swift`, `Haiity/Views/EditHabitSheet.swift`, `Haiity/Services/CalendarSync.swift`, and `Haiity/Services/ReminderSync.swift`
- Test: `HaiityTests/ProGateTests.swift`

**Deliverable:** An expired or revoked Pro entitlement immediately relocks every Pro-only function and exposes at most three active tracked habits while preserving stored over-limit data.

- [ ] Inventory every Pro-only screen, toggle, action, import path, archive/restore path, widget configuration path, and EventKit write path with `rg -n "Pro\.isUnlocked|unlocked|Paywall|calendarSync|nativeReminderSync|freeHabitLimit" Haiity HaiityWidget`.
- [ ] Route each decision through the existing `ProGate` methods; do not introduce per-view copies of the three-habit limit.
- [ ] Confirm the foreground entitlement refresh updates all observable gates immediately and that a revoked purchase cannot leave calendar/reminder writes enabled.
- [ ] Add a matrix covering locked/unlocked, 0/2/3/4 tracked habits, new item, edit item, archive restore, import, calendar sync, native reminder sync, and statistics.
- [ ] Run `xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/ProGateTests`.
- [ ] On the physical phone, toggle the debug entitlement off in a debug build while each gated page is open and verify the paywall/limit appears without restarting.

**Acceptance:** No Pro-only action succeeds while locked, the visible active tracked roster is three items, and reactivation reveals preserved items without data loss.

### Task 3: Make iCloud State Observable and Merge-Safe

**Files:**
- Modify: `Haiity/Services/CloudSync.swift`
- Modify: `Haiity/Models/HabitStore.swift`
- Modify: `Haiity/Theme.swift` (`AppearancePreferences`)
- Test: `HaiityTests/CloudSyncTests.swift`
- Test: `HaiityTests/StoreAndMergeTests.swift`

**Deliverable:** Appearance, background image mode, per-habit settings, recurrence, timezone, notification preferences, and native-sync intent survive delayed writes, conflicts, account changes, and app relaunches.

- [ ] Add fake-store tests for no iCloud account, temporary CloudKit failure, malformed remote payload, newer remote appearance data, and a local write occurring while a remote fetch is in flight.
- [ ] Verify appearance slice freshness and habit/check-in freshness cannot overwrite each other when their timestamps differ.
- [ ] Replace silent persistence failures on the user-visible save path with a recorded sync state and a retry on foreground; keep local writes successful even when CloudKit is unavailable.
- [ ] Bound background-image payload size before local and CloudKit writes and verify selecting a non-image mode clears stale image bytes.
- [ ] Run `xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/CloudSyncTests -only-testing:HaiityTests/StoreAndMergeTests`.
- [ ] On the physical phone, change appearance and a habit offline, terminate/relaunch, reconnect iCloud, and verify the final local state remains intact.

**Acceptance:** Every synced setting has a deterministic merge rule, failed remote writes are retryable and visible, and no local setting disappears after an iCloud delay.

### Task 4: Decouple Startup Animation From Image and Graph Work

**Files:**
- Modify: `Haiity/HaiityApp.swift`
- Modify: `Haiity/Models/StartupSplash.swift`
- Modify: `Haiity/Views/StartupSplashView.swift`
- Modify: existing appearance/image-cache code where it currently lives
- Test: `HaiityTests/StartupSplashTests.swift`
- Test: `HaiityTests/GesturePerfTests.swift` if the existing performance harness covers launch work

**Deliverable:** The splash remains smooth and full-screen, while the first app frame is not delayed by a large background-image decode or graph construction.

- [ ] Measure launch on the physical phone with no image, a small image, and the largest supported image; record time from process start to interactive content.
- [ ] Decode and resize the background once off the main rendering path, cache the prepared image, and let the splash use its own fixed launch asset.
- [ ] Keep the app tree mounted under the splash, but avoid rebuilding ContentView or contribution graphs during the animation handoff.
- [ ] Add cancellation and memory-release behavior for the prewarm task so a second launch or background transition cannot retain multiple image buffers.
- [ ] Preserve reduced-motion behavior and verify the animation covers the entire safe-area configuration.
- [ ] Run `xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/StartupSplashTests` and repeat the three physical launch measurements.

**Acceptance:** No visible frame drop during the splash, no image-dependent launch stall, and the first interactive frame appears at the same point for all background modes.

### Task 5: Complete Widget Type and Navigation Coverage

**Files:**
- Modify: `HaiityWidget/WidgetLogic.swift`
- Modify: `HaiityWidget/HaiityWidgetView.swift`
- Modify: `HaiityWidget/RosterWidgetView.swift`
- Modify: `HaiityWidget/GraphWidgetView.swift`
- Modify: `HaiityWidget/HaiityWidget.swift`
- Modify: relevant App Intent files under `Haiity/Intents/`
- Test: `HaiityTests/WidgetLogicTests.swift`
- Test: `HaiityTests/WidgetRenderingTests.swift`
- Test: `HaiityTests/GitHubWidgetTests.swift`

**Deliverable:** Habit widgets correctly represent checkbox, yes/no, quantity, reminder, reset, and GitHub states; graph widgets never resolve reminders; tapping a specific widget opens the corresponding habit/reminder location.

- [ ] Add pure cases for open/done/no/yes/partial/full-quantity, reminder due/not-due, reset enabled/disabled, archived item, missing selected item, and empty GitHub data.
- [ ] Verify each widget family has stable layout bounds, readable status text, correct palette/custom color, and no forbidden icon for a valid GitHub cache.
- [ ] Make widget actions write through the shared store, update notification/native sync state where applicable, and reload the correct timelines.
- [ ] Make deep links carry the selected item ID and have ContentView scroll to that item after launch or tab restoration.
- [ ] Run `xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/WidgetLogicTests -only-testing:HaiityTests/WidgetRenderingTests -only-testing:HaiityTests/GitHubWidgetTests`.
- [ ] Add and configure one widget of each supported family on the physical phone and verify all interactions after a cold app launch.

**Acceptance:** Widget presentation matches item type, actions are reversible when enabled, GitHub has its own valid rendering path, and deep links land on the selected item.

### Task 6: Harden Notifications and Define the Live Activity Boundary

**Files:**
- Modify: `Haiity/Services/Reminders.swift`
- Modify: `Haiity/Services/NotificationPresenter.swift`
- Modify: `Haiity/Services/MotivationActivityManager.swift`
- Modify: `Haiity/Models/MotivationActivity.swift`
- Test: `HaiityTests/NotificationActionTests.swift`
- Test: `HaiityTests/MotivationTests.swift`
- Test: `HaiityTests/MotivationActivityTests.swift`

**Deliverable:** Per-item reminders, DND windows, configurable quick actions, timezone/end-date rules, and motivation delivery remain consistent after edits, missed launches, and external check-ins.

- [ ] Build a deterministic notification-plan test for each habit/reminder timezone, recurrence end date, disabled notification, DND mode, and reschedule after completion.
- [ ] Verify quick-action slots can be empty, map to the configured actions, and expose the same reset policy as swipe/hold actions.
- [ ] Reconcile pending notifications after widget actions, native reminder changes, app foreground, and date/timezone changes; log user-visible failures instead of silently dropping them.
- [ ] Keep `Activity.request(..., pushType: nil)` as the serverless path. Document that a terminated app cannot start a Live Activity from a local notification; use the notification fallback until a backend is explicitly approved.
- [ ] Run `xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/NotificationActionTests -only-testing:HaiityTests/MotivationTests -only-testing:HaiityTests/MotivationActivityTests`.
- [ ] On the physical phone, test a scheduled habit notification, hold actions, DND expiry, and a motivation delivery after a force-quit.

**Acceptance:** No stale notification remains after a completion, a configured action always resolves to the correct item, and the app does not promise impossible terminated-state Live Activity behavior.

### Task 7: Polish the Product Surface After Reliability Is Green

**Files:**
- Modify: `Haiity/Views/MoreView.swift`
- Modify: `Haiity/Views/ReminderSetupView.swift`
- Modify: `Haiity/Views/HabitCard.swift`
- Modify: `Haiity/Views/StatsView.swift`
- Modify: `Haiity/Theme.swift`
- Modify: `Haiity/Localizable.xcstrings`
- Test: `HaiityTests/ThemeAndPaletteTests.swift`
- Test: `HaiityTests/SetupFlowTests.swift`
- Test: `HaiityTests/FollowUpFixTests.swift`

**Deliverable:** More, setup, stats, search, cards, and settings use the selected Solid/Milky Glass/Liquid Glass/Self-adjust appearance without squished controls or unreadable text.

- [ ] Audit each page for one consistent surface treatment, continuous header blur, stable row heights, and correct safe-area/toast layering.
- [ ] Add Dynamic Type, VoiceOver labels, contrast, reduced-motion, and German/English string checks for the settings and setup flows.
- [ ] Keep background mode controls native and ensure `Bild auswählen` appears only for image mode; retain the developer-only force reset path as a recovery tool, not a normal user workflow.
- [ ] Verify enlarged cards use one visible rounded surface and one shadow, with no source-card halo, clipping, or sibling disappearance.
- [ ] Run `xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/ThemeAndPaletteTests -only-testing:HaiityTests/SetupFlowTests -only-testing:HaiityTests/FollowUpFixTests` and inspect every affected screen on the physical phone.

**Acceptance:** No settings page looks like a different design system, content remains readable at large text sizes, and all long-press/enlarged surfaces stay complete and isolated.

### Task 8: Release and Regression Gate

**Files:**
- Modify: `project.yml` only for the intentional app/widget build bump
- Modify: `tools/release.sh` only when the measured test floor changes
- Test: the full `HaiityTests` target

**Deliverable:** A reproducible release candidate is built, verified, uploaded by Xcode Cloud, and assigned to the intended TestFlight groups without using the device hub.

- [ ] Review and commit the current native-sync and preview fixes separately from any new task changes.
- [ ] Run the full test target on the physical phone, confirm the executed count is at least the release floor in `tools/release.sh`, and inspect failures rather than raising the floor to hide them.
- [ ] Build the app and widget with matching version/build numbers and verify the bundle icon, privacy manifest, entitlements, GitHub client ID, and widget extension.
- [ ] Push `main` and start an Xcode Cloud release workflow from the release-supported environment.
- [ ] Wait for processing, confirm the build in App Store Connect, assign `Internal` and `Preview`, and report the observed status as accepted, processing, or available.
- [ ] Run `tools/cleanup-dev-artifacts.sh` after the release; it may remove unavailable simulator profiles and hAiity temporary output only, never active devices or other projects.

**Acceptance:** The release has matching app/widget metadata, full test evidence, an observed Xcode Cloud/App Store Connect result, and no cleanup of the user’s other devices or repositories.

## Deliberate Non-Goals

- Do not add a server solely to force-start a motivation Live Activity while the app is terminated.
- Do not redesign the data model or split large existing SwiftUI files unless a failing test proves it is required.
- Do not add more widget families until the existing families pass type-aware and physical-phone verification.
- Do not optimize for device-hub coverage; the required runtime evidence is the user’s physical phone.

## Self-Review

- Native duplicate prevention, Pro expiry, iCloud persistence, startup performance, widgets, notifications, appearance, and release evidence each have an explicit task.
- Every task names existing files and focused tests; no new abstraction layer is required.
- The Live Activity limitation and release-environment constraint are explicit, so the plan does not promise behavior iOS cannot provide in this serverless architecture.
