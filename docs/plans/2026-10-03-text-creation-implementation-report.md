# Text Creation Implementation Report

Date: 2026-10-03
Baseline: `main`, `29770e55494fca551f8f5d5d464ebbfd424af730`
Release metadata: 1.0.0 (272), unchanged
Status: implemented and locally verified; hardware gates pending

## Changes

- `CreateSentenceFacts` recognizes complete numeric dates before clock times,
  including space-separated dates, ISO dates and locale-aware separator forms.
  Invalid/incomplete dates are reserved so their fragments cannot become times.
  Leap days, explicit past years, conflicting values and quantity/duration
  numbers are validated without changing the requested date silently.
- Explicit facts take precedence in the deterministic, Foundation Models, MLX
  and text App Intent paths. Model-only dates are validated and converted to
  the storage calendar once. Both prompts include the captured reference
  date/time, timezone and locale, and delimit the sentence as user data.
- `10 Uhr`, `10Uhr`, `um 10`, clock forms and bounded German spoken hours work
  without a model. Midnight/noon AM/PM boundaries are correct. One-off and repeat
  cues use word boundaries so names such as `Concentrate` remain habits.
- Daily and weekly recurrence preserve an explicit start date. Creation rejects
  invalid drafts before writing and still uses the existing observed store,
  coordinated persistence, Pro allowance and notification rescheduling.
- The sheet shows the full localized date, time/all-day state and schedule.
  It saves the displayed draft; an unread model result returns to review first.
  Edits, dismissal, changed locale/timezone and midnight invalidate stale reads.
- The inline microphone uses Apple Speech/AVFoundation with on-device support,
  permissions only after a tap, serialized sessions, idempotent audio cleanup,
  final-result handling and preservation of the existing sentence. Queued starts
  cannot revive recording after cancellation, and resuming editing waits for
  finalization. No audio files, transcript logs or new dependencies are added.
- The input grows from one line and the introduction disappears after entry.
  Keyboard/dock spacing keeps the schedule readable. The existing surfaces,
  native text editing and Reduce Motion handling are retained.
- New labels/errors and microphone/speech purpose strings cover German and all
  16 target UI languages. The design guide reflects the inline microphone.

## Verification

The final source-bound Unit/Smoke run is in
`/tmp/haiity-text-create-verified.CpnjQA`. Its `evidence.json` records the final
source fingerprint, Xcode/SDK/generator identity, build metadata and xcresults.
Xcode 27.0 (27A266a), iOS SDK 27.0, pinned XcodeGen 2.46.0 were used.

| Final check | Result |
| --- | --- |
| Unit, iPhone 18 Pro / iOS 27 simulator | 2,120 passed, 0 failed, 0 skipped |
| Smoke, same simulator | 15 passed, 0 failed, 0 skipped |
| Compact English/Arabic photo scenario, iPhone SE / iOS 27 | 1 test with both locale scenarios passed, 0 failed, 0 skipped |
| Unsigned generic iOS Release build, final app source | Exit 0 |
| Source-bound evidence revalidation | Passed |
| XcodeGen generation and whitespace check | Passed |

Final source fingerprint:
`ec3d88fa6853c86365edd750b3a21269aa6575018d12e825d769aa55e6bc4685`.
The implementation remains uncommitted on the baseline HEAD; the fingerprint
includes changed and untracked source. It is not evidence of a deployed build.
Final Release log: `/tmp/haiity-text-create-release-final.6rhaP4/Release.log`.
The upstream MLX compilation emits existing C++17 extension warnings; they do
not fail the build.

Completed supporting checks:

- Focused native Xcode checks: 151 tests passed before the final review fixes.
- Earlier full native gate: 2,119 Unit and 14 Smoke tests passed, zero failures
  or skips. Additional locale coverage and one-off word-boundary tests were
  added afterward, so those earlier results are not the final evidence.
- Compact iPhone SE (3rd generation), iOS 27: the English/light and Arabic/dark
  photo scenarios passed. Assertions cover the 44 pt inline microphone, RTL
  placement, clock/date preview above the floating dock and absence of permission
  prompts while opening/typing. Result:
  `/tmp/haiity-text-create-compact.3vgo5r/Compact.xcresult`.
- Screenshots inspected for the German date preview with the keyboard open,
  finalized dictation, and dark/solid appearance at largest Dynamic Type.
  English/light and Arabic/dark photo screenshots were also inspected on the
  compact phone; the localized date remains visible above the dock and the
  inline microphone follows RTL direction. Screenshots are retained with their
  xcresult attachments.
- 41 creation/dictation labels checked across all 17 UI languages. Both permission
  purposes were verified in all 17 built simulator language bundles.
- Release-evidence validation checks passed all 16 rejection cases. XcodeGen
  2.46.0 generation and whitespace checks passed.

The first focused UI pass exposed two test assumptions: editing after tapping
places the caret where tapped, and save/dismissal is asynchronous. Tests now
verify retained/editable text and wait for dismissal. Integration review also
fixed the queued-start/final-transcript races and the initial preview crowding.
An intermediate verification run was deliberately interrupted after the final
one-off cue fix; it is not treated as passing evidence.

## Limits and Remaining Gates

- Real microphone accuracy, native first-use/denied permissions, actual offline
  recognition support, final-result latency and Bluetooth/interruption behavior
  require physical-device verification. Simulator dictation fixtures exercise
  interaction/lifecycle rules, not microphone recognition quality.
- Actual Foundation Models/MLX extraction quality still needs the supported
  device/model corpus. Controlled outputs verify date/time precedence; they do
  not prove arbitrary natural-language recognition or every spoken time form.
- Reduce Motion was reviewed in the implementation: custom scroll animation is
  disabled when requested; no waveform or audio-buffer animation loop exists.
  VoiceOver labels/state values and semantic RTL layout are retained. A manual
  screen-reader review on a physical phone remains appropriate before release.
- No existing habit/history/settings schema, StoreKit, widgets, cloud/native
  sync system or dependency/version was changed. No user data was reset.
- No commit, push, phone installation, TestFlight upload or App Store Connect
  action occurred. A release requires a separately authorized build/version
  change, commit and verification of that exact release state.
