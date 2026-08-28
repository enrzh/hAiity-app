# hAiity Large Widget Native Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing native Liste, Raster, and Fokus widgets compact, graph-led, and robust with long names, wide emoji, every item kind, and every configured action.

**Architecture:** Keep behavior in the existing WidgetKit views. Refine `LargeWidgetItem`, `LargeGridItem`, and `LargeGeometry`; reuse `TrailingGrid`, summaries, AppIntents, palette resolution, and deep links. Add observable rendering/source contracts before production changes.

**Tech Stack:** Swift 6, SwiftUI, WidgetKit, AppIntents, XCTest.

## Global Constraints

- Reference canvas is `332 x 356pt`; content height is `332pt` with `12pt` outer padding.
- Every action keeps a native `44 x 44pt` hit target and its localized accessibility label.
- Identity is optional emoji plus a one-line name; no fixed-width emoji frame.
- Status is a compact symbol, numeric value, or short reminder date/time; no sentence status.
- Habits keep meaningful graphs; reminders and Fokus queue rows have no graph.
- Preserve configuration, ordering, links, AppIntent behavior, reset preference, palettes, rendering modes, visibility, and persistence.
- Reuse existing files and types. Add no dependency or architecture layer.
- Preserve unrelated working-tree changes.

---

### Task 1: Shared compact identity, header, and geometry

**Files:**
- Modify: `HaiityTests/WidgetRenderingTests.swift`
- Modify: `HaiityWidget/WidgetLogic.swift`
- Modify: `HaiityWidget/RosterWidgetView.swift`

**Interfaces:**
- Consumes: `WidgetItemSummary`, `WidgetLogic.LargeGeometry`, `TrailingGrid`, existing action intents.
- Produces: compact `LargeWidgetHeader`; `LargeWidgetItem` with graph enabled/disabled presentation; stable Liste/Fokus geometry.

