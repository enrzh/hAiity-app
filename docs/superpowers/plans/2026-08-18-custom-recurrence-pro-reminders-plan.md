# Custom One-Time Reminders and Pro Reminders Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a first-class one-time `Custom` reminder flow, remove obsolete end-title editing, and prove Apple Reminders sync is Pro-only.

**Architecture:** Extend `Recurrence.Frequency` with `.once` and keep all scheduling behavior in `Recurrence.Schedule`. `RecurrenceDraft` and `EditHabitSheet` map the native date picker to `.once` and `HabitItemType.reminder`; Calendar and Apple Reminders consume the existing `CalendarEventPlan`/`ReminderSyncPlan` APIs. Keep persisted `endTitle` decoding for compatibility but stop exposing or writing it from the editor.

**Tech Stack:** Swift, SwiftUI, EventKit, StoreKit, XCTest, Swift Package/Xcode project scripts already present in the repository.

## Global Constraints

- `Custom` appears before `Täglich` and creates exactly one scheduled day.
- Selecting `Custom` automatically changes the item type to `Erinnerung`.
- End-date and end-count controls remain for recurring entries but never show `Kategorie / Endtitel`.
- Apple Calendar and Apple Reminders enable paths require `Pro.isUnlocked`; disabling stays available.
- Existing recurrence JSON and existing `endTitle` data remain decodable.
- The existing `$9.99` non-consumable `com.aiity.haiity.pro` product remains unchanged; no subscription is added.
- Do not modify unrelated `tools/release.sh`, `.superpowers/brainstorm/`, or generated `build/` changes.

---

### Task 1: Add one-time recurrence semantics

**Files:**
- Modify: `Haiity/Models/Recurrence.swift`
- Modify: `Haiity/Models/RecurrenceText.swift`
- Test: `HaiityTests/RecurrenceTests.swift`
- Test: `HaiityTests/RecurrenceTextTests.swift`

**Interfaces:**
- `Recurrence.Frequency.once` is the persisted Codable value for one-time rules.
- `.once` uses `start` as its selected day and exposes no recurring sub-rule.
- `Recurrence.Schedule` returns only that day from `isScheduled`, `occurrences`, and `nextOccurrence`.

- [ ] **Step 1: Write failing recurrence tests** for `.once` matching, next occurrence before/after the date, one-item enumeration, Codable round-trip, and malformed/missing start behavior.
- [ ] **Step 2: Run `xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:HaiityTests/RecurrenceTests -only-testing:HaiityTests/RecurrenceTextTests CODE_SIGNING_ALLOWED=NO` and confirm the new tests fail before implementation.
- [ ] **Step 3: Implement `.once`** in the frequency enum, normalization, schedule matching/search, and Codable/migration switches. Ensure `.once` cannot inherit an end condition or flexible target.
- [ ] **Step 4: Add one-time German/English summary text** and update frequency switch exhaustiveness without changing recurring copy.
- [ ] **Step 5: Run recurrence and text tests** and confirm they pass.
- [ ] **Step 6: Commit** with `feat: add one-time recurrence rules`.

### Task 2: Map the Custom editor flow

**Files:**
- Modify: `Haiity/Models/RecurrenceDraft.swift`
- Modify: `Haiity/Views/EditHabitSheet.swift`
- Test: `HaiityTests/RecurrenceTextTests.swift`
- Test: `HaiityTests/HabitTimeTests.swift`

**Interfaces:**
- `RecurrenceDraft` maps `.once` to the selected `Date` and round-trips it without creating an end rule.
- `EditHabitSheet` renders the segmented order `once, daily, weekly, monthly, yearly`.

