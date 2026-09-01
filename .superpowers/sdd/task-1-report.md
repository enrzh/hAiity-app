# Task 1 Report

## Scope

Implemented the contribution-first shared large-item path and Liste layout from
`.superpowers/sdd/task-1-brief.md`.

## Changes

- Added the approved large-widget geometry contracts and retained the existing `gridRowSpacing` compatibility alias.
- Added the requested geometry and Liste source-contract tests first; the first run failed on missing geometry members, confirming the red phase.
- Removed repeated large-item card fill and clipping. Items now use title/status and graph bands with actions outside the habit link.
- Liste uses the shared 38pt graph band, four 72pt rows, 4pt gaps, outer padding, and final 4pt breathing room.
- Reminder items show only the bell in the graph band and do not render a graph.
- Actions remain visually weak and retain 44pt minimum hit targets. Reset uses `entry.widgetResetEnabled` alone.
- Raster/Fokus source files, resolver, and configuration were not modified.

## Verification

The requested `iPhone 16 Pro` simulator was unavailable. The existing booted simulator `sAiity Verification` (iOS 26.5, `AC636497-5EC6-4AD4-BD83-E5E2458FA702`) was used instead.

Focused tests passed: 2 executed, 0 failures.

Full `WidgetRenderingTests` passed: 14 executed, 0 failures. This included rendering checks at 664 x 712 pixels, all large item kinds, reminder handling, dark/vibrant states, and empty/sparse layouts.

`git diff --check` passed. No physical-device validation was performed. Visual risk remains that the shared unframed item path changes Fokus presentation as intended by the brief, but pixel tests cannot fully assess hierarchy or visual balance; manual simulator inspection is still recommended.

## Commit

`05eb929` (`feat: make large widget items contribution first`). The report is intentionally excluded from the commit.

## Task 1 本次实施

### 变更

- 在 `Haiity/Theme.swift` 增加 `settingsRowSurface()`，复用 `SettingsRowSurface`，并让 `SettingsChromeModifier` 使用 `AppearanceBackground(preferences: appearancePreferences)`。
- `Haiity/Views/MoreView.swift` 的主页、`Verhalten & Teilen` 和相关设置 section 统一使用 `.settingsRowSurface()`；保留 `AppearancePreferences` 字段和图片模式条件逻辑。
- `Haiity/Views/MaterialPreviewPicker.swift` 使用 `.settingsRowSurface()`，保留现有异步 `AppearanceCachedImage` 预览和选中态。
- `HaiityTests/ThemeAndPaletteTests.swift` 先加入 source-contract 测试，覆盖共享背景、row modifier、More 子页和 material picker。

### TDD 与验证

- brief 指定的 `iPhone 16 Pro` destination 不存在：`xcodebuild: error: Unable to find a device matching the provided destination specifier`。未继续等待，改用现有 `sAiity Verification`，ID `AC636497-5EC6-4AD4-BD83-E5E2458FA702`，iOS 26.5。
- RED 阶段源码契约确认缺少 `settingsRowSurface()`；首次 simulator test discovery 对 `ThemeAndPaletteTests` 执行 `0 tests`，因此不能将该次结果视为测试通过。
- GREEN focused build/test 编译成功；`ThemeAndPaletteTests` 仍因 discovery 报告 `Executed 0 tests`，`SetupFlowTests` 执行 14 个测试，其中既有 `testSetupPagesUseTopCompositionAndTransparentFooter` 失败 1 个，与本 Task 无关。
- `git diff --check` 通过。未修改 setup 测试或其他 dirty 文件。

### Commit

本 Task commit：`179defda09b9ca3f8e9a6a17fe99bcef104991bf`（`polish shared appearance surfaces`）。报告按要求保留为未提交文件。

## Task 1 接手修复验证（2026-08-30）

