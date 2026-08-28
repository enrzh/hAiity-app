# Task 3 Report

日期：2026-08-28
基线：`2b91da0`

## 实现

- `HaiityWidget/HaiityWidget.swift`
  - 注册 `HaiityLargeListWidget`、`HaiityLargeGridWidget`、`HaiityLargeFocusWidget`。
  - 三者均使用对应 `AppIntentConfiguration`、`String(localized:)` 与 `.supportedFamilies([.systemLarge])`。
  - 从 gallery 移除旧 `HaiityRosterWidget`，保留 `HaiityRosterProvider` 作为旧 kind 的兼容读取路径。
- `HaiityWidget/RosterWidgetView.swift`
  - 增加 Liste 4 槽与 Fokus 1 大槽加 3 队列 renderer。
  - reminder 只显示 bell/status，不绘制 graph/streak。
  - checkbox/count/yes-no/reminder 使用各自 action；reset 只受配置开关控制，从初始状态即可用。
  - 标题和非操作内容使用精确 habit deeplink，action button 位于 Link 外。
- `HaiityWidget/WidgetGridViews.swift`
  - 增加 Raster 2x3、最多 6 槽 renderer，保持相同 action/deeplink 约束。
- `HaiityTests/GitHubWidgetTests.swift`、`HaiityTests/WidgetRenderingTests.swift`
  - 增加注册、action/reminder/deeplink 与真实 large geometry 像素测试。
  - 更新旧 Overview gallery 测试以匹配迁移后的契约。

## 验证

命令：

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=sAiity Verification' \
  -only-testing:HaiityTests/WidgetRenderingTests \
  -only-testing:HaiityTests/GitHubWidgetTests
```

结果：`TEST SUCCEEDED`，31 tests，0 failures。

输出：

- `/tmp/large-list.png`：664x712，43,337 bytes
- `/tmp/large-grid.png`：664x712，38,648 bytes
- `/tmp/large-focus.png`：664x712，42,402 bytes

三张图均对应 scale 2 的 332x356，均非空；视觉检查未发现内容溢出或槽位重叠。

## Commit

`feat: add list grid and focus large widgets`

## 视觉风险

- 当前渲染测试直接渲染 content view，未注入 WidgetKit 的 container background，因此 PNG 外围显示为黑色；真实 Widget 配置仍由系统容器背景绘制。
- simulator 输出中 Link 文本使用系统 tint，最终颜色可能随 WidgetKit rendering mode 改变；这属于系统显示行为，不影响布局、操作按钮或 deeplink 分区。
