# hAiity: daily experience, performance, and release confidence

Date: 2026-10-04
Status: implemented and locally verified on 2026-10-04; device/service gates pending
Planning baseline: `main`, `109a06d9bfc0633e59b8d45abc60cd25aad4a0dc`
Source metadata at planning: 1.0.0 (273)
Baseline includes existing modified and untracked work; preserve all of it.

Current evidence and remaining gates are tracked in the
[implementation report](2026-10-04-whole-app-implementation-report.md).
Device installation, uploads, recruitment, and recordings remain separately scoped.

## 1. Product goal

Make the central experience dependable and easy to understand:

**Open hAiity -> find today's entry -> record progress -> see the grid change.**

The contribution grid remains the product's recognizable element. Native
navigation, clear controls, and quiet content surfaces support it. Success means
fewer decisions and interruptions in this loop, with evidence that it works on a
phone. Adding features or repeatedly replacing entire pages is outside this plan.

## 2. Scope and constraints

### Included

- Measure and address demonstrated launch, scroll, navigation, and check-off delays.
- Simplify the initial habit/reminder creation form using progressive disclosure.
- Give today's actions stronger priority in the Habits page.
- Correct statistics wording and explain existing completion semantics.
- Clarify More, account, connection, and setup labels using current components.
- Validate recovery, integrations, accessibility, and usability before a release.
- Update documentation and listing claims when the implementation changes them.

### Preserved contracts

- Local-first tracking, existing JSON schema, coordinated saves, and stale-writer rejection.
- Existing habit types, recurrence rules, timezone inheritance, and old entries.
- Existing Pro entitlement policy and its authoritative `Pro.isUnlocked` read path.
- Shared habit/GitHub graph geometry, external month labels, and border-free tiles.
- History editor, including its selected-region treatment and floating actions.
- Dedicated Search page, visible search field, split navigation Search control,
  keyboard behavior, and remaining on Search when editing ends.
- Current native sorting table and guarded persistence of visible order.
- Swipe cancellation on scrolling, immediate check-off feedback, editing controls,
  Undo, and Reduce Motion behavior.
- Existing user-selected materials, backgrounds, colors, and other appearance choices.
- Contextual, user-initiated permission requests; no mandatory sign-in or setup.
- Localization, Dynamic Type, VoiceOver, RTL, Increased Contrast, and Reduce Transparency.
- Multiple notification times and the separation of appointment time from notification time.
- End-of-day automatic resolution, independent of the appointment's clock time.
- App opening clears delivered notifications only; future scheduled requests remain intact.

### Excluded

- New AI capabilities, widgets, GitHub features, sync systems, or dependencies.
- A new onboarding framework, settings coordinator, database, or caching framework.
- Another wholesale Statistics, More, graph, or navigation redesign.
- Removing customization, changing reminder semantics, or changing monetization.
- Production analytics, recording users, or collecting account/data contents.
- Commit, push, phone installation, TestFlight upload, or App Store submission merely
  because this plan exists. Those require a subsequent instruction authorizing them.

## 3. What is already present

These are source/document observations, not proof of an installed build.

| Existing implementation | Consequence for this plan |
| --- | --- |
| Shared visual roles in `Theme.swift` and `AppUIComponents.swift` | Reuse them; do not build another design system. |
| Creation has a preview and collapsible advanced settings | Refine disclosure and grouping instead of replacing the creator. |
| Statistics uses background snapshot calculation and retains completed content | Profile the remaining work before adding another cache. |
| Startup signposts and crowded-data launch/navigation tests exist | Extend the smallest missing measurement instead of replacing instrumentation. |
| Native UIKit sorting with guarded store writes is locally verified | Preserve it; validate hardware feel without reintroducing custom drag physics. |
| Multiple notification times are editable per habit/reminder | Simplify their presentation without deleting or resetting saved times. |
| More uses shared groups and direct account actions | Improve labels and placement without losing login/logout access. |
| Apple sign-in and private iCloud sync are independent | Communicate that distinction consistently; do not couple them. |
| Statistics computes percentage-point deltas but says `% better/worse` | Correct the presentation, not the underlying mathematics. |
| Store listing describes one notification per item | Reconcile listing copy with the shipped multiple-notification behavior. |

