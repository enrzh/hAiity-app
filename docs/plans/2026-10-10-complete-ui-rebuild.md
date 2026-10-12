# hAiity Complete UI Rebuild Plan

> Execution handoff: after the user authorizes implementation, use `executing-plans` or bounded `subagent-driven-development` to complete the tasks and verification below. This document is the detailed design and implementation plan; it is not an implementation result.

Date: 2026-10-10
Author: main assistant
Status: authorized local implementation and verification complete; external gates recorded below
Baseline inspected: `main` at `1927064`; the preceding UI implementation is `3a0f4c6`
Repository: `/Users/enrico/Documents/GitHub/haiity`

**Goal:** Rebuild hAiity's presentation around doing today's work, managing a collection, and understanding progress, with a consistent visual language and clear action ownership.

**Architecture:** Replace screen compositions and simplify their presentation ownership. Reuse the current persistence, recurrence, occurrence, graph, sync, notification and purchase implementations. Give actual screens their own views; extract a shared control only where the rebuilt screens have real duplicate callers.

**Tech stack:** SwiftUI, existing UIKit sorting and context-menu bridges, native navigation and controls, `Theme`, `AppUIComponents`, `ContributionChart`/`ContributionTiles`, XcodeGen, native Unit/Smoke/Device plans. No new dependency or UI framework.

