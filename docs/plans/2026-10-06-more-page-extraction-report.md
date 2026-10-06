# More page extraction

Date: 2026-10-06
Base: `26ee4c8`, main, version 1.0.0 (275)
Status: implementation and local verification complete

## Scope

Split the existing More pages into extensions of MoreView. Keep the existing
state, presentation, lifecycle and purchase-resumption owner. No additional
component layer, view model or binding container is introduced.

Appearance, calendar, personal name, Pro, notifications, behavior and the local
model catalogue each receive a file. Page-local helpers remain private;
cross-file entry points and the existing state they need use module access.
There is no new public API. MoreView is 631 lines, down from 3,412. Across the
eight More source files there are 3,401 lines in total, so the split adds no net
line-count growth.

Ordinary hub actions share moreHubRow instead of two copied buttons. Calendar
destination rows reuse AppSettingsRow for their title, detail and selected
checkmark. These are the only intended presentation changes.

The source contracts now read the file that implements the guarded behavior and
check root composition separately. Assertions for moved entry points no longer
demand private access modifiers. Source contracts still exist; this pass does not pretend to
replace the whole suite with behavioral tests. The old archive assertion that
forbade an unused spelling is corrected to check the existing archive route.
The test bundle copies each More source fixture separately. XcodeGen remains the
project authority.

## Preservation

A read-only comparison against the base checks 150 existing computed properties
and functions, all localized strings and accessibility IDs, 45 root state
fields, and the complete root presentation/lifecycle body. Only mainSettings,
moreHubRow, removed pageRow and calendarOptionRow are excluded from body equality
because they contain the intended row consolidation.

ContentView, Theme, HabitStore, graph rendering, WidgetKit ink, proRow, the fixed
15-point notification symbol, data formats and distinct paywall presenters are
outside this pass. No release metadata, commit, push, upload or physical-device
installation is part of this pass.

## Verification

Artifacts: `/Users/enricomini/Documents/haiity-verification/more-page-extraction-20261006`.

| Checkpoint | Result |
| --- | --- |
| Unchanged baseline Unit | 2,111 passed; zero failures/skips/runtime warnings |
| Pro extraction Unit | 2,111 passed; zero failures/skips/runtime warnings |
| Calendar extraction Unit | 2,111 passed; zero failures/skips/runtime warnings |
| Personal extraction Unit | 2,111 passed; zero failures/skips/runtime warnings |
| Appearance extraction Unit | 2,111 passed; zero failures/skips/runtime warnings |
| Notifications extraction Unit | 2,111 passed; zero failures/skips/runtime warnings |
| Behavior and hub-helper Unit | 2,111 passed; zero failures/skips/runtime warnings |
| Local-model extraction Unit | 2,111 passed; zero failures/skips/runtime warnings |
| Final entitlement-guard coverage repair Unit | 2,111 passed; zero failures/skips/runtime warnings |
| Initial scoped simulator UI checks | 8 passed, 2 launch-setup hittability failures; zero skips |
| Two launch-setup repairs | 2 passed; zero failures/skips/runtime warnings |
| Final source-frozen Unit | 2,111 passed; zero failures/skips/runtime warnings |
| Final source-frozen scoped UI | 10 passed; zero failures/skips/runtime warnings |
| Unsigned generic iOS Release build | Exit 0; zero errors, four MLX dependency warnings |
| Source-bound evidence | Recorded and checked; exact current source and 1.0.0 (275) |
| Embedded source fixtures | All eight More fixtures match the current files |
| Evidence rejection checks | 16 rejection cases passed |
| Final diff check | Exit 0 |

Final review found that the old More-wide negative entitlement-bypass assertions
had not covered every extracted page. The safeguard now scans all seven explicit
page sources while the positive entitlement read remains on root. The first
scoped UI attempt was intentionally interrupted (exit 75) before accepting
evidence; final Unit and UI checks run against the repaired test source.

The first completed UI run failed two tests while their launch helper tried to
reach Appearance without selecting More through the tab bar. The all-style
navigation check and seven other cases passed. A manual simulator launch showed
More rendering correctly. The design test helper now explicitly taps the native
More tab in the requested English/Arabic language before seeking a row. Neither
assertions nor timeouts were weakened, and both previously failing cases passed
on the repair run. Final source-bound checks include that test-setup change.

Final evidence: [evidence.json](/Users/enricomini/Documents/haiity-verification/more-page-extraction-20261006/evidence.json).
Source fingerprint:
`26205f9c48acf0661dbd454b57ed837a9751f8c2ec04d44fd5e5129a5b8cdce6`.
Xcode 27.0 (27A266a), iOS 27.0 SDK, XcodeGen 2.46.0. Final native tests used the
iPhone 18 Pro simulator with iOS 27.0. The ten UI cases are a scoped selection
from Smoke, not a claim that every test in the full Smoke plan ran.

Release used `generic/platform=iOS`, configuration Release and
`CODE_SIGNING_ALLOWED=NO`. App and embedded widget metadata both remain
1.0.0 (275). The four warnings are `constexpr if is a C++17 extension` in
unchanged mlx-swift Metal headers. This is a build check, not a signed archive.

The incremental quiet Xcode logs can print an exit-zero/no-output diagnostic.
For inspected results, Xcode's structured build result reports success and zero
errors. Existing test-source deprecation warnings remain; a passing test result
does not imply a warning-free build.

## Render review

Exported 48 PNGs from the final UI result. Reviewed representative More,
Behavior/calendar, Notifications, local-model, account, public transfer and
Arabic AX5 appearance captures. No new alignment or text clipping defect was
visible in these captures. Existing layouts and native chrome are preserved;
content below the screen remains scrollable. UI tests use synthetic data and
debug identity state; they do not establish real Apple/GitHub login or native
calendar permissions.

| Reviewed page | Capture |
| --- | --- |
| More hub | [More](/Users/enricomini/Documents/haiity-verification/more-page-extraction-20261006/verified-captures/85647861-2D7B-47C9-A9D2-B1AB5E549939.png) |
| Behavior/calendar | [Behavior](/Users/enricomini/Documents/haiity-verification/more-page-extraction-20261006/verified-captures/AB1FC532-477D-4468-8C31-AE7FA35BBE68.png) |
| Notifications | [Notifications](/Users/enricomini/Documents/haiity-verification/more-page-extraction-20261006/verified-captures/0A0A6DE6-13D3-4EBB-9241-F6190F26738B.png) |
| Local-model catalogue | [Models](/Users/enricomini/Documents/haiity-verification/more-page-extraction-20261006/verified-captures/B529163D-3641-4256-9A58-055359B862B9.png) |
| Studio account content | [Account](/Users/enricomini/Documents/haiity-verification/more-page-extraction-20261006/verified-captures/747202BE-1A9F-4614-8592-99A82C534B9B.png) |
| Public Import/Export | [Transfer](/Users/enricomini/Documents/haiity-verification/more-page-extraction-20261006/verified-captures/A25C6F52-671A-453B-8F29-35D5D9AAF31B.png) |
| Arabic, largest text | [Appearance](/Users/enricomini/Documents/haiity-verification/more-page-extraction-20261006/verified-captures/8719B182-4AED-43C9-BDE2-C2614ACF5E5A.png) |

## Remaining work

Physical-device VoiceOver, native account/calendar permissions and live services
remain separate from simulator checks. This cleanup makes no performance or
TestFlight-delivery claim. ContentView and Theme extraction are deliberately
later passes; source-text test debt outside the affected More contracts remains.
No local blocker was found for this More cleanup. No commit, push, upload or
physical-device installation was made.
