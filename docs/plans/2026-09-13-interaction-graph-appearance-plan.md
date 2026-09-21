# Interaction, Graph, and Settings Visual Refinement Plan

Status: implemented
Scope: focused polish for swipe actions, contribution graphs, and the Account/
Standardzeitzone pages. No new product features.

## Goal

Make the four reported areas feel deliberate and consistent without adding a
new navigation system, a new graph implementation, or a new dependency:

1. Habit and reminder swipes should track the finger and settle like native
   iOS actions, including a clear cancelled-gesture state.
2. Habit graphs should be optically centered when their content fits the
   available width.
3. Habit, GitHub, and widget graphs should use the existing shared tile
   renderer without a visible border around every tile.
4. Account and Standardzeitzone should use the same appearance-aware page
   shell as the other More secondary pages.

## Current Boundaries

- [`SwipeReveal.swift`](../../Haiity/Models/SwipeReveal.swift) owns the pure
  thresholds, rubber band, velocity projection, and full-swipe rules.
- [`SwipeRevealPan.swift`](../../Haiity/Views/SwipeRevealPan.swift) owns the
  UIKit gesture bridge and arbitration with the List and horizontal graph
  scrolling.
- [`HabitCard.swift`](../../Haiity/Views/HabitCard.swift) and
  [`ReminderRow.swift`](../../Haiity/Views/ReminderRow.swift) currently repeat
  most reveal state, action-layer layout, and settling animation.
- [`ContributionGrid.swift`](../../Haiity/Views/ContributionGrid.swift),
  [`GitHubContributionGraph.swift`](../../Haiity/Views/GitHubContributionGraph.swift),
  and the widget graph views already converge on `ContributionChart` and
  `ContributionTiles`. That path remains the source of truth.
- [`MoreView.swift`](../../Haiity/Views/MoreView.swift) already has the shared
  `appPageHeader`, `pageHeaderChrome`, `moreSettingsSurface`, and appearance
  environment conventions. Account and timezone should join those conventions
  instead of introducing another page style.

## Order of Work

### 1. Establish a visual and interaction baseline

Before changing code, capture the current behavior with a deterministic data
fixture containing at least one habit, one reminder, and a graph with enough
history to scroll.

Record:

- slow open, quick flick open, cancelled pull, reverse-direction pull, and
  full-swipe commit for both habits and reminders;
- vertical list scrolling while a row is open;
- horizontal graph scrolling at the middle and trailing edge;
- the habit graph on a narrow phone and a regular phone in light and dark mode;
- Account and Standardzeitzone with each Darstellung material selected;
- Reduce Motion, Increased Contrast, and a large Dynamic Type size where
  available.

Use these captures as before/after evidence. Do not use a screenshot to infer
data correctness; the existing pure tests remain responsible for thresholds
and action semantics.

### 2. Rework swipe motion with one shared behavior

Keep the existing UIKit bridge and the pure `SwipeReveal` rules until a
measurement proves they are the cause of a defect. The current hierarchy has
nested Lists and horizontally scrolling graphs, so replacing it with a simpler
SwiftUI gesture without proving arbitration would risk breaking graph taps and
vertical scrolling.

Implementation:

- Extract the duplicated reveal state and rendering into the smallest shared
  internal container or modifier that can host arbitrary row content. Do not
  add a global coordinator.
- Keep row-specific handlers in `HabitCard` and `ReminderRow`; the shared path
  should only know about reveal geometry, action buttons, ownership, and
  callbacks.
- Keep direct, animation-free offset updates while the finger is down. The
  row must never lag behind the pan.
- Use one `interactiveSpring`/interpolating spring profile for open, close,
  reverse-direction, cancellation, and full-swipe return. Pass the actual pan
  velocity to the settle operation.
- Keep the action layer stable behind the row. Use a restrained edge reveal
  and opacity transition if needed, but remove any scale or blur that makes
  buttons jump, shimmer, or change their hit frame during the drag.
