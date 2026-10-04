# Sorting Behavior Rework

Date: 2026-10-03
Status: bounded implementation and final local verification passed; physical gates pending
Inspected baseline: `main`, `109a06d9bfc0633e59b8d45abc60cd25aad4a0dc`, build 273
Working tree at inspection: clean

## Goal

Moving a habit or reminder from the bottom of a long list to the top should be
continuous, predictable and easy to finish. A dropped item must land where the
user placed it; cancellation must not quietly save an intermediate position.

Keep sorting inside the Habits page. Preserve the current order, Heute/Alle
behavior, hidden/archived slots, existing persistence and the normal habit cards.
The initial request authorized this plan only. The user subsequently authorized
implementation. Version changes, commits, phone installation and TestFlight
uploads remain outside this implementation turn.

## What the Current Code Does

`ContentView` shows full habit cards and compact reminders in the same SwiftUI
`List`. Entering sorting disables row actions and installs `HabitSortingSession`.
That representable discovers the List's underlying `UICollectionView`, places
a long-press recognizer on its window, snapshots the dragged cell and disables
the collection's own scrolling gesture. A `CADisplayLink` manually scrolls at
the edges and repeatedly attempts adjacent reorder operations.

The session reconstructs row frames from cached/estimated heights. Each swap
changes the live store without writing to disk; completion later persists the
result. `HabitStore.moveVisible` already preserves filtered-out and archived
items' slots. That storage rule should be reused.

## Findings

### Confirmed: fast movement and release can lag behind the finger

`destinationIndex` only advances one neighbor at a time, regardless of how far
the finger has moved. `applyFinger` rejects another move for 0.12 seconds after
each swap. The `.ended` path calls that same throttled method once, then saves
and stops the display link.

A direct execution of the unchanged policy produced:

| Probe | Current result |
| --- | --- |
| Finger over first row, dragged item at index 11 | Target index 10, rather than 0 |
| Final update 50 ms after previous swap | Rejected by cooldown |
| Eleven adjacent swaps | About 1.32 seconds of serialized move intervals |

The display link can eventually catch up while a finger remains held. These
results identify the short-drag/release weakness; they do not by themselves
reproduce every real-device bottom-to-top failure.

Source: `Haiity/Views/HabitSortingScreen.swift`, `pressed` / `applyFinger` /
`destinationIndex` / `canApplyMove`.

### Confirmed: canceled drags persist intermediate order

`.cancelled` and `.failed` call `finishDrag(save: dragging)`. Detachment may also
persist a changed order. Neither path restores the order from the start of the
drag. An interrupted gesture can therefore commit a reorder that the user did
not drop. This is a concrete behavior to change, not a new animation request.

Source: `HabitSortingScreen.swift`, `pressed` / `detach` / `finishDrag`.

### Confirmed design risk: geometry is estimated and indexed during animation

`captureRowMetrics` obtains frames for every row, including offscreen rows with
missing or estimated layout attributes. It captures the section origin once,
then `stackedFrames` reconstructs the full stack. New measurements are patched
by collection index while the app animates swaps and separately moves its own
ID/height arrays.

This creates two sources of geometry/order: UIKit's changing layout and the
session's reconstructed stack. Variable-height cards and newly revealed rows
can make them diverge. This is a plausible contributor to the reported long
drag bug; the actual device trace still needs to distinguish it from the
confirmed cooldown/drop issue.

Source: `HabitSortingScreen.swift`, `captureRowMetrics` / `logicalFrames` /
`refreshVisibleHeights` / `habitFrames`.

### Confirmed design risk: scrolling changes reversal coordinates

`lastMoveFingerY` is stored in content coordinates. Edge scrolling changes those
coordinates even when the user's finger stays still on the screen. The existing
reverse threshold accepts a 40 pt content-coordinate shift as a reversal.
The check cannot distinguish intentional finger reversal from scrolling.

### Confirmed: sorting feedback does not fully honor Reduce Motion

Neighbor movement in `ContentView.reorderHabit` respects Reduce Motion, but the
UIKit lift scale and settle animations run unconditionally. Reduced-motion
behavior needs one consistent contract.

### Coverage misses the reported scenario

The current UI tests cover entering/exiting sorting, inactive row actions and
a reminder moved above a nearby visible habit. They do not hold a drag at an
edge across several screens, release quickly, reverse direction mid-scroll,
verify cancellation or reload the resulting long-list order.

Many `ChromeLayoutTests` assert the presence of custom implementation details
such as a window recognizer, cached heights and scroll locking. They prove that
this controller exists, not that its behavior works. Replace implementation
assertions only when the controller is replaced; retain the actual product
and persistence assertions.

## Recommended Interaction

Use **compact native reorder rows while sorting is active**, in the same Habits
page. The normal page retains its full graphs and habit/reminder cards.

- Keep the existing sort toolbar entry and Done action. Entering sorting
  changes the list to succinct rows with the existing emoji/icon, name and a
  small Habit/Reminder distinction. Use the app's current typography/surfaces.
