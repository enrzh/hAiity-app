# Reliable Text Creation and Inline Dictation

Date: 2026-10-03
Status: implemented and locally verified; device checks pending
Inspected baseline: `main`, `29770e55494fca551f8f5d5d464ebbfd424af730`, build 272

## Goal

Typing or dictating a sentence should produce the correct habit or reminder,
with the stated date and time visible before saving. Add a microphone button
inside the creation input, using supported Apple speech APIs.

Keep the existing sheet, draft types, Foundation Models/MLX readers, recurrence
engine and `CreateItemSaver`. No new dependency, general parsing framework,
onboarding flow or background model work. This plan does not initiate a build,
device installation or TestFlight upload.

## Findings From the Current Code

1. `CreateItemDraft.stripTime` already recognizes lowercase `10 uhr`. A direct
   Swift probe of the current function returned 600 minutes. The reported
   problem therefore needs end-to-end regression coverage, not another rule
   that duplicates its existing time pattern.
2. There is no shared deterministic numeric-date parser. `namedDayKey` handles
   relative words such as `morgen`, but not `15 10 2026`. Numeric dates are left
   for the model, and the no-model path leaves them in the name.
3. Dates and times collide. The same probe returned 910 minutes (15:10) and
   the name `Zahnarzt .2026` for `Zahnarzt 15.10.2026 10 uhr`. The date is
   mistaken for the first clock time, which also overrides the actual 10:00.
4. Explicit-time precedence differs between readers. `CreateItemDraft.read`
   prefers the sentence's time; `DraftExtraction.parse` instead overwrites its
   deterministic fallback with any accepted model time. A downloaded model can
   therefore change a stated `10 Uhr` to another time.
5. The current time parser turns `12 AM` into 12:00 rather than 00:00.
   `zehn Uhr` is not recognized, which matters when speech returns number words.
6. The live sheet preview only strips the time. Its subtitle does not show an
   exact start date. `create()` can interpret an unread sentence and immediately
   save that new result, so the saved schedule can differ from the preview.
7. `CreateItemSchedule.recurrence` rolls past one-off dates forward and omits
   `startDay` for daily/weekly rules. A supplied full date must not change year
   silently, and a recurring habit with an explicit start needs that anchor.
8. Both model request builders omit the current date/timezone context. Relative
   dates should not depend on a model guessing which year or day it is.
9. Custom speech recognition was intentionally removed in commit `7ad65c1`.
   The current sheet, privacy keys, design guide and tests explicitly enforce
   keyboard-only dictation. The newly requested inline microphone changes this
   contract; update those parts together instead of merely adding an icon.

Relevant code: `Haiity/Intents/CreateHabitIntent.swift`,
`Haiity/Services/DraftExtraction.swift`, `Haiity/Services/CreateItemWriter.swift`,
`Haiity/Services/LocalModelSentenceReader.swift`, and
`Haiity/Views/SpeakToCreateSheet.swift`.

## 1. Parse Explicit Dates Before Times

Extend the existing deterministic draft helpers rather than introducing a
second parser per reader. One small result should carry recognized values,
their text ranges and any actionable validation issue.

- Recognize `DD MM YYYY`, including repeated spaces and pasted nonbreaking
  spaces. Accept German `DD.MM.YYYY`, `DD/MM/YYYY`, `DD-MM-YYYY`, and the
  unambiguous ISO form `YYYY-MM-DD` as well.
- Find complete date spans before searching for times. Reserve even invalid
  date candidates so `31.02.2026` cannot be salvaged as a clock fragment.
  Remove only successfully interpreted spans from the proposed name.
- Validate real calendar dates with Foundation `Calendar`/`DateComponents`
  and strict round-trip checks, reusing `DayKey` where appropriate. Reject
  impossible dates instead of normalizing them into another month.
- Treat these Gregorian numeric formats explicitly and convert to the existing
  storage/calendar convention when necessary. Do not assume all users have a
  Gregorian system calendar, and do not migrate stored day keys.
- Space-separated `DD MM YYYY` stays day-first as requested. Separator-based
  ambiguous dates follow the explicitly resolved input locale: German DMY,
  US English MDY. Show the interpreted date with a month name in the preview.
  Do not infer date order from a model's response or silently try both orders.
- Use the existing effective timezone policy (`HabitTimeZone` plus the store's
  default) and pass a captured `now`, calendar and input locale through the
  interpretation. Relative dates use calendar-day addition, not 24-hour offsets.
