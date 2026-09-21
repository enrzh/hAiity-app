# hAiity Improvement Roadmap

Status: implemented for release candidate `1.0.0 (189)`; local release validation passed, while physical-device and App Store Connect/TestFlight verification remain open
Scope: polish, performance and reliability only

## Release checkpoint - 2026-09-13

- Full German Xcode suite: `1,744` unit tests and `17` UI tests passed with zero
  failures/skips on the iPhone 18 Pro iOS 27 simulator
  (`/tmp/haiity-ui-189-full-rerun.xcresult`).
- Local Release archive/export validation passed for app and widget at
  `1.0.0 (189)`. The distribution IPA is at
  `/tmp/haiity-release-189/export/Haiity.ipa`.
- No App Store Connect or TestFlight upload is recorded for build `189`.
  Physical-device smoke testing and authenticated App Store Connect
  verification of processing and TestFlight availability remain open; these
  are separate gates and are not inferred from local export output.

## Objective

Make hAiity feel immediate, calm and dependable without adding another product
area. The core loop remains:

1. Open the app.
2. See what matters today.
3. Check it off or correct it quickly.
4. See the saved result immediately.

The existing feature set is sufficient for 1.0. The next work should reduce
waiting, visual noise and interaction complexity.

## Priority Order

### P0: Performance and startup

The reported post-splash pause and lag while switching or scrolling are the
highest-impact problems. UI work should not hide them.

Tasks:

- Measure cold launch, first useful frame, first tappable frame and first
  successful scroll on an empty, normal and crowded data set.
- Keep local data and the Habits list as the only launch-critical work.
- Move CloudKit, EventKit, notification scheduling, shortcuts, GitHub refresh
  and nonessential widget work behind cancellable tasks.
- Find remaining synchronous graph, statistics, persistence and image work on
  the main actor.
- Keep the last valid graph and statistics snapshots visible while new data is
  calculated.
- Coalesce persistence, widget reloads and integration callbacks after rapid
  edits.
- Remove obsolete startup work after signposts prove it is no longer needed.

Acceptance criteria:

- The first habit is tappable immediately after the splash handoff.
- The first scroll does not pause for sync, GitHub or statistics work.
- Switching to Statistics and More does not block the main interaction loop.
- Every delayed startup task is cancellable and has a measured reason to run.

### P1: UI system and visual consistency

Create one coherent visual language for the whole app. This is a refinement of
the current design, not a new navigation architecture.

Tasks:

- Define shared tokens for typography, spacing, row height, corner radius,
  surface tint, selected state and toolbar controls.
- Use one reusable header treatment on Habits, Statistics, More, Search and all
  secondary pages: large title, toolbar spacing, safe-area behavior and the
  continuous blur fade should work the same everywhere.
- Reduce competing cards and dividers. Use spacing and contrast to group
  content, with glass reserved for genuinely interactive or framed surfaces.
- Make light mode, dark mode, increased contrast, Reduce Transparency, Reduce
  Motion and Dynamic Type intentional variants rather than afterthoughts.
- Align every leading icon, control, footer action and month label to the same
  grid.
- Keep text inside its container at German, English and large Dynamic Type
  sizes.

Acceptance criteria:

- Main and secondary pages look like one product.
- No clipped header, uneven tile edge, unexplained divider or accidental full
  transparency remains.
- Each page has one obvious primary action.
- Selected, pressed, disabled and destructive states are visually distinct.

### P1: Daily workflow

#### Habits

- Keep the contribution graph as the identity element, but give Today and the
  check-off action visual priority.
- Keep filters compact and show filter feedback only on the Habits page.
- Limit swipe actions to frequent actions; move rare and destructive actions
  into a shorter, grouped hold menu.
- Reset an open swipe row as soon as scrolling starts or another row is used.
- Keep search navigation separate: the Search page owns the search bar, the
  first visit reveals it without the keyboard, and the second tap focuses it.

#### Creation and editing

- Make name, type and recurrence the first decisions.
- Show a live plain-language recurrence summary.
- Put advanced settings behind one consistent section.
- When `zeitkritisch` is selected, enable the time option automatically.
- Use sensible defaults and reveal Pro gating only at the restricted action.
- Keep creation lightweight while preserving the full editing surface.

