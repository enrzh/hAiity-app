# Task 3 Report

- Status: `DONE_WITH_CONCERNS`
- Branch: `task-3-cloud-sync`
- Base commit: `f17b985e2686bc15595eeea93dc426d2c13c591f`
- Commit SHA(s): `b54fdfd4c86b2eca416d34bcc67d4430ef5f9855`

## Scope

Implemented only within the allowed slice:

- `Haiity/Services/CloudSync.swift`
- `Haiity/Models/HabitStore.swift`
- `HaiityTests/CloudSyncTests.swift`
- `HaiityTests/StoreAndMergeTests.swift`

No changes were made to native sync, `ContentView`, `MoreView`, Pro policy, widgets, notifications, startup, release files, the plan, or unrelated dirty work from other slices.

## What changed

- Stopped `CloudSync.pull()` from caching an unreadable remote record, so a later push cannot reuse that broken server record as an overwrite token.
- Kept appearance-only persistence from advancing the general habit/settings freshness timestamp, so newer remote habit metadata still merges even when a local appearance write happened later.
- Added focused deterministic tests for:
  - temporary CloudKit failure followed by a later successful retry with newer local writes intact
  - unreadable remote payloads not being cached for later overwrite
  - remote habit metadata still winning when a local appearance change happens while a remote read is effectively in flight

## Files changed

- `Haiity/Services/CloudSync.swift`
- `Haiity/Models/HabitStore.swift`
- `HaiityTests/CloudSyncTests.swift`
- `HaiityTests/StoreAndMergeTests.swift`

## Commands and results

1. Read the brief and inspected only the allowed files.

2. Generated the Xcode project:

   - Command:
     - `xcodegen generate --spec /Users/enrico/Documents/GitHub/haiity/.worktrees/task-3-cloud-sync/project.yml`
   - Result:
     - `Created project at /Users/enrico/Documents/GitHub/haiity/.worktrees/task-3-cloud-sync/Haiity.xcodeproj`

3. Checked available non-simulator destinations:

   - Command:
     - `xcrun xcodebuild -showdestinations -scheme Haiity -project /Users/enrico/Documents/GitHub/haiity/.worktrees/task-3-cloud-sync/Haiity.xcodeproj`
   - Result:
     - Attached iPhone destination available: `id=00008150-000120AC0287801C`
     - Mac-designed destination also listed, but was not usable for this target because of provisioning.

4. Tried focused tests on `My Mac` to avoid simulator use:

   - Command:
     - `xcodebuild test -project /Users/enrico/Documents/GitHub/haiity/.worktrees/task-3-cloud-sync/Haiity.xcodeproj -scheme Haiity -destination 'platform=macOS,name=My Mac' -only-testing:HaiityTests/CloudSyncTests -only-testing:HaiityTests/StoreAndMergeTests`
   - Result:
     - Failed before tests because the provisioning profiles do not include the Mac-designed destination, and the generated test bundles had no development team.

5. Tried the attached iPhone with the brief destination:

   - Command:
     - `xcodebuild test -project /Users/enrico/Documents/GitHub/haiity/.worktrees/task-3-cloud-sync/Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/CloudSyncTests -only-testing:HaiityTests/StoreAndMergeTests`
   - Result:
     - Failed before tests because the generated test bundles had no development team.

6. Ran the same focused iPhone tests with a command-line team override instead of changing project files:

   - Command:
     - `xcodebuild test -project /Users/enrico/Documents/GitHub/haiity/.worktrees/task-3-cloud-sync/Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' DEVELOPMENT_TEAM=H8FW6W6K2D -only-testing:HaiityTests/CloudSyncTests -only-testing:HaiityTests/StoreAndMergeTests`
   - Result before new tests:
     - `34 tests, 0 failures`

7. Added the new red tests and reran the same focused iPhone command:

   - Result:
     - `37 tests, 3 failures`
     - Failing tests:
       - `CloudSyncTests.testUnreadablePullDoesNotCacheServerRecordForLaterOverwrite`
       - `StoreAndMergeTests.testRemoteHabitMetadataStillWinsWhenLocalAppearanceChangesDuringFetch`
       - `StoreAndMergeTests.testRemoteHabitMetadataStillWinsWhenLocalAppearanceChangesDuringFetch` (two assertions in one test)

