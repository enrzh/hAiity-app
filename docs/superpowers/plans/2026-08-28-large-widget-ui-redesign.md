# hAiity Large Widget UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有三个可配置 `systemLarge` widget 改为 contribution-first 的 Liste、Raster、Fokus 视觉层，同时保留现有解析、配置、状态、palette、AppIntent 与 deep-link 合同。

**Architecture:** 继续在现有 `RosterWidgetView.swift`、`WidgetGridViews.swift`、`HaiityWidgetView.swift` 和 `WidgetLogic.LargeGeometry` 内完成布局，使用少量共享 View 函数/既有 item 类型，禁止增加架构层。`WidgetData.largeEntry`、三个 provider 和 configuration intent 只继续传递已解析的 `largeItems`，不参与视觉决策或改变 resolver/configuration。

**Tech Stack:** Swift 5.9, SwiftUI, WidgetKit, AppIntents, XCTest, `xcodebuild`, XcodeGen, Xcode Cloud/TestFlight。

## Global Constraints

- 唯一需求源是 `docs/superpowers/specs/2026-08-28-large-widget-ui-redesign.md`；本计划不授权修改 resolver/configuration 的行为或新增产品架构。
- 参考画布为 `332 x 356pt`；外 inset `12pt`，内容高度预算 `332pt`，内容宽度 `308pt`，header-to-content `4pt`。
- Liste 为 `20 + 3*4 + 4*72 + 4 = 324pt`；每行 `72pt`，标题/状态 `18pt`，graph `38pt`，底部 breathing room `4pt`。
- Raster 为 `20 + 4 + 3*96 + 2*8 = 324pt`；精确 `2 x 3`，header 独占 `20pt`，tile 两列，tile graph 至少 `48pt`。
- Fokus 为 `20 + 4 + 136 + 3*48 + 3*4 = 312pt`；featured graph 至少 `92pt`，queue 不得重排首项。
- 所有 action 保持独立 `44 x 44pt` hit area；父级 informational `Link` 不得吞掉 action。
- Graph 仅对有效 contribution habit 使用 `TrailingGrid`；reminder graph-free，只显示 bell、标题、due/missed 和既有 `CheckOffHabitIntent`。
- 空、稀疏、混合类型、无 history、reminder、light/dark/vibrant/custom palette 和 accessibility Dynamic Type 均保持布局预算且不得 clipping/overlap。
- 使用 `HomeWidgetBackground`、`HomeWidgetInk`、`Theme`、`entry.palettes.style(for:)`；completed 只使用小 accent，不给整行/tile/featured 着色。
- 保留 `HaiityWidgetLink.habit`、`HaiityWidgetLink.habits`、`CheckOffHabitIntent`、`AnswerYesHabitIntent`、`AnswerNoHabitIntent`、`ResetHabitIntent` 及 reset-before-first-decision 行为。
- 不改 `WidgetLogic.resolveLargeItems`、三种 configuration intent、排序、可见性、recommendation、recurrence、timeline refresh 或 configuration meaning；不改 GitHub widget、其他 widget family、`project.yml` 的 resolver/configuration 设置。
- 不新增 `Manager`、`Service`、`Factory`、`Strategy`、`Protocol`、`Adapter`、`Coordinator`、`Provider` 或 `Resolver`；每个任务完成后独立提交，不推送。
- 发布任务以现有 release gate 为准：从 build `119` bump 到至少 `120`，执行 archive/export/release checks，并把 Xcode Cloud/TestFlight 作为独立状态报告，不把本地 build 误称为可用 TestFlight build。

---

## 文件职责地图

