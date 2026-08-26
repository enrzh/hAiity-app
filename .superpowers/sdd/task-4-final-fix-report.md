# Task 4 Final Fix Report: Startup Review Findings

Date: 2026-08-26
Base commit: `cdee6d0`
Worktree: `/Users/enrico/Documents/GitHub/haiity/.worktrees/task-4-startup-review`

## Status

Implemented the two Task 4 startup review fixes in the isolated
`task-4-startup-review` worktree:

- launch-image prewarm no longer uses detached decode work that can outlive the
  splash-owned task handle
- reduced-motion launch now hands off immediately without rasterizing the splash
  image first

## RED Intent

Added focused regression tests before production changes:

- `HaiityTests/ThemeAndPaletteTests.testLaunchPrewarmDoesNotSpinDetachedDecodeWork`
- `HaiityTests/StartupSplashTests.testReducedMotionHandoffSkipsLaunchRasterizationWork`

The host could not run the XCTest action with `CODE_SIGNING_ALLOWED=NO` because
both available destinations require an installable signed app bundle. The two
attempted `xcodebuild test` runs both built successfully and then failed during
installation, not test execution:

- physical iPhone `00008150-000120AC0287801C`: `Failed to verify code signature`
- designed-for-iPhone My Mac `00008132-000C08820C8B801C`: `No code signature found`

Because the new tests are source-contract checks, I also verified the original
`cdee6d0` snapshot still contained the reviewed bad patterns:

- `Theme.swift` used `Task.detached(priority: .userInitiated)`
- `StartupSplashView.scheduleStartIfReady()` prepared the launch image before
  any reduced-motion early return

## Implementation

### 1. Cancellable startup prewarm

`AppearanceImageCache` still keeps the existing shared cache and in-flight
store, but the prewarm path now behaves differently:

- in-flight work is created with `Task(priority: .userInitiated)` instead of
  `Task.detached`
- waiters are reference-counted in `InFlightStore`
- `prepareEntry(for:)` now uses `withTaskCancellationHandler`
- the decode task builds an `Entry` but does not populate the cache directly
- cache population happens only after a live waiter completes without
  cancellation

This keeps a canceled startup handoff from leaving stale cached image buffers
behind, while still sharing one in-flight preparation result across duplicate
live waiters.

### 2. Reduced-motion splash handoff

`StartupSplashAnimationView.scheduleStartIfReady()` now checks `reduceMotion`
before calling `prepareLaunchImage(...)`.

When Reduce Motion is on:

- the splash marks itself started
- clears any pending launch image
- calls `onFinished?()` immediately
- skips the launch rasterization and animation setup entirely

The existing app-mounted full-screen handoff remains intact.

## Files Changed

- `Haiity/Theme.swift`
- `Haiity/Views/StartupSplashView.swift`
- `HaiityTests/ThemeAndPaletteTests.swift`
- `HaiityTests/StartupSplashTests.swift`

## Verification

### Source-contract spot checks

Current worktree:

- `Theme.swift` contains `Task(priority: .userInitiated)` and
  `withTaskCancellationHandler`
- `Theme.swift` no longer contains `Task.detached`
- `StartupSplashView.scheduleStartIfReady()` now checks `reduceMotion` before
  `prepareLaunchImage(...)`

Original `cdee6d0` snapshot:

- `Theme.swift` contained `Task.detached(priority: .userInitiated)`
- `StartupSplashView.scheduleStartIfReady()` prepared the launch image before
  any reduced-motion escape path

### Compile fallback

Command:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild build-for-testing \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

Result:

- exit code `0`
- terminal line: `** TEST BUILD SUCCEEDED **`

### Attempted test commands blocked by signing

Command:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'id=00008150-000120AC0287801C' \
  -only-testing:HaiityTests/StartupSplashTests \
  -only-testing:HaiityTests/ThemeAndPaletteTests CODE_SIGNING_ALLOWED=NO
```

Result: build completed, install failed with `Failed to verify code signature`
and `** TEST FAILED **`.

Command:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=macOS,id=00008132-000C08820C8B801C' \
  -only-testing:HaiityTests/StartupSplashTests/testReducedMotionHandoffSkipsLaunchRasterizationWork \
  -only-testing:HaiityTests/ThemeAndPaletteTests/testLaunchPrewarmDoesNotSpinDetachedDecodeWork \
  CODE_SIGNING_ALLOWED=NO
```

Result: build completed, install failed with `No code signature found`.

## Concerns

- I could not produce a full XCTest red-green run on Wednesday, August 26,
  2026 because both runnable destinations require a signed installable app and
  this task explicitly used the `CODE_SIGNING_ALLOWED=NO` path.
- The prewarm worker is now cancellation-aware and no longer commits stale
  cache entries after cancellation. The underlying synchronous thumbnail decode
  still cannot be interrupted mid-call once Core Graphics has started it.
