# hAiity Large Widget Contribution-first UI Redesign

Date: 2026-08-28
Baseline: `217f941` (`release: large widget variants build 119`)
Scope: visual and layout redesign of the three configurable `systemLarge` habit widgets. This is a design specification only; it does not authorize product-code changes.

## Goal

Make contribution history the primary reading surface. A user should understand recent activity, today's state, and the next available action in one glance, without four competing cards or large decorative status treatments.

The three approved layouts remain selectable as `list`, `grid`, and `focus`:

- **Liste:** one vertical sequence, with a materially larger graph per habit and no nested/repeated card treatment.
- **Raster:** six graph-led tiles in a 2 x 3 matrix. The header has its own reserved row and never overlaps a tile.
- **Fokus:** one genuinely dominant graph followed by three lightweight queue rows.

The existing entry resolution, habit ordering, status semantics, palette transport, WidgetKit rendering modes, AppIntents, deep links, and configuration intent remain the source of truth. No new manager, service, protocol, factory, or other architecture layer is part of this design.

## Reference geometry

The reference render is the current test canvas: `332 x 356` points. The existing outer inset is `12pt`, leaving a `332pt` high content budget and a `308pt` wide content area (`332pt` wide before the inset is applied by the renderer). All dimensions below are point budgets at that reference size. SwiftUI must use the existing `LargeGeometry` constants or equivalent values in the existing view files, with no geometry that depends on a second, conflicting budget.

Global rules:

- Outer inset: `12pt` on all sides.
- Header-to-content spacing: `4pt`.
- Tile/row spacing: `4pt` unless explicitly listed below.
- Minimum interactive hit area: `44 x 44pt`, even when the visible action glyph is smaller.
- Content must fit inside `332pt` high. No clipping, negative offsets, or overlap is acceptable.
- The graph always reads chronologically left-to-right, with today at the right edge; no wrapped or mirrored graph.

### Liste budget

| Region | Height | Requirement |
| --- | ---: | --- |
| Header | `20pt` | “Heute” and the global due/met summary; one line only |
| Four rows | `4 x 72pt` | Single column, stable row height |
| Three row gaps | `3 x 4pt` | Consistent separation, no card borders |
| Bottom breathing room | `4pt` | Prevents the final graph from touching the inset |
| **Total** | **`324pt`** | Leaves `8pt` tolerance inside the `332pt` budget |

Each row is an unframed layout band, not a card: title and compact status at the top (`18pt`), contribution graph below (`38pt`), and a visually quiet action affordance aligned to the trailing edge within the existing row. The graph gets the majority of the row's visual area. Do not repeat the same habit as a full background card, graph card, and metadata card. The habit link covers the informational row surface; actions remain separate controls.

### Raster budget

| Region | Height | Requirement |
| --- | ---: | --- |
| Header | `20pt` | Dedicated, non-overlapping header band |
| Header gap | `4pt` | Separates header from matrix |
| Three tile rows | `3 x 96pt` | Exactly six tiles, two columns |
| Two matrix gaps | `2 x 8pt` | Horizontal and vertical grid spacing |
| **Total** | **`324pt`** | Leaves `8pt` tolerance inside the `332pt` budget |

Tile width is the available content width minus one `8pt` column gap, divided equally. Each tile reserves its top `20pt` for the name and status, then gives the graph a minimum `48pt` high region. Actions sit in a trailing control strip with a `44pt` hit target and must not consume the header's vertical space. The graph, not the tile background, is the tile's visual anchor.

The six resolved items are shown in resolved list order, limited to six. A tile may be visually quiet, but it must not disappear because its habit is incomplete or has a reminder state.

### Fokus budget

| Region | Height | Requirement |
| --- | ---: | --- |
| Header | `20pt` | Dedicated global summary |
| Header/featured gap | `4pt` | Stable separation |
| Featured item | `136pt` | One dominant graph and title/status |
| Three queue rows | `3 x 48pt` | Lightweight rows, no nested cards |
| Queue gaps | `3 x 4pt` | Stable rhythm |
| **Total** | **`312pt`** | Leaves `20pt` tolerance for safe breathing room |

The featured graph receives at least `92pt` of usable graph height after title/status and compact action allocation. Queue rows show title, today's state, and a short graph strip only when it remains legible; they must not visually compete with the featured item. The first resolved item remains the featured item; do not silently reorder by today's status.

## Visual hierarchy

1. Contribution graph: largest area, strongest contrast, and the first scan target.
2. Habit identity: name and optional emoji, one line, readable at Dynamic Type sizes.
3. Today's state: small text or symbol, semantically precise.
4. Action: quiet glyph treatment, never a pill or prominent button bar.
5. Secondary metadata: streak or metric only where it supports the graph and fits without truncation.

Completed state uses only a small accent: accent-colored text, glyph, or thin indicator. It must never tint an entire row, tile, or featured surface green/accent. Open state uses secondary hierarchy. Declined remains the existing negative palette meaning and must not be mistaken for incomplete. Free days retain the existing “frei” semantics and do not render as completed.

## Reminder treatment

