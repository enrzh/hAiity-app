# Task 4 Fix 2 Report

## Scope

Fixed the reviewed startup-cache issues on top of `5f866d8`.

Changed files:

- `Haiity/Theme.swift`
- `HaiityTests/StartupSplashTests.swift`
- `.superpowers/sdd/task-4-fix2-report.md`

## Fixes

- Launch in-flight completion now removes a worker only when its matching task has completed and its waiter count is zero. A new waiter acquired before completion therefore cannot be evicted by an older completion callback.
- Added a DEBUG-only raster probe and deterministic overlap in the concurrency test. The test now asserts exactly one rasterizer execution for two concurrent requests; the probe is absent from release builds.
- Replaced raw `NSData` cache keys with one shared `AppearanceImageCache.Store` using typed `CacheKey.image` and `CacheKey.launch` namespaces. Launch rasters and persisted image data cannot collide while retaining the same `Entry` representation.

## Verification

Command:

```text
xcodebuild -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -only-testing:HaiityTests/StartupSplashTests test
```

Output:

```text
Test Suite 'StartupSplashTests' passed
Executed 36 tests, with 0 failures
TEST SUCCEEDED
```

The first attempted run used an unavailable `iPhone 16` simulator and stopped during destination resolution. The focused run above used the repository's available iOS 26.5 simulator.

## Known limitation

Existing host-only source-contract tests use `#filePath` to locate repository fixtures. This task does not broaden into rewriting those legacy tests; the physical-device-safe release test path remains unchanged.