- Treat cancellation as a first-class close path: the row returns to zero,
  action buttons become inaccessible, and the next deliberate tap works
  immediately.
- Close an open row when vertical scrolling starts, when another row starts a
  reveal, when exposed content is tapped, and when the scene loses focus.
- Trigger haptics only at the meaningful open/close or commit boundary, never
  on every changed event.
- Keep Reduce Motion behavior explicit: direct tracking remains available, but
  settling is immediate or materially shortened and does not rely on a hidden
  animation completion.
- Preserve stable action widths, VoiceOver reveal actions, RTL side semantics,
  and the existing rule that destructive or navigation actions are not eligible
  for full-swipe commit.

The `ReminderRow` action path must remain synchronous from the user's point of
view. The protection against a reveal action also toggling the checkmark should
be state-based and limited to the current physical event, not a visible timer
lock.

### 3. Center habit graph content

Fix alignment at the shared graph boundary rather than adding padding to each
card.

- Measure the available graph viewport and the rendered chart width using the
  existing fixed cell and gap metrics.
- When the chart fits, render it centered in the viewport and avoid a trailing
  scroll anchor that makes the graph appear shifted right.
- When the chart is wider than the viewport, keep horizontal scrolling and the
  current trailing-date behavior so today remains discoverable.
- Apply the same geometry decision to previews and GitHub graphs where the
  same layout is used, without changing their date window or tile scale.
- Keep month labels aligned to the first tile column after centering; labels
  must never be centered independently from the graph.
- Verify narrow devices, iPad/Split View, RTL, large Dynamic Type labels, and
  the graph's loading state.

Do not solve this with a hard-coded screen width or an arbitrary negative
offset.

### 4. Simplify the shared tile visual language

Refine `ContributionTiles` and `ContributionChart`; do not create a second
habit/GitHub graph component.

- Remove the visible per-tile outline currently supplied for adaptive
  surfaces. Tile color and the gap should define the grid.
- Keep a single quiet graph backing surface only where the selected
  Darstellung material needs contrast. It must not look like a second card
  behind every tile.
- Keep the empty level readable through fill contrast, not a white stroke.
- Reserve outlines for semantic states only: today, selected history cells,
  or an accessibility/high-contrast variant.
- Use one consistent radius, gap, and tile size across habit and GitHub app
  graphs. Widgets should consume the same renderer wherever their geometry
  permits; widget-specific colors remain caller-owned.
- Keep future cells visually quiet and preserve the declined/negative level.
- Check light, dark, Increased Contrast, Reduce Transparency, background image,
  and all existing palette variants before removing any contrast safeguard.

The target visual is a calm continuous field of colored tiles with deliberate
gaps, not a collection of individually outlined white squares.

### 5. Rework Account and Standardzeitzone page shells

Use the existing More secondary-page conventions instead of inventing special
sheet styling.

- Route both pages through the same appearance-aware wrapper used by the other
  More detail pages: background ownership, `themed(...)`, settings surface,
  large title, continuous header blur/fade, safe-area spacing, and toolbar
  treatment.
- Keep Account's existing alias, Apple sign-in, sign-out, and entitlement
  boundary behavior unchanged. This is a shell/layout change only.
- Keep timezone selection, search, inheritance, device timezone, localization,
  and accessibility identifiers unchanged. Only improve page hierarchy,
  selected-state clarity, row alignment, and material propagation.
- Make a Darstellung change immediately visible on both pages, including
  Solid, Milchglas, Liquid, Adaptive, dark mode, and background image modes.
- Remove any nested opaque `List` or sheet background that prevents the chosen
  appearance from reaching the page. Keep readable row surfaces where they
  are needed for contrast.
- Keep the page title, search field, and first row clear of the continuous
  header fade at all Dynamic Type sizes.

Prefer applying the existing modifiers and page shell over adding a new
`AccountPageStyle` or `TimezonePageStyle` abstraction.

## Focused Regression Coverage

Extend existing tests rather than creating a new test framework.

### Swipe

