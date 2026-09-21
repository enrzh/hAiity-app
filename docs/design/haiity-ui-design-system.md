# hAiity UI Design System

Status: implemented contract - shared settings and graph foundations verified
Date: 2026-09-21
Scope: shared UI language for the existing iOS app

This document is the visual and interaction contract for the UI unification
plan. It describes how existing parts should look and behave when they are
refactored. It does not add product features.

## Product character

hAiity is a repeated daily-use tool, not a dashboard or a marketing surface.
Its visual identity is **quiet rhythm, visible progress**:

- the page is a continuous canvas rather than a stack of floating cards;
- the contribution grid is the signature visual element;
- system controls carry navigation and actions;
- glass is reserved for the functional layer above content;
- space, hierarchy, and fill contrast do more work than borders and decoration.

The design should feel unmistakably native to iOS while remaining recognizable
as hAiity through its contribution-grid rhythm, restrained palette use, and
calm German/English copy.

## Layer model

```text
+----------------------------------------------+
| Functional chrome: header, toolbar, tab bar  |  glass/material, floating
+----------------------------------------------+
| Content canvas                               |  selected appearance background
|   title / section rhythm                     |
|   repeated item or settings surface          |  solid/standard material
|   graph tiles                                |  fill contrast, no tile borders
+----------------------------------------------+
```

### Canvas

- The selected appearance background owns the full available screen.
- Scroll content extends behind system chrome and includes bottom clearance.
- Do not create a separate opaque page background inside every screen.

### Content surfaces

- A surface groups related content; it is not decoration.
- Settings sections have one clear grouping treatment.
- Repeated items may have a surface, but do not put a card inside another card.
- Use standard materials or the existing solid fallback in the content layer.

### Functional chrome

- Navigation, header, tab bar, temporary actions, and toasts use the existing
  shared material path.
- The fade/blur transition belongs to chrome, not to every content card.
- Reduce Transparency and Increased Contrast must resolve to a legible solid
  fallback without changing hierarchy.

## Tokens

`Theme.swift` is the only token owner. These existing values are the baseline:

| Role | Owner | Current value |
| --- | --- | ---: |
| Base spacing | `Theme.Metrics.gap` | 8 pt |
| Screen gutter | `Theme.Metrics.gutter` | 16 pt |
| Card/graph padding | `Theme.Metrics.cardPadding` | 12 pt |
| Surface radius | `Theme.Metrics.cardRadius` | 16 pt |
| Minimum hit target | `Theme.Metrics.hit` | 44 pt |
| Control height | `Theme.Metrics.control` | 52 pt |
| Settings row minimum | `Theme.Metrics.settingsRowMinHeight` | 52 pt |
| Settings row gap | `Theme.Metrics.settingsRowGap` | 4 pt |
| Settings section gap | `Theme.Metrics.settingsSectionGap` | 24 pt |
| Icon slot | `Theme.Metrics.glyph` | 32 pt |
| Graph tile size | `GridCell.size` | 12 pt |
| Graph tile gap | `GridCell.gap` | 3 pt |
| Graph tile radius | `GridCell.radius` | 2 pt |

Rules:

1. Reuse a named token before adding a literal.
2. Add a token only when the value is semantic and used by at least three
   callers.
3. Keep graph geometry separate from general UI geometry.
4. Do not make a token configurable merely to avoid choosing a value.

## Color and appearance

- Use semantic system colors for labels, fills, separators, success, and
  destructive actions.
- Resolve custom palette colors through the existing `Theme` APIs so light,
  dark, Increased Contrast, and grayscale have one owner.
- Use the global accent for primary action and progress emphasis, not as a
  background wash on every control.
- Use a distinct symbol, shape, or label with color for status changes. Never
  make completion, decline, selection, or focus color-only.
- Graph levels are fill-driven. Use an outline only for a meaningful state such
  as today, selected range, focus, or an accessibility mode.
- Dark mode uses the same semantic roles, not a second hard-coded palette.

## Typography

Use the system type scale and let Dynamic Type determine actual size:

| Role | SwiftUI style | Use |
| --- | --- | --- |
| Root title | `.largeTitle.weight(.bold)` | Habits, Search, Stats, More |
| Compact title | `.title2.weight(.bold)` | collapsed navigation title |
| Section title | `.headline` | settings and content groups |
| Primary item | `.body.weight(.semibold)` | habit/reminder names |
| Supporting text | `.subheadline` | explanations and summaries |
| Metadata | `.caption` | recurrence/time/detail text |

Text rules:

- Use `fixedSize(horizontal: false, vertical: true)` when rows may wrap.
- Never shrink text to preserve a one-line row at AX5.
- Keep icon-only controls labeled for VoiceOver.
- Avoid using a caption as the only indication of an important state.

## Shared component contracts

### `AppPageHeader`

Purpose: one title and scroll handoff model for root and secondary pages.

Required behavior:

- uses the existing `RootPageTitle` geometry and compact title handoff;
- supports optional subtitle without changing title alignment;
- respects safe area, Dynamic Type, Reduce Motion, and VoiceOver heading traits;
- does not own navigation or page-specific actions.

