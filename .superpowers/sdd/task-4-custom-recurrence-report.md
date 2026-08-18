# Task 4 Custom Recurrence Report

## Status

- Date: 2026-08-18
- Task: Task 4 - Lock down the Apple Reminders Pro boundary
- Outcome: Completed
- Accepted starting head: `d61c74615a237be31fedc3af6830a1b3e268fed1`
- Final commit: `963b09d`
- Production source changed: no
- Scope kept: yes

## Requirements Check

- Verified the Apple Reminders toggle is gated by the same `CalendarFeatureGate` path as Apple Calendar in `MoreView`.
- Verified the gate sits before `ReminderSync.requestAccess()`.
- Verified disabling remains free and runs before the Pro gate.
- Kept the owned hAiity list and reminder sync behavior unchanged.
- Added focused tests for free enable rejection, Pro enable acceptance, and the `MoreView` binding/resume contract.

## Files Changed

- `HaiityTests/CalendarSyncTests.swift`
- `HaiityTests/ReminderSyncTests.swift`
- `HaiityTests/ProGateTests.swift`

## Files Intentionally Not Changed

- `Haiity/Views/MoreView.swift`
- `Haiity/Services/CalendarSync.swift`
- `Haiity/Services/ReminderSync.swift`
- `tools/release.sh`
- `build/`
- `.superpowers/brainstorm/`

## Commands Run

1. Read task brief

```sh
sed -n '1,220p' /Users/enrico/Documents/GitHub/haiity/.superpowers/sdd/task-4-custom-brief.md
```

Result:

- Confirmed Task 4 is test-first, gate-focused, and requests commit message `test: enforce Pro gate for native reminders`.

2. Inspected current implementation and test coverage

```sh
sed -n '1,260p' /Users/enrico/Documents/GitHub/haiity/Haiity/Services/CalendarSync.swift
sed -n '1,260p' /Users/enrico/Documents/GitHub/haiity/Haiity/Views/MoreView.swift
sed -n '1,260p' /Users/enrico/Documents/GitHub/haiity/HaiityTests/CalendarSyncTests.swift
sed -n '1,260p' /Users/enrico/Documents/GitHub/haiity/HaiityTests/ReminderSyncTests.swift
sed -n '1,420p' /Users/enrico/Documents/GitHub/haiity/HaiityTests/ProGateTests.swift
sed -n '420,515p' /Users/enrico/Documents/GitHub/haiity/Haiity/Views/MoreView.swift
sed -n '620,740p' /Users/enrico/Documents/GitHub/haiity/Haiity/Views/MoreView.swift
sed -n '980,1045p' /Users/enrico/Documents/GitHub/haiity/Haiity/Views/MoreView.swift
sed -n '1,260p' /Users/enrico/Documents/GitHub/haiity/Haiity/Services/ReminderSync.swift
```

Result:

- Confirmed existing source already satisfies the requested Pro gate behavior.
- Confirmed the remaining gap was focused contract coverage, not production logic.

3. Resolved the concrete simulator id

```sh
xcrun simctl list devices available
```

Result:

- Used `iPhone 17 Pro Max` simulator id `88C5F8D5-8924-4600-BDE1-22C88910EADA`.

4. Ran focused verification suite on the concrete simulator id

```sh
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=88C5F8D5-8924-4600-BDE1-22C88910EADA' -only-testing:HaiityTests/CalendarSyncSelectionTests -only-testing:HaiityTests/ReminderSyncContractTests -only-testing:HaiityTests/ProGateTests CODE_SIGNING_ALLOWED=NO
```

Result:

- Exit code: `0`
- Summary: `Executed 42 tests, with 0 failures (0 unexpected)`
- xcresult: `/Users/enrico/Library/Developer/Xcode/DerivedData/Haiity-ffgpooiauxelhgdxgvouhoqoqoeb/Logs/Test/Test-Haiity-2026.08.18_20-35-59-+0200.xcresult`

5. Self-review

```sh
git -C /Users/enrico/Documents/GitHub/haiity diff -- HaiityTests/CalendarSyncTests.swift HaiityTests/ReminderSyncTests.swift HaiityTests/ProGateTests.swift
git -C /Users/enrico/Documents/GitHub/haiity status --short
git -C /Users/enrico/Documents/GitHub/haiity rev-parse HEAD
```

Result:

