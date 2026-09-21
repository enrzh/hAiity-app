# hAiity UI Unification and Sustainable UI Plan

Status: complete - implementation and verification finished; no release action performed
Date: 2026-09-21
Repository: `/Users/enricomini/Documents/Github/hAiity`
Baseline: `main` at `156bd2c`
Design specification: [`docs/design/haiity-ui-design-system.md`](../design/haiity-ui-design-system.md)
Phase 0 evidence: [`docs/plans/2026-09-21-ui-inventory-baseline.md`](2026-09-21-ui-inventory-baseline.md)

## Objective

Create one small, reusable UI vocabulary for hAiity so that new and existing
screens use the same spacing, surfaces, headers, rows, icons, states, and
interaction feedback. The result should be easier to maintain and more
consistent without changing the product scope or the behavior users already
rely on.

The visual direction is a quiet, native iOS utility: a continuous canvas,
clear hierarchy, restrained functional glass, and the contribution grid as
the app's distinctive visual signature.

## Constraints

- Preserve all existing uncommitted and untracked files. Do not reset, clean,
  stash, or overwrite unrelated work.
- Do not add dependencies, a new navigation architecture, a new onboarding
  system, or a second design system.
- Reuse the existing `Theme`, palette, appearance, graph, swipe, and native
  SwiftUI infrastructure before adding anything new.
- Keep the feature set frozen. This plan is UI structure and maintainability
  work, not a feature roadmap.
- Keep behavior separate from presentation. Check-off, recurrence, native
  Calendar/Reminders sync, notifications, iCloud, StoreKit, deep links,
  search, and widgets must not change unless a regression is found.
- Preserve localization, Dynamic Type, VoiceOver, Reduce Motion, Reduce
  Transparency, Increased Contrast, dark mode, and RTL behavior.
- No commit, push, archive, Xcode Cloud run, or TestFlight upload is implied by
  this plan.

## Current Baseline

The codebase already has useful foundations in `Haiity/Theme.swift`:

- `Theme.Metrics` owns the main geometry: `gap` 8, `gutter` 16,
  `cardPadding` 12, `cardRadius` 16, `hit` 44, and settings rows at least 52
  points high.
- `RootPageTitle`, `RootPageCompactTitle`, `appSurface()`,
  `settingsSurface()`, `moreSettingsSurface()`, `navigationChrome()`, and
  `pageHeaderChrome()` already encode part of the intended system.
- `GridCell` and `GitHubContributionGraph` are shared across graph surfaces.
- `SwipeRevealPan`, `SwipeRevealSession`, and `SwipeRevealMotion` already own
  the difficult gesture and settling behavior.

The remaining maintenance cost is mostly duplicated composition around those
foundations:

- `ContentView` still owns page chrome and toast presentation helpers that are
  useful outside the root view.
- `MoreView` has local `moreIcon`, `moreHubRow`, and `pageRow` compositions
  beside the shared settings modifiers.
- `HabitCard`, `ReminderRow`, and `SearchResultRow` repeat surface, icon,
  metadata, hit-area, and reveal-container layout while their actions differ.
- `HabitCard` and `GitHubContributionCard` share the graph renderer but have
  separate graph-surface framing and preview layout.
- `StatsView` and utility pages use the same visual ideas with local spacing
  and surface decisions.

The plan deliberately does not turn every view into one generic component.
The semantic differences between a habit, reminder, search result, graph, and
settings row are real and should remain visible in the code.

## Design Direction

### Design thesis

**Quiet rhythm, visible progress.** hAiity should feel like a calm daily tool:
the screen is mostly an uninterrupted canvas, actions are obvious and native,
and progress is expressed by the contribution grid rather than by decorative
cards or excessive chrome.

### Layer model

1. **Canvas**: the selected appearance background owns the full screen and
   extends behind the safe areas.
2. **Content**: lists, graphs, forms, and repeated items use solid or standard
   materials and clear grouping. Content should not imitate navigation glass.
3. **Functional chrome**: tab bar, navigation/header treatment, temporary
   controls, and toasts may use the existing continuous fade/material treatment
   through one shared path.

### Visual rules

- Use `Theme.Metrics` for geometry. Add a metric only after a repeated value is
  confirmed; do not replace meaningful graph-specific geometry with generic
  constants.
- Use semantic system colors and the existing palette roles. The global accent
  is for action/progress, success and destructive states keep their semantic
  meaning, and habit palettes belong primarily to graph data.
- Do not place cards inside cards. A settings group owns its surface; an item
  surface is reserved for a repeated item or a genuinely framed tool.
- Contribution tiles use fill and spacing for level contrast. Borders are
  reserved for focus, selection, today, or accessibility states where an
  additional cue is needed.