- Provide the system reorder handle so the drag affordance is visible. Native
  drag feedback, neighbor movement and edge scrolling own the interaction.
- Ordinary scrolling works whenever no item is being dragged. Holding near
  the upper/lower visible edge scrolls through the list until the user moves
  away, drops, or cancels.
- Hide contribution grids and the GitHub/progress content from the sorting
  surface, retaining the page title and current viewing scope. Those elements
  do not help identify the desired order and increase drag travel/rendering.
- On Done, restore full cards. Anchor the restored viewport to the last moved
  item by ID where possible, rather than unexpectedly jumping to the top.
- Check-off, swipe actions, history and editing stay inactive during sorting.
  Names remain readable and sortable with Dynamic Type and VoiceOver.
- A completed drop saves its final order. A canceled current drag leaves the
  last successfully saved order intact. Earlier completed drops are not undone
  merely because the user later leaves the page.

This is a deliberate change from the previous custom full-card sorting design.
It simplifies a task that only needs item identity and order. It adds no new
page, sorting preference or alternate order model.

Apple design references inspected: `lists-and-tables.md` / Content recommends
succinct rows rather than over-large rows; `gestures.md` / Best practices says
to add custom gestures only when necessary; `motion.md` / Providing feedback
calls for precise, cancellable feedback; `accessibility.md` / Mobility requires
alternatives to gesture-only interaction.

## Implementation Plan

### 1. Prove native reordering against the actual requirements

Start with public SwiftUI `List` editing and `ForEach.onMove`, scoped to the
sorting mode. Reuse the existing row identity, toolbar and store API.

Before replacing the custom controller, verify on a real scrolling list that
native movement handles continuous bottom-to-top/top-to-bottom drags, final
drop position, cancellation, compact mixed rows and header/tab-bar boundaries.
Verify when the public move callback fires; do not assume native cancellation
or persistence semantics without observing them.

Use iOS 18 and the current iOS 27 environment as availability/behavior gates.
If the public SwiftUI path fails a concrete requirement, record that failure
and use an owned native UIKit reorder list for the sorting surface only. Do not
attach interactive movement to SwiftUI's undocumented backing collection view,
ship two reorder engines, or build another estimated-height controller.

### 2. Reuse persistence and make completion unambiguous

- Route a completed move through `HabitStore.moveVisible`, with offsets
  referring to the same stable ordered IDs the sorting rows display.
- Validate IDs, membership and current order before committing. A removed item
  or external same-membership reorder must not reinterpret an old index as a
  different habit. Existing duplicate/bounds guards remain required.
- Keep Heute sorting scoped to visible IDs; hidden active and archived items
  retain their slots. Preserve the existing eligibility of other filters/Search.
- Commit only an actual successful move. No disk writes or widget/cloud work
  from drag-frame updates or a lift with no movement.
- Preserve coordinated-write rejection and surface an unsuccessful save. Do
  not leave a visually successful new order after the store restored durable data.
- Exit/abort safely on navigation, backgrounding, membership/filter changes or
  a concurrent external order change. Cancel only the uncommitted drag; keep
  earlier completed moves.
- Add only minimal ID/session state if the native callback requires it. No new
  coordinator, persisted settings, merge system or history migration.

### 3. Remove the custom reorder machinery

After native behavior passes the long-list checks, remove the unused snapshot,
window recognizer, manual pan locking, display link, synthetic row-height cache,
neighbor cooldown and reversal threshold in `HabitSortingScreen.swift`.

Remove corresponding `sortingDraggedID`/placeholder state and obsolete policy
helpers only after confirming all callers. Keep code shared with normal rows
only where still used. Update the design guide's custom-gesture description.
Do not retain the old engine as an unused fallback.

### 4. Finish motion, accessibility and performance verification

- Use native lift/move/drop feedback. Avoid extra springs, delayed save timers
  or haptics on every frame. Reduce Motion must cover mode transitions too.
- Verify the native VoiceOver reorder actions are reachable. Where insufficient,
  add minimal localized Move Up/Move Down actions using the same move function;
  verify focus and announced position. No separate accessible order path.
- Keep a comfortable touch area for the reorder handle and rows; verify RTL,
  long names, largest Dynamic Type and dark/solid/image appearances.
- Measure interaction on crowded data before/after. Success means responsive
  drag/scroll and fewer unnecessary graph renders, not merely shorter code.
  Do not claim a specific performance gain without comparable measurement.

## Verification Matrix

Use isolated simulator fixtures with at least 30-50 mixed items so the list
spans several screens even in compact mode. Include different name lengths and
Dynamic Type sizes; add only the small fixture extension the tests need.

