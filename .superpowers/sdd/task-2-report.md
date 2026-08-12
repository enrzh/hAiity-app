# Task 2 Report: Two-Destination Native Tab Shells

## Status

Implemented Task 2 in the `navigation-card-interactions` worktree from baseline commit `f6c5227`.

## RED Evidence

Added `AppNavigationTests.testContentViewDeclaresHabitsAndMoreTabs` before changing production code.

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests/AppNavigationTests CODE_SIGNING_ALLOWED=NO
```

Result: `AppNavigationTests` executed 4 tests with 3 expected assertion failures, all in the new source-contract test:

- Missing `value: AppTab.habits`.
- Missing `value: AppTab.more`.
- Existing `enum NativeTab` was still present.

The other three navigation tests passed. `xcodebuild` exited 65 because the new contract was not implemented yet.

## Implementation

### `Haiity/Views/ContentView.swift`

- Replaced the nested `NativeTab` state with `AppTab` from Task 1.
- Added persistent native Habits and Mehr tabs to both the iOS 26 and iOS 27 shells.
- Preserved the iOS 26 search-role create tab and its create zoom anchor.
- Preserved the measured `CreateCircle` mechanism on iOS 27.
- Restores the previously selected real tab after iOS 26 intercepts `.create`, so creating from Mehr does not switch to Habits.
- Added `moreTabContent` with its own `NavigationStack` and nested More sheets through `morePageRoute`.
- Removed `showMore`, the full-screen More cover, More zoom source/destination state, the top toolbar More menu, and menu-only helpers.
- Kept `moreSheet` for pre-iOS-26 deep-link sheets and retained the existing `haiity://sync` alias.
- Updated deep links to select the appropriate native tab; stats/archive select Mehr and open through `morePageRoute` on iOS 26+.
- Retained the native minimized search and the iOS 27 search field watcher. The pre-iOS-26 fallback keeps a standalone search button.

### `HaiityTests/AppNavigationTests.swift`

- Added the source-contract test required by the brief and its repository source URL helper.

## GREEN Evidence

Focused navigation and search command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests/AppNavigationTests \
  -only-testing:HaiityTests/SearchFlowTests CODE_SIGNING_ALLOWED=NO
```

Result: 35 tests executed, 0 failures, `** TEST SUCCEEDED **`.

Full suite command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests CODE_SIGNING_ALLOWED=NO
```

Result: 761 tests executed, 0 failures, `** TEST SUCCEEDED **`. This is the 760-test baseline plus the new Task 2 test.

`git diff --check` also completed with no errors.

## Self-Review

- Confirmed both native shell branches use `AppTab.habits` and `AppTab.more`.
- Confirmed no `NativeTab`, `showMore`, More cover, top toolbar More menu, or More zoom identifier remains.
- Confirmed `showAdd`, `moreSheet`, `morePageRoute`, `createZoomAnchor`, `CreateCircle`, and the search state machine/watcher remain.
- Confirmed iOS 27 `CreateCircle` reads actual tab-bar platter geometry, rather than assuming the former one-tab width.
- Confirmed `Haiity.xcodeproj` remains ignored and is not part of the staged task files.

## Concerns

- Automated tests validate source contracts and search/navigation state, but not the final native tab-bar composition. The two-tab iOS 26 shell and two-tab-plus-measured-circle iOS 27 shell still need repeated on-device or simulator visual/interaction verification, especially minimized tab-bar geometry and CreateCircle placement.
- Removing `listMenuItems` also removed its reorder entry. The follow-up fix below restores reordering with a native `EditButton` in the Habits toolbar.

## Fix Review: Habit Reordering Regression

### RED Evidence

Added `AppNavigationTests.testContentViewKeepsHabitReorderingReachable` before changing production code. The source contract requires the `editMode` state and environment binding, a native `EditButton`, and the search-safe `.onMove` closure.

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests/AppNavigationTests CODE_SIGNING_ALLOWED=NO
```

Result: 5 tests executed. The new source-contract test had 4 expected assertion failures because the Task 2 revision had removed `editMode`, its environment binding, `EditButton`, and `.onMove`; the previous four navigation tests passed. `xcodebuild` exited 65.

### Fix

- Restored `editMode` and the existing search rule that exits edit mode when filtering starts.
- Restored the list's search-safe `.onMove` path to `HabitStore.move`.
- Added native `EditButton` as a leading Habits toolbar item, keeping the iOS 27 trailing search control clear and without restoring the removed Mehr menu or full-screen Mehr cover.
- Closes edit mode when the create cover opens, matching the prior list-state hygiene.

### GREEN Evidence

Focused navigation and search command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests/AppNavigationTests \
  -only-testing:HaiityTests/SearchFlowTests CODE_SIGNING_ALLOWED=NO
```

Result: 36 tests executed, 0 failures, `** TEST SUCCEEDED **`.

Full suite command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests CODE_SIGNING_ALLOWED=NO
```

Result: 762 tests executed, 0 failures, `** TEST SUCCEEDED **`.

### Tracked Follow-Up

- Legacy Mehr reachability remains explicitly assigned to Task 3 and was not changed here.
- Deep-link route clearing and lifecycle behavior remain explicitly assigned to Task 4 and were not changed here.
