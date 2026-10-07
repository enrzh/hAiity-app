# Device session: 2026-10-07

## Priority and scope

Install the existing banner fix, then perform one real-phone pass. The next
observed failure determines the next code change. After that, simplify GitHub
and AppleID hub rows to navigation only, with SignIn on the secondary page.
ContentView/Theme extraction comes later.

Record written results only; no video recording is implied.
Preserve existing real data and unrelated banners. No synthetic data,
reset, or whole-app deletion.

## Build and evidence binding

Local preparation is complete. Physical installation and observations are
blocked by the phone connection; no physical PASS or FAIL is claimed.

| Field | Value |
| --- | --- |
| Build | 276 |
| Base commit | `98241c19551c653057037bc520b2b9e6b4cd2330` (main) |
| Dirty fix paths | `Haiity/HaiityApp.swift`; `Haiity/Services/NotificationPresenter.swift`; `HaiityTests/NotificationActionTests.swift` |
| Dirty hash / source fingerprint | `3e4d67e2756166455d4612650c70e381effd9f140eaa65a27eacb3c803de985f` |
| Configuration | Signed Release archive; local release-testing export |
| Requested iCloud environment | Production |
| Verified iCloud environment / entitlements | Production; `iCloud.com.aiity.haiity`; app and widget retain `group.com.aiity.haiity`; `get-task-allow=false` |
| Release workflow | Manual archive/export and install attempt; no automatic app launch or device tests |
| Artifact directory | `/Users/enricomini/Documents/haiity-verification/notification-device-20261007` |
| Archive status / path | PASS, exit 0 / `notification-device-20261007/Haiity.xcarchive` |
| Export status / path | PASS, exit 0 / `notification-device-20261007/export/Haiity.ipa` |
| Code-signature verification | PASS; deep/strict verification; both provisioning profiles include the paired phone |
| Prepared app binary UUID | `3B6DC689-42F8-3B9F-9FE9-F0FB618EEDAC` (archive and export match) |
| Prepared widget binary UUID | `7FB599F9-EBD1-3598-AFBF-8695D7BACF5B` |
| IPA SHA256 | `09342c30ea8d5d7beb212728c05b7e5581870f5433df911b6409e74aabf3a65c` |
| Install status / time | BLOCKED; attempt exit 1, CoreDevice error 4016; no transfer or launch |
| Installed UUID | PENDING |
| Installed build / fingerprint binding | PENDING |
| Target phone | Paired iPhone Air; unavailable via devicectl |
| Availability gate | Connect to this Mac mini and unlock; accept Trust if prompted; keep hAiity closed |
| Session operator / start / end | PENDING / PENDING / PENDING |

| Local evidence | Pass | Fail | Skipped | Runtime warnings |
| --- | --- | --- | --- | --- |
| Fresh NotificationActionTests | 22 | 0 | 0 | 0 |

Local tests do not establish physical behavior. All physical checks remain
NOT RUN until directly observed. Unavailability is a blocker, not a failed check.
Archive/export and Production iCloud signing are verified locally. Archive has
zero error lines and four existing MLX Metal compiler warnings. Installation
failed before transfer because CoreDevice could not acquire trusted connectivity,
loaded device services and the device power assertion (error 4016). This is an
environment blocker, not a notification test failure. No phone app launch, uninstall,
data reset, TestFlight upload, commit or push was performed.
The unit clock predicate does not prove that the physical bug is fixed or failed.
Later phone-user panel testing must precede any app launch.

## Source feasibility caveat

In the current source,
[Reminders.swift](/Users/enricomini/Documents/Github/haiity/Haiity/Services/Reminders.swift:85),
`ReminderPlan.quickAction` and `notificationCategoryIdentifier` default to nil.
[dailySummaryPlan](/Users/enricomini/Documents/Github/haiity/Haiity/Services/Reminders.swift:407),
[weeklySummaryPlan](/Users/enricomini/Documents/Github/haiity/Haiity/Services/Reminders.swift:429),
and [upcomingDailyPlans](/Users/enricomini/Documents/Github/haiity/Haiity/Services/Reminders.swift:464)
do not supply either field. The
[request builder](/Users/enricomini/Documents/Github/haiity/Haiity/Services/Reminders.swift:1163)
sets a category only when one of those fields exists. The
[registered categories](/Users/enricomini/Documents/Github/haiity/Haiity/Services/NotificationPresenter.swift:24)
are habit categories, with foreground options for actions that open the app.
There is no summary background-answer button defined by these summary plans;
do not invent one or add a feature to satisfy this checklist.

Verify the actual available buttons on the installed phone before any button
test; record their labels and whether the selected action opens the app. A
summary swipe-dismiss removes that summary, keeps the app closed, and should
leave other banners/data alone. Tapping its body is a default action that opens
the app, so clearing other delivered banners is expected (tomorrow's pending
reminders should remain). See
[default-action classification](/Users/enricomini/Documents/Github/haiity/Haiity/Services/NotificationPresenter.swift:72).
Category options are empty, without custom-dismiss handling; do not assume a
summary swipe invokes the delegate or exercises background-action suppression.
Source feasibility is not an installed-phone result.

## Required cold-action order

1. Main completes archive/export/install and records the installed identity.
   Keep the app closed after installation: no app launch before panel actions.
2. Keep the app closed. Inspect a genuine delivered summary's available buttons
   and record them (none expected from current source). Swipe-dismiss only that
   summary, without tapping its body or clearing a group. Record remaining
   banners/data; unrelated banners must stay. If no genuine summary is available,
   leave this check NOT RUN and record why.