- Without a repeat instruction, a particular date means a one-off reminder.
  With an explicit repeat, retain the repeat and use the date as its start.
  Ensure daily/weekly conversion preserves that start rather than dropping it.
- Preserve a stated four-digit year. A past explicit date produces a correction
  message before saving, not an automatic move to next year or today. Keep the
  existing next-occurrence policy for yearless dates separate from this case.
- Incomplete or conflicting dates remain editable with a concise inline hint.
  Do not save a daily item while silently ignoring a requested date.

Start with the explicit formats above. `NSDataDetector` may supplement prose
dates only if its behavior is reproducible for the supported locales; it must
not replace the explicit format/precedence rules. Do not build a general
natural-language grammar.

## 2. Make Time Recognition Consistent Across Readers

- Keep the existing `10 Uhr`, `10 uhr`, `10Uhr`, `um 10`, `10:30`, `10:30 Uhr`,
  dotted clock and AM/PM forms. Match complete tokens, excluding reserved date
  spans and quantity/duration phrases such as `10 Minuten` and `10 reps`.
- Correct AM/PM boundaries: `12 AM` is 00:00 and `12 PM` is 12:00. Reject
  invalid hours/minutes without accepting a valid substring inside them.
- Add bounded German spoken-hour normalization, such as `zehn Uhr`, only in
  clock context. Cover the actual transcripts observed on a device before
  adding less clear phrases such as regional half-hour expressions.
- Apply the same explicit-value merge to the deterministic fallback,
  Foundation Models, downloaded MLX output and text App Intent. An explicit
  valid date/time wins over a conflicting model result. An invalid explicit
  value remains an error; it is not permission for the model to invent one.
- Do not let the model invent a time where the sentence contains no time cue.
  Preserve existing behavior for genuinely unspecified scheduling.
- Add locale, captured current date and effective timezone to both existing
  model requests. Delimit the sentence as user data and include examples for
  numeric dates, `10 Uhr`, one-offs and repeats with a start date.
- Reuse one interpretation of the input for the live preview and final draft.
  Keep model inference behind the existing deliberate read action; never run
  it per keystroke or speech partial result.

Multiple conflicting dates/times should request correction, not silently
discard later values. Keep the existing multiple-notification settings intact;
parsing several notification times from one sentence is outside this plan.

## 3. Make the Preview Match What Is Saved

Retain the existing input card, preview and floating primary action. Improve
their content rather than redesigning the whole sheet.

- Show the proposed name, item type, exact date/start date, clock time or
  all-day state, and repeat rule in a compact, readable preview.
- Explicit dates/times should appear immediately without a model or download.
  Use localized date formatting so the month/year cannot be misread.
- Surface invalid/ambiguous input next to the field and keep the sentence.
  Avoid large alerts or toasts for ordinary correction.
- Save only the draft shown for that exact sentence. If pressing create still
  requires an interpretation, show its completed preview for confirmation
  instead of saving an unseen result. An already reviewed or complete
  deterministic draft needs no extra inference or confirmation cycle.
- Reuse `readFrom` to invalidate drafts after edits or dictation updates.
  Check the sentence again after an await; discard stale results. Permit one
  in-flight read/save, and prevent creation while recording/finalizing speech.
- Continue saving into the sheet's existing store via `CreateItemSaver`.
  Keep write errors, Pro limits and rescheduling behavior intact.
- For the text App Intent, which has no preview, invalid/conflicting scheduling
  must return a useful correction dialog without writing an entry.

## 4. Put a Working Dictation Button Inside the Input

### UI and Interaction

- Add a small SF Symbols `mic` button at the trailing edge inside the input
  card's editing area. Reserve its space so long/multiline text cannot overlap
  it. Use a 44 by 44 pt touch target and the existing theme/surface styling.
- First tap starts dictation; another tap stops and finalizes it. Show a
  preparation indicator, then a stop symbol and the short status `Diktiert...`.
  Preserve a text/state cue in addition to color.
- Keep typing, paste and the keyboard's own dictation available. Starting
  in-app recording dismisses keyboard focus; manually resuming editing stops
  recording first, avoiding concurrent dictation sessions.
- Capture the existing sentence when recording starts. Append the session's
  current transcript to it, replacing only that session's partial text so
  partial results do not duplicate words or erase the existing sentence.
  Stop/finalize before allowing manual edits to the same text.
