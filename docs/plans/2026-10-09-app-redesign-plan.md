# hAiity Redesign Plan

Date: 2026-10-09
Status: implemented and verified locally on `codex/haiity-redesign`; live readiness checks remain open.
Author: main assistant, based on the current code and your feedback.
Baseline: main at `3193faa`, local version 1.0.0 (277), clean before this document.

**Goal:** Make hAiity feel like one deliberate iOS app: useful full-width calendars,
clear daily actions, recognizable sorting, and settings that open the requested task.

**Architecture:** Change existing views and their real callers. Keep the shared
tile renderer, settings components, native reorder controller, routing, and storage.
Add a small sizing function to an existing type where both habit and GitHub graphs
need it; extend page enums only for actual destinations. No new component framework,
Manager, Service, Factory, Protocol, Coordinator, Provider, or Resolver.

**Tech stack:** SwiftUI, the existing UIKit reorder/context-menu bridges,
ContributionChart/ContributionTiles, Theme, XcodeGen, native Unit/Smoke plans.

## My design decision

I would redesign the composition and behavior before adding decoration. The
contribution calendar is the app's visual identity. It should look like a calendar
running across an entry, with the entry's name and action clearly attached to it.
The current eight-column island is too small horizontally and too tall vertically.
Sorting then switches to a different-looking gray list, and the integration entry
switches from settings into a tutorial. Those changes in presentation feel disconnected.

| Approach | Tradeoff | Decision |
| --- | --- | --- |
| Restyle the current cards | Small change, but retains the fixed narrow graphs and inconsistent destinations | Insufficient |
| Recompose the existing screens and correct sizing/navigation | Addresses the actual problems while retaining tested platform behavior | Recommended |
| Replace navigation, design system, and gestures together | Larger regression surface, with little benefit to the four requested changes | Defer |

The direction is **wide calendars, clear actions, restrained surfaces**. Keep the
existing palette identity and four design styles. Their fonts, radii, and spacing
can differ; page order, action meaning, and graph correctness should stay consistent.

## Requirements from you

| Requirement | Planned outcome |
| --- | --- |
| Change the sorting look | A themed, compact editing state with recognizable item identities and native drag handles |
| Fix habit entries and the small centered graph | Measured full-width calendar bands with square tiles and a useful visible period |
| GitHub on top | GitHub is the first content card below the Habits heading, ahead of Today/filter controls and personal entries |
| Do not replay setup from Mitteilungen & Kalender einrichten | Replace the wizard link with direct notification and calendar/reminder settings |

These decisions supersede the October 7 fixed eight-week card window and
GitHub-at-the-bottom placement. Existing histories and saved appearance choices remain.

## 1. Habits page: establish a clear reading order

```text
Habits                                  Filter / Sort / Add

GitHub                                 Profile link
[calendar spanning the content width]

Today: 4 of 6 completed        [ Today | All ]

Read twenty minutes                        Complete
Daily
[calendar spanning the content width]
History                                       Edit

Drink water                                  +1  2/3
Daily · Goal 3
[calendar spanning the content width]
History                                       Edit

Call the dentist                            Complete
Tomorrow · 10:00                             Details
```

The diagram expresses hierarchy, not extra boxed sections. Use the existing
canvas/surface treatment. Reserve glass for functional navigation and temporary
controls. Reduce oversized empty space between the page heading and content.

- GitHub scrolls with the page; "on top" means first content, not a permanent sticky
  graph taking up the screen. No new pin toggle.
- Keep cached GitHub content visible offline. An ongoing refresh does not block
  habits or replace the entire page with a spinner.
- No GitHub card when disconnected. Preserve the first-habit creation action when
  GitHub exists but there are no personal items.
- GitHub remains first under Today/All and item/status filters. It is not an item in
  the habit store and does not enter progress totals or manual item ordering.
- Dedicated Search retains its existing result semantics; this ordering rule belongs
  to Habits and does not inject an unrelated GitHub card into search results.
- Consolidate today's count and Today/All into one compact group. At accessibility
  text sizes they stack naturally; the count and filter stay separately accessible.
- Preserve the separated native Search button and its existing keyboard behavior.

## 2. Habit entries: make the graph use its space

### Layout and actions

Use one coherent entry with equal outer insets. The header gives the name most of
the width and reserves a trailing completion target. Show one short, accurate
schedule/goal line beneath the name. Avoid a competing badge for every property.

