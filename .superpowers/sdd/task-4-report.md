# Task 4 Report: Decouple Startup Animation From Image and Graph Work

## Status

DONE_WITH_CONCERNS

## Worktree

- Path: `/Users/enrico/Documents/GitHub/haiity/.worktrees/task-4-startup-splash-perf`
- Branch: `task-4-startup-splash-perf`
- Baseline: `f17b985` (`Prepare hAiity build 106`)

## Commit SHA(s)

- `cdee6d0c12113d23bda2780647eb141e040fb86c` — `Improve startup splash handoff performance`

## Files

- `Haiity/HaiityApp.swift`
- `Haiity/Models/StartupSplash.swift`
- `Haiity/Theme.swift`
- `Haiity/Views/StartupSplashView.swift`
- `HaiityTests/StartupSplashTests.swift`

## What Changed

- Kept `ContentView` mounted under the splash for the whole launch handoff, but removed the separate root opacity animation so the mounted app is revealed only by the splash overlay fade.
- Replaced the launch-time root `AppearanceImageCache.prewarm(data:)` await with a cancellable `AppearanceImageCache.prewarmTask(data:)` handle stored in `HaiityApp`.
- Cancelled and released the launch-specific prewarm handle when the splash finishes, when the scene backgrounds, and when the root view disappears.
- Added in-flight sharing inside `AppearanceImageCache` so duplicate launch consumers reuse one decode task instead of starting parallel decodes for the same image bytes.
- Moved splash graph raster preparation out of `startAnimation(...)` into the scheduled pre-start task so the animation path no longer rebuilds the launch bitmap right as the handoff begins.
- Preserved the existing three-graph vertical split/zoom behavior, full-screen safe-area coverage, and reduced-motion immediate handoff.
- Updated focused splash tests to cover the new handoff contract, cancellable prewarm path, and pre-animation launch-image preparation.

## Commands And Results

1. Read task brief

```bash
sed -n '1,240p' /Users/enrico/Documents/GitHub/haiity/.superpowers/sdd/task-4-brief.md
```

Result: confirmed Task 4 scope and file ownership.

2. Create isolated worktree

```bash
cd /Users/enrico/Documents/GitHub/haiity
git worktree add .worktrees/task-4-startup-splash-perf -b task-4-startup-splash-perf
```

Result: created isolated worktree on branch `task-4-startup-splash-perf`.

3. Generate the local Xcode project

```bash
cd /Users/enrico/Documents/GitHub/haiity/.worktrees/task-4-startup-splash-perf
xcodegen generate
```

Result: `Created project at /Users/enrico/Documents/GitHub/haiity/.worktrees/task-4-startup-splash-perf/Haiity.xcodeproj`

4. Initial focused test attempt before implementation

```bash
cd /Users/enrico/Documents/GitHub/haiity/.worktrees/task-4-startup-splash-perf
xcodebuild test -project Haiity.xcodeproj -scheme Haiity \
  -destination 'id=00008132-000C08820C8B801C' \
  -only-testing:HaiityTests/StartupSplashTests \
  -skipPackagePluginValidation -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO
```

Result: build reached install, then failed before tests ran because the local Mac destination could not install an unsigned iPhone app (`IDEInstallLocalMacService`, `0xe800801c`, no code signature found).

5. Focused compile error extraction during implementation

```bash
set -o pipefail && \
cd /Users/enrico/Documents/GitHub/haiity/.worktrees/task-4-startup-splash-perf && \
xcodebuild build -project Haiity.xcodeproj -scheme Haiity \
  -destination 'id=00008132-000C08820C8B801C' \
  -skipPackagePluginValidation -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO 2>&1 | rg -n "error:|warning:"
```

Result: exposed one real compile error in `Haiity/Views/StartupSplashView.swift` (`initializer for conditional binding must have Optional type, not 'StartupSplashAnimationView'`). Fixed and reran.

6. Focused app build after the fix

```bash
cd /Users/enrico/Documents/GitHub/haiity/.worktrees/task-4-startup-splash-perf
xcodebuild build -project Haiity.xcodeproj -scheme Haiity \
  -destination 'id=00008132-000C08820C8B801C' \
  -skipPackagePluginValidation -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO
```

Result: `** BUILD SUCCEEDED **`

7. Focused test-target compile without install/launch

```bash
cd /Users/enrico/Documents/GitHub/haiity/.worktrees/task-4-startup-splash-perf
xcodebuild build-for-testing -project Haiity.xcodeproj -scheme Haiity \
  -destination 'id=00008132-000C08820C8B801C' \
  -only-testing:HaiityTests/StartupSplashTests \
  -skipPackagePluginValidation -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO
```

Result: `** TEST BUILD SUCCEEDED **`

8. Focused runtime test attempt with signing allowed

```bash
cd /Users/enrico/Documents/GitHub/haiity/.worktrees/task-4-startup-splash-perf
xcodebuild test -project Haiity.xcodeproj -scheme Haiity \
  -destination 'id=00008132-000C08820C8B801C' \
  -only-testing:HaiityTests/StartupSplashTests \
  -skipPackagePluginValidation -skipMacroValidation
```

Result: failed before execution because the local Mac destination is not included in the selected iOS provisioning profiles, and `HaiityTests` / `HaiityUITests` also require signing configuration for that destination.

9. Commit implementation and tests

```bash
cd /Users/enrico/Documents/GitHub/haiity/.worktrees/task-4-startup-splash-perf
git add Haiity/HaiityApp.swift Haiity/Models/StartupSplash.swift Haiity/Theme.swift \
  Haiity/Views/StartupSplashView.swift HaiityTests/StartupSplashTests.swift
git commit -m "Improve startup splash handoff performance"
```

Result: committed as `cdee6d0c12113d23bda2780647eb141e040fb86c`.

## Test Summary

- `xcodebuild build ... CODE_SIGNING_ALLOWED=NO`: passed
- `xcodebuild build-for-testing ... -only-testing:HaiityTests/StartupSplashTests CODE_SIGNING_ALLOWED=NO`: passed
- `xcodebuild test ... -only-testing:HaiityTests/StartupSplashTests`: could not execute in this environment because install/signing/provisioning failed before test launch

## Concerns

- Physical iPhone launch measurements from process start to first interactive frame were not performed. The task brief asks for those measurements, but this run explicitly avoided simulators/device-hub work and the local environment did not provide a runnable unsigned path for the iPhone app on the Mac destination.
- `StartupSplashTests` were compiled successfully but not executed end-to-end because local runtime test launch is blocked by signing/provisioning on the available non-simulator destination.
- I did not add anything to `GesturePerfTests.swift`; the existing local verification path here was source/compile-focused, and there was no runnable performance harness available without stepping outside the destination constraints above.