Relevant prior evidence is documented in the
[polish report](2026-10-01-whole-app-polish.md),
[hardening report](2026-10-02-project-hardening-report.md),
[text-creation report](2026-10-03-text-creation-implementation-report.md), and
[sorting report](2026-10-03-sorting-implementation-report.md).
Their results describe specific historical source states. The delivered-notification
cleanup was added after the sorting verification; that older full run is not
verification of every current change. Recheck artifact availability and source
identity before reusing any evidence.

## 4. Execution order

| Phase | Work | Exit condition |
| --- | --- | --- |
| 0 | Capture current source, fixtures, and user-visible baseline | Exact baseline and applicable device limits recorded. |
| 1 | Measure and fix demonstrated performance bottlenecks | Matched local results and, when available, phone traces explain the improvement. |
| 2 | Simplify creation and prioritize daily actions | Core loop is easy to complete; existing settings and order are preserved. |
| 3 | Refine Statistics wording and More clarity | Correct, localized information and predictable settings navigation. |
| 4 | Integration, accessibility, and task-based usability validation | Applicable gates pass; unavailable external gates remain explicitly pending. |
| 5 | Final verification and release readiness report | Evidence matches final source; release actions remain separately authorized. |

Performance measurement precedes layout edits so changed UI does not erase the
baseline. Independent copy and fixture work may proceed while hardware access is
unavailable. Hardware-dependent success cannot be inferred from elapsed time or a
simulator pass.

## 5. Phase 0: establish a reproducible baseline

### Tasks

- [ ] Read current shared/project instructions and the engineering/design contracts.
- [ ] Capture branch, HEAD, full Git status, app/widget metadata, and source fingerprint.
- [ ] Identify any active worker or Xcode run; resume it rather than duplicate it.
- [ ] Review existing dirty changes before editing the same paths.
- [ ] Record available Xcode, SDKs, simulators, physical devices, and installed build.
- [ ] Capture representative Habits, creator, Statistics, More, and account screens.
- [ ] Use isolated fixtures; do not reset or replace production data to create a baseline.
- [ ] Record device, OS, configuration, locale, timezone, appearance, thermal state,
  Low Power Mode, background activity, and fixture identity for measurements.

Use empty, realistic mixed, and crowded existing fixtures. Include long names,
checkbox/quantity/yes-no habits, reminders, multiple notification times, archived
items, and inherited/explicit timezones. Only extend fixtures for a missing
scenario relevant to the change.

### Acceptance

The baseline can be repeated without guessing the dataset or overwriting user
state. Historical screenshots and installed builds are labeled with their actual
source/build identity. No current-performance claim rests on an old report.

## 6. Workstream A: measured responsiveness

### Goal

After the splash reveals the app, scrolling and tapping work immediately. Local
tracking stays usable while GitHub, iCloud, native integrations, and statistics
refresh. Performance should be good with normal settings; Performance Mode stays
an optional preference, not the remedy for a blocked interface.

### Implementation steps

- [ ] Reproduce cold launch followed immediately by scroll, check-off, and Stats navigation.
- [ ] Reuse `StartupMetrics` in `Haiity/Models/StartupSplash.swift` to separate
  splash completion, local-data readiness, interactive frame, and later work.
- [ ] Inspect main-thread samples with Time Profiler and UI/rendering instruments
  supported by the current Xcode. Correlate stalls with signposts.
- [ ] Measure first and repeated Stats visits, check-off-to-grid feedback, and
  opening an editor from normal rows and context previews.
