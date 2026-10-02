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
| Data value | text style + `.monospacedDigit()` | statistics numbers |

Data-value rules: every statistics number uses the **default** design with
monospaced digits. Do not mix in a second personality (`.rounded`) for tiles
only, and do not give a streak a heat ramp of its own — the accent means
progress, the trend sentence owns the only other status color. Captions and
metadata wrap at accessibility sizes; never hold a row to one line with
`lineLimit(1)`.

One fact, one place: a value may appear in a summary sentence and in an
accessibility value, but not a third time in a tile or a footer column. When a
summary already carries it, the repeated row is deleted rather than restyled.

Text rules:

- Use `fixedSize(horizontal: false, vertical: true)` when rows may wrap.
- Never shrink text to preserve a one-line row at AX5.
- Keep icon-only controls labeled for VoiceOver.
- Avoid using a caption as the only indication of an important state.
- Root titles have a minimum height and expand with wrapped text; decorative
  floating-control symbols stay within their existing hit region.

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
- A loading graph uses the same bounded viewport as its loaded content. Its
  intrinsic tile width must never drive the width used to fit those tiles.

### `AppToast`

Purpose: one compact, accessible transient feedback surface.

Required behavior:

- uses the tab-bar safe-area clearance and existing appearance surface;
- stays compact enough not to cover the content it describes;
- announces meaningful changes to VoiceOver;
- respects Reduce Motion and does not require timed dismissal to be understood.
- Ordinary Undo expires after six seconds; VoiceOver and accessibility text
  sizes keep it available until an action or navigation replaces it. Wrapped
  accessibility toasts use the card radius so their text is not clipped by a
  capsule.

## Page recipes

### Root pages

```text
Root title + optional subtitle
Section rhythm
Primary content surface or list
Bottom clearance for tab bar
```

Habits keeps the graph-led item layout. Search keeps its dedicated tab and
visible native search field. More remains a settings hub rather than a dashboard.

#### Statistics

```text
Heute          one solid surface: fraction, segmented ring, one sentence
Rhythmus       the merged grid, full card width, same ramp as every other graph
Letzte 7 Tage  seven squares on the same ramp, momentum sentence in the header
Deine Habits   section label + one list surface, rows open the existing card
```

Rules:

- Reading order is today first, then the grid, then the week, then the index.
  Exactly one card is the primary surface; the sections below it stay quiet.
- A day fraction maps onto the **same 0…4 ramp** as the contribution tiles via
  `StatsView.statsDayLevel`. The seven-day strip is not a bar chart, and it does
  not get its own color language. The exact percentage stays visible above the
  square and in the block's accessibility value.
- Keep one block per accessibility element, with the chart's own numbers in the
  value rather than spread over decorative children.
- The metric tiles remain a **customization** for users who ask for them. The
  default selection is Rhythmus + Check-ins; a customized all-five selection
  still shows the grid, so UI tests and existing preferences keep working.
- No extra insight, range, or second graph destination.

### Settings hub

```text
Root title
Grouped panels, grouped by what a person is doing
```

The hub carries three groups — **Alltag**, **Konto & Verbindungen**, **Archiv &
Über** — not one heading per taxonomy. Rows, `AppSettingsRow`, and the group
surface are unchanged by this grouping; only the headings and their order move.

The Apple account entry keeps navigation separate from authentication, like the
GitHub connection row. Its leading label opens the account page; the trailing
native Apple control signs in, or the sign-out action disconnects the local
identity. At accessibility text sizes these targets stack rather than squeezing
the label. The Apple sign-in button keeps at least Apple's 140-point width and
the app's 44-point hit height.

Disconnected GitHub rows offer an explicit sign-in action that opens the GitHub
page. Technical Apple identifiers and their copy action stay exclusively in the
owner-gated developer page; the normal account page shows only name and email.

The account page uses the selected appearance surface for a personal greeting,
an editable alias with a live preview of an existing celebration message, and a
separate Apple identity group. Preview text is explicitly labelled and does not
send a notification. Sign-in remains optional; the alias survives sign-out and
iCloud synchronization remains independent of this identity.

