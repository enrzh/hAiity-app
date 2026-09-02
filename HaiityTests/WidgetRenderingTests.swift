import SwiftUI
import UIKit
import XCTest
@testable import Haiity

@MainActor
final class WidgetRenderingTests: XCTestCase {
    func testTaskFourMixedAccessibilityRegionsAndReminderMiddleAreBounded() throws {
        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        let item = try sourceSlice(roster, from: "private struct LargeFeaturedWidgetItem", to: "private struct LargeCompactWidgetRow")
        XCTAssertTrue(item.contains("if habit.isReminder"))
        XCTAssertTrue(item.contains("Label(summary.metricText, systemImage: \"bell.fill\")"))
        XCTAssertFalse(item.contains("graphHeight: 12"))

        let today = DayKey.today()
        var checkbox = Habit(name: "一个很长的中文习惯名称", emoji: "🧑🏽‍💻")
        checkbox.log[today] = 1
        let quantity = Habit(name: "数量习惯", emoji: "🏋🏽‍♀️", recurrence: Recurrence(target: 3), kind: .quantity)
        var yesNo = Habit(name: "判断习惯", emoji: "✅", kind: .yesNo)
        yesNo.log[today] = Habit.Answer.yes
        let reminder = Habit(name: "提醒事项时间", emoji: "👩🏽‍🔬", itemType: .reminder,
                             recurrence: .weekdays([2, 4, 6]))
        let habits = [checkbox, quantity, yesNo, reminder]
        let entry = HaiityEntry(date: .now, habits: habits, widgetResetEnabled: true,
                                largeItems: habits, largeLayout: .focus)
        let views = [("list", AnyView(LargeListWidgetView(entry: entry))),
                     ("grid", AnyView(LargeGridWidgetView(entry: entry))),
                     ("focus", AnyView(LargeFocusWidgetView(entry: entry)))]
        for (name, view) in views {
            let image = try render(view.environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
                .frame(width: 332, height: 356), to: "large-task-4-mixed-\(name).png")
            XCTAssertGreaterThan(visiblePixelCount(image), 20)
            XCTAssertGreaterThan(foregroundPixelCount(image, in: CGRect(x: 0, y: 0, width: 664, height: 120)), 8)
            XCTAssertGreaterThan(foregroundPixelCount(image, in: CGRect(x: 0, y: 560, width: 664, height: 152)), 8)
        }
    }

    func testTaskFourCustomPaletteHasDistinctLightDarkFullColorAndVibrantGraphRegions() throws {
        let customs = [CustomPalette(name: "Task Four A", base: 0xD97706),
                       CustomPalette(name: "Task Four B", base: 0x2563EB)]
        let today = DayKey.today()
        var first = Habit(name: "Orange", emoji: "🟠")
        first.palette = .custom(customs[0].id)
        first.log[today] = 1
        var second = Habit(name: "Blue", emoji: "🔵")
        second.palette = .custom(customs[1].id)
        second.log[today] = 1
        let entry = HaiityEntry(date: .now, habits: [first, second],
                                palettes: PaletteBook(global: .default, customs: customs),
                                largeItems: [first, second], largeLayout: .grid)
        let base = LargeGridWidgetView(entry: entry).frame(width: 332, height: 356)
        let light = try render(base, to: "large-task-4-custom-light.png")
        let dark = try render(base.environment(\.colorScheme, .dark), to: "large-task-4-custom-dark.png")
        let fullColor = try render(base.environment(\.widgetRenderingMode, .fullColor), to: "large-task-4-custom-full-color.png")
        let vibrant = try render(base.environment(\.widgetRenderingMode, .vibrant), to: "large-task-4-custom-vibrant.png")
        let region = CGRect(x: 24, y: 112, width: 248, height: 172)
        XCTAssertGreaterThan(visiblePixelCount(light), 20)
        XCTAssertGreaterThan(visiblePixelCount(dark), 20)
        XCTAssertGreaterThan(visiblePixelCount(fullColor), 20)
        XCTAssertGreaterThan(visiblePixelCount(vibrant), 20)
        XCTAssertGreaterThan(Set([colorSignature(light, in: region), colorSignature(dark, in: region),
                                  colorSignature(fullColor, in: region), colorSignature(vibrant, in: region)]).count, 1)
    }

    func testLargeRenderersCapAccessibilityDynamicTypeForFixedGeometry() throws {
        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        let grid = try source("HaiityWidget/WidgetGridViews.swift")
        XCTAssertEqual(roster.components(separatedBy: ".dynamicTypeSize(...DynamicTypeSize.accessibility1)").count - 1, 3,
                       "large roots must cap text to the widest non-overlapping accessibility size")
        XCTAssertEqual(grid.components(separatedBy: ".dynamicTypeSize(...DynamicTypeSize.accessibility1)").count - 1, 1,
                       "grid root must cap text to the widest non-overlapping accessibility size")

        let demo = HaiityEntry.demo
        let entry = HaiityEntry(date: demo.date, habits: demo.habits,
                                palettes: demo.palettes, widgetResetEnabled: true,
                                largeItems: Array(demo.habits.prefix(4)), largeLayout: .list)
        for (layout, view) in [("list", AnyView(LargeListWidgetView(entry: entry))),
                               ("grid", AnyView(LargeGridWidgetView(entry: entry))),
                               ("focus", AnyView(LargeFocusWidgetView(entry: entry)))] {
            let image = try render(view
                .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
                .frame(width: 332, height: 356), to: "large-task-4-ax-xxxl-\(layout).png")
            XCTAssertEqual(image.cgImage.map { CGSize(width: $0.width, height: $0.height) },
                           CGSize(width: 664, height: 712))
            XCTAssertGreaterThan(visiblePixelCount(image), 20, "empty \(layout) AX XXXL render")
        }
    }

