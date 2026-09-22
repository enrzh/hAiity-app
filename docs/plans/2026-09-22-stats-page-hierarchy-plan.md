# hAiity: Statistik page hierarchy plan

Date: 2026-09-22
Status: plan only; not authorized to implement, commit, push, or upload
Checkout: /Users/enricomini/Documents/Github/haiity
Baseline: main, HEAD a8cfb25, origin/main in sync
Preserve: existing uncommitted crop-zoom work in Theme.swift, MoreView.swift, and ThemeAndPaletteTests.swift. Do not mix it into this change and do not discard it.

## Opinion and direction

The Statistics tab already has a thesis: today is the reading, the contribution grid is the picture, the week card is the trend, the habit list is the index. It currently says the same numbers three times and the habit rows go nowhere.

Do not rebuild the page. Do not add insights, extra ranges, a new graph screen, or another chart type. Cut the duplicate metric tiles, make a habit row open the existing Habits card, align the settings names with the page, and give VoiceOver the values the charts already show.

## Evidence and limits

- Design review of `Haiity/Views/StatsView.swift`, `Haiity/Models/StatsCardPrefs.swift`, and related tests on 2026-09-22.
- Live simulator capture: empty Habits screen on iPhone 18 Pro (iOS 27.0). Populated Statistics was not captured; the sim showed an in-app URL confirm dialog and Simulator is not available to Computer Use.
- Today and week cards are always on. Card prefs only add the year grid and a 2x2 of Serie / Heute / Woche / Check-ins. Heute, Serie, and Woche already live on the today card; Woche also lives on the week card. Check-ins is the only unique tile.
- There is no separate graph destination. `requestedHabitID` in ContentView already switches to Habits and scrolls to that card. `AppDestination.habit` already produces `haiity://habits?habit=`.
- `-seed-stats` currently writes `StatsCardPrefs()` (the default). UI tests in `StatsContextMenuUITests` assume the four metric tiles exist.
- Signing, TestFlight, and archive are out of scope. Next local archive would need 212+; this plan does not upload.

## Scope

In:

1. Default visible stats cards to year pulse + Check-ins.
2. Habit-row commit opens that habit on the Habits tab.
3. Empty Statistics gets the existing create button.
4. Settings labels match the page.
5. VoiceOver values for today, rhythm, and week.

Out:

- New graph / detail screen
- Removing long-press customize (UI tests and the slider stay)
- 30/90/365 quotes, extra charts, week % label removal
- Crop-zoom, appearance, TestFlight, keychain
- Commit, push, Xcode Cloud, device install

## Implementation

### 1. Default cards

File: `Haiity/Models/StatsCardPrefs.swift`

- Add a named default, `[.yearPulse, .totals]`.
- `StatsCardPrefs()` and uncustomized `load` return that default.
- `isCustomized` is false only when active equals that default.
- Leave stored customized selections alone, including an explicit all-five choice.

File: `Haiity/Views/ContentView.swift`

- `-seed-stats` must pin all five cards for the existing context-menu UI tests, not the new default: `StatsCardPrefs(active: StatsCard.allCases, customized: true)`.

Keep today and week cards always visible. Do not hide them behind prefs.

### 2. Habit row opens the existing card

File: `Haiity/Views/StatsView.swift`

- Do not add a graph view.
- On a ranking row, change `GraphContextMenu` `commit` from `openStatsAdjustments` to open `AppDestination.habit(id).url` with the existing in-app openURL / deep-link path.
- Long-press actions stay `Statistik anpassen`.
- Metric tiles and the year grid keep the current customize commit.
- Locked Pro ranking stays the lock card.

If a short tap still dies on the menu host, fix that host once so an unhandled tap runs `commit`. Do not add a second tap recognizer beside it.

### 3. Empty Statistics

File: `Haiity/Views/StatsView.swift`

- Reuse the Habits empty CTA: same title/body already match, add `Ersten Habit anlegen` with identifier `add-first-habit`.
- Trigger create through the existing `haiity://new` / `requestCreate` path. No new onboarding.

### 4. Names

File: `Haiity/Models/StatsCardPrefs.swift`

Match page copy. Keep raw values.

- `yearPulse`: Rhythmus
- `streakFlame`: Aktuelle Serie
- `todayRing`: Heute
- `weekMomentum`: Diese Woche
- `totals`: Check-ins

Drop Jahres-Puls, Streak-Flamme, Heute-Ring, Wochen-Momentum, Gesamt from UI strings. Detail sentences can stay factual and short.

### 5. VoiceOver

File: `Haiity/Views/StatsView.swift`

Keep each block one element. Put the missing numbers in `accessibilityValue`.

- Today: include open count, streak, and week percent, not only `X von Y`.
- Rhythm: one summary of filled days in the last five months, not only the title. Locked state stays “Nur mit hAiity Pro”.
- Week: one summary of the seven daily percents plus the momentum sentence. Visible % labels can stay.

No Swift Charts Audio Graphs.

## Tests

Update, do not grow a suite:

- `StatsCardPrefsTests.testDefaultIncludesEveryStatsCard` and `testViewPreferencesDefaultToExpandedWithAllStatsCards` → default is year pulse + totals.
- Add one prefs test: uncustomized load picks the new default; a customized all-five payload stays all five.
- Source/behavior test: habit-row commit uses `AppDestination.habit`, not `openStatsAdjustments`.
- Source test: empty Statistics contains `add-first-habit`.
- Source test: accessibility values mentioned above exist.
- `StatsContextMenuUITests` should still see all four metric tiles because `-seed-stats` pins all cards.

Run with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` and `OTHER_SWIFT_FLAGS=-disable-sandbox` if macros need it. `xcode-select -p` is currently Command Line Tools.

Focused:

`HaiityTests/StatsCardPrefsTests`
`HaiityTests/StatsAndReorderTests`
`HaiityTests/FollowUpFixTests/testStatsUseDynamicTypeAndCombineRowsForVoiceOver`
`HaiityTests/AppNavigationTests` if the habit URL path is touched
`HaiityUITests/StatsContextMenuUITests` on a booted simulator

Pending: VoiceOver on a physical device, populated Statistics screenshot, Dynamic Type AX1, German and English strings on device.

## Done when

- Fresh install / uncustomized prefs: today, Rhythmus, Check-ins, week, habit list. No duplicate Heute / Serie / Woche tiles.
- Customized all-five still shows the 2x2.
- Tap a habit row: Habits tab, that card in view. Long-press still opens customize.
- Empty Statistics has the create button.
- Settings names match the page.
- Focused tests above pass. Crop-zoom files remain uncommitted and untouched.
- No commit, push, archive, or TestFlight.

## Execution prompt

Work in /Users/enricomini/Documents/Github/haiity. Recheck git first. Preserve the uncommitted crop-zoom files; do not discard or mix them. Implement docs/plans/2026-09-22-stats-page-hierarchy-plan.md with the smallest diff. Do not commit, push, archive, or upload. Do not print credentials. Use DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer. Run the focused tests in the plan and report exact commands plus any device-only items still pending.