| 文件 | 职责 | 本计划允许的变更 |
| --- | --- | --- |
| `HaiityWidget/WidgetLogic.swift` | 既有 large 几何常量与纯 widget 逻辑 | 只修正/补充 `LargeGeometry` 常量及预算计算，不改 resolver |
| `HaiityWidget/RosterWidgetView.swift` | 既有 roster、小中尺寸、Liste、Fokus 视图及共享 item/action 代码 | 将 large item 改为无卡片 contribution-first；保留小中尺寸行为 |
| `HaiityWidget/WidgetGridViews.swift` | Raster 2x3 renderer、tile 与 `TrailingGrid` | 固定 header band/tile 几何，复用既有 action/link 语义 |
| `HaiityWidget/HaiityWidgetView.swift` | 既有单 item rendering/accessibility/action 语义 | 仅在共享 primitive 必须复用且不改变现有 family 输出时做最小调整 |
| `HaiityTests/WidgetRenderingTests.swift` | geometry、render smoke、图像/源码合同和可访问性合同 | 增加可观察的尺寸、边界、reminder、palette、链接/action 回归测试 |
| `HaiityTests/WidgetLogicTests.swift` | 既有纯逻辑测试 | 仅在 geometry 常量的纯合同需要时增加测试，不测试新的 resolver 行为 |
| `HaiityTests/GitHubWidgetTests.swift` | widget registration/intent/deep-link contract | 仅增加三种 large kind 仍各注册一次且仅 `.systemLarge` 的回归断言 |
| `project.yml` | 已有 target/build settings/source membership | 不改 configuration/resolver；只有 release build number 若由此文件承载才从 `119` 改为 `120` |
| `tools/release.sh` | archive/export/upload 与 release gate | 仅更新现有准确 build-count 注释/门禁（如当前 gate 要求），不改变上传策略 |

## 精确 Interfaces

以下接口必须继续作为实现边界；任务不得引入同义类型或第二套几何来源：

```swift
enum LargeWidgetLayout: Equatable {
    case list
    case grid
    case focus
}

extension WidgetLogic {
    enum LargeGeometry {
        static let contentHeight: CGFloat = 332
        static let outerPadding: CGFloat = 12
        static let itemSpacing: CGFloat = 4
        static let actionHeight: CGFloat = 44
        static let listHeaderHeight: CGFloat = 20
        static let listRowHeight: CGFloat = 72
        static let listTitleHeight: CGFloat = 18
        static let listGraphHeight: CGFloat = 38
        static let listBottomBreathingRoom: CGFloat = 4
        static let gridHeaderHeight: CGFloat = 20
        static let gridHeaderGap: CGFloat = 4
        static let gridRowHeight: CGFloat = 96
        static let gridColumnGap: CGFloat = 8
        static let gridRowGap: CGFloat = 8
        static let gridGraphMinimumHeight: CGFloat = 48
        static let focusHeaderHeight: CGFloat = 20
        static let focusHeaderGap: CGFloat = 4
        static let focusFeaturedHeight: CGFloat = 136
        static let focusFeaturedGraphMinimumHeight: CGFloat = 92
        static let focusQueueHeight: CGFloat = 48

        static let listContentHeight: CGFloat = 324
        static let gridContentHeight: CGFloat = 324
        static let focusContentHeight: CGFloat = 312
    }
}
```

现有 renderer 接口保持：`LargeListWidgetView(entry:)`、`LargeGridWidgetView(entry:)`、`LargeFocusWidgetView(entry:)`；entry 继续消费 `entry.largeItems`, `entry.largeLayout`, `entry.palettes`, `entry.widgetResetEnabled`, `entry.today(for:)` 与 `entry.calendar(for:)`。

## TDD 执行顺序

### Task 1: Shared Contribution-First Item Primitives and Liste

**Files:**
- Modify: `HaiityWidget/WidgetLogic.swift`
- Modify: `HaiityWidget/RosterWidgetView.swift`
- Test: `HaiityTests/WidgetRenderingTests.swift`

**Interfaces:**
- Consumes: `HaiityEntry`, `WidgetLogic.summary(habit:today:calendar:)`, `TrailingGrid`, `HomeWidgetInk`, `HaiityWidgetLink`, existing AppIntent initializers.
- Produces: existing `LargeListWidgetView(entry:)`, `LargeWidgetHeader(entry:)`, and a shared local large-item rendering path used by Liste/Raster/Fokus without adding a new type layer.

- [ ] **Step 1: Write failing geometry and source-contract tests.** Add:

