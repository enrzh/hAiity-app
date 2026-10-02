# hAiity engineering guide

This is the current development and release contract. Dated plans/specs are
historical context; their device IDs, build numbers and commands can be stale.

## Build

- iPhone, portrait, iOS 18 or later. The app has 17 UI localizations.
- Full Xcode is required; on this Mac use
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- XcodeGen is pinned by `.xcodegen-version` to 2.46.0. Run
  `bash tools/generate-project.sh`; incompatible generators fail closed.
- `project.yml` is authoritative. `project.pbxproj` is a tracked generated
  snapshot: regenerate and review its diff, never hand-edit it.
- `Package.resolved` pins the dependency graph. Build without package/macro
  validation bypasses. Review dependency changes deliberately.
- Xcode Cloud bootstraps missing/incompatible XcodeGen from immutable revision
  `8445e778451c7e44237b90281bde622d764b0084`, not the latest Homebrew formula.

## Ownership

- HabitStore owns local persistence and existing CloudKit union/metadata merge
  rules. The app, widgets and App Intents share its App Group JSON file.
- Coordinated atomic saves compare the exact bytes originally read. A stale
  writer fails explicitly, restores the durable snapshot and can retry. It must
  not silently overwrite another process. This is not a new sync system.
- Failed creation/editing stays editable; intents report errors. Notification
  rescheduling follows a successful durable save.
- Notification actions report failed writes, and Live Activity completion keeps
  its session available for retry. A rejected local merge aborts CloudKit
  conflict retry before uploading a restored or incomplete snapshot.
- ContentView owns navigation, presentation and lifecycle integration hooks.
  Tab-bar measurement lives in TabBarPlatterReader, with caller-owned state.
- MoreView owns the settings hub and its bindings. AboutView is a complete
  separate page, retaining its own ephemeral state and existing store dependency.
- Theme/shared UI components own visual roles. Reuse native controls and the
  current design system; add no general coordinator or component framework.

## Tests

The Haiity scheme has three native test plans:

| Plan | Purpose | Destination |
| --- | --- | --- |
| Unit | Full German unit suite | iPhone simulator / CI |
| Smoke | Search, graph/history, reminder editing, settings navigation | iPhone simulator / CI |
| Device | Existing physical-safe subset | Explicit physical iPhone |

Run `bash tools/verify.sh` for Unit and Smoke. Set TEST_DESTINATION to a chosen
simulator and VERIFY_OUT to a fresh output directory if needed. Outputs include
logs, xcresults and evidence.json. Skips, failures and suspiciously small test
counts fail the gate. Results from a different source tree/toolchain do not count.

Prefer behavioral checks for saved data, cancellation, navigation and controls.
Keep source checks for genuine packaging/privacy boundaries, not exact function
locations or syntax. Dates and timezones in regression scenarios are explicit.

The language contract distinguishes UI locales from declared model-language
support. UI coverage is checked against the built app and critical labels in
Localizable.xcstrings. Model claims are a subset, not inferred from model size
or the set of translated UI labels. Quality still requires device/model testing.

## Release

1. Review and commit the source, version/build metadata and generated project.
2. Run verification on that exact commit. Keep its xcresults and evidence.json.
3. For a separately authorized upload, pass RELEASE_EVIDENCE to
   `bash tools/release.sh --upload`. A dirty tree or changed source, toolchain,
   version, missing/failed test results rejects the upload before archive/export.
4. Built app/widget metadata and privacy resources are checked by release.sh.
   Evidence is checked again before upload and copied beside the archive.
5. Apple processing, TestFlight availability, tester groups and installed build
   are separate gates and require live verification. Upload success proves only
   the transport step. Use ego-browser for App Store Connect.

The Cloud archive pre-build script runs Unit and Smoke before archiving. Its
execution on an actual Cloud worker must be verified separately; local passing
tests are not proof of a Cloud upload or tester assignment.

Local `release.sh` without --upload retains the existing development export and
physical-phone smoke flow. It installs an app: use it only when that action is
authorized. Ordinary verification and an unsigned Release build do not install
on the phone or upload anything. Never reset, stash or clean user work.
