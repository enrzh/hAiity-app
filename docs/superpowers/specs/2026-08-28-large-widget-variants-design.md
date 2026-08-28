# Large Widget Variants Design

## 目标

将当前拥挤且不可配置的 systemLarge `Übersicht` widget 改造成三个可分别添加和配置的 hAiity widget：

- `Liste`: 纵向显示最多 4 个项目。
- `Raster`: 2 x 3 网格显示最多 6 个项目。
- `Fokus`: 1 个重点项目加 3 个队列项目。

每个位置都允许用户明确选择一个 habit 或 reminder，也允许选择 `Automatisch`。明确选择保留用户指定的顺序；自动位置从当前可见项目中按现有推荐顺序补齐。三个 widget 共用同一套最小槽位解析逻辑，确保选择、去重、失效回退和 Pro 限制一致。

## 非目标

- 不重做小尺寸、中尺寸、锁屏 widget、GitHub widget 或 Live Activity 的视觉设计。
- 不改变 habit/reminder 的数据模型、完成记录、通知、日历同步或业务规则。
- 不允许在 widget 内编辑排序、创建项目或修改项目设置。
- 不新增 `Manager`、`Service`、`Factory`、`Strategy`、`Protocol`、`Adapter`、`Coordinator`、`Provider` 或 `Resolver` 类型。解析逻辑作为现有 `WidgetLogic` 的一个函数实现。
- 不保留第四种可添加的旧 systemLarge `Übersicht` widget。

## Widget 类型与布局

三种 widget 都注册为独立的 `AppIntentConfiguration`，仅支持 `.systemLarge`，并拥有稳定且唯一的 kind：

| 类型 | 配置槽位 | 视觉结构 |
| --- | --- | --- |
| `Liste` | `slot1` 至 `slot4` | 顶部今日摘要；最多四个纵向项目。每项为标题行、受控高度的 graph 或 reminder 状态区、独立操作行。 |
| `Raster` | `slot1` 至 `slot6` | 2 列 x 3 行。每项显示标题、streak/状态和紧凑 graph；reminder 不显示 graph。 |
| `Fokus` | `featured`、`queue1` 至 `queue3` | 顶部一个重点项目，使用更大的 graph 和完整状态操作；下方为三个紧凑队列项目。reminder 只能以无 graph 的状态行显示。 |

三种布局都遵循现有小 widget 的颜色、背景、玻璃模式、动态颜色和可访问性语言。每个项目的操作区域独立于整项 deeplink，避免点击操作时打开项目页面。项目标题和 graph/内容区域点击后打开对应项目。

### 项目内容

- Habit checkbox：显示 graph、streak、今日状态，并提供完成和可选 `Rückgängig`。
- Habit yes/no：显示 graph、streak、今日状态，并提供 `Ja`、`Nein` 和可选 `Rückgängig`。
- Habit count：显示 graph、streak、当前值/目标，并提供增加和可选 `Rückgängig`。
- Reminder：不显示 graph 或虚假的 streak；显示铃铛、日期/状态，并提供完成和可选 `Rückgängig`。

操作继续复用现有 App Intents：`CheckOffHabitIntent`、`AnswerYesHabitIntent`、`AnswerNoHabitIntent` 和 `ResetHabitIntent`。操作只接收当前槽位的 habit id，不能影响其他槽位。

## 配置与解析

三个配置 intent 分别提供所需的可选 `HabitEntity?` 参数：

- 非 `nil`：用户明确选择的 habit 或 reminder。
- `nil`：`Automatisch`，不是一个持久化的虚拟项目。

`HabitEntity` 继续作为两种项目的统一配置实体；不新增 `ReminderEntity`。现有的 graph-only 配置仍使用仅包含 tracked habit 的实体查询，不能用于这三个 overview widget。

解析函数接收当前 active 项目、按顺序排列的显式槽位选择和当前日期/权限上下文，按以下顺序产生最终项目数组：

1. 读取当前 active、未归档且对当前 Pro 状态可见的项目。
2. 按槽位顺序保留仍存在且可见的显式选择。
3. 重复显式选择只保留第一次出现的槽位，后续重复槽位视为空槽。
4. 按现有推荐顺序为空槽填充未被显式选择的项目。
5. 自动补位不得重复任何已显示项目。
6. 如果显式项目被删除、归档或因 Pro 过期不可见，将其视为空槽，并由自动项目补位。
7. 没有足够项目时隐藏空槽；不显示虚假占位项目。

解析必须统一经过 `HabitVisibility.visibleActiveHabits(...)` 或等价的现有可见性入口，不能使用绕过 Pro 限制的 active-only 重载。解析结果的顺序必须稳定，除非用户修改配置或项目本身的列表顺序发生变化。

## Pro、删除与归档

Pro 过期后，widget 与 app 使用相同的可见性规则：超过免费上限的项目不可作为显式选择，也不可被 `Automatisch` 补入。已有配置不应导致崩溃、显示受限项目或绕过限制；失效槽位按上述规则自动补位。

删除或归档项目后，下一次 widget timeline 读取时必须丢弃其旧选择。项目被恢复且重新可见后，不自动恢复已丢弃的槽位选择，除非系统仍能安全解析到该显式 id；实现必须以当前可见性结果为准，不显示陈旧缓存。

