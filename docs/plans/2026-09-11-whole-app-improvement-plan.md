# hAiity Whole App Improvement Plan

Status: implementation complete for the release candidate; local release validation is complete, while physical-device and App Store Connect/TestFlight verification remain open

## Verified checkpoint - 2026-09-13

- Statistics now obtains seven-day availability, completion rates, monthly counts,
  ranking streaks and total check-ins from its background snapshot. All active
  ranking rows are retained, and calculations use the requested date/calendar.
- Habit graph cache identity now includes recurrence, creation date and calendar;
  bounded eviction replaces clearing every cached graph at capacity. A compatible
  habit snapshot stays visible during updates. GitHub source changes do not reuse
  another source's visible snapshot.
- Shared headers remove extra blur passes, retain the fading material, and improve
  VoiceOver title handoff. Settings glass honors Reduce Transparency and increased
  contrast. These refinements still require visual review across the full scope.
- Full German suite: `1,744` unit tests and `17` UI tests passed with zero
  failures/skips on the iPhone 18 Pro iOS 27 simulator. Result:
  `/tmp/haiity-ui-189-full-rerun.xcresult`.
- Rapid local changes now share one short maintenance window for notifications,
  motivations, shortcuts and native Calendar/Reminders work; local persistence
  and check-off remain immediate. The source-contract rerun passed 1/1 after the
  contract was corrected for the method boundary.
- Persistence baseline: 12 synthetic habits with 168 log entries, ten measured
  writes including widget reload requests. Median approximately 1.15 ms, maximum
  4.84 ms on this simulator. Result: `/tmp/haiity-persistence-baseline.xcresult`.
  This does not establish the cause of the reported physical-device freeze.
- Persistence still writes synchronously. Notifications, Siri and widgets rely
  on reading committed data immediately; moving writes off-thread remains open
  until flush ordering, background suspension and cross-process writes are covered.
- Release validation passed locally for `1.0.0 (189)`: archive and bundle inspection,
  app/widget version parity, icons, 16 localizations per bundle, Release debug
  seam checks and privacy manifests. The distribution IPA is
  `/tmp/haiity-release-189/export/Haiity.ipa` with SHA-256
  `e1edc92c2bae281a5faff471e050cd23e9700d81a975b274629352053e7a4b7d`.
- No App Store Connect or TestFlight upload is recorded for build `189`.
  Remaining release gates are physical-device startup/scroll/check-off smoke
  testing and authenticated App Store Connect verification of processing and
  TestFlight availability.

This plan is based on the current app structure and the recent release work. The product already has a broad feature set, strong test coverage, contribution graphs, history editing, reminders, Calendar/Reminders sync, widgets, GitHub integration, StoreKit entitlement handling and a custom visual system. The next gains should come from focus, speed, trust and consistency.

The goal is a calmer, faster and more coherent habit app. This plan is now intentionally centered on two workstreams: performance and a unified visual redesign. The core loop should always feel immediate:

1. Open the app.
2. See what matters today.
3. Complete or edit it with one clear action.
4. Understand progress without waiting or navigating through settings.

This is a refinement plan, not a feature expansion. Existing behavior, data, integrations and widgets stay stable unless a concrete performance, accessibility or usability problem requires a change.

## Product principles

- Today comes before configuration.
- One screen should have one primary decision.
- Existing data must remain safe and exportable.
- Native iOS behavior should be used where it is more reliable than custom UI.
- Pro should explain value at the moment of limitation, not create permanent visual noise.
- Performance is part of the design, especially at launch and during scrolling.
- Every important action needs a visible result and an undo path where data can change.
- Avoid adding feature surface until the current surface is easier to use.
- Prefer fewer surfaces, fewer simultaneous states and fewer repeated calculations.
- Every page should look like part of the same product, while still making its primary action obvious.
- Measure before and after changes on a cold launch, a normal data set and a crowded data set.

## Priority order

### P0: Performance foundation

These improvements come first because visual polish is wasted if the app still feels blocked.

#### 1. Remove the post-splash freeze

Current risk: the app performs several kinds of work around startup and first foreground activation, while habit rows contain graph-heavy layouts and UIKit interaction bridges.

Plan:

- Keep local habit data as the only launch-critical dependency.
- Render the first useful list with cached values immediately.
- Move CloudKit, EventKit, notification scheduling, shortcuts and GitHub refresh behind cancellable background tasks.
- Keep interaction bridges deferred, but measure the actual activation boundary on a physical device.
- Add a startup performance budget: first visible content, first usable tap and first scroll response.
- Record signposts for disk load, first populated frame, first interactive frame, stats calculation and GitHub hydration.
- Test cold launch with empty, normal and crowded datasets.