- slow pull opens the correct side;
- velocity changes the settle destination predictably;
- cancelled and reverse-direction pulls return exactly to zero;
- vertical scrolling closes the row and remains available to the List;
- another row closes the first row;
- an exposed button is tappable only when fully exposed;
- reminder action runs once and cannot also toggle its checkmark;
- full-swipe commits only the allowed primary action;
- Reduce Motion and RTL preserve semantics.

Add one UI test that captures the row at three states: during opening,
after cancellation, and after a committed action. The test should verify the
accessibility/action state and stable row geometry; pixel comparison may be
used for a local screenshot review but should not be the only assertion.

### Graph

- a fitting habit graph has equal leading and trailing optical space;
- an overflowing graph still scrolls and keeps today at the trailing side;
- month labels move with the graph and do not clip;
- the shared tile renderer has no adaptive per-tile border;
- today/selected outlines remain visible in dark mode and Increased Contrast;
- habit, GitHub, preview, and widget renderers preserve the same tile geometry.

### Settings appearance

- Account and Standardzeitzone use the shared header/surface modifiers;
- changing Darstellung updates both pages without reopening them;
- search and selection remain usable in dark mode, background-image mode, and
  large Dynamic Type;
- existing account and timezone actions still invoke their original handlers.

## Verification

### Completed on 2026-09-13

- `git diff --check` passed.
- Full localized unit target passed: `1746` tests, `0` failures, using
  `/Applications/Xcode.app` and the iPhone simulator destination.
- Focused UI test `ReminderInteractionUITests/testReminderCheckmarkAndRevealButtonsRespondToTouches` passed.
- Focused UI test `ReminderInteractionUITests/testReminderSwipeStartingOnCheckmarkRevealsReset` passed.
- The app, widget, and test targets compiled as part of the full unit run.
- Scope review found no changes in the current uncommitted diff to recurrence,
  check-off logic, notifications, StoreKit, iCloud, Calendar/Reminders,
  widgets, GitHub data, or import/export.

The focused UI tests emitted only the simulator's existing debugger lookup
warning. The broader visual matrix below still requires manual review on a
real device or an explicitly configured simulator session; source-contract and
unit tests are not treated as visual proof.

1. Run `git diff --check` and the focused unit/source tests.
2. Run the full German-localized Xcode test suite with the repository's normal
   Xcode toolchain.
3. Run the focused UI tests on an iPhone simulator in light and dark mode.
4. Review screenshots for swipe opening/cancellation, graph centering, graph
   tile surfaces, Account, and Standardzeitzone.
5. Repeat the interaction checks with Reduce Motion, Increased Contrast, RTL,
   and large Dynamic Type.
6. Inspect the diff for accidental changes to recurrence, check-off logic,
   notifications, widgets, GitHub data, StoreKit, or native sync.

If full Xcode, Simulator, or a physical device is unavailable, report that as
an environment limitation. Source-contract tests must not be reported as
proof that animation or appearance behavior is fixed.

## Acceptance Criteria

- Habit and reminder swipes track the finger with no visible lag.
- Open, close, cancellation, reverse direction, and full-swipe return use one
  coherent motion profile and leave no stale hit target.
- The habit graph is visually centered when it fits, while overflowing graphs
  retain correct scrolling and date anchoring.
- Habit and GitHub graphs show a unified fill-based tile field without a white
  border around every tile.
- Account and Standardzeitzone visibly follow the selected Darstellung on first
  render and after an in-place appearance change.
- Existing data, actions, localization, accessibility, and integrations remain
  behaviorally unchanged.
- No new dependency, navigation architecture, sync system, or product area is
  introduced.

## Out of Scope

- New swipe actions or new habit/reminder features.
- Another redesign of Statistics, More, History, or the overall navigation.
- Changes to recurrence, StoreKit, notifications, iCloud, Calendar/Reminders,
  widgets, GitHub fetching, or import/export semantics.
- A new graph data model or a second tile renderer.
- TestFlight or App Store Connect upload as part of this plan.
