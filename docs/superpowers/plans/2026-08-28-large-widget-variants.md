# Large Widget Variants Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将当前静态且拥挤的 `systemLarge` Übersicht 改造成可配置的 `Liste`、`Raster`、`Fokus` 三种 hAiity widget，并让每个槽位支持显式项目或 `Automatisch`。

**Architecture:** 继续使用现有 `HabitEntity` 作为 habit/reminder 的统一 AppIntent 实体，不新增数据模型或架构层。三个 `WidgetConfigurationIntent` 只保存槽位选择；现有 `WidgetLogic` 增加一个纯解析函数，先应用 Pro 可见性、显式选择去重，再按推荐顺序填充自动槽位。三个 renderer 共用现有状态摘要、palette、AppIntent action 与 deeplink，旧 `HaiityRosterWidget` 的 gallery 注册替换为 Liste，旧静态实例通过兼容读取路径按自动列表绘制。

**Tech Stack:** Swift 5.9, SwiftUI, WidgetKit, AppIntents, XCTest, XcodeGen, `xcodebuild`。

## Global Constraints

- 仅支持三个新的 `systemLarge` widget：`Liste`、`Raster`、`Fokus`；不向 gallery 注册第四个旧 Übersicht 类型。
- `Liste` 使用 `slot1` 至 `slot4`；`Raster` 使用 `slot1` 至 `slot6`；`Fokus` 使用 `featured`、`queue1` 至 `queue3`。
- 槽位类型必须是可选 `HabitEntity?`；`nil` 精确表示 `Automatisch`，不是持久化虚拟项目。
- `HabitEntity` 同时表示 habit 和 reminder；不得新增 `ReminderEntity`。
- 解析必须经过 `HabitVisibility.visibleActiveHabits(_:unlocked:)` 或等价可见性入口，不能绕过 Pro 限制。
- 显式选择按槽位顺序保留，重复 id 只保留第一次；自动槽位只能补入未显示项目。
- 删除、归档或 Pro 过期的显式选择必须失效并由自动项目补位；不足时隐藏空槽，不显示假项目。
- reminder 不显示 graph 或虚假 streak；checkbox、yes/no、count 使用现有状态和 action 语义。
- 操作继续使用 `CheckOffHabitIntent`、`AnswerYesHabitIntent`、`AnswerNoHabitIntent`、`ResetHabitIntent`；每个 action 只带当前 item id。
- 标题和 graph/内容区使用 `HaiityWidgetLink.habit(habit.id)`；操作区域不可被父级 Link 吞掉。
- 槽位选择由 WidgetKit AppIntent configuration 保存，不写入 habit 的 iCloud 模型；widget 只读 App Group 快照。
- 保持现有小尺寸、中尺寸、锁屏和 GitHub widget 的行为不变。
- 不新增 `Manager`、`Service`、`Factory`、`Strategy`、`Protocol`、`Adapter`、`Coordinator`、`Provider` 或 `Resolver` 类型；解析函数放在 `WidgetLogic`。
- AppIntent 参数标题使用本地化资源：`Automatisch`、`Element 1` 等必须能进入现有德语/英语本地化流程，不能只写不可本地化的 UI 字符串。
- 计划执行时每个任务单独提交；未完成当前任务的测试不得进入下一个写集。

---

## 文件职责地图