- 检查了 HEAD `179defd` 的已有草稿：`Haiity/Theme.swift`、`HaiityTests/ThemeAndPaletteTests.swift`；保留并在其上补充测试，未修改其他 dirty 文件。
- 新增 source-contract 测试现在按实现区间验证 `AppearanceBackground(preferences: appearancePreferences)`、四种 material、image/gradient readable overlay、shape-owned `clipShape`/border、无父级 shadow，并分别验证 More 的 `mainSettings`、`appearanceSettings`、`habitBehaviorSettings`、`timeZoneSettings`、setup-related section 和四个 `screen` 分支；不再仅对整文件做 `contains`。
- 真实 XCTest identifier：`HaiityTests.AppearanceSettingTests/testTaskOneSharedSettingsSurfaceContractIsScopedToItsImplementations`，执行 `1 test, 0 failures`。完整 `HaiityTests.AppearanceSettingTests` 执行 `59 tests`，新增契约通过，另有既有 `testSettingsChromeLeavesNavigationBarMaterialToTheSystem` 和 `testStatsPageUsesClearSectionsAndIndividualCardSurfaces` 失败，均非本次新增测试。
- 命令：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -only-testing:HaiityTests/AppearanceSettingTests`；输出：`Executed 59 tests, with 2 failures`。
- `SetupFlowTests` 真实执行 `14 tests`；单个 `HaiityTests.SetupFlowTests/testSetupPagesUseTopCompositionAndTransparentFooter` 失败于 `HaiityTests/SetupFlowTests.swift:104`，原因是 `ReminderSetupView.swift` 含 `alignment: .center`。该失败与 Task 1 无关，属于 Task 2 setup 文件；未修改 `ReminderSetupView.swift` 或 `SetupFlowTests.swift`。
- 命令：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -only-testing:HaiityTests/SetupFlowTests/testSetupPagesUseTopCompositionAndTransparentFooter`；输出：`Executed 1 test, with 1 failure`。
- `git diff --check` 通过；未改 iCloud/App Group payload，未新增 manager/service/factory/provider/coordinator。

## Task 1 复审修复（2026-08-30）

- 修复 `HaiityTests/ThemeAndPaletteTests.swift:800-813` 的 false-positive：setup Section 现在从 `Section { Button { showReminderSetup = true }` 截到紧随其后的 About Section 明确边界，只断言该 Section 自身的 `.settingsRowSurface()`。
- 修正 `testSettingsChromeLeavesNavigationBarMaterialToTheSystem` 的精确期望为 `AppearanceBackground(preferences: appearancePreferences)`。此前失败是 Task 1 将 `SettingsChromeModifier` 参数改名后的回归，不是 baseline；未修改 Task 2 setup 生产文件。
- RED：命令 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -only-testing:HaiityTests/AppearanceSettingTests/testTaskOneSharedSettingsSurfaceContractIsScopedToItsImplementations -only-testing:HaiityTests/AppearanceSettingTests/testSettingsChromeLeavesNavigationBarMaterialToTheSystem`；结果 `Executed 2 tests, with 1 failure`（旧变量名期望）。
- GREEN：同一命令修复后结果 `Executed 2 tests, with 0 failures`，`** TEST SUCCEEDED **`；两个真实 XCTest identifier 均执行，非 0 tests。
- `git diff --check` 通过。

## Task 1 最终复审修复（2026-08-30）

- 修正 `HaiityTests/ThemeAndPaletteTests.swift:800-816`：`setupEnd` 现在只定位紧随 setup Section 后的 About Section 起点 `Section { pageRow(MoreRoute.about, ...)`，不再把 `.settingsRowSurface()` 放入 marker；setup modifier 在截取区间内独立断言。
- 未修改生产文件、Task 2 setup 文件或其他 dirty 文件。
- 命令：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -only-testing:HaiityTests/AppearanceSettingTests/testTaskOneSharedSettingsSurfaceContractIsScopedToItsImplementations`。
- 结果：真实 XCTest 执行 `1 test, with 0 failures`，`** TEST SUCCEEDED **`，非 0 tests。
