# hAiity responsiveness and consistency

Date: 2026-10-01
Status: implemented and locally verified on 2026-10-02; physical-device profiling remains pending
Baseline: main, 4f7ecf6, build 268, including the existing dirty worktree

## Scope

Keep the contribution grid, history editor, split Search, appearance choices,
data model, permissions and integrations. No new product features, dependencies,
global cache, onboarding framework, commit, upload or App Store submission.

1. Reject numeric output without parsing integers; prevent cancelled or stale
   Statistics generations from publishing or overwriting the cache.
2. Measure existing hot paths, remove repeated per-pass timezone/day resolution,
   tighten the coarse frame-work regression budget and add launch/navigation
   measurements. Treat benchmark results as helper timings, not proof of FPS.
3. Share action timing across habit, reminder and search rows. Check-ins update
   during the tap; page/removal actions close first. Preserve spring cancellation,
   gesture reversal, sibling closing, RTL and Reduce Motion.
4. Add an explicit reminder Edit control, separate from completion and swiping.
5. Reuse the existing settings-page shell for Appearance and simplify the
   optional Statistics sentence surface. Preserve user-selected materials.
6. Let reminder text and toast layout wrap/stack at accessibility sizes; keep
   Undo available without timed expiry for VoiceOver or accessibility text.
   Verify light/dark, long names, photo backgrounds and transparency fallbacks.
7. Add behavioral tests for generation cancellation/freshness, immediate swipe
   delivery, gesture interruption, reminder editing and recovery/navigation.

## Baseline evidence

Artifacts: /tmp/haiity-polish-5VOHXO

- German PerformanceTests: 16 passed, zero failures/skips, iPhone 18 Pro
  simulator, iOS 27.0, Debug. Existing 500-iteration warmed measurements:
  progress across 50 mixed-zone habits 0.95431 ms/call; one zone 0.66120 ms/call.
- These fixture benchmarks are not matched physical-device launch/scroll runs.
- Physical iPhone Air is reachable on iOS 27.2 and has build 272 installed,
  newer than this checkout. It was not replaced or reset.
- Time Profiler on that installed app failed: Apple denied debugging because
  the app lacks get-task-allow. The saved trace is not a valid performance
  result. Physical-device profiling requires a development-signed build.

## Verification

- German unit suite: 2,062 passed, zero failures/skips (unit-verified.xcresult).
- iPhone 18 Pro targeted UI: 5/5 passed (ui-3.xcresult), including reminder
  Edit without completing, scroll cancellation, repeated navigation, photo
  backgrounds, and persistent large-text Undo. Further regression run: 9/9
  passed (ui-final.xcresult), including Search, history/graphs, AX5 secondary
  pages, reminder previews/checkmarks/reveals and launch measurement.
- Release iOS build, signing disabled: passed. Shared header concurrency
  captures were corrected and release-final.log is empty (successful quiet
  build); final graph-fix build still pending.
- Screenshots are exported in ui-3-attachments and ui-final-attachments. Their
  review caught the root-title AX5 overlap and low-contrast photo previews;
  both were corrected. Preview backgrounds now reuse AppearanceBackground.
- Post-change warmed helper timings: mixed-zone progress 0.47878 ms/call,
  one-zone progress 0.46612 ms/call. These separate runs had different machine
  load (other helper timings changed too); no causal percentage or FPS claim.
- XCTest responsive first-frame metric, crowded Debug simulator, five runs:
  6.6018, 7.7165, 8.2807, 6.9386, 8.6645 seconds; median 7.7165, worst 8.6645.
  No matched baseline or physical-device latency conclusion. This measurement
  predates the compact-device placeholder fix below.

## Startup defect found during compact validation

The initial SE compact UI run failed all three queries with snapshot timeouts;
the splash remained visible. iPhone 17e reproduced sustained main-thread work.
Sampling showed repeated ContributionGrid construction during the first frame.
A temporary width-only diagnostic confirmed viewport oscillation between 358
and 365.348 points: the cold graph placeholder's fitted content width expanded
the containing row before the async snapshot could appear. Half-point tolerance
alone did not fix that larger oscillation.

The interactive loading placeholder now sits inside the same horizontal
viewport as the loaded habit/GitHub graph. Width updates also ignore sub-point
layout noise. The temporary diagnostic was removed. Manual iPhone 17e launch
then showed the habit list and settled to idle CPU, with screenshot
compact-fixed.png. The SE retest passed both tests (normal/AX5 reminder editing
and Search input) with zero failures/skips. Final graph/launch/unit validation:
2,064/2,064 passed (2,062 unit tests plus graph and launch UI checks). Post-fix simulator launch metric median 6.2298 s, worst
6.8761 s over five runs; machine load and fixture dates differ, so this is not
a matched causal comparison or a phone-performance claim.

The final accessibility surface resolver also shares an opaque fallback for
Reduce Transparency, Increased Contrast and Performance Mode across cards and
settings. The complete final German unit run passed 2,063/2,063 with zero
failures/skips (unit-done.xcresult). Final Release build after this small change
passed with signing disabled and no warnings/errors (release-complete.log is
empty in quiet mode, process exit 0); physical phone build 272 was untouched.

The temporary SE simulator created for validation is removed after screenshots
and results are saved. No existing simulator or user data was reset.

The final large-text Undo screenshot revealed capsule clipping despite its
button remaining hittable. Accessibility toasts now use the existing card
radius; default compact toasts keep their capsule. The follow-up accessibility,
Undo and Statistics checks passed 32/32 with no failures/skips. Statistics requests
also mark their working state synchronously to coalesce same-turn repeated taps.
The final Release check for these last small changes passed for generic iOS,
signing disabled, exit 0; release-last.log is empty in quiet mode. Diff checks
are clean. No commit, push, TestFlight upload or phone installation occurred.

## Physical-device limits

Do not overwrite the phone's newer build 272 with this older checkout. Its
TestFlight binary cannot be attached to Time Profiler. Development-signed,
matched before/after runs with the user's real data, thermal state and settings
are still needed before claiming their particular post-splash stall is solved.
