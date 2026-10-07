# Product simplification verification

Status: implementation, native tests and generic Release build complete locally.
Physical/service verification remains pending separately.

## Source identity

- Repository: /Users/enricomini/Documents/Github/haiity
- Base: main / 98241c19551c653057037bc520b2b9e6b4cd2330
- Version/build: 1.0.0 (276), unchanged
- Frozen source fingerprint: c7db58b6a83db4fd3b4f446f18d4c86d5f7e33a13359b4399375789627194ee1
- Evidence: /Users/enricomini/Documents/haiity-verification/product-simplification-20261007
- No commit, push, upload, device installation or physical test was performed.

## Implemented scope

| Accepted change | Result |
| --- | --- |
| Creation defaults | New habits start daily and reminders once; repetition and loading preserve item type. The generic legacy draft default stays once. |
| Lighter creation | Name, repetition, essential reminder date/time, preview and Save lead. Kind/quantity and optional notification/calendar/duration/timezone/swipe settings remain available through disclosures. Hidden notification times are retained. |
| Today and recent progress | Separate Today controls remain at least 44 pt in compact mode. Cards display eight recent weeks with centered cells capped at 20 pt. |
| History and editing | Name and graph open the existing full history editor; a visible pencil opens Edit. Native long-press remains an optional shortcut. |
| Quiet fresh default | Only fresh stores start Quiet. Existing/legacy/unknown styles retain their prior fallback. Fresh appearance stamp zero is non-authoritative in either merge direction; explicit changes receive their existing positive timestamp. Designs/materials stay inside Customize. |
| Optional sentence creation | The creator passes typed text into the existing sentence/dictation page using a native item-based sheet after dismissal. The global floating action is removed. Sentence dismissal is tracked separately by the existing routing state machine. Normal settings show assistance/readiness; named model controls remain under Advanced, with saved choices preserved. |
| Personalization/connections | More uses navigation-only connection rows. Personalization leads with the local nickname; Apple connection is optional on that page, and GitHub authentication stays on its secondary page. Existing identity/StoreKit boundaries remain unchanged. |
| Useful Statistics | Today and current-week completion lead, followed by recent per-habit completion. Saved metric choices, history routes and Pro gates remain. AI reading is collapsed and requires its own explicit action. Existing math and denominators are unchanged and explained. |
| Flexible weekly goals | The existing recurrence/GoalEngine supports the visible quota option: N times per week, any day. Legacy rules and history remain stable until explicit edits. |
| Feedback/efficiency | One queued/cached snapshot drives each recent graph. The current day's square and count update immediately during check-off/undo through the existing engine. App/widget mutation and invalidation paths remain intact. Real phone responsiveness is a separate pending gate. |

No new component framework, model-download engine, paywall presenter or dependency
was introduced. Shared settings components and ContributionChart/ContributionTiles
remain the existing rendering language. The split native Search button remains.

## Preservation

The initial notification-banner patch remains byte-identical. Its current scoped
diff SHA256 equals the captured baseline.patch:

ace975ec9baecbfaeb33b8dcdfa1771e198555137c179c8b2143197a6863a992

The pre-existing device-session document and Git recovery state remain untouched.
The old notification-only prepared binary is a separate checkpoint and does not
represent these combined product changes.

All 970 prior localization entries retain their values and metadata. Twenty new
keys have 340 translated units across all 17 existing locales; duplicate-key,
nonempty-value, translated-state and placeholder checks pass. Final catalog SHA256:

a5c027bcf1961965131d1ebd6487f89524b70962cea48e0178da8893ecabfdda

## Local verification

| Check | Evidence | Status |
| --- | --- | --- |
| Pre-edit native Unit baseline | Baseline.xcresult | 2,113 passed; 0 failed |
| Final native Unit | FinalUnit2.xcresult | 2,146 passed; 0 failed; 0 skipped |
| Focused native UI regression | UIRegression.xcresult | 9 passed; 0 failed; includes photo/material retention, four-style compact controls, preview tap, AX5/RTL creator/selectors and repeated navigation/scrolling |
| Final complete native Smoke | FinalSmoke.xcresult | 46 passed; 0 failed; 0 skipped; 0 runtime warnings |
| Generic iOS Release build | Release.xcresult; Release.log | PASS, exit 0; unsigned generic iOS compilation; 4 existing MLX Metal warnings; 0 error lines |
| Revision-bound evidence | evidence.json; verification.rb check | PASS; commit, fingerprint, tools and version/build match both final result bundles |
| Project regeneration / evidence checks | generate-project.sh; verification_test.rb | PASS; new test files registered; 16 evidence-rejection cases pass |
| Whitespace / catalog validation | git diff --check; strict JSON comparison | PASS |

The final Unit result records 16 warnings from standalone view-builder rendering
tests reading default SwiftUI Environment/State values outside a mounted view.
Those partial component checks do not prove environment-specific layouts; the
mounted native UI checks provide the AX5/RTL/light/dark evidence. These warnings
are not presented as a warning-free result.

The initial broad Smoke run passed 37 of 43 and exposed six test-target/navigation
failures. The focused nine-check retry passes after matching the accepted UI:
Customize is opened once, compact checks use tab navigation, lifted previews use
UIKit's Preview element, the optional reading has an explicit label target, the
GitHub login action is checked on its page, and scalable month labels have a
separate height allowance from the bounded tiles.

Earlier integration checks also caught and corrected typed text lost through a
Boolean sheet, the creator's multiline Return behavior, disclosure identifiers
propagating into Apple buttons, and debug launch-screen routes overriding incoming
URLs. Failed/intermediate bundles are retained and are not final release proof.

## Visual inspection

Reviewed native screenshots of independent card controls and centered recent
graphs, compact Focus layout, simplified Appearance, nickname/optional Apple
pages, the RTL/AX5 card, and the RTL/AX5 material selector. Text grows and the
functional Search button stays split from the other tabs. The reviewed artifacts
are in ProductUI2-attachments and UIRegression-attachments. Also reviewed final
Smoke screenshots of simple habit creation, the saved flexible weekly editor and
dark RTL/AX5 Statistics. FinalSmoke-attachments contains the exported final captures.

## Separate physical/service gates

No real-phone startup/performance result is claimed. The prior device attempt
stopped before transfer with CoreDevice 4016. The 14 checks in
2026-10-07-device-session.md remain NOT RUN: cold notification panel behavior,
real-data post-splash responsiveness, notification timing, Live Activity, second
device iCloud, native recovery, Home Screen widgets/timeline/Control Center,
VoiceOver and long-held sorting. No new physical availability claim is made.

Local appearance-merge tests exercise delayed legacy/current data and preserve
explicit choices; they do not prove live CloudKit delivery between two devices.
Simulator interaction checks do not prove the original phone stall is fixed.
No TestFlight or Xcode Cloud release action is part of this local change.

## Continuation checkpoint

All ten product changes and their local acceptance checks are implemented and
verified against the frozen fingerprint above. Final Unit, final 46-test Smoke,
generic Release build, localization preservation and revision evidence checks
pass. Do not repeat these passed checks unless sources or verification conditions
change. No bounded workers or Xcode jobs remain active after this checkpoint.

The remaining gates require actual phone/service observations, and a later
combined device binary must be bound to these product sources rather than the
older prepared notification-only binary. Preserve the existing device ledger;
do not mark its NOT RUN rows as passed from these local results.