| 文件 | 责任 | 允许的本计划变更 |
| --- | --- | --- |
| `Haiity/Intents/LargeWidgetIntent.swift` | 三个 large widget 配置 intent 与槽位参数 | 新建；只放配置声明，不放渲染或解析 |
| `Haiity/Intents/CheckOffHabitIntent.swift` | 现有 `HabitEntity`、查询和 action intents | 仅在编译/本地化需要时修改参数标题，不改变 action 行为 |
| `HaiityWidget/WidgetLogic.swift` | active 可见项目、槽位解析、空槽和 fallback | 增加纯函数与必要的结果值，不新增类型层级 |
| `HaiityWidget/HaiityWidget.swift` | timeline provider、widget bundle、gallery 注册 | 增加三个 AppIntent provider，迁移旧 large 注册 |
| `HaiityWidget/RosterWidgetView.swift` | Liste 的纵向 renderer 及共享 item 操作区 | 重写为由布局模式驱动的既有 View 代码，保持小/中 renderer 不变 |
| `HaiityWidget/WidgetGridViews.swift` | Raster 的 2x3 item 布局 | 增加 Raster view；不修改 habit 数据逻辑 |
| `HaiityWidget/HaiityWidgetView.swift` | 已验证的单 item 状态和操作视觉语言 | 只提取可直接复用的现有局部 view，禁止改变小/中布局结果 |
| `HaiityTests/WidgetLogicTests.swift` | 纯解析、排序、可见性和 fallback 测试 | 增加 slot resolution 测试 |
| `HaiityTests/GitHubWidgetTests.swift` | source contract、注册、deeplink 和类型分支 contract | 增加 intent/registration contract 测试 |
| `HaiityTests/WidgetRenderingTests.swift` | SwiftUI light/dark/vibrant rendering smoke tests | 增加三个 large renderer 的尺寸和 item-type 渲染测试 |
| `project.yml` | XcodeGen source membership 与 build settings | 仅加入新 intent 文件并保持 targets 一致 |
| `tools/release.sh` | release gate、build number、archive/upload 入口 | 仅在已有 build-count gate 要求新文件时更新准确计数 |

## 精确 Interfaces

实现前后使用以下确定接口，避免各写集自行发明名称：

```swift
struct LargeWidgetListIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { get }
    @Parameter(title: "Element 1") var slot1: HabitEntity?
    @Parameter(title: "Element 2") var slot2: HabitEntity?
    @Parameter(title: "Element 3") var slot3: HabitEntity?
    @Parameter(title: "Element 4") var slot4: HabitEntity?
    init()
}

struct LargeWidgetGridIntent: WidgetConfigurationIntent {
    @Parameter(title: "Element 1") var slot1: HabitEntity?
    @Parameter(title: "Element 2") var slot2: HabitEntity?
    @Parameter(title: "Element 3") var slot3: HabitEntity?
    @Parameter(title: "Element 4") var slot4: HabitEntity?
    @Parameter(title: "Element 5") var slot5: HabitEntity?
    @Parameter(title: "Element 6") var slot6: HabitEntity?
    init()
}

struct LargeWidgetFocusIntent: WidgetConfigurationIntent {
    @Parameter(title: "Fokus") var featured: HabitEntity?
    @Parameter(title: "Warteschlange 1") var queue1: HabitEntity?
    @Parameter(title: "Warteschlange 2") var queue2: HabitEntity?
    @Parameter(title: "Warteschlange 3") var queue3: HabitEntity?
    init()
}

enum LargeWidgetLayout { case list, grid, focus }

extension WidgetLogic {
    static func resolveLargeItems(
        habits: [Habit],
        selectedIDs: [UUID?],
        limit: Int,
        unlocked: Bool,
        today: String,
        calendar: Calendar
    ) -> [Habit]
}

struct HaiityEntry: TimelineEntry {
    var largeItems: [Habit]
    static var demoLarge: HaiityEntry { get }
}
```

The function receives already-ordered slots. It returns at most `limit` visible items, with no duplicate ids. It filters using `HabitVisibility.visibleActiveHabits(habits, unlocked: unlocked)` before matching explicit ids. `today` and `calendar` are passed so the automatic order can call the existing `recommended` logic without reading process-global state.

---

### Task 1: Selection Intents and Localized Entities

**写集边界:** 只新增配置 intent，并让它们使用现有 `HabitEntity` query。不得修改 renderer、provider 或 `WidgetLogic`。

**Files:**
- Create: `Haiity/Intents/LargeWidgetIntent.swift`
- Modify: `project.yml` source membership for app and widget targets
- Test: `HaiityTests/GitHubWidgetTests.swift`

**Interfaces:**
- Consumes: `HabitEntity`, `HabitEntityQuery`, `WidgetConfigurationIntent`。
- Produces: `LargeWidgetListIntent`, `LargeWidgetGridIntent`, `LargeWidgetFocusIntent`，每个可选参数类型为 `HabitEntity?`。

- [ ] **Step 1: Write the failing contract tests**

