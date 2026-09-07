# Large Widget Featured Progress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (\`- [ ]\`) syntax for tracking.

**Goal:** Rebuild the registered large \`Liste\` and \`Raster\` widgets as native SwiftUI featured-progress surfaces with larger graphs, less text, and bounded action regions.

**Architecture:** Keep \`HaiityEntry\`, \`WidgetLogic\`, AppIntent configuration, palette resolution, links, and WidgetKit registration unchanged. Replace only the large renderer hierarchy in \`RosterWidgetView.swift\` and \`WidgetGridViews.swift\`, using fixed geometry constants in \`WidgetLogic.LargeGeometry\` and small view-local components for the featured item, compact rows, and graph-first tiles.

**Tech Stack:** Swift 5.9, SwiftUI, WidgetKit, AppIntents, XCTest, XcodeGen, SimSlim.

## Global Constraints

- Keep the fixed reference canvas at \`332 x 356pt\` and the existing \`6pt\` outer inset.
- Keep \`HaiityEntry.largeItems\`, both large widget intents, \`HaiityWidgetLink.habits\`, and all current AppIntent bindings unchanged.
- Keep every interactive action at least \`44 x 44pt\` with its existing accessibility label.
- Keep reminders graph-free and render their timing/status value in the reserved visual region.
- Keep \`.dynamicTypeSize(...DynamicTypeSize.accessibility1)\` on registered large renderers.
- Reuse \`HomeWidgetBackground\`, \`HomeWidgetInk\`, \`Theme\`, and semantic/system materials.
- Do not add a data model, persistence field, dependency, manager, service, protocol, factory, or layout framework.
- Preserve unrelated dirty and untracked files. Use only the existing SimSlim profile and one simulator; never use DeviceHub.
- Local implementation and test subagents use \`sub2api/gpt-5.6-luna\` at low reasoning and report in concise Chinese.

---

### Task 1: Add failing renderer contracts

**Files:**
- Modify: \`HaiityTests/WidgetRenderingTests.swift\` near the existing large-widget source and geometry contracts

**Interfaces:**
- Consumes: existing \`source\`, \`sourceSlice\`, \`render\`, \`foregroundPixelCount\`, and \`WidgetLogic.LargeGeometry\` helpers.
- Produces: source and pixel contracts for the approved featured-progress hierarchy.

- [ ] **Step 1: Add the new source contracts**

Add these methods beside the existing large-widget contracts:

\`\`\`swift
func testListeUsesFeaturedItemAndCompactStatusRows() throws {
    let source = try source("HaiityWidget/RosterWidgetView.swift")
    let list = try sourceSlice(source,
                               from: "struct LargeListWidgetView",
                               to: "struct LargeFocusWidgetView")

    XCTAssertTrue(list.contains("LargeFeaturedWidgetItem"))
    XCTAssertTrue(list.contains("LargeCompactWidgetRow"))
    XCTAssertTrue(list.contains("entry.largeItems.dropFirst().prefix(3)"))
    XCTAssertTrue(list.contains("featuredListHeight"))
    XCTAssertTrue(list.contains("compactListRowHeight"))
    XCTAssertTrue(list.contains("LargeWidgetHeader(entry: entry)"))

    let featured = try sourceSlice(source,
                                   from: "private struct LargeFeaturedWidgetItem",
                                   to: "private struct LargeCompactWidgetRow")
    XCTAssertTrue(featured.contains("TrailingGrid(habit: habit"))
    XCTAssertTrue(featured.contains("if habit.isReminder"))
    XCTAssertTrue(featured.contains("summary.metricText"))
    XCTAssertTrue(featured.contains("frame(width: 44, height: 44)"))
}

func testRasterUsesGraphFirstTilesWithoutNestedActionCapsules() throws {
    let source = try source("HaiityWidget/WidgetGridViews.swift")
    let body = try sourceSlice(source,
                               from: "struct LargeGridWidgetView",
                               to: "private struct LargeGridItem")
    let item = try sourceSlice(source,
                               from: "private struct LargeGridItem",
                               to: "/// Gemeinsame Rasterbausteine")

    XCTAssertTrue(body.contains("LazyVGrid"))
    XCTAssertTrue(body.contains("entry.largeItems.prefix(4)"))
    XCTAssertTrue(item.contains("gridIdentityBandHeight"))
    XCTAssertTrue(item.contains("gridVisualBandHeight"))
    XCTAssertTrue(item.contains("gridActionBandHeight"))
    XCTAssertTrue(item.contains("TrailingGrid(habit: habit"))
    XCTAssertTrue(item.contains("if habit.isReminder"))
    XCTAssertTrue(item.contains("Divider()"))
    XCTAssertTrue(item.contains("frame(width: 44, height: 44)"))
    XCTAssertFalse(item.contains("background(.thinMaterial, in: Capsule())"))
}

func testFeaturedAndRasterGeometryUsesTheFullLargeCanvas() {
    let source = try! source("HaiityWidget/WidgetLogic.swift")
    let g = WidgetLogic.LargeGeometry.self
    XCTAssertTrue(source.contains("featuredListHeaderHeight"))
    XCTAssertTrue(source.contains("featuredListHeight"))
    XCTAssertTrue(source.contains("featuredIdentityBandHeight"))
    XCTAssertTrue(source.contains("featuredVisualBandHeight"))
    XCTAssertTrue(source.contains("featuredActionBandHeight"))
    XCTAssertTrue(source.contains("compactListRowHeight"))
    XCTAssertTrue(source.contains("gridVisualBandHeight"))
    XCTAssertTrue(source.contains("gridActionBandHeight"))
    XCTAssertEqual(g.outerPadding, 6)
    XCTAssertEqual(g.actionHeight, 44)
}
\`\`\`

Update the old structural assertions that require the removed registered-list \`LargeWidgetItem\` or the nested capsule so they assert the new names and bands. Keep all \`LargeFocusWidgetView\` compatibility coverage.

- [ ] **Step 2: Run the contracts and verify the failure is meaningful**

\`\`\`bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' \
  -only-testing:HaiityTests/WidgetRenderingTests/testListeUsesFeaturedItemAndCompactStatusRows \
  -only-testing:HaiityTests/WidgetRenderingTests/testRasterUsesGraphFirstTilesWithoutNestedActionCapsules \
  -only-testing:HaiityTests/WidgetRenderingTests/testFeaturedAndRasterGeometryUsesTheFullLargeCanvas \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
\`\`\`

Expected: compilation succeeds and the new source contracts fail because the production views and geometry source do not yet contain the new components or constants.

- [ ] **Step 3: Commit the test contracts**

\`\`\`bash
git add HaiityTests/WidgetRenderingTests.swift
git commit -m "test: define featured progress widget contracts"
\`\`\`

---

### Task 2: Define measured geometry

**Files:**
- Modify: \`HaiityWidget/WidgetLogic.swift\` inside \`LargeGeometry\`
- Test: \`HaiityTests/WidgetRenderingTests.swift\`

**Interfaces:**
- Consumes: current \`contentHeight\`, \`gridRowHeight\`, and \`actionHeight\`.
- Produces: fixed constants used by both new renderer hierarchies.

- [ ] **Step 1: Add the exact band constants**

Keep the existing focus constants unchanged. Add or replace the registered-list and Raster constants with:

\`\`\`swift
static let featuredListHeaderHeight: CGFloat = 20
static let featuredListHeaderGap: CGFloat = 4
static let featuredListHeight: CGFloat = 168
static let featuredIdentityBandHeight: CGFloat = 22
static let featuredVisualBandHeight: CGFloat = 102
static let featuredActionBandHeight: CGFloat = 44
static let compactListRowHeight: CGFloat = 48
static let compactListRowGap: CGFloat = 4

static let gridRowHeight: CGFloat = 168
static let gridColumnGap: CGFloat = 8
static let gridRowGap: CGFloat = 8
static let gridIdentityBandHeight: CGFloat = 20
static let gridVisualBandHeight: CGFloat = 98
static let gridActionBandHeight: CGFloat = 44
static let gridItemSpacing: CGFloat = 1
static let gridItemPadding: CGFloat = 2
static let gridGraphMinimumHeight: CGFloat = gridVisualBandHeight

static let listContentHeight: CGFloat = featuredListHeaderHeight
    + featuredListHeaderGap + featuredListHeight
    + 3 * compactListRowHeight + 2 * compactListRowGap
static let gridContentHeight: CGFloat = 2 * gridRowHeight + gridRowGap
\`\`\`

The arithmetic fills the existing \`344pt\` content budget: \`20 + 4 + 168 + 3*48 + 2*4 = 344\`, and each Raster tile remains \`168pt\): \`20 + 98 + 44 + 2*1 + 2*2 = 168\`.

- [ ] **Step 2: Replace the source-only geometry contract with arithmetic after adding the constants**

Once the production constants exist, change
`testFeaturedAndRasterGeometryUsesTheFullLargeCanvas` to assert the exact arithmetic from this task:

```swift
XCTAssertEqual(g.featuredListHeaderHeight + g.featuredListHeaderGap
               + g.featuredListHeight + 3 * g.compactListRowHeight
               + 2 * g.compactListRowGap, g.contentHeight)