Move the existing visible Edit action into a secondary footer with History. This
retains discoverability while removing the pencil/check/name crowding in the header.
Keep the existing callbacks and accessibility identifiers. Name and graph still
open history; completion changes today; Edit opens the editor. Long-press and
swipes remain shortcuts, with their current confirmation and undo behavior.

Checkbox, quantity, and yes/no controls keep distinct meanings. Quantity shows the
current value and goal. Yes/no keeps two explicit answer targets and a distinguishable
declined state. At AX sizes, place the action beneath the identity rather than
shrinking the name or controls. Every direct action keeps a 44 pt minimum target.

### Calendar sizing

Replace the fixed eight-week request with a viewport-driven column count. Use the
actual tile-band width **after** row/surface insets, not UIScreen width or a preview's
width. Square tiles must consume the band width; a full-width container alone is
not sufficient.

Initial geometry, using the existing gap value:

```text
W = measured drawable tile-band width
g = existing GridCell.gap (currently 3 pt)
p = preferred tile side (12 pt)
N = clamp(floor((W + g) / (p + g)), 1, 53)
c = (W - (N - 1) * g) / N
calendar width = N * c + (N - 1) * g = W
calendar height = 7 * c + 6 * g
```

| Drawable width | Weeks/columns | Tile side | Tile-band width |
| ---: | ---: | ---: | ---: |
| 280 pt | 18 | 12.72 pt | 280 pt |
| 360 pt | 24 | 12.13 pt | 360 pt |
| 400 pt | 26 | 12.50 pt | 400 pt |
| 680 pt | 45 | 12.18 pt | 680 pt |

The preferred size is my starting design choice, not an Apple requirement. Inspect
rendered phone layouts before finalizing it. The invariant is real width coverage
with readable square cells, not preservation of a magic week count.

- Display the latest N weeks, with today's week at the trailing edge. Full history
  remains in the existing history editor. Displayed range/count text uses the actual N.
- New habits use the same geometry. Empty history does not collapse the calendar
  into a tiny island; neutral cells and an accurate start/date range explain it.
  Do not invent failures before tracking began or change completion mathematics.
- Keep seven-row date chronology, item-specific calendars/timezones, today outline,
  negative answers, month-label preferences, and intensity mapping.
- Tiles have fills and gaps, with the existing today/selection outline where needed.
  No white border around each tile, added shadow per tile, or stretched rectangle cells.
- In the normal card the band fits its viewport, removing unnecessary horizontal
  bounce. Full history retains its existing navigation. Context previews get their
  own measured geometry, not the normal card's cached width.
- On wide windows use a readable content column, initially capped at 760 pt; graphs
  fill that column. Centering a page column is different from centering a narrow
  graph inside a much wider entry.
- Use the existing queued snapshot/cache path. The key's week count must match the
  rendered columns. Quantize width changes to column-count changes before requesting
  new history; do not calculate a year synchronously on every layout or scroll frame.
- Keep immediate today-square projection and undo while a changed snapshot loads.
  Use a stable placeholder with the final band's dimensions to avoid list jumps.

## 3. GitHub: a first-class card with matching graph language

Move the existing GitHub section ahead of Today and habit/reminder sections. Match
its content insets, square-cell pitch, month-label treatment, and typography to the
new habit entry. Reuse the graph sizing calculation; retain the annual contribution
dataset and GitHub's own intensity/count meaning.

The card displays a readable latest window rather than forcing a complete year
into microscopic tiles. Preserve access to the existing complete data/profile
experience and native preview. A concise GitHub label remains when the username
preference hides the account name. Put an explicitly labeled profile link in the
header, rather than requiring a hold gesture to discover it.

During sorting, show a compact fixed GitHub identity at the top, labeled as fixed.
Hide its large graph while rearranging personal entries. GitHub never gets a drag
handle, position number, habit UUID, or persisted reorder entry.

## 4. Sorting: an editing state of the same app

Keep `NativeHabitSortingController` and its native reorder behavior. Rework the
row presentation and surrounding chrome, not the gesture engine.

```text
Reihenfolge                                  Fertig
Ziehen, um die Reihenfolge zu ändern.

GitHub                         Fixed at top

Read twenty minutes                         [handle]
Habit · Daily

Call the dentist                            [handle]
Reminder · Tomorrow, 10:00
```

- Recognizable emoji/icon, strong title, one secondary identity line, native handle.
  No contribution grids, completion controls, Edit, Delete, or active swipe actions.
