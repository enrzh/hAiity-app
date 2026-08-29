# Task 2 Report

## 改动

- 在 `WidgetLogic` 增加 `resolveLargeItems`，先调用 `HabitVisibility.visibleActiveHabits(_:unlocked:)`，再按槽位保留有效显式选择、去重，并用推荐顺序自动补位。
- `HaiityEntry` 增加大型 Widget 的有序 `largeItems` 与 `largeLayout` 输入。
- `WidgetData` 增加大型 entry/timeline 输入，并新增三个对应 provider，将三个 intent 的槽位转换为 `[UUID?]`。
- 未修改三种 renderer，也未修改旧静态 provider 的兼容行为。
- 测试文件增加 brief 要求的五个 resolver 测试；修正 brief 中无法通过 Swift 编译的嵌套闭包参数为等价合法写法。

## 测试

失败阶段（按 TDD）：

```text
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -only-testing:HaiityTests/WidgetLogicTests/testLargeResolverKeepsExplicitOrderAndFillsAutomaticSlots -only-testing:HaiityTests/WidgetLogicTests/testLargeResolverDeduplicatesExplicitAndAutomaticItems -only-testing:HaiityTests/WidgetLogicTests/testLargeResolverDropsArchivedDeletedAndProHiddenSelections -only-testing:HaiityTests/WidgetLogicTests/testLargeResolverAppliesFreeLimitWhenProIsLocked -only-testing:HaiityTests/WidgetLogicTests/testLargeResolverReturnsNoItemsForEmptyVisibleStore
```

按预期因 `resolveLargeItems` 不存在而失败；实现后同一组测试通过。

最终验证：

```text
xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -only-testing:HaiityTests/WidgetLogicTests
```

结果：`TEST SUCCEEDED`，62 tests，0 failures。使用已有 simulator `sAiity Verification`，未创建设备。

## 提交

提交信息：`feat: resolve configurable large widget slots`

提交哈希：`f25d7549a6e4ab954cee38500482561d92b88f62`。

## 风险

- 尚未进行 Task 3 的 gallery 注册或 renderer 像素验证，按任务边界留给后续任务。
- 未进行实体设备验证；本任务仅验证 simulator 上的 unit/widget logic tests。

## Task 2 追加记录

### 改动

- `ContentView.swift` 将 `legacyBottomChrome` overlay 限定在 iOS 26 以下 fallback；iOS 26+ 仅由原生 `TabView(selection: $nativeTab)` 持有底部栏。
- `ChromeLayout.nativeTabBarClearance` 统一 native toast 的底部安全区预留，避免 native bar resize 覆盖 toast。
- `ReminderSetupView.swift` 保留 permission actions、deep links 与 accessibility identifiers；setup page 继续使用 `GeometryReader` 可用高度、top composition，并为 footer 使用透明背景。
- `ChromeLayoutTests.swift`、`SetupFlowTests.swift`、`SearchFlowTests.swift` 增加 native owner、toast clearance、setup footer/top composition、search close cleanup contracts。

### 测试

失败阶段（按 TDD）：

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HaiityTests/ChromeLayoutTests -only-testing:HaiityTests/SetupFlowTests -only-testing:HaiityTests/SearchFlowTests
```

`iPhone 16 Pro` destination 不存在；xcodebuild 列出的可用 target 为 `AC636497-5EC6-4AD4-BD83-E5E2458FA702`（`sAiity Verification`）。新增 assertions 在实现前按预期 RED：60 tests 中 4 failures。

GREEN：

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -only-testing:HaiityTests/ChromeLayoutTests -only-testing:HaiityTests/SetupFlowTests -only-testing:HaiityTests/SearchFlowTests
```

结果：`TEST SUCCEEDED`，60 tests，0 failures；使用已有 `sAiity Verification` simulator，未创建设备。

### 提交

提交信息：`align native navigation and setup chrome`。
