# Habit and Reminder Swipe Performance Plan

Status: implemented; simulator verification complete on 2026-09-13

## Goal

Make swipe actions on habits and reminders feel like native iOS interactions:
directly attached to the finger, velocity-aware when released, easy to cancel
while scrolling, and visually quiet. At the same time, reduce work performed
while a long list or contribution grid is being dragged.

This is a refinement of existing behavior, not a new interaction system. The
current action set, data semantics, navigation, graph behavior and reminder
mutation rules remain unchanged unless a concrete correctness issue requires
otherwise.

## Current implementation

- [`SwipeReveal.swift`](../../Haiity/Models/SwipeReveal.swift) owns the pure
  geometry and snap rules: semantic leading/trailing offsets, rubber-banding,
  velocity projection, full-swipe commits and horizontal-intent arbitration.
- [`SwipeRevealPan.swift`](../../Haiity/Views/SwipeRevealPan.swift) provides the
  UIKit pan bridge because nested `List` and horizontally scrolling graph
  content previously made a pure SwiftUI gesture unreliable. It also decides
  whether a gesture belongs to the row, the graph or the enclosing list.
- [`HabitCard.swift`](../../Haiity/Views/HabitCard.swift) and
  [`ReminderRow.swift`](../../Haiity/Views/ReminderRow.swift) duplicate the
  offset state, reveal-button layout, snap handling and notification-based
  dismissal around that shared bridge.
- Both views settle with the same velocity-aware interpolating spring and
  honor Reduce Motion; release velocity is normalized and clamped by
  `SwipeReveal`.
- `ReminderRow` mutates immediately. Reveal actions use a short-lived,
  state-based action lock while the row closes, preventing the same UIKit touch
  from also reaching the checkmark. The old fixed delays and time-based gate
  were removed, so the next deliberate checkmark touch remains interactive.
- Reveal button dimensions remain fixed and stable for hit testing. The dead
  `containerWidth` plumbing was removed from both row renderers.

## Implementation checkpoint

- The shared UIKit pan bridge now reports row ownership, explicitly handles
  cancellation/failure, closes sibling rows when a new row begins, preserves
  vertical list handoff, and identifies control-originated swipes.
- Habit and reminder rows use the same motion, cancellation and sibling-close
  behavior. Reminder actions commit immediately and remain protected from a
  stale checkmark event without a visible action delay.
- Focused geometry/source tests and the reminder interaction UI tests cover
  velocity projection, cancellation, row reuse, sibling dismissal, control
  event ordering and stable action identifiers.
- Verification completed: `HaiityTests` passed `1,744/1,744` tests with German
  localization (`de/DE`); `HaiityUITests` passed `17/17` tests on the iPhone 18
  Pro iOS 27.0 simulator. The focused `ReminderInteractionUITests` suite also
  passed `3/3` after the final follow-up checkmark assertion was made explicit.
  `git diff --check` passed after the final source and test cleanup.
- A physical-device trace, frame-hitch budget and Instruments comparison were
  not available on this machine; simulator UI coverage is the evidence for
  behavior, not a substitute for that device-level measurement.

## Design decisions

1. Keep `SwipeReveal` as the source of truth for geometry and thresholds.
2. Keep the UIKit bridge and graph/list arbitration until measurements prove
   that a native SwiftUI alternative is equally reliable in this hierarchy.
3. Use one shared reveal rendering/state path only if it removes duplication
   without making `HabitCard` and `ReminderRow` harder to reason about. A small
   internal `SwipeRevealContainer` or modifier is appropriate; a new global
   coordinator is not.
4. Keep the reveal surface flat and native-looking: stable action frames,
   minimal tint, no per-frame blur, shadow or scale effects.
5. Do not add a dependency or redesign the surrounding pages as part of this
   work.

## Execution plan

### 1. Establish a baseline

- Build a deterministic fixture containing a normal and crowded Habits list,
  both habit cards and reminder rows, and graphs with horizontal history.
- Measure cold launch, first usable tap, first vertical scroll and a repeated
  open/close swipe sequence on Simulator and, where available, a physical
  device.
- Add or reuse signposts around pan begin, first offset update, snap completion,
  action commit and row mutation. Record frame hitches and main-thread time,
  not only total test duration.
- Capture current behavior for LTR/RTL, light/dark mode, Reduce Motion and
  Dynamic Type before changing the gesture path.

### 2. Unify reveal state and rendering

- Define a small shared interaction contract for `closed`, `dragging`,
  `leading`, `trailing` and `committing` states. The contract should carry the
  raw drag start, current offset, row width and the side/action counts needed
  for the existing `SwipeReveal` rules.
- Route both views through the same begin/change/end/cancel/close flow.
- Keep row-specific callbacks (`onToggle`, `onEdit`, `onArchive`, and so on)
  outside the shared geometry code.
- Keep stable button widths and accessibility identifiers. Remove the unused
  `containerWidth` plumbing unless it is needed for a measured hit-area fix.
- Preserve the current graph arbitration: horizontal graph scrolling continues
  to work, trailing reveal over the graph is allowed only at the graph end, and
  an open row can always be dragged closed.

### 3. Make the motion interactive and native

- During `.changed`, update the offset directly with no implicit animation so
  the row stays under the finger.
- On release, select the existing semantic destination using the raw pull and
  velocity. Use an interactive spring whose initial velocity is derived from
  the pan velocity, with one consistent response/damping profile for both row
  types.
