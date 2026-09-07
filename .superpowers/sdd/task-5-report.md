# Task 5 报告

STATUS: 完成测试契约迁移；完整 WidgetRenderingTests 与 GitHubWidgetTests 均通过。

COMMITS: `78e5122 test: reconcile widget rendering contracts`（仅 `HaiityTests/WidgetRenderingTests.swift` 与 `HaiityTests/GitHubWidgetTests.swift`）。

TESTS:
- RED 命令：
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -only-testing:HaiityTests/WidgetRenderingTests -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO`
- RED 结果：测试进程在模拟器服务初始化后无汇总输出，运行数分钟无进展；确认只有该 xcodebuild 进程后中止，日志为 `BUILD INTERRUPTED`。先前日志已证明相关旧契约失败。
- WidgetRenderingTests 完整命令：同上 `-only-testing:HaiityTests/WidgetRenderingTests` 命令。
- WidgetRenderingTests 结果：`** TEST SUCCEEDED **`，40 tests，0 failures，退出码 0。
- GitHubWidgetTests 完整命令：
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -only-testing:HaiityTests/GitHubWidgetTests -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO`
- GitHubWidgetTests 结果：`** TEST SUCCEEDED **`，33 tests，0 failures，退出码 0。
- 两次最终运行均只使用现有 SimSlim 模拟器；日志中的 XPC/widget 服务告警未影响结果。

CONCERNS:
- 仅更新测试契约与 dynamic-type 像素坐标；生产 Swift、project、plan、其他 report 和无关 dirty/untracked 文件未修改。
- 未运行完整全项目测试套件。

## Review 修复

STATUS: 已修复两个 Important finding。

COMMITS: `0d3bb50 test: strengthen widget contract coverage`（仅两个测试文件）。

TESTS:
- 覆盖测试命令：
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -only-testing:HaiityTests/GitHubWidgetTests/testLargeRenderersUseGraphsOnlyForTrackedHabitsAndLinkAllContent -only-testing:HaiityTests/WidgetRenderingTests/testListeDynamicTypeRegionsKeepEachRowBoundedAndReadable -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO`
- 覆盖测试结果：2 tests，0 failures，退出码 0。GitHub 契约现在分别切片 Roster featured visual 与 Raster grid visual 的 reminder 分支，断言包含 timing `Label` 且不含 `TrailingGrid`；Dynamic Type 契约分别检查 featured identity/visual/actions 与 3 个 compact row identity/actions，保留 `>2`、`>20`、`>8` 阈值和 gap `<=40`。
- WidgetRenderingTests 完整命令：
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -only-testing:HaiityTests/WidgetRenderingTests -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO`
- WidgetRenderingTests 结果：40 tests，0 failures，退出码 0。
- GitHubWidgetTests 完整命令：
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -only-testing:HaiityTests/GitHubWidgetTests -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO`
- GitHubWidgetTests 结果：33 tests，0 failures，退出码 0。

CONCERNS:
- 模拟器日志仍有 XPC/widget 服务告警，但未影响上述结果。
- 报告文件未纳入代码提交；无关 dirty/untracked 文件保持原样。