```swift
func testLargeWidgetIntentsExposeExpectedOptionalSlots() throws {
    let source = try source("Haiity/Intents/LargeWidgetIntent.swift")
    XCTAssertTrue(source.contains("struct LargeWidgetListIntent: WidgetConfigurationIntent"))
    XCTAssertTrue(source.contains("struct LargeWidgetGridIntent: WidgetConfigurationIntent"))
    XCTAssertTrue(source.contains("struct LargeWidgetFocusIntent: WidgetConfigurationIntent"))
    XCTAssertEqual(source.components(separatedBy: "var slot").count - 1, 10)
    XCTAssertTrue(source.contains("var featured: HabitEntity?"))
    XCTAssertTrue(source.contains("var queue1: HabitEntity?"))
    XCTAssertTrue(source.contains("var queue2: HabitEntity?"))
    XCTAssertTrue(source.contains("var queue3: HabitEntity?"))
    XCTAssertFalse(source.contains("struct ReminderEntity"))
}

func testLargeWidgetIntentTitlesAreLocalizable() throws {
    let source = try source("Haiity/Intents/LargeWidgetIntent.swift")
    XCTAssertTrue(source.contains("LocalizedStringResource"))
    XCTAssertTrue(source.contains("Automatisch"))
    XCTAssertTrue(source.contains("Element 1"))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HaiityTests/GitHubWidgetTests/testLargeWidgetIntentsExposeExpectedOptionalSlots -only-testing:HaiityTests/GitHubWidgetTests/testLargeWidgetIntentTitlesAreLocalizable
```

Expected: `FAIL` because `Haiity/Intents/LargeWidgetIntent.swift` does not exist.

- [ ] **Step 3: Add the minimal intent declarations**

```swift
import AppIntents

struct LargeWidgetListIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Liste"
    static var description = IntentDescription("Vier Habits oder Erinnerungen auswählen; leer bedeutet Automatisch.")
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Element 1") var slot1: HabitEntity?
    @Parameter(title: "Element 2") var slot2: HabitEntity?
    @Parameter(title: "Element 3") var slot3: HabitEntity?
    @Parameter(title: "Element 4") var slot4: HabitEntity?

    init() {}
}

struct LargeWidgetGridIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Raster"
    static var description = IntentDescription("Sechs Habits oder Erinnerungen auswählen; leer bedeutet Automatisch.")
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Element 1") var slot1: HabitEntity?
    @Parameter(title: "Element 2") var slot2: HabitEntity?
    @Parameter(title: "Element 3") var slot3: HabitEntity?
    @Parameter(title: "Element 4") var slot4: HabitEntity?
    @Parameter(title: "Element 5") var slot5: HabitEntity?
    @Parameter(title: "Element 6") var slot6: HabitEntity?

    init() {}
}

struct LargeWidgetFocusIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Fokus"
    static var description = IntentDescription("Einen Fokus und drei Warteschlangen-Elemente auswählen; leer bedeutet Automatisch.")
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Fokus") var featured: HabitEntity?
    @Parameter(title: "Warteschlange 1") var queue1: HabitEntity?
    @Parameter(title: "Warteschlange 2") var queue2: HabitEntity?
    @Parameter(title: "Warteschlange 3") var queue3: HabitEntity?

    init() {}
}
```

Add `Haiity/Intents/LargeWidgetIntent.swift` to the app and widget sources in `project.yml`, then run `xcodegen generate`.

- [ ] **Step 4: Run the focused test and verify it passes**

Run:

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HaiityTests/GitHubWidgetTests/testLargeWidgetIntentsExposeExpectedOptionalSlots -only-testing:HaiityTests/GitHubWidgetTests/testLargeWidgetIntentTitlesAreLocalizable
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit the isolated write set**

```bash
git add Haiity/Intents/LargeWidgetIntent.swift project.yml Haiity.xcodeproj/project.pbxproj HaiityTests/GitHubWidgetTests.swift
git commit -m "feat: add configurable large widget intents"
```

---

### Task 2: Slot Resolver, Visibility, Provider Input

**写集边界:** 只增加 `WidgetLogic.resolveLargeItems` 与 timeline entry/provider 所需数据传递。不得修改三种 renderer 的布局。

**Files:**
- Modify: `HaiityWidget/WidgetLogic.swift`
- Modify: `HaiityWidget/HaiityWidget.swift`
- Test: `HaiityTests/WidgetLogicTests.swift`

**Interfaces:**
- Consumes: 三个 intent 的槽位值，转换为 `[UUID?]`；`HabitVisibility.visibleActiveHabits`；现有 `WidgetLogic.recommended`。
- Produces: `WidgetLogic.resolveLargeItems(habits:selectedIDs:limit:unlocked:today:calendar:) -> [Habit]`；provider entries carrying the resolved ordered items and layout.

