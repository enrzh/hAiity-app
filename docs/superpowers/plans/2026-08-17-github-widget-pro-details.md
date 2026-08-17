# GitHub Graph Widget and Pro Details Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the existing Graph widget select either a habit or the connected GitHub graph, add a shared GitHub username-visibility setting, and make the active Pro row reopen the Pro feature sheet.

**Architecture:** Keep the current habit and streak widget intents unchanged. Add a dedicated graph configuration intent and a shared App Group snapshot cache so the widget extension can render the public GitHub calendar without credentials. Reuse the current GitHub graph layout by moving its UIKit-free view code into a shared source file, and keep the More-page and Pro changes local to their current views.

**Tech Stack:** Swift 5.9, SwiftUI, WidgetKit, AppIntents, XCTest, XcodeGen, iOS 17+

## Global Constraints

- GitHub selection is available only in `HaiityGraphWidget`.
- The app never writes GitHub credentials, tokens, or private account data to the App Group snapshot.
- The Graph widget remains graph-only; it does not render a username heading.
- Username visibility defaults to enabled and is stored in the existing App Group defaults.
- The existing Pro feature list and unlocked footer remain the single source of truth.
- Preserve all unrelated dirty worktree changes and do not alter existing build number `60`.
- Keep the full-test floor at or above the current `MIN_TESTS: 1091` release gate.

### Task 1: Shared GitHub graph data and Graph widget selection

**Files:**
- Create: `Haiity/Models/GitHubWidgetSupport.swift`
- Create: `Haiity/Models/GitHubContributionModels.swift`
- Create: `Haiity/Intents/SelectGraphIntent.swift`
- Create: `Haiity/Views/GitHubContributionGraph.swift`
- Create: `HaiityTests/GitHubWidgetTests.swift`
- Modify: `Haiity/Services/GitHubContributions.swift`
- Modify: `Haiity/Models/GitHubContributionStore.swift`
- Modify: `Haiity/Views/GitHubContributionCard.swift`
- Modify: `HaiityWidget/HaiityWidget.swift`
- Modify: `HaiityWidget/GraphWidgetView.swift`
- Modify: `project.yml`

**Interfaces:**
- `GraphWidgetSource: String, AppEnum, CaseIterable, Codable, Sendable` with `.habit` and `.github`.
- `SelectGraphIntent: WidgetConfigurationIntent` with `@Parameter var source: GraphWidgetSource` and `@Parameter var habit: HabitEntity?`.
- `GitHubContributionSnapshot.sharedCacheURL(fileManager:) -> URL`, throwing `GitHubContributionSnapshot.saveShared(_:to:)`, and non-throwing `GitHubContributionSnapshot.loadShared(from:) -> GitHubContributionSnapshot?`.
- `HaiityEntry.graphSource: GraphWidgetSource` and `HaiityEntry.githubSnapshot: GitHubContributionSnapshot?`.
- `GraphWidgetProvider` supplies `HaiityGraphWidget` entries from the selected source.

- [ ] **Step 1: Write failing tests for source selection and shared cache.**

Add tests with these behaviors:

```swift
func testGraphWidgetSourceHasOnlyHabitAndGitHubCases() {
    XCTAssertEqual(GraphWidgetSource.allCases, [.habit, .github])
}

func testSharedSnapshotRoundTripsWithoutCredentials() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let url = root.appendingPathComponent("github-contributions.json")
    let snapshot = GitHubContributionSnapshot(
        username: "enrzh",
        days: [GitHubContributionDay(date: "2026-08-17", count: 3, level: 2)],
        fetchedAt: Date(timeIntervalSince1970: 0))

    try GitHubContributionSnapshot.saveShared(snapshot, to: url)
    XCTAssertEqual(GitHubContributionSnapshot.loadShared(from: url), snapshot)
    let text = try String(contentsOf: url)
    XCTAssertFalse(text.contains("access_token"))
    XCTAssertFalse(text.contains("device_code"))
}

func testGitHubGraphEntryDoesNotResolveAHabit() {
    let entry = HaiityEntry(date: .now, habits: [], graphSource: .github,
                            githubSnapshot: nil)
    XCTAssertNil(entry.habit)
}
```

