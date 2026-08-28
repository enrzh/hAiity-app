# hAiity Large Widget Native Polish Design

Date: 2026-08-28
Baseline: `51804e0` (build 121)
Scope: polish the existing native SwiftUI `Liste`, `Raster`, and `Fokus` system-large widgets.

This document refines `2026-08-28-large-widget-ui-redesign.md`. Its compact-content rules supersede that document where they differ; widget configuration, ordering, persistence, intents, links, palettes, and business logic remain unchanged.

## Context and goals

The widgets already expose the right three layouts, but text, actions, emoji, and graphs compete for the same small regions. The redesign must make every layout glanceable with long Chinese names, wide emoji, all habit types, and optional reset actions while remaining recognizably native WidgetKit UI.

The graph is the primary visual signal for habits. Reminders remain graph-free. No new widget type, data model, dependency, manager, service, protocol, or reusable architecture layer is introduced.

## Design tokens and foundations

- Reference canvas: `332 x 356pt`; existing `12pt` outer padding and `332pt` content-height budget remain authoritative.
- Spacing uses the existing `4/8/12pt` rhythm.
- Every AppIntent action keeps a `44 x 44pt` hit target. Its SF Symbol may be visually smaller.
- Identity is exactly optional emoji plus one-line name. Remove fixed-width emoji frames; the name receives layout priority over status.
- Status is compact: `checkmark`, `xmark`, `2/3`, or a short reminder date/time. Sentence forms such as `Heute erledigt` are prohibited inside item rows.
- Graph height never shrinks to preserve optional text.
- Existing `Theme`, `HomeWidgetInk`, `HomeWidgetBackground`, `TrailingGrid`, palette resolution, and WidgetKit rendering modes remain the visual source of truth.
- Emoji are user content, not control icons. Controls continue to use SF Symbols.

## Component rules

### Shared header

Keep one line with `Heute` and a compact `met/due` value or `frei`. Remove sentence copy such as `2 von 4 heute`. The header is secondary to item content and never overlaps the first graph.

### Shared item identity and actions

Each item reserves exclusive regions for identity/status, graph or reminder timing, and actions. Long names truncate after one line; status never forces the name below one line. Actions remain independently tappable Buttons and never sit inside the item Link.

Action availability is unchanged:

- Checkbox and reminder: checkmark, plus reset when enabled.
- Count: plus, plus reset when enabled.
- Yes/no: checkmark and xmark, plus reset when enabled.

### Liste

Show up to four fixed-height rows. Each habit row has a compact identity/status line, a meaningful graph below it, and a stable trailing action region. A reminder uses the graph region for its next date/time rather than an empty graph. Do not add card backgrounds, metadata pills, or streak sentences.

### Raster

Show four native `2 x 2` tiles. Each tile has a one-line identity/status band, a large seven-row graph or reminder timing region, and a dedicated bottom action strip. The action strip must not reduce the graph below the existing approved graph height. No sentence status or fixed `18pt` emoji frame is allowed.

### Fokus

Show one featured item with the largest graph in the family, followed by up to three queue rows. Queue rows intentionally contain no graph: they show identity, compact state or reminder date/time, and stable actions. This prevents unreadably small contribution cells and preserves the featured graph's dominance.

## Accessibility requirements

- Every Button retains its existing localized accessibility label and native Button semantics.
- The informational Link and each action remain separate accessibility elements.
- Action hit regions are at least `44 x 44pt` in all combinations.
- Dynamic Type may truncate secondary state, but must not clip emoji, action symbols, or the primary graph.
- Status meaning cannot depend on color alone; symbols or compact values remain visible.
- Light, dark, vibrant, and custom-palette modes must keep readable text and distinguishable graph levels.

## Content standards

- Prefer symbols and numeric values to phrases: `checkmark`, `xmark`, `2/3`, `09:30`, `28.08.`.
- Do not repeat a habit name, type, streak, and full status sentence in the same item.
- Reminder timing uses the existing summary value; no new scheduling copy or calculation is introduced.

## Anti-patterns

- No graph smaller than the approved geometry merely to fit metadata.
- No graph in Fokus queue rows.
- No fixed-width emoji container.
- No nested cards, material pills, decorative action capsules, or new palette tokens.
- No custom layout abstraction when the existing views and `LargeGeometry` constants suffice.
- No changes to configuration slots, selected items, AppIntent behavior, timeline refresh, or Pro visibility.

## QA checklist

- Render Liste, Raster, and Fokus with long Chinese names and wide emoji.
- Render checkbox, count, yes/no, and reminder content in every layout.
- Render reset enabled and disabled; all visible actions retain `44 x 44pt` hit regions.
- Verify reminders have no graph and Fokus queue rows have no graph.
- Verify Liste and Raster graphs retain their approved heights and the featured Fokus graph remains dominant.
- Render light, dark, vibrant, custom palette, and accessibility Dynamic Type variants.
- Inspect generated widget renders for clipped text, emoji, SF Symbols, overlap, or tiny graphs.
- Run widget rendering, widget logic, and GitHub widget regression suites plus a generic iOS build.

## Self-review

The specification contains no placeholders. It preserves all existing behavior, gives each layout a non-overlapping content hierarchy, resolves the prior queue-graph ambiguity, and uses only existing native SwiftUI and WidgetKit primitives.
