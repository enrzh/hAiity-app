# Prompt and Process Hardening Plan

Date: 2026-10-01
Status: implemented; focused checks pass; physical-device model paths remain unverified
Baseline: `main`, build 268 (`4f7ecf6`), with existing user changes preserved

## Goal

Make the app's existing sentence-to-entry and on-device writing flows
predictable, understandable, and testable. This is reliability work, not a new
AI feature or a prompt-framework project. Keep the feature set frozen and reuse
the current MLX, Foundation Models, deterministic parsing, persistence, and
`CreateItemSaver` paths.

## Current Flow

- **Create from a sentence:** the user edits a sentence in `SpeakToCreateSheet`;
  tapping “Satz lesen” uses a downloaded MLX model when present, otherwise
  Foundation Models when available, then the deterministic time/one-off parser.
  The draft is previewed and saved through the shared `CreateItemSaver`. App
  Intents also use `CreateItemDraft.read` and that same saver.
- **Motivation:** the on-device writer generates a bounded sentence; a 14-day
  local cache is shared by the app, notifications, and Live Activity. Reminder
  rescheduling reads cached lines and does not invoke the model.
- **Statistics reading:** the model is called only after an explicit tap. The
  result is validated and stored once per day; reopening Statistics reads the
  cache without another model call.
- **Speech input:** the current sheet uses a real text field and the system
  keyboard's own dictation. The staged deletion of `VoiceWaveform.swift` is
  already in the user's worktree; this plan does not restore the custom mic.

## Findings

### P1: Sentence reading can be offered but hidden

`SpeakToCreateSheet.canRead` allows either Foundation Models or a downloaded
model (`Haiity/Views/SpeakToCreateSheet.swift:76`), but `draftPreview` renders
the “Satz lesen” control only when Foundation Models is available
(`SpeakToCreateSheet.swift:261`). A device with a downloaded MLX model but no
Foundation Models capability can satisfy the first check and still have no
visible read action. The source-contract test currently checks `canRead`, not
that the control is present in this state.

Minimal fix: use one existing capability expression for the actual read control
and its “not read yet” copy. Add a view-contract or UI test for local-model-only,
Foundation-Models-only, and neither-available states.

Acceptance: if either reader can run and the sentence is nonempty, the read
button is visible and enabled; if neither can run, no dead button is shown and
deterministic preview/create remains available.

### P1: CreateItemWriter ignores the requested language

`CreateItemDraft.read` passes a language into `CreateItemWriter.draft`
(`Haiity/Intents/CreateHabitIntent.swift:501`), and the writer's instructions
say the sentence language is named in the request. But `CreateItemWriter.draft`
currently sends only `"Sentence: …"` to Foundation Models
(`Haiity/Services/CreateItemWriter.swift:122`). The `language` parameter is
unused; the German examples can bias output for other locales.

Minimal fix: include the requested language explicitly in the request, using a
small pure request-builder function that can be tested without Foundation
Models. Do not add a general prompt templating layer.

Acceptance: tests verify that German and English language identifiers are
present in the exact request passed to the model, while the source sentence is
preserved as user data and existing one-off/time guardrails remain in force.

### P1: Statistics number checks do not validate number-to-fact mapping

`StatsReadingValidator` currently accepts any output number that appears
anywhere in `StatsReadingFacts.numbers` (`Haiity/Models/StatsReadingFacts.swift:51`
and `:119`). If several facts share values, a sentence can attach a valid number
to the wrong label and still pass. The validator's current guarantee is “no
unknown number,” not “each claim is factually correct.”

Minimal fix: tighten the output contract only if a small, deterministic rule
can validate the relationship. Otherwise use safe templated phrases for numeric
claims and let the model vary only nonnumeric wording. Never add a larger model
or a second validation framework.

Acceptance: adversarial tests cover swapped values, repeated equal values,
grouped digits, and a valid sentence. A wrong association must be rejected or
rendered by a deterministic template.

### P2: Cached Statistics reading can outlive the facts it describes

`StatsReadingStore` keys the reading by day only (`Haiity/Services/StatsReadingWriter.swift:79`),
and the view restores it by day (`Haiity/Views/StatsView.swift:466`). A check-off
or habit edit later the same day can change totals while the old sentence stays
visible. The once-per-day policy correctly avoids rerunning the model on every
render, but it currently has no way to tell whether the underlying snapshot
changed.

Minimal fix: persist a compact signature of the exact permitted facts alongside
the reading. Invalidate on mismatch; generate again only after the user taps,
not during page opening or ordinary refresh. Decode older cache entries safely.

