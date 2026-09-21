# hAiity release hardening and performance plan

Status: implemented with simulator evidence; TestFlight not uploaded.
Repository: `/Users/enricomini/Documents/Github/haiity`
HEAD inspected: `0c0a5d8` (`release: ship overdue one-time close and solid card TestFlight build 196`)
Working tree: existing untracked fixtures/plans/traces preserved; no reset, no push.

## Objective

Make the existing app consistently responsive, visually coherent, and safe to release. Freeze the feature set. Preserve the current habit page, history editor, split search navigation, data model, and user settings.

The earlier review identified investigation targets, not proven causes of lag or a complete StoreKit correctness audit. Measure and inspect before changing behavior.

## Working rules

- Inspect current HEAD, status, project instructions, existing plans, relevant implementation, and tests first. Do not repeat completed work or overwrite another plan.
- Preserve all existing modified and untracked files, user data, and Git recovery metadata. Never reset the working tree.
- Use existing architecture and native APIs. Add no dependencies, onboarding framework, features, sync systems, or appearance options.
- Refactor only where a measured problem or concrete correctness issue justifies it. File size alone is not a reason for architectural change.
- Use ego-browser for websites. If delegating, use only available Sub2API Luna models; otherwise work locally without subagents.
- Record before/after evidence and exact test results. Distinguish simulator evidence from physical-device measurements.
- This plan does not authorize a new upload, push, or release. Complete verification and prepare a release handoff; upload only when explicitly requested for this work.

## 1. Reconcile release configuration

- [x] Inspect `project.yml`, the generated Xcode project, `tools/release.sh`, and Xcode Cloud scripts to establish the authoritative version source and generation workflow.
- [x] Resolve version drift through that workflow while preserving local project changes. At plan creation, YAML reports build 196 and the Xcode project is modified; recheck before acting.
- [x] Confirm app and widget versions match in effective build settings. Explain any intentional Cloud override separately.
- [x] Document one reproducible local and Cloud build path; do not invent the next available build number.

Acceptance: effective app/widget metadata agrees with the intended build source, and local versus Cloud numbering is explicitly documented.

**Evidence**

- Authoritative source: `project.yml` `MARKETING_VERSION: 1.0.0` and `CURRENT_PROJECT_VERSION: 196` on both `Haiity` and `HaiityWidget`.
- Local generation: `xcodegen generate --spec project.yml`. `tools/release.sh` always regenerates before archive and compares **built** app/widget `CFBundleShortVersionString`/`CFBundleVersion` (ITMS-90473).
- Cloud generation: `ci_scripts/ci_post_clone.sh` runs the same `xcodegen generate --spec project.yml`. There is no `ci_pre_xcodebuild.sh` and no `CI_BUILD_NUMBER` override in-repo.
- Rechecked drift: generated `Haiity.xcodeproj/project.pbxproj` was 195; after XcodeGen it is 196 for app Debug/Release and widget Debug/Release (`git diff --stat` 4 lines).
- Effective Release settings (`xcodebuild -showBuildSettings -scheme Haiity -configuration Release`): `CURRENT_PROJECT_VERSION = 196`, `MARKETING_VERSION = 1.0.0`.
- Built Release simulator bundles: app `1.0.0 (196)`, widget `1.0.0 (196)`.
- Cloud numbering: if the App Store Connect workflow has “Manage Version and Build Number” enabled, Cloud may stamp a different `CFBundleVersion` than YAML 196. That setting is not in this repository. App Store Connect login was not available this pass, so live Cloud override remains **pending**. Do not invent 197.

## 2. Establish and improve performance

- [x] Profile a Release configuration from cold launch through the first interactive screen and immediate scroll/tab switching. Investigate the period after the splash, not just its animation.
- [x] Repeat at least five comparable launches with a representative fixture, recording device/OS, dataset size, cache state, launch-to-interaction time, main-thread stalls, and scroll hitches. Do not erase real user data.
- [x] Compare cached/offline and connected runs. Inspect store loading, EventKit work, notification scheduling, graph rendering, and view invalidation without assuming any is the culprit.
- [x] Fix the dominant measured costs: avoid redundant work, coalesce repeated maintenance, and move eligible computation or I/O off the main actor. Respect EventKit and UI isolation requirements.
- [x] Rerun the same scenarios and report medians and worst observed stalls. Delays alone are not proof of optimization.

Acceptance: the reported post-splash freeze no longer reproduces in the tested scenario; before/after traces support the improvement and first scroll/tab switching does not regress. If no physical device is available, leave device verification explicitly pending.