### `AppSettingsRow`

Purpose: align settings labels and trailing native controls.

```text
 [icon]   Title                         trailing control/value/chevron
          Optional detail text
```

Required behavior:

- minimum 44-point hit region, with a 52-point default row rhythm;
- independent hit testing for a trailing `Picker`, `Menu`, `Toggle`, or
  `Button`;
- title and detail wrap at larger text sizes;
- optional divider belongs to the group, not duplicated by each row;
- the component contains layout only, never persistence or routing.

### `AppItemSurface`

Purpose: consistent visual framing for repeated habit, reminder, search, and
stats items.

Required behavior:

- owns padding, surface, clipping, and content shape only;
- does not own swipe state, check-off state, context menus, or model logic;
- remains usable with a transparent/solid accessibility fallback;
- keeps the existing item-specific content and action hit targets.

### `AppGraphSurface`

Purpose: keep habit and GitHub graph framing aligned.

Required behavior:

- centers fitting graphs with equal leading/trailing padding;
- scrolls only when the graph genuinely overflows;
- keeps month labels outside the tile field when shown;
- keeps tile fill treatment free of decorative per-tile borders;
- preserves each caller's data, title, username, and context actions.

### `AppToast`

Purpose: one compact, accessible transient feedback surface.

Required behavior:

- uses the tab-bar safe-area clearance and existing appearance surface;
- stays compact enough not to cover the content it describes;
- announces meaningful changes to VoiceOver;
- respects Reduce Motion and does not require timed dismissal to be understood.

## Page recipes

### Root pages

```text
Root title + optional subtitle
Section rhythm
Primary content surface or list
Bottom clearance for tab bar
```

Habits keeps the graph-led item layout. Search keeps its dedicated tab and
visible native search field. Stats keeps its statistics hierarchy. More remains
a settings hub rather than a dashboard.

### Secondary pages and sheets

```text
Shared navigation/header chrome
One continuous scroll surface
Grouped settings sections
Native controls in trailing slots
Explicit Done/Close action where appropriate
```

Account, Appearance, Notifications, GitHub settings, and habit behavior use
the same header, section, row, material, and bottom-clearance rules. The
standard timezone remains a direct selector on More; it is not a secondary
page.

The shared settings-row contract is used by the More hub, appearance and
behavior controls, GitHub display settings, and Reminder Setup. Native menus,
toggles, and permission actions remain owned by those callers; the shared row
only owns icon alignment, text wrapping, spacing, and hit-target geometry.

### Graphs

The graph is content, not chrome:

- no liquid-glass tile container;
- no white outline around every tile;
- consistent tile scale and gap through `GridCell`;
- equal horizontal padding when the graph fits;
- semantic outline/state cue only where needed;
- visible empty, selected, today, complete, declined, and loading states.

Habit, GitHub, and history previews use the same `ContributionChart` and
`ContributionTiles` path. A separate graph wrapper is intentionally not part
of the system: the shared renderer already owns fit-versus-scroll behavior and
equal horizontal centering, while each caller retains its own interaction and
data semantics.

## Interaction and motion

- Prefer native `Button`, `Picker`, `Toggle`, `TabView`, `NavigationStack`, and
  context-menu behaviors.
- Keep swipe gestures direct and cancellable. The action should track the
  finger, settle briefly, and close when vertical scrolling or another row
  takes ownership.
- Keep explicit button/VoiceOver alternatives for every swipe action.
- Use existing `SwipeRevealMotion` for gesture physics; do not duplicate spring
  constants in row views.
- Use haptics as a secondary confirmation, never as the only state signal.
- Reduce Motion removes nonessential settling and transition animation while
  retaining state changes and hit behavior.

## Accessibility quality floor

Every shared component must pass:

- Dynamic Type through AX5 without clipped or hidden text;
- VoiceOver heading, label, value, and action order;
- 44-point default hit targets and 28-point minimum where a smaller visual is
  unavoidable;
- light/dark and Increased Contrast contrast checks;
- Reduce Motion and Reduce Transparency fallbacks;
- RTL layout and mirrored swipe action semantics;
- grayscale/state checks where color could otherwise be the only cue.

## Review checklist

Before merging a component migration:

- Does this component have at least three real callers?
- Is its API semantic and small, with no business logic?
- Does it reuse `Theme` rather than define parallel tokens?
- Does it preserve native control hit testing?
- Does it survive AX5, dark mode, Increased Contrast, and Reduce Motion?
- Is the component simpler than the duplicated code it replaces?
- Can one caller remain local without creating a second style system?

If the answer to the last question is yes, keep the caller local.

## HIG anchors

The direction follows the local Apple Design review references:

- `accessibility.md` -> Dynamic Type, semantic color, alternatives to gestures,
  and 44-point controls;
- `layout.md` -> grouping, hierarchy, and content extending beneath chrome;
- `materials.md` -> Liquid Glass for functional chrome, standard materials for
  content;
- `motion.md` -> purposeful, brief, gesture-connected, cancellable motion;
- `searching.md` -> one clear, primary search location.

These are constraints for the existing app, not a reason to introduce new
features or imitate another app screen-for-screen.
