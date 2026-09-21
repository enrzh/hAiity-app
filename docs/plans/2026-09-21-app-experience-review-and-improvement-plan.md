# hAiity: experience review and improvement plan

Date: 2026-09-21
Status: implemented; simulator-verified with device-only items pending
Baseline: main, HEAD 156bd2c, with existing uncommitted work preserved

## Opinion and direction

The app has enough functionality. Its strongest identity is the habit grid and
the immediate satisfaction of recording progress. Make that loop feel effortless:
create a habit, complete it, see the square change. Prioritize responsiveness,
clear settings ownership, and consistent interaction over another whole-app redesign.

Visually, keep the native typography, contribution colors, grouped surfaces, and
separate Search tab. Use glass for navigation and floating controls; keep content
legible through the existing appearance modes. Stronger hierarchy is more useful
than more decoration: one primary action, fewer redundant captions, consistent
spacing, and no additional nested cards. Preserve user-selected surfaces.

## Evidence and limits

- Main review inspected current Statistics, More, creation, and empty-state code,
  the existing design-system document, and the earlier More screenshot at
  `/tmp/haiity-ui-phase1-more-final.png`. That screenshot predates the latest
  timezone hit-area adjustment and is not proof of current runtime behavior.
- Luna subagent `01a0c577-637b-76a0-825e-3f6e44b88f85`, explicitly running
  `sub2api/gpt-5.6-luna`, independently reviewed creation, permission timing,
  first-run guidance, and settings discoverability. Its findings were checked
  against source before inclusion.
- This is a bounded review, not a full runtime/accessibility audit. No new app
  tests, profiling, installation, or release were performed. Historical passing
  tests are not presented as verification of this proposed work.
- References: `docs/design/haiity-ui-design-system.md` and
  `docs/plans/2026-09-21-ui-unification-and-sustainable-ui-plan.md` remain the
  existing contracts. This plan complements them rather than restarts completed work.

## 1. Establish responsiveness evidence first

Priority: high. Classification: measurement requirement, not a diagnosed bottleneck.

Source: `Haiity/Views/StatsView.swift:60` refreshes using the store timestamp;
line 64 already calculates snapshots through `ContributionSnapshotScheduler` and
records a `statsCalculation` signpost. Line 160 builds the statistics content.
Do not describe the existing calculation as synchronous or add a second cache.

Actions:

- Profile a Release build on the same physical phone, with identical data and
  settings: cold launch through the first usable scroll, first Statistics visit,
  repeated tab changes, and rapid check-offs. Include offline operation.
- Use the user's approximate dataset (12 active, 10 archived, 169 log entries)
  plus a larger fixture. Record device, OS, build, thermal state, and fixture.
- Capture at least ten matched runs before and after a candidate fix. Report
  median, worst run, main-thread stalls, and scroll hitches. Do not infer a
  reliable percentile from ten samples.
- Investigate whether unrelated updates invalidate statistics and whether
  offscreen content contributes meaningful work. Change invalidation or layout
  only if traces establish a cost; a lazy stack is not automatically an improvement.
- Verify cancellation cannot publish stale data after switching accounts,
  changing habits, or changing entitlement. Preserve cached/offline behavior.

Acceptance: no reproducible interaction-blocking stall after the splash in the
measured scenario; targeted metrics improve beyond run-to-run variation without
data or navigation regressions. If no bottleneck reproduces, retain evidence and
report the limitation instead of claiming a performance fix.

## 2. Make first creation feel lightweight

Priority: high. Classification: design judgment.

Source: `Haiity/Views/EditHabitSheet.swift:203` presents preview, type, name,
emoji, recurrence, kind, and advanced settings. `ContentView.swift:1979` already
has an empty-state grid and a direct create button.

Actions:

- Prioritize the name field and Save visually. Preserve existing defaults,
  habit/reminder types, recurrence controls, and the advanced disclosure.
- Reduce redundant preview text before hiding or relocating useful controls.
  A basic habit should require only a name and Save.