- Verified only the three intended test files were modified before adding this report.
- Verified unrelated dirty items remained untouched.
- Confirmed starting HEAD was `d61c74615a237be31fedc3af6830a1b3e268fed1`.

## Test Changes

### `HaiityTests/ReminderSyncTests.swift`

- Added a focused contract test for the `reminderSyncBinding` block in `MoreView`.
- Verifies:
  - `ReminderSync.disable()` runs in the free disable path.
  - The shared `CalendarFeatureGate` is checked before `ReminderSync.requestAccess()`.
  - Free enable rejection lands in `paywall = .calendar`.
  - `pendingNativeReminder` is set for post-purchase resume.

### `HaiityTests/CalendarSyncTests.swift`

- Added a binding contract test for the Reminder toggle in `MoreView`.
- Verifies:
  - The toggle is wired through `reminderSyncBinding`.
  - Successful purchase resume uses `reminderSyncBinding.wrappedValue = true`.
  - Resume does not bypass the binding contract.

### `HaiityTests/ProGateTests.swift`

- Tightened the native reminder sync gate test with explicit free/pro `CalendarFeatureGate` assertions.

## Concerns

- The implementation already matched Task 4, so there was no legitimate production fix to make without inventing churn.
- Coverage remains intentionally contract-based for the SwiftUI binding path because the task asked to preserve the single entitlement source and existing sync ownership behavior.

6. Created the requested commit

```sh
git -C /Users/enrico/Documents/GitHub/haiity add HaiityTests/CalendarSyncTests.swift HaiityTests/ReminderSyncTests.swift HaiityTests/ProGateTests.swift .superpowers/sdd/task-4-custom-recurrence-report.md
git -C /Users/enrico/Documents/GitHub/haiity commit -m 'test: enforce Pro gate for native reminders'
```

Result:

- Commit created: `963b09d`
- Subject: `test: enforce Pro gate for native reminders`

## Fix Section

7. Added the failing pure-action tests first

```sh
xcodebuild test -project /Users/enrico/Documents/GitHub/haiity/Haiity.xcodeproj -scheme Haiity -destination 'id=88C5F8D5-8924-4600-BDE1-22C88910EADA' -only-testing:HaiityTests/ReminderSyncContractTests CODE_SIGNING_ALLOWED=NO
```

Result:

- Exit code: `65`
- Failure: `Cannot find 'NativeReminderToggleAction' in scope`
- Confirmed the red step was the missing pure reminder-toggle decision seam, not an unrelated test break.

8. Implemented the smallest production seam and reran the focused reminder contract

```sh
xcodebuild test -project /Users/enrico/Documents/GitHub/haiity/Haiity.xcodeproj -scheme Haiity -destination 'id=88C5F8D5-8924-4600-BDE1-22C88910EADA' -only-testing:HaiityTests/ReminderSyncContractTests CODE_SIGNING_ALLOWED=NO
```

Result:

- Exit code: `0`
- Summary: `Executed 7 tests, with 0 failures (0 unexpected)`

9. Reran the requested Calendar/Reminder/Pro gate focused suite on the concrete simulator id

```sh
xcodebuild test -project /Users/enrico/Documents/GitHub/haiity/Haiity.xcodeproj -scheme Haiity -destination 'id=88C5F8D5-8924-4600-BDE1-22C88910EADA' -only-testing:HaiityTests/CalendarSyncSelectionTests -only-testing:HaiityTests/ReminderSyncContractTests -only-testing:HaiityTests/ProGateTests CODE_SIGNING_ALLOWED=NO
```

Result:

- Exit code: `0`
- Summary: `Executed 45 tests, with 0 failures (0 unexpected)`

10. Self-review after the fix

```sh
git -C /Users/enrico/Documents/GitHub/haiity diff -- Haiity/Services/CalendarSync.swift Haiity/Views/MoreView.swift HaiityTests/CalendarSyncTests.swift HaiityTests/ReminderSyncTests.swift HaiityTests/ProGateTests.swift .superpowers/sdd/task-4-custom-recurrence-report.md
git -C /Users/enrico/Documents/GitHub/haiity status --short
```

Result:

- Verified the fix is limited to `CalendarSync.swift`, `MoreView.swift`, `CalendarSyncTests.swift`, `ReminderSyncTests.swift`, and this report.
- Verified unrelated dirty items such as `tools/release.sh`, `build/`, and `.superpowers/brainstorm/` remained untouched.
