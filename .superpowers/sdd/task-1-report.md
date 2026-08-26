# Task 1 Report

- Status: `DONE_WITH_CONCERNS`
- Repository: `/private/tmp/haiity-task1-f17b985`
- Base HEAD: `f17b985e2686bc15595eeea93dc426d2c13c591f`
- Branch: `codex/task1-native-sync-idempotent`
- Commit SHA(s):
  - `5a10332b794f38259368f21ae6a15be0577efb7e` `Finish native sync idempotence handling`

## Files Changed

Committed:
- `Haiity/Services/CalendarSync.swift`
- `Haiity/Services/NativeSyncInstallation.swift`
- `Haiity/Services/ReminderSync.swift`
- `Haiity/Services/SyncWatermark.swift`
- `HaiityTests/CalendarSyncTests.swift`
- `HaiityTests/ReminderSyncTests.swift`

Preserved but intentionally left unstaged/uncommitted:
- `Haiity/Views/ContentView.swift`
- `Haiity/Views/MoreView.swift`

## What Changed

- Kept the existing dirty sync work and finished the idempotence pass instead of replacing it.
- Added deterministic selection regression coverage for duplicate owned IDs, legacy marker trimming, and stale stored native IDs.
- Stopped silently discarding failed owned-item removals during calendar/reminder reconciliation so the same pass does not recreate duplicates after a failed delete.
- Kept failed removal mappings/links around during disable flows so retry remains possible instead of losing ownership state.
- Exposed `NativeSyncCleanup.Result.needsRetry` for UI retryable cleanup state.

## Commands And Results

1. Create isolated worktree and carry Task 1 dirty files into it.

```bash
git -C /Users/enrico/Documents/GitHub/haiity worktree add /private/tmp/haiity-task1-f17b985 -b codex/task1-native-sync-idempotent f17b985
for f in Haiity/Services/CalendarSync.swift Haiity/Services/ReminderSync.swift Haiity/Services/SyncWatermark.swift HaiityTests/CalendarSyncTests.swift HaiityTests/ReminderSyncTests.swift; do cp "/Users/enrico/Documents/GitHub/haiity/$f" "/private/tmp/haiity-task1-f17b985/$f"; done
cp /Users/enrico/Documents/GitHub/haiity/Haiity/Views/ContentView.swift /private/tmp/haiity-task1-f17b985/Haiity/Views/ContentView.swift
cp /Users/enrico/Documents/GitHub/haiity/Haiity/Views/MoreView.swift /private/tmp/haiity-task1-f17b985/Haiity/Views/MoreView.swift
```

Result:
- Worktree created on `codex/task1-native-sync-idempotent` at `f17b985`.
- Task 1 sync files were brought over from the dirty main checkout.
- Dirty `ContentView.swift` and `MoreView.swift` were preserved for compilation only and left unstaged.

2. Generate the local Xcode project needed in this worktree.

```bash
xcodegen generate
```

Result:
- Succeeded.
- Output: `Created project at /tmp/haiity-task1-f17b985/Haiity.xcodeproj`

3. Requested focused device test command from the brief.

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/CalendarSyncTests -only-testing:HaiityTests/ReminderSyncTests
```

Result:
- Initial run failed on generated test-target signing defaults.

4. Same requested command with signing overrides from the existing project spec.

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/CalendarSyncTests -only-testing:HaiityTests/ReminderSyncTests DEVELOPMENT_TEAM=H8FW6W6K2D CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates
```

Result:
- Build and device launch succeeded.
- Xcode treated the file-level `-only-testing` selectors as `0 tests executed` on this setup, so this was not useful evidence.

5. Concrete class-level rerun for the two Task 1 test files.

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/CalendarSyncSelectionTests -only-testing:HaiityTests/SyncWatermarkTests -only-testing:HaiityTests/CalendarEventPlanTests -only-testing:HaiityTests/ReminderSyncPlanTests -only-testing:HaiityTests/ReminderSyncContractTests -only-testing:HaiityTests/ReminderSyncNativeMappingTests DEVELOPMENT_TEAM=H8FW6W6K2D CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates
```

Result:
- The new pure Task 1 regressions passed.
- Existing source-inspection tests from these files failed on device because the iPhone runner cannot open checkout paths such as `/tmp/haiity-task1-f17b985/...` from the host filesystem.

6. Full compile/build check for the Task 1 slice on the requested physical device target.

```bash
xcodebuild build-for-testing -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' DEVELOPMENT_TEAM=H8FW6W6K2D CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates
```

Result:
- Succeeded.
- Output: `** TEST BUILD SUCCEEDED **`

7. Method-level device execution for the new pure regressions added in this task.

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/SyncWatermarkTests/testCanonicalNativeItemSelectionCollapsesIdenticalOwnedIdentifiers -only-testing:HaiityTests/SyncWatermarkTests/testCanonicalNativeItemSelectionIgnoresStoredIdentifierFromAnotherItem -only-testing:HaiityTests/SyncWatermarkTests/testLegacyCleanupMarkerTrimsWhitespace -only-testing:HaiityTests/SyncWatermarkTests/testNativeCleanupResultMarksFailedPassesAsRetryable DEVELOPMENT_TEAM=H8FW6W6K2D CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates
```

Result:
- Succeeded.
- Output: `Executed 4 tests, with 0 failures (0 unexpected)`

8. Stage only the allowed Task 1 files and verify the staged patch.

```bash
git -C /private/tmp/haiity-task1-f17b985 add Haiity/Services/CalendarSync.swift Haiity/Services/ReminderSync.swift Haiity/Services/SyncWatermark.swift Haiity/Services/NativeSyncInstallation.swift HaiityTests/CalendarSyncTests.swift HaiityTests/ReminderSyncTests.swift
git -C /private/tmp/haiity-task1-f17b985 diff --cached --check
```

Result:
- Succeeded with no diff-check errors.

9. Commit the Task 1 implementation.

```bash
git -C /private/tmp/haiity-task1-f17b985 commit -m "Finish native sync idempotence handling"
```

Result:
- Succeeded.
- Commit: `5a10332b794f38259368f21ae6a15be0577efb7e`

## Concerns

- The brief’s physical-phone manual verification sequence was not performed in this environment, so reinstall cleanup, duplicate cleanup, edit/delete recovery, and unrelated-entry preservation remain unverified on-device by hand.
- The two requested test files contain existing source-inspection tests that are not runnable on a physical iPhone because the runner cannot open host checkout paths. I recorded the full device build check and a passing device run for the new pure Task 1 regressions instead.
