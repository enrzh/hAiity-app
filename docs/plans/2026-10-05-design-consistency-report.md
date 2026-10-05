# Recent UI design consistency fixes

Date: 2026-10-05
Base: main, `0b2acf6`, version 1.0.0 (274)
Status: implementation and local verification complete

## Corrected drift

- Design/material options now use the active app surface, style radius, padding,
  typography and palette. Removed private gray fills, unselected borders and
  duplicate List-row surface decoration. Selection keeps its explicit border,
  checkmark and accessibility trait; decorative candidate previews stay separate.
- More/Customize, account, cloud status, notifications and GitHub controls use
  current style spacing, shared rows and icons. Removed tiny uppercase subsection
  headings. Kept the account avatar, crop geometry and native control shapes.
- Import/Export is now a pair of full-width settings actions with consistent
  icon alignment, spacing and hit targets.
- Creator additional/schedule controls and Statistics Details use shared settings
  rows. Explanations use supporting-text typography; metric/Pro icons share the
  badge component. Decorative icon scaling stays inside its fixed slot.
- Widget positive actions use the global accent and its accessible fill role for
  white symbols. No-state symbols retain their data color without a low-contrast
  white-on-pastel fill; status text is neutral and selected traits are explicit.

The existing four styles and all material/background choices remain. Localization
keys/IDs, data models, calculations, permissions, bindings, import/export handling,
account/Pro behavior and navigation routes were preserved. No dependency, widget
kind or product feature was added. Existing shared components were reused.

## Verification

Artifacts: `/Users/enricomini/Documents/haiity-verification/design-consistency-20261005`.
The initial repository was clean; other project builds on the shared Mac were
left alone. Metadata remains 1.0.0 (274), and no commit/push/upload/device install
is part of this task. Source fingerprint:
`bf938325a477118f08ddc655f87ae1eb2ac2ac94ebaa78b45ee7eb96bec65c76`.

| Check | Result | Artifact |
| --- | --- | --- |
| Early focused regression | 149 passed; one obsolete literal surface assertion corrected | `Focused.xcresult` |
| SE Arabic, largest text, creator/appearance interactions | 2 passed; zero failures/skips/runtime warnings | `CompactReview.xcresult`, `compact-attachments` |
| Complete native Unit | 2,111 passed; zero failures/skips/runtime warnings | `verified/Unit.xcresult` |
| Complete Smoke | 26 passed; zero failures/skips/runtime warnings | `verified/Smoke.xcresult` |
| Project generation and evidence rejection checks | Exit 0; 16 rejection cases passed | `verify.log` |
| Complete verification script | Exit 0; source unchanged throughout tests | `verify.log`, `verified/evidence.json` |
| Evidence identity/result recheck | Exit 0; matches current source, toolchain and 1.0.0 (274) | `verified/evidence.json` |
| Unsigned generic iOS Release build | Exit 0; zero compiler errors, four MLX dependency warnings | `Release.log`, `ReleaseDerivedData` |
| Final whitespace check | `git diff --check`, exit 0 | Current diff |

The full check used Xcode 27.0 (27A266a), iOS SDK 27.0 and XcodeGen 2.46.0.
Unit/Smoke ran on the iPhone 18 Pro simulator with iOS 27.0; the two compact
accessibility cases ran on the iPhone SE (3rd generation) simulator. Release
used `generic/platform=iOS`, configuration Release and `CODE_SIGNING_ALLOWED=NO`.
Its four warnings are `constexpr if is a C++17 extension` from the unchanged
mlx-swift Metal headers. They do not represent a successful signed archive.

The new widget pixel check verifies the selected background against the global
palette's fill color in both light and dark mode, even when the item uses another
palette. Existing palette contrast, appearance preservation, creator, transfer,
widget bounds and navigation checks remain. The stale selector assertion now
accepts the shared surface's actual parameterized API rather than requiring the
old List-row wrapper. The final complete Unit run includes the corrected
assertion and passes. Smoke covers style selection/preservation, account and
settings controls, creation, notifications, transfer entry points, search,
sorting, contribution history and Statistics disclosures.

## Visual review

Exported 73 PNG attachments from the final Smoke result. Reviewed representative
captures of all four design selectors, Original/Quiet/Studio More layouts,
account content, Studio/Quiet material options over a dark photo, creator
controls, transfer, GitHub and Statistics. Also reviewed the compact Arabic
appearance captures and both widget render boards. No new alignment or text
clipping defect was visible in these captures; content below the viewport stays
scrollable. Native navigation titles and Apple sign-in controls retain their
platform styling.

| Reviewed example | Screenshot |
| --- | --- |
| Original design options | [Selector](/Users/enricomini/Documents/haiity-verification/design-consistency-20261005/smoke-attachments/863623E0-0670-4F63-A9DD-D4D076EC0D03.png) |
| Quiet More layout | [More](/Users/enricomini/Documents/haiity-verification/design-consistency-20261005/smoke-attachments/C65FA361-9D1C-4D1A-8A25-FF6ED313C792.png) |
| Studio account content | [Account](/Users/enricomini/Documents/haiity-verification/design-consistency-20261005/smoke-attachments/68169D86-6AB3-4AFC-8384-3142DA416BCA.png) |
| Studio material options over a photo | [Materials](/Users/enricomini/Documents/haiity-verification/design-consistency-20261005/smoke-attachments/0821E2E4-15BC-4BC2-9511-5E28462AC5C9.png) |
| Public Import/Export | [Transfer](/Users/enricomini/Documents/haiity-verification/design-consistency-20261005/smoke-attachments/4E6B7C9C-89D2-48F4-AE59-861F66B41CF1.png) |
| Shared GitHub rows | [GitHub](/Users/enricomini/Documents/haiity-verification/design-consistency-20261005/smoke-attachments/8C0E9D4F-7DE3-4CE5-8C16-180F96F3ADAE.png) |
| Creator additional settings | [Creator](/Users/enricomini/Documents/haiity-verification/design-consistency-20261005/smoke-attachments/434C4C73-D020-473B-AE7A-B57781290AFB.png) |
| Expanded Statistics details | [Statistics](/Users/enricomini/Documents/haiity-verification/design-consistency-20261005/smoke-attachments/A5E32B89-E4C8-42F3-B560-1F7CBF792283.png) |
| SE Arabic, largest text, material preview | [Compact appearance](/Users/enricomini/Documents/haiity-verification/design-consistency-20261005/compact-attachments/C15AC7C0-6DDC-48F5-89D3-3D884399EF00.png) |
| Widget render boards | [Light](/Users/enricomini/Documents/haiity-verification/design-consistency-20261005/widget-previews/widget-board-light.png), [Dark](/Users/enricomini/Documents/haiity-verification/design-consistency-20261005/widget-previews/widget-board-dark.png) |

## Remaining validation

Real-device VoiceOver, native widget-host tint/touch and live services remain
separate checks. Simulator interactions and render previews do not establish
TestFlight delivery or a physical-device installation. No local blocker was
found for this design consistency scope. Full project-hardening and release
gates retain their separate checkpoints; their continuation automation was not
changed. No signed archive, upload, commit, push or phone installation was made.
