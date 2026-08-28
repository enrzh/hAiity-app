import SwiftUI
import UIKit
import XCTest
@testable import Haiity

@MainActor
final class WidgetRenderingTests: XCTestCase {
    func testRasterUsesDedicatedHeaderAndSixTileBudget() throws {
        let source = try source("HaiityWidget/WidgetGridViews.swift")
        XCTAssertTrue(source.contains("LargeGeometry.gridHeaderGap"))
        XCTAssertTrue(source.contains("LargeGeometry.gridColumnGap"))
        XCTAssertTrue(source.contains("LargeGeometry.gridRowGap"))
        XCTAssertTrue(source.contains("entry.largeItems.prefix(6)"))

        let geometry = WidgetLogic.LargeGeometry.self
        XCTAssertEqual(geometry.gridHeaderHeight, 20)
        XCTAssertEqual(geometry.gridHeaderGap, 4)
        XCTAssertEqual(geometry.gridColumnGap, 8)
        XCTAssertEqual(geometry.gridRowGap, 8)
        XCTAssertEqual(geometry.gridGraphMinimumHeight, 48)
        XCTAssertEqual(geometry.gridHeaderHeight + geometry.gridHeaderGap
                       + 3 * geometry.gridRowHeight + 2 * geometry.gridRowGap, 328)

        let body = try sourceSlice(source, from: "struct LargeGridWidgetView", to: "private struct LargeGridItem")
        XCTAssertTrue(body.contains("VStack(alignment: .leading, spacing: 0)"))
        XCTAssertTrue(body.contains("Color.clear.frame(height: WidgetLogic.LargeGeometry.gridHeaderGap)"))
        XCTAssertTrue(body.contains("LazyVGrid"))
        let item = try sourceSlice(source, from: "private struct LargeGridItem", to: "/// Gemeinsame Rasterbausteine")
        XCTAssertTrue(item.contains("LazyVGrid(columns:"))
        XCTAssertTrue(item.contains("frame(width: 44, height: 44)"))
        XCTAssertTrue(item.contains("frame(width: 88, height: 88"))
        XCTAssertFalse(item.contains("VStack(spacing: 0)"))
        XCTAssertTrue(item.contains(".ultraThinMaterial"))
        XCTAssertTrue(item.contains("if habit.isReminder"))
    }

    func testRasterSixGraphRegionsStayBelowHeaderAndDoNotOverlap() throws {
        let today = DayKey.today()
        let customs = (0..<6).map { CustomPalette(name: "Raster \($0)", base: 0xD97706 + UInt32($0) * 0x082040) }
        let habits = (0..<6).map { index -> Habit in
            var habit = Habit(name: "Raster Habit \(index)", emoji: index.isMultiple(of: 2) ? "*" : "")
            habit.log[today] = index + 1
            habit.palette = .custom(customs[index].id)
            return habit
        }
        let entry = HaiityEntry(date: .now, habits: habits,
                                palettes: PaletteBook(global: .default, customs: customs),
                                largeItems: habits, largeLayout: .grid)
        let image = try render(LargeGridWidgetView(entry: entry).frame(width: 332, height: 356), to: "large-grid-six-regions.png")
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
        let headerBottom = contentY + WidgetLogic.LargeGeometry.gridHeaderHeight * scale
            + WidgetLogic.LargeGeometry.gridHeaderGap * scale
        let tiles = (0..<6).map { index -> CGRect in
            let row = index / 2
            let column = index % 2
            return CGRect(x: contentX + CGFloat(column) * (columnWidth + columnGap),
                          y: headerBottom + CGFloat(row) * (rowHeight + rowGap),
                          width: columnWidth, height: rowHeight)
        }
        for first in 0..<tiles.count {
            for second in (first + 1)..<tiles.count {
                XCTAssertFalse(tiles[first].intersects(tiles[second]))
            }
        }
        XCTAssertGreaterThan(foregroundPixelCount(image, in: CGRect(x: contentX, y: contentY,
                                                                      width: 308 * scale,
                                                                      height: WidgetLogic.LargeGeometry.gridHeaderHeight * scale)), 2)
        for index in 0..<6 {
            let tile = tiles[index]
            let tileX = tile.minX
            let tileY = tile.minY
            let graph = CGRect(x: tileX, y: tileY + 20 * scale,
                               width: columnWidth - WidgetLogic.LargeGeometry.actionHeight * scale,
                               height: WidgetLogic.LargeGeometry.gridGraphMinimumHeight * scale)
            XCTAssertGreaterThan(foregroundPixelCount(image, in: graph), 20, "missing graph \(index)")
            XCTAssertGreaterThanOrEqual(tileY, headerBottom)
            XCTAssertLessThanOrEqual(tileY + rowHeight, 712 - contentY)
            XCTAssertEqual(tile.maxX + (index % 2 == 0 ? columnGap : 0),
                           index % 2 == 0 ? tiles[index + 1].minX : tile.maxX)
            if index < 4 { XCTAssertEqual(tile.maxY + rowGap, tiles[index + 2].minY) }
        }
        let partialEntry = HaiityEntry(date: .now, habits: habits,
                                       palettes: PaletteBook(global: .default, customs: customs),
                                       largeItems: Array(habits.prefix(2)), largeLayout: .grid)
        let partial = try render(LargeGridWidgetView(entry: partialEntry).frame(width: 332, height: 356), to: "large-grid-partial-positions.png")
        XCTAssertEqual(partial.cgImage.map { CGSize(width: $0.width, height: $0.height) }, CGSize(width: 664, height: 712))
        XCTAssertGreaterThan(visiblePixelCount(partial), 20)
        let vibrant = try render(LargeGridWidgetView(entry: entry).environment(\.widgetRenderingMode, .vibrant)
            .frame(width: 332, height: 356), to: "large-grid-custom-vibrant.png")
        let accented = try render(LargeGridWidgetView(entry: entry).environment(\.widgetRenderingMode, .accented)
            .frame(width: 332, height: 356), to: "large-grid-custom-accented.png")
        for image in [vibrant, accented] {
            XCTAssertGreaterThan(visiblePixelCount(image), 20)
        }
    }