- Use SF Symbols and the existing equal icon slot. Do not introduce a second
  icon library or hand-drawn symbol language.
- Use system text styles. `largeTitle`/`title2` are for page hierarchy,
  `headline`/`body` for content, and `subheadline`/`caption` for secondary
  metadata. Do not use arbitrary fixed text sizes for layout convenience.
- Frequent interactions get short, direct feedback. Existing swipe motion,
  haptics, and context previews remain behaviorally unchanged while their
  visual constants become easier to share.

## Component Strategy

### Keep as authoritative

`Theme.swift` remains the source of truth for:

- spacing, hit targets, card radius, and settings row minimums;
- palette and semantic color resolution;
- appearance/material selection and accessibility fallbacks;
- page/header chrome modifiers;
- haptic and animation policy where a value is genuinely global.

Do not create a parallel `DesignSystem`, `UIConstants`, or configuration
object that mirrors `Theme`.

### Add only small semantic components

Introduce a small shared file, preferably
`Haiity/Views/AppUIComponents.swift`, only for compositions that have at least
three real callers and a stable semantic contract:

1. **`AppSettingsRow`**
   - leading SF Symbol in the shared icon slot;
   - title and optional detail text;
   - trailing content supplied by the caller (`Picker`, `Toggle`, value,
     chevron, or action);
   - one 44-point minimum hit region and Dynamic-Type-safe wrapping;
   - no navigation or persistence logic inside the component.

2. **`AppSection`**
   - shared section title, spacing, and accessibility grouping;
   - supports the continuous More surface and the grouped settings surface
     without forcing both into the same visual treatment;
   - does not hide native `List`/`Form` semantics.

3. **`AppItemSurface`**
   - shared padding, clipping, content shape, and appearance-aware surface;
   - no item-specific actions, gesture state, or model knowledge;
   - used by habit, reminder, search-result, and repeated stats items only
     after the visual contract is proven identical.

4. **`AppGraphSurface`**
   - shared outer frame, centering, graph padding, and preview frame;
   - leaves graph data, tile geometry, month labels, and context-menu actions
     with the graph caller;
   - keeps the existing single graph renderer instead of adding another one.

5. **`AppToast`**
   - move the existing toast surface out of `ContentView`;
   - centralize safe-area placement, compact sizing, semantic tint, and
     accessibility announcements;
   - retain the current dismiss/timing behavior.

These components should use view builders and simple values, not protocols,
factories, type erasure, or an environment-driven registry. A component with
one caller stays local.

### Do not unify

- Habit and reminder business actions. Their rows may share a surface, but
  their state and action semantics remain explicit.
- Habit graph and GitHub graph data models. They may share framing and the
  existing renderer, but not one overloaded model.
- Native `Picker`, `Menu`, `Toggle`, `Button`, `NavigationStack`, and `TabView`
  behavior. Shared components should wrap their layout, not replace it; a
  compact one-choice selector may use a native menu when a menu `Picker`
  repeats or clips its selected value inside a custom row.
- The history editor's date editing model or its selected-range logic.
- StoreKit, sync, notification, recurrence, persistence, or deep-link flows.

## Implementation Phases

### Phase 0: Inventory and visual baseline

- Capture the current source state and verify the existing focused test suites.
- Build an inventory of repeated UI literals and compositions with `rg`, grouped
  by semantic role rather than by file.
- Mark each repetition as `reuse`, `keep local`, or `delete`; do not extract a
  component solely because two snippets look similar.
- Capture baseline screenshots for Habits, History, Search, Stats, More,
  Appearance, Notifications, Konto, create/edit habit, and the graph preview in
  light/dark and Solid/Liquid/Adaptive appearances.
- Record the current accessibility and interaction behavior before refactoring.

Acceptance: the inventory identifies every proposed caller, baseline tests are
green, and no visual change is made in this phase.

### Phase 1: Foundation and shared contracts

- Add `AppUIComponents.swift` with only the semantic primitives that passed the
  three-caller threshold.
- Keep `Theme.Metrics` and palette resolution authoritative.
- Move `ToastSurface` and any truly reusable chrome composition out of
  `ContentView` without changing behavior.
- Add focused source-contract tests for minimum hit targets, shared modifier
  use, and the absence of duplicate token definitions.

Acceptance: the app builds with no screen migration yet; tests prove the new
components have no business logic and retain accessibility identifiers.

Implementation checkpoint (2026-09-21):

- `AppUIComponents.swift` now owns `AppIconBadge`, `AppSettingsRow`, and the
  appearance-aware `AppToastSurface` modifier.
- More hub rows, GitHub, direct `Standardzeitzone`, and page rows use the shared
  settings-row layout. Routing, selector behavior, and accessibility
  identifiers remain in their callers.