- [ ] **Step 1: Write failing resolver tests**

```swift
func testLargeResolverKeepsExplicitOrderAndFillsAutomaticSlots() {
    let a = named("A"), b = named("B"), c = named("C")
    let result = WidgetLogic.resolveLargeItems(
        habits: [a, b, c], selectedIDs: [b.id, nil, a.id], limit: 3,
        unlocked: true, today: today, calendar: cal)
    XCTAssertEqual(result.map(\.id), [b.id, c.id, a.id])
}

func testLargeResolverDeduplicatesExplicitAndAutomaticItems() {
    let a = named("A"), b = named("B")
    let result = WidgetLogic.resolveLargeItems(
        habits: [a, b], selectedIDs: [a.id, a.id, nil, nil], limit: 4,
        unlocked: true, today: today, calendar: cal)
    XCTAssertEqual(result.map(\.id), [a.id, b.id])
}

func testLargeResolverDropsArchivedDeletedAndProHiddenSelections() {
    let archived = named("Archived", archived: today)
    let live = named("Live")
    let result = WidgetLogic.resolveLargeItems(
        habits: [archived, live], selectedIDs: [archived.id, UUID()], limit: 2,
        unlocked: true, today: today, calendar: cal)
    XCTAssertEqual(result.map(\.id), [live.id])
}

func testLargeResolverAppliesFreeLimitWhenProIsLocked() {
    let habits = (1...5).map { named("H\($0)") }
    let result = WidgetLogic.resolveLargeItems(
        habits: habits, selectedIDs: habits.suffix(2).map(\.id), limit: 6,
        unlocked: false, today: today, calendar: cal)
    XCTAssertEqual(result.count, HabitVisibility.freeHabitLimit)
    XCTAssertTrue(result.allSatisfy { habits.prefix(HabitVisibility.freeHabitLimit).contains { $0.id == $1.id } })
}

func testLargeResolverReturnsNoItemsForEmptyVisibleStore() {
    XCTAssertTrue(WidgetLogic.resolveLargeItems(
        habits: [], selectedIDs: [nil, nil, nil, nil], limit: 4,
        unlocked: true, today: today, calendar: cal).isEmpty)
}
```

- [ ] **Step 2: Run the resolver tests and verify failure**

Run:

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HaiityTests/WidgetLogicTests/testLargeResolverKeepsExplicitOrderAndFillsAutomaticSlots -only-testing:HaiityTests/WidgetLogicTests/testLargeResolverDeduplicatesExplicitAndAutomaticItems -only-testing:HaiityTests/WidgetLogicTests/testLargeResolverDropsArchivedDeletedAndProHiddenSelections -only-testing:HaiityTests/WidgetLogicTests/testLargeResolverAppliesFreeLimitWhenProIsLocked -only-testing:HaiityTests/WidgetLogicTests/testLargeResolverReturnsNoItemsForEmptyVisibleStore
```

Expected: `FAIL` because `resolveLargeItems` is not defined.

- [ ] **Step 3: Implement the pure resolver**

```swift
static func resolveLargeItems(
    habits: [Habit],
    selectedIDs: [UUID?],
    limit: Int,
    unlocked: Bool,
    today: String,
    calendar: Calendar
) -> [Habit] {
    let visible = HabitVisibility.visibleActiveHabits(habits, unlocked: unlocked)
    let byID = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
    var result: [Habit] = []
    var used = Set<UUID>()

    for id in selectedIDs.compactMap({ $0 }) {
        guard result.count < limit, let habit = byID[id], used.insert(id).inserted else { continue }
        result.append(habit)
    }

    let recommendedID = recommended(habits: visible, today: today, calendar: calendar)?.id
    let ordered = visible.sorted { left, right in
        if left.id == recommendedID { return true }
        if right.id == recommendedID { return false }
        return visible.firstIndex(where: { $0.id == left.id })!
            < visible.firstIndex(where: { $0.id == right.id })!
    }.filter { !used.contains($0.id) }
    result.append(contentsOf: ordered.prefix(max(0, limit - result.count)))
    return result
}
```

Use the existing streak/recommendation calculation rather than adding a new ranking type. In the provider, read the shared store once, obtain visible habits through the same `unlocked` flag, resolve the configuration slots, and put the resulting `[Habit]` into the existing `HaiityEntry` extension fields. Keep the old static provider as a compatibility provider only for already-installed `HaiityRosterWidget` instances; it must not be registered in the gallery after Task 3.

- [ ] **Step 4: Run all widget logic tests**

Run:

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HaiityTests/WidgetLogicTests
```