- [ ] **Step 1: Add failing draft/editor contract tests** asserting `.once` round-trips its date, `Custom` is present before `Täglich`, and `end-title` is absent while `end-date`/`end-count` remain.
- [ ] **Step 2: Run `xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:HaiityTests/RecurrenceTextTests -only-testing:HaiityTests/HabitTimeTests CODE_SIGNING_ALLOWED=NO` and confirm failure.
- [ ] **Step 3: Extend `RecurrenceDraft`** with a one-time date path; clear recurring-only state when building `.once`, and make switching away restore normal recurring controls.
- [ ] **Step 4: Update `EditHabitSheet.recurrenceSection`** to show `Custom` first, render a native compact `DatePicker`, automatically set `itemType = .reminder`, hide recurring controls for `.once`, and remove both end-title `TextField`s.
- [ ] **Step 5: Ensure save passes no new end title** while existing model decoding remains intact.
- [ ] **Step 6: Run the focused editor/draft tests** and commit with `feat: add custom one-time reminder editor`.

### Task 3: Support one-time native Calendar and Reminders plans

**Files:**
- Modify: `Haiity/Services/CalendarSync.swift`
- Modify: `Haiity/Services/ReminderSync.swift`
- Test: `HaiityTests/CalendarSyncTests.swift`
- Test: `HaiityTests/ReminderSyncTests.swift`

**Interfaces:**
- `CalendarEventPlan(habit:today:calendar:)` produces one plan for `.once` with no recurrence rule.
- `ReminderSyncPlan` continues to use `CalendarEventPlan` and the shared occurrence engine.

- [ ] **Step 1: Add failing Calendar tests** asserting a `.once` reminder starts on its selected day, has no recurrence rule, and does not create a future recurring occurrence.
- [ ] **Step 2: Run `xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:HaiityTests/CalendarSyncTests -only-testing:HaiityTests/ReminderSyncTests CODE_SIGNING_ALLOWED=NO` and confirm the new tests fail.
- [ ] **Step 3: Update EventKit mapping** so `.once` uses a single event/reminder and does not pass an `EKRecurrenceRule`; preserve end dates and per-item opt-out for recurring rules.
- [ ] **Step 4: Compile and run CalendarSyncTests and ReminderSyncTests**; fix only exhaustiveness or one-time plan handling required by the new frequency.
- [ ] **Step 5: Commit** with `feat: sync one-time reminders to native apps`.

### Task 4: Lock down the Apple Reminders Pro boundary

**Files:**
- Modify: `Haiity/Services/CalendarSync.swift`
- Modify: `Haiity/Views/MoreView.swift`
- Test: `HaiityTests/CalendarSyncTests.swift`
- Test: `HaiityTests/ReminderSyncTests.swift`
- Test: `HaiityTests/ProGateTests.swift`

**Interfaces:**
- Both native Calendar and Apple Reminders enable operations must call the same Pro gate before requesting EventKit access.
- Turning either feature off must never present the paywall or require Pro.

- [ ] **Step 1: Add/adjust contract tests** for free enable rejection, Pro enable acceptance, and free disable behavior for the Apple Reminders toggle.
- [ ] **Step 2: Run `xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:HaiityTests/CalendarSyncTests -only-testing:HaiityTests/ReminderSyncTests -only-testing:HaiityTests/ProGateTests CODE_SIGNING_ALLOWED=NO` and confirm any missing contract fails.
- [ ] **Step 3: Keep or minimally refactor the existing `CalendarFeatureGate` path** so Apple Reminders remains Pro-only without adding a second entitlement source or changing sync ownership.
- [ ] **Step 4: Run the same gate command again and commit with `test: enforce Pro gate for native reminders`.

### Task 5: Full verification and release-readiness check

**Files:**
- No source changes expected.

- [ ] **Step 1: Run `tools/release.sh` with `DEVELOPER_DIR` set to the public Xcode; this regenerates the project, runs the complete `HaiityTests` suite, and enforces the repository test floor.
- [ ] **Step 2: Run `git diff --check` and inspect `git diff --stat`**.
- [ ] **Step 3: Verify `Haiity.storekit` still contains one non-consumable `$9.99` product and no subscription products.
- [ ] **Step 4: Build with `tools/release.sh` on supported non-beta macOS/Xcode; do not claim TestFlight status from local build metadata.
- [ ] **Step 5: Commit any final test-only corrections separately and report live App Store pricing as unverified unless App Store Connect is checked directly.
