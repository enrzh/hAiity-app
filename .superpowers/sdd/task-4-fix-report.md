# Task 4 测试加固报告

## 修改范围

- 未修改产品代码。
- `WidgetRenderingTests` 现在断言三种 large renderer 空 entry 的真实 CGImage 像素尺寸 `664x712` 与可见像素，并单独验证 roster 的 `WidgetEmptyState` 路径。
- `GitHubWidgetTests` 将 old provider 限定到具体 provider 区段，动作 isolation 限定到 `LargeWidgetItem`/`LargeGridItem`，只读检查限定到 `resolveLargeItems` 函数体。
- resolver 新增 locked/unlocked 矩阵，验证有效显式槽保序、归档/删除/失效槽自动补位及对应结果。

## 验证

Focused command:

`xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -only-testing:HaiityTests/WidgetRenderingTests -only-testing:HaiityTests/WidgetLogicTests -only-testing:HaiityTests/GitHubWidgetTests`

首次运行发现新增尺寸断言误用了 point 尺寸，已改为检查 `cgImage` 像素尺寸；随后一次运行已编译并执行到测试，但 Xcode simulator diagnostics 长时间挂起，命令被中止，未将其记为通过。此前同一 focused target 的运行结果显示 WidgetLogic 67 项通过、GitHubWidget 30 项通过；WidgetRendering 的空 renderer 可见像素断言通过，仅旧尺寸写法失败。

完整 target 未在本次重新运行。已有记录中的 17 个 full-target failures 仅记为“现有非 widget failures observed”，不作为独立 baseline 证明，也不声称完整 target 通过。

## 限制

- `HaiityRosterProvider` 属于 `HaiityWidget` extension，HaiityTests target 无法直接实例化；没有新增跨 target 测试架构，因此保留精确 source contract。
- 本次 focused 命令中曾观察到 2 个既有 `ProGateTests` entitlement failures，不在 widget 测试改动范围内。