iCloud sync status deliberately stays **off** the hub (it is ambient noise at
rest) and remains on the behavior page. GitHub state is already a hub row.
Settings ownership stays in the page that owns the setting.

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
standard timezone is a direct native `Menu` selector, but it lives inside
**Verhalten & Teilen** rather than loose on the More hub: it is an app-wide
behavior default, so it belongs with the other app-wide behavior controls
instead of competing with the hub's navigation rows for attention. The hub
only carries destinations.

Settings sub-pages are **`ScrollView` + `AppSettingsGroup`**, not `List`.
iOS 27 drops taps on grouped `List` rows, so a tappable settings page must not
use one; `List` is the form that must not come back. This is now the whole
settings surface: the More hub, Notifications, Account, Behavior & sharing, the
GitHub page, the timezone list, the calendar-destination picker, the
Developer page, and the custom-palette sheet. `moreSettingsSection()` is gone
from the app — the list-backed modifier has no callers left, so it should not
be reintroduced.

`AppSettingsGroup` takes an optional leading `symbol`. The hub's groups are
text-only; the Developer page labels its groups with an SF Symbol. One
component serves both rather than the page composing its own.

When a group is migrated, keep each control individually addressable: outside a
`List` a plain container identifier bleeds onto its children, so a group needs
`.accessibilityElement(children: .contain)` or every child answers with the
group's identifier.

A `List` `footer:` has no equivalent in a continuous surface, so its text
becomes a caption inside the group. A `header:` becomes the group label.

A single on/off setting is still a row, not a bare `Toggle` with a long label.
Wrap it in `AppSettingsRow` with a symbol and keep the title to one short
imperative — the mechanism ("automatically", "after completing") belongs in the
caption, not the title, because a toggle is already immediate. A caption that
describes the row above it is indented to the title's left edge, derived from
the badge (`Theme.Metrics.glyph + Theme.Metrics.gap + 4`) so it survives a
metric change. Sub-*controls* like pickers may span the full panel instead;
descriptive text may not, because `AppSettingsRow` already lines its own
`detail:` up with its title.

### On-device generation

Two features use the on-device model: the daily motivational line and the
statistics reading. Both follow the same contract, and neither may break it.

**Availability is asked, never assumed.** `OnDeviceModel.availability` is the
single place `FoundationModels` is touched. The app deploys to iOS 17 while the
framework needs iOS 26 plus an eligible device with Apple Intelligence on, so
every caller branches on that enum instead of on the system version. The writers
are `@available(iOS 26.0, *)`; the UI never shows a control that cannot work, and
says why when it cannot.

**The model writes words, never facts.** For the motivation line the model writes
only the body — the greeting stays in the catalog, because it is translated,
reviewed, and has to place the name per language. For the statistics reading the
facts are extracted in `StatsReadingFacts` (pure, testable, no model), handed over
as a closed list, and every number in the output is checked against that list by
`StatsReadingValidator`. A number the facts do not contain rejects the whole
reading.

**A reading must add something the page does not already say.** The statistics
page's first card owns today, so the reading covers only the pattern over time —
the week against last week, the longest run, the habit carrying it. Restating
today in a second voice is the noise this design system already forbids.

**Nothing runs without a tap.** Running the model makes the device warm, and the
statistics page is the screen people open most. So reading and writing are
separate operations: the cache read is free and happens on every visit, and the
write is reached only from a button. The notification scheduler and the Live
Activity are pure cache reads — a reschedule happens on every settings change
and a reconcile can run in the background, so neither may ever reach the model.
A day without a tap gets the built-in line, which is the same thing an
unavailable model would produce, just cheaper.

A re-roll is a second, separate request for the same heat. It is offered as its
own labelled action and is never inferred, and a repeat tap without one returns
the cached line rather than paying for a second call.

**The block is always visible; its content changes.** The reading block is the
affordance, so it cannot be conditional. An invitation that only appears once it
has a result stays undiscovered. Five states are all rendered and all
explained: idle (the invitation), working, shown, unavailable (which of the four
reasons), and failed. There is no greyed-out placeholder and no silent absence
— a missing sentence would be a small loss, but so would a feature nobody finds.

**Nothing leaves the device.** The retired open-source quote feed was removed
because it broke the app's zero-server promise: its text came from a third-party
repository. The on-device model restores variety without breaking it.

