# hAiity UI Unification Inventory and Baseline

Status: Phase 0 complete, Phase 1 ready to start
Date: 2026-09-21
Repository: `/Users/enricomini/Documents/Github/hAiity`
Source baseline: `main` at `156bd2c`

This is the evidence sheet for
[`2026-09-21-ui-unification-and-sustainable-ui-plan.md`](2026-09-21-ui-unification-and-sustainable-ui-plan.md).
It records the current ownership and visual state before extracting shared UI
components.

## Worktree protection

The following existing modified and untracked paths were present and remain
untouched by this inventory:

- Modified app/model/test files in `Haiity/` and `HaiityTests/`.
- `.runtime-stats-fixture.json`.
- `.superpowers/brainstorm/`.
- `Launch_Haiity_2026-09-13_04.55.42_77DEF1CA.trace/`.
- Existing files under `docs/plans/`.

No reset, clean, stash, commit, push, or release action was performed.

## Source inventory

### Shared foundations to keep

| Foundation | Owner | Current callers/evidence | Decision |
| --- | --- | ---: | --- |
| Spacing, hit targets, radii | `Theme.Metrics` | 1 owner, many references | Keep authoritative |
| Palette/material resolution | `Theme` and environment values | app-wide | Keep authoritative |
| Root title and compact title | `RootPageTitle` / `RootPageCompactTitle` | 3 files | Keep, unify call contract later |
| App surface | `appSurface()` | 6 view files | Keep, do not duplicate |
| Settings surface | `moreSettingsSurface()` | 5 view files | Keep, do not duplicate |
| Graph tile primitive | `GridCell` | shared app/widget paths | Keep separate from UI card tokens |
| Graph renderer | `GitHubContributionGraph` | habit/GitHub/widget paths | Keep single renderer |
| Swipe gesture/physics | `SwipeRevealPan`, `SwipeRevealSession`, `SwipeRevealMotion` | habit/reminder/search paths | Keep behavior owner |

### Repeated compositions

| Visual role | Current implementations | Reuse decision |
| --- | --- | --- |
| Settings row with icon, title, detail, trailing value/control | `MoreView.moreIcon`, `MoreView.moreHubRow`, `MoreView.pageRow`, local rows in utility screens | Extract a small `AppSettingsRow` only for stable matching callers |
| Settings group title and spacing | More hub groups, `List`/`Form` sections, settings modifiers | Extract grouping layout only; preserve native list semantics |
| Repeated item surface | `HabitCard`, `ReminderRow`, `SearchResultRow`, Stats rows | Share surface geometry only; keep model/actions local |
| Graph outer frame and preview sizing | `HabitCard`, `GitHubContributionCard`, Stats graph cards | Extract frame/centering contract; keep graph data/actions local |
| Header/scroll title | `RootPageTitle`, `RootPageCompactTitle`, `navigationChrome`, `pageHeaderChrome`, `ContentView.ChromeGlass` | Consolidate ownership after baseline; no behavior rewrite |
| Toast shell | `ContentView.ToastSurface` and root toast placement | Move visual modifier only; keep state/timing in `ContentView` |
| Context menu bridge | `GraphContextMenu` | Already shared; do not wrap again |

### Intentional non-duplication

- `HabitCard` and `ReminderRow` do not share business actions or state.
- `ReminderSlidingSurface` and `HabitSlidingGrid` may share future framing
  values, but their gesture ownership must remain explicit.
- `Standardzeitzone` remains a direct picker on More, not a page component.
- Native `Picker`, `Toggle`, `Button`, `TabView`, and `NavigationStack` remain
  native controls rather than being replaced by an abstraction.

## Measured caller counts

These counts were collected with `rg -l` over `Haiity/**/*.swift`:

- `appSurface(`: 7 matches in 7 files, including the modifier definition.
- `moreSettingsSurface(`: 6 matches in 6 files, including the modifier
  definition.