- [ ] **Step 2: Run the focused tests and verify they fail for missing interfaces.**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests/GitHubWidgetTests CODE_SIGNING_ALLOWED=NO
```

Expected: compilation or assertion failures naming the new source, cache, or entry interfaces.

- [ ] **Step 3: Split the Codable GitHub models from the app-only network client.**

Move `GitHubContributionDay` and `GitHubContributionSnapshot` into `Haiity/Models/GitHubContributionModels.swift`. Leave `GitHubHTTPTransport`, `GitHubContributionsFetching`, `GitHubContributionsClient`, and the GraphQL decoding types in `Haiity/Services/GitHubContributions.swift`. Update the app tests and imports only as needed; keep the public model names unchanged.

- [ ] **Step 4: Add the shared source enum and App Group snapshot cache.**

Implement the source enum and App Group URL in `GitHubWidgetSupport.swift`. The cache API must encode/decode only `GitHubContributionSnapshot`, use atomic writes, create the parent directory, and return `nil` for missing or malformed files. Keep an overload accepting an explicit URL so tests never touch the real App Group.

- [ ] **Step 5: Make the app store use the shared cache and reload the Graph widget.**

Replace `GitHubContributionStore.defaultCacheURL` with the shared App Group URL and keep injected `cacheURL` support for tests. After `persist(_:)` succeeds, call `WidgetCenter.shared.reloadTimelines(ofKind: "HaiityGraphWidget")`; do not reload timelines for failed fetches or disconnect before removing the cache. Keep the existing app-only credential and contribution clients out of the widget target.

- [ ] **Step 6: Extract the UIKit-free GitHub graph view.**

Move `GitHubContributionGraph`, its layout calculation, and `GitHubGridWidthKey` from `GitHubContributionCard.swift` to `Haiity/Views/GitHubContributionGraph.swift`. Keep `GitHubContributionCard` and `GraphContextMenu` in the original file. Replace its `GridCell` metric references with UIKit-free `GitHubGraphMetrics` constants set to the current values (12 point cells, 3 point gaps, 2 point corners). Preserve the existing public initializer and `GitHubContributionGraph.layout` behavior so current card tests remain valid.

- [ ] **Step 7: Add a dedicated graph configuration intent and provider.**

Create `SelectGraphIntent` with a localized `source` AppEnum and optional habit parameter. Add `GraphWidgetProvider` in `HaiityWidget/HaiityWidget.swift`. For `.habit`, use the existing `WidgetData.entry(selected:)` behavior. For `.github`, read the shared snapshot and create a `HaiityEntry` whose `graphSource` is `.github` and whose habit is `nil`. Keep previews deterministic with `.demo` and a demo GitHub snapshot when the configuration is GitHub.

- [ ] **Step 8: Render the selected GitHub graph in the existing Graph widget.**

Extend `HaiityEntry` with `graphSource` and `githubSnapshot`, defaulting to `.habit` and `nil` so all existing initializers remain valid. Change `HaiityGraphWidget` to use `SelectGraphIntent` and `GraphWidgetProvider`. In `GraphWidgetView`, render `GitHubContributionGraph(days:)` for `.github`, render the existing `TrailingGrid` for `.habit`, and keep the graph-only frame, background, supported families, and widget URL unchanged.

- [ ] **Step 9: Add widget target sources and run focused tests green.**

Add the shared model/cache, `SelectGraphIntent`, `GitHubContributionModels.swift`, `GridCalendar`, `Theme`, and `GitHubContributionGraph.swift` plus any required existing shared dependencies to the `HaiityWidget` target in `project.yml`. Do not add `GitHubContributionStore`, `GitHubDeviceFlow`, credentials, or network clients to the extension. Regenerate the project and rerun `GitHubWidgetTests`, `GitHubCardContractTests`, and `GitHubContributionStoreTests`; all must pass.

### Task 2: GitHub username visibility preference

**Files:**
- Create: `Haiity/Models/GitHubPreferences.swift`
- Modify: `Haiity/Views/GitHubSettingsView.swift`
- Modify: `Haiity/Views/GitHubContributionCard.swift`
- Modify: `Haiity/Localizable.xcstrings`
- Modify: `HaiityTests/GitHubCardContractTests.swift`
- Create: `HaiityTests/GitHubPreferencesTests.swift`

**Interfaces:**
- `GitHubPreferences.showsUsername: Bool`.
- `GitHubPreferences.setShowsUsername(_:in:)` for isolated tests.

- [ ] **Step 1: Write failing preference and view-contract tests.**

Add tests that verify a fresh suite defaults to `true`, a false value round-trips, the GitHub settings source contains a toggle with a stable accessibility identifier, and the card reads the shared preference before drawing its username header.

- [ ] **Step 2: Run the focused preference tests and verify the expected RED state.**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests/GitHubPreferencesTests \
  -only-testing:HaiityTests/GitHubCardContractTests CODE_SIGNING_ALLOWED=NO
```