- [ ] Inspect only demonstrated hotspots: store publication, repeated derived
  calculations, graph layout, image decoding, view invalidation, or integration callbacks.
- [ ] Fix the owning path with the smallest change. Reuse existing scheduling,
  snapshots, geometry boundaries, and lifecycle state where they already work.
- [ ] If material/image rendering is measured as expensive, simplify that rendering
  path while preserving selected appearance and accessibility fallbacks.
- [ ] Repeat matched measurements after each meaningful fix; stop when the identified
  bottleneck is resolved and appropriate regression checks pass.

Do not add arbitrary sleeps, lengthen the splash, suppress required saves, or
disable services to conceal a stall. A view-state event named interactive does
not itself prove that input is being serviced.

### Measurement protocol and proposed budgets

| Scenario | Evidence | Proposed quality target |
| --- | --- | --- |
| Cold launch, then immediate input | At least 5 matched launches; timing summary and main-thread trace | No repeatable post-splash input stall; investigate every observed block over 100 ms. |
| Check-off feedback | At least 10 matched interactions across habit types | Visible feedback target within 100 ms; durable-save failure remains truthful and recoverable. |
| Tab transition and editor presentation | First visit plus at least 10 repeated interactions | Input acknowledgement target within 100 ms; no repeatable blocked transition over 250 ms. |
| Continuous scroll with graph-heavy data | Fixed gesture route; frame/hitch trace | No repeatable visible hitch attributable to app work; compare hitch metrics with the baseline. |
| Background/offline refresh | Same route with integrations available and unavailable | Local actions remain usable; delayed/stale results cannot overwrite current state. |

These are proposed experience budgets, not measured results or a guarantee about
all supported hardware. Report median and worst values, sample count, and matched
conditions. Report p95 only with enough samples to support it. Separate animation
duration from input blocking and helper timings from whole-app latency. Respect
the device's actual refresh rate rather than claiming universal 120 Hz operation.

### Verification and files

Reuse `PerformanceTests`, `TodayProgressUITests`, snapshot cancellation tests,
and graph/geometry regressions. Keep timing assertions out of noisy CI unless a
stable baseline supports them. Add a focused behavioral test for each actual
correctness fix; do not create tests that merely mirror implementation syntax.

Primary owners: `ContentView.swift`, `StatsView.swift`, `ContributionGrid.swift`,
`HabitStore.swift`, `StartupSplash.swift`, and `Theme.swift` when traces implicate them.

Physical profiling needs an authorized development-signed build. A TestFlight
binary may reject profiler attachment. Do not overwrite an existing phone build
without authorization; continue simulator and source work while that gate is pending.

## 7. Workstream B: faster, clearer creation

### Goal

A simple habit can be created by entering its name and saving sensible defaults.
A reminder exposes its date and optional time clearly. Complex schedules and
existing advanced settings remain fully available.

### Proposed hierarchy

| Initial view | Revealed when relevant | Additional settings |
| --- | --- | --- |
| Habit/reminder type and name | Quantity target or yes/no semantics for the selected type | Emoji, color, duration, timezone, native integrations, auto-resolution. |
| Compact schedule summary and the essential date/frequency choices | Weekdays, monthly/yearly detail, interval, recurrence ending | Existing repeat-while-incomplete behavior where applicable. |
| Optional notification choice | Notification times and add/remove controls when enabled | Time-sensitive behavior with its existing automatic clock activation. |
| Existing preview and Save | Inline validation and actionable save errors | No separate wizard or onboarding coordinator. |

Treat this table as presentation grouping, not a new schema or a change to
defaults. Preserve existing user-selected defaults. Hide advanced recurrence
controls behind an explicit disclosure, with a summary when their saved values
are active. Never imply that hidden settings have been cleared.

### Tasks

