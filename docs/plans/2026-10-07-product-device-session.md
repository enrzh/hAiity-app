# Combined product changes: device and release checkpoint

## Authorized sequence

Prepare and install the current signed product changes on the approved phone,
perform the real-device session, fix observed failures, then create the new
TestFlight release after those checks pass. The user's "do it" on 2026-10-07
authorizes this sequence. Physical checks are prerequisites, not simulator claims.

## Current source and local evidence

- Base commit: 98241c19551c653057037bc520b2b9e6b4cd2330, main with preserved dirty work.
- Source fingerprint: c7db58b6a83db4fd3b4f446f18d4c86d5f7e33a13359b4399375789627194ee1.
- Current device candidate: 1.0.0 (276); TestFlight's next unique build is determined
  separately before the later release. Do not identify this dirty binary as the
  already published 276.
- Exact-source local evidence: product-simplification-20261007/evidence.json;
  2,146 Unit and 46 Smoke passed; unsigned generic Release compilation passed.
- Signed candidate artifacts: /Users/enricomini/Documents/haiity-verification/product-device-20261007.
- This candidate includes all ten product changes plus the preserved banner fix.

## Availability gate

Xcode devicectl reports approved physical iPhone Air
00008150-000120AC0287801C as paired but unavailable. Developer Mode is cached as
enabled. This is not live device access and does not prove current installed state.
Connect and unlock the phone on this Mac mini and accept Trust if prompted.
No repeated install attempts while availability is unchanged.

## Cold-notification order

Keep hAiity closed after installation. Perform the existing cold notification
checks before any launch, app-running UI test or diagnostics collection. No
automatic launch is part of preparation or installation. Preserve real data and
unrelated delivered banners; no uninstall, reset, synthetic seeding or recording.

The existing 2026-10-07-device-session.md is retained as the notification-only
checkpoint, and its observations remain NOT RUN. Its 14 physical acceptance rows
apply to this combined candidate too. Summary notifications have no background
answer button: dismiss one summary without opening the app; a body tap opens the
app and is expected to clear other delivered banners. Pending reminders must stay.

## Results

| Gate | Status | Evidence |
| --- | --- | --- |
| Source-bound local verification | PASS | product-simplification-20261007/evidence.json |
| Signed archive | PASS | Archive.xcresult / Archive.log; exit 0; 4 existing MLX warnings; 0 errors |
| Release-testing export with Production CloudKit | PASS | Export.log; exit 0; app Production iCloud entitlement verified |
| Signature, version and phone-profile checks | PASS | signing-summary.jsonl; deep/strict codesign validation; both valid profiles include the approved phone |
| Installation and installed binary identity | NOT RUN | Phone remains unavailable in the post-export devicectl check; no transfer or launch attempted |
| Cold notification panel / immediate real-open | NOT RUN | Needs real phone and delivered banners |
| Real-data startup, scroll and switching | NOT RUN | Needs direct physical observations |
| Creation, flexible week, Today/history/Edit, swipe and undo | NOT RUN | Needs direct physical observations |
| Notification timing, Live Activity and native recovery | NOT RUN | Needs real services |
| Widgets, Control Center and timeline | NOT RUN | Needs installed Home Screen widgets |
| Second-device iCloud | NOT RUN | Needs second device and a scoped real change |
| VoiceOver and held-finger sorting | NOT RUN | Needs direct physical observations |
| New TestFlight release | PENDING | After device checks and fixes; new build/evidence required |

Preserve this concrete preparation and resume from installation when the phone
becomes available. Do not repeat successful local tests merely because the phone
is unavailable, and do not publish a passing simulator result as physical proof.

## Prepared artifact identity

- IPA: /Users/enricomini/Documents/haiity-verification/product-device-20261007/export/Haiity.ipa
- Exported installable app: product-device-20261007/exported-app/Payload/Haiity.app
- IPA SHA256: 08f1ddefd4ef58caec2accbb35927ae1dadb0cd5211600792f372289bf473a97
- App binary UUID: 48693F2D-DD69-31D4-8191-D0D9239AA038
- Widget binary UUID: 795A3215-F45E-3F2F-8BC3-F80A874CEE67
- Exported and archive binary UUIDs match. Both bundles report 1.0.0 (276).
- App has Production CloudKit and the existing shared App Group; the widget
  retains its existing App Group-only boundary, with no direct CloudKit entitlement.
- Both provisioning profiles include the paired iPhone Air and remain valid.
  The release-testing export has get-task-allow=false in both bundles.
- Source-bound local evidence revalidated after archive/export: unchanged
  fingerprint c7db58b6a83db4fd3b4f446f18d4c86d5f7e33a13359b4399375789627194ee1.

No app launch, phone tests, uninstall, data reset, TestFlight upload, commit or
push was performed. The physical session and subsequent TestFlight release are
authorized but blocked on phone connectivity and actual device observations.