- GitHub display settings, Reminder Setup summaries and permission actions, and
  the More appearance/behavior toggles now use the same `AppSettingsRow`
  geometry. Native `Toggle` and `Menu` ownership remains in each caller, so
  full-row accessibility and control hit testing are preserved.
- The existing `appPageHeader`, `RootPageHeaderBlur`, `ContributionChart`, and
  `appSurface()` paths already satisfy the header, graph, and item-shell
  contracts, so no redundant `AppPageHeader`, `AppGraphSurface`, or
  `AppItemSurface` wrapper was added.
- The timezone selector stays a direct More-row control; it uses a native
  `Menu` so the shared row can show the current value once without the
  selected-value duplication produced by a menu `Picker` label.
- The shared `ContributionChart` remains the single graph surface for habit,
  GitHub, and history preview callers. Its existing equal-padding and
  fit-versus-scroll contracts make a second `AppGraphSurface` wrapper
  redundant.
- `AppSection` and `AppItemSurface` were not added: existing section modifiers
  and model-specific item shells do not have a stable identical contract yet.
  Keeping them local avoids a generic wrapper that would hide behavior without
  reducing code.
- Focused simulator tests: 138/138 passed after the extraction.
- Debug app build and install verified on iPhone 18 Pro simulator
  (`2F9C45FC-34DC-44F6-B12A-C72B9DED1673`).
- Release simulator build passed with Xcode 27.0; the only diagnostic was the
  pre-existing `ContentView.swift:3720` unnecessary availability-check warning.
- Focused UI test
  `TodayProgressUITests/testAccountTimeZoneAndDarkHistorySelectionRemainLegible`
  passed on the same simulator in 56.956 seconds.
- Visual smoke captures: `/tmp/haiity-ui-phase1-more-final.png` and
  `/tmp/haiity-ui-phase1-appearance.png`.

### Final implementation and verification checkpoint (2026-09-21)

- Shared UI work is complete for the stable contracts found in the inventory:
  `AppIconBadge`, `AppSettingsRow`, and `AppToastSurface` are the reusable
  primitives. Existing header, graph, item-shell, and swipe infrastructure
  remains authoritative where a new wrapper would add indirection without a
  stable multi-caller contract.
- `HaiityTests` with German test localization passed **1,793/1,793**:
  `-testLanguage de -testRegion DE -only-testing:HaiityTests`.
- Focused appearance and cloud-status regression suites passed **76/76** after
  the source-contract and locale-safe assertion updates.
- `TodayProgressUITests` passed **12/12**, covering light/dark pages, graph and
  history editing, creation, search, sorting, timezone/account screens, and
  large-text interaction paths.
- Release simulator build passed with Xcode 27.0 using
  `CODE_SIGNING_ALLOWED=NO`. The existing warning at
  `ContentView.swift:3720` is an unnecessary availability check; it is not
  introduced by this work and does not block the build.
- `git diff --check` passed.
- Verification is simulator-based. Physical-device gesture feel, archive
  signing, App Store Connect processing, and TestFlight behavior remain outside
  this task and were intentionally not claimed or performed.

### Phase 2: Headers and functional chrome

- Route root and secondary pages through the same header contract while keeping
  the existing scroll-driven title handoff and continuous fade blur.
- Keep the split Search tab/search activation behavior unchanged.
- Keep Liquid Glass limited to functional chrome and use the existing
  Reduce-Transparency fallback.
- Remove obsolete local header modifiers only after all callers migrate.

Acceptance: every page has the same title alignment, safe-area behavior,
compact-title transition, and material fallback; search remains a dedicated
  tab with its split search control.

### Phase 3: Settings and utility rows

- Migrate More, Darstellung, Verhalten & Teilen, Mitteilungen, Konto, GitHub
  settings, and other utility pages to `AppSettingsRow`/`AppSection` where the
  semantics match.
- Keep `Standardzeitzone` as the direct native selector on More, not a page.
- Preserve native trailing controls and prevent a parent row from stealing
  their hit tests.
- Normalize icon slots, divider ownership, wrapping behavior, and row spacing.

Acceptance: settings pages share one row rhythm and appearance behavior in all
four appearance modes; every native control remains independently tappable at
normal and AX5 text sizes.

### Phase 4: Habit, reminder, search, stats, and graph surfaces

- Migrate only the shared visual shell of `HabitCard`, `ReminderRow`, and
  `SearchResultRow` to `AppItemSurface` if their measured geometry matches.
- Preserve each row's model-specific content, checkmark, VoiceOver actions,
  context menu, and swipe action ownership.
- Use `AppGraphSurface` for habit and GitHub framing so centering, padding,
  month-label placement, preview size, and tile treatment cannot drift apart.
- Keep the graph tile renderer and contribution data path unchanged.
- Apply the same surface rule to repeated Stats items without nesting cards.