- [ ] Trace creation, edit, text creation, and Siri paths before moving controls.
- [ ] Reuse `RecurrenceDraft`, existing summaries, and current form sections.
- [ ] Reduce initial density without hiding fields essential to the selected habit type.
- [ ] Keep a clear distinction between appointment time and notification times.
- [ ] Retain multiple times when notifications are switched off and back on.
- [ ] Show the effective schedule and active non-default options in the existing preview.
- [ ] Preserve text creation's editable date/time preview, inline dictation,
  stale-result rejection, and save-exactly-what-was-reviewed behavior.
- [ ] Preserve draft contents and keep the editor open after save or permission failure.
- [ ] Verify that creating/editing does not request Calendar, Reminders, or
  notifications merely because the form was opened.

### Acceptance and verification

- A basic habit needs no expansion of additional settings to save.
- Existing daily/weekly/monthly/yearly rules, interval, ending, explicit timezone,
  quantity goals, and legacy flexible rules survive a no-change edit round trip.
- Habit/reminder type changes preserve only the existing documented conversion
  behavior; they do not silently alter notification times or old history.
- Disabled/denied notification behavior is explained without preventing local tracking.
- The preview and essential controls remain usable with the keyboard open,
  largest Dynamic Type, long translations, and RTL.
- The first-habit -> check-off -> changed grid loop remains available without
  an account, model download, or permission prompt.

Owners: `EditHabitSheet.swift`, `RecurrenceDraft.swift`, `SpeakToCreateSheet.swift`,
`CreateSentenceFacts.swift`, and existing creation/persistence callers.
Focused coverage: recurrence draft/round-trip tests, `MultipleNotificationTests`,
`VoiceCreateSheetTests`, `CreateSentenceFactsTests`, `CreateHabitIntentTests`,
`SpeakToCreateDockUITests`, and first-run/navigation checks.

## 8. Workstream C: prioritize today's actions

### Goal and proposed layout

The Habits page makes the current task obvious before optional integration content.

```text
Habits                         existing filter / create actions
Today progress                 existing Today / All selector
Habit and reminder rows        current filtered, user-defined order
GitHub activity                existing shared graph and account actions
Native tab bar                 preserve the split Search control
```

Move the existing GitHub card after the entry list; reuse its existing collapsed
behavior. Do not introduce another dashboard, feed, or graph preference. In a
GitHub-only or filtered-empty state, keep the card reachable and make the lack of
matching habit entries explicit.

### Tasks

- [ ] Adjust composition in `ContentView` without changing filter or sort mathematics.
- [ ] Keep reminder deadlines and habit check-off controls visually distinguishable
  with existing labels and symbols, not color alone.
- [ ] Preserve stored ordering in Today and All, including hidden/archived slots.
- [ ] Preserve scroll restoration, deep-link targets, history access, and native sorting.
- [ ] Verify immediate check-off, Undo, swipe trigger/cancel, and edit behavior.
- [ ] Check that GitHub loading or reconnection cannot block the daily loop or
  cause repeated jumps in scroll position.

### Acceptance

On the representative fixture, an actionable entry is reachable sooner than the
GitHub card without changing saved order. At accessibility sizes, all content
remains reachable even when it cannot fit above the fold. No action depends on
discovering a long press. Existing graph centering, tile treatment, and history
selection remain unchanged.

Owners: `ContentView.swift`, `TodayProgressView.swift`, `HabitCard.swift`,
`ReminderRow.swift`, and the existing GitHub card.
Coverage: `TodayProgressUITests`, `SortingUITests`, `ScheduledProgressTests`,
`AppNavigationTests`, and graph/history smoke cases.

## 9. Workstream D: trustworthy Statistics

### Tasks

- [ ] Change weekly comparison labels to percentage points: 60% -> 70% is
  `10 percentage points higher`, not `10% better`.
- [ ] Use neutral German/English phrasing for lower, equal, and unavailable comparisons;
  translate it through the existing string catalog for every declared UI locale.