Expected: `TEST SUCCEEDED` and all existing resolver, reminder, Pro, roster, and new large resolver tests pass.

- [ ] **Step 5: Commit the isolated write set**

```bash
git add HaiityWidget/WidgetLogic.swift HaiityWidget/HaiityWidget.swift HaiityTests/WidgetLogicTests.swift
git commit -m "feat: resolve configurable large widget slots"
```

---

### Task 3: Liste, Raster, Fokus Renderers and Gallery Registration

**写集边界:** 只实现三个 large renderer、kind/provider 注册与旧 Übersicht gallery 迁移。解析契约来自 Task 2；不改变 AppIntent declarations 或 pure resolver。

**Files:**
- Modify: `HaiityWidget/HaiityWidget.swift`
- Modify: `HaiityWidget/RosterWidgetView.swift`
- Modify: `HaiityWidget/WidgetGridViews.swift`
- Modify: `HaiityWidget/HaiityWidgetView.swift` only when a small existing item view is safely reused without changing its output
- Test: `HaiityTests/GitHubWidgetTests.swift`, `HaiityTests/WidgetRenderingTests.swift`

**Interfaces:**
- Consumes: `LargeWidgetListIntent`, `LargeWidgetGridIntent`, `LargeWidgetFocusIntent`; resolved entry items; `LargeWidgetLayout`.
- Produces: unique kinds `HaiityLargeListWidget`, `HaiityLargeGridWidget`, `HaiityLargeFocusWidget`, each `.supportedFamilies([.systemLarge])`; views `LargeListWidgetView`, `LargeGridWidgetView`, `LargeFocusWidgetView`.

- [ ] **Step 1: Write failing registration and renderer tests**

```swift
func testThreeLargeWidgetsAreRegisteredAndOldOverviewIsNotInGallery() throws {
    let source = try source("HaiityWidget/HaiityWidget.swift")
    XCTAssertTrue(source.contains("HaiityLargeListWidget"))
    XCTAssertTrue(source.contains("HaiityLargeGridWidget"))
    XCTAssertTrue(source.contains("HaiityLargeFocusWidget"))
    XCTAssertEqual(source.components(separatedBy: ".supportedFamilies([.systemLarge])").count - 1, 3)
    XCTAssertFalse(source.contains("HaiityRosterWidget()"))
}

func testLargeRenderersKeepReminderGraphFreeAndUseAllActions() throws {
    let roster = try source("HaiityWidget/RosterWidgetView.swift")
    let grid = try source("HaiityWidget/WidgetGridViews.swift")
    for text in [roster, grid] {
        XCTAssertTrue(text.contains("habit.isReminder"))
        XCTAssertTrue(text.contains("CheckOffHabitIntent"))
        XCTAssertTrue(text.contains("AnswerYesHabitIntent"))
        XCTAssertTrue(text.contains("AnswerNoHabitIntent"))
        XCTAssertTrue(text.contains("ResetHabitIntent"))
        XCTAssertTrue(text.contains("HaiityWidgetLink.habit"))
    }
}

@MainActor
func testAllLargeRenderersProducePixelsAtRealLargeGeometry() throws {
    let entry = HaiityEntry.demoLarge
    try render(LargeListWidgetView(entry: entry).frame(width: 332, height: 356), to: "large-list.png")
    try render(LargeGridWidgetView(entry: entry).frame(width: 332, height: 356), to: "large-grid.png")
    try render(LargeFocusWidgetView(entry: entry).frame(width: 332, height: 356), to: "large-focus.png")
}
```

- [ ] **Step 2: Run the new tests and verify failure**

Run:

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HaiityTests/GitHubWidgetTests/testThreeLargeWidgetsAreRegisteredAndOldOverviewIsNotInGallery -only-testing:HaiityTests/GitHubWidgetTests/testLargeRenderersKeepReminderGraphFreeAndUseAllActions -only-testing:HaiityTests/WidgetRenderingTests/testAllLargeRenderersProducePixelsAtRealLargeGeometry
```

Expected: `FAIL` because the three kinds and views are not yet defined.

- [ ] **Step 3: Implement the three fixed layouts**

Use these layout invariants in the renderer code:

```swift
struct LargeListWidgetView: View {
    let entry: HaiityEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LargeWidgetHeader(entry: entry)
            ForEach(entry.largeItems.prefix(4)) { habit in
                LargeListItem(habit: habit, entry: entry)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(12)
    }
}