- Replace hard-coded cell backing with a clear UIKit cell plus the existing themed
  surface in its hosted row. Quiet, Original, Focus, Studio, photos, custom colors,
  Reduce Transparency, and Increase Contrast retain their actual selected treatment.
- Use existing design-style fonts/padding/radius. Keep rows compact at normal size;
  let long names and accessibility text grow vertically.
- Keep native lift, slot movement, edge auto-scroll, and release animation. Add only
  brief edit-state transitions; Reduce Motion preserves immediate state feedback.
- Preserve native scroll position and stable cell identity while dragging. Do not
  reload the whole table merely for a style/content refresh during an active move.
- Keep VoiceOver Move Up/Move Down and announced positions. A finger hold or tap on
  a sorting row must never change completion or open another screen.
- The current implementation persists each move. `Fertig` exits editing; do not add
  a misleading Cancel or imply that Done is a new save/commit operation.
- Sort the current filtered subset with the existing full-list permutation rules.
  Hidden/archived entries retain their relative order, and stale/external updates
  keep the current rejection and reconciliation behavior.

## 5. More: settings must open settings

Remove `Mitteilungen & Kalender einrichten` as a normal hub action. It currently
sets `showReminderSetup = true` on every tap, replaying a three-page wizard whose
daily/weekly switches start enabled. A customer checking configuration should
land on their current settings.

Use clear task destinations:

| Hub row | Destination |
| --- | --- |
| Mitteilungen | Existing notification settings: authorization, reminders, summaries, quiet times |
| Kalender & Erinnerungen | Direct integration settings composed from the existing `calendarSection` |
| Verhalten | Existing archive/swipe/default-timezone options |
| Darstellung | Existing appearance page and Customize |

Expose the calendar composition as an actual `MoreScreen`/`MoreRoute` case using
the current page shell. The existing `MoreCalendar.swift` already owns the controls
and permission/recovery handlers; reuse them instead of adding another service or
duplicated setup view. Remove the calendar controls' second ordinary entry from
Behavior so there is one obvious home for them.

The calendar page shows enabled integrations and their selected destinations,
plus accurate disconnected/denied/recovery states. Requests happen when the person
chooses Enable/Connect, never from opening the page. Existing Pro boundaries,
disabled-state retention, scoped cleanup, confirmations, and error reporting remain.
Opening or leaving the page does not enable daily/weekly summaries or rewrite times.

Remove the wizard from normal navigation. Retain it only where an existing explicit
tutorial/debug path actually needs it; do not add a new onboarding state machine or
completion flag merely to suppress repeated navigation to the wrong destination.

Group More by everyday controls, personal connections, then data/about. Keep account
rows navigation-only, use precise status text instead of repeating descriptions,
and retain nickname-first personalization and optional Apple connection.

## 6. Additional changes I would make

### Reminders

Bring reminder identity, spacing, completion targets, Edit/Details discoverability,
and swipe surfaces into the same visual rhythm as habits. Keep reminders compact;
they get clear date/time/status text rather than a contribution calendar. Do not
borrow streak terminology for appointments. Preserve early-completion confirmations
and end-of-day auto-resolution rules.

### Statistics

Lead with the existing current-week completed/total result, then make Today a
lighter summary instead of another large dashboard hero. Per-habit recent progress
and history are the next useful layer. Keep explicit custom metric selections and
the optional reading disclosure. Reuse the calendar language for rhythm charts,
without silently changing their displayed period, denominators, or saved visibility.

### Creation

Keep name, schedule and Save visually primary. Place the optional sentence action
as a clear alternative to manual entry, with its existing typed-text handoff. The
preview should be a readable sentence with active settings, not a second decorative
card. Show quantity controls when quantity is explicitly chosen; retain collapsed
optional settings, daily/once defaults, and hidden notification times.

### Consistency and performance

Normalize repeated row edges, action sizes, title hierarchy, and vertical spacing
through the existing Theme roles. Use one surface per meaningful group. Avoid
repeated blur layers, broad implicit animations, rotating loaders in every entry,
and heavy graph work in sorting. Add no further appearance modes or configuration
knobs to compensate for layout defects. Measure first-open and scrolling behavior
with representative data; do not call a visual change a proven phone performance fix.

## Implementation sequence and file ownership

Each task ends with a reviewable result. Execute serially where files overlap;
no unrequested commits, uploads, device resets, or background workers.

