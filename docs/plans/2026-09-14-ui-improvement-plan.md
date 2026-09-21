# hAiity UI Improvement Plan

Status: proposed
Scope: focused usability, accessibility, localization, and performance polish
based on a read-only code audit and an iPhone 18 Pro simulator review.

## Baseline

- Source: `main` at `3035635`.
- `project.yml` declares build 192, but the checked-in Xcode project still
  declares build 191. The simulator audit therefore ran `1.0.0 (191)`.
- Recent swipe and graph refinements are present and their existing UI tests
  pass. Do not redesign those areas without reproducing a remaining defect.
- Preserve the current untracked fixtures, plans, traces, and brainstorm files.

## Priorities

### 1. Make Search correct before polishing it

Search currently starts from the Habits tab's filtered collection without
showing the active filter. A valid habit can therefore appear missing.

- Search all active, user-visible habits and reminders independently of the
  Habits tab filter.
- Use compact native-style result rows instead of graph-heavy `HabitCard`
  instances. Open the full item from the result.
- Preserve the query and result position when temporarily switching tabs;
  clear only through an explicit clear/cancel action.
- Keep the split Search tab and always-visible native search field.
- Align Search's large/compact title transition with the other root tabs.
- Shorten the German placeholder so it is not truncated.

Acceptance:

- Every active item is findable regardless of the selected Habits filter.
- Search remains responsive with at least 100 seeded items.
- Leaving and returning to Search preserves the query.
- The split Search control remains visible and focus works on iOS 26 and 27.

### 2. Complete localization

The English simulator run still showed German strings on Stats, empty Habits,
habit creation, Appearance previews, advanced form help, and Reminders.

- Audit the string catalog for missing English values and source strings that
  bypass localization.
- Prioritize root pages, creation/editing, Reminders, Stats, Appearance, Konto,
  and Standardzeitzone.
- Add a lightweight English UI regression that fails on the known German
  fragments rather than introducing a screenshot framework.

Acceptance:

- No German copy appears in the English smoke-test path.
- German remains the development-language fallback.
- Long translations remain readable at accessibility text sizes.

### 3. Fix interaction accessibility

- Expose every `ReminderRow` swipe action through the VoiceOver Actions rotor,
  matching `HabitCard`.
- Strengthen horizontal gesture intent so near-diagonal drags continue to
  scroll the vertical list instead of revealing actions.
- Allow swipe labels to use two lines or a Dynamic-Type-aware width instead of
  shrinking long localized labels to 70%.
- Keep Reduce Motion settling, RTL side semantics, and one-shot destructive
  actions intact.

Acceptance:

- Reminder actions work through VoiceOver while the row is closed.
- An 8×7 near-diagonal drag scrolls; deliberate horizontal drags still reveal.
- Swipe labels remain readable at AX5 in German and a long RTL localization.
- Existing reminder and habit interaction tests continue to pass.

### 4. Improve graph accessibility without another renderer

- Make habit graph accessibility values report the actual rendered date range
  or week count rather than always saying “last year.”
- Add useful totals/range context to GitHub and Stats rhythm summaries.
- Increase state distinction for Increased Contrast and grayscale. Keep the
  quiet fill-based tile design; reserve outlines or another non-color cue for
  semantic states such as today, selected, declined, or complete.
- Preserve the current centering, scrolling, chronology, and shared renderer.

Acceptance:

- VoiceOver summaries match the visible time range and state.
- Empty, partial, complete, declined, today, and selected remain distinguishable
  in grayscale and Increased Contrast.
- Fitting graphs remain centered and overflowing graphs retain trailing-date
  behavior.

### 5. Rework Solid styling in create and edit forms

Status: implemented and simulator-tested; physical-device visual matrix pending.

The Solid appearance currently gives every Form row its own rounded outline.
In habit and reminder creation/editing this produces a stack of bordered
elements inside already grouped sections, making the form look busy and
fragmented.

- Rework the existing `SettingsRowSurface` / form modifiers for Solid rather
  than adding per-screen exceptions or a new design system.
