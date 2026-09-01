# Large Widget Redesign: Featured Progress

## Status

Approved direction: **B, Featured progress**.

This redesign changes only the native SwiftUI rendering of the registered
large `Liste` and `Raster` widgets. It does not change the widget data model,
AppIntent configuration, deep links, or the unregistered `Fokus` compatibility
renderer.

## Goals

- Make the large widgets feel like one intentional Apple-style surface rather
  than a collection of nested legacy cards.
- Give the graph enough area to communicate progress at a glance.
- Keep names, status, metrics, reminders, and quick actions readable without
  truncation at the supported widget geometry.
- Keep light, dark, full-color, vibrant, and accessibility rendering stable.

## Visual Design

### Liste

The widget keeps the existing `Heute` header and overall progress summary.
The first resolved item is the featured item:

1. A large contribution graph occupies the primary visual area.
2. The item name, emoji, status, streak or metric, and reminder timing are
   layered at the graph edges instead of consuming a separate card row.
3. The featured item keeps its existing AppIntent actions with 44pt targets.

The remaining visible items become up to three compact status rows. Each row
contains only the name, one status/metric treatment, and its quick actions.
Secondary rows do not render a second mini graph. Rows share the widget
surface, use lightweight separators, and do not receive individual material
cards or shadows.

When the featured item is a reminder, its primary visual area is a calm
schedule/status treatment with the reminder symbol and timing. A reminder
never receives a fake contribution graph.

### Raster

The widget keeps its existing two-column, four-visible-position layout and
selection order. Each tile becomes graph-first:

1. A single compact identity line contains the emoji, name, and status symbol.
2. The contribution graph fills the middle of the tile.
3. A flat bottom action rail contains the metric and configured quick actions.

The action rail has no capsule nested inside the tile. The tile may retain one
subtle material/tint surface and a restrained border for separation from the
widget background. Reminder tiles use the same identity/action structure but
replace the graph region with a readable timing/status band.

Six configuration slots remain supported by `LargeWidgetGridIntent`; the
renderer continues to show the four positions that fit the registered large
widget geometry, preserving the current deterministic order.

## Interaction and Data Flow

- `HaiityEntry.largeItems` remains the sole resolved input for both renderers.
- Existing `CheckOffHabitIntent`, `AnswerYesHabitIntent`,
  `AnswerNoHabitIntent`, and `ResetHabitIntent` bindings stay attached to the
  current habit, never to the parent collection.
- Existing `HomeWidgetBackground`, `HomeWidgetInk`, palette resolution, and
  WidgetKit rendering-mode handling remain the source of background and graph
  colors.
- All item content continues to link to `HaiityWidgetLink.habits`; no item
  deep link is introduced.
- Empty state continues to use `WidgetEmptyState` and the existing habits link.

## Geometry and Accessibility

- Keep the fixed reference canvas at 332 x 356 points and the existing outer
  inset contract unless a measured layout change is required by the new
  hierarchy.
- Use explicit bounded bands for identity, graph/status, and actions so
  Dynamic Type cannot push content into another region.
- Keep the current widget Dynamic Type cap used by the rendering tests, while
  preserving `.minimumScaleFactor` only as a last-line fallback for names and
  metrics.
- Keep every interactive action at least 44 x 44 points and expose concise
  accessibility labels for each intent.
- Do not rely on color alone for done, declined, open, or reminder state; keep
  the existing symbols and text metrics.

## Failure and Mode Handling

- No history: render the same stable empty graph/status region rather than
  collapsing the tile.
- Missing or stale selected item: preserve the existing provider resolution
  behavior; the view only renders the resolved `largeItems`.
- Vibrant or non-full-color mode: continue using the existing monochrome ink
  mapping so graph levels remain distinguishable.
- Light/dark mode: use semantic/system materials and existing palette helpers;
  do not introduce a hardcoded dark-only surface.

## Verification

Update focused rendering tests to assert the new structure and render all
large views in:

- light and dark appearance;
- full-color and vibrant WidgetKit modes;
- checkbox, quantity, Yes/No, and reminder items;
- reset enabled and disabled;
- sparse data and empty state;
- accessibility-large and accessibility-extra-extra-extra-large text sizes;
- full 332 x 356 point geometry with no foreground pixels crossing reserved
  gaps or falling outside the widget canvas.

Run the focused widget test suite and verify representative screenshots with
the existing single SimSlim simulator. Do not use DeviceHub or add another
simulator.

## Non-goals

- No new widget type, data model, persistence field, or AppIntent parameter.
- No redesign of the small/medium widgets, graph-only widgets, or live
  activities.
- No changes to the app's habit/reminder screens.
- No TestFlight release as part of the design-spec step; release happens only
  after implementation and verification.
