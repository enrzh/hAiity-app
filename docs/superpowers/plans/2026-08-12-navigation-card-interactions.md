# Navigation and Card Interactions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the toolbar Mehr menu with a real Habits/Mehr bottom-tab group, keep create as the separate right-side action, and simplify habit cards by removing the header ellipsis while making Bearbeiten available from the graph long-press interaction.

**Architecture:** Introduce a small pure navigation model so tab and deep-link behavior can be tested without SwiftUI. Recompose the existing `ContentView` shells around two persistent tab destinations while retaining the existing iOS 27 measured create circle and the legacy custom chrome. Keep the native graph `contextMenu`; expose Bearbeiten as a guaranteed menu action and attempt preview tapping only through native SwiftUI behavior.

**Tech Stack:** Swift 5.9, SwiftUI, XCTest, XcodeGen, iOS 17 deployment target, release Xcode 26.6 for shipping verification.

## Global Constraints

- Keep `Habits` and `Mehr` as real destinations on every supported OS.
- Keep create visually and semantically separate on the right.
- Do not use `TabRole.prominent` until the release SDK can compile it.
- Preserve the current iOS 27 search-dismissal workarounds and repeated-open/close behavior.
- Preserve graph-cell tap as Nacharbeiten; it must never write immediately.
- Use the native context menu; do not build a custom long-press presentation solely to force preview tapping.
- Keep all existing accessibility labels and minimum 44-point hit targets.
- Add no dependency and perform no unrelated `ContentView` refactor.
- Run shipping checks with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

---

## File Map

- Create `Haiity/Models/AppNavigation.swift`: pure tab and deep-link routing types.
- Create `HaiityTests/AppNavigationTests.swift`: routing and fallback behavior.
- Modify `Haiity/Views/ContentView.swift`: two-destination shells, Mehr tab, deep links, and removal of the toolbar Mehr menu/cover.
- Modify `Haiity/Views/HabitCard.swift`: remove header ellipsis and make the preview/edit path explicit.
- Modify `HaiityTests/GesturePerfTests.swift`: preserve gesture and accessibility source contracts after removing the header button.
- Modify `HaiityTests/SearchFlowTests.swift`: preserve search behavior when switching tabs and opening create.
- Modify `Haiity/Localizable.xcstrings`: only if Xcode extracts a genuinely new user-facing string.
- Modify `tools/release.sh`: raise `MIN_TESTS` by the exact number of new XCTest methods after the full suite is counted.

### Task 1: Pure Navigation Model

**Files:**
- Create: `Haiity/Models/AppNavigation.swift`
- Create: `HaiityTests/AppNavigationTests.swift`

**Interfaces:**
- Produces: `enum AppTab: Hashable { case habits, more, create }`
- Produces: `enum AppMoreDestination: Equatable { case stats, archive }`
- Produces: `enum AppDestination: Equatable { case habits, more, stats, archive, search, create }`
- Produces: `static func resolve(url: URL) -> AppDestination?`
- Produces: `var selectedTab: AppTab`

- [ ] **Step 1: Write failing routing tests**

```swift
import XCTest
@testable import Haiity

final class AppNavigationTests: XCTestCase {
    func testPrimaryDeepLinksSelectTheirTabs() {
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://habits")!), .habits)
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://more")!), .more)
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://stats")!), .stats)
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://archive")!), .archive)
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://search")!), .search)
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://new")!), .create)
    }

    func testUnknownAndForeignURLsAreIgnored() {
        XCTAssertNil(AppDestination.resolve(url: URL(string: "https://aiity.de")!))
        XCTAssertNil(AppDestination.resolve(url: URL(string: "haiity://unknown")!))
    }

    func testNestedMoreDestinationsSelectMoreTab() {
        XCTAssertEqual(AppDestination.stats.selectedTab, .more)
        XCTAssertEqual(AppDestination.archive.selectedTab, .more)
        XCTAssertEqual(AppDestination.more.selectedTab, .more)
        XCTAssertEqual(AppDestination.search.selectedTab, .habits)
        XCTAssertEqual(AppDestination.create.selectedTab, .create)
    }
}
```

- [ ] **Step 2: Generate the project and verify the tests fail**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=haiity-v6' \
  -only-testing:HaiityTests/AppNavigationTests CODE_SIGNING_ALLOWED=NO
```

Expected: compilation fails because `AppDestination` does not exist.

- [ ] **Step 3: Implement the minimal pure model**

```swift
import Foundation

enum AppTab: Hashable {
    case habits
    case more
    case create
}

enum AppMoreDestination: Equatable {
    case stats
    case archive
}

enum AppDestination: Equatable {
    case habits, more, stats, archive, search, create