```swift
func testLargeGeometryMatchesApprovedContributionFirstBudgets() {
    let g = WidgetLogic.LargeGeometry.self
    XCTAssertEqual(g.listHeaderHeight + 3 * g.itemSpacing + 4 * g.listRowHeight
                   + g.listBottomBreathingRoom, 324)
    XCTAssertEqual(g.gridHeaderHeight + g.gridHeaderGap + 3 * g.gridRowHeight
                   + 2 * g.gridRowGap, 324)
    XCTAssertEqual(g.focusHeaderHeight + g.focusHeaderGap + g.focusFeaturedHeight
                   + 3 * g.focusQueueHeight + 3 * g.itemSpacing, 312)
    XCTAssertLessThanOrEqual(g.listContentHeight, g.contentHeight)
    XCTAssertLessThanOrEqual(g.gridContentHeight, g.contentHeight)
    XCTAssertLessThanOrEqual(g.focusContentHeight, g.contentHeight)
    XCTAssertEqual(g.listGraphHeight, 38)
    XCTAssertEqual(g.focusFeaturedGraphMinimumHeight, 92)
}

func testListeDoesNotUseRepeatedCardTreatmentAndUsesLargeGraphRegion() throws {
    let source = try source("HaiityWidget/RosterWidgetView.swift")
    XCTAssertTrue(source.contains("LargeGeometry.listGraphHeight"))
    XCTAssertTrue(source.contains("LargeGeometry.listTitleHeight"))
    XCTAssertFalse(source.contains("RoundedRectangle(cornerRadius: 10"))
    XCTAssertFalse(source.contains("background(.ultraThinMaterial, in: Capsule())"))
}
```

- [ ] **Step 2: Run focused tests and verify failure.** Run:

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HaiityTests/WidgetRenderingTests/testLargeGeometryMatchesApprovedContributionFirstBudgets -only-testing:HaiityTests/WidgetRenderingTests/testListeDoesNotUseRepeatedCardTreatmentAndUsesLargeGraphRegion
```

Expected: `FAIL`; current focus constants are `108/56`, current Liste graph is `14pt`, and the current large item contains rounded card/capsule treatment.

- [ ] **Step 3: Implement the smallest shared path and Liste layout.** Set the constants to the exact interface above. Keep the existing `summary` switch and intents, but render an item as an unframed `VStack`: an `18pt` title/status band, a `38pt` graph band, and a separate trailing action control with `.frame(minWidth: 44, minHeight: 44)`. For a reminder use this exact branch inside the graph band:

```swift
if habit.isReminder {
    Image(systemName: "bell.fill")
        .accessibilityHidden(true)
} else {
    TrailingGrid(habit: habit, today: today) { level in
        HomeWidgetInk.level(level, mode: mode, dark: dark, palette: cellPalette)
    }
}
```

Wrap only the title/metadata/informational area in `Link(destination: HaiityWidgetLink.habit(habit.id))`; keep each existing intent button outside that link. Use `entry.widgetResetEnabled` alone to show reset, including before a decision. `LargeListWidgetView` must use `padding(WidgetLogic.LargeGeometry.outerPadding)`, header `20pt`, four maximum rows at `72pt`, `4pt` gaps, and a final `4pt` bottom spacer; sparse entries leave unused space.

- [ ] **Step 4: Run focused tests and render Liste.** Run the command from Step 2, then:

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HaiityTests/WidgetRenderingTests
```

Expected: focused budget/source tests and existing rendering tests pass; generated Liste output is `664 x 712` pixels at renderer scale `2` and has no card borders/background repetition.

- [ ] **Step 5: Commit the isolated write set.**

```bash
git add HaiityWidget/WidgetLogic.swift HaiityWidget/RosterWidgetView.swift HaiityTests/WidgetRenderingTests.swift
git commit -m "feat: make large widget items contribution first"
```

### Task 2: Raster Header and Six Graph-Led Tiles

**Files:**
- Modify: `HaiityWidget/WidgetGridViews.swift`
- Test: `HaiityTests/WidgetRenderingTests.swift`