Reminders are graph-free by definition. They use a simple bell mark, title, due/missed text, and the same quiet action affordance as other items. No empty graph rectangle, fake contribution cells, flame streak, or graph placeholder is shown. A reminder can occupy a Liste row, Raster tile, Fokus featured slot, or queue slot without changing geometry; its content aligns to the same title/status baseline.

Reminder missed state uses the existing negative/status semantics in text or a small accent mark only. It does not color the whole item. Completing a reminder uses the existing `CheckOffHabitIntent` and the existing reminder accessibility label.

## Actions and links

Informational surfaces remain deep links:

- Habit information links to `HaiityWidgetLink.habit(habit.id)`.
- Empty states link to `HaiityWidgetLink.habits`.
- The graph and title/metadata area belong to the informational link, except where an action control occupies the hit target.

Actions remain the current AppIntent behaviors: yes/no answer, quantity increment, checkbox/reminder check-off, and optional reset. Do not add new actions or change configuration meaning. Visible glyphs are deliberately subordinate: no filled capsule, no large colored button background, and no decorative action container. Every action still exposes a `44 x 44pt` hit area, has a localized accessibility label, and remains independently tappable from its surrounding `Link`. The reset action is shown exactly when `widgetResetEnabled` is true, including before the first decision.

## Empty and partial data

Empty `largeItems` uses the existing shared empty state and the existing habits deep link in all three layouts. The empty state must be visible in light, dark, and non-full-color rendering modes and must not imply that the user has completed anything.

Partial data means fewer than the layout's nominal capacity, stale/missing graph history, or a mixture of habit kinds. Preserve resolved order and preserve geometry:

- Liste shows available rows and leaves remaining budget as breathing room; it does not stretch one habit into a replacement card.
- Raster keeps the 2 x 3 matrix positions stable; absent positions remain quiet empty space, not fabricated habits.
- Fokus keeps one featured slot when at least one item exists and shows only the available queue rows.
- A valid habit with no contribution history renders an empty seven-row graph using the existing level-zero treatment. Missing history is not “done”.
- A reminder remains graph-free in every partial-data case.

## Appearance and color

### Light and dark

Use `HomeWidgetBackground`, the existing `Theme`, `HomeWidgetInk`, and the entry-carried palette. Light mode must retain sufficient contrast for level 1 and secondary text; dark mode must not turn the graph into a flat glowing block. Background surfaces are translucent or unframed according to existing widget conventions, but the redesign removes per-item accent fills as the default visual container.

### Vibrant and other non-full-color modes

When WidgetKit supplies `.vibrant` or another non-full-color mode, preserve contribution level distinctions through the existing monochrome/opacity mapping rather than arbitrary palette colors. Keep the same geometry and hierarchy; do not replace graphs with text or hide action targets. Verify the background remains legible without assuming full-color blending.

### Custom palettes

Resolve each habit's existing custom palette through `entry.palettes.style(for:)`. A custom palette colors graph levels and small accent/status marks only. It must not recolor the complete row, tile, or featured region. Negative status continues to use the palette's negative color; secondary and open states use hierarchical system styles. Palette fallback and global palette behavior remain unchanged.

## Testing and acceptance

Extend the existing `HaiityTests/WidgetRenderingTests.swift` coverage and keep the tests focused on observable contracts:

- Assert each layout's explicit height sum is at or below `332pt`, including the new Liste, Raster, and Fokus budgets.
- Render representative complete, sparse, mixed-kind, reminder, and empty entries at `332 x 356` and assert non-empty output.
- Add geometry assertions or image checks that the Raster header occupies its reserved band and that six tile graphs do not overlap the header or each other.
- Add image fixtures/checks for Liste's larger graph region, no repeated card/background treatment, and Fokus featured-versus-queue scale.
- Assert reminders render without `TrailingGrid`/graph content and with their existing action intent.
- Render light, dark, vibrant, and custom-palette variants for all three layouts.
- Render at the existing accessibility Dynamic Type size and assert the output remains the expected pixel dimensions with no clipping or missing primary graph.
- Preserve existing link, action, reset-before-first-decision, status, palette, and empty-state assertions.
- Use accessibility labels and intent type assertions where rendering alone cannot prove Link/action separation.

Review screenshots at the reference canvas and at the largest supported Dynamic Type size. A passing test that only counts visible pixels is insufficient for overlap, hierarchy, or duplicate-card regressions; visual fixture review is part of acceptance.

## Non-goals

- No product-code implementation in this change.
- No change to habit ordering, recommendation, recurrence, status calculation, graph data, timeline refresh, or configuration intent.
- No new widget family, new graph algorithm, wrapped-year graph, or alternate chronology.
- No new persistence, networking, analytics, or architecture abstraction.
- No redesign of the separate GitHub contribution widget.
- No removal of AppIntent actions, deep links, Dynamic Type support, glass/material behavior, vibrant behavior, or custom colors.
- No full-card completion coloring, decorative card nesting, or reminder graph placeholder.

## Self-review result

The specification has one geometry source, explicit behavior for all three layouts, clear action/link ownership, defined empty and partial states, and no unresolved placeholders or contradictory requirements. The document describes design intent and acceptance criteria only; implementation planning is intentionally out of scope.