    func testLargeGeometryMatchesApprovedContributionFirstBudgets() {
        let g = WidgetLogic.LargeGeometry.self
        XCTAssertEqual(g.listHeaderHeight + 4 * g.itemSpacing + 4 * g.listRowHeight, 324)
        XCTAssertEqual(g.gridHeaderHeight + g.gridHeaderGap + 3 * g.gridRowHeight
                       + 2 * g.gridRowGap, 328)
        XCTAssertEqual(g.focusHeaderHeight + g.focusHeaderGap + g.focusFeaturedHeight
                       + 3 * g.focusQueueHeight + 3 * g.itemSpacing, 312)
        XCTAssertLessThanOrEqual(g.listContentHeight, g.contentHeight)
        XCTAssertLessThanOrEqual(g.gridContentHeight, g.contentHeight)
        XCTAssertLessThanOrEqual(g.focusContentHeight, g.contentHeight)
        XCTAssertEqual(g.listGraphHeight, 38)
        XCTAssertEqual(g.focusFeaturedGraphMinimumHeight, 92)
    }

    func testListeDoesNotUseRepeatedCardTreatmentAndUsesLargeGraphRegion() throws {
        let source = try source("HaiityWidget/RosterWidgetView.swift")
        let list = try sourceSlice(source, from: "struct LargeListWidgetView", to: "struct LargeFocusWidgetView")
        XCTAssertTrue(list.contains("graphHeight: WidgetLogic.LargeGeometry.listGraphHeight"))
        let item = try sourceSlice(source, from: "private struct LargeWidgetItem", to: "private extension View")
        XCTAssertTrue(item.contains("listTitleHeight"))
        XCTAssertTrue(item.contains("titleStatusBand"))
        XCTAssertTrue(item.contains(".frame(height: graphHeight)"))
        XCTAssertTrue(item.contains("spacing: WidgetLogic.LargeGeometry.itemSpacing"))
        XCTAssertFalse(item.contains("background(.ultraThinMaterial"))
    }

    func testLargeRenderersDeclareWidgetBackgroundAndBoundFocusLayout() throws {
        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        let grid = try source("HaiityWidget/WidgetGridViews.swift")

        XCTAssertEqual(roster.components(separatedBy: ".containerBackground(for: .widget)").count - 1, 1)
        XCTAssertTrue(grid.contains(".containerBackground(for: .widget)"))
        XCTAssertTrue(roster.contains("LargeGeometry.focusQueueHeight"))
        XCTAssertTrue(roster.contains("LargeGeometry.itemSpacing"))
        XCTAssertTrue(roster.contains("LargeGeometry.focusFeaturedHeight"))
        XCTAssertTrue(roster.contains("LargeGeometry.listGraphHeight"))
        XCTAssertTrue(roster.contains("graphHeight: 32"))
        XCTAssertTrue(roster.contains("width: WidgetLogic.LargeGeometry.actionHeight"))
        XCTAssertTrue(grid.contains("frame(width: 44, height: 44)"))
    }

    func testLargeLayoutsFitTheRealSystemLargeContentBudget() {
        XCTAssertEqual(WidgetLogic.LargeGeometry.contentHeight, 332)
        XCTAssertEqual(WidgetLogic.LargeGeometry.listContentHeight,
                       WidgetLogic.LargeGeometry.listHeaderHeight
                       + 4 * WidgetLogic.LargeGeometry.itemSpacing
                       + 4 * WidgetLogic.LargeGeometry.listRowHeight)
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
        XCTAssertTrue(list.contains("ForEach(entry.largeItems.prefix(4))"))
        let item = try sourceSlice(roster, from: "private struct LargeWidgetItem", to: "private extension View")
        XCTAssertTrue(item.contains("padding(preserveFocusSurface ? 4 : 0)"))
        XCTAssertTrue(item.contains("RoundedRectangle(cornerRadius: 8"))
        XCTAssertTrue(item.contains("clipShape(RoundedRectangle(cornerRadius: 8"))
    }