**Interfaces:**
- Consumes: `entry.largeItems` in resolved order, `LargeWidgetHeader(entry:)`, shared item/action path from Task 1.
- Produces: `LargeGridWidgetView(entry:)` with exactly six maximum items, a dedicated `20pt` header band, and stable `2 x 3` geometry.

- [ ] **Step 1: Write failing Raster contract tests.** Add tests that assert the source uses `gridHeaderGap`, `gridColumnGap`, `gridRowGap`, `gridGraphMinimumHeight`, and does not place six tiles in the header's `VStack` slot. Add a rendering test with six habits and assert the image is exactly `664 x 712` and visible. The test must inspect six tile graph regions by rendering six distinct level patterns and assert each of the six non-header tile rectangles has pixels while the header band does not overlap them.

```swift
func testRasterUsesDedicatedHeaderAndSixTileBudget() throws {
    let source = try source("HaiityWidget/WidgetGridViews.swift")
    XCTAssertTrue(source.contains("LargeGeometry.gridHeaderGap"))
    XCTAssertTrue(source.contains("LargeGeometry.gridColumnGap"))
    XCTAssertTrue(source.contains("LargeGeometry.gridRowGap"))
    XCTAssertTrue(source.contains("LargeGeometry.gridGraphMinimumHeight"))
    XCTAssertTrue(source.contains("entry.largeItems.prefix(6)"))
}
```

- [ ] **Step 2: Run focused test and verify failure.** Run `xcodebuild test ... -only-testing:HaiityTests/WidgetRenderingTests/testRasterUsesDedicatedHeaderAndSixTileBudget`; expected `FAIL` because current grid uses the old single spacing constant and does not assert the graph minimum/header separation contract.

- [ ] **Step 3: Implement the fixed Raster matrix.** Use a `VStack(spacing: 0)` with a `20pt` header, a `4pt` header gap, then a `LazyVGrid` with two flexible columns, `8pt` column gap, `8pt` row gap, and each tile `96pt`. Keep the resolved list order and `prefix(6)`. Each tile must reserve title/status `20pt`, graph at least `48pt`, and a separate trailing `44pt` action strip. Do not fabricate absent positions and do not stretch sparse tiles. Do not add a tile/card background; use only existing widget background and palette graph level colors.

- [ ] **Step 4: Run Raster tests and inspect screenshots.** Run focused plus the full `WidgetRenderingTests` suite. Expected: six tile graphs never intersect y `0...24pt` content coordinates (header plus gap), no two tile rectangles intersect, and light/dark/vibrant output remains non-empty.

- [ ] **Step 5: Commit.**

```bash
git add HaiityWidget/WidgetGridViews.swift HaiityTests/WidgetRenderingTests.swift
git commit -m "feat: redesign large widget raster layout"
```

### Task 3: Fokus Featured Item, Queue, Reminder and Partial Data

**Files:**
- Modify: `HaiityWidget/RosterWidgetView.swift`
- Modify: `HaiityWidget/WidgetGridViews.swift`
- Test: `HaiityTests/WidgetRenderingTests.swift`

**Interfaces:**
- Consumes: `entry.largeItems.first` as featured item, remaining resolved items in order, `WidgetItemSummary`, existing reminder accessibility label and intents.
- Produces: `LargeFocusWidgetView(entry:)` with `136pt` featured slot and up to three `48pt` queue rows; all three layouts handle reminder/empty/partial data consistently.

- [ ] **Step 1: Write failing focus/reminder/partial tests.** Add tests for `focusFeaturedHeight == 136`, `focusQueueHeight == 48`, one featured graph with at least `92pt` usable graph height, queue rows limited to three, and no `TrailingGrid` in the reminder branch. Assert `largeItems = [reminder]` renders bell/title/status/action but no graph rectangle or `flame.fill`; assert a no-history habit renders an empty seven-row graph; assert sparse Liste/Raster/Fokus preserve nominal geometry rather than stretching items.

