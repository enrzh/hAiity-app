# Native Sync Fix Report

## Changed files

- Haiity/Services/CalendarSync.swift: entitlement disable now uses marker-based full inventory cleanup.
- Haiity/Services/ReminderSync.swift: entitlement disable now uses the async marker-based full inventory cleanup.
- Haiity/Views/ContentView.swift: Home Screen cleanup retains needsRetry and the resulting user-facing message.
- HaiityTests/CalendarSyncTests.swift: source-contract coverage for stale-link cleanup.
- HaiityTests/ReminderSyncTests.swift: source-contract coverage for stale-link cleanup.

## Tests and commands

- git diff --check: passed, no whitespace errors.
- xcodegen generate: passed, generated Haiity.xcodeproj.
- xcodebuild -project Haiity.xcodeproj -scheme Haiity -showBuildSettings: passed.
- Focused XCTest execution: not run. The target is iOS-only and executing XCTest requires a simulator or physical device, both explicitly excluded for this task.

## Remaining concerns

- EventKit removal behavior remains covered by existing source-contract tests rather than runtime XCTest execution in this environment.
- Existing unrelated working-tree changes were preserved and excluded from this commit.