### Notifications: nothing left means nothing sent

A reminder is a statement that something is still outstanding. When it is not,
it is noise, and the person who finished early is the one paying for it.

- **Per-habit reminders** are planned only for a day that is neither done nor
  answered. `habitPlans` skips it, and the pending request for that habit is
  removed and rebuilt on every check-in. Answering "no" counts as handled —
  declining an item must not leave its reminder armed.
- **The daily summary** is suppressed when nothing is outstanding. Finishing
  everything at breakfast must not buy an evening notification reading "Heute
  geschafft: 3 von 3". The perfect-day celebration is the notification that
  belongs to that moment, and it fires on its own from `celebrateIfPerfectDay`.
- **The weekly summary and the motivational line** are not tied to one day
  being done, so they are unaffected.

The rule is tested from both directions: a finished day must produce no plan,
and the *next* day must still be planned — otherwise "don't remind me when
done" would quietly become "stop tracking this habit".

### The speak button

One standing control, in the shell so it is on every tab, in the **trailing
column directly above** the floating control that lives there (the prominent
search button on iOS 27, the create button before it). Trailing rather than
leading because that column already belongs to global actions, and Apple
reserves that trailing slot for search in the tab bar itself
(`tab-bars.md` › Phone (iOS): "A tab bar can include a dedicated search tab at
the trailing end"). Stacking in the same column reads as one group rather than
two unrelated corners.

**It is deliberately the quieter of the two.** Two accent-filled circles in one
column compete for the same glance, and the control underneath is the system's
own search — the primary global action. So the mic gets thin material, a 0.5 pt
border and no drop shadow, while search keeps the glass and the shadow. Apple's
guidance is to keep prominent buttons to one or two per view
(`buttons.md` › Style) and to leave enough space around a button that it can be
told apart from its surroundings — hence the 12 pt stack gap rather than a
touching pair.

The stack is measured, not guessed: `ChromeLayout` carries the trailing
control's inset and diameter, and the mic's offsets are derived from them. When
either diameter changes, the pair stays aligned and the content clearance
follows.

On iOS 26 the search role is a tab rather than a floating control, so the mic
keeps the same trailing position with empty space beneath it rather than moving
per system version — one place for the control beats a position that shifts
between OS releases.

### Dictation

Apple's system keyboard dictation is already available in every text field in
the app and needs nothing from the app to work: no entitlement, no
`NSMicrophoneUsageDescription` (that key is only for recording *inside* the app),
and no API call. The mic lives on the keyboard, not in the field, which is the
usual reason people think it is missing.

Adding an in-app microphone button would mean a second dictation stack —
`Speech`/`AVFoundation`, a permission prompt, its own errors — to duplicate a
control iOS already provides on every keyboard. The cost is not the code, it is
two dictation paths that can disagree. So the app does not add one, and the
creation field is left as a plain `TextField` so dictation keeps working in it.

### Creating items from outside the app

Two App Intents, because they answer two different requests:

- `CreateHabitIntent` — explicit fields (name, kind, emoji, time). No model, no
  parsing, no guessing. This is what a reusable Shortcut is built from.
- `CreateItemFromTextIntent` — one sentence in. This is the "work out what I
  said" request, and it is the only place the model reads a whole sentence.

Both write through `CreateItemSaver`, which is the single place a new item is
saved. The free-habit limit and the notification reschedule are product rules,
and two copies of them in two intents is how a Shortcut quietly becomes a way
around the paywall.

The time is read deterministically (`stripTime`) and the model's opinion is
never allowed to override it. A clock time in a sentence is a fact; the model is
the part that can be wrong. The no-model path deliberately does very little —
it takes the time out and leaves the rest as the name — because a hand-rolled
parser for "every morning" or "on weekdays" would be a second, worse language
than the one already chosen.

### Shared component contracts

`AppSettingsGroup` is the one grouped settings surface: a label, a panel, and
caller-owned rows and dividers. It was `MoreView.moreHubGroup` and moved to
`AppUIComponents.swift` when the sub-pages needed it. The hub and every
migrated sub-page render the same component, so there is one visual family
rather than a custom hub beside stock iOS screens.

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