8. Applied the production fixes and reran the same focused iPhone command:

   - Result:
     - `37 tests, 0 failures`
     - `** TEST SUCCEEDED **`

## Concerns

- The requested manual physical-phone scenario was **not** performed:
  - change appearance and a habit offline
  - terminate/relaunch
  - reconnect iCloud
  - verify final local state manually
- I did not create or use simulators, and I did not use the device hub.
- The CLI test invocation required `DEVELOPMENT_TEAM=H8FW6W6K2D` as a command-line override because the generated `HaiityTests`/`HaiityUITests` bundles did not carry a team setting. I kept that out of the project files to stay inside scope.

## Task 3: Splash handoff performance

### What changed

- Added `StartupSplashTimeline.reducedMotionDuration` and `reducedMotionOpacity(at:)` for one short opacity-only Reduce Motion handoff.
- Renamed the normal tile animation key to `startupSplashFinalHandoff`; the existing `AppearanceImageCache.launchTilesImageTask` path remains asynchronous and shared.
- Kept `startupContentMounted = true` and the existing `HaiityApp.finishStartupAnimation()` callback handoff unchanged.
- Added focused contracts for no pre-completion zero-opacity gap, reduced-motion timing, and final handoff animation naming.

### Commands and results

1. RED attempt:

   - Command:
     - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HaiityTests/StartupSplashTests`
   - Result:
     - No output or test summary after approximately 40 seconds; process was interrupted to avoid a hung run.

2. GREEN attempt:

   - Command:
     - `perl -e '$SIG{ALRM}=sub{kill 9,-$$; exit 124}; setpgrp(0,0); alarm 60; exec @ARGV' env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -only-testing:HaiityTests/StartupSplashTests`
   - Result:
     - Reached Xcode build graph and external tool discovery, but produced no test summary within the execution window; no `TEST SUCCEEDED` result was obtained.

3. Commit:

   - `9631390 smooth splash handoff`
   - Only `Haiity/Views/StartupSplashView.swift`, `Haiity/Models/StartupSplash.swift`, and `HaiityTests/StartupSplashTests.swift` were committed. `Haiity/HaiityApp.swift` was unchanged.

### Concerns

- The focused simulator test run did not reach a verifiable XCTest result because the environment hung during Xcode setup/build; simulator `AC636497-5EC6-4AD4-BD83-E5E2458FA702` was booted.
- Existing unrelated dirty reports and untracked files were preserved. This report was appended after the commit and remains unstaged.

### Review 修复验证

- 已将旧 animation key 断言改为完整调用匹配，避免误命中 `startupSplashFinalHandoff`。
- Reduce Motion 现在仅提交一个 opacity handoff，并通过 Core Animation completion 与 `finishIfNeeded()` 一次性完成；正常路径同样由 transaction completion 驱动，取消/移除后不会重复回调。
- 提交后检查确认 report 未进入 `fb0af4e..HEAD`，且保持 unstaged；`git diff --check` 通过。
- 指定 simulator 的 bounded `StartupSplashTests` 两次均停在 Xcode 外部工具/build graph 阶段，未产生非零 XCTest 汇总，因此未宣称测试通过。

### Final focused verification

- Command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -only-testing:HaiityTests/StartupSplashTests -derivedDataPath /tmp/haiity-task3-derived -skipPackagePluginValidation -skipMacroValidation` (240-second process bound)
- Result: `Executed 42 tests, with 0 failures (0 unexpected)` and `** TEST SUCCEEDED **`.
- `testConcurrentLaunchTileRequestsShareOneExecutableRasterTask` passed, including the one-executable-raster assertion after the probe stabilization in `a5b7852`.
- Independent review found no production-code correctness defect. Minor residual test-depth note: the Core Animation completion contract is primarily source-contract coverage rather than a runtime-driven `StartupSplashAnimationView` completion-count test.