Acceptance: the graph is centered with equal horizontal padding, no tile has an
unnecessary per-tile white border, and all existing swipe/check-off/context-menu
tests remain green.

### Phase 5: Motion, states, and accessibility hardening

- Centralize only repeated animation durations or haptic meanings that are
  demonstrably shared; keep gesture-specific physics in `SwipeRevealMotion`.
- Verify pressed, selected, open, cancelled, loading, empty, error, and
  disabled states for every shared component.
- Verify VoiceOver labels and action order, Dynamic Type through AX5, RTL, dark
  mode, Increased Contrast, Reduce Motion, and Reduce Transparency.
- Ensure no state is conveyed by color alone; add shape, text, or symbol cues
  where needed.

Acceptance: shared components have one documented behavior matrix and no
accessibility regression is hidden behind a visual refactor.

### Phase 6: Cleanup and deletion

- Delete migrated private row/header/toast helpers and duplicate literals.
- Keep compatibility wrappers only when they materially reduce risk; mark them
  for deletion in the same plan rather than allowing permanent parallel paths.
- Update source-contract tests and design documentation with the final ownership
  map.
- Run `git diff --check` and inspect the final diff for unrelated churn.

Acceptance: each visual rule has one owner, each shared component has multiple
real callers, and no unused abstraction or duplicate style path remains.

## Verification Matrix

### Automated

- Existing `HaiityTests` and `HaiityUITests`.
- Focused tests for `AppSettingsRow`, `AppItemSurface`, `AppGraphSurface`, and
  `AppToast` contracts where source contracts are the established local
  pattern.
- Graph geometry tests for centering, equal padding, month labels, and shared
  renderer use.
- Swipe tests for open, cancel, reverse, commit, sibling-close, vertical
  scroll interruption, RTL, and Reduce Motion.
- `git diff --check` and a Release simulator build.

### Visual and interaction

- iPhone narrow and regular widths, portrait and landscape where supported.
- Light and dark appearance; Solid, Milky/Liquid, and Adaptive settings.
- German and English, including long labels.
- Dynamic Type default and AX5; VoiceOver rotor/actions.
- Increased Contrast, Reduce Motion, Reduce Transparency, and grayscale.
- Search tab, graph long press, history editing, check-off, swipe cancellation,
  create/edit, More settings, and native picker/toggle hit testing.

Before/after screenshots are evidence for layout only. A simulator test pass is
not a claim that physical-device gesture feel or TestFlight behavior was
verified.

## Definition of Done

- Repeated visual roles have one implementation owner.
- Shared components have stable semantic boundaries and no hidden business
  logic.
- Existing app behavior and data contracts are unchanged.
- All specified accessibility and appearance states remain usable.
- The graph, row, settings, header, and toast families are visually coherent
  without a nested-card or over-glass effect.
- Tests, screenshots, and diff checks are recorded with exact results.
- No release or App Store action is performed unless separately requested.

## Out of Scope

- New habits, reminders, graphs, widgets, sync, AI, StoreKit products, or
  appearance options.
- Reworking the history editor's data model.
- Replacing SwiftUI with UIKit or adding a third-party UI library.
- A total rewrite or a broad `ContentView` split without measured benefit.
- TestFlight, App Store Connect, commits, or pushes.

## Copy-Paste Execution Prompt

```text
Implement the accepted plan in
docs/plans/2026-09-21-ui-unification-and-sustainable-ui-plan.md and use
docs/design/haiity-ui-design-system.md as the visual contract.

Work in /Users/enricomini/Documents/Github/hAiity. First inspect git status,
branch, HEAD, project instructions, the current Theme.swift foundations, the
existing tests, and all current uncommitted/untracked files. Preserve every
existing change. Do not reset, clean, stash, overwrite, commit, push, archive,
run Xcode Cloud, or upload to TestFlight.

Use the existing Theme, palettes, native SwiftUI controls, graph renderer,
SwipeRevealPan/Session/Motion, and appearance modifiers. Add only small shared
semantic components with at least three real callers. Do not create a parallel
design system, generic protocol hierarchy, factory, dependency, or business
logic inside UI components.

Implement in phases: inventory/baseline, shared contracts, headers/chrome,
settings rows, item/graph surfaces, accessibility/motion, then cleanup. Keep
Standardzeitzone as a direct selector on More. Preserve split Search behavior,
habit/history behavior, swipe semantics, check-off, recurrence, sync,
notifications, widgets, localization, and all data contracts.

After each phase run the smallest relevant tests. Before finishing run the
focused suites, the relevant UI tests, a Release simulator build, and
git diff --check. Report exact test results, screenshot/device limitations,
remaining duplicate paths, and all intentionally untouched worktree files.
```