```swift
func testReminderIsGraphFreeInEveryLargeLayout() throws {
    let reminder = Habit(name: "Reminder", itemType: .reminder)
    let entry = HaiityEntry(date: .now, habits: [reminder], largeItems: [reminder], largeLayout: .focus)
    for (name, view) in [("list", AnyView(LargeListWidgetView(entry: entry))),
                         ("grid", AnyView(LargeGridWidgetView(entry: entry))),
                         ("focus", AnyView(LargeFocusWidgetView(entry: entry)))] {
        let image = try render(view.frame(width: 332, height: 356), to: "reminder-\(name).png")
        XCTAssertEqual(image.cgImage.map { CGSize(width: $0.width, height: $0.height) }, CGSize(width: 664, height: 712))
        XCTAssertGreaterThan(visiblePixelCount(image), 20)
    }
    let sources = try [source("HaiityWidget/RosterWidgetView.swift"), source("HaiityWidget/WidgetGridViews.swift")]
    for source in sources { XCTAssertTrue(source.contains("if habit.isReminder")) }
}
```

- [ ] **Step 2: Run the focused tests and verify failure.** Run the test by name plus `testLargeRenderersRenderAllItemKindsAndReminderStatusWithoutGraph`; expected failure because current focus is `108pt/56pt` and current reminder branch uses a large decorative bell/card treatment.

- [ ] **Step 3: Implement Fokus and shared state rules.** Set the featured frame to `136pt`, queue frames to `48pt`, use `3 x 4pt` queue gaps, and keep `entry.largeItems.first` featured without status-based sorting. Featured title/status gets the first `20pt`; graph gets at least `92pt`; actions stay independent. Queue shows title, today state, and a short graph strip only for non-reminders. Use hierarchical styles for open/secondary state, existing negative palette for declined/missed, and no full-surface completion tint. For empty entries use `Link(destination: HaiityWidgetLink.habits) { WidgetEmptyState() }` in all three layouts.

- [ ] **Step 4: Run complete item-kind, partial, and appearance tests.** Run `xcodebuild test ... -only-testing:HaiityTests/WidgetRenderingTests`; expected PASS for checkbox, quantity, yes/no, reminder, no-history, empty, sparse, light, dark, vibrant, custom palette, and accessibility-large renders. Inspect reference and Dynamic Type screenshots for no clipping/overlap.

- [ ] **Step 5: Commit.**

```bash
git add HaiityWidget/RosterWidgetView.swift HaiityWidget/WidgetGridViews.swift HaiityTests/WidgetRenderingTests.swift
git commit -m "feat: add focus and reminder-first large widget states"
```

### Task 4: Rendering and Integration Regression Shield

**Files:**
- Modify: `HaiityTests/WidgetRenderingTests.swift`
- Modify: `HaiityTests/GitHubWidgetTests.swift`
- Modify: `HaiityTests/WidgetLogicTests.swift` only if a pure geometry assertion belongs there

**Interfaces:**
- Consumes: existing `LargeWidgetLayout`, `HaiityEntry`, three renderer views, three existing providers/kinds, existing intent/link types.
- Produces: focused observable regression coverage; no product interface changes.

- [ ] **Step 1: Add failing integration contracts.** Assert `HaiityLargeListWidget`, `HaiityLargeGridWidget`, and `HaiityLargeFocusWidget` occur exactly once, each configuration is `.systemLarge`, all three providers use `.demoLarge`, and `WidgetData.largeEntry` still calls the existing `WidgetLogic.resolveLargeItems` signature. Add accessibility/source assertions for `44pt` buttons, existing localized labels, link URLs, and `widgetResetEnabled` before first decision.