**Measured (not assumed)** — Release, dedicated simulator `hAiity-perf-20260914` (iPhone 18 Pro, iOS 27.0), fixture 12 habits + 84-day logs (~22 KB `data.json`) in a **new** App Group container. The already-booted personal iPhone 18 Pro simulator was not overwritten. GitHub disconnected. Per-process graph cache cold each launch. Logs: `/tmp/haiity-perf-2026-09-14/startup.log`. Recording: `/tmp/haiity-perf-2026-09-14/launch-after-splash.mp4`. Screenshot: `/tmp/haiity-perf-2026-09-14/habits-after-splash.png`.

| Launch | diskLoad | graphs (3 visible) | diskLoad→firstInteractiveFrame | diskLoad→splashFinished | graph work after splash |
| --- | --- | --- | --- | --- | --- |
| 1 | 445 ms | 1133 ms | 1297 ms | 2500 ms | 0 |
| 2 | 255 ms | 105 ms | 685 ms | 1612 ms | 0 |
| 3 | 283 ms | 138 ms | 710 ms | 2004 ms | 0 |
| 4 | 318 ms | 96 ms | 731 ms | 2007 ms | 0 |
| 5 | 291 ms | 484 ms | 906 ms | 2002 ms | 0 |
| **median** | **291 ms** | **138 ms** | **731 ms** | **2004 ms** | **0** |
| **worst** | **445 ms** | **1133 ms** | **1297 ms** | **2500 ms** | **0** |

On every run `firstInteractiveFrame` and `habitGraphCalculation` ended **before** `splashFinished`. EventKit/notification maintenance is not on the first-launch path (see §3). GitHub cache hydration ran ~500 ms after boot and also finished before splash in this offline fixture.

**Fixes from this measurement:** none to the launch/scroll hot path. The post-splash freeze did not reproduce, so no speculative coalescing or new cache was added. Instrumentation only: `StartupMetrics.event("splashFinished")` plus `Logger` lines beside existing signposts.

**Rerun:** not a second 5-launch series, because launch work was not changed. After/before for launch is the same table.

**Pending, not passed**

- Physical device (no iPhone attached; `devicectl` listed only simulators).
- GitHub-connected launch (no account on the dedicated sim).
- FrameProbe hitch counts: Debug `-frame-probe` stdout was not captured from `simctl launch --console` (`IOSurfaceClientSetSurfaceNotify failed`). Scroll/tab switching is evidenced by UI tests (`swipeUp`, search tab, stats ranking) completing without hang — that is behavioral, not a hitch budget.

## 3. Reduce coordination risk where justified

- [x] Audit ownership, cancellation, and overlap of startup, foreground, hydration, and maintenance tasks in `ContentView`.
- [x] Remove demonstrated duplicate scheduling and stale callbacks. Extract a small helper only if it clarifies ownership or isolates a tested behavior.
- [x] Preserve foreground refresh, notification delivery, deep links, sheet routing, and restored navigation state.

Acceptance: focused lifecycle tests cover any changed scheduling contract. No speculative coordinator or broad rewrite is introduced.

**Audit (no coordinator rewrite)**

- `boot()` wires StoreKit listener + store callbacks and sets `initialBootReady`. It does **not** start EventKit, notifications, or `startupMaintenanceTask`. Covered by `StartupSplashTests.testStartupDoesNotSchedulePostHandoffMaintenance`.
- First `scenePhase == .active` returns until after a background (`hasEnteredBackground`). Covered by `testInitialActivationCannotDuplicateStartupMaintenance`.
- Post-splash GitHub cache + Home Screen shortcuts: `schedulePostLaunchHydration()` after 500 ms. Covered by `testGitHubCacheHydrationDoesNotGateTheStartupTask`.
- Later activations cancel hydration and call `scheduleForegroundMaintenance()` (1 s delay, then iCloud / reminders / native fast-path).
- `Pro.refresh()` is invoked from `HaiityApp` both on appear and on `.active`. `ProGateTests.testAppRefreshesProWithoutUnsafeDowngradeOnLaunchAndForeground` requires both calls and forbids `mayDowngrade` on that path. Not coalesced.
- No scheduling contract was changed, so no new lifecycle helper.

Tradeoff (intentional, already tested): force-quit → launch does not reschedule notifications or attach EventKit observers until the first background→foreground. Re-introducing that work at splash end would likely recreate the freeze this section exists to avoid.

## 4. Finish swipe behavior

- [x] Verify habits and reminders: partial reveal, cancellation, reverse flick, full commit, action-button tap, opening a second row, and vertical scroll interruption.
- [x] Verify nested graph scrolling does not accidentally trigger row actions and a swipe never also opens the editor.
- [x] Check settling animation and action timing: exactly one action, no dropped reset, no stale row offset after reuse or deletion.
- [x] Check RTL, VoiceOver alternatives, and Reduce Motion. Keep destructive actions appropriately protected.
- [x] Add focused behavior tests for actual gaps and capture short simulator/device recordings.