- Adjust existing empty-state copy to explain completing the first habit and
  seeing its grid change. Do not turn it into notification setup guidance.
- Where notification controls are visible, clarify the relationship between
  entry time and reminders with one concise, localized explanation.

Acceptance: fresh install -> create -> check off -> visibly updated square,
without permission prompts on the ordinary untimed path. Test checkbox,
quantity, and reminder creation, editing, cancellation, and existing defaults.
No onboarding coordinator, tutorial carousel, or persisted tutorial state.

## 3. Resolve permission timing deliberately

Priority: high for verification; implementation depends on reproduced behavior.
Classification: confirmed code behavior with a proposed UX change, not a confirmed bug.

Source: `EditHabitSheet.swift:388` and `:392` request notification permission
when time or notification mode changes. `:1047` explicitly documents this as
intentional; `:1098` implements the request. User-initiated toggles can legitimately
be contextual permission triggers. The Luna review called this a bug, but the
current evidence does not establish that conclusion.

Preferred outcome: abandoned or invalid drafts should not produce unnecessary
system prompts. First test turning on time, selecting Time Sensitive, canceling,
saving, denying permission, and changing existing entries.

If prompts are premature, move the request to the existing validated Save flow,
after name/Pro validation, without making permission success a prerequisite for
saving. Keep denial guidance attached to a live presentation and ensure granting
permission schedules the saved item through the existing scheduler. Do not simply
launch a prompt from an editor that has already dismissed. Coalesce duplicate
requests only if the current permission service does not already do so.

Acceptance: no prompt for canceled drafts under the revised contract; one prompt
for an eligible Save; denial still saves the item; no duplicate notification;
Time Sensitive still enables time. Add focused regression tests for the chosen
contract before changing implementation.

## 4. Make More and secondary settings easier to scan

Priority: medium. Classification: design judgment.

Source: `Haiity/Views/MoreView.swift:315` groups settings under Manage,
Connections, Personal, and Tools; `:617` owns Behavior & Sharing. The baseline
screenshot shows consistent rows already, but broad labels hide ownership.

Actions:

- Clarify existing row subtitles: app-wide behavior, defaults for new entries,
  and per-entry overrides must be distinguishable. Verify actual semantics
  before writing copy, especially timezone and sync settings.
- Make "Run setup again" describe what it configures rather than implying a
  first-run requirement. Keep its destination available.
- Audit secondary pages against existing `AppSettingsRow`, `AppIconBadge`,
  surface, and header helpers. Reuse these where equivalent; do not create a
  general-purpose form framework or wrap every native control.
- Keep the full-row timezone Menu. It is already implemented; do not restore a
  dedicated timezone page or chevron-only target.
- Retain the selected glass/surface styling. Adjust density only where a fresh
  screenshot demonstrates wasted space, never by shrinking touch targets.

Acceptance: light/dark and each existing surface mode remain consistent;
largest accessibility text wraps without clipping; VoiceOver announces control
purpose and current value; interactive targets remain at least 44 x 44 points.

## 5. Polish Statistics hierarchy and loading, without rebuilding it

Priority: medium. Classification: design judgment plus measurement hypothesis.

Source: `StatsView.swift:160` displays today, optional year pulse, configurable
metrics, week, and ranking. The loading surface at approximately line 226 differs
from final content. Existing snapshots are retained during refresh.

Actions:

- Keep existing cards and customization. Let today's progress be the primary
  reading, with weekly context secondary and detail below. Reduce competing
  title weights and repeated labels rather than adding insights or metrics.
- Match initial loading geometry to the first visible content where practical;
  retain previous content during refresh and avoid decorative shimmer.
- Verify that refreshes do not reset scroll position or jump the title/header.
- Check empty, partial, fully completed, locked-Pro, and large-data states.

Acceptance: no unnecessary full-page loading flash on repeat visits, no scroll
jump on refresh, meaningful VoiceOver order, and no loss of configured metrics.