Acceptance criteria:

- The first habit can be checked without a visible post-splash pause.
- Scrolling responds immediately after the first frame.
- Startup work can be canceled when the scene leaves the foreground.
- No integration failure blocks the core habit loop.

Performance targets:

- First useful local content is visible without waiting for CloudKit, EventKit, StoreKit, GitHub or notification work.
- The first tap and first scroll remain responsive immediately after the splash disappears.
- No synchronous full-file encode, widget reload or native-store reconciliation runs on the interaction path.
- Signposts give a clear before/after measurement for disk load, first interactive frame, stats and graph work.

#### 2. Remove repeated work from interaction and rendering

Plan:

- Move `HabitStore` persistence to a serial background writer with coalesced writes while keeping in-memory mutations immediate.
- Coalesce widget timeline reloads and integration callbacks after rapid edits.
- Give store changes an explicit revision so graph and stats caches do not repeatedly hash complete habit payloads.
- Calculate all statistics needed by a page in one snapshot; views should render values, not calculate them in `body`.
- Reuse graph date windows and snapshots across Habit, Statistics, GitHub and widgets.
- Keep the previous valid snapshot visible while new calculations run.
- Profile observation invalidations before splitting `ContentView`; only extract boundaries that reduce measured work.

Acceptance criteria:

- Check-off, navigation and scrolling do not wait for persistence or sync.
- A stats or graph tab can open with cached content and refine in place.
- Repeated body evaluation does not trigger full-day or per-habit calculations.

#### 3. Make sync failures explainable and safe

Plan:

- Keep local habit changes authoritative while a sync is pending.
- Show a compact, actionable state only when the user can do something about it.
- Separate permission denied, temporarily unavailable, account changed and successfully synchronized states.
- Ensure Calendar and Reminders reconciliation is idempotent and never duplicates native items.
- Add a diagnostics path that shows last successful sync and pending work without exposing implementation details.
- Keep import/export as the recovery path and test it with old and current data formats.

#### 4. Finish the StoreKit contract

Plan:

- Keep one authoritative `Pro.isUnlocked` read path.
- Treat temporary StoreKit read failures as unknown, preserving a previously confirmed lifetime entitlement.
- Use transaction updates for live revocations and lifecycle refresh for verification.
- Remove polling if tests and device traces confirm it adds no correctness.
- Add tests for offline launch, revoked purchase, account boundary, restore and transient StoreKit failure.

### P0: Unified redesign system

The redesign should be implemented as one system, not as isolated page makeovers.

#### 5. Establish the visual language

Plan:

- Define one page background, one grouped surface, one interactive row, one floating action treatment and one selected state.
- Use one continuous header treatment across Habits, Statistics, More and every secondary page: title, toolbar, safe area and blur fade behave the same way.
- Standardize spacing, corner radii, icon alignment, row heights, control sizes and typography tokens.
- Keep materials restrained: hierarchy comes from spacing, type and contrast rather than many competing cards.
- Design light mode, dark mode, Dynamic Type, high contrast and Reduce Motion as first-class variants.
- Remove duplicated visual containers and decorative dividers when grouping can be communicated through spacing.

Acceptance criteria:

- A user can move from a primary page into a secondary page without the interface feeling like a different app.
- The primary action is obvious on every page without adding explanatory chrome.
- No page relies on a clipped header, misaligned icon, accidental transparency or inconsistent bottom treatment.

#### 6. Redesign the main navigation surfaces

Plan:

- Habits: prioritize today, make check-off immediate, reduce visual competition from management actions and keep the contribution graph as the identity element.
- Statistics: one clear hero insight, one shared contribution graph, a small supporting metric group and compact habit ranking below it.
- More: a calm settings index with grouped destinations, concise summaries and no dashboard-like noise or transient sync hint.
- Secondary pages: use the same header and surface system, keep one primary action per screen and move destructive actions away from routine controls.
- Creation and editing: use the same components, but make creation progressive and lightweight while editing can expose the full existing configuration.
- History: preserve the current graph-first direction, strengthen selected-state contrast and make month navigation and bulk correction fast.

Do not add new navigation areas, widgets, analytics categories or customization systems as part of this redesign.

## P1: Simplify the daily experience

### 7. Rework the Habits page around today

The Habits page should answer “what should I do now?” before showing every management option.

Plan:

- Keep the current contribution grid as the visual identity.
- Make the first visible section a concise Today group with clear due, done and upcoming states.
- Keep archived, future and non-due entries behind a deliberate filter or secondary section.
- Make the check-off control the strongest tap target in each row.
- Keep swipe actions limited to the few actions users perform frequently; move destructive or rare actions to the hold menu.
- Close an open swipe row as soon as the user begins scrolling or taps another row.
- Make the active filter visible only on the Habits page and keep the toast short.
- Preserve the current graph tile appearance while standardizing spacing, tile size and month-label alignment.

