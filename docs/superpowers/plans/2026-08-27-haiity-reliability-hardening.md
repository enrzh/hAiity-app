# hAiity Reliability Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the current hAiity feature set dependable by enforcing Pro limits consistently, making native sync idempotent, and removing avoidable notification, interaction, and startup instability.

**Architecture:** Keep the existing `HabitStore`, `ProGate`, `CalendarSync`, `ReminderSync`, and `StartupSplashView` boundaries. Add only small pure helpers or state transitions where an existing type already owns the behavior; do not introduce new managers or service layers. Each change gets a focused regression test before integration.

**Tech Stack:** Swift 5.9, SwiftUI, StoreKit 2, EventKit, UserNotifications, WidgetKit, XCTest, XcodeGen.

## Global Constraints

- Preserve the current German-first localization and visible product name `hAiity`.
- Keep the free tracked-habit limit at three; reminders remain free; family sharing stays unavailable.
- Preserve existing iCloud payload compatibility and do not discard user data during repair or migration.
- Native Calendar and Reminders entries must remain hAiity-owned and idempotent; never recreate a duplicate after a failed cleanup.
- Use only the connected physical iPhone Air for device verification; do not use the device hub or simulator.
- Use the existing test/build scripts and do not increment the repository build number unless a release build requires it.
- Keep all edits ASCII unless an existing localized source file requires otherwise.

---

### Task 1: Make Pro entitlement and feature gates reactive

**Files:**
- Modify: `Haiity/Models/ProEntitlement.swift`
- Modify: `Haiity/Models/HabitStore.swift`
- Modify: `Haiity/HaiityApp.swift`
- Modify: existing gated call sites only where the audit finds a missing `Pro.isUnlocked`/`ProGate` check
- Test: `HaiityTests/ProGateTests.swift`

**Interfaces:**
- Preserve `Pro.isUnlocked`, `ProStatus.shared`, `ProGate.visibleActiveHabits`, and `ProGate.mayUseProFeature` as the public gate surface.
- Add no second entitlement source. Any newly found gated call site must use the existing gate.

- [x] **Step 1: Add failing pure tests** for expired Pro visibility, native-sync restrictions, and a gate transition observed by an existing `ProStatus` observer.
- [x] **Step 2: Run the focused Pro tests** and confirm the new assertions fail for the missing call-site behavior.
- [x] **Step 3: Update only the existing entitlement refresh/cache path and missing call sites** so revocation/expiry immediately publishes the locked state and disables all paid paths, while preserving owner-device and debug behavior.
- [x] **Step 4: Run `xcodebuild test` for `HaiityTests/ProGateTests.swift`** and the existing StoreKit-independent gate tests.
- [x] **Step 5: Commit:** `fix: enforce reactive pro gates across paid features`

---

### Task 2: Make Calendar and Reminders synchronization idempotent

**Files:**
- Modify: `Haiity/Services/CalendarSync.swift`
- Modify: `Haiity/Services/ReminderSync.swift`
- Modify: `Haiity/Services/SyncWatermark.swift`
- Modify: `Haiity/Services/NativeSyncInstallation.swift` only if the existing installation flow needs the shared marker
- Test: `HaiityTests/CalendarSyncTests.swift`
- Test: `HaiityTests/ReminderSyncTests.swift`

**Interfaces:**
- Keep the existing native sync entry points and EventKit types.
- Preserve the existing watermark/category format and make cleanup/setup safe to retry.
- A cleanup pass must identify hAiity-owned entries by the existing invisible marker/category, not by an unsafe broad title match alone.

- [x] **Step 1: Add failing tests** proving repeated setup produces one owned calendar event/reminder per logical item, cleanup is retryable after a partial failure, and stale legacy entries are removed before recreation.
- [x] **Step 2: Run the focused Calendar and Reminder tests** and confirm the duplicate scenarios fail.
- [x] **Step 3: Centralize only the existing marker lookup/update logic** so setup first reconciles owned identifiers, deletes stale duplicates deterministically, and writes one current entry per habit/reminder.
- [x] **Step 4: Add explicit no-op behavior for denied/unavailable EventKit stores** so a failed cleanup never falsely reports success or proceeds to duplicate creation.
- [ ] **Step 5: Run the focused sync tests plus the full unit suite.** The current host has no safe non-simulator destination for the source-contract suite; the physical-safe subset passed on the approved iPhone, while this host/CI-only coverage remains pending.
- [x] **Step 6: Commit:** `fix: make native sync retryable and duplicate-free`

---

### Task 3: Stabilize interaction and notification behavior

