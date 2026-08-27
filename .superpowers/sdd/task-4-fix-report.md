# Task 4 Startup Cache Fix

## Changed files

- `Haiity/Theme.swift`
- `HaiityTests/StartupSplashTests.swift`

## Fixes

- Kept launch raster coordination alive until the worker task completes, even when the final waiter cancels.
- Reused `AppearanceImageCache.Store` and `Entry` for launch rasters instead of maintaining a second image cache.
- Made synchronous launch rasterization private so callers use the coordinated async API.
- Added regression checks for cancellation coordination and the shared cache boundary.
- Updated the reusable-raster test to use the coordinated async API.

## Verification

Command:

`xcodebuild build -project Haiity.xcodeproj -scheme Haiity -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`

Output: `** BUILD SUCCEEDED **`

Focused device command:

`xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/StartupSplashTests`

Output: the app and test bundle built and launched on the connected device. 13 runtime timeline/cache tests passed. 22 source-contract tests failed because they resolve repository-relative files from the test bundle's working directory (`Haiity/HaiityApp.swift`, `Haiity/Theme.swift`, etc.), where those paths do not exist. This is a test-harness path issue; no production runtime failure was reported.

## Concerns

- The source-contract tests should resolve the repository root from a stable build setting or bundled fixture before relying on physical-device execution. That harness repair is outside this Task 4 production scope.
- The cache uses a UTF-8 launch key in the shared `NSCache`; launch images and user background data remain distinct by key namespace.