3. With the app still closed, record the genuine delivered habit banner to act
   on, other delivered banner identities/count, and the relevant real habit state.
   Verify its actual available buttons and select a non-opening action. Invoke
   that habit banner's action from the notification panel. Confirm only
   the acted-on banner is removed and unrelated banners/data are preserved.
   Do not real-open between steps 2 and 3. If no genuine eligible banner or
   non-opening button is available, leave the action check NOT RUN and record
   why; do not fabricate a fixture, reset data, or substitute a foreground action.
4. Capture remaining delivered banners and tomorrow's pending reminders without
   delaying the opening. Immediately real-open the app within 1.5 seconds of the
   last habit background panel action. Record both timestamps and the elapsed
   time between that action and opening the app, so a long wait cannot hide the existing 600 ms
   settle / 1.5 s suppression behavior. If this window is missed, record the
   actual elapsed time and leave the immediate-open check NOT RUN until observed
   with a genuine eligible banner. Confirm remaining delivered banners clear while
   tomorrow's pending reminders stay scheduled. Record real-data loading after
   the splash, including any stall and its duration.
5. Continue the remaining checks below on real data. Record the first actionable
   failure as the input to the next code change; do not invent outcomes.
6. Separately, when another genuine summary is available with the app closed,
   tap its body. Record the resulting app opening and expected clearing of other
   delivered banners; verify tomorrow's pending reminders remain. This is not
   the cold non-opening action check. If unavailable, leave it NOT RUN.

## Physical result ledger

Use exactly PASS, FAIL, or NOT RUN. Enter actual observations and written evidence
references before changing a status. Empty observation fields mean no result.

| Check / acceptance | Status | Observation fields (complete during session) |
| --- | --- | --- |
| Cold habit background button removes only acted-on banner | NOT RUN | Available button labels: pending; selected non-opening action/time: pending; targeted banner/habit: pending; delivered before/after: pending; real-data change: pending; unrelated banners/data retained: pending |
| Cold summary swipe-dismiss removes only dismissed summary; app stays closed | NOT RUN | Available buttons (none expected): pending; swipe/time: pending; targeted summary: pending; delivered before/after: pending; unrelated banners/data retained: pending; app remained closed: pending |
| Immediate real-open (within 1.5 s) clears remaining delivered; tomorrow pending stays | NOT RUN | Last habit background panel action timestamp: pending; app-open timestamp: pending; elapsed time: pending; within 1.5 s: pending; delivered before/after: pending; tomorrow reminder identities/times before/after: pending |
| Summary body tap opens app and clears other delivered banners; tomorrow pending stays | NOT RUN | Genuine summary identity: pending; body-tap/open time: pending; delivered before/after: pending; tomorrow pending before/after: pending |
| Post-splash real data loads without stall | NOT RUN | Splash end/data visible times: pending; stall duration/symptom: pending; affected screen: pending |
| One on-time notification | NOT RUN | Real reminder identity: pending; intended timestamp with timezone: pending; actual delivery timestamp with timezone: pending; delay: pending; observed banner/content: pending |
| Live Activity reflects real state and actions | NOT RUN | Real activity/state: pending; start/update/end observations and times: pending; action/result: pending |
| Second-device iCloud propagates a real change | NOT RUN | Devices: pending; real item/change: pending; origin/change time: pending; destination/arrival time: pending; final values: pending |
| Scoped Calendar OR Reminders recovery | NOT RUN | Chosen integration and bounded scope: pending; existing symptom/item: pending; recovery action: pending; actual result: pending; unrelated data preserved: pending |
| Home widgets: tint/clear appearance | NOT RUN | Widget/configuration: pending; tint appearance: pending; clear appearance: pending; legibility/data: pending |
| Widget tap and Control Center action | NOT RUN | Widget tap target/destination: pending; Control Center control/action: pending; real-data result: pending |
| Widget timeline after checkoff | NOT RUN | Real item/checkoff time: pending; widget before/after state: pending; refresh time/delay: pending |
| VoiceOver: More and habit card | NOT RUN | More labels/focus/navigation: pending; habit-card labels/state/action: pending; issue: pending |
| Sorting with long-held finger | NOT RUN | Real list/item: pending; hold duration: pending; drag/scroll/drop behavior: pending; resulting persisted order: pending |

| Physical totals | PASS | FAIL | NOT RUN |
| --- | --- | --- | --- |
| Before phone session | 0 | 0 | 14 |

## Written session outcome

- First actionable failure / exact reproduction: NOT RUN; pending phone access.
- Written observation/evidence references: pending.
- Next code change justified by that failure: pending real-phone result.
- Artifact status: archive/export/signature PASS; installation BLOCKED by CoreDevice 4016.
- Production entitlement verification: PASS on the exported signed app.
- Physical verification: NOT RUN; awaiting connected/unlocked phone.
- Account-row simplification: authorized, deferred until the real-phone pass; root auth buttons are unchanged.
- ContentView/Theme split: later work, unchanged.

## Saved evidence

- [NotificationActionTests result](/Users/enricomini/Documents/haiity-verification/notification-device-20261007/NotificationActions.xcresult)
- [Current banner-fix patch](/Users/enricomini/Documents/haiity-verification/notification-device-20261007/banner-fix.patch)
- [Signing and phone-profile summary](/Users/enricomini/Documents/haiity-verification/notification-device-20261007/signing-summary.jsonl)
- [Install failure](/Users/enricomini/Documents/haiity-verification/notification-device-20261007/Install.log)
- [Prepared IPA](/Users/enricomini/Documents/haiity-verification/notification-device-20261007/export/Haiity.ipa)

The prepared local build contains the uncommitted banner patch. It is distinct
from the already-shipped TestFlight 276 despite sharing its version/build number;
bind this session to the fingerprint, IPA hash and binary UUIDs above.