**Files:**
- Modify: `Haiity/Views/HabitCard.swift`
- Modify: `Haiity/Views/ReminderRow.swift`
- Modify: `Haiity/Views/StatsView.swift`
- Modify: `Haiity/Services/NotificationPresenter.swift`
- Modify: `Haiity/Services/Reminders.swift`
- Test: `HaiityTests/InteractionTests.swift`
- Test: `HaiityTests/NotificationActionTests.swift`
- Test: `HaiityUITests/StatsContextMenuUITests.swift` only for assertions that remain deterministic

**Interfaces:**
- Keep the established interaction contract: tap changes state, hold opens the menu, swipe actions are explicit, and drag reordering is available only in sorting mode.
- Keep the current quick-action slot model; expose zero to three configured actions without inventing another settings model.

- [x] **Step 1: Add failing tests** for the three quick-action slots, undo visibility before a decision, no drag outside sorting mode, and one enlarged preview host at a time.
- [x] **Step 2: Run the focused interaction and notification tests.**
- [x] **Step 3: Fix the smallest gesture ownership and notification scheduling paths** so source cards do not render a second shadow/drag layer and notification actions match the saved configuration.
- [x] **Step 4: Run focused tests and inspect the existing physical-device smoke path without replacing the TestFlight bundle.**
- [x] **Step 5: Commit:** `fix: stabilize card interactions and notification actions`

---

### Task 4: Reduce startup work and unify appearance readiness

**Files:**
- Modify: `Haiity/HaiityApp.swift`
- Modify: `Haiity/Views/StartupSplashView.swift`
- Modify: `Haiity/Theme.swift` only for existing background-cache/readability integration
- Test: `HaiityTests/StartupSplashTests.swift`
- Test: `HaiityTests/ThemeAndPaletteTests.swift`

**Interfaces:**
- Keep the current three-graph vertical splash concept and reduce-motion behavior.
- Keep `AppearanceImageCache` as the only image decode/cache path.
- The first usable content frame must not wait on a duplicate image decode or an unbounded animation task.

- [x] **Step 1: Add failing timing/state tests** for cancellation, content handoff, reduced motion, and image-mode startup not retaining stale splash work.
- [x] **Step 2: Run the focused startup/theme tests.**
- [x] **Step 3: Remove duplicate main-thread work and make the splash-to-content handoff await only the already-started prewarm task.**
- [x] **Step 4: Run the focused tests and verify a release build compiles with the current asset catalog.**
- [x] **Step 5: Commit:** `perf: tighten startup splash and background handoff`

---

### Task 5: Integration, release, and physical-device verification

**Files:**
- Modify: only files required by review findings or build metadata; do not touch unrelated untracked planning files.
- Test: all existing `HaiityTests` and deterministic `HaiityUITests` that can run without replacing the TestFlight app.

- [x] **Step 1: Review each task commit and resolve Critical/Important findings.**
- [x] **Step 2: Run `xcodegen generate` and the physical-safe release gate from `tools/release.sh` without uploading.** The complete source-contract suite remains a host/CI responsibility because those tests read the Mac checkout and cannot execute from the iPhone bundle.
- [x] **Step 3: Build/archive and verify app/widget bundle versions, entitlement keys, icon assets, and widget inclusion from the archive.**
- [x] **Step 4: Verify the connected physical iPhone Air with a development-signed smoke export from the exact archive, launch hAiity, and run the physical-safe test subset.** The App Store shipping IPA is intentionally not installed on-device because its App Store beta profile is not device-installable (`0xe800801f`).
- [ ] **Step 5: Upload through the supported Xcode Cloud/TestFlight path only when the release machine accepts it; report upload, processing, and installability as separate states.** The local beta macOS host correctly refuses this irreversible step.
- [x] **Step 6: Commit the final verified reliability changes:** `fix: finish hAiity reliability hardening`

**Verified locally:** build `1.0.0 (108)` archived and exported successfully; the shipping IPA is at `/tmp/haiity-release-reliability-final/export/Haiity.ipa`, the development smoke export was installed and launched on the approved iPhone Air, and 20 physical-safe tests passed. Upload remains pending until Xcode Cloud or a release-macOS host is used.

## Completion Criteria

- Pro expiry/revocation locks every paid feature without requiring an app restart.
- Repeated native setup/cleanup converges to one hAiity-owned entry per item and remains retryable after failure.
- Card hold/swipe/drag and notification quick actions follow one deterministic configuration.
- Startup does not duplicate background-image decoding or delay first usable content unnecessarily.
- The physical-safe tests and archive verification pass, and the physical iPhone check names the development smoke build derived from the exact archived source. The full host unit suite and Xcode Cloud/TestFlight processing remain separate pending gates.