- [ ] **Step 2: Run the focused integration tests and verify any missing contracts.** Run:

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HaiityTests/GitHubWidgetTests -only-testing:HaiityTests/WidgetRenderingTests -only-testing:HaiityTests/WidgetLogicTests
```

Expected: all existing behavior remains green; any failure identifies a missing regression assertion or an unintended renderer contract change.

- [ ] **Step 3: Add explicit fixture checks.** Keep representative complete/sparse/mixed/reminder/empty fixtures at `332 x 356`; check image size, non-empty output, header and tile bounding boxes, and no graph pixels for reminders. Verify custom palette changes graph cells/status marks only, while background remains `HomeWidgetBackground`.

- [ ] **Step 4: Run the complete local suite and inspect source diff.** Run `xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`; expected `TEST SUCCEEDED`. Confirm no files outside the three renderer/logic files and focused tests changed.

- [ ] **Step 5: Commit.**

```bash
git add HaiityTests/WidgetRenderingTests.swift HaiityTests/GitHubWidgetTests.swift HaiityTests/WidgetLogicTests.swift
git commit -m "test: lock down large widget rendering contracts"
```

### Task 5: Build 120+ Release, Xcode Cloud and TestFlight Gate

**Files:**
- Modify: `project.yml` only if its existing `CURRENT_PROJECT_VERSION` is the authoritative source
- Modify: `tools/release.sh` only if its existing build-count gate/comment requires the new build
- Test/verify: generated `Haiity.xcodeproj`, archive output, Xcode Cloud/TestFlight state

**Interfaces:**
- Consumes: completed Tasks 1-4, existing release script and signing configuration.
- Produces: local build/archive evidence for build `120` or higher, Xcode Cloud submission evidence, and a separately reported TestFlight processing/available state.

- [ ] **Step 1: Write the release preflight check before changing metadata.** Run:

```bash
git status --short --branch
rg -n "CURRENT_PROJECT_VERSION|MARKETING_VERSION|119|120" project.yml tools/release.sh
xcodegen generate
xcodebuild -showBuildSettings -project Haiity.xcodeproj -scheme Haiity | rg "CURRENT_PROJECT_VERSION|MARKETING_VERSION"
```

Expected: only the five task commits plus pre-existing unrelated user changes are present; the authoritative build number is identified before editing.

- [ ] **Step 2: Bump the authoritative build to 120.** Change only the existing build-number value from `119` to `120`, regenerate Xcode project if required, and do not alter resolver/configuration settings. Verify:

```bash
xcodebuild -showBuildSettings -project Haiity.xcodeproj -scheme Haiity | rg "CURRENT_PROJECT_VERSION"
```

Expected: `CURRENT_PROJECT_VERSION = 120` for app and widget extension.

- [ ] **Step 3: Run release archive/export gates.** Run the repository's existing release command without upload first, then the focused and full tests if the script does not already run them:

```bash
tools/release.sh
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Expected: archive contains app and widget extension with matching version/build, no beta-SDK/macOS upload claim is made, and all tests pass.

- [ ] **Step 4: Commit release metadata independently.**

```bash
git add project.yml tools/release.sh Haiity.xcodeproj/project.pbxproj
git commit -m "release: large widget redesign build 120"
```

- [ ] **Step 5: Trigger and verify Xcode Cloud/TestFlight without conflating states.** Push is explicitly out of scope for this request, so stop after the local commit unless the existing repository workflow independently triggers Xcode Cloud. Record whether Xcode Cloud accepted/started/completed, and whether the exact build `120` is `processing` or `available` in TestFlight. Do not claim upload or TestFlight availability from local archive output alone.

## Self-Review Checklist

- [ ] Spec coverage: geometry, hierarchy, reminder graph-free behavior, actions/links, empty/partial data, appearance modes, custom palettes, Dynamic Type, registration preservation, and release gate each map to a task above.
- [ ] Placeholder scan: every step has concrete files, interfaces, code, commands, expected results, and no unresolved placeholder wording.
- [ ] Type consistency: all tasks use the existing `LargeWidgetLayout`, `HaiityEntry`, `LargeListWidgetView`, `LargeGridWidgetView`, `LargeFocusWidgetView`, `WidgetLogic.LargeGeometry`, `WidgetLogic.resolveLargeItems`, and existing AppIntent/link types.
- [ ] Geometry check: Liste `324pt`, Raster `324pt`, Fokus `312pt`, all under `332pt`; outer inset is `12pt`; actions are at least `44pt`; Raster header gap and matrix gaps are distinct `4pt/8pt` values.
- [ ] Scope check: no manager/service/protocol layer, no resolver/configuration rewrite, no unrelated widget changes, and no product code is changed while authoring this plan.