- Let the section provide the primary visual grouping. Inside a Solid section,
  use a continuous borderless plane, spacing, and hierarchy instead of a
  rounded border or separator around every control or row.
- Keep clear boundaries for interactive controls that require them, but avoid
  nested card-on-card styling around text fields, pickers, toggles, date rows,
  recurrence controls, and explanatory text.
- Apply the same treatment to new and existing habits and reminders, including
  nested date/edit sheets.
- Do not weaken Increased Contrast or Reduce Transparency. Those accessibility
  modes may retain a stronger outline when it is needed for legibility.
- Leave Milky, Liquid, and Adaptive visually unchanged unless shared modifier
  work would otherwise cause a regression.

Acceptance:

- Solid create/edit screens read as a small number of coherent sections, not a
  border around every element.
- Habit and reminder forms use the same spacing, borderless section treatment,
  and control hierarchy.
- Text fields, pickers, toggles, destructive actions, validation, and hit
  targets behave exactly as before.
- Light/dark, Increased Contrast, Reduce Transparency, and AX5 remain readable.
- Milky, Liquid, and Adaptive match their current appearance.

### 6. Polish smaller flow inconsistencies

- Rewrite the first Reminder setup page as an introduction, or move the first
  actual choices onto it. Do not tell users to choose when no choices exist.
- Verify and, only if needed, add bottom scroll clearance so More and Stats
  content is fully visible and tappable above the expanded glass tab bar.
- Add direct UI routes for Konto and Standardzeitzone, then verify all
  Darstellung materials, dark mode, and background images. The source already
  uses shared surfaces, so this is verification-first rather than a rewrite.
- Bring the iOS 17–25 fallback Stats and More roots onto the same appearance
  background ownership as the modern tab shell.

Acceptance:

- Reminder setup copy matches the available action.
- Last rows are visible and tappable without fighting the tab bar.
- Konto and Standardzeitzone update immediately when Darstellung changes.
- Older-iOS fallback roots match the selected background/material.

### 7. Remove measured maintenance and performance debt

- Regenerate or update the checked-in Xcode project so build 192 is consistent
  with `project.yml` before using simulator evidence as the release baseline.
- Remove stale Search comments and unused `moreStatusHero`; clarify the unused
  `AppTab.create` route.
- Index Stats per-habit snapshots by ID once instead of linearly searching for
  each ranking row.
- Reuse the shared Canvas tile path in Stats where measurement shows repeated
  per-tile view construction is material.
- Defer splitting the large `ContentView` until the behavior changes above are
  stable; do not combine structural refactoring with UI fixes.

## Implementation Order

1. Baseline/version consistency and deterministic seeded UI state.
2. Search correctness and compact results.
3. English localization completion.
4. Reminder VoiceOver actions and gesture arbitration.
5. Graph spoken summaries and contrast modes.
6. Solid create/edit form styling.
7. Reminder onboarding, bottom clearance, Konto/timezone, and fallback surfaces.
8. Measured Stats optimization and dead-code cleanup.

Each slice should be independently reviewable and leave the app buildable.
Do not include a TestFlight upload unless separately requested.

## Verification Matrix

- Existing unit and UI suites, plus focused tests for each slice.
- iPhone narrow and regular widths; light and dark.
- German, English, and one long RTL localization.
- AX5 Dynamic Type, VoiceOver, Increased Contrast, Reduce Motion, Reduce
  Transparency, and grayscale.
- Habit and reminder create/edit matrices in Solid light/dark, compared against
  Milky, Liquid, and Adaptive to catch shared-surface regressions.
- Search and Stats with 100+ seeded items, using Time Profiler and SwiftUI body
  update instrumentation before accepting a performance claim.
- Physical-device check for swipe feel and glass/tab-bar composition before
  describing those visual interactions as fixed.

## Out of Scope

- New habit, reminder, account, graph, or sync features.
- A new design system, graph renderer, navigation architecture, or dependency.
- StoreKit, iCloud, Calendar/Reminders, widget, recurrence, or data-model changes.
- Commit, push, Xcode Cloud, TestFlight, or App Store actions.