- Keep the recorded text editable; dictation never automatically creates an
  entry. Repeated sessions append predictably, and failed sessions retain the
  last usable text.
- Provide VoiceOver labels for start/stop and state changes, Dynamic Type,
  right-to-left placement, dark/solid/image appearances and Reduce Motion.
  No waveform, decorative panel or recording animation loop is needed.

Apple design references used: `text-fields.md` / Mobile recommends the trailing
end for additional features; `buttons.md` / Best practices specifies a 44x44 pt
hit region; `privacy.md` / Requesting permission calls for contextual requests;
`accessibility.md` / Vision and Mobility covers labels, non-color cues and sizing.

### Supported Apple Implementation

There is no public API for an app button to launch the system keyboard's
dictation key. UIKit exposes dictation-result callbacks, not a start command.
The button therefore uses Apple speech recognition; it must not masquerade as
a keyboard shortcut that merely focuses the field.

- Use `Speech` and `AVFoundation`, already part of iOS, with one small
  sheet-owned service. The app supports iOS 18+, so `SFSpeechRecognizer` is the
  minimal shared implementation. A separate iOS-26-only speech engine or
  automatic speech-model download is unnecessary.
- The removed `SpeechDictation.swift` is a useful reference for audio teardown,
  not a file to restore wholesale. Omit waveform amplitude calculation,
  per-audio-buffer UI tasks and unused compatibility branches.
- Request speech and microphone permissions only after a microphone tap.
  Add clear localized purpose strings in authoritative `project.yml` and its
  generated Info.plist. Never request these permissions when the app or sheet
  opens, or when the user types/reads/saves a sentence.
- Resolve a supported recognition locale deliberately. Require on-device
  support before setting `requiresOnDeviceRecognition`; do not silently switch
  to remote recognition. If unavailable, offer typing/system keyboard dictation
  with an honest inline explanation. Verify actual locale/device availability.
- Stop audio capture, remove the installed tap exactly once, release recognition
  resources and deactivate the audio session on dismissal, backgrounding,
  interruption, permission denial, startup failure and normal completion.
  Normal stop must allow the final transcript to arrive; cancellation must
  ignore late callbacks. Ignore late permission results after dismissal too.
- Serialize start/stop so rapid taps cannot install duplicate audio taps or
  resurrect a canceled session. No background recording, stored audio files,
  transcript logging, cloud transcription service or private selectors.

## 5. Verification and Acceptance

Use a fixed test clock of 2026-10-03 in Europe/Berlin unless the test explicitly
sets a different calendar/timezone. Model-output tests use controlled responses,
not probabilistic inference as their assertion oracle.

| Input / situation | Required result |
| --- | --- |
| `Zahnarzt 15 10 2026 10 uhr` | Reminder, 15 October 2026, 10:00; date/time removed from name |
| `Zahnarzt 15.10.2026 10 Uhr` | Same result; never 15:10 |
| `Zahnarzt 15/10/2026 um 10` or `15-10-2026` | Same German-locale date/time |
| `Zahnarzt 2026-10-15 10:30 Uhr` | Reminder, 15 October 2026, 10:30 |
| `Lesen 10 uhr`, `10Uhr`, `um 10` | 10:00 in the preview and saved item on every reading path |
| `Lesen zehn Uhr` | 10:00 for the bounded German spoken-hour form |
| `Call at 12 AM` / `12 PM` | 00:00 / 12:00 |
| `29 02 2028` / `29 02 2027` | Leap-day accepted / invalid date reported |
| `31.02.2027`, `25:00`, `10:99` | Correction required; no guessed/clamped schedule saved |
| `10 Minuten lesen`, `3 sets at 10 reps` | Quantity/duration preserved; no 10:00 notification invented |
| `Zahnarzt 15 10 2026` | One-off reminder, all day |
| `Jeden Tag ab 15 10 2026 um 10 lesen` | Daily habit, starts 15 October, 10:00; not a one-off |
| `morgen um 10`, `jeden Morgen lesen` | Tomorrow's reminder / recurring habit remain distinct |
| `Zahnarzt 15 09 2026` | Past explicit date reported; never silently moved to 2027 |
| `03/04/2030`, de-DE / en-US | 3 April / March 4, clearly written in the preview |
| Model returns 09:00 for a sentence saying 10:00 | Explicit 10:00 survives |
| Model returns a different year or daily for a one-off date | Explicit date and one-off classification survive |
| Text changes during reading/dictation | Old draft cannot be displayed as current or saved |
| Microphone denied/unavailable/interrupted | No crash or text loss; typing still works; recording stops |