| Order | Deliverable | Existing files to change | Focused verification |
| ---: | --- | --- | --- |
| 1 | Width-driven habit calendars and entry composition | HabitCard.swift; GridCalendar.swift; GitHubContributionGraph.swift for the shared sizing helper | HabitCardProductTests; GridCalendar tests; graph layout UI/pixel checks |
| 2 | GitHub-first composition and matched card | ContentView.swift; GitHubContributionCard.swift; GitHubContributionGraph.swift | AppNavigationTests; GitHubCardContractTests; TodayProgressUITests |
| 3 | Themed sorting state and fixed GitHub identity | HabitSortingScreen.swift; ContentView.swift | Reorder/filter tests; SortingUITests; compact/RTL/native drag checks |
| 4 | Direct calendar/reminder settings, remove setup replay | MoreView.swift; MoreCalendar.swift; MoreBehavior.swift; ContentView.swift | AppNavigationTests; setup/permission contracts; More UI navigation checks |
| 5 | Reminder, Statistics and creator composition | ReminderRow.swift; StatsView.swift; EditHabitSheet.swift; TodayProgressView.swift | Existing item/creation/Stats tests and real interaction checks |
| 6 | Shared polish, localization and final verification | Theme.swift; AppUIComponents.swift only where an existing shared role needs adjustment; Localizable.xcstrings; design-system document; affected test files | Unit, Smoke, Release compilation, screenshot inspection and physical gates |

All paths in the table are under `Haiity/Views`, except models under `Haiity/Models`,
`Haiity/Theme.swift`, `Haiity/Localizable.xcstrings`, and the existing test folders.
Reuse those files; this is not a repository-wide extraction exercise.

- [x] Review existing geometry, source-contract tests, permissions, and sort callbacks.
- [x] Add regression checks for measured geometry, order, navigation and date rollover; verify geometry and date failures before their fixes.
- [x] Implement tasks 1-4 using the existing rendering, routing and native drag paths.
- [x] Review normal/compact simulator layouts before applying the same roles to secondary screens.
- [x] Implement task 5 without changing persistence, recurrence math, purchase boundaries or syncing.
- [x] Replace obsolete fixed-eight-week/GitHub-last/wizard-link assertions with behavior checks.
- [x] Preserve all existing localization values; translate new UI copy in all 17 supported locales.
- [x] Update the design-system contract to describe the approved new hierarchy and sizing.
- [x] Regenerate the explicit Xcode project.
- [x] Complete local Unit, Smoke, visual and Release checks; bind evidence to the actual source revision.
- [ ] Confirm the candidate build number live through ego lite; keep phone, iOS 27 and distribution checks separate.

## Acceptance checks

| Area | Required evidence |
| --- | --- |
| Width | At 320/375/402/440 pt phone widths, tile band uses its actual available width within 1 pt, with equal insets, square cells, seven rows and no clipped final column |
| Time | Today's day/outline, timezone, quantity/yes-no intensity and month labels match the same snapshot; changing width updates displayed range accurately |
| Data | New, sparse, long-history, future-start and archived items retain original logs/rules; no phantom completion before creation |
| Actions | Name/graph open history; direct completion and undo update the correct day; Edit stays discoverable; swipes and native preview remain usable |
| GitHub | First content in Today/All and filtered Habits; excluded from totals and reorder writes; disconnected/connecting/cached/offline states stay usable |
| Sorting | Top-to-bottom and bottom-to-top moves, edge auto-scroll, long holds, filtered moves, relaunch persistence, save rejection and external changes remain correct |
| Setup | Tapping direct notification/calendar settings never presents ReminderSetupView or changes preferences; denied/granted/limited access and Pro states are truthful |
| Appearance | All four styles, light/dark, photo/gradient/custom colors, compact, contrast and transparency preferences remain selected and legible |
| Accessibility | AX5 narrow width, long names, Arabic RTL, VoiceOver ordering and Move Up/Down; no reduced text scale to force fit |
| Performance | Cached first render, visible-band background calculation, resize stability, rapid check-off/undo and held-finger scrolling; preserve existing StartupMetrics/signposts |

Native final commands, run from `/Users/enrico/Documents/GitHub/haiity`:

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash tools/generate-project.sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash tools/verify.sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Haiity.xcodeproj -scheme Haiity -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