XCTAssertEqual(g.featuredIdentityBandHeight + g.featuredVisualBandHeight
               + g.featuredActionBandHeight, g.featuredListHeight)
XCTAssertEqual(g.gridIdentityBandHeight + g.gridVisualBandHeight
               + g.gridActionBandHeight + 2 * g.gridItemSpacing
               + 2 * g.gridItemPadding, g.gridRowHeight)
XCTAssertLessThanOrEqual(g.listContentHeight, g.contentHeight)
XCTAssertLessThanOrEqual(g.gridContentHeight, g.contentHeight)
```

- [ ] **Step 3: Run the geometry test**

\`\`\`bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' \
  -only-testing:HaiityTests/WidgetRenderingTests/testFeaturedAndRasterGeometryUsesTheFullLargeCanvas \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
\`\`\`

Expected: the arithmetic assertions pass; source assertions remain red until Tasks 3 and 4.

- [ ] **Step 4: Commit geometry**

\`\`\`bash
git add HaiityWidget/WidgetLogic.swift
git commit -m "feat: define featured widget geometry"
\`\`\`

---

### Task 3: Implement the featured Liste renderer

**Files:**
- Modify: \`HaiityWidget/RosterWidgetView.swift\` in the registered \`LargeListWidgetView\` path
- Test: \`HaiityTests/WidgetRenderingTests.swift\`

**Interfaces:**
- Consumes: \`HaiityEntry.largeItems\`, \`LargeWidgetHeader\`, \`WidgetLogic.summary\`, \`TrailingGrid\`, palettes, links, and existing AppIntents.
- Produces: one featured graph, up to three compact rows, and unchanged focus compatibility rendering.

- [ ] **Step 1: Add a mixed-content render assertion**

Use four items (checkbox, quantity, Yes/No, reminder) and require a 664 x 712 pixel output. Check a foreground featured graph region, all three compact rows, and a non-empty reminder timing region using the existing helpers:

\`\`\`swift
let image = try render(LargeListWidgetView(entry: entry)
    .frame(width: 332, height: 356), to: "large-featured-list-mixed.png")
XCTAssertEqual(image.cgImage.map { CGSize(width: $0.width, height: $0.height) },
               CGSize(width: 664, height: 712))
XCTAssertGreaterThan(foregroundPixelCount(image,
    in: CGRect(x: 12, y: 48, width: 640, height: 204)), 20)
for index in 0..<3 {
    let start = WidgetLogic.LargeGeometry.featuredListHeaderHeight
        + WidgetLogic.LargeGeometry.featuredListHeaderGap
        + WidgetLogic.LargeGeometry.featuredListHeight
    let stride = WidgetLogic.LargeGeometry.compactListRowHeight
        + WidgetLogic.LargeGeometry.compactListRowGap
    let y = 2 * Int(WidgetLogic.LargeGeometry.outerPadding
                    + start + CGFloat(index) * stride)
    XCTAssertGreaterThan(foregroundPixelCount(image,
        in: CGRect(x: 12, y: CGFloat(y), width: 640,
                   height: WidgetLogic.LargeGeometry.compactListRowHeight * 2)), 8)
}
\`\`\`

- [ ] **Step 2: Add \`LargeFeaturedWidgetItem\`**

Add a private view before \`LargeCompactWidgetRow\` with three explicit sections:

\`\`\`swift
VStack(alignment: .leading, spacing: 0) {
    identityBand
        .frame(height: WidgetLogic.LargeGeometry.featuredIdentityBandHeight)
    visualBand
        .frame(maxWidth: .infinity,
               height: WidgetLogic.LargeGeometry.featuredVisualBandHeight)
    actionBand
        .frame(height: WidgetLogic.LargeGeometry.featuredActionBandHeight)
}
.frame(maxWidth: .infinity,
       height: WidgetLogic.LargeGeometry.featuredListHeight,
       alignment: .topLeading)
.background(.thinMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
\`\`\`

The identity section contains emoji, one-line name, and status. The visual section uses \`TrailingGrid(habit: habit, maxWeeks: 18, today: today, radius: nil)\` for tracked habits. For reminders, use one \`Label(summary.metricText, systemImage: "bell.fill")\` and no \`TrailingGrid\`. The action section keeps the metric plus current-item Yes/No, quantity, checkbox/reminder, and conditional reset intents. Every button remains \`44 x 44\` with its current accessibility label. The content link remains \`HaiityWidgetLink.habits\`.

- [ ] **Step 3: Add \`LargeCompactWidgetRow\`**

Add a private view after the featured view. It is a single 48pt HStack with emoji/name, one status or metric, and the same current-item action buttons. It must not render a graph or an individual material card:

\`\`\`swift
HStack(spacing: WidgetLogic.LargeGeometry.itemSpacing) {
    Link(destination: HaiityWidgetLink.habits) {
        identityAndMetric
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    actionButtons
}
.frame(maxWidth: .infinity,
       height: WidgetLogic.LargeGeometry.compactListRowHeight)
.overlay(alignment: .bottom) { Divider() }
\`\`\`

Keep names and metrics to one line with \`.minimumScaleFactor(0.8)\`; reminder timing remains the one metric.

- [ ] **Step 4: Replace only the registered Liste body**

Keep empty-state handling, outer padding, Dynamic Type cap, and \`largeWidgetBackground\`. Use:

\`\`\`swift
VStack(alignment: .leading, spacing: 0) {
    LargeWidgetHeader(entry: entry)
        .frame(height: WidgetLogic.LargeGeometry.featuredListHeaderHeight)
    Color.clear.frame(height: WidgetLogic.LargeGeometry.featuredListHeaderGap)
    if let featured = entry.largeItems.first {
        LargeFeaturedWidgetItem(habit: featured, entry: entry)
    }
    VStack(alignment: .leading,
           spacing: WidgetLogic.LargeGeometry.compactListRowGap) {
        ForEach(entry.largeItems.dropFirst().prefix(3)) { habit in
            LargeCompactWidgetRow(habit: habit, entry: entry)
        }
    }
}
\`\`\`

Do not change \`LargeFocusWidgetView\` or \`LargeWidgetItem\`; they remain compatibility paths.

- [ ] **Step 5: Run Liste tests and commit**

\`\`\`bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' \
  -only-testing:HaiityTests/WidgetRenderingTests/testListeUsesFeaturedItemAndCompactStatusRows \
  -only-testing:HaiityTests/WidgetRenderingTests/testLargeRenderersRenderAllItemKindsAndReminderStatusWithoutGraph \
  -only-testing:HaiityTests/WidgetRenderingTests/testLargeRenderersRenderDarkAndVibrantStates \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
git add HaiityWidget/RosterWidgetView.swift HaiityTests/WidgetRenderingTests.swift
git commit -m "feat: redesign large list widget"
\`\`\`

Expected: all selected tests pass and the featured graph and compact rows remain inside the canvas in light, dark, vibrant, and large Dynamic Type rendering.

---

### Task 4: Implement graph-first Raster tiles

**Files:**
- Modify: \`HaiityWidget/WidgetGridViews.swift\` in \`LargeGridWidgetView\` and \`LargeGridItem\`
- Test: \`HaiityTests/WidgetRenderingTests.swift\`

**Interfaces:**
- Consumes: \`entry.largeItems\`, \`WidgetLogic.LargeGeometry\`, \`TrailingGrid\`, summary, palettes, links, and current AppIntents.
- Produces: a 2x2 graph-first Raster with one tile surface, larger graphs, a flat action rail, and a reminder timing region.

- [ ] **Step 1: Preserve the provider-facing grid**

Leave \`LargeGridWidgetView\` using \`LazyVGrid\`, \`entry.largeItems.prefix(4)\`, 8pt row/column gaps, outer padding, the Dynamic Type cap, and \`HomeWidgetBackground\`. Each tile keeps \`gridRowHeight\`.

- [ ] **Step 2: Replace the nested tile/action presentation**

Build \`LargeGridItem\` from identity, visual, divider, and action sections:

\`\`\`swift
VStack(alignment: .leading, spacing: WidgetLogic.LargeGeometry.gridItemSpacing) {
    identityBand
        .frame(maxWidth: .infinity,
               height: WidgetLogic.LargeGeometry.gridIdentityBandHeight,
               alignment: .leading)
    visualBand
        .frame(maxWidth: .infinity,
               height: WidgetLogic.LargeGeometry.gridVisualBandHeight)
    Divider()
    actionBand
        .frame(maxWidth: .infinity,
               height: WidgetLogic.LargeGeometry.gridActionBandHeight)
}
.padding(WidgetLogic.LargeGeometry.gridItemPadding)
.background(.thinMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
.overlay {
    RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(Theme.accentText(palette).opacity(0.16), lineWidth: 0.5)
}
\`\`\`

The identity line uses emoji/name and the status symbol. The visual line uses \`TrailingGrid(habit: habit, maxWeeks: 11, today: today, radius: nil)\` for tracked habits. Reminders use a centered \`Label(metricText, systemImage: "bell.fill")\` in the same 98pt region. The action line shows the metric and current-item actions, each at \`44 x 44\`, with the conditional reset button and current accessibility labels. Remove \`.background(.thinMaterial, in: Capsule())\` from the action rail.

- [ ] **Step 3: Run Raster tests and commit**

\`\`\`bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' \
  -only-testing:HaiityTests/WidgetRenderingTests/testRasterUsesGraphFirstTilesWithoutNestedActionCapsules \
  -only-testing:HaiityTests/WidgetRenderingTests/testTaskThreeRasterRendersMixedContentInExclusiveRegions \
  -only-testing:HaiityTests/WidgetRenderingTests/testRasterFourGraphRegionsUseFullHeightAndDoNotOverlap \
  -only-testing:HaiityTests/WidgetRenderingTests/testLargeRenderersRenderDarkAndVibrantStates \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
git add HaiityWidget/WidgetGridViews.swift HaiityTests/WidgetRenderingTests.swift
git commit -m "feat: redesign large raster widget"
\`\`\`

Expected: graph pixels occupy the visual bands, reminder timing appears without a graph, and no action or title crosses a tile boundary.

---

### Task 5: Full verification and visual smoke check

**Files:**
- Modify: none unless a focused test identifies a concrete regression

- [ ] **Step 1: Run all widget tests**

\`\`\`bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' \
  -only-testing:HaiityTests/WidgetRenderingTests \
  -only-testing:HaiityTests/WidgetLogicTests \
  -only-testing:HaiityTests/GitHubWidgetTests \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
\`\`\`

Expected: all selected tests pass, including empty state, sparse data, mixed item kinds, reminders, reset states, Dynamic Type, light/dark, vibrant, and full-canvas dimensions.

- [ ] **Step 2: Build app and widget targets without signing**

\`\`\`bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project Haiity.xcodeproj -scheme Haiity -configuration Debug \
  -destination 'id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' \
  -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO
\`\`\`

Expected: app and widget extension compile without SwiftUI type-checking or AppIntent errors.

- [ ] **Step 3: Verify only the configured SimSlim simulator**

Use \`/Users/enrico/.config/simslim/haiity.json\` and the existing simulator. Inspect the registered large \`Liste\` and \`Raster\` previews in light and dark appearance. Confirm the first item has the dominant graph, secondary rows stay readable, Raster graphs fill tiles, reminders show timing, and no text/icon is clipped. Do not boot another simulator or use DeviceHub.

- [ ] **Step 4: Review the final diff and preserve unrelated state**

\`\`\`bash
git status --short --branch
git diff HEAD~4 -- HaiityWidget/RosterWidgetView.swift HaiityWidget/WidgetGridViews.swift HaiityWidget/WidgetLogic.swift HaiityTests/WidgetRenderingTests.swift
\`\`\`

Expected: only planned widget source/test commits appear in the relevant diff; \`.runtime-stats-fixture.json\`, \`.superpowers/\`, and unrelated existing plan files remain untouched.

- [ ] **Step 5: Commit only a concrete final test correction**

If Task 5 exposes a concrete assertion mismatch, make the smallest correction, rerun the failing test, and commit it:

\`\`\`bash
git add HaiityTests/WidgetRenderingTests.swift HaiityWidget/RosterWidgetView.swift HaiityWidget/WidgetGridViews.swift HaiityWidget/WidgetLogic.swift
git commit -m "test: stabilize large widget rendering contracts"
\`\`\`

Do not create a release or upload to TestFlight as part of this plan unless the user explicitly requests it after verification.