| Scenario | Acceptance |
| --- | --- |
| Last item to first, continuous edge hold | Item reaches first position without releasing/regrabbing; final order survives reload |
| First item to last | Same guarantee in the opposite direction |
| Several rows crossed quickly, immediate release | Final target follows the drop; no one-row/cooldown lag |
| Stationary finger at top edge for several screens | Continuous scroll; item identity remains stable; no bounce or frozen preview |
| Reverse direction after edge scrolling | Reversal follows finger intent; item does not jump because content offset changed |
| Return from edge to center | Edge scrolling stops; ordinary target movement continues |
| Cancel, navigate away or background mid-drag | No unfinished move committed, no overlay/scroll lock/recognizer left behind |
| Re-enter sorting after cancellation | Scroll, drag and Done remain usable |
| Heute subset with hidden/archived items | Only visible slots reorder; unrelated data remains unchanged |
| External remove/order change or stale write | Safe abort/rejection; no wrong-ID movement or silent overwrite |
| Lift/drop at original position | No unnecessary write |
| Save failure | Visible order reconciles with durable data and an error is reachable |
| GitHub connected and disconnected | Headers never become move targets; edge scroll respects actual visible bounds |
| Small phone, long names, largest text, RTL | Name, handle and target remain readable/reachable |
| VoiceOver and Reduce Motion | Reordering works without touch dragging; no forced custom lift animation |

Extend `ReorderTests` for first/last destinations, same-membership stale orders,
Today hidden slots and save failures. Replace custom-physics source assertions
in `ChromeLayoutTests` with behavioral requirements where appropriate.

Extend `TodayProgressUITests` with continuous multi-screen drags, cancellation,
reload order and no-action-during-sort checks. Retain its existing entry/exit
and mixed-item guarantees. Add the new bottom-to-top regression to Smoke so
the standard gate exercises the reported bug.

Run focused tests, then the existing Unit/Smoke verification and an unsigned
Release build with full Xcode through `DEVELOPER_DIR`. Keep source-bound xcresults
and before/after screenshots. Real finger edge holds, interruption and 60/120 Hz
devices remain physical-device gates; simulator success does not prove their feel.

## Files Expected to Change During Implementation

- `Haiity/Views/ContentView.swift`: sorting surface, native movement callback,
  mode transitions and viewport restoration.
- `Haiity/Views/HabitSortingScreen.swift`: replace/remove custom controller;
  retain a focused sorting view here only if it improves ownership.
- `Haiity/Models/HabitStore.swift`: only any necessary stale-order validation,
  reusing `moveVisible` and existing persistence.
- `HaiityTests/ChromeLayoutTests.swift`, `HaiityTests/StatsAndReorderTests.swift`,
  `HaiityUITests/TodayProgressUITests.swift`, `TestPlans/Smoke.xctestplan`:
  behavioral coverage and removal of obsolete implementation assertions.
- `Haiity/Models/DesignFixture.swift`: minimal long-list test data if needed.
- `Haiity/Localizable.xcstrings` and the design guide: only changed labels/contracts.

## Evidence and Limits of This Audit

The working tree, current implementation, all reorder callers, relevant storage
tests, sorting UI tests and design/engineering contracts were inspected.
The unchanged policy was executed in a Foundation/SwiftUI Swift probe, exit 0,
confirming the adjacent-only destination, blocked immediate final move and
content-coordinate reversal behavior. No source or test code was modified.

No new simulator gesture recording, physical-device reproduction or native
replacement prototype was run in this planning turn. The reported long-drag
failure remains the primary implementation verification gate, not a claim
already resolved by this plan.

## Implementation Checkpoint

The authorized owned UITableView fallback replaces the custom engine. Public
SwiftUI List movement was tried first but failed the 40-item long-drag gate.
The owned UITableViewController hosts generic SwiftUI rows and lets UIKit own
dragging and edge scrolling. Title/scope live in the navigation header, outside
the sorting table. The final 40-item bottom-to-top/top-to-bottom test passed
with exact order and persistence after both relaunches.

The old snapshot/window recognizer/display link/height cache/cooldown engine was
removed. Normal cards no longer carry sorting-only gesture guards. Store moves
validate ordered visible IDs, avoid no-op writes, preserve hidden/archived slots
and restore durable state after a failed save. A sorting session token rejects
callbacks from a previous mode session. The normal viewport uses the same stable
string ID as the restored card.

Final frozen-source verification passed: Unit 2,105, Smoke 17, existing
fast-drop/no-op and background/navigation/relaunch regressions 2, compact SE
Arabic/largest-text/Reduce Motion 1; zero failures/skips/runtime warnings.
Unsigned generic iOS Release exited 0. Artifacts and evidence.json are retained
in `/Users/enricomini/Documents/haiity-verification/sorting-complete.d7Hf84`,
bound to fingerprint
`bcde83fa70ab13d73e099acff9c8cb2fba5973b373535b8e082400f88a13436e`.
Final evidence and whitespace checks passed; 1.0.0 (273) is unchanged.

The UI oracle uses one public accessibility snapshot per screen to pair exact
IDs and frames; all 40-order/persistence assertions remain. RTL uses the actual
native handle. Semantic cell backgrounds passed light/dark photo audits.
Physical held-touch cancellation, VoiceOver focus, reversal, 60/120 Hz timing
and iOS 18 hardware remain distinct pending gates. No FPS speedup is claimed.
No phone install, upload, commit, push or release metadata change is included.
See the implementation report for final artifact paths and limitations.
