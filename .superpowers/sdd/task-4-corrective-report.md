# hAiity Task 4 corrective report

## Status

Implemented and committed the corrective startup tile coordination changes.

## Changes

- Added an in-flight actor for launch-tile raster requests so concurrent callers share one raster task.
- Added a cancellation check immediately before the synchronous renderer starts.
- Connected `StartupSplashView` to the shared async cache entry point and retained the existing three-graph vertical Core Animation splash and reduced-motion immediate handoff.
- Added focused executable/pure regression coverage for concurrent sharing and cancellation ordering.
- Updated affected source-contract assertions to describe the shared cache boundary.

## Commit

`fix: deduplicate startup tile rasterization`

## Tests

Passed on the existing `sAiity Verification` simulator:

- `StartupSplashTests`: 33 tests, 0 failures
- `AppearanceSettingTests.testLaunchPrewarmDoesNotSpinDetachedDecodeWork`: passed
- Build and test compilation completed successfully.

The first attempted destination, `iPhone 16 Pro`, was unavailable on this host. No simulator was created.

An expanded run also reported the pre-existing unrelated failure `AppearanceSettingTests.testStatsPageUsesClearSectionsAndIndividualCardSurfaces`; no StatsPage or other unrelated file was changed.

## Changed files

- `Haiity/Theme.swift`
- `Haiity/Views/StartupSplashView.swift`
- `HaiityTests/StartupSplashTests.swift`
- `HaiityTests/ThemeAndPaletteTests.swift`
- `.superpowers/sdd/task-4-corrective-report.md`

All other existing uncommitted changes were preserved.

## Concerns

The raster worker is cancellation-aware before entering the synchronous renderer, but a cancellation arriving after rendering has begun cannot interrupt UIKit's synchronous drawing operation. Physical-device startup timing and reduced-motion behavior were not device-tested in this run.