Focused checks to add/update:

- Extend `CreateHabitIntentTests` and `DraftExtractionTests` with the shared
  date/time matrix, model conflicts, locale/timezone boundaries, incomplete
  input, multiple conflicting values, and explicit-year behavior. Assert the
  resulting `Habit` recurrence/time as well as the intermediate draft.
- Replace the obsolete no-microphone assertions in `VoiceCreateSheetTests`
  with contextual-permission/lifecycle contracts. Test transcript accumulation,
  cancel during permission acquisition, stale callbacks and idempotent cleanup
  with a minimal controllable seam; do not add a speech provider framework.
- Extend `SpeakToCreateDockUITests` for the inline button's placement/44 pt
  target, preview date/time, validation, editing and the existing dock. Add a
  focused typed-input regression to `TestPlans/Smoke.xctestplan` so the normal
  gate actually runs it. Use deterministic UI test input for speech states.
- Include small-screen, large Dynamic Type, German/English, right-to-left,
  light/dark, solid/image appearance, VoiceOver and Reduce Motion review.
- After implementation, run focused tests, then the existing Unit and Smoke
  gate via `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash
  tools/verify.sh`, and an unsigned Release build. Follow `docs/development.md`
  and retain revision-bound xcresults; do not use `release.sh` for mere checks
  because its local workflow can install on a phone.
- Keep real microphone quality, first-use/denied permissions, offline German
  dictation, interruption/Bluetooth routes and both model readers as explicit
  physical-device gates. Simulator text/state tests do not prove these passed.

## Execution Order

1. Add reproductions for date/time collision and conflicting model output.
2. Implement the shared explicit date/time parsing, validation and precedence.
3. Connect preview, both readers, start-date conversion and the text App Intent;
   make the displayed draft the saved draft.
4. Add the inline microphone and minimal Apple speech lifecycle/permissions.
5. Update tests, localization and the design guide's keyboard-only contract;
   regenerate the project with the pinned XcodeGen workflow if needed.
6. Run local verification, inspect the input/preview UI and record outstanding
   device checks separately. Release/upload remains a separately requested action.

## Evidence Collected for This Plan

Source and existing tests were inspected, including the removed speech service
in Git history. The current `stripTime` function was executed unchanged in a
Foundation-only Swift probe: ten cases completed with exit code 0, reproducing
the dotted-date collision, missing spoken-hour recognition and 12 AM error.
These are diagnostic observations, not passing regression tests. Installed
iOS 27 UIKit/Speech headers were checked for supported API behavior. No app,
unit/UI suite or physical microphone test was run for this planning-only task.
At the planning checkpoint only this Markdown file was added; the user later
authorized implementation. Release metadata remains unchanged.

## Implementation Checkpoint

- Date-first recognition and strict validation are shared by preview, both
  readers and the text App Intent. Explicit values win; daily/weekly start dates
  survive conversion, and impossible model dates are rejected too.
- The preview shows a localized full date, time/all-day state and recurrence.
  Creation saves the displayed draft. Invalid input, missing names and stale
  interpretations cannot be written.
- The input includes a native Apple Speech microphone with contextual
  permissions, partial/final transcript handling, on-device availability,
  cancellation and audio-session cleanup. The input grows from one line;
  the introduction disappears after entry so the schedule stays accessible.
- German and all 16 target UI languages include the new status/validation
  messages and both permission purpose strings.
- Focused native Xcode checks passed 151 tests before the final integration
  review. The review then fixed two start/finalization races, a model-date
  validation gap and one-off cue substring matching. The final native gate
  passed 2,120 Unit tests and 15 Smoke tests with zero failures or skips.
  Compact English/Arabic/photo scenarios and the unsigned Release build passed.
  See [the implementation report](2026-10-03-text-creation-implementation-report.md)
  for exact evidence and the source fingerprint.
- Device-only gates remain real microphone quality, native first-use/denied
  permissions, offline recognition availability, audio interruptions/Bluetooth,
  and actual Foundation Models/MLX inference quality. Simulator fixture speech
  covers the app's interaction contract, not these hardware capabilities.
- No phone installation, commit, push, TestFlight upload or App Store action
  is part of this implementation turn.