- [ ] **Step 1: Write failing tests.** Assert the header uses only `met/due` or `frei`, the shared item has no fixed emoji width, queue presentation can omit `TrailingGrid`, every action retains `actionHeight`, and Liste/Fokus totals remain within `contentHeight`.
- [ ] **Step 2: Verify RED.** Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/WidgetRenderingTests CODE_SIGNING_ALLOWED=NO
```

Expected: a new compact-header, no-fixed-emoji-frame, or queue-no-graph assertion fails against build 121.

- [ ] **Step 3: Implement the minimum shared change.** Shorten the existing header, remove fixed emoji width, give the name layout priority, keep status compact, and add one simple item parameter to suppress graphs. Do not extract a new type.
- [ ] **Step 4: Verify GREEN.** Re-run Step 2. Expected: `WidgetRenderingTests` passes.
- [ ] **Step 5: Commit only Task 1 files.**

```bash
git add HaiityWidget/WidgetLogic.swift HaiityWidget/RosterWidgetView.swift HaiityTests/WidgetRenderingTests.swift
git commit -m "refactor: compact large widget content"
```

### Task 2: Liste and Fokus hierarchy

**Files:**
- Modify: `HaiityTests/WidgetRenderingTests.swift`
- Modify: `HaiityWidget/RosterWidgetView.swift`

**Interfaces:**
- Consumes: Task 1's item presentation switch and geometry.
- Produces: four graph-led Liste rows and one featured graph plus three graph-free Fokus queue rows.

- [ ] **Step 1: Write failing tests.** Assert Liste renders graphs only for habits, Fokus's featured graph retains `focusFeaturedGraphMinimumHeight`, every queue row disables graph rendering, and a mixed entry with a long Chinese name and wide emoji renders at accessibility Dynamic Type.
- [ ] **Step 2: Verify RED.** Run Task 1 Step 2. Expected: queue suppression or long-name contract fails.
- [ ] **Step 3: Implement minimally.** Keep Liste's four stable rows and graph height. Make Fokus queue rows graph-free, fitting identity/state/actions in 48pt. Reminders use their existing compact metric. Preserve Links and independent Buttons.
- [ ] **Step 4: Verify GREEN and inspect `/tmp/large-*.png`.** Confirm full graphs, uncropped emoji/SF Symbols, and no overlap.
- [ ] **Step 5: Commit.**

```bash
git add HaiityWidget/RosterWidgetView.swift HaiityTests/WidgetRenderingTests.swift
git commit -m "fix: refine list and focus widgets"
```

### Task 3: Raster hierarchy and actions

**Files:**
- Modify: `HaiityTests/WidgetRenderingTests.swift`
- Modify: `HaiityWidget/WidgetGridViews.swift`

**Interfaces:**
- Consumes: four-item `LazyVGrid`, `LargeGeometry.grid*`, `TrailingGrid`, and existing intents.
- Produces: four tiles with exclusive identity, graph/reminder, and 44pt action regions.

- [ ] **Step 1: Write failing tests.** Assert `LargeGridItem` has no `.frame(width: 18`, preserves approved graph height and `44 x 44pt` actions, and renders long Chinese names, wide emoji, yes/no, count, checkbox, and reminder items without losing a graph.
- [ ] **Step 2: Verify RED.** Run Task 1 Step 2. Expected: fixed emoji-frame assertion fails.
- [ ] **Step 3: Implement minimally.** Remove the fixed emoji frame, prioritize the name, render compact state, preserve `gridGraphMinimumHeight`, and keep the bottom action strip stable for every action count. Reminder tiles use the graph-free middle region for timing/state.
- [ ] **Step 4: Verify GREEN and inspect `/tmp/large-grid-*.png`** in light, dark, vibrant, custom palette, and accessibility size.
- [ ] **Step 5: Commit.**

```bash
git add HaiityWidget/WidgetGridViews.swift HaiityTests/WidgetRenderingTests.swift
git commit -m "fix: refine large raster widget"
```

### Task 4: Regression, build, and release

**Files:**
- Modify only for verified regressions: `HaiityWidget/RosterWidgetView.swift`, `HaiityWidget/WidgetGridViews.swift`, `HaiityWidget/WidgetLogic.swift`, `HaiityTests/WidgetRenderingTests.swift`
- Release metadata: `project.yml` and generated `Haiity.xcodeproj/project.pbxproj` as required by the existing release workflow.

**Interfaces:**
- Consumes: completed Liste, Raster, and Fokus implementations.
- Produces: verified widget suite, generic build, next unused app/widget build, pushed `main`, and exact Xcode Cloud/TestFlight status.

- [ ] **Step 1: Run complete widget regression.**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/WidgetRenderingTests -only-testing:HaiityTests/WidgetLogicTests -only-testing:HaiityTests/GitHubWidgetTests
```

Expected: all selected tests pass on the single approved physical iPhone.

- [ ] **Step 2: Run generic build and repository checks.**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Haiity.xcodeproj -scheme Haiity -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
git diff --check
git status --short
```

- [ ] **Step 3: Inspect all generated images.** Cover long Chinese names, wide emoji, every item kind, reset on/off, light/dark/vibrant/custom palette, and accessibility Dynamic Type. Fix only observed regressions and rerun covering tests.
- [ ] **Step 4: Select the next unused build after live Xcode Cloud/TestFlight verification, then run the existing release verifier.** Keep app and widget build numbers identical.
- [ ] **Step 5: Commit attributable release metadata, push `main`, and trigger Xcode Cloud.**
- [ ] **Step 6: Verify through ego-browser only.** Confirm the exact build is accepted, processing, or available; assign `Internal` and `Preview`. Do not infer availability from a push.
- [ ] **Step 7: Run `tools/cleanup-dev-artifacts.sh` only after preserving release output.** Do not remove unrelated caches, simulator/device state, or user files.

## Self-review

The plan covers every approved layout and edge case, uses existing types only, requires RED before production changes, preserves all behavior, and separates local, cloud, and TestFlight claims. It contains no placeholders or speculative abstractions.
