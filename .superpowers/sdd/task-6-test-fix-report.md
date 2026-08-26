# Task 6 Test Fix Report

- Status: implemented
- Files:
  - `Haiity/Services/Reminders.swift`
  - `Haiity/Services/MotivationActivityManager.swift`
  - `Haiity/Views/ContentView.swift`
  - `HaiityTests/NotificationActionTests.swift`
  - `HaiityTests/MotivationActivityTests.swift`
  - `.superpowers/sdd/task-6-test-fix-report.md`

## Commands and results

1. `xcodegen generate`
   - Result: succeeded
   - Evidence: created `/Users/enrico/Documents/GitHub/haiity/.worktrees/task-6-verification/Haiity.xcodeproj`.

2. `xcrun simctl list devices`
   - Result: succeeded
   - Evidence: output was only `== Devices ==`, so this host currently has no installed iOS simulator devices.

3. `xcodebuild test -project /Users/enrico/Documents/GitHub/haiity/.worktrees/task-6-verification/Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:HaiityTests/NotificationActionTests/testDeliveryIssueConsumerForwardsPersistedMessageAndClearsIt -only-testing:HaiityTests/MotivationActivityTests/testManagerReportsDeliveryIssueWhenActivityRequestFails CODE_SIGNING_ALLOWED=NO`
   - Result: failed
   - Evidence: `Unable to find a device matching the provided destination specifier` for `platform:iOS Simulator, OS:latest, name:iPhone 16`.

4. `xcodebuild build-for-testing -project /Users/enrico/Documents/GitHub/haiity/.worktrees/task-6-verification/Haiity.xcodeproj -scheme Haiity -destination 'generic/platform=iOS Simulator' -only-testing:HaiityTests/NotificationActionTests/testDeliveryIssueConsumerForwardsPersistedMessageAndClearsIt -only-testing:HaiityTests/MotivationActivityTests/testManagerReportsDeliveryIssueWhenActivityRequestFails CODE_SIGNING_ALLOWED=NO`
   - Result: succeeded
   - Evidence: exit code `0` and `** TEST BUILD SUCCEEDED **`.

## Fix summary

- Added `NotificationDeliveryIssueCenter.deliverPendingMessage(...)` so the persisted delivery issue can be consumed and forwarded behaviorally, without source-string assertions.
- Switched `ContentView` to use that helper for the existing `flash(...)` toast path.
- Added a narrow async `reportDeliveryIssue` seam to `MotivationActivityManager` so the thrown-start path can be tested directly without new types or extra layers.
- Replaced the two source-only Task 6 tests with behavioral coverage for:
  - persisted delivery issue consumption and clearing,
  - failed Live Activity start reporting the same persisted delivery issue.
- Kept the existing `pushType: nil` terminated-app boundary documentation in `MotivationActivityManager.swift`.

## Concerns

- The focused tests could not be executed on a simulator because this host has no installed iOS simulator devices.
- The compile fallback succeeded, but it does not replace a real runtime XCTest pass on a simulator or attached iPhone.
