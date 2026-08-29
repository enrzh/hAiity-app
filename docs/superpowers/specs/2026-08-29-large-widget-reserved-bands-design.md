# hAiity Large Widget Reserved-Band Design

Date: 2026-08-29
Baseline: `25c08dd` (build 122)
Scope: refine the existing native SwiftUI `Liste`, `Raster`, and `Fokus` system-large widgets.

## Context and goals

The three large widgets already have the intended content and actions, but the
fixed canvas makes identity, graph or reminder timing, and actions compete for
space. Long names, wide emoji, status values, and the graph can therefore feel
compressed even when the renderer reports the correct overall size.

The goal is a glanceable, native layout with explicit content ownership: every
item gets a one-line identity/status band, a full visual band, and an action
band that cannot overlap either. The graph remains the primary visual signal;
reminders remain graph-free. Existing data, links, AppIntents, palettes,
configuration, and Pro visibility are unchanged.

## Design foundations

- Keep the existing `332 x 356pt` reference canvas and outer widget padding.
- Use the existing 4/8/12pt spacing rhythm and `LargeGeometry` constants.
- Preserve 44 x 44pt independent action hit targets and localized labels.
- Keep identity to one line: optional user emoji plus the habit/reminder name.
- Use compact symbols and values for status; do not add sentence-length copy.
- Do not layer a second card, shadow, or material surface over an item.
- Keep Dynamic Type capped at the existing non-overlapping accessibility size.

## Component layout

### Liste

Each of the four fixed rows reserves its title/status line, then a graph or
reminder timing region, while the existing action controls stay in their own
trailing region. The visual region may use all remaining content width but may
not be shortened by status text. A reminder uses the same timing region without
rendering a fake graph.

### Raster

The 2 x 2 grid remains fixed. Each tile has three exclusive vertical bands:

1. Identity and compact status.
2. Graph, or centered reminder timing.
3. Quiet action strip with independent 44pt targets.

The graph starts below the identity band and ends before the action strip. The
tile and grid constants must leave the existing inter-tile gaps and remain
inside the 332pt content budget.

### Fokus

The first item remains the featured item and receives the largest graph. Its
identity, visual region, and action region stay bounded. The following queue
rows remain graph-free and show only identity, compact state or reminder
timing, and actions. Missing queue items leave quiet space rather than causing
another item to stretch unexpectedly.

## Content and appearance

- Show a habit graph only for tracked habits.
- Show a bell and the existing reminder metric for reminders.
- Keep checkbox, quantity, and yes/no status semantics intact.
- Keep done/declined/open meaning visible through glyphs or values, not color
  alone.
- Reuse `Theme`, `HomeWidgetInk`, `HomeWidgetBackground`, and per-habit palette
  resolution across light, dark, vibrant, and full-color modes.
- Long names and emoji must truncate or scale within their identity band;
  controls and the primary graph must not be clipped.

## Accessibility and interaction

- Links cover informational identity and graph/timing regions only.
- AppIntent buttons remain separate accessibility elements from links.
- Every visible action retains its localized accessibility label and a 44pt hit
  target, including reset before the first decision.
- Dynamic Type uses the existing cap; no hard-coded per-language text widths.
- Empty and partial data use existing deep links and empty-state behavior.

## Testing

Extend the existing `WidgetRenderingTests` contracts before production edits:

- Assert each layout's reserved bands fit inside the 332pt content budget.
- Render all three layouts with long names, wide emoji, checkbox, quantity,
  yes/no, reminder, reset enabled, and partial data.
- Assert graph/timing regions begin after identity and end before actions.
- Assert reminder regions contain timing and no `TrailingGrid`.
- Render light, dark, vibrant, full-color, and accessibility Dynamic Type
  variants at the real large-widget pixel size.
- Keep existing deep-link, action-label, palette, empty-state, and reset
  contracts passing.

## Non-goals

- No new widget family or widget configuration.
- No changes to habit ordering, recurrence, status calculation, or timeline
  refresh.
- No new data model, dependency, manager, service, protocol, or layout
  framework.
- No redesign of the separate GitHub widget.
- No product behavior change beyond visual separation and clipping prevention.

## Self-review

The design names one layout rule for each large widget, preserves the existing
native surfaces and actions, defines reminder and partial-data behavior, and
keeps the implementation limited to the current widget views, geometry, and
rendering tests. It contains no unresolved placeholders or conflicting
geometry requirements.