    static func resolve(url: URL) -> Self? {
        guard url.scheme?.lowercased() == "haiity" else { return nil }
        switch url.host?.lowercased() {
        case "habits": return .habits
        case "more": return .more
        case "stats": return .stats
        case "archive": return .archive
        case "search": return .search
        case "new": return .create
        default: return nil
        }
    }

    var selectedTab: AppTab {
        switch self {
        case .more, .stats, .archive: return .more
        case .create: return .create
        case .habits, .search: return .habits
        }
    }
}
```

- [ ] **Step 4: Run the focused tests**

Run the command from Step 2.

Expected: `AppNavigationTests` executes 3 tests with 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Haiity/Models/AppNavigation.swift HaiityTests/AppNavigationTests.swift Haiity.xcodeproj
git commit -m "Add testable app navigation routes"
```

Do not force-add `Haiity.xcodeproj` if it remains ignored; stage only source and tests in that case.

### Task 2: Two-Destination Native Tab Shells

**Files:**
- Modify: `Haiity/Views/ContentView.swift`
- Test: `HaiityTests/AppNavigationTests.swift`

**Interfaces:**
- Consumes: `AppTab` and `AppDestination` from Task 1.
- Produces: `nativeTab: AppTab`, `habitsTabContent`, and `moreTabContent`.
- Preserves: `showAdd`, `moreSheet`, `morePageRoute`, `createZoomAnchor`, `CreateCircle`, and search state machine.

- [ ] **Step 1: Add a source-contract test for two real tabs**

Add to `AppNavigationTests`:

```swift
func testContentViewDeclaresHabitsAndMoreTabs() throws {
    let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
    XCTAssertTrue(source.contains("value: AppTab.habits"))
    XCTAssertTrue(source.contains("value: AppTab.more"))
    XCTAssertFalse(source.contains("enum NativeTab"))
}

private func sourceURL(_ path: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent(path)
}
```

- [ ] **Step 2: Run the focused test and verify failure**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=haiity-v6' \
  -only-testing:HaiityTests/AppNavigationTests CODE_SIGNING_ALLOWED=NO
```

Expected: the new source-contract test fails because `ContentView` still has `NativeTab` and no Mehr tab.

- [ ] **Step 3: Replace the private tab enum and add persistent destinations**

In `ContentView`:

```swift
@State private var nativeTab: AppTab = .habits

@available(iOS 26, *)
private var moreTabContent: some View {
    NavigationStack {
        MoreView(store: store,
                 cloudStatus: cloudStatus,
                 statsCards: viewPreferences,
                 openPage: { morePageRoute = $0 })
            .navigationTitle(String(localized: "Mehr"))
    }
}
```

Delete the nested `NativeTab` declaration. Do not delete `morePageRoute`; nested Mehr pages continue using it.

- [ ] **Step 4: Add Mehr to the iOS 26 and iOS 27 `TabView`s**

Use the same two destination tabs in both native shells:

```swift
Tab(String(localized: "Habits"), systemImage: "square.grid.2x2",
    value: AppTab.habits) {
    habitsTabContent
}
Tab(String(localized: "Mehr"), systemImage: "ellipsis",
    value: AppTab.more) {
    moreTabContent
}
```

For iOS 26, retain the existing search-role create tab as the third item and continue intercepting `.create`. For iOS 27, retain `CreateCircle` and keep only Habits/Mehr in the native `TabView`. Update `onChange(of: nativeTab)` so only `.create` opens the create page and the selected real tab is restored appropriately after dismissal.

- [ ] **Step 5: Remove the top toolbar Mehr menu and full-screen Mehr cover**

Delete:

- `showMore` and the full-screen cover driven by it.
- `listMenu`, `searchAndMenu`, `listMenuItems`, `menuPlacement`, and the Mehr zoom source/destination used only by that cover.
- Empty-state comments and toolbar items that existed solely to keep Mehr reachable.

Keep the system minimized search item on the Habits screen. On iOS 27 there is no longer a custom trailing toolbar menu competing with search, so simplify only the menu-specific branch; retain the field watcher until repeated-device verification proves the binding bug is gone.

- [ ] **Step 6: Run navigation and search tests**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=haiity-v6' \
  -only-testing:HaiityTests/AppNavigationTests \
  -only-testing:HaiityTests/SearchFlowTests CODE_SIGNING_ALLOWED=NO
```

Expected: all selected tests pass with 0 failures.

- [ ] **Step 7: Commit**

```bash
git add Haiity/Views/ContentView.swift HaiityTests/AppNavigationTests.swift
git commit -m "Move Mehr into bottom navigation"
```

### Task 3: Legacy Bottom Chrome

**Files:**
- Modify: `Haiity/Views/ContentView.swift`
- Modify: `Haiity/Models/ChromeLayout.swift`
- Modify: `HaiityTests/ChromeLayoutTests.swift`

**Interfaces:**
- Consumes: `AppTab`.
- Produces: fallback Habits/Mehr selector and separate create action for iOS 17 through 25.