- `navigationChrome(`: 3 files.
- `pageHeaderChrome(`: 7 files.
- `GraphContextMenu`: 5 files.
- `SwipeRevealPan`: 4 files.
- `GridCell`: 5 files.
- `ToastSurface`: 1 file, still private to `ContentView`.
- `ChromeGlass`: 1 file, still private to `ContentView`.

The counts support extracting only settings rows, shared item surfaces, graph
framing, and toast/chrome composition. They do not support a generic protocol
hierarchy or a new UI framework.

## Visual baseline

### Environment

- Device: iPhone 18 Pro simulator
- Simulator UDID: `2F9C45FC-34DC-44F6-B12A-C72B9DED1673`
- OS: iOS 27.0
- App bundle: `com.aiity.haiity`
- Local app: `1.0.0 (208)` Debug simulator build
- Screenshot size: 1206 x 2622 pixels
- Fixture: `-design-fixture crowded`
- Screens captured after a 5-second post-launch wait, once the first UI was
  visible and interactive.

### Captures

The captures are kept outside the repository under `/tmp` so baseline evidence
does not add binary assets to the product source:

| Surface | Appearance | Evidence |
| --- | --- | --- |
| Habits | Light | `/tmp/haiity-ui-baseline-2026-09-21-habits-light-interactive.png` |
| Stats | Dark | `/tmp/haiity-ui-baseline-2026-09-21-stats-dark-interactive.png` |
| More | Light | `/tmp/haiity-ui-baseline-2026-09-21-more-light-interactive.png` |
| More | Dark | `/tmp/haiity-ui-baseline-2026-09-21-more-dark-interactive.png` |
| Appearance | Light | `/tmp/haiity-ui-baseline-2026-09-21-appearance-light-interactive.png` |
| Search | Light | `/tmp/haiity-ui-baseline-2026-09-21-search-light-interactive.png` |

An earlier two-second capture showed only the startup contribution animation:
`/tmp/haiity-ui-baseline-2026-09-21-habits-light.png`. It is retained as
startup evidence and is not used as a content-layout baseline.

### Observations

- The Habits page establishes the strongest visual identity: a large root
  title, progress strip, segmented filter, and graph-led item surfaces.
- Stats uses the same root title and bottom functional chrome, but its cards
  have more local framing and typography than More/settings groups.
- More already has a consistent group rhythm, but its icon/title/detail rows
  are locally composed and should be the first settings-row migration target.
- More's direct timezone picker is visually different from navigation rows by
  intent, but it still needs the same icon slot, row height, and divider rules.
- Appearance uses native controls inside a large settings surface and should
  not be forced into the same composition as the More hub.
- Search correctly presents one prominent search field in its dedicated tab;
  its result rows use the same repeated-item spacing family but no graph.
- Dark mode preserves hierarchy but exposes the importance of semantic surface
  and secondary-label tokens. No new color system should be introduced to
  address this; use the existing appearance resolver.
- The screenshots contain English and German copy in the fixture. This is a
  localization baseline observation, not a reason to change UI architecture in
  this phase.

## Phase 0 exit criteria

- [x] Worktree and current UI ownership inspected.
- [x] Repeated components classified as reuse, local, or deletion candidates.
- [x] Caller counts recorded.
- [x] Light/dark interactive simulator baseline captured.
- [x] Startup-only screenshot distinguished from content baseline.
- [x] No source behavior changed.

## Phase 1 starting point

Start with the smallest reversible extraction:

1. Move the visual toast modifier out of `ContentView` into a shared view file,
   retaining all state, timing, safe-area calculations, and action closures in
   `ContentView`.
2. Add the first `AppSettingsRow` contract for More's `pageRow` and
   `moreHubRow`, but leave the direct picker and native trailing controls
   explicit until hit testing is covered.
3. Add source-contract tests for the shared icon slot, minimum row height,
   accessibility identifiers, and native trailing-control hit ownership.
4. Re-run the focused navigation, appearance, GitHub graph, feedback, and UI
   tests before migrating another family.

Do not extract item rows or graph framing in the same change. They have higher
interaction and layout blast radius and should follow the settings-row proof.
