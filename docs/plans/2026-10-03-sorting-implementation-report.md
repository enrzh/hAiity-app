# Native Sorting Implementation

Date: 2026-10-03
Baseline: `main`, `109a06d9bfc0633e59b8d45abc60cd25aad4a0dc`
Build metadata: 1.0.0 (273), unchanged
Status: bounded implementation and final local gates passed; physical gates pending

## Result

Sorting stays in the Habits page and uses an owned native `UITableViewController`
with generic `UIHostingConfiguration` rows. UIKit owns the reorder handle,
lift, neighbor movement and edge scrolling. Public SwiftUI List movement was
tried first, but its 40-item long-drag regression failed; the plan's authorized
owned-table fallback is the final implementation. No second reorder engine,
backing-view discovery, custom drag physics or window gesture remains.

Compact rows show the name, item type and existing icon. Title and Heute/Alle
scope remain outside the reorder area. Normal graphs, check-off, swipe actions
and editing return on Done, near the last moved item where possible.

The table converts UIKit's final destination row into SwiftUI Array.move
semantics: downward destinations add one, upward destinations retain the row
index. Completed moves use ContentView's captured ordered IDs and generation,
then its guarded store.moveVisible callback. HabitStore owns atomic persistence,
validates stale orders and offsets, preserves hidden/archived slots, avoids
no-op writes and restores durable state on save rejection. Navigation,
backgrounding and external membership/order changes end the sorting session.

Row names, position/count and localized Move Up/Move Down accessibility actions
remain available through the shared move path. Cell hosting state resets when
the habit ID changes. Unchanged Habit models do not refresh visible content;
refresh after a completed native table move is queued onto the next main run-loop
turn. The sorting clock checks fresh-date membership without refreshing stable
rows. Final test bundles contain no publishing-during-view-updates warning.

The final photo audit found insufficient contrast in the small type caption
over a gray photo stripe. One semantic cell background,
`secondarySystemGroupedBackground`, now protects both text and the native handle
in light/dark appearances. This follows Apple HIG accessibility/color guidance
to maintain contrast and use adaptive semantic surfaces. Row and handle audit
coverage was retained; only the existing native navigation/tab-bar contrast
exception remains. No new row exemption was added.

## Regression Findings

The owned table reached both ends and saved the exact expected order, but an
earlier live UI scan reported 731/732 swapped; the next scan reported 718/719.
Read-only inspection of only those tests' isolated
`tmp/design-fixture-sorting-UUID.json` files confirmed correct durable order.
No production data.json, CloudKit or account stores were inspected.

The UI oracle previously read an index-bound element's identifier and frame
through separate live accessibility queries. It now reads all row identities
and geometry from one public `XCUIElement.snapshot()` per screen. Exact 40-ID
order comparisons, idle scrolling, both 30-second single-grab edge holds and
relaunch persistence assertions remain intact; saved data does not replace the
UI assertion.

The compact RTL test initially pressed at x=351 on the right while UIKit's
handle was on the left. An obsolete label-based fallback guessed the wrong
edge. Tests now use the identified native cell's actual hittable reorder button
in either layout direction. Exact target order and restored editing/re-entry
assertions are unchanged. Both corrected cases passed focused checks and the
required final source-bound gates.

## Final Verification

All final artifacts are retained under
`/Users/enricomini/Documents/haiity-verification/sorting-complete.d7Hf84`.

Final source fingerprint:
`bcde83fa70ab13d73e099acff9c8cb2fba5973b373535b8e082400f88a13436e`

Toolchain: Xcode 27.0 (27A266a), iOS SDK 27.0, pinned XcodeGen 2.46.0.
Every Xcode command used
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

| Check | Final result | Artifact in the directory above |
| --- | --- | --- |
| Full `bash tools/verify.sh`, Unit | 2,105 passed; zero failures/skips/runtime warnings | `Unit.xcresult`, `Unit.log` |
| Full Smoke | 17 passed; zero failures/skips/runtime warnings | `Smoke.xcresult`, `Smoke.log` |
| Fast-drop/no-op and background/navigation/relaunch | 2 passed; zero failures/skips/runtime warnings | `Regression.xcresult`, `Regression.log` |
| Compact SE, Arabic RTL/largest text/Reduce Motion/Done | 1 passed; zero failures/skips/runtime warnings | `Compact.xcresult`, `Compact.log` |
| Unsigned generic iOS Release | Exit 0, `CODE_SIGNING_ALLOWED=NO` | `Release.log`, `Release.exit` |
| Source/toolchain/version evidence | Check passed against final sources, 1.0.0 (273) | `evidence.json` |

Full verification and focused regressions used simulator
`2F9C45FC-34DC-44F6-B12A-C72B9DED1673` (iPhone 18 Pro, iOS 27.0).
Compact verification used `CE73965B-EDCC-4331-BF9B-86EFEA944973`.
The compact test restores its original simulator Reduce Motion setting in
teardown. Smoke includes the exact 40-item bottom-to-top/top-to-bottom and
relaunch case plus light/dark photo row audits. Regression.xcresult reruns the
existing fast-drop/no-op and completed-order recovery cases against UIKit;
old SwiftUI passes are not used as proof.

The full gate ran after the final code/test freeze. Pinned project generation
did not change the fingerprint. Verification tooling passed its 16 rejection
cases, including changed/untracked source detection. Final
`ruby tools/verification.rb check` and `git diff --check` passed after the
documentation updates. All earlier /tmp artifacts are historical only; lost
artifacts and passing results from different sources are not final evidence.

## Remaining Gates and Scope

Public XCUITest drags release before another action runs. Background/navigation
recovery proves preservation of completed moves, not cancellation while a
physical finger remains held. Physical held-touch interruption/cancellation,
rapid reversal after edge scrolling, VoiceOver focus/announcements and 60/120 Hz
device feel remain separate manual hardware gates.

The unsigned Release build compiles for the existing iOS 18 deployment target;
these runtime tests use iOS 27.0. iOS 18 hardware remains unverified. Performance
metric cases were not repeated. No FPS, render-latency or speedup claim is made.

Final integration review and source-bound evidence validation passed. The source
remained unchanged throughout the final Unit/Smoke, regression, Release and compact
checks. Existing dirty, untracked and Git recovery state was preserved. The
implementation remains local and uncommitted; no push, version change, upload or
physical-phone installation occurred.