Reading guide: [navigation](#3-product-structure), [visual rules](#4-visual-language), [Today](#5-today-screen), [collection](#6-habits-collection), [details](#7-item-details-and-full-history), [creation](#9-creation-editing-and-sentence-input), [implementation](#18-implementation-sequence), [verification](#20-verification-plan).

## Final result (2026-10-12 03:13 UTC)

Tasks 0-10 are complete for the authorized local UI rebuild. The implementation and all dirty/untracked work remain in `/Users/enrico/Documents/GitHub/haiity/.worktrees/2026-10-10-ui-rebuild`, branch `codex/haiity-ui-rebuild`. Base HEAD remains `19270646a142ba88c3b94a6094137738eea7144b`; exact source fingerprint is **`b2397935093d745a45dc5988f96d8fe9899d60ba0254bdb8c724e0dc25902b64`**. Main checkout, original untracked plan, recovery state and earlier diagnostic artifacts are preserved.

Evidence directory: `/Users/enrico/Documents/haiity-verification/ui-rebuild-20261010/Final`. All final gates use Xcode 27.0 (`27A266a`), SDK 27.0, pinned XcodeGen 2.46.0 and app/widget `1.0.0 (278)`. Simulator execution uses iPhone 17 Pro QA `43B7F59D-8E63-4C28-9099-9DBABE305363`, iOS 26.5 (`23F77`). The unchanged local version/build number is baseline metadata; no new distribution build was allocated.

| Gate | Verified result | Evidence |
| --- | --- | --- |
| Complete Unit | 2,204 passed, zero failures/skips | `Unit7.xcresult` |
| Complete Smoke | All 70 registered selectors passed, zero failures/skips/runtime warnings | `Smoke8.xcresult` |
| Release candidate compilation | Unsigned generic-iOS Release succeeded | `Release5.xcresult`, `Release5.log` |
| Built resources | App/widget versions match; 17 locales, 15 new keys/255 translations, 80 reused-key locale additions, prior catalog data preserved, privacy declarations/assets checked | `Release5Resources.json` |
| Performance | 3 passed, zero failures/skips; first-frame median 1.304670 s (5 samples), collection scroll 2.300282 s (3), native sorting scroll 2.300469 s (3) | `Performance4.xcresult`, `Performance4Metrics.json` |
| Source binding | `record` and `check` succeeded for the exact fingerprint/toolchain/version; queue sealed at exit 0 | `evidence2.json`, `CandidateIdentity2.json`, `FinalGates2.exit`, `FinalGates2.log` |
| Visual review | 119 deliberate final PNGs exported; 16 representative captures inspected directly, covering roots/details, ordinary/selected history, creator, keyboard-open AX5 sentence, RTL/photo, sorting, settings, account and material selection | `AppFinalCaptures/manifest.json` |
| Capture policy | All three plans request screenshots; activity metadata for all 70 Smoke cases has 119 retained attachment references and zero screen-recording attachments | `CapturePolicy2.json` |

The final correction retains the sentence/microphone when the empty prompt becomes a preview, and clears the Settings child path after actual guarded dismissal. Both have native failing-then-passing evidence, and both pass within the final complete Smoke run. The bounded read-only review's single material finding was reproduced and fixed; every worker is closed and no native build/test job remains active.

The 23 direct-view environment warnings in Unit helper/source checks remain recorded. Native layout evidence comes from the UI run and inspected captures. History contrast retains only the two identifier-specific iOS 26.5 simulator heuristic exceptions documented in the execution history, backed by the controlled UIKit comparison; physical VoiceOver/contrast verification remains open. Performance comparisons are bounded simulator observations: baseline capture policy differs and real-data phone performance has separate status.

### Open platform and distribution gates

These gates require separately authorized device/service work. Their precise outstanding status satisfies this plan's requirement to distinguish local completion from external verification.

| Gate | Precise outstanding boundary |
| --- | --- |
| Physical app and input | No authorized candidate installation or real-data phone launch/return; held-finger sorting and actual VoiceOver remain unverified on a phone |
| OS compatibility | Only iOS 26.5 runtime is installed; older compatibility and the actual iOS 27 branch have no executable runtime evidence here. SDK 27 compilation is recorded separately |
| System hosting and services | Actual Home/Lock Screen widget refresh/tint/clear hosting, Live Activity actions/timers and notification timing/banner cleanup remain unverified for this candidate; helper/engine/intent checks retain their local scope |
| Native account/data recovery | Cross-device iCloud, granted/denied Calendar/Reminders recovery, real Photos selection/crop and authenticated Apple/GitHub recovery need the relevant device/account. Fixture/layout and saved-field checks have local evidence |
| Trusted live URL delivery | XCTest's public URL opener relaunches the app; the UI-runner in-process call returned `FBSOpenApplicationErrorDomain Code=3`, `Request is not trusted`. The existing Device-only case remains unrun; no trust/signing bypass was attempted |
| Cloud upload | No new commit, push, unique release build allocation or Cloud upload was performed for this dirty candidate; local Release success does not establish a Cloud worker's verification/archive/upload |
| Apple processing | No candidate processing or TestFlight availability was verified |
| Tester assignment | No candidate tester-group assignment was performed or verified |
| Installed TestFlight | No installed phone build was verified against this source. Historical build 278 evidence belongs to the October 9 baseline |

No credential extraction, recording, physical installation or data reset was performed. Browser/account verification for this candidate remains unperformed; the current website preference is Chrome Use with Chrome. The local worktree and evidence are retained for review. Completion heartbeat **`check-haiity-redesign-completion` was deleted** through the app tool after all applicable local gates and the explicit external-gate report were complete. The tool returned `deleteStatus: deleted`; its exact automation file is absent. No other automation was changed.

## Execution history (superseded by the final result above)

- Authorized by the user: "Start with it and create a cron to make sure it's completed."
- Implementation: `/Users/enrico/Documents/GitHub/haiity/.worktrees/2026-10-10-ui-rebuild`, branch `codex/haiity-ui-rebuild`, starting commit `19270646a142ba88c3b94a6094137738eea7144b`. Main checkout and original untracked plan preserved.
- Baseline source fingerprint confirmed live: `7871e745be01203790af1fb3f7ac8466840c6735c53413e7bf93d385b9340275`. Xcode 27.0 (`27A266a`), app/widget `1.0.0 (278)`. Earlier Final278 Unit/Smoke/Release/captures are the baseline, not verification of this rebuild.
- Completion heartbeat `check-haiity-redesign-completion` updated and ACTIVE every 30 minutes in this chat. No duplicate automation created.
- Main has integrated Today, collection, live-ID active/archived details, shared action controls, root/settings routing, native creation, durable feedback and stale-action/late-history guards. The app and widget compile natively; full final verification is unfinished.
- Bounded workers (all dispatched with `sub2api/gpt-6.1-sol`): creator `01a12784-23a1-7ac1-ae1c-f215edf553f7`; collection/compact rows `01a12784-2451-7412-9566-c8b35802c575`; Progress then obsolete-test migration `01a12784-240c-75a1-b42d-6e55029d08b0`. Read their live state before resuming; never duplicate running work.
- Original implementation/test migrations are integrated. Latest actual rollout `turn_context.model` was reverified for all three: `sub2api/gpt-6.1-sol`. All three bounded workers completed and are now closed; their patches are preserved. Main owns integration and all serialized Xcode checks.
- Catalog is frozen: 15 new entries, 255 translated values, all 17 locales, plus 80 missing locale units in five reused critical keys. Prior values and metadata are preserved. Subtracting only those 80 reused-key additions gives the preservation hash `68940ef0a8ae218f4b69752a8cd4cf8da21a28c429d18668b87c3efda0ebe84e`. Existing catalog raw baseline is `a30eb238beeaa7b11de232b96ffc307a51194d15c223c63489ea47aa3b095871`.
- Evidence folder: `/Users/enrico/Documents/haiity-verification/ui-rebuild-20261010`. `FocusedUnit.xcresult`: 104/105 passed; the remaining fixture reused a reserved Yes/No log before converting to quantity, now corrected. `UnitAttempt1.xcresult`: 2,174 tests, 20 failed assertions in obsolete source contracts; the new Today tests passed. This is not a green Unit gate.
- `FocusedUI1.xcresult`: 9/10 passed, covering Today stable check/undo, rejected save, four styles/AX5 RTL, settings from all roots, reminder defaults, details/history and weekly summary. The successful sentence flow closed both views; its final visible-item assertion incorrectly queried a StaticText instead of the reminder's named button. That test query is corrected but not yet reverified.
- Real captures exported to `Visuals1`; inspected ordinary Quiet/Studio and AX5 Arabic photo. Removed redundant Today headings/summary labeling after visual review. Baseline collection capture is at `Baseline/collection.png`; historical Final278 captures match the inspected baseline fingerprint.
- Native project regeneration uses the existing pinned XcodeGen 2.46.0 at `.worktrees/2026-10-09-redesign/.ci-tools/xcodegen` through `XCODEGEN_BIN`; the generator is absent from PATH. All new files are registered by regeneration, not manual pbxproj edits.
- `SmokeAttempt1.xcresult` sealed at 50/64 passed. Subsequent focused native checks verified creator cancellation/save, styles, Search Undo, date saving, AX5 Progress and multiple-notification editing. `UnitAttempt4.xcresult` sealed at 2,189 tests with five failure records, covering deletion-marker regression and two native history tests; neither complete suite is green yet.
- `FocusedUI3.xcresult` sealed at 2/4 passed. `FocusedUI4.xcresult` sealed at 1/2 passed: flexible periods, negative answer and Undo now pass after restricting the disclosure identifier to its label. Date contrast passed, then the audit found invisible swipe-underlay buttons still exposed to accessibility; hiding moved to the actual shared buttons and a native assertion now checks their absence while closed. The audit remains unfiltered. Xcode's failure sysdiagnose timed out after 600 seconds; subsequent commands disable verbose diagnostic collection, retaining normal failure screenshots/results.
- Review found two material gaps: multi-date history writes/Undo persisted day-by-day, and new routes did not await the history sheet's actual dismissal. Root write/restore/global Undo now call the existing store's atomic batch extension. History uses the existing presentation bookkeeping and `onDismiss`; the reviewer found no material issue in that correction. New unit and native route coverage is added.
- Latest: `FocusedUnit2.xcresult` sealed at 135/137 passed, including all new atomic persistence, tombstone, session and history-route checks. The two remaining failures showed that direct Unit-host traversal exposes no SwiftUI AX elements despite a correctly sized window. Those tests now exercise the real atomic setter's prewrite receipt; native history rejection/disabled Undo is covered by an added UI test. The setter returns ordinary tuples so the widget does not acquire the app-only Undo UI model.
- `FocusedUI5`/`6` stopped at an invalid structural assertion that hidden controls must be absent from XCTest's entire view query. The original unfiltered audit remains. Explicit accessibility child containment now ignores the closed underlay. An attempted UI-runner `UIApplication.open` required a system consent alert; the owned hung run was interrupted and preserved. The official XCTest URL API is restored, with a before/after process-ID assertion to prove in-process history dismissal. `FocusedUI8` failed compilation in the intermediate test harness and is not evidence.
- `FocusedUI9` verified rejected history save/disabled Undo. Its process-ID assertion proved that XCTest's `open(URL)` relaunches the app and cannot prove live dismissal. The public UI-runner URL API then failed with `FBSOpenApplicationErrorDomain Code=3`, `Request is not trusted`. That concrete OS trust gate is preserved in Device, separate from the self-contained simulator Smoke plan; no signing/security bypass or phone installation was attempted. Current Smoke plan has 68 selectors. The already-reported ego blocker remains unchanged.
- The audit now collects all failures in a run, with no blanket exclusions. `FocusedUI12` exposed closed swipe underlays, long-name truncation, graph captions and native scroll-edge issues. Source fixes retain permanent visual layers while supplying explicit accessible representations, allow compact names to wrap, strengthen secondary text on the ordinary canvas/use opaque primary text on custom backgrounds, and improve visible Edit sizing. History headings now use the unambiguous existing `Historie` key. The single URL handler now wraps the sheet modifiers as well as root content.
- The closed action underlays and decorative month labels now supply explicit accessible representations; actual visible actions retain their layout and callbacks. Compact long names wrap. The scoped audit checks content in the unobscured viewport and scrolls the lower details into view; it handles only known native-bar title metrics and the native resolved label's heuristic separately. `FocusedUI17` proves that the real disclosure grows and remains tappable at AX5.
- `FocusedUI16` exposed a genuine 100% CPU scroll/layout loop at AX5. Its screenshot and 3-second process sample are preserved. The sample is dominated by SwiftUI `LazySubviewPlacements`; replacing Today’s compact outer lazy stack with the existing native `VStack` solved the scenario in 31.558 seconds. No graph-heavy collection layout was changed.
- Frozen working-tree source fingerprint: `3658dde472f405c7a75a00070cc40f35688f950eb7f3d37f6893f3ad2c42e805`, base HEAD still `19270646a142ba88c3b94a6094137738eea7144b`, app/widget still `1.0.0 (278)`. This is a dirty working-tree candidate, not a new committed/distribution revision.
- Final `Final/Unit2.xcresult` sealed and passed all 2,203 tests, zero failures/skips. Current serialized check is the full 69-test `Final/Smoke.xcresult` / `Final/Smoke.log`; recheck its live process/result before starting another build. All workers are closed. Unsigned Release, final captures and comparable performance remain pending. No new allocation, upload, tester assignment or installed TestFlight evidence is claimed.
- Simulator target: iOS 26.5, hAiity Redesign QA `43B7F59D-8E63-4C28-9099-9DBABE305363`, booted. Another project's existing simulator is also booted; do not create/boot more or interfere with it. SimSlim is absent; no slimming/reset performed.
- Next: inspect the sealed final Smoke/captures, fix only concrete failures if any, then complete unsigned Release/resource checks, final visual review and comparable performance on the frozen fingerprint. Physical/iOS27/services and trusted live URL delivery, uploads, phone installation and installed TestFlight gates remain distinct and are not newly authorized. ego lite and its prescribed browser skill are still absent; the already-reported web blocker is unchanged and no other browser is permitted.
- Resume at 20:07 UTC verified no active Xcode job or surviving worker. The sealed `Final/Smoke.xcresult` passed 68/69; its sole failure tapped the collapsed Habits tab under the native Search keyboard (`Computed hit point {-1, -1}`). Native Close correctly cancels the query. The corrected test submits Search, waits for the visible Habits target, sorts and returns with its query intact. `Final/SearchSorting2.xcresult` passed in 23.209 seconds; no app-source change was needed.
- All three native test plans now request screenshots, not automatic screen recordings. The focused run's attachments confirm this. Existing recovery artifacts, including old XCTest recordings, remain preserved; no new recording/device/reset/distribution action was authorized or performed.
- Current frozen fingerprint: `adfc569b79a94d3939c1e49422af79fcf21a969fdcf1ead94d9e00f68af8632d`. `Final/Unit3.xcresult` passed 2,203/2,203 with zero failures/skips. `Final/Release.xcresult` is a successful unsigned generic-iOS Release build; built metadata/resource validation is next. `Final/Performance.xcresult` / `Performance.log` is the active serialized three-case performance run (exec session `24673`). The final complete 69-case Smoke rerun and source-bound evidence record remain pending.
- Exported 114 deliberate app screenshots from the original final Smoke to `Final/AppCaptures`. Reviewed representative Quiet/Studio Today, Studio collection, details/full history, native creator, keyboard-open sentence child, Settings, Studio Progress, AX5 Arabic photo Today/Progress and dark photo sorting. These captures establish simulator layout, not real-device behavior, native widget hosting or authenticated service success.
- `Final/ReleaseResources.json` passed direct built-bundle checks: app/widget both `1.0.0 (278)`, iPhoneOS 27.0 SDK, iOS 18 minimum, all 17 locales with the 15 new translated labels, privacy declarations, app assets and no shipped StoreKit fixture. All prior catalog data is unchanged, with exactly 80 missing locale units added to reused keys. The widget uses native/code-drawn content and has no asset catalog.
- `Final/Performance.xcresult` sealed at 3/3, zero failures/skips. Same iPhone 17 Pro QA simulator, iOS 26.5, Xcode 27.0 and Debug fixtures as `redesign-20261009/Final278/Performance.xcresult`: five responsive-launch samples, median 1.314137 s versus 1.729610 s; three full-card scroll samples, median 2.312113 s versus 2.316680 s; three native-sort scroll samples, median 2.300551 s versus 2.300159 s. Ordinary desktop background work was present; no competing build was running. This does not establish real-data phone launch performance.
- Active final gate: complete 69-selector `Final/Smoke2.xcresult` / `Smoke2.log`, main-owned exec session `13401`, initial xcodebuild PID `85594`, on fingerprint `adfc569b79a94d3939c1e49422af79fcf21a969fdcf1ead94d9e00f68af8632d`. Unit, Release/resource and performance gates have evidence; do not repeat them unless source/toolchain changes. After Smoke seals, export its final screenshots, record/check `tools/verification.rb` evidence and finish the report/heartbeat decision.
- The 20:40 heartbeat rechecked live state: the old command host/session had disappeared, xcodebuild was gone and `Smoke2` stopped after eight passing cases. Its missing result `Info.plist` confirms it is unsealed and cannot be a pass. A normal detached shell was also cleaned up by the command host. The temporary launchd job was denied Documents access and removed; its error artifacts are preserved. No privacy setting was changed.
- Current active final gate is **`Final/Smoke5.xcresult` / `Smoke5.log`** on the unchanged frozen fingerprint. A normal authorized subprocess now owns its own process group: runner PID/PGID `89073`, parent PID 1; xcodebuild PID `89074`. `Final/Smoke5.runner.pid` and `Final/Smoke5.exit` are its live/terminal receipts. `Final/run_smoke.sh` is outside source and only runs this one serialized native test command. Do not rerun while either the runner or xcodebuild is active. After it seals, inspect all 69 results, export screenshots, record/check final source-bound evidence and update the completion/heartbeat state. All other passed gates remain reusable.
- Subsequent visual review found a genuine history contrast gap: filled light dates had white text (default level 1 is 1.4369:1 against white), and a new native audit exposed seven weak weekday labels. `Smoke5` was intentionally interrupted before changing app source; its interruption artifacts are preserved. It is not a final pass.
- `Theme.levelText` now chooses opaque black/white with the existing WCAG calculation; `Theme.level` and the new text role share the exact palette lookup. History selection retains its two outlines without a tint that could reduce text contrast. Quantity/answer marks are at least 11 pt, weekday captions use the stronger existing text role, and selection/action controls use explicit surfaces and stronger type/ink. A new independent contrast test covers all built-in palettes plus extreme custom colors in both schemes and all logged/declined levels. Smoke now has 70 selectors.
- Ordinary full-history native contrast audit passes. Selected history still produces two findings, `history-select-all` (Contrast nearly passed) and `backfill-status` (Contrast failed), even with explicit strong text/surfaces. Separate fresh launches and text-node refresh did not remove them; exact raw reports and element screenshots are preserved under `Final/HistoryContrast*`. Do not suppress an entire category or declare them resolved. A bounded read-only reviewer, Socrates `01a12cf1-28db-73a1-a249-8a0d60cd20d3`, was dispatched with the exact `sub2api/gpt-6.1-sol` override to diagnose these findings; recheck its live status before resuming it.
- Current source fingerprint is `bfe581e679f6fd4aadd17cf448f9d769e3515ca6fe0aee3dae77278ae688894d`. Current serialized native check is `Final/Unit4.xcresult` / `Unit4.log`, launched through the one-shot `Final/run_xcode.sh` process-group runner, PID `2603`. Its `.runner.pid` and `.exit` receipts are durable across chat interruption. The earlier Unit3/Release/performance results describe the pre-history-fix candidate and require matching final checks for this changed source. After resolving the selected-history findings, freeze source and complete Unit/70-case Smoke/unsigned Release/resources/performance plus inspected captures and the evidence receipt.
- Latest human tooling preference replaces every earlier ego-browser requirement: Chrome Use for websites, Computer Use for desktop UI, Chrome as browser. Both shared AGENTS files were reread. The existing heartbeat prompt was updated in place, remains ACTIVE every 30 minutes, and preserves release/device boundaries. Browser unavailability is no longer inferred from ego lite being absent; website verification has not been performed for this candidate. Native Apple checks take precedence over the newly installed web-oriented design recipes; no web library/template or lintapple native audit was added.
- The read-only reviewer completed, its actual rollout model was verified as `sub2api/gpt-6.1-sol`, and it is closed. Its minimal diagnostic was executed: a UIKit UILabel with identical status text/caption font/black-white colors passes the unfiltered audit while the SwiftUI Text node fails. A matching UIKit UIButton then removed the remaining select-all finding. `Final/HistoryContrastUIKitBothProbe.xcresult` passed the complete unfiltered ordinary/selected audit. The temporary UIKit types were removed; no production bridge or extra component was retained.
- Current history coverage uses a precisely documented exception for only `history-select-all` and `backfill-status`, only for `.contrast`, only on the iOS 26.5 simulator, backed by that controlled UIKit comparison. All other history contrast findings remain unsuppressed; the real weekday/date contrast fixes and the independent palette-text calculation remain. `Final/HistoryContrastFinal.xcresult` passed ordinary and selected history in 21.755 seconds. This is a scoped simulator result, not universal accessibility or real VoiceOver evidence.
- Final frozen fingerprint is **`2c8fc2543c316018b2abba294836db6c492bdafd19f295c50fd0d88cf9578e30`**. `Final/Unit4.xcresult` ran 2,204 tests and had only one obsolete source assertion requiring the removed selection tint; that assertion was removed while its gesture and non-crossfade contracts remain. `Final/Unit5.xcresult` / `Unit5.log` is the active serialized gate (runner PID `7215`). After it seals, finish matching unsigned Release/resources, three-case performance, complete 70-case Smoke and final captures/evidence on this fingerprint. Current source contains no UIKit probe types or worker edits. Do not restart an active process-group runner; read its `.runner.pid` and `.exit` receipts.
- `Final/Unit5.xcresult` sealed and passed all 2,204 tests with zero failures/skips. `Final/Release3.xcresult` is a successful unsigned Release on the frozen source; `Final/Release3Resources.json` passed the built app/widget version, locale, preserved catalog, privacy/resource checks. `Final/Performance2.xcresult` sealed at 3/3 with zero failures/skips: five responsive-launch samples, median 1.321309 s; three collection scroll samples, median 2.300207 s; three native-sort scroll samples, median 2.300514 s. Baseline capture policy differs; these are bounded simulator observations, not a causal or phone speedup claim.
- `Final/Smoke6.xcresult` sealed: 69/70 passed, one failure, zero skips, exit 65. The sole failure is `SpeakToCreateDockUITests/testDeniedDictationKeepsTypedTextAndEditingAvailable()`. Exact captures in `Final/Smoke6Dictation` prove that automatic preview scrolling moved the active AX5 input/microphone under the navigation bar, before dictation began. `Final/DictationScrollRed.xcresult` reproduces this with the strengthened existing test, without a rescue swipe.
- An initial focused-input guard did not resolve the old offset retained after removing the empty prompt. `Final/DictationScrollGreen.xcresult` sealed at 8/10, with that same reachability failure and a 44 pt RTL frame measured as `43.99999999999997`. The final one-line correction anchors the existing scroll helper at the top during typing and the bottom for preview; the RTL test uses the existing 0.001 pt geometry tolerance. `Final/DictationScrollGreen2.xcresult` passed both affected cases, zero failures/skips. Inspected `Final/DictationScrollGreen2Visuals` confirms that the input and microphone stay visible with the AX5 keyboard open and after denial; typing remains editable.
- **Frozen candidate fingerprint: `ddc3ef7c35053d3d1baaadbbfe329faf65790f42f92dff2ed3ec542c4ae6f2af`. Active serialized queue: `Final/run_final_gates.sh`, runner PID/PGID `32647`, parent 1.** `Final/FinalGates.runner.pid`, `Final/FinalGates.exit` and `Final/FinalGates.log` are its live/terminal receipts. It runs only Unit6, unsigned Release4/resources, Performance3 and complete 70-case Smoke7, then records/checks `Final/evidence.json`; it aborts on failure or a changed fingerprint. `Final/CandidateIdentity.json` records base HEAD `19270646a142ba88c3b94a6094137738eea7144b`, Xcode 27.0 (`27A266a`), SDK 27.0, XcodeGen 2.46.0 and unchanged app/widget `1.0.0 (278)`. The pinned generator was rerun successfully before freezing. Recheck the queue and each child `.runner.pid` / `.exit` before starting anything; do not duplicate them. All original workers are absent/closed. After the queue seals, diagnose a concrete failure or inspect matching Smoke7 captures and update the final report/heartbeat decision. Unit5/Release3/Performance2 remain preserved historical candidate results. No new push/upload/device installation/recording/reset is authorized.
- `Final/Unit6.xcresult` sealed: 2,204 passed, zero failures/skips. `Final/Release4.xcresult` succeeded unsigned for generic iOS, and `Final/Release4Resources.json` passed app/widget `1.0.0 (278)`, all 17 built locales, 15 new keys/255 translations, exactly 80 additions to reused keys with all prior catalog data preserved, privacy declarations and packaged assets. The queue continues with Performance3, then Smoke7. A bounded read-only final correctness reviewer, Pasteur `01a12db7-9c79-78e3-a35f-250ef87d2f30`, is active; actual rollout `turn_context.model` verified as `sub2api/gpt-6.1-sol`, medium effort. Its scope is creation lifecycle, live-ID/navigation and atomic history writes/Undo. It may neither edit source nor run native checks; main retains frozen-source/build ownership.
- Pasteur completed and is closed. It found one concrete missing native dismissal path: swiping Settings closed from Notifications left `moreSheetPath` intact. Main preserved the first queue and interrupted its owned Smoke7 before editing; Unit6/Release4/resources/Performance3 passed for the preceding `ddc3ef...` candidate, while Smoke7/FinalGates terminated at exit 75 and are not final passes. The initial queue script is retained as `Final/run_final_gates_initial.sh`. `Final/SettingsDismissRed2.xcresult` proves actual native dismissal succeeded and reopening incorrectly returned to Notifications. Main moved the existing path cleanup to `deliverPendingMoreDismissalRoute`, after its guard against a newer sheet. The existing 70-selector Settings case now includes a full native dismissal gesture and reopening; no new abstraction/test selector was added. `Final/SettingsDismissGreen.xcresult` passed that all-root/Back/close case and Calendar/Notifications recovery, zero failures/skips. Exact screenshots are in `Final/SettingsDismissGreenVisuals`.
- **Current frozen source: `b2397935093d745a45dc5988f96d8fe9899d60ba0254bdb8c724e0dc25902b64`. Active serialized queue: `Final/run_final_gates.sh`, runner PID/PGID `39345`, parent 1; live receipts `Final/FinalGates2.runner.pid`, `Final/FinalGates2.exit` and `Final/FinalGates2.log`.** It runs Unit7, unsigned Release5/resources, Performance4, full 70-case Smoke8, then `Final/evidence2.json` record/check. `Final/CandidateIdentity2.json` and `CandidateStatus2.txt` bind the exact dirty source/base HEAD/toolchain/version. All workers are closed. Recheck this queue/child receipts before starting any native job. After it seals, diagnose a concrete failure or export/inspect matching Smoke8 captures, finish the report and handle only this completion heartbeat. Earlier results remain preserved; no physical/service/distribution gate is inferred from them.
- Matching-source gates now passed: `Final/Unit7.xcresult`, 2,204/2,204 with zero failures/skips; `Final/Release5.xcresult`, unsigned generic-iOS Release; `Final/Release5Resources.json`, app/widget/version/locales/catalog/privacy/assets; `Final/Performance4.xcresult`, 3/3 with zero failures/skips. Performance medians on the same iPhone 17 Pro/iOS 26.5 QA device: responsive first frame 1.304670 s (five samples), collection scroll 2.300282 s (three), native sorting scroll 2.300469 s (three). Baseline medians remain 1.729610 / 2.316680 / 2.300159 s; baseline capture policy differs, so these are bounded simulator observations, not causal or phone-performance claims. Unit7 also records 23 direct-view environment warnings in helper/source checks; native layout/accessibility evidence comes from the actual UI runs, not those reflected default environments.
- **Current child: complete `Final/Smoke8.xcresult` / `Smoke8.log`, runner PID `39999`, owned by queue PGID `39345`.** Read `Smoke8.exit` and `FinalGates2.exit` before acting; do not repeat the matching passed gates while source/toolchain is unchanged. Main inspected `SettingsDismissGreenVisuals/rebuild-settings-after-interactive-dismiss` and verified that the actual root hub/close control replaced the stale Notifications child. Only iOS 26.5 runtime (`23F77`) is installed; older compatibility/iOS 27 execution and physical/native-service gates remain explicitly open. After Smoke8 seals, inspect its captures and the source-bound evidence receipt, then finish this report/heartbeat decision.

### Task execution status

The original task checklists below retain the accepted requirements. This table and the exact evidence above are the current execution record; an external gate is not a local pass.

| Task | Current state | Evidence / remaining boundary |
| --- | --- | --- |
| 0: baseline | Complete | Protected source/version/fixtures, isolated checkout and previous Final278 baseline recorded |
| 1: compositions | Complete locally | Native app captures, four styles, AX5/RTL/photo and component-width rendering checks |
| 2: shared actions/details | Complete locally | Live UUID actions, exact batch persistence/Undo, detail/history/edit and rejected-write Unit/UI coverage |
| 3: Today | Complete locally | Classification, stable completion/Undo, flexible/negative/reminder states and AX5 layout-loop regression |
| 4: collection/sorting | Complete locally | Width contracts, fixed GitHub identity, native drag/reload and guarded order persistence |
| 5: root/settings/Search | Complete locally | All root entries and retained Search query verified; trusted in-process URL delivery remains Device-only |
| 6: Progress | Complete locally | Existing counts/order/empty choices, weekly hierarchy and AX5 RTL native captures/tests |
| 7: creator | Complete locally | Hidden-field retention, cancellation, date/notification handling and failed-save retry covered; focused AX5 typing/denial and RTL geometry now pass with inspected captures |
| 8: secondary pages | Complete locally | Direct settings/navigation without setup writes, account/data/appearance contracts; authenticated recovery and real photo selection remain external |
| 9: extensions/launch | Local gates complete | Widget family/style/intent/timer rendering tests and launch comparison; actual Home/Lock Screen hosting and native services require a candidate device |
| 10: final evidence | Complete locally | Matching Unit 2,204/2,204, Smoke 70/70, unsigned Release/resources, performance, inspected final captures and source-bound receipt; external gates recorded above |

## 1. The design decision

The main problem is how much work the current Habits page is asked to do. It is a daily checklist, a history browser, a collection editor, a reminder list, and a GitHub display. A person opening it to complete three items must scan through content designed for reflection.

The recent changes corrected graph sizing, sorting surfaces and settings destinations. Keep those fixes. This rebuild changes the information architecture and the screen compositions around them.

| Approach | Result | Decision |
| --- | --- | --- |
| Keep the current screens and change their styling | Familiar structure with the same competing jobs and tall daily feed | Too limited for this request |
| Rebuild the UI around Today, Habits and Progress | Clearly different daily experience while retaining the app's tested behavior | Recommended |
| Rewrite UI, storage, scheduling and sync together | Larger regression surface and unnecessary data migration | Excluded from this UI scope |

The visual direction is a **calm contribution journal**. Daily work is concise and immediately actionable. History gets a dedicated place. The grid remains the app's recognizable visual element.

## 2. Scope and constraints

### 2.1 Included

- The root tab composition and initial screen.
- A new Today screen for current work and flexible goals.
- A rebuilt Habits collection with GitHub first and correctly measured calendars.
- A coherent detail destination for habits and reminders.
- A recomposed Progress screen using existing statistics.
- Creation, editing, sentence input and dictation presentation.
- Search, sorting, archive and settings presentation.
- Account, appearance, integrations, data, Pro and feedback pages.
- Empty, loading, error, permission, offline and purchase states.
- Appearance, accessibility, localization and performance parity.
- Presentation consistency of widgets and Live Activities where the new app roles affect them.
- Removal of superseded UI branches after their replacements are verified.

### 2.2 Retained contracts

| Contract | Required treatment |
| --- | --- |
| Split Search | Keep the separated native Search affordance on supported iOS versions and the existing compatibility search path on older versions |
| GitHub first | First content under the Habits heading; not a sticky overlay and not included in Today totals or item order |
| Four design styles | Keep Original, Quiet, Focus and Studio raw values and saved selections |
| Custom appearance | Keep photo crop/zoom, gradients, colors, materials, palettes, compact mode, performance mode and icon choices |
| Global timezone | A full-row native selector, not a separate Standard Time Zone page |
| Item timezone | Keep inherited, device and explicit per-item choices distinct |
| Multiple notifications | Add/remove times for each item; preserve disabled and inherited values |
| Automatic resolution | Existing end-of-day behavior; never reinterpret the appointment clock as the automatic completion time |
| Habits versus reminders | Explicit item type; recurrence selection must not silently change it |
| Quantity and Yes/No | Preserve exact values, targets, selected answers and negative-answer semantics |
| Sorting | Native handles, stable IDs, full-list permutation, filtered-scope validation and stale-save rejection |
| History | Same date bounds, logs, negative levels, calendars and full-history writing rules |
| Apple identifiers | Developer-only visibility; user-facing pages show meaningful connection states |
| Accounts | Optional Apple connection; GitHub sign-in/logout stays on its secondary page |
| Settings navigation | Opening notification/calendar configuration must not replay setup or enable summaries |
| Data safety | Existing coordinated writes and failed-save recovery remain authoritative |
| Pro | Existing limits, restore, entitlement and account-boundary behavior remain authoritative |

### 2.3 Implementation boundaries

- iPhone, portrait, iOS 18 or later; retain all 17 UI localizations.
- Native iOS 26/27 presentation and older-system compatibility must be verified separately.
- Do not replace `HabitStore`, `GoalEngine`, `ReminderOccurrenceEngine`, `StatsEngine`, CloudKit merge rules or notification scheduling with UI-local copies.
- Do not add a Manager, Service, Factory, Protocol, Adapter, Coordinator, Provider or Registry for this rebuild.
- Do not create a second store instance when opening a screen.
- Add no new appearance modes, rewards, social feed, scoring system, model feature, database or persistence format.
- Preserve existing dirty/untracked files and recovery metadata throughout execution.
- Use Chrome Use for websites/browser interactions and Computer Use for desktop UI, with Chrome as the browser, following the latest human preference and supported tool APIs.
- Only `sub2api/gpt-6.1-sol` may be used for bounded workers. The main assistant owns design decisions, integration and final claims.
- Serialize Xcode work. Reuse an appropriate existing simulator and follow the user's SimSlim policy.
- This planning request does not trigger a build, commit, upload, phone installation or data reset.

## 3. Product structure

### 3.1 Three content tabs

| Tab | German label | Primary job | Content it owns |
| --- | --- | --- | --- |
| Today | Heute | Complete current work | Scheduled habits, today's reminders, overdue reminders, flexible goals and completed/answered work |
| Habits | Habits | Browse and manage the collection | All active items, full-width recent calendars, filters, manual order and GitHub |
| Progress | Fortschritt | Understand the existing statistics | Weekly result, daily rates, selected metrics, aggregate rhythm and individual habit progress |

Today becomes the initial screen on a normal launch. An explicit deep link continues to open its requested destination.

Settings is available through a recognizable header button on each content tab. Search stays visually separated from the three-tab group. Add is a toolbar action, not a fourth content tab.

The new hierarchy is identical across the four design styles. Their typography, spacing and surfaces vary; navigation and action meanings do not.

### 3.2 Navigation and presentation

```text
Application
  Today / Habits / Progress        Separated Search
       |
       +-- Item details -- Edit
       |       |
       |       +-- Full history for a habit
       |       +-- Reminder schedule/occurrence details
       |
       +-- Add -- New habit / New reminder / Sentence creation
       |
       +-- Settings
               Appearance
               Notifications
               Calendar & Reminders
               Behavior
               Personalization / Apple
               GitHub
               Import & Export
               Archive
               Pro
               About / Privacy / Feedback
```

Use pushes for browsing from a collection to an item's details and for moving between settings pages. Use sheets for creation, editing, purchase, system pickers and full-history editing. Use confirmation dialogs for destructive or early-completion decisions.

There is one settings navigation stack, not a new independent sheet for every row. Back returns to the settings hub at its previous scroll position. Closing settings returns to the originating tab at its previous scroll position.

Do not replace the existing presentation generation/dismissal bookkeeping. The new shell must still dismiss a stale editor, sentence flow or paywall before applying a newer external route.

### 3.3 Legacy URL compatibility

| Existing URL | New visible result |
| --- | --- |
| `haiity://habits` | Habits collection |
| `haiity://habits?habit=<UUID>` | The requested item's details in Habits, resolving the ID from the live store |
| `haiity://stats` | Progress |
| `haiity://more` | Settings hub |
| `haiity://sync` | Settings hub with its current integration/status entry reachable |
| `haiity://archive` | Archive destination, with a way back to settings |
| `haiity://search` | Search with a usable native field |
| `haiity://new` | New habit creator, retaining the current creation gate |
| `haiity://cleanup` | Existing explicitly requested native cleanup flow |

Do not change widget/intent URLs just because visible tab labels change. Preserve the accepted URL scheme and host whitelist. A stale or deleted item link shows a clear unavailable state; it must not create a replacement item.

The implementation adds `AppTab.today` and a real settings-root destination. Legacy `.more` remains interpretable, but is not selected as a tab that no longer exists. Keep `.stats` as the internal route identity even though its visible title becomes Progress.

## 4. Visual language

### 4.1 Canvas, surfaces and edges

- The existing `AppearanceBackground` owns the canvas once.
- Use a quiet neutral default canvas with readable primary text and restrained supporting text.
- Keep the current 16 pt page gutter and 760 pt readable-content maximum.
- Align headings, row identities, graph bands and action footers to actual content edges.
- Use one surface for a meaningful group. Do not put a card around every caption, value or row action.
- Quiet can remain flat on its ordinary canvas. Photos, gradients, custom colors and accessibility settings retain the shared readability fallback.
- Use native glass for navigation and temporary functional controls. Reuse the saved material path for existing content customization; do not add extra blur or a private material family.
- Keep destructive actions visually and semantically distinct.

### 4.2 Typography

| Role | Proposed default | Behavior |
| --- | --- | --- |
| Root heading | `.title2` with the current style's appropriate weight/design | Compact heading, grows for Dynamic Type; no large reserved empty hero block |
| Secondary page title | Native inline navigation title | Avoid a second oversized title immediately below it |
| Section label | Existing `sectionTitleFont` | Clear grouping, without uppercase/tracking ornament |
| Item name | Existing `rowTitleFont`, or body semibold for its primary role | Two lines at ordinary sizes; unrestricted useful wrapping at accessibility sizes |
| Schedule/status | `.subheadline` for important state | Must remain readable on photos and materials |
| Secondary metadata | `.caption` where genuinely secondary | Never the only indication of completion, decline or a failure |
| Numeric progress | System design with monospaced digits | Preserve legibility; no competing numeral font families |

Keep Studio's serif heading character, Focus's closer spacing, Quiet's restraint and Original's familiar surface grouping. Do not hard-code a different font stack inside each new screen.

### 4.3 Spacing and density

Reuse `Theme` and `AppDesignStyle` roles before adding values. The starting layout targets are:

| Element | Target at ordinary text size |
| --- | --- |
| Root title region | Approximately 44-56 pt of content, plus safe-area behavior |
| Today row | Usually 64-88 pt; grows for names, metadata and accessibility |
| Direct action target | At least 44 x 44 pt |
| Space between meaningful sections | Current style's section gap; no additional repeated hero spacing |
| Name-to-status spacing | Current style's row gap |
| Graph | Seven square-cell rows, fitted to measured inner width |

Aim for four to six ordinary Today entries visible on a typical phone with short/two-line names. This is a design target, not a fixed row count or a reason to shrink text.

### 4.4 Color and symbols

- Primary text uses semantic roles and has sufficient contrast against its actual surface.
- Habit colors primarily identify graph data and selected habit states.
- Use `Theme.accentText` for text/symbol accents and `Theme.accentFill` for filled controls requiring white symbols.
- Negative answers keep their existing palette mapping and an explicit selected No state.
- Completion, decline, an error and selection must be distinguishable without color.
- Use one SF Symbols vocabulary and the shared icon slot.
- Decorative emoji/icons do not become separate VoiceOver stops.
- Do not draw a white outline around every graph tile.

### 4.5 Motion

| Trigger | Feedback |
| --- | --- |
| Successful check-off | Immediate state change, brief check/tile response and existing haptic semantics |
| Quantity increment | Immediate number update and matching current-day grid update |
| Yes/No answer | Selected-state change with explicit answer identity |
| Undo | Restore exact prior state immediately; animate only the small changed element |
| Swipe reveal | Tracks the finger and returns smoothly to its resting position |
| Swipe cancel | Returns to the original state and writes nothing |
| Native reorder | Native lift, slot changes, auto-scroll and drop |
| Push/sheet | Native transition reflecting the navigation hierarchy |
| Loading | Stable skeleton; no spinner in every item |

Custom feedback should generally finish within about 150-250 ms. This is an implementation target, not a delay before an action can be used. Avoid page-wide implicit animation on every store update.

Reduce Motion keeps immediate state feedback and uses restrained transitions. Do not animate a completed row away while the finger, reveal session or undo action still owns it.

## 5. Today screen

### 5.1 Anatomy

```text
Today                                      Settings   Add
Saturday, 10 October

2 of 3 scheduled habits completed
[small progress indicator]

Today
Read twenty minutes                       [ Complete ]
Daily

Drink water                                [ +1  2/3 ]
Daily

Call the dentist                           [ Complete ]
Today, 10:00

Flexible goals
Run                                        [ Complete ]
2 of 3 this week

[ Completed and answered (2)                 Expand ]

Today               Habits               Progress     Search
```

The date labels this screen; it does not introduce a new arbitrary-day editor. Past-day editing remains in full history.

No full contribution calendars in the Today list. No GitHub card ahead of today's work. The grid remains available in Habits and item details.

### 5.2 Data and counts

- Scheduled habit progress comes from `ScheduledProgress.today`.
- Reminder rows and their status come from `ReminderOccurrenceEngine`.
- Flexible period goals remain separate from scheduled daily habits.
- Reminder counts are labeled as reminders, not added to the habit percentage.
- A reminder row with several open occurrences shows the engine's additional-open count; do not silently count it as several ordinary habits.
- A day with no fixed obligations uses a no-due message instead of a fabricated 100% success.
- A No answer is resolved input but does not count as successful completion.
- A quantity below target remains partial. Its numeric value must not inflate the count of completed habits.

The UI must not make `ScheduledProgress` and the differently defined Statistics measures appear interchangeable. Keep their explanations accurate.

### 5.3 Inclusion rules

| Item | Today treatment |
| --- | --- |
| Fixed habit scheduled on its local current day | Show in Today |
| Fixed habit on a rest day | Available in Habits/details; do not invent an obligation |
| Reminder scheduled today, before its clock time | Show with a future-time state; early completion retains confirmation |
| Reminder currently due | Show with current due state |
| Older unfinished reminder | Show as overdue, according to occurrence state |
| Reminder only scheduled on a later date | Available in Habits/Search; keep out of today's due list |
| Flexible weekly/monthly/yearly habit in its active period | Show in Flexible goals with that period's existing progress |
| Future-start or ended rule | Respect existing schedule bounds |
| Archived item | Exclude from active Today; accessible through Archive |

Use existing engine results for these decisions. Do not treat a flexible quota without weekdays as an unscheduled forgotten habit.

### 5.4 Stable rows and completion grouping

The screen is for quick repeated actions, so completion must not make its position unpredictable.

At entry, show open/current work first and put already completed/answered items in the disclosure. Once the person starts interacting, preserve that visit's row order. Completing an item updates it inline; it does not immediately move into another section.

Regroup when returning to Today, explicitly refreshing, or crossing a relevant day boundary while the list is idle. Keep only temporary ID/order state for this presentation. Never persist a second habit order or copy entire habits into a new store.

Newly added items enter a sensible position according to the existing store order. External changes update visible values; removals disappear safely. An ongoing touch must not be reassigned to a different item.

The completed/answered section includes declined answers with a clear No label. It is not a claim that every item inside was successfully completed.

### 5.5 Actions

- Name opens the item's details.
- Checkbox toggles the actual current day in the item's timezone.
- Quantity increments the existing value by one; retain exact-value undo/reset semantics.
- Yes/No shows two explicit targets and the selected answer.
- Reminder completion/reversion uses the existing occurrence path, including early confirmation.
- A successful durable change receives success feedback. A rejected write shows an error and does not invent a success count or actionable fake undo.
- Swipe actions remain shortcuts with existing choices and full-swipe semantics.
- Holding a row does not complete it.

For a gesture started before midnight and released after it, the action resolves the live item/day at activation. The display clock is not authorization to write yesterday's day key.

### 5.6 Today states

| State | Required UI |
| --- | --- |
| No items yet | Short explanation and Create your first habit; no permission/login wizard |
| Nothing due but collection exists | Honest free-day message, link to Habits, flexible goals if applicable |
| All scheduled work resolved | Clear state with completed/answered items still reachable |
| Loading local data | Stable light rows and usable root chrome; defer integrations/model work |
| Write failure | Inline/global error with the affected action recoverable; retain the durable state |
| Cloud unavailable | Local use continues; meaningful status belongs in settings unless action requires attention |

## 6. Habits collection

### 6.1 Anatomy

```text
Habits                                 Settings   Add

GitHub                                  Open profile
[full-width contribution calendar]

[ All | Habits | Reminders ]       Filter   Edit order

Read twenty minutes                    [ Today action ]
Every day                                      Details
[full-width contribution calendar]

Drink water                            [ +1  2/3 ]
Every day                                      Details
[full-width contribution calendar]

Call the dentist                       [ Complete ]
Tomorrow, 10:00                                Details
```

The collection supports browsing and managing everything. Reminders remain concise and have no invented streak or habit grid.

### 6.2 Habit entries

- Strong name, one useful schedule/goal line, an independent Today control, and the measured recent calendar.
- Name opens the new details destination containing history context.
- Graph opens the existing full-history editing flow.
- Move editing to the clearly labeled Edit action in details and retain an optional native quick-action menu.
- Remove the repeated two-button History/Edit footer once detail navigation and direct graph history are verified. The header's Details affordance communicates the destination.
- Never make the whole entry a completion button.
- Keep free-day check-ins available through Habits/details even though they are absent from Today obligations.
- Compact mode reduces spacing/secondary presentation; it never removes essential actions or shrinks hit areas.

This intentionally changes name-tap navigation from the existing direct history sheet to an item detail page. Direct graph/history access is retained. Treat that as a declared product change, not an accidental consequence of moving views.

### 6.3 Calendar correctness

Retain the existing shared band sizing:

```text
W = actual drawable width after insets
g = GridCell.gap, currently 3 pt
p = preferred tile side, 12 pt
N = clamp(floor((W + g) / (p + g)), 1, 53)
c = (W - (N - 1) * g) / N
painted width = N * c + (N - 1) * g = W
height = 7 * c + 6 * g
```

| Phone/container width | Drawable width after 16 pt gutters | Columns |
| ---: | ---: | ---: |
| 320 pt | 288 pt | 19 |
| 375 pt | 343 pt | 23 |
| 402 pt | 370 pt | 24 |
| 440 pt | 408 pt | 27 |

These values change if a real surface introduces further padding; measure the band itself. Do not use screen width as a substitute.

- Seven rows stay chronological left-to-right even in RTL.
- Month labels, today outline, quantity intensity and declined levels use the same snapshot as the tiles.
- Request history only when data, local day/calendar or the quantized column count changes.
- Keep the cancellable snapshot queue and bounded cache.
- Check-off/undo projects the current-day tile immediately without synchronously recalculating the whole history.
- Skeleton and populated graph have stable dimensions.
- New and sparse habits have the same band geometry; no fabricated completions before tracking.
- Context previews measure their own inner width.
- Full history retains its date navigation and writing bounds.

### 6.4 GitHub

- First content under the heading in every collection filter.
- Same readable graph pitch and content edge as habit entries.
- Keep the annual dataset and existing profile destination available.
- Preserve cached data while refreshing/offline.
- Hidden username still leaves a concise GitHub identity.
- No personal-item UUID, check-off, swipe action, manual-order slot or progress contribution.
- No GitHub injection into Today or dedicated Search.
- During sorting, replace the large graph with a compact fixed-at-top identity.

### 6.5 Filters

Type and status filters stay local to the collection/search context. Preserve the stored `habitListFilterTodayOnly` value: the former Today-only choice can appear as a Due today filter in the collection menu, with a visible active-filter indicator. Do not erase that preference just because Today now has its own tab.

Today always shows its defined daily scope independently. Visiting it must not set/reset the collection's persisted filter.

Keep a one-tap reset, an honest no-matches state, and a distinction between no collection and no matching results.

## 7. Item details and full history

### 7.1 Habit details

```text
Back                                          Edit

Read twenty minutes
Every day

Today                                     [ Complete ]

Recent history
[full-width calendar]
[ Open full history ]

Progress
Existing recent completion / streak when meaningful

Schedule
Every day; appointment time if set; timezone

Notifications
Off / inherited / explicit times, described accurately

More actions
Start session / Share / Archive / Delete
```

- Resolve a UUID against the live store instead of retaining an obsolete copied item.
- Editing an item updates this screen when the editor returns.
- Widget/Siri/iCloud changes update the same item without remounting its navigation identity.
- Today controls share the exact action implementation with Today and the collection.
- Full history opens the existing `BackfillCard` flow; it is not a second backfill engine.
- Show progress only where it has a truthful denominator/period.
- Keep optional session duration, share behavior and per-item choices accessible.
- Archive and Delete are distinct actions. Delete retains name/context and confirmation.

### 7.2 Reminder details

The same screen structure adapts to a reminder: name, explicit due/status text, completion action, schedule, notifications, calendar destination and editing.

Do not mount a habit calendar, streak, success percentage or quantity control for a reminder. Multiple outstanding occurrences use the current engine's actionable occurrence and count; this rebuild does not introduce an occurrence database or change cursor rules.

### 7.3 Missing or archived items

If an item is removed while its details are open, show that it is unavailable and offer Back/Return to Habits. Do not mutate a retained stale value.

An archived item reached from Archive is visibly archived and uses the existing restore flow. Active-only external links must follow the existing eligibility rules or show an unavailable state; do not silently unarchive.

### 7.4 Full-history interaction

Retain month navigation, visible selection, exact date labels, the current multi-day selection behavior, allowed date bounds, Yes/No/quantity meaning and exact undo.

The read-only recent graph and the history editor are different contexts: a 12 pt visual tile is not a 12 pt direct edit target. The editor retains its larger native selection controls and accessible actions.

## 8. Progress

### 8.1 Composition

```text
Progress                                      Settings

This week so far
10 of 15 completed                         67%
[seven-day strip with dates/rates]
[ How this is calculated ]

Rhythm                         visible if selected
[existing aggregate contribution period]

Your selected metrics
[existing selections in preserved order]

Your habits
Name                         existing recent completion
Name                         existing recent completion

[ Optional summary                              Expand ]
```

Use one clear weekly result. Remove the always-present duplicate large Today section; the dedicated Today screen owns that daily job. An explicitly selected Today metric remains available as a chosen metric.

There is one contextual explanation of the main weekly result. Individual rows/details provide their own relevant explanation without repeating a full-sized Details row for every number.

### 8.2 Data and saved selections

- Reuse `StatsEngine.Snapshot`, `weekCompletionSummary`, the existing daily strip and the existing per-habit calculations.
- Keep `StatsCard` raw values and `StatsCardPrefs` storage keys unchanged.
- Keep default selections `[.yearPulse, .totals]` and preserve explicit customized selections, including empty/all-five cases.
- Preserve each chosen card's existing value, order and access boundary.
- If an explicit weekly metric and the main summary show the same number, use one visible value with the additional chosen context/action. Do not erase the preference or create duplicate hero blocks.
- Preserve the aggregate rhythm's actual existing period and label it accurately. Its internal `yearPulse` identifier is not permission to relabel five months as a year.
- Do not add a Week/Month/Year selector that implies unimplemented changes to every statistic's denominator.
- A missing denominator gets a no-data/no-due state, not an invented success rate.
- Reminder/GitHub data remains excluded from habit statistics where currently excluded.
- Per-habit selection opens details; a direct History action still reaches full history.
- AI reading is optional, collapsed initially and never runs merely because the page/disclosure opened.

New analytical formulas, monthly comparison models and motivation scoring are outside this UI rebuild.

## 9. Creation, editing and sentence input

### 9.1 Entry points

Add exposes New habit, New reminder and From a sentence as clearly named choices. The direct first-habit empty-state action opens the habit creator without an extra chooser.

Keep an obvious sentence alternative inside the manual creation flow. Editing an existing item does not offer a second creator.

### 9.2 Manual creator

| Field | Initial presentation |
| --- | --- |
| Item type/name | Direct; type switch remains explicit |
| Schedule | Direct concise choice/summary |
| Habit default | Daily, preserving existing new-habit draft semantics |
| Reminder default | Once, with essential appointment date/time controls |
| Quantity target | Direct only after Quantity is explicitly selected |
| Other habit kind | Current choice available without decorative preview machinery |
| Preview | A readable sentence describing active name/schedule and distinct notification state |
| Extra settings | Collapsed initially, with a truthful summary of non-default active choices |
| Save | Clear native confirmation action; disabled for empty name/active save |

The native sheet may grow to a large detent and must use large/full-height presentation where the keyboard, accessibility text or recurrence controls require it. Do not force a complex editor into a half-screen frame.

Add an `initialItemType: HabitItemType = .habit` input to the current editor for creation entry points. It applies only when `existing == nil`; loading an existing item always restores its saved type and recurrence. Keep the global legacy `RecurrenceDraft` default unchanged, using its existing item-specific initializer for new daily habits and once reminders.

Show the preview once. Avoid a separate decorative card and a second copy of the same schedule underneath it.

### 9.3 Extra settings

Retain emoji, color, duration, calendar participation, timezone, notification mode/times, repeat-while-incomplete behavior, automatic resolution, recurrence details and existing per-item swipe overrides.

Collapsing a section changes visibility only. Loading/saving still retains legacy, unknown or hidden fields under existing contracts.

### 9.4 Notification controls

- The schedule clock and alert clocks are distinct fields and distinct preview text.
- Off hides alert-time controls while retaining their stored values.
- Nil inheritance, an explicit empty array and explicit times keep their different meanings.
- Add/remove controls have large hit areas and stable row identity.
- Sort/deduplicate/sanitize through the existing implementation; do not introduce a parallel time representation.
- Opening the editor or expanding notifications does not ask for permission.
- Permission requests occur only in the existing explicit enable/save path.
- A denied request does not destroy the editable draft or claim that alerts will fire.
- Automatic resolution still happens at end of day under existing item timezone rules.

### 9.5 Sentence and dictation flow

The sentence view has a native text field, an inline dictation control, current parsing/model state, a reviewable draft and a clear Create action.

Preserve deterministic parsing of numeric/space-separated/ISO dates and `10 Uhr`, the invalid-date save block, explicit model reading and manual correction.

The manual draft must remain mounted when the person opens its sentence alternative. Use the creator's native navigation stack for this child task. Reuse the sentence view's content and lifecycle in its existing file, with standalone and embedded presentation only where the two actual callers need them.

That requires removing a nested `NavigationStack` from the embedded content and adapting its Back/Cancel/Save callbacks. Do not simply mount the current sheet wrapper inside a second stack and assume its dismissal semantics are correct.

- Cancel/Back from the child returns to the intact manual draft, including quantity, recurrence and notification values.
- The typed name is passed into the child exactly once.
- Successful sentence creation closes the intended creation flow exactly once.
- Failed saving retains text/draft and offers retry.
- Dictation denial keeps typed input usable.
- Dictation finalization completes before saving; a late transcript cannot create or modify an item after dismissal.
- An external route cancels pending reading/dictation and dismisses the active child before changing destinations.
- Microphone/speech permission is requested only when the person taps Dictate.

Do not add a persisted draft system or a new AI feature to support this presentation change.

### 9.6 Edit and save behavior

Creation and editing use the same controls and field preservation. The existing free/Pro gate, validation, coordinated save and successful-save rescheduling remain in their current owners.

Cancel writes nothing. Failed saves leave the form editable. A successful save returns to the originating screen with the new/changed item reachable, rather than unconditionally switching every flow to Habits.

## 10. Search

- Preserve the separated Search control and native keyboard behavior.
- Search all eligible active items regardless of Today/collection status filters.
- Results are compact identities with schedule/status, without mounting a second set of full calendars.
- Result name opens item details; direct actions use the same underlying mutation paths.
- No GitHub result is injected simply because its card exists in Habits.
- Preserve typed query, cancel/clear behavior and appropriate focus while switching presentation.
- Do not rely on the Search tab button remaining in the accessibility tree after iOS replaces it with the active field.
- A no-result state shows the query and recovery; it does not change collection preferences.
- Return from details preserves the query and result scroll position.

Use stable item IDs for result identity. Query text must not become a new row identity on every character.

## 11. Sorting

Sorting belongs to collection management. Today inherits the existing manual order but does not invite a drag operation between its presentation groups.

```text
Order                                         Done
Drag to change the order.

GitHub                                 Fixed at the top

Read twenty minutes                           [handle]
Habit - Every day

Call the dentist                              [handle]
Reminder - Tomorrow, 10:00
```

- Retain `NativeHabitSortingController` and its existing native gesture behavior.
- Match the collection's identity, fonts, insets and shared surface treatment.
- No grids, check-off targets, Edit/Delete controls or active swipe buttons in sorting rows.
- GitHub is outside the movable table and has no handle or persisted order entry.
- Retain the currently supported filtered-scope permutation and generation checks.
- Do not silently expand sorting into unsupported status/type-filter combinations; disable with a clear reason and offer the supported scope.
- Each accepted move uses the existing durable save path. Done exits; it is not a new save operation and there is no misleading Cancel.
- A stale/external update rejects/reconciles instead of overwriting unseen changes.
- A style/content refresh updates hosted content without reloading the entire table during an active native move.
- Preserve scroll position and row identity on long drags and auto-scroll.
- VoiceOver Move Up/Move Down uses the same guarded move callback and announces the updated position.
- Holding/tapping a sorting row never completes or opens an item.

## 12. Settings and secondary pages

### 12.1 Hub and hierarchy

Reuse `MoreView` and its extracted page files. The user-facing destination is Settings; renaming every internal `More*` symbol adds no product value.

| Group | Destinations |
| --- | --- |
| Everyday | Notifications, Behavior |
| Appearance | Design style/appearance, existing Customize controls |
| Connections | Calendar & Reminders, GitHub, Personalization/Apple, meaningful iCloud status |
| Data & privacy | Import & Export, Archive, About/Privacy, Feedback |
| Purchase | Existing Pro entry and restore flow |

Use `AppSettingsGroup`, `AppSettingsRow`, `AppIconBadge` and the existing page/surface roles. No private row family for account, calendar or appearance pages.

### 12.2 Notifications and calendar

Direct pages show current configuration, permissions, selected destinations and recovery actions. They do not replay `ReminderSetupView`, enable daily/weekly summaries, rewrite alert clocks or start cleanup just because they opened.

Native cleanup and deletion stay explicit actions with their current ownership and confirmations. Full/denied/restricted/write-only states must be accurate. Opening iOS Settings returns without losing the app's navigation context.

The global timezone is a full-row selector. Per-item override selection remains in the item editor and explains inheritance clearly.

### 12.3 Personalization, Apple, GitHub and iCloud

- Nickname-first personalization remains available locally.
- Connection rows navigate; they do not hide independent Sign In controls inside the same hit region.
- Sign In, pending, connected, reauthentication and Sign Out states are clearly labeled on secondary pages.
- Developer identifiers remain hidden from ordinary users.
- GitHub code copying remains an explicit action; opening its page does not replace the clipboard.
- GitHub pending login has Cancel; refresh has current status and preserves cached content.
- Apple personalization/identity changes do not change raw StoreKit purchase evidence.
- iCloud status reports reality; the UI does not claim that a local save proves cross-device sync.

### 12.4 Appearance and image crop

Keep every current choice and storage format. Design styles change appearance roles on one common layout hierarchy.

The photo-selection/crop flow stays sequential: select, present the adjustment view, pan/zoom, confirm/cancel, then apply. Maintain the phone-ratio crop and bounded image data. Cancel preserves the previous background.

Test returning from the system photo picker, changing a second image, crop cancellation, large text and repeated presentation. Do not move the crop under a sheet that is still dismissing or add another image cache.

### 12.5 Data, archive, Pro and feedback

- Import & Export stays a public reachable page using the existing security-scoped importer and share/export implementation.
- Import errors remain actionable; do not label an About link as data transfer unless it opens the actual route.
- Archive keeps search/restore/delete and existing cap behavior.
- Pro clearly explains the existing offer, price and restore result; keep caller-specific dismissal/resume behavior.
- Do not consolidate paywall presenters in a way that hides deep-link or purchase continuation differences.
- About, privacy, support and feedback follow the common settings hierarchy.
- Existing shake-to-report behavior remains; a direct support/feedback entry is discoverable.

## 13. Widgets, Live Activities and launch

The recently rebuilt extension layouts are retained. This pass aligns their typography/status/action language with the app and verifies compatibility; it does not replace their timeline or intent architecture.

| Surface | Required parity |
| --- | --- |
| Home Screen list/roster | Clear identity, honest current state, independent actions and readable overflow |
| Dual/Grid | Measured graph space, full targets, no nested cards or duplicate reset controls |
| Focus | One clear primary item with quiet secondary rows |
| Lock Screen circular/rectangular/inline | Native monochrome/opacity behavior, correct zero progress and reminder occurrence state |
| Control Center | Existing kind/configuration and intent meaning |
| Session Live Activity | System timer/progress, current Finish/Cancel, private personal fields and bounded compact layout |
| Motivation Live Activity | Existing content/dismiss semantics and privacy markings |

Keep intent IDs, gallery kinds, stored configuration, root URLs, Pro filtering and refresh behavior. A root navigation link must not intercept an intent button.

Launch presents local data and the first useful screen promptly. Keep the existing splash/background handoff, signposts and deferred maintenance. No new introductory animation, forced account setup or model download before an item can be used.

## 14. Shared UI and file boundaries

The rewrite should make screen ownership clearer without building a component framework.

| File | Responsibility in the rebuild |
| --- | --- |
| `Haiity/Views/ContentView.swift` | Root state, route/presentation ownership, successful mutation/undo callbacks, lifecycle integration |
| New `Haiity/Views/TodayView.swift` | Today composition and temporary presentation ordering; a local `TodayHabitRow` can live here |
| New `Haiity/Views/HabitsView.swift` | Extracted/rebuilt collection composition, supplied filter/sorting state and row content |
| New `Haiity/Views/HabitDetailView.swift` | Actual detail screen for a habit or reminder, resolved by ID through the existing store |
| New `Haiity/Views/HabitActionControls.swift` | Checkbox/quantity/Yes-No controls shared by Today, collection and details; real three-caller reuse |
| `Haiity/Views/HabitCard.swift` | Collection calendar entry and existing graph-preview bridge |
| `Haiity/Views/ReminderRow.swift` | Reminder identity/status/actions adapted for compact and collection contexts |
| `Haiity/Views/StatsView.swift` | Progress composition and existing statistics presentation |
| `Haiity/Views/EditHabitSheet.swift` | Shared manual creation/editing controls and current save/permission contracts |
| `Haiity/Views/SpeakToCreateSheet.swift` | Reused sentence content/lifecycle plus its actual standalone/embedded presentation |
| `Haiity/Views/MoreView.swift` and `More*.swift` | Settings hub and current secondary-page responsibilities |
| `Haiity/Views/AppUIComponents.swift` | Existing genuinely shared UI components; no generic screen/row registry |
| `Haiity/Theme.swift` | Existing visual roles and appearance handling |
| `Haiity/Views/GitHubContributionGraph.swift` | Shared chart/tile renderer and band geometry |
| `Haiity/Views/HabitSortingScreen.swift` | Native reorder table and hosted rows |
| `Haiity/Models/AppNavigation.swift` | New visible Today/root-settings routing with legacy compatibility |

Keep `HabitStore.swift`, recurrence/occurrence engines, sync and entitlement ownership in place. New presentation values should live beside the view using them and remain small.

### 14.1 Proposed contracts for integration

These are proposed additive view interfaces, not existing compiled APIs. Final parameters must be kept consistent between their definitions and callers.

```swift
// Existing enum: add a real content destination.
enum AppTab: Hashable {
    case today, habits, stats, more, create, search
}

// Existing route enums: add a real root settings destination.
// MoreRoute.settings builds MoreView(screen: .main).
// AppMoreDestination.settings records that actual presented page.

// Shared controls receive display inputs and existing mutation callbacks.
struct HabitActionControls: View {
    let habit: Habit
    let calendar: Calendar
    let now: Date
    let onToggleDay: (String) -> Void
    let onIncrement: () -> Void
    let onAnswer: (Bool) -> Void
}
```

`HabitActionControls` renders from `now`, but its checkbox action resolves `DayKey.today(calendar:)` at activation. The root's quantity/answer callbacks continue to resolve their live day. It owns no store, timer, history cache or scheduling policy.

Today and the collection can receive row-building closures from the root while actions remain there. Do not move check-off logic into a new page-owned service just to reduce `ContentView`'s line count.

Detail navigation carries a UUID. The current item is resolved from `store.habits` whenever used. Required action callbacks are Details, History, Edit, the existing habit mutations, reminder completion/reversion and existing contextual operations.

The settings hub's `onOpen` callback pushes into its actual navigation stack. It must not reuse the old More-tab callback that replaces the entire settings sheet for each child page.

## 15. State, errors and correctness

| Situation | Required response |
| --- | --- |
| Coordinated write rejected | Show the existing durable state and error; retain editable draft/action recovery |
| Import invalid or inaccessible | Keep current data, explain the error, allow a different file/retry |
| Network/GitHub refresh fails | Keep cached graph and personal items usable |
| Entitlement changes | Preserve authoritative purchase behavior; access UI follows current state |
| Permission denied | Explain the affected integration and offer existing recovery; no fabricated enabled state |
| External route during a modal | Cancel stale work, dismiss in the existing order, apply only the latest route |
| Locale/timezone changes | Refresh presentation and date labels using actual item calendars |
| Midnight | Today scope and graph keys refresh without writing data |
| Reminder clock becomes due | State changes on the existing page clock; equality must not suppress a meaningful same-day occurrence change |
| App backgrounds during input/drag | Cancel pending ephemeral work safely; preserve durable data and accepted order |
| Item disappears | Details/actions cannot mutate the stale copied item |

The new pages should use the existing page clock explicitly. Compare the relevant rendered state/day in equatable views; a day-only comparison is insufficient for a reminder that becomes due at 10:00 while its date stays the same.

Do not clear unrelated delivered notifications because a background action wakes the app. Preserve the current real-open notification boundary.

## 16. Accessibility and localization

### 16.1 Accessibility requirements

- Every direct action is at least 44 x 44 pt in every style.
- Layouts grow rather than shrinking text at AX1-AX5.
- Stack identity/actions when a horizontal proposal cannot accommodate both.
- VoiceOver order is title, relevant schedule/status, then independent actions.
- A combined summary must not swallow Save, Edit, completion or disclosure controls.
- Native headings identify sections and pages.
- State is available in text/traits, not only palette intensity.
- Sorting offers named movement actions and honest positions.
- Read-only charts describe their name, period and result; editor controls retain accessible date/selection actions.
- RTL reverses text/control layout correctly while contribution chronology stays left-to-right.
- Keyboard focus survives typing, presentation and returning from a child task where appropriate.
- Native audit failures are investigated. Do not suppress an entire content class or replace a failing check with an unvalidated pixel heuristic.

### 16.2 Localization requirements

German remains the source-key convention. Translate new labels and state messages into every existing locale: `ar`, `bn`, `de`, `en`, `es`, `fr`, `hi`, `id`, `it`, `ja`, `ko`, `pt`, `ru`, `tr`, `ur`, `vi`, `zh-Hans`.

Proposed visible names include `Heute`, `Habits`, `Fortschritt`, `Einstellungen`, `Fällig heute`, `Flexible Ziele`, `Abgeschlossen`, `Details` and `Reihenfolge ändern`. Check the existing catalog before adding a key; reuse exact existing keys when their meanings match.

Keep all existing entries, metadata and placeholder types. Verify canonical preservation after subtracting only the intended additions/approved edits. Translate the new combined states rather than concatenating English word order across languages.

Formatting uses the item's effective calendar/timezone and current locale. UI translation coverage does not imply that every local model supports the same languages.

## 17. Performance and quality targets

| Area | Required behavior/evidence |
| --- | --- |
| First useful frame | Today can render from local data while native/cloud/model maintenance remains deferred |
| Today scrolling | No full-history graphs, local model loads or year calculations in ordinary rows |
| Collection/detail graphs | One existing queued/cache path; correct column key and stable skeleton |
| Tabs | Returning to a built tab keeps useful state/scroll/snapshot rather than flashing a fresh loader |
| Search typing | No rebuilding a second off-screen graph-heavy collection for each character |
| Check-off/undo | Correct value/current tile immediately; durable failure correctly represented |
| Reorder | Native interaction remains stable under a held finger and edge auto-scroll |
| Memory | Avoid retaining multiple duplicate chart arrays, store instances or optional model weights |

Measure comparable old/new runs with the same fixture, device/runtime, build configuration and settings. Keep at least five launch measurements and three repeatable scrolling measurements. A target is no more than a 10% regression on comparable stable runs; investigate high variance instead of inventing a percentage improvement.

Existing simulator measurements are useful baselines only in their recorded context. Do not use them to claim that the user's real-data splash stall has been fixed.

## 18. Implementation sequence

Each task is independently reviewable. Screen creation is justified by an actual new destination; shared extraction is justified by real duplicate callers. Main owns the shared route/mutation contracts and serialized verification.

### Task 0: Freeze behavior and record the baseline

**Read:** `docs/development.md`, the current design-system document, relevant models, route/presentation code and UI tests.

**Modify:** Existing fixture/tests only where needed to make the new acceptance scenarios reproducible.

- [ ] Inspect latest Git, active worker/build state and existing verification before doing work.
- [ ] Reuse a suitable isolated implementation checkout; preserve the user's main/dirty state.
- [ ] Record actual current source revision, toolchain, app/widget version and saved appearance fixture values.
- [ ] Capture current Today-equivalent feed, collection, Progress, creator, settings and sorting as the comparison baseline.
- [ ] Define isolated scenarios for empty, mixed, flexible, quantity, Yes/No, long history, future start, archived, duplicate names and rejected writes.
- [ ] Record the existing legacy URL, notification, purchase, crop and creation cancellation expectations.

**Exit evidence:** A reproducible baseline and exact protected-field/callback checklist. Earlier passing checks need not be repeated unless the current revision/toolchain requires it.

### Task 1: Prove the screen compositions

**Files:** `Haiity/Theme.swift`, `Haiity/Views/AppUIComponents.swift`, existing debug design fixtures and this plan/design contract.

- [ ] Build native mockups for Today, Habits and item details against isolated fixture data.
- [ ] Inspect ordinary light/dark layouts, photo/gradient appearance, 375/402/440 pt widths and narrow AX5 Arabic.
- [ ] Confirm first actionable content, distinct tap targets, named detail/history access and graph width.
- [ ] Apply root title/spacing roles in the existing Theme; do not add a separate token system.
- [ ] Record actual layout choices and remove prototype-only scaffolding before shipping.

**Exit evidence:** The three main compositions visibly satisfy the specification. Normal implementation choices do not require a new approval round; a material change to the proposed product behavior must be made explicit.

### Task 2: Share the actual habit actions and build details

**Files:** New `Haiity/Views/HabitActionControls.swift`, new `Haiity/Views/HabitDetailView.swift`, `HabitCard.swift`, `ReminderRow.swift`, existing root mutation/backfill callbacks.

**Tests:** `HaiityTests/HabitCardProductTests.swift`, `HaiityTests/BackfillTests.swift`, `HaiityTests/NotificationActionTests.swift`, `HaiityUITests/HabitCardProductUITests.swift` and existing reminder interaction tests.

- [ ] Add a focused failing behavioral check for shared checkbox/quantity/Yes-No targets and exact undo.
- [ ] Extract only the existing action UI needed by the real Today/collection/detail callers.
- [ ] Render details from a live UUID lookup and route its actions to current root callbacks.
- [ ] Add name-to-detail navigation while keeping graph-to-full-history navigation explicit.
- [ ] Verify Edit, Archive/Delete, session/share, rejected writes and an item disappearing while open.
- [ ] Keep the native preview host away from direct completion/name/edit hit regions.
- [ ] Verify AX5, each style and returned editor values before removing the repeated collection footer.

**Exit evidence:** All three contexts write through the same existing semantics; details and history are separate reachable destinations with no stale snapshot writes.

### Task 3: Build Today

**Files:** New `Haiity/Views/TodayView.swift`, `Haiity/Views/TodayProgressView.swift`, existing `HabitListFilter.swift`, `ScheduledProgress.swift`, `ReminderOccurrence.swift` and `GoalEngine.swift` as read-only semantic dependencies.

**Tests:** Add `HaiityTests/TodayViewTests.swift` for the new pure presentation/grouping behavior and `HaiityUITests/TodayViewUITests.swift` for real actions. Extend existing schedule/reminder tests rather than duplicating engine arithmetic.

- [ ] Write failing classification checks for fixed, rest-day, flexible, overdue, future-time, archived and declined scenarios.
- [ ] Compose the page from the existing canonical results, with separate fixed/flexible/reminder units.
- [ ] Keep temporary row/group IDs stable during the current visit.
- [ ] Verify a completion/undo does not move the row or change the neighboring action target while interacting.
- [ ] Verify newly arriving/removed items and safe idle regrouping.
- [ ] Feed an explicit page clock/calendar through rows and test midnight plus a reminder's same-day due-time transition.
- [ ] Add the empty/free-day/resolved/write-failure states.

**Example regression using the existing engine:**

```swift
func testFlexibleGoalsDoNotBecomeDailyObligations() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = DayKey.date(from: "2026-10-10", calendar: calendar)!
    var daily = Habit(name: "Read", recurrence: Recurrence())
    daily.createdAt = "2026-10-01"
    var flexible = Habit(name: "Run", recurrence: .times(3, per: .weekly))
    flexible.createdAt = "2026-10-01"
    let progress = ScheduledProgress.today(habits: [daily, flexible],
        defaultTimeZoneIdentifier: "UTC", now: now, calendar: calendar)
    XCTAssertEqual(progress.scheduled, 1)
    XCTAssertEqual(progress.flexible, 1)
}
```

The fixture dates are explicit so the test does not depend on the machine's current day. The assertion expresses the existing engine contract; it does not replace tests of the new view's actual classification and behavior.

**Exit evidence:** Fast daily actions, truthful counts and stable touch/undo behavior without graph-heavy row construction.

### Task 4: Rebuild the collection and sorting composition

**Files:** New `Haiity/Views/HabitsView.swift`, `HabitCard.swift`, `ReminderRow.swift`, `GitHubContributionCard.swift`, `GitHubContributionGraph.swift`, `HabitSortingScreen.swift`; root supplies existing guarded order/filter/action callbacks.

**Tests:** `HabitListFilterTests.swift`, `StatsAndReorderTests.swift`, `GitHubCardContractTests.swift`, `HabitCardProductTests.swift`, `SortingUITests.swift` and collection UI scenarios.

- [ ] Extract the actual collection layout from `ContentView`; do not duplicate its backing store or gesture engine.
- [ ] Keep GitHub first in all filters and the new detail/history interaction contract visible.
- [ ] Preserve stored Today-only selection while making the new Today tab independent of it.
- [ ] Verify rendered band width within 1 pt at the specified phone/container sizes.
- [ ] Retain cache keys, today projection and independent preview geometry.
- [ ] Restyle order mode around the existing native table, including the fixed GitHub identity.
- [ ] Exercise bottom-to-top/top-to-bottom moves, auto-scroll, relaunch, rejected saves, external membership changes and VoiceOver moves.

**Exit evidence:** Correct measured graphs and manual order without a second collection implementation or new drag recognizer.

### Task 5: Integrate the root shell and settings navigation

**Files:** `Haiity/Models/AppNavigation.swift`, `Haiity/Views/ContentView.swift`, `MoreView.swift`, existing More page handlers and legacy chrome/search support.

**Tests:** `AppNavigationTests.swift`, `SearchFlowTests.swift`, `ChromeLayoutTests.swift`, existing navigation UI tests and new Today navigation tests.

- [ ] Add `.today` and the real settings-root destination to the current enums.
- [ ] Show Today/Habits/Progress with the separated Search affordance; launch Today only when no explicit route overrides it.
- [ ] Replace More-as-tab with a global settings entry using the existing stack/path machinery.
- [ ] Map legacy routes to real visible destinations; no binding to an absent `.more` tab.
- [ ] Keep the current modal dismissal/generation rules and caller-specific paywall continuations.
- [ ] Preserve built-tab/scroll state and proper active accessibility/hit-testing layers.
- [ ] Adapt the older-iOS compatibility shell without adding another new navigation framework.
- [ ] Verify deep links from an open editor, sentence child, paywall, history view and settings child.
- [ ] Remove the unused old More-tab presentation branch only after replacement coverage passes.

**Proposed route check after the enum addition:**

```swift
func testLegacyMoreOpensTheRealSettingsRoot() {
    XCTAssertEqual(AppDestination.more.effect,
        AppRouteEffect(tab: .today, morePage: .settings,
                       opensSearch: false, opensCreate: false))
}
```

Other legacy destination effects keep the URL intent in section 3.3. The old `.more` case is a compatibility identity, not a fourth content page.

**Exit evidence:** One working root composition on supported systems, with correct old URLs, stable state and no orphaned modal.

### Task 6: Recompose Progress

**Files:** `Haiity/Views/StatsView.swift`, existing `StatsCardPrefs.swift` and `StatsEngine.swift` as preserved data contracts.

**Tests:** `StatsEngineTests.swift`, `StatsProductTests.swift`, `StatsCardPrefsTests.swift`, `StatsProductUITests.swift`, `StatsContextMenuUITests.swift`.

- [ ] Write a behavioral expectation for one primary weekly result and retained selected metrics.
- [ ] Implement the new hierarchy using the existing snapshot/cancellable scheduler.
- [ ] Remove the compulsory duplicate Today hero while keeping explicitly selected Today content.
- [ ] Keep exact values, denominators, custom ordering and Pro boundaries.
- [ ] Replace repeated explanation chrome with contextual explanations.
- [ ] Route habit selections to details and retain direct full history.
- [ ] Verify empty denominators, flexible-period explanations, localization and optional AI expansion without generation.

**Exit evidence:** A distinct reflection screen with unchanged statistics and saved choices.

### Task 7: Rebuild creation/editing presentation

**Files:** `Haiity/Views/EditHabitSheet.swift`, `SpeakToCreateSheet.swift`, root creation callbacks; preserve `RecurrenceDraft.swift`, `CreateItemSaver` and dictation/parsing behavior.

**Tests:** `CreationProductTests.swift`, `CreationDisclosureTests.swift`, `HabitTimeTests.swift` including its `LegacyFieldsSurviveTests` class, `MultipleNotificationTests.swift`, `ProGateTests.swift`, `ProductSimplificationUITests.swift`, `SpeakToCreateDockUITests.swift`.

- [ ] Add the explicit initial item type input for the Add choices, preserving daily/once defaults and existing callers.
- [ ] Recompose essential fields, one preview sentence, conditional quantity and collapsed extras.
- [ ] Keep the parent manual draft mounted during the embedded sentence task.
- [ ] Reuse sentence content without nested stacks or duplicate work/lifecycle owners.
- [ ] Verify cancel/back restores the full manual draft and successful child creation closes exactly once.
- [ ] Keep all save/permission/Pro/hidden-field handlers intact or migrate them with exact regression coverage.
- [ ] Verify multi-alert add/remove, Off retention, inherited/empty times and distinct appointment clocks.
- [ ] Verify numeric dates, invalid dates, inline dictation, denial, finalization and late cancellation.
- [ ] Test keyboard-open layouts and date/recurrence controls at AX5 in RTL.

**Exit evidence:** Creation is shorter to scan, cancellation is lossless for unsaved UI state, and saving preserves the existing durable contracts.

### Task 8: Unify settings and secondary pages

**Files:** `MoreView.swift`, `MoreAppearance.swift`, `MoreNotifications.swift`, `MoreCalendar.swift`, `MoreBehavior.swift`, `MorePersonal.swift`, `MorePro.swift`, `MoreLocalModel.swift`, `GitHubSettingsView.swift`, `DataTransferView.swift`, `AboutView.swift`, `ArchiveView.swift`, `FeedbackSheet.swift`.

**Tests:** Current account, entitlement, data-transfer, setup, appearance and navigation suites plus their native UI cases.

- [ ] Compose the new groups through existing shared rows and page roles.
- [ ] Make child navigation return to its correct parent and scroll state.
- [ ] Verify direct notification/calendar pages without setup or initial-open writes.
- [ ] Record non-default summary/time/permission preferences before opening and compare after returning.
- [ ] Keep account rows navigation-only and login/logout states clear on secondary pages.
- [ ] Verify full-row timezone selection and Pro/permission recovery.
- [ ] Verify sequential image selection/crop/zoom/cancel and all saved appearance fields.
- [ ] Keep importer/share/export, archive, restore purchase and feedback behavior.

**Exit evidence:** Every secondary destination belongs to the same UI language and retains its actual state/permissions.

### Task 9: Verify extension and launch parity

**Files:** Existing `HaiityWidget/WidgetComponents.swift`, family/accessory/Live Activity view files only where a proven presentation mismatch needs correction; root URLs and intent implementations remain stable.

- [ ] Inspect each existing family in native full-color, tinted/clear and relevant accessibility modes.
- [ ] Confirm action targets, intent independence, root links and timeline refresh after a durable change.
- [ ] Confirm reminder occurrence status and zero/partial/completed graph state.
- [ ] Confirm system session timers, Finish/Cancel/Dismiss and privacy markings.
- [ ] Verify the splash-to-local-content handoff without integration/model work competing with the first frame.
- [ ] Leave already-correct extension composition in place; do not redo the completed widget rebuild.

**Exit evidence:** The rebuilt app and extension presentation agree without changing background behavior.

### Task 10: Final resources, cleanup and release evidence

**Files:** `Haiity/Localizable.xcstrings`, `docs/design/haiity-ui-design-system.md`, affected tests, `TestPlans/Smoke.xctestplan`, `project.yml` and regenerated project snapshot when needed.

- [ ] Translate every new critical label/state in all 17 locales and prove prior catalog preservation.
- [ ] Keep one owner for the catalog while workers hand off exact keys/placeholders.
- [ ] Remove superseded UI code and source assertions that only freeze private syntax; keep privacy/packaging checks.
- [ ] Update the design-system contract to this hierarchy without erasing preserved appearance rules.
- [ ] Regenerate with pinned XcodeGen; do not hand-edit the project.
- [ ] Run focused regressions, then final complete Unit/Smoke and Release checks on one source revision.
- [ ] Inspect actual captures and collect comparable performance evidence.
- [ ] Record remaining physical/service/platform gates separately.
- [ ] If a release is requested, choose a unique build from live state, align app/widget metadata and verify the exact reviewed commit.

**Exit evidence:** A reviewable complete UI candidate with truthful source-bound results and no remaining unexplained local failures.

## 19. Worker ownership and recovery

The design in this document is authored by the main assistant. During an authorized implementation:

| Owner | Bounded scope |
| --- | --- |
| Main | Root routes/presentation, mutation/undo contracts, shared interfaces, integration, Xcode and release evidence |
| Today/detail worker | New Today/detail presentation and their isolated tests after interfaces are agreed |
| Collection worker | Collection/sorting presentation and owned graph/UI tests; no store or routing writes |
| Progress/creator worker | Progress or creator in separate disjoint assignments; no concurrent writes to the same file |
| Settings/resources worker | Assigned More pages or catalog; one catalog owner at a time |
| Reviewer | Read-only actual diff and connected caller/test review |

Do not spawn all of these by default. Use only workers that advance independent work without blocking the main critical path. Every worker uses the exact requested Sub2API model, preserves dirty state, and avoids Xcode/browser/device/release actions outside its assignment.

Freeze source before final gates. Store the last concrete checkpoint, source fingerprint, toolchain, active build/session and outstanding requirements in the implementation report. Reuse passed evidence while unchanged. Respect actual provider resets and Retry-After instead of repeated futile requests.

A completion heartbeat resumes authorized interrupted work; it does not authorize implementation of a newly proposed design or broaden upload/installation permissions. Update its checkpoint when the accepted scope changes and disable only the relevant heartbeat after actual completion.

## 20. Verification plan

### 20.1 Functional scenarios

| Area | Minimum meaningful cases |
| --- | --- |
| Today | Empty, free day, fixed daily, rest day, weekly/monthly/yearly flexible, quantity partial/target/over-target, Yes/No/undo |
| Reminders | Before clock, due, overdue, future day, completed, several open occurrences, early confirmation and recurring cursor behavior |
| Data | Future start, ended rule, archived, duplicate names, sparse/long history, rejected/stale write, external update/removal |
| Details | Name route, Edit roundtrip, full history, archived restore, deletion during navigation |
| Navigation | All old URLs, settings from each tab, child Back, cancelled creator, newer route superseding older pending work |
| Search | Filters independent, retained query, keyboard open, no GitHub injection, selected item and returning scroll |
| Sorting | Both directions, edge auto-scroll, held finger, filtered scope, failed save, external change, relaunch, VO actions |
| Progress | Existing counts/rates/rounding, zero denominators, customized empty/all-five choices, Pro and optional reading |
| Creation | Explicit type/defaults, advanced retention, alert clocks, date parser, dictation denied/finalized/cancelled, failed save retry |
| Settings | Non-default values unchanged on opening, denied/granted recovery, crop sequence, accounts, importer, restore purchase |

### 20.2 Visual/platform matrix

Use representative combinations rather than running every possible Cartesian product.

| Dimension | Coverage |
| --- | --- |
| Width | Native small/ordinary/large phone; component render checks at 320/375/402/440 pt |
| Styles | Original, Quiet, Focus, Studio |
| Appearance | Light/dark, ordinary solid, photo, gradient, custom palette, chosen material |
| Accessibility | Ordinary size, AX1 and AX5; VoiceOver and Reduce Motion |
| Fallbacks | Reduce Transparency, Increase Contrast, performance mode and compact mode |
| Languages | English/German, Arabic RTL and long translated labels; full catalog coverage for all 17 |
| OS | Available older compatibility runtime plus iOS 26/27 behavior where executable environments exist |

Capture Today, collection, details, history, creator with keyboard, sentence input, settings, account, crop, Progress and sorting. Compare the same fixtures and preferences. Passing source-string assertions do not establish layout quality.

### 20.3 Native commands

Run from the actual implementation checkout. Select the current existing simulator from live inventory; no retired Mac mini device IDs.

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  bash tools/generate-project.sh

env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun simctl list devices available

env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  bash tools/verify.sh

env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild build -project Haiity.xcodeproj -scheme Haiity \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO

git diff --check
```

`tools/verify.sh` supports `TEST_DESTINATION` and `VERIFY_OUT` for a selected existing simulator and fresh output directory. Its evidence gate checks source changes, failure/skip counts and suspiciously small runs. Use the new test enumeration as well; a floor passing is not proof that new tests were registered.

When native runtime, provider or build tooling fails, diagnose the actual error, preserve the checkpoint and continue independent authorized work. An unsealed/interrupted test report is not a passing result bundle.

### 20.4 Physical and external gates

When the relevant device/service action is authorized and available, verify:

- Real-data first open after the splash and repeated return to each tab.
- Reordering while a finger remains held, interruption and resumption.
- Actual VoiceOver focus/action order on Today, details, sorting and settings.
- Notification timing, answering one banner without clearing unrelated banners, and real-open cleanup.
- Live Activity actions/timers and widget refresh after app/intent writes.
- iCloud change from another device and Calendar/Reminders recovery.
- Background crop result and text contrast on the real screen.
- iOS 27's separated prominent Search behavior where that branch is actually running.

Local Unit/Smoke/Release success remains distinct from those results. An unavailable phone/account is an explicit open gate, not a reason to claim success or reset data.

For requested distribution, recheck live App Store Connect through Chrome Use with Chrome, use the supported release/Cloud path for the current host, verify the exact commit, then distinguish accepted upload, Apple processing, tester assignment and the installed TestFlight build. Do not call `release.sh` without understanding that its default flow installs on a physical phone.

## 21. Definition of completion

The checked items record the authorized local candidate and its source/fixture/native regression evidence. The precise external execution boundaries retain their separate status in the final result above.

- [x] Today, Habits and Progress have distinct purposes and working routes.
- [x] Settings is reachable from all roots and Search remains separated.
- [x] Daily work is visible quickly; no full-history grid is mounted in Today rows.
- [x] Flexible goals/reminders/negative answers have accurate, distinct meanings.
- [x] Today completion/undo and collection sorting preserve touch/identity stability.
- [x] Collection graphs fill measured width and GitHub stays first without entering personal totals/order.
- [x] Details, Edit and full history are independently reachable and use the live item.
- [x] Creator/sentence cancellation preserves the parent draft; save/permission/Pro behavior remains correct.
- [x] All settings pages follow the same language and opening them does not rewrite configuration.
- [x] Saved appearance, metric choices, backgrounds, crop and notification times remain intact.
- [x] Old URLs, widgets, Live Activities, notification actions and sync retain their tested compatibility contracts; external execution gates are recorded above.
- [x] Every new critical label is translated in all 17 locales.
- [x] Native tests, inspected screenshots and comparable performance checks support the actual new revision.
- [x] Applicable physical/platform/service checks have evidence or an explicit precise outstanding gate.
- [x] Release/distribution status is stated accurately and the relevant completion heartbeat is handled.

## 22. Design basis and current limitations

The three-job structure, density targets and presentation choices are the main assistant's design judgment, informed by current source and October 9 simulator captures. They are not claims about the build currently installed on the user's phone.

Apple HIG references read from the local apple-design collection constrain the proposal:

- `layout.md`, Visual hierarchy: "Align components with one another to make them easier to scan" and make relative importance visible.
- `lists-and-tables.md`, Content: succinct rows may lead to a detail view for fuller content.
- `tab-bars.md`, Best practices: stable tabs represent content destinations; actions belong in appropriate controls.
- `typography.md`, Supporting Dynamic Type: adapt layout and maintain hierarchy at larger sizes.
- `accessibility.md`, Mobility: sufficiently sized controls and alternatives to gestures.
- `settings.md`, Task-specific options: keep task-specific filtering/reordering near the affected task.
- `motion.md`, Best practices: brief, precise feedback; avoid unnecessary motion for frequent actions and allow cancellation.
- `color.md`: semantic colors, light/dark/increased-contrast support, and actual contrast checks.

The original design proposal was prepared without app-source, build/test or release changes. Its authorized implementation and final local verification are now recorded above. The candidate remains in the preserved dirty worktree, with the physical/platform/service and distribution gates stated explicitly.
