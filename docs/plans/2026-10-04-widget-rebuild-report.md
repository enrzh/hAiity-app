# Widget rebuild implementation and verification

Date: 2026-10-04
Base: main, `109a06d9bfc0633e59b8d45abc60cd25aad4a0dc`
Version: 1.0.0 (273), unchanged
Status: implementation and local verification complete; real-device host checks remain
Plan: [widget rebuild](2026-10-04-widget-rebuild-plan.md)

## Changes

- Rebuilt the small/medium selected-item widget, large two-item composition,
  retained large list/grid/focus layouts and legacy overview using the same
  identity/status/action components. The registered gallery kinds remain the
  same; retained list/grid/focus views are not newly registered widget products.
- Replaced nested card outlines with a continuous canvas and quiet separators.
  Graphs use shared ContributionTiles; all five positive/empty intensity levels
  remain distinct instead of collapsing levels 2, 3 and 4 to one fill.
- Actions have independent 44 pt targets. Checkbox completion remains idempotent,
  quantities increment, Yes/No remain separate choices, and reset follows the
  existing saved preference. Reset sits beside identity in narrow graph panels.
- Actual available geometry governs layout. Names can use two lines with full
  accessibility names; Focus falls back to equal rows at accessibility sizes.
  Sparse grid selections expand into real rows without phantom slots.
- Timeline entries carry the saved design style; the existing persistence and
  widget reload path remains authoritative. No new dependency or sync layer.
- Reminder status uses ReminderOccurrenceEngine at the timeline date, including
  completed one-time reminders and old unfinished occurrences. Timed reminders
  show their actual clock; all-day reminders do not appear overdue at noon.
- Graphs use the item's calendar. Timeline refresh chooses the earliest relevant
  midnight or future timed reminder boundary. WidgetKit still decides delivery
  timing; this is a refresh request, not a timing guarantee.
- Demo habit creation dates now precede demo logs, so gallery history is visible.
- Lock-screen ring represents zero accurately, reminder accessories avoid habit
  history/streaks, and Live Activities have clearer identity/timer/action regions.
  Existing ActivityKit types, system timers/progress and intents remain intact.
- Four missing reminder/action labels plus the incomplete Hide label now have all
  17 locales. Existing values/metadata were preserved by normalized hash checks.

## Verification

Artifacts: `/Users/enricomini/Documents/haiity-verification/widgets-rebuild-20261004`.
Pre-task tracked patch, status and source fingerprint are retained. Existing
dirty/untracked work and Git metadata were preserved. Source fingerprint:
`e687f2124d8649130c6c2a2de47c41d17eb9f3c5e98e778b8219e899e448b75e`.

| Check | Result | Artifact |
| --- | --- | --- |
| Pre-task widget suites | 152 passed, zero failures/skips | `Baseline.xcresult` |
| Integration build | Exit 0 | `build.log` |
| Focused widget logic/GitHub/rendering | 124 passed, zero failures/skips/runtime warnings | `Review6.xcresult` |
| Final visual matrix including small/medium AX and preview boards | 16 passed, zero failures/skips/runtime warnings | `SmallAX.xcresult` |
| Complete final Unit | 2,110 passed; zero failures/skips/runtime warnings | `verified-final/Unit.xcresult` |
| Complete final Smoke | 26 passed; zero failures/skips/runtime warnings | `verified-final/Smoke.xcresult` |
| `tools/verify.sh` and evidence check | Both exit 0; source/HEAD/metadata/toolchain match | `verified-final/evidence.json`, `verify-final.log` |
| Unsigned generic iOS Release | Exit 0 | `Release.log`, `ReleaseDerivedData` |
| App/widget metadata and privacy | Both 1.0.0 (273); both privacy manifests present | Built app/extension |

The old widget rendering suite pinned private struct names and fixed 168 pt
bands. It was replaced with checks of actual production views: overflow detection
at three canvas sizes, every item kind, empty/sparse data, reset on/off, custom
palettes, all design styles, light/dark/accented/vibrant, RTL graph chronology,
region content, six distinct data levels and preserved action/link/timer contracts.
The action, recurrence, entitlement and configuration logic suites remain.

Final evidence matches the source fingerprint above after Release compilation.
Xcode 27.0 (27A266a), iOS SDK/simulator 27.0 and XcodeGen 2.46.0 were used.
The simulator destination is iPhone 18 Pro,
`2F9C45FC-34DC-44F6-B12A-C72B9DED1673`. Three widget canvas sizes also cover the
narrow 292 x 311 pt large-family content area; small/medium content canvases are
138 x 138 and 332 x 138 pt. Existing dependency C++17 warnings remain in the
Release log; all final native test summaries report zero runtime warnings.

Native commands run serially with full Xcode via
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Project source discovery
uses the pinned XcodeGen generator. No phone installation, signing changes, commit,
push, archive, upload or TestFlight release was performed.

## Previews and remaining gates

`previews/widget-board-light.png` and `previews/widget-board-dark.png` render the
production Home Screen and accessory views. Individual `native-*-light/dark.png`,
mode, sparse, bounds and accessory images sit beside them. These are native SwiftUI
renders, not screenshots of WidgetKit placed over an actual Home Screen wallpaper.
The light board's monochrome accessory examples need a dark Lock Screen backdrop;
the dark board shows that ink treatment visibly.

Representative final previews:

- [Home Screen and lock-screen board, dark](/Users/enricomini/Documents/haiity-verification/widgets-rebuild-20261004/previews/widget-board-dark.png)
- [Home Screen board, light](/Users/enricomini/Documents/haiity-verification/widgets-rebuild-20261004/previews/widget-board-light.png)
- [Two-item composition](/Users/enricomini/Documents/haiity-verification/widgets-rebuild-20261004/previews/native-dual-light.png)
- [Retained four-item matrix](/Users/enricomini/Documents/haiity-verification/widgets-rebuild-20261004/previews/native-grid-light.png)

The view rebuild removes roughly 450 lines from widget production sources even
after adding shared components, reminder/date handling and design-style transport.
No timing benchmark is claimed from code size or offscreen renders.

Verify WidgetKit-host tint/clear modes, live Home Screen touch dispatch, Control
Center, actual timeline delivery and Live Activity delivery/privacy on a real
device before distribution. Local ImageRenderer tests and compilation cannot
establish those service/host results.
No local implementation or automated verification blocker remains for this scope.
