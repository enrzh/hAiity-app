# App-wide design styles

Date: 2026-10-04
Base: `main`, `109a06d9bfc0633e59b8d45abc60cd25aad4a0dc`
Metadata: 1.0.0 (273), unchanged
Status: implementation complete and locally verified; physical/service checks remain

## Result

Darstellung now offers Original, Quiet, Focus and Studio through one persisted
appearance field and the existing Theme/component system. The same root and
secondary pages adopt the selected headings, spacing, icon treatment and surfaces.
No parallel navigation, persistence system or dependency was introduced.

The selector uses live miniature content and native buttons with selected traits.
It becomes a single column at accessibility text sizes. Existing advanced controls
sit behind native Customize; light/dark/system stays directly available.
The Today progress summary and creation preview are slimmer. The disconnected
Apple account row uses the existing short Not signed in label.

Photo/crop/color/material/performance/compact preferences remain independent of
design selection. Quiet's flat default surface does not remove legibility backing
from custom backgrounds or accessibility fallbacks. Focus preserves 44 pt targets.
Graph dates, tile geometry and month labels remain unchanged; Studio increases
framing only. Native navigation, split Search, gestures, sorting, history editing,
habit calculations, save/permission contracts and purchase policy remain shared.

Missing/unknown stored styles fall back to Original. Model regression tests cover
all styles, storage/reload, preservation of habit data/customization, newer remote
appearance merge and export/import. These verify local merge paths, not live iCloud.
The 11 style/selector labels and four material-preview labels have all 17 existing
locales. A focused regression test enforces complete coverage.

## Verification

Artifacts: `/Users/enricomini/Documents/haiity-verification/design-styles-20261004`

- Pre-task tracked patch, status and source fingerprint retained; prior dirty and
  untracked files preserved.
- Existing layout contracts now validate shared style roles while preserving
  minimum target, section and surface protections. Native option buttons retain
  their names, hints and selected traits; disclosure child IDs remain independent.
- Screenshot review fixed excessive scaling of purely decorative previews and
  four missing material-preview translations. Option labels/descriptions still
  scale fully. Quiet preserves Reduce Transparency outlines; Studio statistics
  numbers retain the system font.
- Compact-preference preservation is checked by enabling the native switch at
  its thumb, then changing all four styles. Prior test attempts and screenshots
  remain as diagnostic artifacts; only the results below verify the final source.

No commit, push, upload, TestFlight release or phone installation was performed.
Real-device VoiceOver/touch/material behavior and live iCloud appearance propagation
remain separate physical/service checks.

## Final local verification

Source fingerprint:
`88831efc9ca897c5f18de72d3475ae7bf4722cc83c493b793e5a31edbe82663e`

| Check | Result | Artifact under the task root |
| --- | --- | --- |
| Final complete Unit | 2,137 passed, zero failures/skips/runtime warnings | `verified-release/Unit.xcresult` |
| Final complete Smoke | 26 passed, zero failures/skips/runtime warnings | `verified-release/Smoke.xcresult` |
| Final narrow SE, Arabic RTL, largest Dynamic Type | One passed, zero failures/skips/runtime warnings; corrected preview translations visually reviewed | `CompactFinal.xcresult`, `compact-final-attachments` |
| Generic iOS Release, signing disabled | Exit 0 | `Release.log`, `ReleaseDerivedData` |
| App/widget metadata and privacy | Both 1.0.0 (273); both privacy manifests present | Built Release app and extension |
| `bash tools/verify.sh` and evidence recheck | Both exit 0; source, HEAD, metadata and toolchain match | `verify-release.log`, `verified-release/evidence.json` |
| Catalog and whitespace | 15 scoped keys in all 17 locales; `git diff --check` exit 0 | Catalog, `DesignStyleTests`, source diff |

Commands use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, Xcode
27.0 and iOS 27.0. Global `xcode-select` still points at CommandLineTools; it was
not changed. The explicit full-Xcode environment runs the native tests/builds.

Primary simulator: iPhone 18 Pro, iOS 27.0,
`2F9C45FC-34DC-44F6-B12A-C72B9DED1673`.
Narrow simulator: iPhone SE (3rd generation), iOS 27.0,
`CE73965B-EDCC-4331-BF9B-86EFEA944973`.
Native commands ran serially for this task; unrelated work on the shared Mac
was preserved. The Release build contains the unchanged dependency C++17 warnings.
No new runtime warnings were reported by the final tests.

The complete Smoke exercises actual style taps and selected state, root/account
navigation, retained photo/material/compact controls, and prior creation, search,
sorting/relaunch, notification times, account, history, Statistics Details and
data-transfer routes. The six focused model tests cover compatibility, complete
localization, Codable round-trip, durable saving, merge/import and minimum targets.

## Screenshots

Final source screenshots are exported under `final-style-attachments` and copied
without image modification to stable names in the artifact root:

| Style | Habits | Statistics | More |
| --- | --- | --- | --- |
| Original | `style-native-habits.png` | `style-native-stats.png` | `style-native-more.png` |
| Quiet | `style-quiet-habits.png` | `style-quiet-stats.png` | `style-quiet-more.png` |
| Focus | `style-focus-habits.png` | `style-focus-stats.png` | `style-focus-more.png` |
| Studio | `style-studio-habits.png` | `style-studio-stats.png` | `style-studio-more.png` |

Matching `style-*-selector.png` and `style-*-account.png` files show the selector
and a representative secondary page. Dark-photo material/customization captures
remain in `final-style-attachments`; Arabic AX5 captures are in
`compact-final-attachments`.

## Remaining verification

No local implementation or automated verification blocker remains for this scope.
Before shipping, check VoiceOver focus/selected announcements, touch/material
behavior on a real phone, and propagation between signed-in iCloud devices.
The final checks do not verify live StoreKit, native Calendar/Reminders or extension
service delivery. Those gates belong to the broader release/device checklist.
Build 273 was not signed for distribution, archived, uploaded or installed on a
physical device during this task; no release action is implied by local success.