- [ ] **Step 1: Write a failing selector-width test**

Replace assumptions that the collapsed selector is always two icon-only buttons with a calculation based on the two real destinations:

```swift
func testFallbackSelectorContainsTwoMinimumHitTargets() {
    XCTAssertGreaterThanOrEqual(ChromeLayout.navigationWidth,
                                2 * Theme.Metrics.hit + 3 * ChromeLayout.inset)
}
```

Rename dependent test references from `collapsedSwitcherWidth` to `navigationWidth` only where they describe the new Habits/Mehr selector.

- [ ] **Step 2: Run `ChromeLayoutTests` and verify failure**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=haiity-v6' \
  -only-testing:HaiityTests/ChromeLayoutTests CODE_SIGNING_ALLOWED=NO
```

Expected: compilation fails because `navigationWidth` does not exist.

- [ ] **Step 3: Rename the pure layout concept and wire the fallback selector**

In `ChromeLayout.swift`:

```swift
static let navigationWidth = 2 * Theme.Metrics.hit + 3 * inset
```

Update the fallback chrome in `ContentView` so its two segments bind to `.habits` and `.more`; keep create as the existing trailing circle. Labels must be `Habits`, `Mehr`, and `Neuer Habit`, with identifiers `tab-habits`, `tab-more`, and `create-habit`.

- [ ] **Step 4: Run focused layout tests**

Run the command from Step 2.

Expected: all `ChromeLayoutTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Haiity/Models/ChromeLayout.swift Haiity/Views/ContentView.swift HaiityTests/ChromeLayoutTests.swift
git commit -m "Add Mehr to legacy bottom navigation"
```

### Task 4: Deep-Link Routing Through Tabs

**Files:**
- Modify: `Haiity/Views/ContentView.swift`
- Modify: `HaiityTests/AppNavigationTests.swift`

**Interfaces:**
- Consumes: `AppDestination.resolve(url:)` and `selectedTab`.
- Produces: `handle(_ destination: AppDestination)`.

- [ ] **Step 1: Extend routing tests for route effects**

Add a pure route description:

```swift
struct AppRouteEffect: Equatable {
    let tab: AppTab
    let morePage: AppMoreDestination?
    let opensSearch: Bool
    let opensCreate: Bool
}
```

Add tests:

```swift
func testStatsAndArchiveRouteViaMoreTab() {
    XCTAssertEqual(AppDestination.stats.effect,
                   AppRouteEffect(tab: .more, morePage: .stats,
                                  opensSearch: false, opensCreate: false))
    XCTAssertEqual(AppDestination.archive.effect,
                   AppRouteEffect(tab: .more, morePage: .archive,
                                  opensSearch: false, opensCreate: false))
}

func testSearchAndCreateHaveExplicitEffects() {
    XCTAssertEqual(AppDestination.search.effect.tab, .habits)
    XCTAssertTrue(AppDestination.search.effect.opensSearch)
    XCTAssertTrue(AppDestination.create.effect.opensCreate)
}
```

- [ ] **Step 2: Run the focused tests and verify failure**

Use the Task 1 focused command.

Expected: compilation fails because `AppRouteEffect` and `effect` do not exist.

- [ ] **Step 3: Implement route effects and simplify URL handling**

Define `AppRouteEffect` in `AppNavigation.swift`, then add:

```swift
extension AppDestination {
    var effect: AppRouteEffect {
        switch self {
        case .habits: return .init(tab: .habits, morePage: nil, opensSearch: false, opensCreate: false)
        case .more: return .init(tab: .more, morePage: nil, opensSearch: false, opensCreate: false)
        case .stats: return .init(tab: .more, morePage: .stats, opensSearch: false, opensCreate: false)
        case .archive: return .init(tab: .more, morePage: .archive, opensSearch: false, opensCreate: false)
        case .search: return .init(tab: .habits, morePage: nil, opensSearch: true, opensCreate: false)
        case .create: return .init(tab: .habits, morePage: nil, opensSearch: false, opensCreate: true)
        }
    }
}
```

Map `AppMoreDestination.stats` and `.archive` to the view-local `MorePage`
cases inside `ContentView`. `AppNavigation.swift` must not import SwiftUI or
depend on `MoreView.swift`.

Update `onOpenURL` to resolve once, select the target tab first, then present the nested route/search/create on the next main-actor turn where SwiftUI presentation requires it.

- [ ] **Step 4: Run navigation and search tests**

Run the Task 2 Step 6 command.

Expected: all selected tests pass.

- [ ] **Step 5: Commit**

```bash
git add Haiity/Models/AppNavigation.swift Haiity/Views/ContentView.swift HaiityTests/AppNavigationTests.swift
git commit -m "Route deep links through bottom tabs"
```

### Task 5: Remove Card Ellipsis and Guarantee Edit from Long Press

**Files:**
- Modify: `Haiity/Views/HabitCard.swift`
- Modify: `HaiityTests/GesturePerfTests.swift`

**Interfaces:**
- Preserves: `onEdit: () -> Void` and existing `habitActions`.
- Produces: graph preview with an attempted native tap-to-edit path plus guaranteed `Bearbeiten` context action.

- [ ] **Step 1: Write failing source-contract tests**

Add to the relevant source-level test class:

```swift
func testCardHeaderHasNoEllipsisEditButton() throws {
    let source = try habitCardSource()
    XCTAssertFalse(source.contains("private var editButton"))
    XCTAssertFalse(source.contains("Image(systemName: \"ellipsis\")"))
}

