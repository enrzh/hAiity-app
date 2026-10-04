# hAiity whole-app implementation and verification

Date: 2026-10-04
Status: implementation complete and locally verified; device/service gates pending
Base: `main`, `109a06d9bfc0633e59b8d45abc60cd25aad4a0dc`
Metadata: 1.0.0 (273), unchanged
Plan: [whole-app experience and performance](2026-10-04-whole-app-experience-and-performance-plan.md)

## Implementation

- Daily habit/reminder rows precede optional GitHub activity, preserving filtered
  order and the shared graph. A GitHub-only state offers first-habit creation.
- Creator/editor use native recurrence disclosure and one Additional Settings
  section. Active hidden values are summarized; disabled notification times are
  retained. Large text uses menus/stacked controls and comfortable hit regions.
- Editing opens at the large sheet size so the form has usable space. Archive
  and deletion keep the editor open when persistence rejects the action.
- Habit-card date-window and streak work moves out of body evaluation onto the
  existing snapshot scheduler/cache. The graph and header reuse its result;
  cancelled or outdated requests cannot publish.
- Statistics uses neutral percentage-point comparisons, with metric explanations
  behind accessible Details disclosures. Mathematics and card preferences remain.
- More names setup and native connections directly. Optional Apple identity and
  StoreKit purchase state are independent. Import/export is publicly reachable,
  sharing its existing controls with diagnostics.
- Decoding/import/merge consolidate duplicate habit IDs using existing metadata
  and history rules, preventing duplicate-key crashes in native reconciliation.
- Imports throw after a rejected durable write rather than confirming success.
- Session completion durably saves history even when completion/minutes are
  unchanged; same-store failed retries cannot silently lose records or double count.
- Deep links dismiss an editor before changing destination, discard its unsaved
  draft, wait for actual dismissal, and retain latest-route precedence.
- New/touched copy is translated through the existing catalog; the listing now
  describes multiple notification times and distinguishes legacy flexible rules.
- Date selection at accessibility sizes opens native wheels from a wrapping
  full-row button. Ordinary text retains compact date selection. Decorative
  timezone symbols stay inside their slots and selection is exposed by traits.
- Import/export uses the existing central More presentation/dismissal lifecycle,
  including a verified deep-link departure, rather than another local modal owner.

Existing dirty/untracked/recovery state was preserved. No schema migration,
dependency, AI feature, widget, graph redesign, or new sync engine was added.
The split Search, history editor, native sorting and user appearance choices remain.

## Baseline and retained artifacts

Artifact root:
`/Users/enricomini/Documents/haiity-verification/whole-app-20261004`

Baseline fingerprint:
`274708f07d522b9d53d4cf583d49dd031ac5c17f606ad4c5c59108af606ea551`