- Animate normal open, close, interrupted drag and opposite-direction drag
  through the same settling path. Do not animate a row after its backing model
  has already been replaced.
- Respect Reduce Motion by using an immediate or materially shortened settle;
  retain the direct drag behavior and all action availability.
- Fire haptics only when crossing a meaningful reveal/commit boundary, not on
  every frame or every cancelled micro-drag.
- Keep action buttons visually quiet while partially exposed. They should become
  fully accessible and tappable only when their stable hit frame is exposed.

### 4. Fix cancellation and action timing

- Close the current row immediately when a vertical scroll intent is detected,
  and verify that the enclosing list can begin scrolling in the same gesture.
- Keep the existing broadcast close behavior for sibling rows, but test whether
  per-row notification subscriptions cause measurable invalidation work in large
  lists. Replace them only if profiling shows a real cost.
- Close an open row when another row starts a reveal, when the user taps the
  exposed content, and when the pan is cancelled or the scene loses
  interaction focus.
- Remove the `ReminderRow` `100 ms` action delay if the action can be made safe
  by ordering the close, mutation and control-event suppression explicitly.
- Replace the `400 ms` lock with the smallest state-based protection that
  prevents one physical/synthesized gesture from both invoking a reveal action
  and toggling the checkmark. The guard must reset on the next deliberate tap,
  pan cancellation or row identity change; it must never make a later tap feel
  disabled.
- Verify that full-swipe commits run exactly once, close immediately, and do
  not cause a reminder reset plus an accidental check-off.

### 5. Reduce work during scrolling and dragging

- Keep graph calculations and statistics out of the pan update path. A drag
  should update only the active row's offset and the minimum visual state needed
  for the reveal buttons.
- Ensure the shared action layer has stable identity and does not rebuild the
  contribution grid on every offset change.
- Preserve the existing `Equatable` optimizations for `HabitCard` and
  `ReminderRow`; add boundaries only where profiling shows parent invalidations
  reaching expensive graph content.
- Avoid new translucent materials, masks, shadows or `drawingGroup` work while
  dragging. Prefer opaque/simple surfaces when Reduce Transparency or the app's
  performance mode requires it.
- Check that action arrays, localized labels and derived row state are not
  recomputed unnecessarily for every gesture update. Cache only values with a
  measured benefit and a clear invalidation rule.
- Remove dead parameters and duplicated layout calculations rather than adding
  another abstraction layer.

### 6. Add focused regression coverage

Extend the existing [`SwipeRevealTests.swift`](../../HaiityTests/SwipeRevealTests.swift)
and [`GesturePerfTests.swift`](../../HaiityTests/GesturePerfTests.swift), adding
UI coverage where pure geometry cannot prove the behavior:

- slow pull opens the correct side at the expected threshold;
- fast short flick opens or closes according to velocity;
- release beyond the rubber band still uses the raw pull for full-swipe commit;
- interrupted and opposite-direction drags settle once and do not jump;
- vertical scrolling closes an open habit or reminder and gives control to the
  list;
- starting a second row closes the first row;
- tapping exposed content closes without changing a graph cell or checkmark;
- a reminder reveal action is immediate, runs once and cannot also toggle its
  checkmark;
- full-swipe commit, button tap and cancellation leave the row interactive for
  the next deliberate gesture;
- graph horizontal scrolling still works at the middle and trailing end;
- LTR/RTL side semantics, Reduce Motion, VoiceOver reveal actions and large
  Dynamic Type remain correct;
- a crowded fixture stays within the agreed frame-hitch and main-thread budget
  during repeated vertical scrolling and swiping.

Tests should prefer behavior and accessibility identifiers over brittle source
string assertions. Existing source-contract tests may remain where they guard
UIKit bridge constraints that are otherwise difficult to exercise reliably.

### 7. Verify and release-gate

- Run `git diff --check` and the focused swipe suite first.
- Run the full German-localized test suite with the repository's normal full
  Xcode toolchain; report an environment blocker if only Command Line Tools are
  selected.
- Re-run the baseline measurements and compare cold launch, first-scroll
  responsiveness, frame hitches and action latency.
- Smoke-test on Simulator and a physical device when available in light/dark
  mode, RTL, Reduce Motion and large Dynamic Type.
- Inspect the final diff for accidental changes to habits, reminders, graph
  semantics, widgets, notifications, sync or localization.
- This plan does not authorize an App Store Connect upload. A future release
  request should treat tests, archive/signing, upload, processing and
  TestFlight availability as separate verification gates.

## Acceptance criteria

- Habit and reminder swipes track the finger without visible lag or snapping
  artifacts.
- A quick flick feels responsive, while a cancelled or reversed gesture settles
  predictably with no stale action layer.
- Starting vertical scrolling closes open actions immediately and does not
  steal list scrolling.
- A reveal action never causes a second checkmark/reset action.
- The same interaction rules, motion profile, accessibility behavior and
  performance characteristics apply to habits and reminders.
- No measurable regression is introduced for horizontal graph scrolling,
  startup interaction readiness, Dynamic Type, Reduce Motion, RTL or VoiceOver.
- The measured crowded-list interaction stays within the agreed frame budget,
  and the final implementation removes unnecessary work rather than hiding it
  behind a new coordinator.

## Out of scope

- New habit or reminder actions.
- A new navigation architecture or page redesign.
- Changes to recurrence, check-off semantics, Calendar/Reminders sync,
  notifications, widgets, GitHub or StoreKit.
- New third-party dependencies.
- TestFlight or App Store Connect upload as part of this planning task.