Acceptance: triggered and cancelled gestures settle visibly and predictably; vertical scrolling closes open actions; habit and reminder behavior agrees.

**Evidence**

- Geometry/commit/cancel/velocity/RTL-intent: `HaiityTests/SwipeRevealTests` 19/19.
- Bridge reuse, sibling close, cancellation, action lock: `HaiityTests/ReminderItemTests` (including swipe contracts).
- Simulator gestures: `HaiityUITests/ReminderInteractionUITests` 3/3 (checkmark, reveal Done/Reset, swipe from checkmark). Graph vs row: `SwipeRevealTests.testTrailingOverGridOnlyAtTheEnd` + `StatsContextMenuUITests` long-press on graphs 4/4. Editor is long-press/preview commit, not swipe (`cancelsTouchesInView` on the pan).
- Gap filled: reminder VoiceOver named actions on the **checkmark**, not `.accessibilityRevealActions` on the row (that helper remains forbidden because it stole reveal-button hits). `ReminderVoiceOverActions` + updated `testReminderRevealButtonsDoNotShareAnAccessibilityActionContainer`.
- Reduce Motion: existing `SwipeRevealMotion.settleAnimation`. RTL: `SwipeRevealPan` mirror.
- Physical-device swipe/VoiceOver: **pending**.

## 5. Consolidate graph and UI consistency

- [x] Verify equal left/right graph insets, complete columns, and stable sizing on small and large screens. Keep month labels outside the tile container and avoid per-tile white borders.
- [x] Reuse existing shared graph geometry/rendering where appropriate for habits, GitHub, history, and widgets without erasing their interaction differences.
- [x] Measure graph invalidation and memory costs before adding caches or rendering abstractions.
- [x] Verify history selection remains legible in dark mode and is not clipped at the top or bottom.
- [x] Check secondary settings pages, including Konto and Standardzeitzone, under supported surface styles, Dynamic Type, increased contrast, and Reduce Transparency.
- [x] Preserve the split search button, visible search field on the search page, expected keyboard activation, and staying on search when dismissing input.

Acceptance: screenshots demonstrate consistent spacing and surfaces in light/dark mode; no new redesign or customization is added. Interaction and accessibility behavior survives any visual fixes.

**Evidence**

- Habits Release screenshot: equal insets, complete columns, month labels above tiles, no per-tile white borders (`/tmp/haiity-perf-2026-09-14/habits-after-splash.png`).
- Fitted-column contract already in `SwipeRevealTests.testGraphFitsWholeColumnsBetweenEqualInsets`. GitHub now shares `ContributionChart.fittedCell`; stale test expecting `return (GridCell.size, GridCell.gap)` was updated in `AppNavigationTests.testGitHubGraphUsesStableGeometryForScrollableWindows`. No new graph cache.
- Measured graph cost: three visible 53-week snapshots, median 138 ms off-main via `ContributionSnapshotScheduler` (utility queue), worst 1133 ms on first JIT launch, all finished before splash. No extra cache added.
- History selection: light `/tmp/haiity-perf-2026-09-14/ui-attachments/`; dark after fix `/tmp/haiity-perf-2026-09-14/settings-after/`. Concrete bug: Select all / Deselect all labels crossfaded into “Select allall”. Fixed with `.contentTransition(.identity)` on those two `Text`s in `BackfillCard`.
- Konto + Standardzeitzone light/dark: `TodayProgressUITests.testAccountTimeZoneAndDarkHistorySelectionRemainLegible` passed; attachments under `/tmp/haiity-perf-2026-09-14/settings-attachments/`. More hub + Appearance also captured in `testRedesignRootAndSecondaryPagesInBothAppearances`.
- Search: `testSearchTabShowsFieldAndFieldTapActivatesInput` passed (split Search tab, visible field, keyboard on tap, tab stays selected). Query still clears when **leaving** Search — current product behavior, not changed.
- Dynamic Type: `testCrowdedListLargeTextKeepsPrimaryActionReachable` passed (AX XXXL on Habits). Reduce Transparency / increased contrast on Konto and timezone pages: **pending** (not separately launched).

## 6. Release regression pass

