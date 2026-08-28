# Task 4 测试加固报告

## 修改范围

- 未修改产品代码。
- `WidgetRenderingTests` 现在断言三种 large renderer 空 entry 的真实 CGImage 像素尺寸 `664x712` 与可见像素，并单独验证 roster 的 `WidgetEmptyState` 路径。
- `GitHubWidgetTests` 将 old provider 限定到具体 provider 区段，动作 isolation 限定到 `LargeWidgetItem`/`LargeGridItem`，只读检查限定到 `resolveLargeItems` 函数体。
- resolver 新增 locked/unlocked 矩阵，验证有效显式槽保序、归档/删除/失效槽自动补位及对应结果；按实际算法确认 unlocked 为 `[h2,h1,h0,h3]`、locked 为 `[h1,h2,h0]`。
- slice helper 对 provider/action/read-only 的 start/end marker 缺失均显式 `XCTFail` 并抛错，不再静默扩大扫描范围。

## 验证

Focused command:

`xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -only-testing:HaiityTests/WidgetRenderingTests -only-testing:HaiityTests/WidgetLogicTests -only-testing:HaiityTests/GitHubWidgetTests`

先将 locked expected 改为 `[h1,h2,h0]`，单测试按 TDD 先观察到 unlocked expected 失败，随后按算法实际结果改为 `[h2,h1,h0,h3]`，resolver/action 单测试均通过。`build-for-testing` 输出 `** TEST BUILD SUCCEEDED **`；之后用 `-parallel-testing-enabled NO -maximum-parallel-testing-workers 1` 重跑三组 focused widget tests：GitHubWidget 30/30、WidgetLogic 68/68、WidgetRendering 7/7，共 105/105 通过。

完整 target 未在本次重新运行。已有记录中的 17 个 full-target failures 仅记为“现有非 widget failures observed”，不作为独立 baseline 证明，也不声称完整 target 通过。此前普通并行 invocation 曾发生 simulator diagnostics 挂起，本次仅按要求进行一次单 worker/禁并行重跑并成功完成。

## 限制

- `HaiityRosterProvider` 属于 `HaiityWidget` extension，HaiityTests target 无法直接实例化；没有新增跨 target 测试架构，因此保留精确 source contract。
- 本次 focused 命令中曾观察到 2 个既有 `ProGateTests` entitlement failures，不在 widget 测试改动范围内。