- [ ] Keep the existing delta calculation and rounding semantics unless a focused
  correctness test demonstrates a separate mathematical defect.
- [ ] Explain existing denominators, scheduled-day boundaries, quantity thresholds,
  flexible-period exclusions, and no-due-item states near the relevant metric.
- [ ] Reuse short supporting text or an existing disclosure; avoid another statistics
  settings page, tooltip system, or metric card.
- [ ] Keep optional model-generated reading user-triggered and subordinate to facts.
- [ ] Verify that edits/backfills update the snapshot and that cancelled or outdated
  calculations/readings cannot replace newer results.

### Acceptance

Positive, negative, zero, and absent comparison cases use the correct units and
accessible labels. Zero scheduled entries are never described as a failed day.
Explanations match `GoalEngine`, `StatsEngine`, and `ScheduledProgress`, including
their existing differences; no metric is silently redefined to make copy simpler.
The page retains its current layout and selected cards.

Owners: `StatsView.swift`, `Localizable.xcstrings`, and existing statistics engines
only when a concrete bug requires it. Coverage: `StatsEngineTests`,
`StatsAndReorderTests`, `StatsReadingTests`, and focused statistics UI checks.

## 10. Workstream E: understandable More and connections

### Proposed information hierarchy

Retain the current hub and its shared grouping treatment. Keep everyday preferences
together, optional connections together, and archive/help/privacy together.
Improve ambiguous labels before moving settings between destinations.

### Tasks

- [ ] Replace `Setup wiederholen` with a label naming its purpose, such as
  `Mitteilungen & Kalender einrichten`, with appropriate localized wording.
- [ ] Make the account entry explicitly describe optional Apple sign-in/personalization.
- [ ] Keep direct login/logout actions for both Apple and GitHub, with independent
  hit areas and clear disconnected, working, connected, and error states where applicable.
- [ ] Explain that Apple sign-in does not enable/disable private iCloud synchronization.
- [ ] Keep sync detail in the relevant existing settings/status location; do not restore
  the removed decorative iCloud-sync hint or orphaned divider on the More hub.
- [ ] Preserve the simple full-row timezone selector and avoid reintroducing its old page.
- [ ] Make native Calendar/Reminders setup and existing data export/import discoverable
  with direct labels, while keeping destructive cleanup clearly distinguished.
- [ ] Reuse `SettingsPage`, `AppSettingsGroup`, `AppSettingsRow`, semantic colors,
  and current icon slots; do not replace selected materials with a new fixed style.

### Acceptance

People can identify what sign-in does, find notification/native integration setup,
and enter appearance settings without exploring unrelated pages. Login, logout,
row navigation, timezone selection, and appearance controls remain independently
tappable at normal and accessibility text sizes. App tracking works while signed
out. Navigation, cancel, and confirmation controls remain consistent.

Owners: `MoreView.swift`, `AppUIComponents.swift`, `Theme.swift`, and
`Localizable.xcstrings`. Coverage: account/appearance/navigation behavior,
`ThemeAndPaletteTests`, `ChromeLayoutTests`, and settings smoke scenarios.

## 11. Workstream F: reliability, accessibility, and usability

### Device/service matrix

| Scenario | Expected behavior | Verification gate |
| --- | --- | --- |
| Cold launch or return while offline | Local entries load and check-offs save; optional connections can recover later | Simulator behavior plus physical offline run. |
| App and widget/intent overlap | Conflicting stale save cannot silently overwrite newer durable data | Store tests plus real extension-process check. |
| Notification action/save failure | No false completion; retry is possible; successful action persists once | Controlled tests plus signed notification action. |
| Open app with delivered notifications | Delivered app notifications disappear; pending future requests remain | Scheduling tests plus Notification Center check on a phone. |
| Live Activity completion/retry | Failed write retains recoverable session; retry does not double-count | Existing tests plus device Live Activity. |
| StoreKit offline/restore/revocation | Valid cached access survives transient unavailability; confirmed revocation locks correctly | Deterministic tests plus signed StoreKit environment. |
| Calendar/Reminders create/edit/delete | Managed objects reconcile correctly; unrelated user objects are untouched | Sync tests plus dedicated authorized device test data. |
| iCloud account/offline/conflict recovery | Durable local state is preserved and rejected merges cannot publish incomplete data | Merge tests plus real account/service validation. |
| Export and merge import | Export is readable; supported import merges; malformed data cannot corrupt storage | Isolated round-trip/corruption tests. |
| Deep link after modal/search/sorting | Destination and draft/cancellation policy remain correct | Navigation/UI tests plus applicable device route. |