## 旧 Übersicht 迁移与 Gallery

当前 `HaiityRosterWidget` 的旧 systemLarge 体验迁移为 `Liste`：

- 旧 widget 的列表式视觉内容迁移到 `Liste` 的 renderer。
- 旧的静态配置迁移为 `Automatisch` 槽位，保证已有用户不会突然得到空 widget。
- 新版本只向 widget gallery 注册 `Liste`、`Raster`、`Fokus` 三种 systemLarge 类型。
- 不注册旧 `Übersicht` kind 的新实例，也不让它继续作为第四个可选 large widget 展示。
- 对系统已放置的旧 kind，提供兼容读取/占位路径，直到系统移除旧实例；兼容路径不得出现在 gallery。

迁移不删除用户的其他 widget，也不重置小尺寸、中尺寸或锁屏 widget 配置。

## 数据边界与 iCloud

槽位选择属于 widget 配置，由 WidgetKit 的 AppIntent 配置保存；不把槽位配置写入 habit 的 iCloud 数据模型。widget 通过现有 App Group shared data 读取 habit/reminder、完成状态、palette、Pro 可见性和 widget reset 设置。

App Group 数据是 widget 的只读快照边界：app 写入后通过现有 widget reload 机制刷新，widget 不直接写 iCloud。habit/reminder 的 iCloud 同步仍由 app 的现有同步流程负责；本设计不新增同步字段。若 shared data 暂时不可读，widget 显示统一的空/不可用状态，不覆盖或删除 iCloud 数据。

## 错误与空状态

- 没有可见项目：三种 widget 显示统一、简洁的空状态，并保持可点击进入 app 的入口（若现有 empty-state 组件支持）。
- 部分槽位无项目：隐藏空槽，布局不得留下明显的重叠、负间距或异常大面积空白。
- 配置中的项目已删除、归档或受 Pro 限制：静默失效并自动补位；无法补位时隐藏该槽位。
- App Group 数据损坏或读取失败：显示安全空状态，不执行写入修复，不崩溃。
- Action 执行时项目已失效：intent 安全 no-op 或返回现有错误反馈；不能修改另一个槽位的项目。
- deeplink 指向已删除项目：进入 app 的通用 habit 页面或现有安全 fallback，不显示错误项目。

各布局必须在最小 systemLarge 尺寸下保持标题、状态和操作的可读性；文字超长时截断或缩放，不允许压缩操作命中区域。

## 测试计划

### 解析与可见性

- Liste、Raster、Fokus 的显式选择按配置顺序输出。
- `nil` 槽位自动补齐当前推荐项目。
- 显式选择重复时第一次优先，自动补位不重复。
- 删除、归档和 Pro 过期项目会失效并正确补位。
- 槽位数量不足时只返回可用项目，全部为空时返回 empty state 数据。
- 解析路径不会绕过 Pro 可见性上限。

### 类型、视觉和交互

- checkbox、yes/no、count 和 reminder 分别显示正确内容。
- reminder 不显示 graph 或 streak。
- 每种项目的完成、Ja、Nein、增加和撤销操作只作用于对应项目。
- 标题和 graph/内容区域 deeplink 到对应 habit/reminder。
- reset 关闭时不显示撤销操作，开启时从初始渲染开始显示。
- large renderer 在真实 `.systemLarge` 几何尺寸下不重叠、不裁切、不产生额外阴影卡片；三个布局均覆盖浅色、深色和 widget rendering mode。

### 注册、配置与兼容

- 三个 kind 各只注册一次，并且仅注册 `.systemLarge`。
- 每个配置 intent 的槽位数量正确，`nil` 能表示 `Automatisch`。
- 旧 `Übersicht` 实例能读取为自动列表，gallery 不再出现第四个 large 类型。
- 删除或归档已选择项目后，刷新不会崩溃或显示旧项目。
- App Group 无数据时显示空状态，且不修改 iCloud 数据。

优先扩展现有 `WidgetLogicTests.swift`、`GitHubWidgetTests.swift` 和 `WidgetRenderingTests.swift`；除非现有测试结构无法覆盖，否则不新增测试基础设施。完成后至少运行 widget 相关单元测试、`git diff --check` 和 generic iOS `build-for-testing`。

## 发布与兼容风险

实现完成后先验证 widget target 和 app target 的构建、配置 intent 生成和三种 widget 的 gallery 注册，再提升 app/widget build number。提交前确认旧配置迁移和 Pro 可见性测试通过。

发布风险包括：AppIntent 配置在系统 gallery 中缓存、旧 StaticConfiguration 实例的迁移行为依赖 WidgetKit、App Group 快照晚于 iCloud 同步更新，以及不同 iOS 版本对 large widget 几何尺寸和玻璃渲染的差异。上线后应在至少一个 iOS 27 设备上验证添加、配置、刷新、点击 deeplink 和四类项目操作；未验证前不能把模拟器或 generic build 结果当作物理设备通过。

发布流程由实现阶段执行：递增 app/widget build，提交并 push `main`，触发 Xcode Cloud，确认 TestFlight 处理完成后将新 build 分配到 `Internal` 和 `Preview`。本 spec 本身不执行 push、构建或 TestFlight 上传。
