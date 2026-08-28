# Task 4 最终视觉回归报告

## 结论

已修复 accessibilityExtraExtraExtraLarge 下 systemLarge widget 的 emoji、status、标题和 actions 重叠问题。三个 large 根 view 统一使用 SwiftUI 原生 dynamic type 上限：

```swift
.dynamicTypeSize(...DynamicTypeSize.accessibility1)
```

选择 `.accessibility1` 是因为它比 `.xxxLarge` 更宽，仍允许较大的可访问性字号，同时实测能够在现有固定 systemLarge 几何预算中保持内容分区，不需要硬编码字体缩放或新增类型。

## TDD 证据

先在 `WidgetRenderingTests` 新增可观察约束，要求 list/focus/grid 三个 renderer 都声明上述上限，并用 `.accessibilityExtraExtraExtraLarge` 环境渲染三个非空 large layout。生产代码未修改时该 source contract 必然失败；随后仅在三个根 view 加上 modifier，测试转绿。

## 视觉检查

重新生成并检查：

- `/tmp/large-task-4-ax-xxxl-list.png`
- `/tmp/large-task-4-ax-xxxl-grid.png`
- `/tmp/large-task-4-ax-xxxl-focus.png`

三张图均为 664 x 712 像素。AX XXXL 输入下，emoji/标题/status、网格或指标、以及 action buttons 均保持在各自布局区域内，未复现原始截图中的重叠。

## 测试

使用现有 `sAiity Verification` iOS 26.5 simulator 运行：

```text
xcodebuild test -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' \
  -only-testing:HaiityTests/WidgetRenderingTests \
  -only-testing:HaiityTests/WidgetLogicTests \
  -only-testing:HaiityTests/GitHubWidgetTests
```

结果：`130 tests, 0 failures`；WidgetRenderingTests 29 tests，WidgetLogicTests 68 tests，三套指定 suite 总计 130 tests，测试成功。

## 改动范围

仅修改：

- `HaiityWidget/RosterWidgetView.swift`
- `HaiityWidget/WidgetGridViews.swift`
- `HaiityTests/WidgetRenderingTests.swift`
- 本报告文件

## Final Review 修复

共享 `LargeWidgetItem` 的 reminder 标题行现在只显示 bell；当 `graph == true` 时，`summary.metricText` 单独显示在 middle region，覆盖 Liste 与 Fokus featured。Fokus queue 继续使用 `graph == false` 的单行路径，并移除无效的 `graphHeight: 12`。

新增回归覆盖：AX XXXL 下混合长中文/宽 emoji 的 list、grid、focus 分区与 action 行；grid reminder 标题/middle timing/44pt actions；以及真实 `PaletteBook(customs:)` 在 light、dark、fullColor、vibrant 下的非空和 distinct graph signatures。旧的 `partialGraphs` 自我计数死代码已删除。

最终三套 suite：`132 tests, 0 failures`，其中 WidgetRenderingTests 31、WidgetLogicTests 68，GitHubWidgetTests 包含在总计中。

## Final Test-Only Fix

custom palette 回归现在显式分别渲染并断言 `light`、`dark`、`.fullColor`、`vibrant` 四种状态；`.fullColor` 输出单独命名为 `large-task-4-custom-full-color.png`，不再依赖默认 rendering mode。

最终 test-only 修复验证：WidgetRenderingTests `31 tests, 0 failures`；本次无生产代码改动。