Xcode 27.0 (27A266a), iOS simulator 27.0, iPhone 18 Pro, pinned XcodeGen 2.46.0.
Commands use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` because
the system-selected developer directory remains CommandLineTools.

- Baseline build-for-testing: exit 0, frozen binary in BaselineDerivedData.
- Baseline launch/navigation/graph/history/root screenshots: 4 passed, no failures,
  skips or runtime warnings, Baseline.xcresult.
- Baseline creator and large-text account screenshots: 2 passed, no failures,
  skips or runtime warnings, BaselineForms.xcresult.
- Baseline responsive-first-frame values (seconds): 6.639794333, 8.495069,
  6.162670041, 7.676492667, 6.348761958. Median 6.639794333; worst 8.495069.
  These are Debug simulator/XCTest timings, not measured phone startup latency.
- `baseline-active.sample.txt` caught HabitCard header streak and graph-window
  calculations on the main thread during UI updates. A separate launch sample
  includes dyld/simulator startup; it must not be presented as a post-splash trace.
- Screenshots/attachments remain in baseline-attachments and baseline-form-attachments.

## Diagnostic checks and corrections

The initial focused Unit run had 249 passes and 4 failures. Those failures exposed
notification-preview clock formatting assumptions and language-bundle selection
in the Statistics test. The clock formatter was corrected; its five focused tests
passed with no failures, skips or runtime warnings in ClockPreview.xcresult.
The Statistics test now selects actual built language bundles and preserves both
German and English expectations. Both corrected Statistics tests passed in the
first complete Unit run; the run overall failed six older source-layout contracts
and is not accepted as final evidence.

The first focused UI run passed six workflows and exposed two failures: an
accessibility identifier inherited by expanded Statistics text, and a launch-test
argument overriding the URL route. Both were corrected; the follow-up passed
editor-to-Stats/creation routing, accessible Statistics Details, and creation
save-conflict recovery (3 passed; its RTL case still failed at that point).

Compact RTL verification then caught a compact date string overflowing, inline
wheels consuming form-scroll gestures, a switch query covering its whole label
row, and a lazy disclosure queried as if offscreen controls already existed.
The final UI uses a wrapping date button with focused native wheels in a sheet.
Disclosures preserve child accessibility identities; the test activates the
actual RTL switch and scrolls to verify reachable controls. CompactCreatorFinal
passed its complete creator/recurrence/additional-settings/timezone flow, with
zero failures, skips or runtime warnings. That run predates the last resource-only
translation additions and the decorative timezone-symbol sizing fix; final
compact screenshot verification still needs those latest sources.

Focused UI was started before the final catalog additions and large editor-sheet
adjustment; its results are diagnostic, not final source-bound evidence. The first
complete Unit attempt passed 2,125 tests and failed six source-layout contracts.
Assertions for header/copy names, accessibility summary calls and GitHub placement
now reflect the intended behavior without removing protections. The production
startup hydration guard was retained; simulator-only GitHub demo data is seeded
at fixture initialization, avoiding a false production-startup dependency.

## Final local verification

Source fingerprint:
`e53c46c2a7ca6921dbd053be1854a7d7a86fb7fb30f40e027c9b72fffda0f0d3`

| Check | Exact result | Artifact under the root above |
| --- | --- | --- |
| Complete native Unit | 2,131 passed; 0 failed, 0 skipped, 0 runtime warnings | `verified/Unit.xcresult`, `verified/Unit.log` |
| Complete native Smoke | 24 passed; 0 failed, 0 skipped, 0 runtime warnings | `verified/Smoke.xcresult`, `verified/Smoke.log` |
| `bash tools/verify.sh` | Exit 0; final source-bound evidence created | `verified/evidence.json`, `verified.log` |
| Evidence check after all builds/checks | Exit 0; source, HEAD, metadata and toolchain match | `verified/evidence.json` |
| Performance/visual supplementary run | 5 passed; 0 failed, 0 skipped, 0 runtime warnings | `PerformanceVisual.xcresult`, `performance-visual.log` |
| Final SE, Arabic RTL, largest Dynamic Type, photo/solid creator | 1 passed; 0 failed, 0 skipped, 0 runtime warnings | `CompactVerified.xcresult`, `compact-verified.log` |
| Generic iOS Release, signing disabled | Exit 0 | `Release.log`, `ReleaseDerivedData` |
| Built app/widget metadata and privacy | Both 1.0.0 (273); both privacy manifests present | Release app and extension bundles |
| Release evidence rejection checks | 16 invalid-evidence cases rejected; changed/untracked source detected | `verified.log` |
| Catalog, links and whitespace | Catalog parses without duplicate keys; scoped translations/placeholders validated; local documentation links and `git diff --check` pass | Source/catalog and task reports |

Primary destination: iPhone 18 Pro, iOS 27.0,
`2F9C45FC-34DC-44F6-B12A-C72B9DED1673`.
Compact destination: iPhone SE (3rd generation), iOS 27.0,
`CE73965B-EDCC-4331-BF9B-86EFEA944973`.
The native commands ran serially for this task. Other project activity on the
shared Mac occurred during some runs; it was not interrupted or modified.

The complete Smoke covers initial creation -> check-off -> changed grid/Undo,
rejected-save draft retention/retry, GitHub ordering and its empty state, public
transfer plus routing away, editor-to-Stats/creation routing with unsaved drafts,
accessible Statistics Details, retained multiple notification times, native
Search, graph/history, account/edit controls, text/dictation regression fixtures,
and the exact 40-item native sorting/relaunch behavior.

Supplementary checks cover repeated navigation/scrolling, light/dark root and
secondary pages, photo backgrounds, and largest-text action reachability. The
last case runs the platform hit-region/description accessibility audit. It does
not establish universal contrast compliance or physical VoiceOver behavior.

Screenshots were inspected from `verified-attachments`,
`performance-visual-attachments`, and `compact-verified-attachments`. The final
English creator no longer shows the inspected German-only form labels; Arabic
timezone labels are translated and decorative symbols no longer crowd the text.
These are rendered fixture screens, not screenshots of the user's installed app.

Existing compiler warnings remain in MLX C++ templates and deprecated test-source
readers. No failed/skipped native result or validation bypass was accepted. No
passing partial result substitutes for the final complete Unit/Smoke evidence.

## Performance results and limits

Both measurements used the existing five-iteration crowded-data Debug simulator
launch metric, with the same simulator model, OS, test, fixture and Pro setting.
They occurred at different times, with different machine/background activity.

| Responsive-first-frame metric | Baseline | Final |
| --- | ---: | ---: |
| Runs | 5 | 5 |
| Median | 6.639794333 s | 4.610863083 s |
| Worst | 8.495069 s | 5.0117535 s |

Final values: 5.0117535, 4.53816475, 4.599138417, 4.610863083,
4.675606958 seconds. The result is a lower observed simulator timing; it is not
a controlled causal percentage improvement, a phone measurement, or proof that
the reported post-splash physical freeze is resolved. Debug loading, XCTest and
the launch animation are included. No FPS or 100 ms phone-input claim is made.

The code removes the sampled header streak/history-window calculations from
body evaluation by using the existing background scheduler and graph snapshot
cache. Native navigation/scroll checks passed after that change. Extra manual
CLI sampling ran during concurrent simulator activity and captured launch/splash
state rather than a usable interaction trace; those samples and the empty frame
log are diagnostic artifacts only and excluded from performance conclusions.

## Task-based usability protocol

The internal walkthrough uses isolated fixtures, not user data. Check whether
each task has a clear first action, truthful feedback, and a recoverable mistake:

| Task | Internal evidence | External participant gate |
| --- | --- | --- |
| Create a basic habit and check it off | UI test follows creation to changed grid and Undo, without setup prompts. | Observe uncoached creation, perceived schedule, and feedback. |
| Correct yesterday's entry | Existing history UI checks exercise earlier-month editing and Undo. | Observe discovery of history and correct date selection. |
| Create a timed reminder | Creator preview and existing text/date tests compare the reviewed schedule with the save. | Observe appointment versus notification-time understanding. |
| Add/remove notification times | UI test saves disabled values and re-enables them after reopening. | Observe discovery and whether disabled retained times are understood. |
| Find appearance/account settings | Existing settings/account UI cases exercise independent controls. | Observe destinations chosen without coaching. |
| Export/import data | Public transfer navigation and isolated merge/error tests protect reachability and truthful results. | Observe understanding of merge import versus replacement. |

For 3-5 authorized participants, record anonymous completion, wrong destinations,
accidental actions, and explanations needed. Do not contact or record anyone by
default. With that small sample, timings describe observations rather than prove
an average product improvement. The internal automated checks do not establish
uncoached human usability.

## Gates requiring additional environment/authorization

- Development-signed phone installation and matched physical profiling are not
  authorized by this plan's implementation instruction. The paired phone is
  available, but no installed build was replaced or private data inspected.
- Physical VoiceOver, held-touch sorting/swipe feel, minimum-supported-OS runtime,
  signed notification/Live Activity/StoreKit, real extension overlap and native
  Calendar/Reminders/iCloud recovery remain separate gates.
- Participant recruitment, recordings, and production analytics were not authorized.
  The task-based walkthrough can run internally; external usability remains pending.
- No commit, push, Xcode Cloud trigger, upload, TestFlight assignment or phone
  installation occurred. A release needs its own instruction and exact-source evidence.
- Legacy versions combined owner exemption and purchased access in one cache bit.
  The implementation separates new writes but does not guess whether an old true
  value was a valid offline purchase. Authoritative StoreKit evidence resolves it.

## Remaining release gates, ordered by severity

1. Matched physical profiling and post-splash first-scroll/check-off validation
   with a development-signed build and representative data. Simulator timing
   cannot close the user's physical-freeze report.
2. Real extension overlapping writes and signed notifications/Live Activity,
   StoreKit offline/restore/revocation, Calendar/Reminders managed recovery and
   iCloud conflict/account behavior. Deterministic tests pass; live services were
   not exercised in this task.
3. Physical VoiceOver, held-touch sorting/swipe interruption, 60/120 Hz feel and
   the minimum iOS 18 runtime. Compilation targets iOS 18; available runtime
   execution here used iOS 27.
4. Uncoached participant validation remains pending. The protocol is prepared;
   no recruitment/contact/recording was performed. This is usability evidence,
   separate from the engineering release gates above.

The changes are ready for code review and an authorized device verification
build. The repository is not represented as a fully validated App Store release
candidate. All source remains uncommitted, version/build remain unchanged, and
the user's prior dirty/untracked work remains intact.
