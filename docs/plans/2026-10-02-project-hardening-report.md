# Project-hardening implementation

Date: 2026-10-02. All seven items from the accepted project review are implemented.
No product features, app dependencies, database migration or broad UI redesign
were added.

## Implemented scope

| Item | Implementation and purpose |
| --- | --- |
| Reproducible releases | `tools/verify.sh` runs Unit and Smoke, records native results with the Git commit, source fingerprint, build/version, SDK, Xcode and XcodeGen. `release.sh --upload` requires a clean tree and matching evidence before archive and again before upload. Each run gets its own artifact directory. The Cloud archive pre-build hook runs the same verification. |
| Shared JSON safety | HabitStore uses native file coordination, atomic replacement and an exact-byte baseline. A stale writer restores durable data and reports a retry instead of overwriting a newer app/widget/Siri save. Deferred startup does not synchronously read or adopt an unloaded file as a writable baseline. |
| Save failure propagation | Creation/editing stays open on failure. Widget/Siri and notification actions cannot confirm an unsaved change. Live Activity completion stops before clearing the session; retry repairs saved session minutes without another quantity increment. Cloud conflict retry can throw and stops after a failed local merge. |
| Less fragile verification | Native Unit, Smoke and Device plans separate full unit coverage, real UI interaction and the existing physical-safe subset. Tests affected by extraction follow the actual owning page. Two merge tests and design-fixture launches now use independent temporary files. Existing assertions were preserved; failures and skips block release evidence. |
| Bounded view extraction | AboutView and tab-bar measurement moved into their own files. Both implementations match their originals; root navigation, lifecycle state and bindings stay with their existing owners. |
| Current documentation | README, the engineering guide and store-listing minimum OS match the code: iOS 18+, pinned development tools, current dependencies and 17 declared UI localizations. Historical plan/spec indexes explain that old commands and completion claims are reference material. |
| Honest language claims | UI locales are checked against the built app and six core labels. Model language declarations remain a separate subset, without a claim of quality in every translated UI language. Two duplicate string keys were removed so the complete translations are used consistently. Duplicate keys now fail verification. |
| Pinned generator and validation | XcodeGen 2.46.0 is enforced locally. Cloud bootstrap builds immutable revision `8445e778451c7e44237b90281bde622d764b0084` and installs its required resource bundle. Package-plugin and macro validation bypass flags were removed from the release script. |

The shared-write policy deliberately rejects conflicting operations rather than
introducing a merge queue or changing existing CloudKit union/metadata rules.
The user or intent can retry from the durable snapshot. Normal saved values,
recurrence, Pro policy, notifications and native Calendar/Reminders rules retain
their existing contracts.

## Verification evidence

Initial checkout was clean on `main`, at
`4ecf1844130f8fc937cfeb88531a8910eef9ab34`. Build/version remain `1.0.0 (269)`.
The implementation is uncommitted. The evidence records both that base commit
and the changed build inputs; it is not evidence that the published build 269
contains these changes. Committing changes invalidates the commit identity and
requires verification again before a release upload.

Final source fingerprint:
`07fb262174d662913a542ef15d763c7616740816c6fd92ccbf2935fef2638f7f`.

All native commands used
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. System xcode-select
still points at CommandLineTools; full Xcode was available through this explicit
override. Xcode: 27.0, build 27A266a; iOS SDK: 27.0. Simulator: iPhone 18 Pro,
iOS 27.0, ID `2F9C45FC-34DC-44F6-B12A-C72B9DED1673`.

| Check | Result |
| --- | --- |
| `bash tools/verify.sh` on the final source | Exit 0. Unit: 2,073 passed, 0 failed, 0 skipped. Smoke: 4 passed, 0 failed, 0 skipped. |
| `ruby tools/verification.rb check .../evidence.json` | Exit 0; current source, metadata, tools and result bundles match. |
| `ruby tools/verification_test.rb` | Exit 0; 16 invalid-evidence cases rejected, changed and untracked inputs detected. |
| Stale evidence after a source change | Exit 1 as required; old passing results did not authorize the changed tree. |
| Generator version mismatch | Exit 1 before generation, as required. |
| Pinned XcodeGen source build | Exit 0. Relocated binary plus resource bundle generated a byte-identical project, with the original source presets temporarily unavailable. |
| Native scheme test plans | Exit 0; Unit, Smoke and Device are recognized. |
| Native Device plan enumeration | Exit 0; 20 methods selected. The release count guard matches that selection. This was enumeration on a simulator, not execution on a phone. |
| Unsigned Release build, generic iOS destination | Exit 0, without package/macro validation bypasses. No archive, signing export or upload performed. |
| Built app/widget resources | Exit 0; matching `1.0.0 (269)` metadata, translated localization folders and privacy manifests in both bundles. |
| Extraction comparison against original source | Exit 0; AboutView and tab-bar measurement preserve their original implementation. |
| Shell syntax, Ruby syntax, `git diff --check` | Exit 0. |

Final result bundles, logs and evidence are under:
`/tmp/haiity-project-hardening-k7kuw6/final/`.
Unsigned build output is under:
`/tmp/haiity-project-hardening-k7kuw6/ReleaseDerivedData/`.
These are local temporary artifacts, not uploaded or permanent CI storage.

Verification found and fixed reused test storage and outdated source-location
assertions. No test was removed, skipped, weakened or given automatic retries to
obtain the final passing result. Existing compiler warnings remain, including
deprecated test-source readers and dependency warnings.

## Remaining release gates

1. Review and commit the working tree, then verify that exact commit. The current
   dirty tree is intentionally ineligible for `release.sh --upload`.
2. Exercise simultaneous app/widget writes, Siri/notification error handling
   and Live Activity retry on a real device. The concurrency regression uses
   separate stores and overlapping queues in one process; it does not prove
   real extension-process scheduling.
3. Verify the new Cloud pre-build hook and generator bootstrap on an actual
   Xcode Cloud worker. Local execution and compilation do not prove the remote
   workflow ran or that its artifacts are retained.
4. Confirm real iCloud account/offline recovery and signed StoreKit/native
   Calendar/Reminders behavior before selecting the App Store candidate. Their
   existing deterministic tests passed; live services were not exercised here.
5. A separately authorized release still requires archive/export, upload,
   Apple processing, TestFlight availability, group assignment and installation
   checks. None of those happened in this task.

The implementation is ready for review and a device/Cloud verification build.
It is not being represented as a fully validated App Store release candidate.