## 6. Finish interaction consistency and simplify only proven duplication

Priority: medium. Classification: validation and bounded cleanup.

Validate existing habit/reminder swipes before proposing another rewrite:
partial drag, cancel, commit, opposite direction, vertical scroll takeover,
one-open-row behavior, and Reduce Motion. Feedback must correspond to the
actual committed action, with no duplicate haptics or accidental completion.
Keep context menus and accessible alternatives usable without swiping.

Keep graph tiles fill-driven without decorative white borders. Preserve current
history selection and shared graph ownership; check light/dark contrast,
non-color selection cues, equal margins, and widget geometry as regressions.

`MoreView.swift` still defines `moreStatusHero` and `moreOverview`; current symbol
search found declarations only. Verify all references/configurations before
removing dead helpers. Their synchronous statistics calls are not evidence of an
active performance bottleneck. Avoid a broad ContentView rewrite.

## Execution order and completion gates

1. Record current screenshots and device performance baseline. Preserve the dirty
   worktree and compare against existing completed-plan evidence.
2. Implement measured responsiveness fixes, if justified, in small independent changes.
3. Polish creation and resolve the permission contract with focused tests.
4. Clarify settings copy and apply existing shared components to demonstrated outliers.
5. Refine Statistics loading/hierarchy; finish gesture and accessibility validation.
6. Compare before/after captures and traces. Document changes, tests, and remaining
   device-only limitations. Do not equate source checks with interaction proof.

For each phase run focused relevant unit/UI tests and a build; finish with the
repository's required regression checks. Test German and English, light/dark,
Dynamic Type, VoiceOver, Reduce Motion, and Reduce Transparency. Report exact
commands/results and pending checks. Use full Xcode explicitly if xcode-select
still points to CommandLineTools.

No new AI, social, GitHub, widget, sync, or customization features. No dependencies,
new coordinator, or speculative caching system. Preserve Pro/offline entitlement,
recurrence, end-of-day auto-resolution, import/export, and sync behavior.
Keep the dedicated split Search tab and its accepted search interaction.
This planning request does not authorize implementation, commits, pushes,
device installation, or TestFlight upload.

## Execution Record

Implementation was completed in the existing dirty checkout without resetting,
stashing, cleaning, committing, pushing, installing to a physical phone, or
uploading a release.

- Responsiveness: no source change was justified without physical traces. The
  requested Release profiling, matched before/after runs, thermal/device data,
  and physical interaction measurement remain pending because phone
  installation was not authorized. Existing `ContributionSnapshotScheduler`
  and signpost ownership were preserved.
- Creation and permissions: identity fields now precede the optional preview;
  the notification relationship is explained in localized copy. Permission is
  requested only after a valid Save persists the item. Save is single-flight;
  the saved editor stays locked through denial, both denial-alert actions
  dismiss it, interactive dismissal is disabled while permission is pending,
  denial/retry cannot add a second new item, and a grant explicitly calls
  `Reminders.reschedule(store:)` before dismissal. Unsaved and canceled drafts
  do not prompt. The form, Save, and toolbar cancellation controls are
  disabled while the saved editor waits for permission; the two state flags are
  intentional because request-in-flight and denied-alert phases have different
  behavior.
- First-run copy: the empty Habits and Statistics states now explain the
  complete-the-first-entry loop and seeing the grid grow; they do not redirect
  users into notification setup.
- More: existing `AppSettingsRow` and `AppIconBadge` are reused. Behavior
  ownership and setup scope are explicit, while the full-row native timezone
  menu remains unchanged. No prior UI unification or timezone page was
  restored.
- Statistics: the loading state reuses the existing today card with a
  placeholder snapshot and redaction, preserving loaded geometry and Dynamic
  Type behavior without shimmer or a second layout.
- Hierarchy and cleanup: today's Statistics card remains the primary reading,
  weekly context follows it, and the unused `moreStatusHero`, `moreOverview`,
  and `moreMetric` helpers were removed after reference search confirmed they
  had no live callers.