These are future validation steps, not checks run for this planning request. Use
the current MacBook simulator/device inventory, not a retired Mac mini destination.
Inspect screenshots for actual width usage; passing source-string assertions is
not visual evidence. Confirm original-data startup, native services, widget refresh,
and VoiceOver on the phone separately. Later TestFlight distribution uses a unique
build and source-bound evidence; this plan itself does not trigger a release.

## Design basis

The concrete layout and 12 pt preferred tile pitch are my design judgment. Apple
guidance used to constrain the proposal:

- `layout.md`, Visual hierarchy: "Align components with one another to make them easier to scan".
- `charting-data.md`, Designing effective charts: "Match the size of a chart to its functionality, topic, and level of detail".
- `lists-and-tables.md`, Best practices: "Let people edit a table when it makes sense".
- `onboarding.md`, Additional requests: "Postpone nonessential setup flows or customization steps".
- `settings.md`, Task-specific options: "prefer letting people modify task-specific options without going to your settings area".
- `accessibility.md`, Mobility: "Offer alternatives to gestures" and use the platform's recommended 44 pt control targets.
- `motion.md`, Best practices: "Add motion purposefully, supporting the experience without overshadowing it".

References read from the local apple-design HIG collection. This proposal is based
on current source and your observations; no new screenshot audit, build, device
test, implementation, commit or upload was performed in this planning turn.

## Implementation checkpoint

Updated 2026-10-09. The implementation is isolated in
`/Users/enrico/Documents/GitHub/haiity/.worktrees/2026-10-09-redesign`, on
`codex/haiity-redesign` at `3a0f4c6aa205d9bf9520ba1fe0459c64a385d0b5`.
The primary checkout remains on its existing main revision; its untracked plan is preserved.

The complete redesign is implemented, including native sorting surfaces, full-width
adaptive calendars, GitHub-first composition, direct integration settings, lighter
creation/Statistics presentation, and unchanged recurrence/storage/purchase boundaries.
Six new strings have all 17 localizations; all 990 previous catalog entries and
metadata are preserved. A further date regression fixes unchanged graphs retaining
the previous day. Its failing equality check now passes for all three views, with
the habit timezone and GitHub UTC kept distinct. No timers or new component layers were added.

Candidate metadata is 1.0.0 (278), aligned between app and widget. Its source
fingerprint is `7871e745be01203790af1fb3f7ac8466840c6735c53413e7bf93d385b9340275`.
Final verification of this exact commit passed 2,150 Unit tests and all 47 Smoke
tests, with no failures or skips. The unsigned generic-iOS Release build passed.
The initial UI run had six failures; all are resolved in the final full run, and
the original native sorting accessibility audit remains intact. Three additional
simulator performance tests passed: crowded-fixture first responsive frame averaged
1.752 seconds across five launches; full-card and compact sorting deceleration
measurements averaged 2.319 and 2.295 seconds across three runs each. These are
current simulator measurements, without a comparable earlier-build baseline or
real-phone performance claim.

Current verification root: `/Users/enrico/Documents/haiity-verification/redesign-20261009`.
Final results are `Final278/UnitReleaseCommit.xcresult`,
`Final278/SmokeReleaseCommit.xcresult`, `Final278/Performance.xcresult` and
`Final278/Release.log`. `Final278/evidence.json` is recorded and passes
`tools/verification.rb check` for the commit, fingerprint, 1.0.0 (278),
Xcode 27.0 (27A266a), SDK 27.0 and pinned XcodeGen 2.46.0. The clean worktree and
unchanged fingerprint were rechecked. Built app/widget versions match; each
contains 17 localization bundles and its privacy manifest. The compiled primary
and 17 alternate icons and resolved public OAuth configuration passed validation.
Final screenshots in `Final278/Screenshots` were inspected for full-width bands,
GitHub-first order, Studio/Quiet layouts, dark-photo sorting and direct settings;
the native UI run also covered four styles, AX5, Arabic RTL and compact actions.
Do not repeat these passed checks unless the source or toolchain changes.
Subagent review used and verified `sub2api/gpt-6.1-sol` for all workers.

Live App Store Connect checks are blocked because ego lite and its prescribed skill
are absent on this MacBook. Build 278's availability must be confirmed there before
distribution. The installed simulator runtime is iOS 26.5; physical-device behavior,
iOS 27's prominent Search presentation, Cloud execution/upload, tester groups and
installed build remain separate checks. No upload, phone installation or data reset
has been performed. Keep the completion heartbeat active until the applicable
implementation and release-readiness gates have final evidence.
