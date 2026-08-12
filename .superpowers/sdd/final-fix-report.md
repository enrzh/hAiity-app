# Final Review Integration Fix Report

Date: 2026-08-13
Base HEAD: `f424d8425ebe8253059215d521c1d5c174ba8c83`
Worktree: `/Users/enrico/Documents/GitHub/haiity/.worktrees/navigation-card-interactions`
Release simulator: `876E667A-7321-41E1-9008-876B53FF9F71` (`haiity-v6`, iOS 26.4)

## Scope

- Keep the iOS 17-25 Habits and More destination trees mounted while only the selected tree is visible, interactive, and exposed to accessibility.
- Serialize deep-link route delivery across create-cover and More-sheet dismissal lifecycles, with latest-generation wins, native/fallback parity, and no same-page replacement loop.
- Normalize custom create controls to localized `Neuer Habit` and identifier `create-habit`; document the system Tab limitation on iOS 26.
- Preserve search/create generation handling, reorder/card behavior, backfill layering, and native tab selection.

## RED Evidence

### Initial navigation contracts

Command:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests/AppNavigationTests \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
```

Result: build failed as expected because the new contracts referenced missing `RouteWork.nextStep`, `RoutePresentation`, route steps, and `AppTabLayerState`. This established RED before production changes.

### Requested-but-not-presented sheet edge

After the first GREEN pass, review identified a sheet binding that could be cancelled before sheet content appeared. New source contracts required both sheet contents to call `moreSheetDidPresent(route)` and required replacement to re-advance immediately when no `onDismiss` was owed.

The focused runner executed all 18 tests and recorded 3 expected assertion failures:

```text
testBothMoreSheetHostsDeliverPendingRouteFromOnDismiss: 0 != 2
testMoreRouteCanReplaceARequestedButNotPresentedSheet: two XCTAssertTrue failures
Executed 18 tests, with 3 failures
```

The simulator/test infrastructure then hung after completing the test summary: the log stopped at `01:20:10`, while worktree-specific `xcodebuild` PID `53621` remained idle for over four minutes and never emitted a terminal `** TEST FAILED **`. Only PID `53621` was sent `SIGTERM`; its wrapper exited. This hang is not counted as pass/fail evidence beyond the completed RED assertions above. The requested simulator was shut down, booted, and reached terminal boot status in 33 seconds.

## Implementation

- `AppTabLayerState` is a deterministic pure visibility contract. The fallback `ZStack` now has fixed Habits and More children; opacity, hit testing, accessibility hiding, and z-index follow `AppTab` without conditional subtree removal.
- `RouteWork.nextStep` is a deterministic pure coordinator over create and More presentation phases. One `pendingRoute` retains only the latest generated item.
- Create departure happens first. Its real `onDismiss` advances the latest route, which can then dismiss More before application.
- Both `moreSheet` and `morePageRoute` use `deliverPendingMoreDismissalRoute`. Sheet content marks actual presentation from `onAppear`; replacement before `onAppear` advances immediately because no dismissal callback is owed.
- A Stats/Archive route matching the already-presented More page returns `keepCurrentMorePage`, avoiding a dismiss/re-present loop.
- Both custom create buttons share `CreateAccessibility.label` (`Neuer Habit`) and `.identifier` (`create-habit`). The iOS 26 system `Tab` uses the same localized label, but SwiftUI's `Tab` declaration exposes no modifier path for an explicit accessibility identifier; this exact limitation is documented beside the declaration.

## GREEN Evidence

All commands used release Xcode and simulator `876E667A-7321-41E1-9008-876B53FF9F71`. Post-recovery commands had process-group wall-clock bounds; none reached its timeout. A timeout would have been exit `124` and would not have counted as test evidence.

| Suite | Result |
| --- | --- |
| `AppNavigationTests` | 18 tests, 0 failures, `** TEST SUCCEEDED **` |
| `SearchFlowTests` | 31 tests, 0 failures, `** TEST SUCCEEDED **` |
| `ChromeLayoutTests` | 12 tests, 0 failures, `** TEST SUCCEEDED **` |
| Full `HaiityTests` | 777 tests, 0 failures, `** TEST SUCCEEDED **` |

`tools/release.sh` was updated from `MIN_TESTS=769` to the exact executed count `MIN_TESTS=777`; the adjacent comment records the 8 added navigation/lifecycle contracts.

## Release Evidence

Command:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./tools/release.sh
```

Result: exit 0, no upload requested or performed.

- Toolchain: release Xcode 26.6.
- Project regeneration and iOS platform preflight passed.
- Release gate executed 777 tests with floor 777.
- Archive created at `/tmp/haiity-release/Haiity.xcarchive`.
- App and widget versions matched at `1.0.0 (23)`.
- Top-level AppIcon, compiled primary icon, and all 5 alternate icons passed.
- App and widget each carried 16 localized `.lproj` directories.
- Debug seam checks passed: 4 guarded source literals, 0 unguarded, 15,928 dSYM symbols inspected, 2 Mach-O binaries inspected.
- App and widget privacy manifests passed.
- No-upload App Store export completed at `/tmp/haiity-release/export/Haiity.ipa`.

## Residual Concerns

- Unit and source contracts deterministically cover coordinator decisions and SwiftUI structure, but no UI automation drives an interactive sheet swipe during a deep-link arrival. Both item-sheet hosts use the same lifecycle path, reducing platform divergence.
- The iOS 26 system create Tab cannot receive explicit `create-habit` through the available SwiftUI Tab API. Its localized accessibility name is `Neuer Habit`; iOS 17-25 fallback and iOS 27 custom `CreateCircle` both expose `create-habit` exactly.