Expected: failures for the missing preference and toggle contract.

- [ ] **Step 3: Implement the App Group preference.**

Use one key, default `true` when absent, and `UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard`. The test overload must accept a supplied `UserDefaults` suite without changing production storage.

- [ ] **Step 4: Add the concise toggle and wire the card header.**

Add `Toggle(String(localized: "GitHub-Namen anzeigen"), isOn: ...)` to `GitHubSettingsView` with accessibility identifier `github-username-toggle`. Use `@AppStorage` backed by the same App Group key in `GitHubContributionCard`; conditionally omit only the username heading when false, leaving the graph and long-press profile action intact.

- [ ] **Step 5: Add all catalog translations and rerun focused tests.**

Add translated entries for the new key in every existing supported localization. Verify JSON validity and rerun the focused GitHub tests until green.

### Task 3: Active Pro details row

**Files:**
- Modify: `Haiity/Views/MoreView.swift`
- Modify: `HaiityTests/ProGateTests.swift`

- [ ] **Step 1: Write the failing unlocked-row contract.**

Add a test that asserts the unlocked `proSection` contains a tappable button which assigns `paywall = .settings`, retains the `pro-status` identifier, and exposes a distinct `open-pro-details` identifier. Assert that the existing locked branch still exposes `open-paywall`.

- [ ] **Step 2: Run the Pro gate test and verify the expected RED state.**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'id=876E667A-7321-41E1-9008-876B53FF9F71' \
  -only-testing:HaiityTests/ProGateTests CODE_SIGNING_ALLOWED=NO
```

Expected: the new contract fails because the unlocked row is currently static.

- [ ] **Step 3: Make the unlocked row open the existing Pro sheet.**

Wrap the existing highlighted `proRow` in a `Button` only in the `unlocked` branch. Set `paywall = .settings`, keep `pro-status` on the row, add `open-pro-details` to the button, and include the same trailing chevron used by the locked row. Do not change `PaywallView`, purchase, restore, or entitlement logic.

- [ ] **Step 4: Run focused Pro and paywall tests green.**

Run `ProGateTests` and the existing paywall-related tests. Confirm the unlocked footer remains `Freigeschaltet. Danke.` plus `Fertig`, with no purchase or restore button.

### Task 4: Integrated verification and visual checks

**Files:**
- Modify: `HaiityTests/GitHubCardContractTests.swift` only if the integrated source contract needs a stable assertion.
- No production files beyond Tasks 1-3.

- [ ] **Step 1: Regenerate and run the complete iOS test suite.**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'id=876E667A-7321-41E1-9008-876B53FF9F71' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: at least 1,119 tests pass with zero failures.

- [ ] **Step 2: Build and launch the simulator UI.**

Install the Debug app on the booted `haiity-v6` simulator, open More -> GitHub, and capture a screenshot showing the username toggle. Stage an active Pro entitlement with the existing debug hook, tap the Pro row, and capture the feature sheet showing the complete Pro feature list and unlocked footer.

- [ ] **Step 3: Verify Graph widget source behavior.**

Render the Graph widget preview for both `Habit` and `GitHub` source configurations. Confirm the GitHub configuration draws the cached contribution grid, the habit configuration still resolves the selected habit, and neither case draws a username header.

- [ ] **Step 4: Run release verification without uploading.**

Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer tools/release.sh` and confirm the current version/build, app/widget bundle checks, privacy manifests, localization bundles, and debug-seam scans pass. Do not bump or upload a build as part of this feature implementation plan.

- [ ] **Step 5: Review the final diff and report residual risk.**

Run `git diff --check`, inspect `git status`, and confirm all unrelated pre-existing dirty files remain present. Report that widget GitHub data is cache-based and will remain empty until the app has fetched a connected account at least once.