- Interaction: existing swipe and graph ownership/contracts were retained and
  verified with pure and simulator UI tests. No speculative performance fix or
  new dependency was added.
- Localization: new creation/settings/loading strings have German source text
  and English catalog translations in `Haiity/Localizable.xcstrings`.

Verification completed:

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=2F9C45FC-34DC-44F6-B12A-C72B9DED1673' -only-testing:HaiityTests/HabitTimeTests/testNotificationPermissionWaitsForSavingTheDraft -only-testing:HaiityTests/FeedbackTests/testMoreKeepsCloudStatusInDeveloperToolsAndUsesConciseSettings -only-testing:HaiityTests/AppNavigationTests/testDefaultTimeZoneUsesTheWholeSettingsRowAsTheMenuLabel -only-testing:HaiityTests/SwipeRevealTests -only-testing:HaiityTests/StatsAndReorderTests -only-testing:HaiityTests/ThemeAndPaletteTests -testLanguage de -testRegion DE -quiet`: passed.
- Full `HaiityTests` with `-testLanguage de -testRegion DE`: 1,795 passed,
  zero failures or skips, independently confirmed from
  `Test-Haiity-2026.09.21_21-59-37-+0200.xcresult`.
- Release simulator build with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Haiity.xcodeproj -scheme Haiity -configuration Release -destination 'id=2F9C45FC-34DC-44F6-B12A-C72B9DED1673'`: `BUILD SUCCEEDED`.
- Simulator UI checks for habit creation, graph long press, and reminder swipe:
  three passed across the `22-01-41` and `22-02-38` result bundles on booted
  iPhone 18 Pro simulator `2F9C45FC-34DC-44F6-B12A-C72B9DED1673`.
- Permission denial/retry coverage is a source-contract check, not a runtime
  system-permission-dialog test. Live grant/denial and notification delivery
  remain verification gaps; passing source assertions does not prove them.
- `jq empty Haiity/Localizable.xcstrings` and `git diff --check`: passed.
- The initial default-locale baseline run reported 48 pre-existing failures:
  `HabitSessionTests.testDurationText`, the time/recurrence cases in
  `HabitTimeTests`, `HomeShortcutsTests.testMenuWithoutOpenHabitCarriesTheThreeDestinations`,
  `LegacyFieldsSurviveTests.testFlexibleGoalSurvivesARoundTripThroughTheEditor`,
  the `RecurrenceDraftTests`, `RecurrenceOrdinalTests`, `RecurrenceTextTests`,
  `ReminderOccurrenceTests`, `ReminderUpcomingTests`, `SiriIntentTests`,
  `SummaryTextTests`, and `UndoToastStateTests` cases reported by that run.
  Re-running with `-testLanguage de -testRegion DE` passed the full unit suite;
  this execution did not mask or broaden the default-locale baseline failures.

Pending verification is physical-device performance/swipe feel, VoiceOver rotor/order,
Reduce Motion/Transparency and increased-contrast interaction review, and the
full light/dark Dynamic Type matrix on hardware. The simulator test runner also
reported an environment diagnostic warning while collecting diagnostics:
`xcrun: error: unable to find utility "simctl"`; it did not prevent build or
test execution when `DEVELOPER_DIR` was set explicitly.

## Ready-to-use execution prompt

> Implement `docs/plans/2026-09-21-app-experience-review-and-improvement-plan.md`
> in `/Users/enricomini/Documents/Github/hAiity`. Inspect current code, instructions,
> tests, and Git state first; preserve all existing changes. Follow the existing
> design-system contract and do not repeat completed work. Use Sub2API Luna only
> for any bounded subagents and ego-browser for any browser work. Start with
> measurements, make minimal evidence-backed changes in the plan's order, and
> preserve the habit/history UI, split Search, and full-row timezone menu. Add
> focused regression tests where behavior changes. Report exact verification
> results and any unverified device behavior. Do not commit, push, install on my
> phone, or upload to TestFlight without a separate request.