Acceptance criteria:

- A user can identify today’s next action in under two seconds.
- A habit can be completed without opening a menu.
- The list remains readable with large text and VoiceOver.

### 8. Make creation feel like a guided decision

The current editor is powerful but contains many controls and conditional branches.

Plan:

- Keep the name, type and recurrence as the primary first screen.
- Show a live plain-language summary directly below the recurrence controls.
- Put advanced options behind one clearly named section and remember its open state only within the current editor session.
- Make “zeitkritisch” automatically enable the time control and explain the consequence in one sentence.
- Use sensible defaults for habit, reminder, notification and calendar behavior.
- Avoid showing Pro locks until the user reaches the specific restricted option.
- Keep creation and editing visually related, but let creation stay lighter and more focused than editing.
- Add focused tests for type changes, recurrence changes, timezone changes and notification defaults.

### 9. Rebuild History as a fast correction tool

The current editor already has the right foundation: graph preview, month navigation, selection and undo. Improve speed and confidence rather than adding more modes.

Plan:

- Keep the month graph preview compact and make the selected month unmistakable in dark mode.
- Keep month navigation swipeable from the lower editor area.
- Use a grid-first interaction for common corrections; avoid a long day list as the main path.
- Support tap to toggle, drag across adjacent days for multi-select and a clear selection summary.
- Keep “all unlogged” as an explicit bulk action with confirmation only when it changes many entries.
- Keep the count tag anchored to the graph, with the month and year outside the graph surface.
- Make undo persistent until the editor closes or the user explicitly clears it.
- Ensure Dynamic Type does not collapse the graph or hide the footer actions.

## P1: Make the secondary areas coherent

### 10. Give Statistics a clear hierarchy

The statistics page should explain progress, not present a dashboard of equal-weight cards.

Plan:

- Lead with one answer: today’s completion and current rhythm.
- Use the shared contribution graph as the primary visual anchor.
- Follow with a small number of supporting metrics: current streak, recent consistency and total activity.
- Put per-habit ranking below the summary and keep it compact.
- Let users customize which supporting metrics are visible, but keep the default order opinionated.
- Use progressive loading with a stable placeholder and keep the previous snapshot visible while recalculating.
- Long press should work on individual cards without installing section-wide interaction surfaces.

### 11. Make More a settings index, not another dashboard

The current More surface contains many unrelated controls and several nested destinations. It should become a calm index with clear grouping.

Proposed groups:

- Account and Pro
- Appearance
- Notifications
- Calendar and Reminders
- Data and Privacy
- About and Support

Plan:

- Show one-line summaries under rows only when they help a decision.
- Remove transient sync hints from the main page; show sync state inside the relevant integration page.
- Use the same header, blur fade, row height, icon alignment and navigation behavior on every secondary page.
- Keep the main More page short enough to scan without feeling like a control center.
- Make destructive operations visually separate and require a clear confirmation.
- Ensure every setting has a visible immediate effect or a clear saved state.

### 12. Standardize headers and surfaces

Plan:

- Define one reusable page-header component for Habits, Statistics, More and all secondary pages.
- Use one continuous top blur that transitions into the page background instead of page-specific approximations.
- Standardize large title placement, compact title behavior, toolbar spacing and safe-area handling.
- Use one surface vocabulary: page background, grouped surface, interactive row, floating action.
- Keep materials subtle and let content contrast carry the design.
- Verify light mode, dark mode, high contrast, large text and reduced motion for every header variant.

## P2: Improve integrations and widgets

### 13. Make notifications useful and quiet

Plan:

- Keep notification setup user-initiated and contextual.
- Separate reminders, live activity and motivational messages in the UI.
- Show the next scheduled notification and provide a direct edit path.
- Avoid duplicate scheduling after edits, sync, foregrounding or timezone changes.
- Test whole-day reminders specifically around midnight and timezone transitions.
- Make notification actions consistent across habit, reminder and yes/no types.

### 14. Make Calendar and Reminders sync trustworthy

Plan:

- Keep per-item opt-in visible near the item’s calendar/reminder setting.
- Show whether the native item exists, is pending, or was removed externally.
- Use stable identifiers and watermarks for reconciliation.
- Make deletion behavior explicit before removing native entries.
- Add a repair action for a single item instead of forcing a full resync.
- Test external edits, deleted calendars, revoked permission, renamed lists and account changes.