struct LargeGridWidgetView: View {
    let entry: HaiityEntry
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(entry.largeItems.prefix(6)) { habit in
                LargeGridItem(habit: habit, entry: entry)
                    .frame(minHeight: 96)
            }
        }
        .padding(12)
    }
}

struct LargeFocusWidgetView: View {
    let entry: HaiityEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LargeWidgetHeader(entry: entry)
            if let focus = entry.largeItems.first {
                LargeFocusItem(habit: focus, entry: entry)
                    .frame(maxHeight: 220)
            }
            ForEach(entry.largeItems.dropFirst().prefix(3)) { habit in
                LargeQueueItem(habit: habit, entry: entry)
                    .frame(minHeight: 30)
            }
        }
        .padding(12)
    }
}
```

The actual item code must keep the existing `summary`/`actionButtons` branches: reminder uses a bell and status row; checkbox uses check/reset; yes/no uses yes/no/reset; count uses increment/reset. Wrap only title and non-action content in `Link(destination: HaiityWidgetLink.habit(habit.id))`. Keep every action button outside that Link. Use fixed minimum hit heights and clip each item to its own rounded shape so the large widget cannot overlap or create an extra background card.

Update `HaiityWidget.swift` with three `AppIntentConfiguration` registrations. Use one provider per intent or one generic-free concrete provider per configuration, with these exact kinds:

```swift
AppIntentConfiguration(kind: "HaiityLargeListWidget", intent: LargeWidgetListIntent.self, provider: LargeListWidgetProvider())
AppIntentConfiguration(kind: "HaiityLargeGridWidget", intent: LargeWidgetGridIntent.self, provider: LargeGridWidgetProvider())
AppIntentConfiguration(kind: "HaiityLargeFocusWidget", intent: LargeWidgetFocusIntent.self, provider: LargeFocusWidgetProvider())
```

All three descriptions and display names must use `String(localized:)`. Remove `HaiityRosterWidget()` from `HaiityWidgetBundle`; retain a private compatibility path in the provider code for an installed old kind, but do not expose it through the bundle gallery.

- [ ] **Step 4: Run renderer, contract, and existing widget tests**

Run:

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HaiityTests/WidgetRenderingTests -only-testing:HaiityTests/GitHubWidgetTests
```

Expected: `TEST SUCCEEDED`; the three PNG render outputs are non-empty, and existing GitHub, reminder, action, and deeplink contracts remain green.

- [ ] **Step 5: Commit the isolated write set**

```bash
git add HaiityWidget/HaiityWidget.swift HaiityWidget/RosterWidgetView.swift HaiityWidget/WidgetGridViews.swift HaiityWidget/HaiityWidgetView.swift HaiityTests/GitHubWidgetTests.swift HaiityTests/WidgetRenderingTests.swift
git commit -m "feat: add list grid and focus large widgets"
```

---

### Task 4: Integration, Migration, and Full Regression Gates

**写集边界:** 只补齐跨模块测试、旧 Übersicht 兼容测试、App Group 空状态和配置失效 contract；不得扩大 renderer 或 resolver 功能。

**Files:**
- Modify: `HaiityTests/WidgetLogicTests.swift`
- Modify: `HaiityTests/GitHubWidgetTests.swift`
- Modify: `HaiityTests/WidgetRenderingTests.swift`
- Modify: `HaiityWidget/HaiityWidget.swift` only for compatibility reads exposed by failing tests
- Modify: `HaiityWidget/WidgetLogic.swift` only for compatibility reads exposed by failing tests

**Interfaces:**
- Consumes: the exact intent, resolver, provider, renderer, kind names from Tasks 1-3.
- Produces: regression proof for old static overview migration, item action isolation, Pro visibility, empty App Group data, deleted/archived choices, and all three layouts.

- [ ] **Step 1: Add failing integration tests**