Acceptance: same facts reuse the reading; changed facts do not show stale text;
reopening without changes causes zero model calls; old persisted entries do not
break loading.

### P2: Habit names enter the Statistics prompt as raw prompt text

`StatsReadingFacts.promptFacts` inserts `strongestHabitName` inside quotes
(`Haiity/Models/StatsReadingFacts.swift:68`). Names are user-controlled and can
contain quotes or line breaks, so they can blur the boundary between facts and
instructions. Inference is on-device, but the prompt should still treat stored
text as data.

Minimal fix: encode or delimit the name unambiguously and tell the writer that
the value is data, never instructions. Add tests with quotes, newline, and a
name that resembles a prompt directive. Do not log the raw name or prompt.

### P3: Two small prompt/process cleanups

- `StatsReadingWriter.instructions` contains an accidental run of spaces in
  “pattern over     time” (`StatsReadingWriter.swift:40`). Correct it and add a
  tiny assertion against the rendered instruction string.
- `SpeakToCreateSheet.stopEverything()` is empty after the custom speech
  recognizer was removed (`SpeakToCreateSheet.swift:479`). Remove the no-op and
  its calls only after confirming no close/create lifecycle behavior depends on
  it. Keep `localReader.release()` on dismissal.

## Execution Order

1. Fix the model-capability/read-button mismatch and add the missing state test.
2. Pass and test the explicit sentence language in the Foundation Models request.
3. Harden Statistics fact validation and cache freshness with focused pure tests.
4. Delimit user habit names in prompts and clean the Statistics instruction text.
5. Remove the empty recognizer-era cleanup hook if reference search confirms it
   has no behavior.
6. Run the full German unit suite, focused UI tests, and a Release build. On a
   physical iPhone, verify an unsupported device, supported device with model
   unavailable, downloaded MLX selection, Foundation Models selection, text
   editing before save, cancellation during read, and notification/Live Activity
   fallback. These hardware/model states were not proven by source tests.

## Guardrails

- Preserve habit history, recurrence, reminder delivery, Search, appearance,
  widgets, and existing settings placement.
- Do not add a prompt framework, model provider, model download, permission, or
  automatic generation path.
- Keep sentence generation explicitly user-triggered; no model call on sheet
  open, Statistics page open, or notification reschedule.
- Never include transcript text or habit names in diagnostics or logs.
- Keep the current dirty/staged work intact, especially the staged removal of
  `VoiceWaveform.swift`; do not reset, stash, or clean the worktree.
- This plan does not authorize implementation, commit, TestFlight upload, or
  App Store submission.

## Implementation Notes

- The sentence reader control and preview now share one capability check for
  Foundation Models or a downloaded MLX model.
- The create request includes the requested language and quotes the sentence as
  data; focused tests cover German and embedded newlines.
- Statistics prose receives qualitative facts only and the validator rejects
  output containing numeric characters, avoiding digit-to-label mismatches. Habit names remain
  quoted data.
- The follow-up whole-app polish adds cancellation/freshness checks after
  generation, rejects Unicode/oversized numeric strings without conversion and
  keeps error logs free of model-response content. See the follow-up plan for
  its broader UI, performance, and verification evidence.
- Statistics cache entries include a SHA-256 signature of facts and language.
  Changed facts hide the old reading without generating automatically. Legacy
  entries decode safely and are treated as cache misses.
- Removed the empty recognizer-era cleanup hook; dismissal still releases the
  downloaded local reader.
- `xcodebuild test` passed for `StatsReadingTests`, `CreateHabitIntentTests`,
  and `VoiceCreateSheetTests` on iPhone 18 Pro / iOS 27.0. An initial attempt
  named an unavailable iPhone 17 Pro simulator and did not run tests.
- Release builds passed for generic iOS Simulator and generic iOS device with
  signing disabled. Existing MLX C++17 extension warnings remain.
- Physical-device checks for model availability, downloaded-model selection,
  cancellation, and notification/Live Activity fallback still require a device.

## Execution Prompt

> Implement `docs/plans/2026-10-01-prompt-and-process-hardening-plan.md` in
> `/Users/enricomini/Documents/Github/hAiity`. Inspect current Git state and
> source first; preserve all existing staged, unstaged, and untracked work.
> Follow the plan in order with the smallest changes possible. Do not add a
> prompt framework or model provider. Add focused tests for the exact
> capability, language, validator, cache, and prompt cases. Run the German unit
> suite, affected UI tests, and Release build. Report hardware/model paths that
> remain unverified. Do not commit, push, or upload without a separate request.
