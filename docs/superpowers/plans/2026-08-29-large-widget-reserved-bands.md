# Large Widget Reserved Bands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing `Liste`, `Raster`, and `Fokus` large widgets visually stable by separating identity, graph or reminder timing, and actions into bounded regions.

**Architecture:** Reuse the existing SwiftUI views and `WidgetLogic.LargeGeometry`. Add only geometry constants needed to describe each reserved band. Keep links, AppIntents, palettes, data resolution, configuration, and WidgetKit families unchanged.

**Tech Stack:** SwiftUI, WidgetKit, AppIntents, XCTest, XcodeGen.

## Global Constraints

- Keep the existing `332 x 356pt` system-large reference canvas and current widget configuration.
- Keep each independent action at least `44 x 44pt` with its existing accessibility label.
- Keep reminders graph-free and show their existing metric/timing value.
- Keep the existing Dynamic Type cap at `DynamicTypeSize.accessibility1`.
- Do not add a new widget type, dependency, data model, manager, service, protocol, or layout framework.
- Preserve unrelated working-tree files and run physical-device checks only on the connected iPhone.

---

### Task 1: Add failing reserved-band contracts

**Files:**
- Modify: `HaiityTests/WidgetRenderingTests.swift` near the existing large-widget geometry tests

**Interfaces:**
- Consumes: `WidgetLogic.LargeGeometry`, `LargeWidgetItem`, `LargeGridItem`, and the existing source/render helpers.
- Produces: failing source and geometry contracts for the production tasks.

- [x] **Step 1: Write the failing test**

Add `testLargeLayoutsExposeNonOverlappingReservedBandsWithinContentBudget` to assert the nine band constants (`listIdentityBandHeight`, `listVisualBandHeight`, `listActionBandHeight`, and the corresponding `grid` and `focus` names), that the layout views consume them, and that reminder rendering remains graph-free. Add `testListeAndFokusKeepIdentityVisualAndActionRegionsSeparate` to require `identityBand`, `visualBand`, and `actionBand` in the shared item and the focus-specific band constants.

- [x] **Step 2: Run test to verify it fails**

Run on the existing verification simulator because these source-contract tests read repository paths at runtime:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' \
  -only-testing:HaiityTests/WidgetRenderingTests/testLargeLayoutsExposeNonOverlappingReservedBandsWithinContentBudget \
  -only-testing:HaiityTests/WidgetRenderingTests/testListeAndFokusKeepIdentityVisualAndActionRegionsSeparate \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
```

Expected: the tests fail because the new band constants and view markers are absent. A physical-device run is not valid for these tests because the phone cannot access the host source files.

- [x] **Step 3: Commit the test contract**

```bash
git add HaiityTests/WidgetRenderingTests.swift
git commit -m "test: define large widget reserved bands"
```

### Task 2: Implement Raster reserved bands

**Files:**
- Modify: `HaiityWidget/WidgetLogic.swift` in `LargeGeometry`
- Modify: `HaiityWidget/WidgetGridViews.swift` in `LargeGridWidgetView` and `LargeGridItem`

**Interfaces:**
- Consumes: existing `LargeGeometry.gridRowHeight`, `gridGraphMinimumHeight`, `LargeWidgetHeader`, `TrailingGrid`, reminder summary, and AppIntent actions.
- Produces: a four-tile renderer whose identity, visual, and action regions use shared constants and do not overlap.

- [x] **Step 1: Add the smallest geometry constants**

Define `gridIdentityBandHeight`, `gridVisualBandHeight`, and `gridActionBandHeight` in `WidgetLogic.LargeGeometry`; preserve `gridGraphMinimumHeight` as an alias to the visual height. Keep the sum equal to the existing `gridRowHeight` so the 2 x 2 grid and 332pt budget remain stable.

- [x] **Step 2: Use constants in each tile**

Use the identity height for the title/status row, the visual height for `TrailingGrid` or the centered reminder metric, and the action height for the footer. Keep reminder tiles free of `TrailingGrid`, keep actions as separate Buttons, and retain their 44pt frames and labels.

- [x] **Step 3: Run the focused renderer tests**

Run the two new contracts plus the existing Raster tests on the verification simulator. Expected: the geometry and source contracts pass, and the existing four-tile render checks remain green.

### Task 3: Implement Liste and Fokus reserved bands

**Files:**
- Modify: `HaiityWidget/RosterWidgetView.swift` in `LargeWidgetItem`, `LargeListWidgetView`, and `LargeFocusWidgetView`

**Interfaces:**
- Consumes: existing `LargeGeometry`, `LargeWidgetItem` summary/status logic, links, actions, and `TrailingGrid`.
- Produces: bounded list rows with a graph/timing visual slot and queue rows without graphs.

- [x] **Step 1: Define explicit local bands**

Build the existing item from `identityBand`, `visualBand`, and `actionBand` values. Identity remains one line; visual content uses the approved graph height or reminder metric; actions remain independent and retain 44pt targets. Do not introduce a new view type.

- [x] **Step 2: Preserve fixed list and focus budgets**

Keep four 72pt list rows, one 136pt featured focus item, and three 48pt queue rows. Ensure the visual slot is clipped to the item’s declared height and that a queue item with `graph: false` does not receive a graph or an oversized visual slot.

- [x] **Step 3: Run list/focus render checks**

Run the new source contracts and existing large list/focus rendering tests with long names, wide emoji, reminders, reset enabled, dark mode, vibrant mode, and accessibility Dynamic Type. Expected: no row overflow, no clipped primary graph, and no graph in focus queue rows.

### Task 4: Full verification and device check

**Files:**
- Modify: none unless a failing test identifies a concrete regression

- [x] **Step 1: Run the widget suites**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' \
  -only-testing:HaiityTests/WidgetRenderingTests \
  -only-testing:HaiityTests/WidgetLogicTests \
  -only-testing:HaiityTests/GitHubWidgetTests \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
```

Expected: all selected tests pass and all three large layouts render at the expected pixel dimensions.

- [x] **Step 2: Run the generic iOS build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'generic/platform=iOS' \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
```

Expected: `** TEST BUILD SUCCEEDED **` or a successful build completion without errors.

- [x] **Step 3: Verify the signed app on the connected iPhone**

Use device ID `2B7C93E3-7DF1-5690-A36F-B481CCF8479D` only. Confirm the built app launches and inspect the installed app version; do not create or use additional devices.

- [x] **Step 4: Review diff and commit implementation**

```bash
git diff --check
git status --short
git add HaiityWidget/WidgetLogic.swift HaiityWidget/WidgetGridViews.swift HaiityWidget/RosterWidgetView.swift
git commit -m "fix: stabilize large widget reserved bands"
```

Keep the existing unrelated reports, fixture, brainstorm directory, and older plans out of the commit.