#### History

- Keep the graph-first editor and compact month preview.
- Make selected days unmistakable in dark mode and high contrast.
- Keep month/year labels outside the graph surface.
- Use the grid as the main correction interface instead of a long day list.
- Preserve swipe month navigation, multi-select, bulk actions and undo.
- Keep the bottom action area visible and usable with large text.

### P1: Statistics and More

#### Statistics

- Lead with one clear answer about current progress and rhythm.
- Keep one shared contribution graph as the visual anchor.
- Show only a small set of supporting metrics before the ranking.
- Preserve customization, but use an opinionated default order.
- Load snapshots progressively without blanking already visible content.

#### More

- Make More a settings index rather than another dashboard.
- Group destinations into Account and Pro, Appearance, Notifications,
  Calendar and Reminders, Data and Privacy, and About and Support.
- Keep rows concise and show summaries only when they help a decision.
- Keep transient sync state inside the relevant integration page, not on More.
- Separate destructive actions from routine settings and confirm them clearly.

### P2: Reliability and integrations

- Keep one authoritative Pro entitlement read path.
- Preserve a confirmed lifetime entitlement during transient StoreKit failures.
- Use transaction updates for live changes and lifecycle refresh when needed;
  remove polling if device evidence confirms it is unnecessary.
- Verify that Calendar and Reminders reconciliation is idempotent and does not
  create duplicates after foregrounding, edits, timezone changes or sync.
- Ensure whole-day reminders are not completed at the start of their day.
- Keep notification permission contextual and user initiated.
- Keep GitHub cached, quiet and non-blocking; distinguish cached, loading,
  disconnected and empty states.
- Ensure widgets use the same data semantics and show stable offline states.

### P2: Accessibility and localization

- Audit VoiceOver order and labels for check-off, search, graph, history and
  every primary toolbar action.
- Give graph cells useful grouped summaries without forcing VoiceOver through
  hundreds of indistinguishable tiles.
- Test the largest Dynamic Type size on every secondary page.
- Test German, English and one long-label locale for headers, settings,
  notifications, widgets and creation flows.
- Never use localized visible text as an accessibility identifier.
- Verify contrast for graph levels, selected history regions and disabled
  controls in dark mode.

### P2: Data safety and recovery

- Keep export available as the recovery path and make its metadata readable.
- Validate imports completely before mutating local data.
- Show a clear import result for accepted, skipped and conflicting entries.
- Test round trips with current and older data formats.
- Confirm that local changes remain available offline while cloud work is
  pending.

## Execution Sequence

1. Instrument cold launch and first-scroll behavior.
2. Fix measured main-thread work and preserve cached snapshots.
3. Complete the shared UI tokens and header/surface system.
4. Polish Habits, Search, creation and History as the highest-frequency flows.
5. Apply the same system to Statistics, More and secondary pages.
6. Harden StoreKit, notifications, Calendar/Reminders, GitHub and widgets.
7. Run accessibility, localization, import/export and regression audits.
8. Freeze the feature set and prepare the next release candidate.

## Verification Gates

Each phase must include:

- Relevant unit and source-contract tests.
- UI tests with empty, normal and crowded fixtures.
- Light and dark screenshots for changed pages.
- Dynamic Type, VoiceOver and Reduce Motion checks where applicable.
- `git diff --check`.
- Debug and Release builds with the full Xcode toolchain.
- Physical-device smoke testing for startup, scroll, check-off, search,
  History, Statistics and the changed integration.
- Separate reporting for tests, archive, upload, processing and TestFlight
  availability.

## Deliberately Out Of Scope

- New habit, statistics, GitHub, widget or AI features.
- A second navigation architecture.
- A large onboarding framework.
- Additional appearance customization.
- New sync systems or third-party dependencies.
- Another redesign before the current hierarchy is measured in use.

## Definition Of Done

hAiity is ready for the next release candidate when a user can open the app,
scroll and check off a habit without a post-splash pause; move through every
page without encountering a different visual language; correct history without
guesswork; and trust that local, StoreKit and native-calendar state remains
consistent when the network or system services are temporarily unavailable.