    func testLargeHeaderUsesTodayProgressInsteadOfLargeItemCount() throws {
        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        XCTAssertTrue(roster.contains("WidgetLogic.progress"))
        XCTAssertFalse(roster.contains("String(entry.largeItems.count)"))
        XCTAssertTrue(roster.contains("met") && roster.contains("due"))
        XCTAssertTrue(roster.contains("isFree"))

        let grid = try source("HaiityWidget/WidgetGridViews.swift")
        XCTAssertTrue(grid.contains("LargeWidgetHeader"))
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
        try render(LargeListWidgetView(entry: entry).frame(width: 332, height: 356), to: "large-list.png")
        try render(LargeGridWidgetView(entry: entry).frame(width: 332, height: 356), to: "large-grid.png")
        try render(LargeFocusWidgetView(entry: entry).frame(width: 332, height: 356), to: "large-focus.png")
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
            let headerHeight = Int(WidgetLogic.LargeGeometry.listHeaderHeight * scale)
            let rowHeight = Int(WidgetLogic.LargeGeometry.listRowHeight * scale)
            let gap = Int(WidgetLogic.LargeGeometry.itemSpacing * scale)
            let titleHeight = Int(WidgetLogic.LargeGeometry.listTitleHeight * scale)
            let graphStart = titleHeight + gap
            let graphHeight = Int(WidgetLogic.LargeGeometry.listGraphHeight * scale)
            let rowStride = rowHeight + gap
            let contentBottom = contentTop + Int(WidgetLogic.LargeGeometry.contentHeight * scale)

            for row in 0..<4 {
                let rowTop = contentTop + headerHeight + gap + row * rowStride
                let title = CGRect(x: 0, y: CGFloat(rowTop), width: image.size.width * scale, height: CGFloat(titleHeight))
                let graph = CGRect(x: 0, y: CGFloat(rowTop + graphStart),
                                   width: image.size.width * scale, height: CGFloat(graphHeight))
                XCTAssertGreaterThan(foregroundPixelCount(image, in: title), 2,
                                     "missing title/status foreground in row \(row) at \(name)")
                XCTAssertGreaterThan(foregroundPixelCount(image, in: graph), 20,
                                     "missing graph foreground in row \(row) at \(name)")
                if row < 3 {
                    let nextRowTop = rowTop + rowStride
                    let interRow = CGRect(x: 0, y: CGFloat(rowTop + rowHeight),
                                          width: image.size.width * scale,
                                          height: CGFloat(gap))
                    XCTAssertLessThanOrEqual(foregroundPixelCount(image, in: interRow), 8,
                                             "graph escaped row \(row) into the next-row gap at \(name)")
                    XCTAssertLessThanOrEqual(rowTop + rowHeight, nextRowTop)
                }
            }
            XCTAssertLessThanOrEqual(contentTop + headerHeight + 4 * rowHeight + 4 * gap,
                                     contentBottom,
                                     "Liste content exceeds the 332pt content bottom at \(name)")
        }
    }

    func testListeReminderRegionsHaveStatusForegroundWithoutGraphRequirement() throws {
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
            let rowTop = (12 + 20 + 4) * 2
            let reminderRow = CGRect(x: 0, y: CGFloat(rowTop), width: image.size.width * 2, height: 72 * 2)
            XCTAssertGreaterThan(foregroundPixelCount(image, in: reminderRow), 2,
                                 "reminder bell/status is missing from its 72pt row")
        }
    }

    func testAffectedWidgetsRenderInspectableLightModeImages() throws {
        try render(RosterWidgetView(entry: .demo)
            .content(family: .systemLarge, dark: false)
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
        let item = try sourceSlice(source, from: "private struct LargeWidgetItem", to: "private extension View")
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
        let item = try sourceSlice(roster, from: "private struct LargeWidgetItem", to: "private extension View")
        XCTAssertEqual(item.components(separatedBy: "largeActionButton(intent:").count - 1, 5)
        XCTAssertTrue(item.contains("frame(width: WidgetLogic.LargeGeometry.actionHeight"))
        XCTAssertTrue(item.contains("if entry.widgetResetEnabled"))
        XCTAssertFalse(item.contains(".frame(minWidth: 44, minHeight: 44)"), "actions must not receive the hit frame as a group")
    }

    func testLargeItemStatusAndDynamicTypeContractsAreObservable() throws {
        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        let item = try sourceSlice(roster, from: "private struct LargeWidgetItem", to: "private extension View")
        XCTAssertTrue(item.contains("case .done"))
        XCTAssertTrue(item.contains("case .declined"))
        XCTAssertTrue(item.contains("case .open, .free"))
        XCTAssertTrue(item.contains("preserveFocusSurface"))
        XCTAssertTrue(item.contains(".foregroundStyle(statusTint(summary.status"))
        XCTAssertTrue(item.contains("frame(height: graphHeight)"))
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
        try data.write(to: URL(fileURLWithPath: "/tmp/\(name)"), options: .atomic)
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