### 15. Treat widgets as glanceable entry points

Plan:

- Keep each widget focused on one question: what is due, what is progressing, or what changed.
- Reduce text and decorative chrome in small and medium sizes.
- Make the contribution graph readable at a glance and avoid tiny labels.
- Ensure every tappable region has one predictable destination.
- Use the same data semantics as the app and show a stable empty/offline state.
- Test widget snapshots with empty, locked Pro, many habits, reminders and GitHub unavailable.

### 16. Keep GitHub valuable but quiet

Plan:

- Cache the last valid snapshot and show it immediately.
- Refresh in the background with a clear last-updated state only when useful.
- Make disconnected, empty and loading states distinct.
- Keep the shared graph component identical between Habit, Statistics, GitHub and widgets where geometry allows.
- Avoid turning GitHub into a second analytics product.

## P2: Accessibility, localization and data confidence

### 17. Make accessibility a design constraint

Plan:

- Audit every primary action with VoiceOver order and labels.
- Ensure graph cells have useful summaries without forcing users through hundreds of individual tiles.
- Add larger hit targets for check-off, month navigation and editor actions.
- Test Reduce Motion for splash, previews, tab transitions and graph updates.
- Test the full app at the largest Dynamic Type sizes.
- Verify contrast for selected history regions and graph levels in dark mode.

### 18. Make localization resilient

Plan:

- Run UI tests in German and English for every release candidate.
- Check long translations in headers, settings rows, notification actions and widgets.
- Avoid using localized text as an accessibility identifier.
- Keep dates, weekdays, months, numbers and timezones locale-aware.
- Add layout checks for German, English and one long-label locale.

### 19. Improve data portability and recovery

Plan:

- Make export understandable to a normal user, not only useful for debugging.
- Include a clear export timestamp, app version and timezone context.
- Validate imports before mutating the store and show a readable result summary.
- Provide a safe preview for large or conflicting imports.
- Test round trips across at least two app versions.

## Technical simplification

The largest maintainability risk is not a missing abstraction; it is too much coordination in `ContentView` and too many presentation-specific states.

Plan:

- Keep domain rules in models and services, not in view callbacks.
- Extract startup lifecycle work into a small coordinator only if signposts show the current view is still the bottleneck after scheduling fixes.
- Separate search state, navigation state and integration state conceptually, even if they remain in the same file initially.
- Remove obsolete compatibility code after the supported iOS baseline makes it unnecessary.
- Prefer one shared graph layout and one shared page header over per-screen variants.
- Keep comments focused on constraints and reasons; remove comments that describe obvious code.
- Add performance tests only around measured regressions, not around every view.

## Release gates for each phase

Every phase should finish with:

- Full localized unit tests using German localization settings.
- Relevant UI tests on an empty and crowded fixture.
- `git diff --check`.
- Debug and Release simulator builds.
- A physical-device smoke test for startup, scrolling, check-off, search, history and the changed area.
- Verification that app and widget versions match.
- Separate reporting for tests, archive, upload and App Store Connect processing.

## Deliberately out of scope

- Another statistics redesign before performance and hierarchy are validated.
- More GitHub data sources or social features.
- More widgets without evidence that current widgets are not useful.
- AI features, sync systems or third-party dependencies.
- A large onboarding framework.
- Broad appearance customization that increases settings complexity.
- A new navigation architecture unless the current one fails a measured user flow.

## Recommended execution sequence

1. Measure and remove remaining launch and first-scroll stalls.
2. Simplify the Habits page and verify the check-off loop.
3. Polish creation and History as the two highest-frequency editing flows.
4. Standardize headers and secondary-page surfaces.
5. Reframe Statistics and More using the shared visual system.
6. Harden notifications, Calendar/Reminders and offline behavior.
7. Audit widgets, GitHub, accessibility, localization and export/import.
8. Run a release-candidate freeze with no new feature additions.
9. Create and verify the final TestFlight release.

## Final TestFlight release

TestFlight is the final delivery step after the redesign and performance work is complete.

Release checklist:

- Confirm the release version and globally unique build number.
- Run the full localized test suite and relevant UI smoke tests.
- Build the Release configuration with the full Xcode toolchain.
- Verify startup, first scroll, check-off, Statistics, More, History, widgets and integrations on a physical device.
- Archive and export with the correct distribution signing configuration.
- Upload to App Store Connect and verify the build appears and begins processing.
- Report upload success separately from TestFlight processing and tester availability.
- Do not claim the release is available until App Store Connect confirms the corresponding state.

The success measure is not how many settings or cards the app contains. It is whether a user can open hAiity, understand what matters today, act immediately, and trust that the result is saved and recoverable.
