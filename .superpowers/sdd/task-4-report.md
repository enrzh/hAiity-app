# Task 4 Report: Deep-Link Routing Through Tabs

## Status

Implemented Task 4 from baseline `0e042a4` in the
`navigation-card-interactions` worktree.

## RED

Added the route-effect tests before production changes:

- `testStatsAndArchiveRouteViaMoreTab`
- `testSearchAndCreateHaveExplicitEffects`

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests/AppNavigationTests CODE_SIGNING_ALLOWED=NO
```

Result: expected compilation failure. `AppRouteEffect` was not in scope and
`AppDestination` had no `effect` member. `xcodebuild` exited 65.

## GREEN

Added pure `AppRouteEffect` values to `AppDestination`, covering tab selection,
nested Mehr page, search, and create effects. The legacy `haiity://sync` alias
now resolves centrally to plain Mehr.

`ContentView` now resolves a URL once and delegates to `handle(_:)`. The
handler clears old nested presentation routes, selects the effect tab, then
waits one main-actor turn before opening the requested nested Mehr page,
search, or create presentation. The pending presentation task is cancelled
when a newer route arrives.

Focused command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests/AppNavigationTests \
  -only-testing:HaiityTests/SearchFlowTests CODE_SIGNING_ALLOWED=NO
```

Result: 38 tests executed, 0 failures, `** TEST SUCCEEDED **`.

## Lifecycle Decisions

- Every accepted route first clears `moreSheet` and `morePageRoute`, including
  Habits, Search, Create, and plain Mehr. This resolves the Task 2 review
  finding that an earlier native Mehr page could remain presented.
- Stats and Archive select `.more` before presenting the exact requested page.
- `AppMoreDestination` remains UI-independent. Only `ContentView` maps it to
  the view-local `MoreRoute`.
- iOS 26+ presents nested Mehr destinations through `morePageRoute`; iOS 17-25
  retains the existing `moreSheet` fallback.

## Files

- `Haiity/Models/AppNavigation.swift`
- `Haiity/Views/ContentView.swift`
- `HaiityTests/AppNavigationTests.swift`

## Full Suite

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests CODE_SIGNING_ALLOWED=NO
```

Result: 764 tests executed, 0 failures, `** TEST SUCCEEDED **`.
`git diff --check` also passed.

## Self-Review

- Verified `AppNavigation.swift` remains Foundation-only and does not import
  SwiftUI or refer to `MoreRoute`/`MoreView`.
- Verified `ContentView` has one URL-resolution path and one route-effect
  handler.
- Verified stale More presentation state is cleared for all routes before the
  selected tab changes.
- Verified no tab visuals or card interaction code changed.

## Concerns

- The supplied simulator runs iOS 26.5. The iOS 17-25 route fallback is
  covered structurally and continues to use `moreSheet`, but visual runtime
  verification still needs an older simulator or device.
- Xcode continues to emit pre-existing App Group entitlement and App Shortcut
  metadata notices during tests; they did not cause test failures.

## Route/Search Race Follow-up

### RED

Added `AppNavigationTests.testMoreRouteWinsOverQueuedSearchWork` before the
production change. The test models a delayed search-route token followed by a
newer More-route token and requires only the newest token to remain current.

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests/AppNavigationTests CODE_SIGNING_ALLOWED=NO
```

Result: expected compile failure, `cannot find 'RouteWork' in scope`;
`xcodebuild` exited 65.

### GREEN

Added pure `RouteWork` generation tracking. Every accepted deep-link route
advances its generation; both queued `openSearch` main-queue callbacks verify
the captured route generation before changing search state. Non-search route
effects also explicitly dismiss a search that managed to open just before the
newer route arrived. Toolbar search supplies no route generation, preserving
its native minimized-toolbar behavior and existing `SearchFlow` path.

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests/AppNavigationTests \
  -only-testing:HaiityTests/SearchFlowTests CODE_SIGNING_ALLOWED=NO
```

Result: 39 tests executed, 0 failures, `** TEST SUCCEEDED **`.
`git diff --check` also passed.

### Full Suite

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests CODE_SIGNING_ALLOWED=NO
```

Result: 765 tests executed, 0 failures, `** TEST SUCCEEDED **`.

## Create Cover Route Lifecycle Follow-up

### RED

Added the create-cover lifecycle tests before production changes:

- `testNonCreateRoutesWaitForOpenCreateCover`
- `testLatestRouteWinsOverQueuedCreateCoverDismissal`

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests/AppNavigationTests CODE_SIGNING_ALLOWED=NO
```

Result: expected compilation failure. `RouteWork.begin(_:createIsPresented:)`
and `RouteWork.canDeliverAfterCreateDismissal(_:)` did not exist;
`xcodebuild` exited 65.

### GREEN

`RouteWork.Item` now carries the effect, generation, and whether a non-create
route must wait for the Anlegen full-screen cover to finish dismissing.
`ContentView` holds the latest deferred item, sets `showAdd = false`, and
delivers it only from the cover's `onDismiss` after one main-actor turn.
Generation checks prevent an older dismissal callback or queued presentation
task from applying after a newer route. A separate transition flag keeps routes
that arrive after `showAdd` becomes false but before `onDismiss` waiting behind
the still-visible cover. Create routes remain idempotent. The existing
`showAdd` observer still calls `SearchFlow.coverChanged(open:)` unchanged.

Focused command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests/AppNavigationTests \
  -only-testing:HaiityTests/SearchFlowTests CODE_SIGNING_ALLOWED=NO
```

Result: 41 tests executed, 0 failures, `** TEST SUCCEEDED **`.

### Full Suite

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests CODE_SIGNING_ALLOWED=NO
```

Result: 767 tests executed, 0 failures, `** TEST SUCCEEDED **`.

### Concerns

- The supplied simulator runs iOS 26.5. The lifecycle ordering is covered by
  deterministic `RouteWork` tests; visual runtime verification on iOS 17-25
  still needs an older simulator or device.