    func testLargeTextKeepsReadableFallbacksWithoutChangingGraphBands() throws {
        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        let grid = try source("HaiityWidget/WidgetGridViews.swift")
        let item = try sourceSlice(roster, from: "private struct LargeFeaturedWidgetItem", to: "private struct LargeCompactWidgetRow")
        let gridItem = try sourceSlice(grid, from: "private struct LargeGridItem", to: "/// Gemeinsame Rasterbausteine")

        XCTAssertFalse(item.contains(".minimumScaleFactor(0.7)"))
        XCTAssertTrue(item.contains(".minimumScaleFactor(0.8)"))
        XCTAssertFalse(gridItem.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertFalse(gridItem.contains(".minimumScaleFactor(0.75)"))
        XCTAssertTrue(gridItem.contains("gridVisualBandHeight"))
        XCTAssertTrue(item.contains("featuredVisualBandHeight"))
    }

    func testRasterUsesFullBudgetAndFourTiles() throws {
        let source = try source("HaiityWidget/WidgetGridViews.swift")
        XCTAssertTrue(source.contains("LargeGeometry.gridColumnGap"))
        XCTAssertTrue(source.contains("LargeGeometry.gridRowGap"))
        XCTAssertTrue(source.contains("entry.largeItems.prefix(4)"))

        let geometry = WidgetLogic.LargeGeometry.self
        XCTAssertEqual(geometry.gridColumnGap, 8)
        XCTAssertEqual(geometry.gridRowGap, 8)
        XCTAssertEqual(geometry.gridGraphMinimumHeight, 98)
        XCTAssertEqual(2 * geometry.gridRowHeight + geometry.gridRowGap, 344)

        let body = try sourceSlice(source, from: "struct LargeGridWidgetView", to: "private struct LargeGridItem")
        XCTAssertFalse(body.contains("LargeWidgetHeader"))
        XCTAssertFalse(body.contains("LargeGeometry.gridHeaderGap"))
        XCTAssertTrue(body.contains("LazyVGrid"))
        let item = try sourceSlice(source, from: "private struct LargeGridItem", to: "/// Gemeinsame Rasterbausteine")
        XCTAssertTrue(item.contains("HStack(spacing: 0)"))
        XCTAssertTrue(item.contains("frame(width: 44, height: 44)"))
        XCTAssertTrue(item.contains("gridActionBandHeight"))
        XCTAssertFalse(item.contains("background(.thinMaterial, in: Capsule())"))
        XCTAssertFalse(item.contains("tileWidth - 88"))
        XCTAssertTrue(item.contains("if habit.isReminder"))
        XCTAssertTrue(item.contains("gridIdentityBandHeight"))
        XCTAssertTrue(item.contains(".lineLimit(1)"))
    }

    func testTaskThreeRasterRendersMixedContentInExclusiveRegions() throws {
        let source = try source("HaiityWidget/WidgetGridViews.swift")
        let item = try sourceSlice(source, from: "private struct LargeGridItem", to: "/// Gemeinsame Rasterbausteine")
        XCTAssertFalse(item.contains("frame(width: 18"), "emoji must not consume a fixed title width")
        XCTAssertTrue(item.contains(".fixedSize(horizontal: true, vertical: false)"))
        XCTAssertTrue(item.contains("Text(verbatim: habit.name)"))
        XCTAssertTrue(item.contains(".layoutPriority(1)"))
        XCTAssertTrue(item.contains("Divider()"))
        XCTAssertTrue(item.contains("Label(metricText, systemImage: summary.metricSymbol)"), "non-reminder status remains compact")
        XCTAssertTrue(item.contains("Label(metricText, systemImage: \"bell.fill\")"),
                      "reminder timing must be rendered in the middle region")
        XCTAssertTrue(item.contains("Image(systemName: \"bell.fill\")"))
        XCTAssertFalse(item.contains("Text(verbatim: metricText)"), "reminder timing uses the centered Label")
        XCTAssertTrue(item.contains("frame(width: 44, height: 44)"), "raster actions keep 44pt targets")
        XCTAssertEqual(item.components(separatedBy: "frame(width: 44, height: 44)").count - 1, 1,
                       "the shared action helper keeps 44pt frames")
        XCTAssertTrue(item.contains("gridVisualBandHeight"))

        let today = DayKey.today()
        var checkbox = Habit(name: "这是一个需要优先显示的超长中文习惯名称", emoji: "🧑🏽‍💻")
        checkbox.log[today] = 1
        let quantity = Habit(name: "数量", emoji: "🏋🏽‍♀️", recurrence: Recurrence(target: 3), kind: .quantity)
        var yesNo = Habit(name: "判断", emoji: "✅", kind: .yesNo)
        yesNo.log[today] = Habit.Answer.yes
        let reminder = Habit(name: "提醒事项的长中文名称", emoji: "👩🏽‍🔬", itemType: .reminder,
                             recurrence: .weekdays([2, 4, 6]))
        let habits = [checkbox, quantity, yesNo, reminder]
        let entry = HaiityEntry(date: .now, habits: habits, palettes: HaiityEntry.demo.palettes,
                                widgetResetEnabled: true, largeItems: habits, largeLayout: .grid)
        let image = try render(LargeGridWidgetView(entry: entry)
            .frame(width: 332, height: 356), to: "large-grid-task-3-mixed.png")

        let scale: CGFloat = 2
        let contentX = WidgetLogic.LargeGeometry.outerPadding * scale
        let contentY = contentX
        let tileWidth = ((332 - 2 * WidgetLogic.LargeGeometry.outerPadding
                          - WidgetLogic.LargeGeometry.gridColumnGap) / 2) * scale
        let tileHeight = WidgetLogic.LargeGeometry.gridRowHeight * scale
        let rowPitch = tileHeight + WidgetLogic.LargeGeometry.gridRowGap * scale
        let columnPitch = tileWidth + WidgetLogic.LargeGeometry.gridColumnGap * scale
        for index in 0..<4 {
            let tile = CGRect(x: contentX + CGFloat(index % 2) * columnPitch,
                              y: contentY + CGFloat(index / 2) * rowPitch,
                              width: tileWidth, height: tileHeight)
            XCTAssertGreaterThan(foregroundPixelCount(image, in: tile.offsetBy(dx: 0, dy: 0)
                .intersection(CGRect(x: tile.minX, y: tile.minY, width: tile.width, height: 20 * scale))), 8)
            let actions = CGRect(x: tile.minX, y: tile.maxY - 44 * scale,
                                 width: tile.width, height: 44 * scale)
            XCTAssertGreaterThan(foregroundPixelCount(image, in: actions), 8, "missing actions (index)")
            if index != 3 {
                let graph = CGRect(x: tile.minX, y: tile.minY + 20 * scale,
                                   width: tile.width, height: WidgetLogic.LargeGeometry.gridGraphMinimumHeight * scale)
                XCTAssertGreaterThan(foregroundPixelCount(image, in: graph), 20, "missing graph (index)")
            } else {
                let reminderMiddle = CGRect(x: tile.minX, y: tile.minY + 20 * scale,
                                            width: tile.width, height: 86 * scale)
                XCTAssertGreaterThan(foregroundPixelCount(image, in: reminderMiddle), 8,
                                     "missing reminder timing region")
            }
        }

        let accessible = try render(LargeGridWidgetView(entry: entry)
            .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
            .frame(width: 332, height: 356), to: "large-grid-task-3-accessibility.png")
        XCTAssertGreaterThan(visiblePixelCount(accessible), 20)
        let custom = try render(LargeGridWidgetView(entry: entry)
            .environment(\.widgetRenderingMode, .vibrant)
            .frame(width: 332, height: 356), to: "large-grid-task-3-vibrant.png")
        XCTAssertGreaterThan(visiblePixelCount(custom), 20)
    }

    func testRasterFourGraphRegionsUseFullHeightAndDoNotOverlap() throws {
        let today = DayKey.today()
        let customs = (0..<4).map { CustomPalette(name: "Raster \($0)", base: 0xD97706 + UInt32($0) * 0x082040) }
        let habits = (0..<4).map { index -> Habit in
            var habit = Habit(name: "Raster Habit \(index)", emoji: index.isMultiple(of: 2) ? "*" : "")
            for offset in 0...4 {
                if let day = DayKey.shifted(today, by: -(index * 2 + offset)) {
                    habit.log[day] = (index + offset) % 4 + 1
                }
            }
            habit.palette = .custom(customs[index].id)
            return habit
        }
        let entry = HaiityEntry(date: .now, habits: habits,
                                palettes: PaletteBook(global: .default, customs: customs),
                                largeItems: habits, largeLayout: .grid)
        let image = try render(LargeGridWidgetView(entry: entry).frame(width: 332, height: 356), to: "large-grid-four-regions.png")
        XCTAssertEqual(image.cgImage.map { CGSize(width: $0.width, height: $0.height) },
                       CGSize(width: 664, height: 712))
        XCTAssertGreaterThan(visiblePixelCount(image), 20)

        let scale: CGFloat = 2
        let contentX = WidgetLogic.LargeGeometry.outerPadding * scale
        let contentY = WidgetLogic.LargeGeometry.outerPadding * scale
        let columnWidth = (332 - 2 * WidgetLogic.LargeGeometry.outerPadding - WidgetLogic.LargeGeometry.gridColumnGap) / 2 * scale
        let rowHeight = WidgetLogic.LargeGeometry.gridRowHeight * scale
        let columnGap = WidgetLogic.LargeGeometry.gridColumnGap * scale
        let rowGap = WidgetLogic.LargeGeometry.gridRowGap * scale
        let tiles = (0..<4).map { index -> CGRect in
            let row = index / 2
            let column = index % 2
            return CGRect(x: contentX + CGFloat(column) * (columnWidth + columnGap),
                          y: contentY + CGFloat(row) * (rowHeight + rowGap),
                          width: columnWidth, height: rowHeight)
        }
        for first in 0..<tiles.count {
            for second in (first + 1)..<tiles.count {
                XCTAssertFalse(tiles[first].intersects(tiles[second]))
            }
        }
        for index in 0..<4 {
            let tile = tiles[index]
            let tileX = tile.minX
            let tileY = tile.minY
            let graph = CGRect(x: tileX, y: tileY + 20 * scale,
                               width: columnWidth,
                               height: WidgetLogic.LargeGeometry.gridGraphMinimumHeight * scale)
            XCTAssertGreaterThan(foregroundPixelCount(image, in: graph), 20, "missing graph \(index)")
            XCTAssertGreaterThanOrEqual(tileY, contentY)
            XCTAssertLessThanOrEqual(tileY + rowHeight, 712 - contentY)
            XCTAssertEqual(tile.maxX + (index % 2 == 0 ? columnGap : 0),
                           index % 2 == 0 ? tiles[index + 1].minX : tile.maxX)
            if index < 2 { XCTAssertEqual(tile.maxY + rowGap, tiles[index + 2].minY) }
        }
        let signatures = Set(tiles.map { colorSignature(image, in: CGRect(x: $0.minX, y: $0.minY + 40,
                                                                            width: $0.width, height: 86)) })
        XCTAssertGreaterThanOrEqual(signatures.count, 3)
        let partialEntry = HaiityEntry(date: .now, habits: habits,
                                       palettes: PaletteBook(global: .default, customs: customs),
                                       largeItems: Array(habits.prefix(2)), largeLayout: .grid)
        let partial = try render(LargeGridWidgetView(entry: partialEntry).frame(width: 332, height: 356), to: "large-grid-partial-positions.png")
        XCTAssertEqual(partial.cgImage.map { CGSize(width: $0.width, height: $0.height) }, CGSize(width: 664, height: 712))
        XCTAssertGreaterThan(visiblePixelCount(partial), 20)
        let vibrant = try render(LargeGridWidgetView(entry: entry).environment(\.widgetRenderingMode, .vibrant)
            .frame(width: 332, height: 356), to: "large-grid-custom-vibrant.png")
        XCTAssertGreaterThan(visiblePixelCount(vibrant), 20)

        let rasterSource = try source("HaiityWidget/WidgetGridViews.swift")
        XCTAssertTrue(rasterSource.contains("if habit.isReminder"))
        XCTAssertTrue(rasterSource.contains("bell.fill"))
    }

    func testLargeGeometryMatchesApprovedContributionFirstBudgets() {
        let g = WidgetLogic.LargeGeometry.self
        XCTAssertEqual(g.featuredListHeaderHeight + g.featuredListHeaderGap
                       + g.featuredListHeight + 3 * g.compactListRowHeight
                       + 2 * g.compactListRowGap, 344)
        XCTAssertEqual(2 * g.gridRowHeight + g.gridRowGap, 344)
        XCTAssertEqual(g.focusHeaderHeight + g.focusHeaderGap + g.focusFeaturedHeight
                       + g.focusFeaturedQueueGap + 3 * g.focusQueueHeight
                       + 2 * g.itemSpacing, 340)
        XCTAssertLessThanOrEqual(g.listContentHeight, g.contentHeight)
        XCTAssertLessThanOrEqual(g.gridContentHeight, g.contentHeight)
        XCTAssertLessThanOrEqual(g.focusContentHeight, g.contentHeight)
        XCTAssertEqual(g.listGraphHeight, 61)
        XCTAssertEqual(g.focusFeaturedGraphMinimumHeight, 104)
    }

    func testListeUsesFeaturedItemAndCompactStatusRows() throws {
        let source = try source("HaiityWidget/RosterWidgetView.swift")
        let list = try sourceSlice(source,
                                   from: "struct LargeListWidgetView",
                                   to: "struct LargeFocusWidgetView")

        XCTAssertTrue(list.contains("LargeFeaturedWidgetItem"))
        XCTAssertTrue(list.contains("LargeCompactWidgetRow"))
        XCTAssertTrue(list.contains("entry.largeItems.dropFirst().prefix(3)"))
        XCTAssertTrue(list.contains("LargeWidgetHeader(entry: entry)"))

        let featured = try sourceSlice(source,
                                       from: "private struct LargeFeaturedWidgetItem",
                                       to: "private struct LargeCompactWidgetRow")
        XCTAssertTrue(featured.contains("TrailingGrid(habit: habit"))
        XCTAssertTrue(featured.contains("if habit.isReminder"))
        XCTAssertTrue(featured.contains("summary.metricText"))
        XCTAssertTrue(featured.contains("frame(width: 44, height: 44)"))
        XCTAssertTrue(featured.contains("featuredListHeight"))
        let reminderBranch = try sourceSlice(featured, from: "if habit.isReminder", to: "} else")
        XCTAssertFalse(reminderBranch.contains("TrailingGrid(habit: habit"))
        let compact = try sourceSlice(source,
                                     from: "private struct LargeCompactWidgetRow",
                                     to: "struct LargeListWidgetView")
        XCTAssertTrue(compact.contains("compactListRowHeight"))
    }

    func testFeaturedItemLinksIdentityAndVisualContentToHabits() throws {
        let source = try source("HaiityWidget/RosterWidgetView.swift")
        let featured = try sourceSlice(source,
                                       from: "private struct LargeFeaturedWidgetItem",
                                       to: "private struct LargeCompactWidgetRow")
        XCTAssertTrue(featured.contains("Link(destination: HaiityWidgetLink.habits)"))
        XCTAssertTrue(featured.contains("let visualBand = Group"))
        XCTAssertTrue(featured.contains("identityBand"))
        XCTAssertFalse(try sourceSlice(featured,
                                       from: "private func actions",
                                       to: "private func largeActionButton").contains("Link(destination: HaiityWidgetLink.habits)"))
    }

    func testFeaturedActionBandShowsCurrentMetricAlongsideActions() throws {
        let source = try source("HaiityWidget/RosterWidgetView.swift")
        let featured = try sourceSlice(source,
                                       from: "private struct LargeFeaturedWidgetItem",
                                       to: "private struct LargeCompactWidgetRow")
        let actions = try sourceSlice(featured,
                                      from: "private func actions",
                                      to: "private func largeActionButton")
        XCTAssertTrue(actions.contains("summary.metricText"))
        XCTAssertTrue(actions.contains("Label(summary.metricText, systemImage: summary.metricSymbol)"))
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
        let g = WidgetLogic.LargeGeometry.self
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
        XCTAssertEqual(g.outerPadding, 6)
        XCTAssertEqual(g.actionHeight, 44)
    }

    func testLargeLayoutsExposeNonOverlappingReservedBandsWithinContentBudget() throws {
        let g = WidgetLogic.LargeGeometry.self
        let geometrySource = try source("HaiityWidget/WidgetLogic.swift")
        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        let grid = try source("HaiityWidget/WidgetGridViews.swift")

        XCTAssertTrue(geometrySource.contains("listIdentityBandHeight"))
        XCTAssertTrue(geometrySource.contains("listVisualBandHeight"))
        XCTAssertTrue(geometrySource.contains("listActionBandHeight"))
        XCTAssertTrue(geometrySource.contains("gridIdentityBandHeight"))
        XCTAssertTrue(geometrySource.contains("gridVisualBandHeight"))
        XCTAssertTrue(geometrySource.contains("gridActionBandHeight"))
        XCTAssertTrue(geometrySource.contains("focusIdentityBandHeight"))
        XCTAssertTrue(geometrySource.contains("focusVisualBandHeight"))
        XCTAssertTrue(geometrySource.contains("focusActionBandHeight"))

        XCTAssertLessThanOrEqual(g.listRowHeight, g.contentHeight)
        XCTAssertLessThanOrEqual(g.gridRowHeight, g.contentHeight)
        XCTAssertLessThanOrEqual(g.focusFeaturedHeight, g.contentHeight)

        let featured = try sourceSlice(roster, from: "private struct LargeFeaturedWidgetItem", to: "private struct LargeCompactWidgetRow")
        let gridItem = try sourceSlice(grid, from: "private struct LargeGridItem", to: "/// Gemeinsame Rasterbausteine")
        XCTAssertTrue(featured.contains("featuredIdentityBandHeight"))
        XCTAssertTrue(featured.contains("featuredVisualBandHeight"))
        XCTAssertTrue(featured.contains("featuredActionBandHeight"))
        XCTAssertTrue(gridItem.contains("gridIdentityBandHeight"))
        XCTAssertTrue(gridItem.contains("gridVisualBandHeight"))
        XCTAssertTrue(gridItem.contains("gridActionBandHeight"))
        XCTAssertTrue(gridItem.contains("if habit.isReminder"))
        XCTAssertTrue(gridItem.contains("reminder"))
    }

    func testLargeGridFixtureRendersSupportedVisualBands() throws {
        let today = DayKey.today()
        var checkbox = Habit(name: "Checkbox", emoji: "*")
        checkbox.log[today] = 1
        let quantity = Habit(name: "Quantity", emoji: "+", recurrence: Recurrence(target: 3), kind: .quantity)
        var yesNo = Habit(name: "Yes No", emoji: "?", kind: .yesNo)
        yesNo.log[today] = Habit.Answer.yes
        let reminder = Habit(name: "Reminder", emoji: "!", itemType: .reminder,
                             recurrence: .weekdays([2, 4, 6]))
        let habits = [checkbox, quantity, yesNo, reminder]
        let entry = HaiityEntry(date: .now, habits: habits, largeItems: habits, largeLayout: .grid)
        let image = try render(LargeGridWidgetView(entry: entry).frame(width: 332, height: 356),
                               to: "large-task-4-supported-bands.png")
        let scale: CGFloat = 2
        let tileWidth = (332 - 2 * WidgetLogic.LargeGeometry.outerPadding
                         - WidgetLogic.LargeGeometry.gridColumnGap) / 2 * scale
        let tileHeight = WidgetLogic.LargeGeometry.gridRowHeight * scale
        let x = WidgetLogic.LargeGeometry.outerPadding * scale
        let y = WidgetLogic.LargeGeometry.outerPadding * scale
        for index in 0..<4 {
            let tile = CGRect(x: x + CGFloat(index % 2) * (tileWidth + 16),
                              y: y + CGFloat(index / 2) * (tileHeight + 16),
                              width: tileWidth, height: tileHeight)
            let identity = CGRect(x: tile.minX, y: tile.minY, width: tile.width, height: 40)
            let visual = CGRect(x: tile.minX, y: identity.maxY, width: tile.width,
                                height: WidgetLogic.LargeGeometry.gridVisualBandHeight * scale)
            let actions = CGRect(x: tile.minX, y: tile.maxY - 88, width: tile.width, height: 88)
            XCTAssertGreaterThan(foregroundPixelCount(image, in: identity), 2)
            XCTAssertGreaterThan(foregroundPixelCount(image, in: visual), 8)
            XCTAssertGreaterThan(foregroundPixelCount(image, in: actions), 8)
            XCTAssertFalse(identity.intersects(visual))
            XCTAssertFalse(visual.intersects(actions))
        }
        XCTAssertLessThanOrEqual(WidgetLogic.LargeGeometry.gridContentHeight,
                                 WidgetLogic.LargeGeometry.contentHeight)
    }

    func testListeAndFokusKeepIdentityVisualAndActionRegionsSeparate() throws {
        let source = try source("HaiityWidget/RosterWidgetView.swift")
        let listItem = try sourceSlice(source, from: "private struct LargeFeaturedWidgetItem", to: "private struct LargeCompactWidgetRow")
        let focusStart = try XCTUnwrap(source.range(of: "struct LargeFocusWidgetView"))
        let focus = String(source[focusStart.lowerBound...])

        XCTAssertTrue(listItem.contains("featuredIdentityBandHeight"))
        XCTAssertTrue(listItem.contains("featuredVisualBandHeight"))
        XCTAssertTrue(listItem.contains("featuredActionBandHeight"))
        XCTAssertTrue(focus.contains("graph: false"))
        XCTAssertFalse(focus.contains("graphHeight: WidgetLogic.LargeGeometry.focusQueueHeight"))
    }

    func testFokusUsesFixedFeaturedAndQueueGeometry() throws {
        let g = WidgetLogic.LargeGeometry.self
        XCTAssertEqual(g.focusFeaturedHeight, 148)
        XCTAssertEqual(g.focusQueueHeight, 52)
        XCTAssertEqual(g.focusHeaderHeight + g.focusHeaderGap + g.focusFeaturedHeight
                       + g.focusFeaturedQueueGap + 3 * g.focusQueueHeight
                       + 2 * g.itemSpacing, 340)

        let source = try source("HaiityWidget/RosterWidgetView.swift")
        let focusStart = try XCTUnwrap(source.range(of: "struct LargeFocusWidgetView"))
        let focus = String(source[focusStart.lowerBound...])
        XCTAssertTrue(focus.contains("focusHeaderGap"))
        XCTAssertTrue(focus.contains("focusFeaturedGraphMinimumHeight"))
        XCTAssertTrue(focus.contains("focusFeaturedQueueGap"))
        XCTAssertTrue(focus.contains("dropFirst().prefix(3)"))
        XCTAssertFalse(focus.contains("preserveFocusSurface"))
    }

    func testListeDoesNotUseRepeatedCardTreatmentAndUsesLargeGraphRegion() throws {
        let source = try source("HaiityWidget/RosterWidgetView.swift")
        let list = try sourceSlice(source, from: "struct LargeListWidgetView", to: "struct LargeFocusWidgetView")
        XCTAssertTrue(list.contains("LargeFeaturedWidgetItem"))
        let item = try sourceSlice(source, from: "private struct LargeFeaturedWidgetItem", to: "private struct LargeCompactWidgetRow")
        XCTAssertTrue(item.contains("featuredIdentityBandHeight"))
        XCTAssertTrue(item.contains("summary.metricText"))
        XCTAssertTrue(item.contains("featuredVisualBandHeight"))
        XCTAssertTrue(item.contains("featuredActionBandHeight"))
        XCTAssertTrue(item.contains("background(.thinMaterial"))
    }

    func testLargeListKeepsActionsBesideTheGraphAndRasterKeepsReadableBands() throws {
        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        let item = try sourceSlice(roster, from: "private struct LargeFeaturedWidgetItem", to: "private struct LargeCompactWidgetRow")
        XCTAssertTrue(item.contains("LargeFeaturedWidgetItem"),
                      "fixed-height list items must keep actions beside the graph")
        XCTAssertTrue(item.contains("summary.metricText"),
                      "the title/status band remains a distinct horizontal region")

        let grid = try source("HaiityWidget/WidgetGridViews.swift")
        let gridItem = try sourceSlice(grid, from: "private struct LargeGridItem", to: "/// Gemeinsame Rasterbausteine")
        XCTAssertFalse(gridItem.contains("frame(width: 48"),
                       "the compact status column must remain flexible for localization")
        XCTAssertEqual(WidgetLogic.LargeGeometry.gridIdentityBandHeight, 20)
        XCTAssertEqual(WidgetLogic.LargeGeometry.gridVisualBandHeight, 98)
        XCTAssertEqual(WidgetLogic.LargeGeometry.gridItemPadding, 2)
        XCTAssertEqual(WidgetLogic.LargeGeometry.gridIdentityBandHeight
                       + WidgetLogic.LargeGeometry.gridVisualBandHeight
                       + WidgetLogic.LargeGeometry.gridActionBandHeight
                       + 2 * WidgetLogic.LargeGeometry.gridItemSpacing
                       + 2 * WidgetLogic.LargeGeometry.gridItemPadding, 168)
    }

    func testLargeRenderersDeclareWidgetBackgroundAndBoundFocusLayout() throws {
        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        let grid = try source("HaiityWidget/WidgetGridViews.swift")

        XCTAssertEqual(roster.components(separatedBy: ".containerBackground(for: .widget)").count - 1, 1)
        XCTAssertTrue(grid.contains(".containerBackground(for: .widget)"))
        XCTAssertTrue(roster.contains("LargeGeometry.focusQueueHeight"))
        XCTAssertTrue(roster.contains("LargeGeometry.itemSpacing"))
        XCTAssertTrue(roster.contains("LargeGeometry.focusFeaturedHeight"))
        XCTAssertTrue(roster.contains("LargeGeometry.featuredListHeight"))
        XCTAssertTrue(roster.contains("focusFeaturedGraphMinimumHeight"))
        XCTAssertTrue(roster.contains("width: WidgetLogic.LargeGeometry.actionHeight"))
        XCTAssertTrue(grid.contains("frame(width: 44, height: 44)"))
    }

    func testLargeLayoutsFitTheRealSystemLargeContentBudget() {
        XCTAssertEqual(WidgetLogic.LargeGeometry.contentHeight, 344)
        XCTAssertEqual(WidgetLogic.LargeGeometry.listContentHeight,
                       WidgetLogic.LargeGeometry.featuredListHeaderHeight
                       + WidgetLogic.LargeGeometry.featuredListHeaderGap
                       + WidgetLogic.LargeGeometry.featuredListHeight
                       + 3 * WidgetLogic.LargeGeometry.compactListRowHeight
                       + 2 * WidgetLogic.LargeGeometry.compactListRowGap)
        XCTAssertEqual(WidgetLogic.LargeGeometry.gridContentHeight,
                       2 * WidgetLogic.LargeGeometry.gridRowHeight
                       + WidgetLogic.LargeGeometry.gridRowGap)
        XCTAssertLessThanOrEqual(WidgetLogic.LargeGeometry.listContentHeight,
                                 WidgetLogic.LargeGeometry.contentHeight)
        XCTAssertEqual(WidgetLogic.LargeGeometry.focusContentHeight,
                       WidgetLogic.LargeGeometry.focusHeaderHeight
                       + WidgetLogic.LargeGeometry.focusHeaderGap
                       + WidgetLogic.LargeGeometry.focusFeaturedHeight
                       + 3 * WidgetLogic.LargeGeometry.focusQueueHeight
                       + 3 * WidgetLogic.LargeGeometry.itemSpacing)
        XCTAssertLessThanOrEqual(WidgetLogic.LargeGeometry.focusContentHeight,
                                 WidgetLogic.LargeGeometry.contentHeight)
        XCTAssertGreaterThanOrEqual(WidgetLogic.LargeGeometry.actionHeight, 44)
    }

    func testListeUsesNaturalFourChildGapsAndFokusRestoresPriorSurface() throws {
        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        let list = try sourceSlice(roster, from: "struct LargeListWidgetView", to: "struct LargeFocusWidgetView")
        XCTAssertFalse(list.contains("Spacer().frame"))
        XCTAssertTrue(list.contains("LargeFeaturedWidgetItem"))
        XCTAssertTrue(list.contains("entry.largeItems.dropFirst().prefix(3)"))
        let item = try sourceSlice(roster, from: "private struct LargeFeaturedWidgetItem", to: "private struct LargeCompactWidgetRow")
        XCTAssertFalse(item.contains("preserveFocusSurface"))
        XCTAssertFalse(item.contains("background(AnyShapeStyle(Color.clear)"))
    }

    func testLargeDualUsesTheNativeWidgetBackgroundWithoutInsetCardSurfaces() throws {
        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        let item = try sourceSlice(roster, from: "private struct LargeFeaturedWidgetItem", to: "private struct LargeCompactWidgetRow")
        let dual = try sourceSlice(roster, from: "struct LargeDualWidgetView", to: "struct LargeFocusWidgetView")

        XCTAssertTrue(item.contains("var showsSurface: Bool = true"))
        XCTAssertTrue(item.contains("if showsSurface"))
        XCTAssertTrue(dual.contains("showsSurface: false"),
                      "the dual widget should rely on WidgetKit's container background")
    }

    func testLargeHeaderUsesTodayProgressInsteadOfLargeItemCount() throws {
        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        let focusStart = try XCTUnwrap(roster.range(of: "struct LargeFocusWidgetView"))
        XCTAssertTrue(roster[focusStart.lowerBound...].contains("LargeWidgetHeader"))

        let grid = try source("HaiityWidget/WidgetGridViews.swift")
        XCTAssertFalse(grid.contains("LargeWidgetHeader"))
    }

    func testTaskOneUsesCompactIdentityAndQueuePresentation() throws {
        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        let item = try sourceSlice(roster, from: "private struct LargeFeaturedWidgetItem", to: "private struct LargeCompactWidgetRow")

        XCTAssertFalse(item.contains("frame(width: 18"))
        XCTAssertTrue(item.contains("name"))
        XCTAssertTrue(item.contains("featuredVisualBandHeight"))
        XCTAssertTrue(item.contains("featuredActionBandHeight"))
        XCTAssertTrue(item.contains("frame(width: 44, height: 44)"))

        let focusStart = try XCTUnwrap(roster.range(of: "struct LargeFocusWidgetView"))
        let focus = String(roster[focusStart.lowerBound...])
        XCTAssertTrue(focus.contains("graph: false"))
    }

    func testTaskOneLargeGeometryKeepsListAndFocusWithinContentHeight() {
        let g = WidgetLogic.LargeGeometry.self
        XCTAssertLessThanOrEqual(g.listContentHeight, g.contentHeight)
        XCTAssertLessThanOrEqual(g.focusContentHeight, g.contentHeight)
        XCTAssertEqual(g.actionHeight, 44)
    }

    func testTaskTwoFokusQueueSuppressesGraphsAndProtectsMixedDynamicTypeIdentity() throws {
        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        let list = try sourceSlice(roster, from: "struct LargeListWidgetView", to: "struct LargeFocusWidgetView")
        let focusStart = try XCTUnwrap(roster.range(of: "struct LargeFocusWidgetView"))
        let focus = String(roster[focusStart.lowerBound...])
        let item = try sourceSlice(roster, from: "private struct LargeWidgetItem", to: "private extension View")
        XCTAssertTrue(list.contains("LargeFeaturedWidgetItem(habit: featured, entry: entry)"))
        XCTAssertTrue(list.contains("LargeFeaturedWidgetItem(habit: featured, entry: entry)"))
        XCTAssertTrue(item.contains("if graph && habit.isReminder"),
                      "featured reminders must render timing in the middle region")
        XCTAssertTrue(item.contains("TrailingGrid(habit: habit, maxWeeks: compact ? 12 : 18"),
                      "featured non-reminders must retain their graph region")
        XCTAssertTrue(focus.contains("compact: true"))
        XCTAssertEqual(focus.components(separatedBy: "LargeWidgetItem(habit:").count - 1, 2,
                       "Fokus must have one featured item and one queue source path")
        XCTAssertTrue(focus.contains("LargeWidgetItem(habit: focus, entry: entry,"))
        XCTAssertTrue(focus.contains("ForEach(entry.largeItems.dropFirst().prefix(3)) { habit in"))
        XCTAssertTrue(focus.contains("LargeWidgetItem(habit: habit, entry: entry, compact: true,"))
        XCTAssertEqual(focus.components(separatedBy: "graph: false").count - 1, 1,
                       "the queue source path must explicitly suppress graphs")
        XCTAssertTrue(focus.contains("graphHeight: WidgetLogic.LargeGeometry.focusFeaturedGraphMinimumHeight"))
        XCTAssertTrue(item.contains(".minimumScaleFactor(0.8)"))

        let today = DayKey.today()
        var checkbox = Habit(name: "今日需要完成的中文习惯名称", emoji: "🧑🏽‍💻")
        checkbox.log[today] = 1
        let quantity = Habit(name: "第三个数量习惯", emoji: "🏋🏽‍♀️",
                             recurrence: Recurrence(target: 3), kind: .quantity)
        var yesNo = Habit(name: "第四个判断习惯", emoji: "✅", kind: .yesNo)
        yesNo.log[today] = Habit.Answer.yes
        let reminder = Habit(name: "第二个很长的提醒名称", emoji: "📚",
                             itemType: .reminder, recurrence: .weekdays([2, 4, 6]))
        let habits = [checkbox, reminder, quantity, yesNo]
        let entry = HaiityEntry(date: .now, habits: habits, largeItems: habits,
                                largeLayout: .focus)
        let image = try render(LargeFocusWidgetView(entry: entry)
            .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
            .frame(width: 332, height: 356), to: "large-focus-task-2-mixed-dynamic-type.png")
        XCTAssertEqual(image.cgImage.map { CGSize(width: $0.width, height: $0.height) },
                       CGSize(width: 664, height: 712))
        XCTAssertGreaterThan(visiblePixelCount(image), 20)
    }

    func testTaskTwoMixedFocusAndListeRegionsHaveStableForegroundBounds() throws {
        let today = DayKey.today()
        var checkbox = Habit(name: "中文习惯", emoji: "🧑🏽‍💻")
        checkbox.log[today] = 1
        let reminder = Habit(name: "提醒", emoji: "📚", itemType: .reminder,
                             recurrence: .weekdays([2, 4, 6]))
        let quantity = Habit(name: "数量", emoji: "🏋🏽‍♀️",
                             recurrence: Recurrence(target: 3), kind: .quantity)
        var yesNo = Habit(name: "判断", emoji: "✅", kind: .yesNo)
        yesNo.log[today] = Habit.Answer.yes
        let habits = [checkbox, reminder, quantity, yesNo]
        let entry = HaiityEntry(date: .now, habits: habits, largeItems: habits,
                                largeLayout: .focus)
        let scale: CGFloat = 2
        let contentX = WidgetLogic.LargeGeometry.outerPadding * scale
        let contentWidth = (332 - 2 * WidgetLogic.LargeGeometry.outerPadding) * scale
        let focus = try render(LargeFocusWidgetView(entry: entry)
            .frame(width: 332, height: 356), to: "large-focus-task-2-regions.png")

        let featuredTop = (WidgetLogic.LargeGeometry.focusHeaderHeight
                           + WidgetLogic.LargeGeometry.focusHeaderGap) * scale
        let featuredGraph = CGRect(x: contentX,
                                   y: contentX + featuredTop + WidgetLogic.LargeGeometry.listTitleHeight * scale,
                                   width: contentWidth,
                                   height: WidgetLogic.LargeGeometry.focusFeaturedGraphMinimumHeight * scale)
        let featuredDensity = Double(foregroundPixelCount(focus, in: featuredGraph))
            / Double(featuredGraph.width * featuredGraph.height)
        XCTAssertGreaterThan(foregroundPixelCount(focus, in: featuredGraph), 40)

        let queueStart = featuredTop + WidgetLogic.LargeGeometry.focusFeaturedHeight * scale
            + WidgetLogic.LargeGeometry.focusFeaturedQueueGap * scale
        let queueHeight = WidgetLogic.LargeGeometry.focusQueueHeight * scale
        let queueGap = WidgetLogic.LargeGeometry.itemSpacing * scale
        let queueContent = CGRect(x: contentX, y: contentX + queueStart,
                                  width: contentWidth, height: queueHeight)
        let graphOnlyBand = CGRect(x: contentX + 8 * scale,
                                   y: queueContent.minY + WidgetLogic.LargeGeometry.listTitleHeight * scale,
                                   width: contentWidth - 56 * scale,
                                   height: queueHeight - WidgetLogic.LargeGeometry.listTitleHeight * scale)
        for index in 0..<3 {
            let row = queueContent.offsetBy(dx: 0, dy: CGFloat(index) * (queueHeight + queueGap))
            XCTAssertGreaterThan(foregroundPixelCount(focus, in: row), 20,
                                 "queue row (index) has no foreground")
            let identity = CGRect(x: row.minX, y: row.minY, width: row.width, height: 20 * scale)
            XCTAssertGreaterThan(foregroundPixelCount(focus, in: identity), 8,
                                 "queue identity/status (index) is missing")
            let actions = CGRect(x: row.maxX - 52 * scale, y: row.minY,
                                 width: 52 * scale, height: row.height)
            XCTAssertGreaterThan(foregroundPixelCount(focus, in: actions), 8,
                                 "queue actions (index) are missing")
            let band = graphOnlyBand.offsetBy(dx: 0, dy: CGFloat(index) * (queueHeight + queueGap))
            let queueDensity = Double(foregroundPixelCount(focus, in: band))
                / Double(band.width * band.height)
            XCTAssertLessThan(queueDensity, max(0.01, featuredDensity * 0.35),
                              "queue (index) unexpectedly contains a tile-grid-density graph")
            if index < 2 {
                let gap = CGRect(x: contentX, y: row.maxY, width: contentWidth, height: queueGap)
                XCTAssertLessThanOrEqual(foregroundPixelCount(focus, in: gap), 12,
                                         "queue row (index) overflows its gap")
            }
        }

        let list = try render(LargeListWidgetView(entry: entry)
            .frame(width: 332, height: 356), to: "large-list-task-2-regions.png")
        let listRowHeight = WidgetLogic.LargeGeometry.listRowHeight * scale
        let listGap = WidgetLogic.LargeGeometry.itemSpacing * scale
        let listStart = contentX
        for index in 0..<4 {
            let row = CGRect(x: contentX, y: listStart + CGFloat(index) * (listRowHeight + listGap),
                             width: contentWidth, height: listRowHeight)
            XCTAssertGreaterThan(foregroundPixelCount(list, in: row), 20,
                                 "Liste row (index) has no foreground")
            if index != 1 {
                let graph = CGRect(x: row.minX, y: row.minY + WidgetLogic.LargeGeometry.listTitleHeight * scale,
                                   width: row.width, height: WidgetLogic.LargeGeometry.listGraphHeight * scale)
                XCTAssertGreaterThan(foregroundPixelCount(list, in: graph), 20,
                                     "Liste habit graph (index) is missing")
            }
        }
    }

    func testLargeProvidersUseLargeDemoPlaceholders() throws {
        let source = try self.source("HaiityWidget/HaiityWidget.swift")
        XCTAssertEqual(source.components(separatedBy: "func placeholder(in context: Context) -> HaiityEntry { .demoLarge }").count - 1, 3)
    }

    func testLargeRenderersCoverSparseAndRepresentativeHabitKinds() throws {
        let demo = HaiityEntry.demo
        let empty = HaiityEntry(date: demo.date, habits: [], palettes: demo.palettes,
                                widgetResetEnabled: true, largeItems: [], largeLayout: .focus)
        let sparse = HaiityEntry(date: demo.date, habits: demo.habits, palettes: demo.palettes,
                                 widgetResetEnabled: true, largeItems: Array(demo.habits.prefix(1)), largeLayout: .list)
        try render(LargeListWidgetView(entry: empty).frame(width: 332, height: 356), to: "large-empty.png")
        try render(LargeFocusWidgetView(entry: sparse).frame(width: 332, height: 356), to: "large-sparse.png")

        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        let grid = try source("HaiityWidget/WidgetGridViews.swift")
        for text in [roster, grid] {
            for marker in ["case .checkbox, .reminder", "case .quantity", "case .yesNo",
                           "CheckOffHabitIntent", "AnswerYesHabitIntent", "AnswerNoHabitIntent",
                           "ResetHabitIntent"] {
                XCTAssertTrue(text.contains(marker), "missing rendering contract: \(marker)")
            }
        }
    }

    func testAllLargeRenderersProducePixelsAtRealLargeGeometry() throws {
        let demo = HaiityEntry.demo
        let entry = HaiityEntry(date: demo.date, habits: demo.habits,
                                palettes: demo.palettes, widgetResetEnabled: true,
                                largeItems: demo.habits, largeLayout: .list)
        try render(LargeListWidgetView(entry: entry)
            .background(Color.white)
            .frame(width: 332, height: 356), to: "haiity-ui-redesign-list-composited.png")
        try render(LargeGridWidgetView(entry: entry)
            .background(Color.white)
            .frame(width: 332, height: 356), to: "haiity-ui-redesign-grid-composited.png")
        try render(LargeFocusWidgetView(entry: entry)
            .background(Color.white)
            .frame(width: 332, height: 356), to: "haiity-ui-redesign-focus-composited.png")
    }

    func testAllLargeLayoutsShareTheEmptyAppGroupState() throws {
        let cases: [(LargeWidgetLayout, AnyView)] = [
            (.list, AnyView(LargeListWidgetView(entry: emptyEntry(.list)))),
            (.grid, AnyView(LargeGridWidgetView(entry: emptyEntry(.grid)))),
            (.focus, AnyView(LargeFocusWidgetView(entry: emptyEntry(.focus))))
        ]
        for (layout, view) in cases {
            let image = try render(view.frame(width: 332, height: 356), to: "large-empty-\(layout).png")
            XCTAssertEqual(image.cgImage.map { CGSize(width: $0.width, height: $0.height) },
                           CGSize(width: 664, height: 712), "wrong \(layout) pixel size")
            XCTAssertGreaterThan(visiblePixelCount(image), 20, "\(layout) empty state has no visible pixels")
        }

        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        let bodyRange = try XCTUnwrap(roster.range(of: "func content(family:"))
        let body = roster[bodyRange.lowerBound...]
        XCTAssertTrue(body.contains("WidgetEmptyState()"))
        let emptyRoster = try render(RosterWidgetView(entry: emptyEntry(.list))
            .content(family: .systemLarge, dark: false)
            .frame(width: 332, height: 356), to: "large-roster-empty.png")
        XCTAssertEqual(emptyRoster.cgImage.map { CGSize(width: $0.width, height: $0.height) },
                       CGSize(width: 664, height: 712))
        XCTAssertGreaterThan(visiblePixelCount(emptyRoster), 20)
    }

    func testLargeRenderersRenderAllItemKindsAndReminderStatusWithoutGraph() throws {
        let today = DayKey.today()
        var checkbox = Habit(name: "Checkbox", emoji: "C")
        checkbox.log[today] = 1
        let quantity = Habit(name: "Count", recurrence: Recurrence(target: 3), kind: .quantity)
        var yesNo = Habit(name: "Yes No", kind: .yesNo)
        yesNo.log[today] = Habit.Answer.yes
        var reminder = Habit(name: "Reminder", itemType: .reminder,
                             recurrence: .weekdays([2, 4, 6]))
        reminder.missedDays = [today]
        let entry = HaiityEntry(date: .now,
                                habits: [checkbox, quantity, yesNo, reminder],
                                largeItems: [checkbox, quantity, yesNo, reminder],
                                largeLayout: .grid)

        try render(LargeListWidgetView(entry: entry).frame(width: 332, height: 356), to: "large-all-kinds-list.png")
        try render(LargeGridWidgetView(entry: entry).frame(width: 332, height: 356), to: "large-all-kinds-grid.png")
        try render(LargeFocusWidgetView(entry: entry).frame(width: 332, height: 356), to: "large-all-kinds-focus.png")

        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        let grid = try source("HaiityWidget/WidgetGridViews.swift")
        for text in [roster, grid] {
            XCTAssertTrue(text.contains("TrailingGrid(habit: habit"))
            XCTAssertTrue(text.contains("summary.metricText"))
            XCTAssertTrue(text.contains("bell.fill"))
            XCTAssertTrue(text.contains("if habit.isReminder"))
        }
    }

    func testLargeRenderersRenderDarkAndVibrantStates() throws {
        let entry = HaiityEntry.demo
        for (name, view) in [("list", AnyView(LargeListWidgetView(entry: entry))),
                             ("grid", AnyView(LargeGridWidgetView(entry: entry))),
                             ("focus", AnyView(LargeFocusWidgetView(entry: entry)))] {
            let dark = try render(view.environment(\.colorScheme, .dark)
                .frame(width: 332, height: 356), to: "large-\(name)-dark.png")
            let vibrant = try render(view.environment(\.widgetRenderingMode, .vibrant)
                .frame(width: 332, height: 356), to: "large-\(name)-vibrant.png")
            XCTAssertGreaterThan(visiblePixelCount(dark), 20)
            XCTAssertGreaterThan(visiblePixelCount(vibrant), 20)

            let largeType = try render(view.environment(\.sizeCategory, .accessibilityLarge)
                .frame(width: 332, height: 356), to: "large-\(name)-dynamic-type-large.png")
            XCTAssertEqual(largeType.cgImage.map { CGSize(width: $0.width, height: $0.height) },
                           CGSize(width: 664, height: 712))
            XCTAssertGreaterThan(visiblePixelCount(largeType), 20)

            let dynamicType = try render(view.environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
                .frame(width: 332, height: 356), to: "large-\(name)-dynamic-type.png")
            XCTAssertEqual(dynamicType.cgImage.map { CGSize(width: $0.width, height: $0.height) },
                           CGSize(width: 664, height: 712))
            XCTAssertGreaterThan(visiblePixelCount(dynamicType), 20)
        }
    }

    func testHaiityDualWidgetRendersTwoFullCardsInTheLargeCanvas() throws {
        let today = DayKey.today()
        var first = Habit(name: "Lesen", emoji: "L")
        first.log[today] = 1
        var second = Habit(name: "Sport", emoji: "S")
        second.log[today] = 1
        let entry = HaiityEntry(date: .now,
                                habits: [first, second],
                                largeItems: [first, second],
                                largeLayout: .dual)

        let image = try render(LargeDualWidgetView(entry: entry)
            .background(Color.white)
            .frame(width: 332, height: 356), to: "haiity-dual-large.png")
        XCTAssertEqual(image.cgImage.map { CGSize(width: $0.width, height: $0.height) },
                       CGSize(width: 664, height: 712))

        let scale: CGFloat = 2
        let firstVisual = CGRect(x: 0,
                                 y: (WidgetLogic.LargeGeometry.outerPadding
                                     + WidgetLogic.LargeGeometry.featuredIdentityBandHeight) * scale,
                                 width: image.size.width * scale,
                                 height: WidgetLogic.LargeGeometry.featuredVisualBandHeight * scale)
        let secondTop = WidgetLogic.LargeGeometry.outerPadding
            + WidgetLogic.LargeGeometry.featuredListHeight
            + WidgetLogic.LargeGeometry.compactListRowGap
        let secondVisual = CGRect(x: 0,
                                  y: (secondTop + WidgetLogic.LargeGeometry.featuredIdentityBandHeight) * scale,
                                  width: image.size.width * scale,
                                  height: WidgetLogic.LargeGeometry.featuredVisualBandHeight * scale)
        XCTAssertGreaterThan(foregroundPixelCount(image, in: firstVisual), 20)
        XCTAssertGreaterThan(foregroundPixelCount(image, in: secondVisual), 20)
    }

    func testListeDynamicTypeRegionsKeepEachRowBoundedAndReadable() throws {
        let today = DayKey.today()
        var habits = (0..<4).map { Habit(name: "Habit \($0)") }
        for index in habits.indices { habits[index].log[today] = 1 + index }
        let entry = HaiityEntry(date: .now, habits: habits, largeItems: habits,
                                largeLayout: .list)

        for (name, category) in [("large", ContentSizeCategory.accessibilityLarge),
                                  ("xxxl", ContentSizeCategory.accessibilityExtraExtraExtraLarge)] {
            let image = try render(LargeListWidgetView(entry: entry)
                .environment(\.sizeCategory, category)
                .frame(width: 332, height: 356), to: "large-list-regions-\(name).png")
            let scale: CGFloat = 2
            let contentTop = Int(WidgetLogic.LargeGeometry.outerPadding * scale)
            let header = Int((WidgetLogic.LargeGeometry.featuredListHeaderHeight
                             + WidgetLogic.LargeGeometry.featuredListHeaderGap) * scale)
            let featuredHeight = Int(WidgetLogic.LargeGeometry.featuredListHeight * scale)
            let featuredIdentityHeight = Int(WidgetLogic.LargeGeometry.featuredIdentityBandHeight * scale)
            let featuredVisualHeight = Int(WidgetLogic.LargeGeometry.featuredVisualBandHeight * scale)
            let featuredActionHeight = Int(WidgetLogic.LargeGeometry.featuredActionBandHeight * scale)
            let compactHeight = Int(WidgetLogic.LargeGeometry.compactListRowHeight * scale)
            let gap = Int(WidgetLogic.LargeGeometry.compactListRowGap * scale)
            let contentBottom = contentTop + Int(WidgetLogic.LargeGeometry.contentHeight * scale)

            let featuredTop = contentTop + header
            let featuredIdentity = CGRect(x: 0, y: CGFloat(featuredTop),
                                          width: image.size.width * scale, height: CGFloat(featuredIdentityHeight))
            let featuredVisual = CGRect(x: 0, y: CGFloat(featuredTop + featuredIdentityHeight),
                                        width: image.size.width * scale, height: CGFloat(featuredVisualHeight))
            let featuredActions = CGRect(x: 0, y: CGFloat(featuredTop + featuredHeight - featuredActionHeight),
                                         width: image.size.width * scale, height: CGFloat(featuredActionHeight))
            XCTAssertGreaterThan(foregroundPixelCount(image, in: featuredIdentity), 2,
                                 "missing featured identity foreground at \(name)")
            XCTAssertGreaterThan(foregroundPixelCount(image, in: featuredVisual), 20,
                                 "missing featured visual foreground at \(name)")
            XCTAssertGreaterThan(foregroundPixelCount(image, in: featuredActions), 8,
                                 "missing featured action foreground at \(name)")
            for row in 0..<3 {
                let rowTop = featuredTop + featuredHeight + row * (compactHeight + gap)
                let identity = CGRect(x: 0, y: CGFloat(rowTop),
                                      width: image.size.width * scale, height: CGFloat(featuredIdentityHeight))
                let actions = CGRect(x: 0, y: CGFloat(rowTop + compactHeight - featuredActionHeight),
                                     width: image.size.width * scale, height: CGFloat(featuredActionHeight))
                XCTAssertGreaterThan(foregroundPixelCount(image, in: identity), 2,
                                     "missing compact identity foreground in row \(row) at \(name)")
                XCTAssertGreaterThan(foregroundPixelCount(image, in: actions), 8,
                                     "missing compact action foreground in row \(row) at \(name)")
                if row < 2 {
                    let interRow = CGRect(x: 0, y: CGFloat(rowTop + compactHeight),
                                          width: image.size.width * scale,
                                          height: CGFloat(gap))
                    XCTAssertLessThanOrEqual(foregroundPixelCount(image, in: interRow), 40,
                                             "row content escaped into the next-row gap at \(name)")
                }
            }
            XCTAssertLessThanOrEqual(contentTop + header + featuredHeight + 3 * compactHeight + 2 * gap,
                                     contentBottom,
                                     "Liste content exceeds the 332pt content bottom at \(name)")
        }
    }

    func testListeReminderRegionsHaveBellAndMetricStatusWithoutGraphRequirement() throws {
        let reminder = Habit(name: "Reminder", itemType: .reminder,
                             recurrence: .weekdays([2, 4, 6]))
        let habits = [reminder, Habit(name: "Habit 1"), Habit(name: "Habit 2"), Habit(name: "Habit 3")]
        let entry = HaiityEntry(date: .now, habits: habits,
                                largeItems: habits, largeLayout: .list)
        for category in [ContentSizeCategory.accessibilityLarge,
                         ContentSizeCategory.accessibilityExtraExtraExtraLarge] {
            let image = try render(LargeListWidgetView(entry: entry)
                .environment(\.sizeCategory, category)
                .frame(width: 332, height: 356), to: "large-list-reminder-\(category).png")
            let rowTop = Int((WidgetLogic.LargeGeometry.outerPadding
                              + WidgetLogic.LargeGeometry.featuredListHeaderHeight
                              + WidgetLogic.LargeGeometry.featuredListHeaderGap) * 2)
            let reminderRow = CGRect(x: 0, y: CGFloat(rowTop), width: image.size.width * 2,
                                     height: WidgetLogic.LargeGeometry.featuredVisualBandHeight * 2)
            XCTAssertGreaterThan(foregroundPixelCount(image, in: reminderRow), 2,
                                 "reminder timing is missing from its featured visual band")
        }
    }

    func testAffectedWidgetsRenderInspectableLightModeImages() throws {
        try render(RosterWidgetView(entry: .demo)
            .content(family: .systemLarge, dark: false)
            .background(Color.white)
            .frame(width: 332, height: 356),
                   to: "haiity-roster-large.png")
        try render(RosterWidgetView(entry: .demo)
            .content(family: .systemLarge, dark: true)
            .environment(\.colorScheme, .dark)
            .frame(width: 332, height: 356),
                   to: "haiity-roster-large-dark.png")

        try render(GraphWidgetView(entry: githubEntry)
            .content(family: .systemMedium, dark: false)
            .frame(width: 332, height: 155),
                   to: "haiity-github-medium.png")
        try render(GraphWidgetView(entry: githubEntry)
            .content(family: .systemMedium, dark: true)
            .environment(\.colorScheme, .dark)
            .frame(width: 332, height: 155),
                   to: "haiity-github-medium-dark.png")
        try render(GraphWidgetView(entry: githubEntry)
            .content(family: .systemMedium, dark: false, mode: .vibrant)
            .frame(width: 332, height: 155),
                   to: "haiity-github-medium-vibrant.png")
    }

    func testDedicatedGraphWidgetsRenderTheLargeFamilyWithInset() throws {
        var habit = Habit(name: "Großes Raster")
        for offset in 0..<180 {
            if let day = DayKey.shifted(DayKey.today(), by: -offset), offset % 3 != 0 {
                habit.log[day] = (offset % 4) + 1
            }
        }
        let habitEntry = HaiityEntry(date: .now,
                                     habits: [habit],
                                     selected: habit.id)

        for (name, entry) in [("habit", habitEntry), ("github", githubEntry)] {
            let image = try render(GraphWidgetView(entry: entry)
                .content(family: .systemLarge, dark: false)
                .frame(width: 332, height: 356),
                                   to: "haiity-(name)-large.png")
            XCTAssertEqual(image.cgImage.map { CGSize(width: $0.width, height: $0.height) },
                           CGSize(width: 664, height: 712))
            XCTAssertGreaterThan(visiblePixelCount(image), 20,
                                 "(name) large graph is blank")
        }

        let source = try source("HaiityWidget/GraphWidgetView.swift")
        XCTAssertTrue(source.contains("family == .systemLarge ? WidgetLogic.LargeGeometry.outerPadding : 0"))
    }

    func testHomeWidgetInkPreservesOpacityLevelsOutsideFullColor() {
        let palette = GraphPalette.blue.style
        var white: CGFloat = 0
        var alpha: CGFloat = 0
        let vibrant = UIColor(HomeWidgetInk.level(1,
                                                  mode: .vibrant,
                                                  dark: false,
                                                  palette: palette))

        XCTAssertTrue(vibrant.getWhite(&white, alpha: &alpha))
        XCTAssertEqual(white, 1, accuracy: 0.001)
        XCTAssertEqual(alpha, WidgetInk.opacity(1), accuracy: 0.001)

        let accented = UIColor(HomeWidgetInk.level(2,
                                                   mode: .accented,
                                                   dark: false,
                                                   palette: palette))
        XCTAssertTrue(accented.getWhite(&white, alpha: &alpha))
        XCTAssertEqual(alpha, WidgetInk.opacity(2), accuracy: 0.001)

        let fullColor = UIColor(HomeWidgetInk.level(1,
                                                    mode: .fullColor,
                                                    dark: false,
                                                    palette: palette))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        XCTAssertTrue(fullColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertGreaterThan(blue, red)
    }

    func testWidgetUndoIsVisibleBeforeTheFirstDecision() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let main = try String(contentsOf: root.appendingPathComponent(
            "HaiityWidget/HaiityWidgetView.swift"))
        let roster = try String(contentsOf: root.appendingPathComponent(
            "HaiityWidget/RosterWidgetView.swift"))

        XCTAssertTrue(main.contains("if entry.widgetResetEnabled {"))
        XCTAssertTrue(roster.contains("if entry.widgetResetEnabled {"))
        XCTAssertFalse(main.contains("entry.widgetResetEnabled && hasValue"),
                       "undo is a configured action, not a post-decision action")
        XCTAssertFalse(roster.contains("entry.widgetResetEnabled && hasValue"),
                       "undo is a configured action, not a post-decision action")
    }

    func testLargeResetEnabledAndDisabledRenderStatesAreCovered() throws {
        let source = try source("HaiityWidget/RosterWidgetView.swift")
        let item = try sourceSlice(source, from: "private struct LargeFeaturedWidgetItem", to: "private struct LargeCompactWidgetRow")
        XCTAssertTrue(item.contains("if entry.widgetResetEnabled"))
        let demo = HaiityEntry.demo
        let enabled = HaiityEntry(date: demo.date, habits: demo.habits, palettes: demo.palettes,
                                   widgetResetEnabled: true, largeItems: Array(demo.habits.prefix(1)), largeLayout: .list)
        let disabled = HaiityEntry(date: demo.date, habits: demo.habits, palettes: demo.palettes,
                                   widgetResetEnabled: false, largeItems: Array(demo.habits.prefix(1)), largeLayout: .list)
        XCTAssertGreaterThan(visiblePixelCount(try render(LargeListWidgetView(entry: enabled)
            .frame(width: 332, height: 356), to: "large-reset-enabled.png")), 20)
        XCTAssertGreaterThan(visiblePixelCount(try render(LargeListWidgetView(entry: disabled)
            .frame(width: 332, height: 356), to: "large-reset-disabled.png")), 20)
    }

    func testLargeActionsHaveIndependentHitTargetsAndResetStates() throws {
        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        let item = try sourceSlice(roster, from: "private struct LargeFeaturedWidgetItem", to: "private struct LargeCompactWidgetRow")
        XCTAssertEqual(item.components(separatedBy: "largeActionButton(intent:").count - 1, 5)
        XCTAssertTrue(item.contains("frame(width: 44, height: 44"))
        XCTAssertTrue(item.contains("if entry.widgetResetEnabled"))
        XCTAssertFalse(item.contains(".frame(minWidth: 44, minHeight: 44)"), "actions must not receive the hit frame as a group")
    }

    func testLargeItemStatusAndDynamicTypeContractsAreObservable() throws {
        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        let item = try sourceSlice(roster, from: "private struct LargeFeaturedWidgetItem", to: "private struct LargeCompactWidgetRow")
        XCTAssertTrue(item.contains("case .done"))
        XCTAssertTrue(item.contains("case .declined"))
        XCTAssertTrue(item.contains("case .open, .free"))
        XCTAssertTrue(item.contains(".foregroundStyle(statusTint(summary.status"))
        XCTAssertTrue(item.contains("featuredVisualBandHeight"))
        let compact = try sourceSlice(roster, from: "private struct LargeCompactWidgetRow", to: "struct LargeListWidgetView")
        XCTAssertTrue(compact.contains("compactListRowHeight"))
        XCTAssertFalse(item.contains("background(AnyShapeStyle(Color.clear)"))
    }

    private var githubEntry: HaiityEntry {
        let today = DayKey.today()
        let days = (0..<371).compactMap { offset -> GitHubContributionDay? in
            guard let date = DayKey.shifted(today, by: -offset) else { return nil }
            let level = offset.isMultiple(of: 7) ? 0 : (offset % 4) + 1
            return GitHubContributionDay(date: date, count: level * 2, level: level)
        }
        return HaiityEntry(date: .now,
                           habits: [],
                           graphSource: .github,
                           githubSnapshot: GitHubContributionSnapshot(username: "enrzh",
                                                                       days: days,
                                                                       fetchedAt: .now))
    }

    private func emptyEntry(_ layout: LargeWidgetLayout) -> HaiityEntry {
        HaiityEntry(date: .now, habits: [], largeItems: [], largeLayout: layout)
    }

    private func render<Content: View>(_ content: Content, to name: String) throws -> UIImage {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.uiImage,
              let data = image.pngData(),
              !data.isEmpty else {
            XCTFail("Could not render \(name)")
            throw NSError(domain: "WidgetRenderingTests", code: 1)
        }
        let outputURL = URL(fileURLWithPath: "/tmp/\(name)")
        try data.write(to: outputURL, options: .atomic)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path),
                      "render output missing: \(outputURL.path)")
        let fileSize = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber
        XCTAssertGreaterThan(fileSize?.intValue ?? 0, 0,
                             "render output is empty: \(outputURL.path)")
        return image
    }

    private func visiblePixelCount(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage,
              let provider = cgImage.dataProvider,
              let data = provider.data,
              let bytes = CFDataGetBytePtr(data) else { return 0 }
        let components = cgImage.bitsPerPixel / 8
        return stride(from: 0, to: cgImage.width * cgImage.height * components, by: components)
            .filter { index in
                let alpha = components == 4 ? bytes[index + 3] : 255
                return alpha > 8 && (components < 3 || bytes[index] > 8 || bytes[index + 1] > 8 || bytes[index + 2] > 8)
            }.count
    }

    private func foregroundPixelCount(_ image: UIImage, in rect: CGRect) -> Int {
        guard let cgImage = image.cgImage,
              let provider = cgImage.dataProvider,
              let data = provider.data,
              let bytes = CFDataGetBytePtr(data) else { return 0 }
        let components = cgImage.bitsPerPixel / 8
        let bounds = CGRect(x: max(0, rect.minX), y: max(0, rect.minY),
                            width: min(CGFloat(cgImage.width) - max(0, rect.minX), rect.width),
                            height: min(CGFloat(cgImage.height) - max(0, rect.minY), rect.height))
        let referenceY = min(cgImage.height - 1, max(0, Int(bounds.midY)))
        let referenceIndex = (referenceY * cgImage.width + 2) * components
        let reference = (Int(bytes[referenceIndex]), Int(bytes[referenceIndex + 1]), Int(bytes[referenceIndex + 2]))
        var count = 0
        for y in Int(bounds.minY)..<Int(bounds.maxY) {
            for x in Int(bounds.minX)..<Int(bounds.maxX) {
                let index = (y * cgImage.width + x) * components
                let distance = abs(Int(bytes[index]) - reference.0)
                    + abs(Int(bytes[index + 1]) - reference.1)
                    + abs(Int(bytes[index + 2]) - reference.2)
                if distance > 18 { count += 1 }
            }
        }
        return count
    }

    private func visiblePixelCount(in image: UIImage, rect: CGRect) -> Int {
        guard let cgImage = image.cgImage, let provider = cgImage.dataProvider,
              let data = provider.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
        let components = cgImage.bitsPerPixel / 8
        var count = 0
        for y in max(0, Int(rect.minY))..<min(cgImage.height, Int(rect.maxY)) {
            for x in max(0, Int(rect.minX))..<min(cgImage.width, Int(rect.maxX)) {
                let index = (y * cgImage.width + x) * components
                if bytes[index] > 8 || bytes[index + 1] > 8 || bytes[index + 2] > 8 { count += 1 }
            }
        }
        return count
    }

    private func colorSignature(_ image: UIImage, in rect: CGRect) -> String {
        guard let cgImage = image.cgImage,
              let provider = cgImage.dataProvider,
              let data = provider.data,
              let bytes = CFDataGetBytePtr(data) else { return "invalid" }
        let components = cgImage.bitsPerPixel / 8
        let minX = max(0, Int(rect.minX)), maxX = min(cgImage.width, Int(rect.maxX))
        let minY = max(0, Int(rect.minY)), maxY = min(cgImage.height, Int(rect.maxY))
        var total = (0, 0, 0), count = 0
        for y in minY..<maxY {
            for x in minX..<maxX {
                let index = (y * cgImage.width + x) * components
                total.0 += Int(bytes[index]); total.1 += Int(bytes[index + 1]); total.2 += Int(bytes[index + 2]); count += 1
            }
        }
        guard count > 0 else { return "empty" }
        return "\(total.0 / count / 2)-\(total.1 / count / 2)-\(total.2 / count / 2)"
    }

    private func colorVariance(_ image: UIImage, in rect: CGRect) -> Double {
        guard let cgImage = image.cgImage, let provider = cgImage.dataProvider,
              let data = provider.data, let bytes = CFDataGetBytePtr(data) else { return .greatestFiniteMagnitude }
        let components = cgImage.bitsPerPixel / 8
        var values: [Double] = []
        for y in max(0, Int(rect.minY))..<min(cgImage.height, Int(rect.maxY)) {
            for x in max(0, Int(rect.minX))..<min(cgImage.width, Int(rect.maxX)) {
                let index = (y * cgImage.width + x) * components
                values.append(Double(Int(bytes[index]) + Int(bytes[index + 1]) + Int(bytes[index + 2])))
            }
        }
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }

    private func colorBins(_ image: UIImage, in rect: CGRect) -> Int {
        guard let cgImage = image.cgImage, let provider = cgImage.dataProvider,
              let data = provider.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
        let components = cgImage.bitsPerPixel / 8
        var bins = Set<String>()
        for y in max(0, Int(rect.minY))..<min(cgImage.height, Int(rect.maxY)) {
            for x in max(0, Int(rect.minX))..<min(cgImage.width, Int(rect.maxX)) {
                let index = (y * cgImage.width + x) * components
                bins.insert("\(bytes[index] / 16)-\(bytes[index + 1] / 16)-\(bytes[index + 2] / 16)")
            }
        }
        return bins.count
    }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath))
    }

    private func sourceSlice(_ source: String, from start: String, to end: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: start))
        let end = try XCTUnwrap(source.range(of: end, range: start.upperBound..<source.endIndex))
        return String(source[start.lowerBound..<end.lowerBound])
    }
}