func testLongPressMenuKeepsEditAction() throws {
    let source = try habitCardSource()
    XCTAssertTrue(source.contains("Button(action: onEdit)"))
    XCTAssertTrue(source.contains("String(localized: \"Bearbeiten\")"))
}

private func habitCardSource() throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Haiity/Views/HabitCard.swift")
    return try String(contentsOf: url)
}
```

- [ ] **Step 2: Run the focused test and verify failure**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=haiity-v6' \
  -only-testing:HaiityTests/GesturePerfTests CODE_SIGNING_ALLOWED=NO
```

Expected: the no-ellipsis assertion fails.

- [ ] **Step 3: Remove the header button and retain the menu action**

Delete `editButton` and its insertion in `header`. Ensure `habitActions` contains:

```swift
Button(action: onEdit) {
    Label(String(localized: "Bearbeiten"), systemImage: "pencil")
}
.accessibilityIdentifier("edit-habit")
```

Wrap the preview content in a plain button only if the simulator confirms SwiftUI delivers preview taps:

```swift
Button(action: onEdit) {
    habitPreviewContent
}
.buttonStyle(.plain)
.accessibilityLabel(String(localized: "\(habit.name) bearbeiten"))
```

If the tap is not delivered, leave the preview noninteractive and keep the labeled context-menu action as the guaranteed behavior, as required by the approved spec.

- [ ] **Step 4: Run focused gesture tests**

Run the command from Step 2.

Expected: all selected tests pass.

- [ ] **Step 5: Commit**

```bash
git add Haiity/Views/HabitCard.swift HaiityTests/GesturePerfTests.swift Haiity/Localizable.xcstrings
git commit -m "Simplify habit card actions"
```

Stage `Localizable.xcstrings` only if extraction changed it.

### Task 6: Device and Release Verification

**Files:**
- Modify: `tools/release.sh`
- Modify: `HaiityTests/AppNavigationTests.swift` only if verification exposes a missing pure contract.

**Interfaces:**
- Verifies all outputs from Tasks 1 through 5.

- [ ] **Step 1: Run the complete test suite and count tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=haiity-v6' \
  -only-testing:HaiityTests CODE_SIGNING_ALLOWED=NO | tee /tmp/haiity-navigation-tests.log
rg 'Executed [0-9]+ tests' /tmp/haiity-navigation-tests.log | tail -1
```

Expected: 0 failures and an executed count greater than the current floor of 757.

- [ ] **Step 2: Raise the release test floor exactly**

Set `MIN_TESTS` in `tools/release.sh` to the executed count from Step 1 and update the adjacent comment to identify the navigation/card phase. Never lower the floor.

- [ ] **Step 3: Verify iOS 26 behavior**

On `haiity-v6`:

- Habits and Mehr appear in the left native group.
- Create appears separately on the right and opens once.
- Switching Habits/Mehr preserves Mehr's nested state.
- Search opens and closes for 6 consecutive cycles.
- Opening and closing create does not activate search.
- Long-press graph shows preview and Bearbeiten; graph-cell tap still opens Nacharbeiten.

Capture screenshots for expanded and minimized tab-bar states in `/tmp/haiity-navigation-verification/`.

- [ ] **Step 4: Verify iOS 27 behavior with beta Xcode**

Build only for behavioral verification:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodegen generate
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild build \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=haiity-ios27' CODE_SIGNING_ALLOWED=NO
```

Repeat the Step 3 interaction checks. Confirm the measured create circle aligns with the native Habits/Mehr group in expanded and minimized states. Do not archive or upload from beta Xcode.

- [ ] **Step 5: Run the full release gate**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./tools/release.sh
```

Expected: tests meet the raised floor, archive and export succeed, app/widget versions match, icons and 16 localizations are present, no debug seam is found, and an IPA is written under `/tmp/haiity-release/export/`.

- [ ] **Step 6: Commit the verification floor**

```bash
git add tools/release.sh
git commit -m "Raise test floor for navigation redesign"
```

Do not bump the app build number or upload in this phase unless the user separately requests a release.