```swift
func testOldOverviewCompatibilityUsesAutomaticListWithoutGalleryRegistration() throws {
    let widget = try source("HaiityWidget/HaiityWidget.swift")
    XCTAssertTrue(widget.contains("HaiityRosterProvider"))
    XCTAssertTrue(widget.contains("automatic"))
    XCTAssertFalse(widget.contains("HaiityRosterWidget()"))
}

func testLargeWidgetActionsRemainScopedToCurrentItem() throws {
    let sources = try [
        source("HaiityWidget/RosterWidgetView.swift"),
        source("HaiityWidget/WidgetGridViews.swift")
    ]
    for source in sources {
        XCTAssertTrue(source.contains("init(habit: habit)"))
        XCTAssertTrue(source.contains("HaiityWidgetLink.habit(habit.id)"))
        XCTAssertFalse(source.contains("widgetURL(URL(string: \"haiity://habits\")"))
    }
}

func testLargeWidgetConfigurationDoesNotPersistIntoHabitData() throws {
    let source = try source("HaiityWidget/WidgetLogic.swift")
    XCTAssertFalse(source.contains("save") && source.contains("selectedIDs"))
    XCTAssertFalse(source.contains("iCloud") && source.contains("slot"))
}
```

- [ ] **Step 2: Run the integration tests and verify failure**

Run:

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HaiityTests/WidgetLogicTests -only-testing:HaiityTests/GitHubWidgetTests -only-testing:HaiityTests/WidgetRenderingTests
```

Expected: `FAIL` only for newly added compatibility/isolation assertions; previously passing widget tests must remain green.

- [ ] **Step 3: Implement only the missing compatibility behavior**

For an old static instance, keep the existing `HaiityRosterProvider` able to read `WidgetData.entry()` and render the automatic list. Do not add an old `Widget` back to `HaiityWidgetBundle`. For invalid configured ids, use the already-tested resolver result; never write a replacement into shared data. For no visible items, pass the existing `WidgetEmptyState` path and leave App Group/iCloud untouched.

The integration implementation must preserve these exact actions:

```swift
CheckOffHabitIntent(habit: habit)
AnswerYesHabitIntent(habit: habit)
AnswerNoHabitIntent(habit: habit)
ResetHabitIntent(habit: habit)
```

The `ResetHabitIntent` button is rendered from initial state whenever `entry.widgetResetEnabled` is true, not only after a decision. A stale action may safely no-op through the existing intent store lookup.

- [ ] **Step 4: Run the full unit test target and source hygiene checks**

Run:

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
git diff --check
```

Expected: `TEST SUCCEEDED`; `git diff --check` prints no output. A simulator run is a compile/test gate only and is not evidence of physical iPhone behavior.

- [ ] **Step 5: Commit the isolated integration write set**

```bash
git add HaiityWidget/HaiityWidget.swift HaiityWidget/WidgetLogic.swift HaiityTests/WidgetLogicTests.swift HaiityTests/GitHubWidgetTests.swift HaiityTests/WidgetRenderingTests.swift
git commit -m "test: cover large widget migration and interactions"
```

---

### Task 5: Release Build and Xcode Cloud Handoff

**写集边界:** 只做版本号、release verification、commit/push 和 Xcode Cloud/TestFlight 操作；不得继续改 widget behavior。

**Files:**
- Modify: `project.yml` app and widget `CFBundleVersion` from current `112` to next unique build `118` only if no newer build has landed in the meantime
- Regenerate: `Haiity.xcodeproj/project.pbxproj`
- Modify: `tools/release.sh` only if its expected test count/source gate requires the newly added test count
- Test: release script and Xcode Cloud processed build

**Interfaces:**
- Consumes: all three widget kinds, AppIntent generated metadata, passing full unit tests, and current App Store Connect build state.
- Produces: app/widget build `118` unless a newer verified TestFlight build exists, pushed `main`, an Xcode Cloud `Default` workflow run, and build assigned to `Internal` and `Preview` after processing.

- [ ] **Step 1: Verify build-number preconditions before editing**

Run:

```bash
git status --short
git log -1 --oneline
rg -n "CURRENT_PROJECT_VERSION|CFBundleVersion|MARKETING_VERSION" project.yml Haiity.xcodeproj/project.pbxproj
```

Expected: only known unrelated untracked files remain; current source build is `112`; no later local commit has changed the release files. If App Store Connect already contains a build newer than `117`, choose the next unused verified number and update this task's commit message accordingly.

- [ ] **Step 2: Write and verify the next build number**