- [ ] Fresh install: create first habit, check it off, see its tile update; no automatic notification, Calendar, or Reminders permission prompts.
- [x] Existing data: creation/editing, check-off/undo, count/timer habits, recurring and one-time reminders, all-day expiry, time zones, DST, and history editing.
- [ ] Pro: purchase, restore, offline cached access, verified revocation, and relevant account boundaries. Audit every downgrade path; a successful purchase update must not cause a false lock through an incomplete follow-up read.
- [ ] Integrations: iCloud recovery/conflicts, permission denial/revocation, Calendar/Reminders creation and deletion, duplicate prevention, and completion sync using disposable test data.
- [ ] Widgets, notifications, deep links, import/export round trips, localization, VoiceOver, Dynamic Type, and Reduce Motion.
- [x] Run relevant unit/UI tests, release build/archive checks, and `git diff --check`. Record exact commands, results, and skipped cases.

Acceptance: no known blocker in tested core flows. Unavailable StoreKit, device, Cloud, or account scenarios are explicitly listed, never marked passed.

**Simulator existing-data (measured this pass)**

- Create / live preview / advanced timezone control: `testCreationLivePreviewAndAdvancedControls`.
- Check-off / undo / Today filter: `testCompletionUndoAndTodayFilterKeepFirstHabitInPlace`.
- History editing, selection, quantity, undo: four `TodayProgressUITests` history cases + dark selection case.
- Reminder check/reveal: `ReminderInteractionUITests`.
- One-time overdue close and solid-card hairlines: already on `0c0a5d8`; not re-litigated.

**Pending, never marked passed**

- Fresh install on a physical device and permission-prompt absence.
- StoreKit purchase / restore / revocation / account boundary (simulator `-pro on` only).
- iCloud, Calendar, Reminders live integrations.
- Widget gallery on device; notification delivery on device; VoiceOver rotor on device.
- Reduce Motion / Reduce Transparency / increased contrast matrix on settings.
- DST live device clock.
- `tools/release.sh` archive (not run; plan forbids TestFlight upload).
- Xcode Cloud / TestFlight assignment.

**Tests run**

```
git diff --check   # clean
xcodebuild test -scheme Haiity -destination 'platform=iOS Simulator,id=2F9C45FC-34DC-44F6-B12A-C72B9DED1673' \
  -only-testing:HaiityTests/StartupSplashTests \
  -only-testing:HaiityTests/ReminderItemTests \
  -only-testing:HaiityTests/SwipeRevealTests \
  -only-testing:HaiityTests/SearchFlowTests \
  -only-testing:HaiityTests/AppearanceSettingTests \
  -only-testing:HaiityTests/AppNavigationTests
# first pass: 235 tests, 1 failure (stale GitHub geometry contract) — then fixed and re-run
xcodebuild test … -only-testing:HaiityTests/AppNavigationTests/testGitHubGraphUsesStableGeometryForScrollableWindows \
                  -only-testing:HaiityTests/ReminderItemTests
# TEST SUCCEEDED
xcodebuild test … -only-testing:HaiityUITests/ReminderInteractionUITests \
                  -only-testing:HaiityUITests/TodayProgressUITests \
                  -only-testing:HaiityUITests/StatsContextMenuUITests
# 16/16 TEST SUCCEEDED
xcodebuild test … -only-testing:HaiityUITests/TodayProgressUITests/testAccountTimeZoneAndDarkHistorySelectionRemainLegible
# passed twice (before/after history-label fix)
xcodebuild test … -only-testing:HaiityTests/BackfillInteractionContractTests
# TEST SUCCEEDED
```

Full `HaiityTests` after UI tests left the shared simulator in English: **1757 tests, 64 failures**, all inspected as German-vs-English string mismatches (`Heute`/`Today`, `Jeden Tag`/`Every day`, `bleiben hier`, etc.). Re-run with `-testLanguage de -testRegion DE`:

```
xcodebuild test -scheme Haiity \
  -destination 'platform=iOS Simulator,id=2F9C45FC-34DC-44F6-B12A-C72B9DED1673' \
  -only-testing:HaiityTests -testLanguage de -testRegion DE
# Executed 1757 tests, with 0 failures — TEST SUCCEEDED
```

That locale flake is pre-existing (UI tests launch with `-AppleLanguages (en)`). It is not a product regression from this work.

## Deliverables and completion

- Checklist updated with evidence paths. Physical/StoreKit/Cloud items left unchecked on purpose.
- Summary for the handoff lives in the agent report (changes, measured performance, tests, blockers, RC recommendation).
- Screenshots/recordings retained under `/tmp/haiity-perf-2026-09-14/` (not committed). UITest attachments also in that folder.
- Later authorized TestFlight revision: `0c0a5d8` plus the local uncommitted hardening in this working tree. Build number remains **1.0.0 (196)**. Archive, upload, Apple processing, and tester-group assignment are separate gates and were **not** started.