Audit before editing. Fix only defects demonstrated by a reproduction or failing
behavioral check. Do not rewrite integration engines merely because they are complex.
The native Device test plan is useful but does not replace live-service validation.

### Accessibility and visual matrix

- [ ] Smallest supported iPhone layout and a larger phone; supported minimum OS
  runtime when available, otherwise document the missing gate.
- [ ] Light/dark, solid and selected material surfaces, photo background,
  Reduce Transparency, and Increased Contrast.
- [ ] Default and largest Dynamic Type; German, English, and representative Arabic RTL.
- [ ] VoiceOver headings, reading order, button labels, numeric values, focus after
  check-off/reorder, and persistent accessible Undo.
- [ ] Reduce Motion for swipe cancellation, sorting, presentation, and grid feedback.
- [ ] Keyboard-visible creation/search, navigation bars, safe areas, and bottom actions.
- [ ] Minimum 44 pt primary tap targets; no clipped important text or controls.
- [ ] Compute contrast from actual rendered colors/surfaces where possible; do not
  declare contrast compliant from an unmeasured screenshot.

### Small task-based usability check

Invite 3-5 participants only if the user authorizes recruitment/contact. Until then,
prepare the protocol and run an internal walkthrough. Do not contact people or
record screens/audio automatically.

Ask participants to create a basic habit, complete it, correct yesterday's entry,
create a timed reminder, adjust notification times, and find appearance/account
settings. Let them attempt each task without coaching. Record anonymized task
completion, wrong destinations, accidental actions, and points needing explanation.
Timing is descriptive with such a small sample, not statistical proof.

Fix repeated friction with the smallest adjustment. One observation can also
justify a fix when it reveals an objective defect, such as an unreachable control.
Lack of participants leaves the usability gate pending; it does not prevent
independent implementation and native checks.

## 12. Validation and evidence protocol

### Per workstream

Run focused behavioral checks appropriate to its change. Inspect representative
screenshots after UI changes. Run the required complete gate at the final source
freeze; repeat it only after changes that invalidate its evidence or a failure
that requires correction. Do not remove assertions, add skips, or retry failures
automatically to make a result look green.

Use [the engineering guide](../development.md) for current commands and ownership.
These are verification examples, not release or installation commands:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  VERIFY_OUT=/Users/enricomini/Documents/haiity-verification/whole-app-YYYYMMDD-HHMMSS \
  TEST_DESTINATION='platform=iOS Simulator,id=<verified-current-simulator-UDID>' \
  bash tools/verify.sh

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild build -project Haiity.xcodeproj -scheme Haiity \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO

ruby tools/verification.rb check /absolute/path/to/evidence.json
git diff --check
```

Resolve the simulator and a fresh artifact directory before running. Store exact
commands, exit codes, logs, and native result bundles. `verify.sh` regenerates the
tracked project using the pinned generator: review its diff and preserve existing
generated changes. Never hand-edit `project.pbxproj` or bypass package validation.

### Evidence deliverables

- [ ] Per-phase implementation notes, paths changed, and reason for each change.
- [ ] Baseline/post-change timing table with matching conditions and known limits.
- [ ] Before/after screenshots for creation, Habits hierarchy, Statistics wording,
  and More/account labels at the relevant accessibility sizes.
- [ ] Native Unit/Smoke results and final unsigned Release exit status.
- [ ] Source fingerprint, HEAD, toolchain, SDK, generator, and app/widget metadata.
- [ ] Explicit physical-device and live-service results, or their concrete blockers.
- [ ] Usability observations, or a clearly pending external-participant gate.
- [ ] Remaining issues ranked by impact, with owners and the next required action.

Retain artifacts under `Documents/haiity-verification`, not only `/tmp`. Keep
personal data and credentials out of repository reports, traces, and screenshots.
Device-data inspection, recording, account changes, or installation must stay
within the user's actual authorization.

## 13. Release readiness and completion

### Documentation tasks

- [ ] Update [the design contract](../design/haiity-ui-design-system.md) for the
  implemented disclosure and page ordering; record ownership without adding a new framework.
- [ ] Reconcile [store listing](../store-listing.md) notification wording and any
  other capability claims affected by this work. Distinguish legacy editable rules
  from what users can currently create; do not advertise unavailable creation choices.
- [ ] Update screenshots/release notes only for behavior verified in the actual build.
- [ ] Create a dated implementation report separating local, hardware, service,
  usability, and release outcomes.

### Completion states

| State | Required evidence |
| --- | --- |
| Implementation complete | All scoped code/copy work done; focused checks and UI inspection pass. |
| Locally verified | Full Unit/Smoke and unsigned Release pass on final matching source. |
| Device/service verified | Applicable physical performance, accessibility, notification, sync, and purchase gates have real evidence. |
| Ready for release candidate | Exact reviewed source plus required evidence; no unresolved release-blocking defects. |
| Released to TestFlight | Separately authorized release, archive/export/upload, Apple processing, group availability, and installed build verified individually. |

Do not call the whole effort fully verified when a required hardware gate is
blocked. Report the completed work and the exact missing gate. A new commit,
build number, source change, or toolchain invalidates the corresponding release
evidence and requires revalidation.

Do not run `tools/release.sh` as a harmless check: its non-upload path installs
on a phone. Do not run its upload path, push a release commit, trigger Xcode Cloud,
or submit in App Store Connect without a subsequent release instruction. When a
release is authorized, use the engineering guide and ego-browser for all websites.

## 14. Start checklist for a future implementation turn

1. Re-read this plan, the latest human instruction, current Git state, and active work.
2. Confirm which phases already have current evidence; do not restart them.
3. Preserve dirty/untracked/recovery state and identify the first unfinished phase.
4. Start with baseline/performance work and continue independent tasks when a device
   gate is unavailable; keep that gate pending rather than treating it as passed.
5. Keep changes bounded and reuse existing native/shared paths. If workers are useful,
   follow the latest requested agent model (`sub2api/gpt-6.1-sol` at planning time)
   and give them isolated, non-overlapping ownership. This preference is not a request
   to create new user-facing chats or spend on additional providers.
6. Finish with a source-bound report and applicable validation. Ask for a release
   decision only if there is no existing authorization for the next external action.

## 15. Design rationale

The existing design contract's phrase, **quiet rhythm, visible progress**, remains
the direction. The grid carries identity; navigation and controls use familiar
iOS behavior. Keep system typography, semantic color, aligned controls, restrained
surfaces, and glass on the functional navigation layer. Preserve user appearance
choices while improving legibility in every mode.

Apple Design references consulted for the advisory review: `layout.md > Visual
hierarchy`, `settings.md > Best practices`, `onboarding.md > Additional requests`,
`entering-data.md > Best practices`, `loading.md > Best practices`, and
`liquid-glass.md > The two layers`, alongside accessibility, typography, color,
and iOS foundations. The product priorities and proposed timing budgets are our
judgment, not Apple requirements. Visual compliance still needs rendered/device
inspection; source review alone is insufficient.