Change both app and widget version values in `project.yml` to `118`, regenerate the project, then run:

```bash
xcodegen generate
git diff --check
rg -n "CURRENT_PROJECT_VERSION: 118|CFBundleVersion.*118" project.yml Haiity.xcodeproj/project.pbxproj
```

Expected: both targets resolve to `118`; no whitespace errors.

- [ ] **Step 3: Run the release gate**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer OUT=/tmp/haiity-release-118 ./tools/release.sh
```

Expected: the project regenerates, all configured unit tests compile/run, archive verification passes, and the final line reports `hAiity` with build `118`. Do not claim physical-device validation unless the approved iPhone is connected and unlocked; do not use simulators or the device hub for the physical gate.

- [ ] **Step 4: Commit and push only the release write set**

```bash
git add project.yml Haiity.xcodeproj/project.pbxproj tools/release.sh
git commit -m "release: large widget variants build 118"
git push origin main
```

Expected: push succeeds and `origin/main` contains the release commit. Preserve `.runtime-stats-fixture.json`, `.superpowers/`, and unrelated plan files.

- [ ] **Step 5: Trigger and verify Xcode Cloud**

In App Store Connect, open hAiity's `Default` workflow, verify source branch `main` and push trigger, then wait for the pushed commit's build. Confirm the build is accepted and processed before assigning it.

Expected state transitions: `Queued/Running` -> `Processing` -> `Ready to Test`; if the workflow trigger is disabled, start `Default` manually from the pushed commit and record that fact in the release handoff.

- [ ] **Step 6: Assign the processed build**

In **Apps -> hAiity -> TestFlight -> iOS**, add the exact processed build `118` to both `Internal` and `Preview`. Reopen both groups and verify `118` is listed. Report separately whether the build is accepted, processing, or available; do not report upload completion as TestFlight availability.

- [ ] **Step 7: Commit release metadata only when required by the gate**

If `tools/release.sh` required a changed test floor or source count, commit that already-reviewed change separately:

```bash
git add tools/release.sh
git commit -m "test: update release gate for large widgets"
git push origin main
```

Expected: the second push changes only the release gate and triggers at most one additional Xcode Cloud run; do not alter product code in this step.

---

## Self-Review

### Spec coverage

- Three layouts and exact slot counts: Tasks 1 and 3.
- Explicit selection, `Automatisch`, stable ordering, duplicate removal and fallback: Task 2 tests and resolver.
- Pro visibility, archive/delete invalidation and free-limit behavior: Task 2 and Task 4.
- Habit checkbox, yes/no, count, reminder rendering and all actions: Task 3 renderer contract and Task 4 action isolation.
- Item deeplinks without parent action interception: Tasks 3 and 4.
- Reminder graph/streak exclusion: Task 3.
- AppIntent parameter localization: Task 1.
- App Group read-only boundary and no iCloud model changes: Task 4.
- Empty state and stale action behavior: Task 4.
- Old Übersicht migration to automatic Liste behavior and gallery removal: Tasks 3 and 4.
- Three unique `.systemLarge` registrations: Task 3.
- Rendering at real large geometry in light/dark/vibrant modes: Task 3 and Task 4.
- Build, push, Xcode Cloud, TestFlight Internal/Preview assignment: Task 5.

### Placeholder scan

The plan contains no unresolved design marker or unspecified implementation step. Every code-changing task includes concrete file paths, signatures, code, commands, expected results, and a commit command. It does not use a cross-reference that asks an agent to copy another task's implementation.

### Type consistency

`HabitEntity?` is used consistently by all three intents. Their ordered values become `[UUID?]`, which is consumed by `WidgetLogic.resolveLargeItems(...)` and returns `[Habit]`. Providers place those habits into `HaiityEntry.largeItems`; renderers consume `[Habit]` and call existing `WidgetLogic.summary`, action intents, and `HaiityWidgetLink.habit`. The exact widget kinds and intent types are used consistently in registration and tests.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-28-large-widget-variants.md`. Two execution options:

1. **Subagent-Driven (recommended)** - dispatch a fresh subagent per task, review between tasks, and keep each write set isolated.
2. **Inline Execution** - execute tasks in this session with executing-plans and checkpoints.

For this project, use `sub2api/gpt-5.6-luna` with low reasoning for implementation subagents; the planning agent remains responsible for coordination and review.
