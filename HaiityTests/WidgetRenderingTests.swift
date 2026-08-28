import SwiftUI
import UIKit
import XCTest
@testable import Haiity

@MainActor
final class WidgetRenderingTests: XCTestCase {
    func testLargeRenderersDeclareWidgetBackgroundAndBoundFocusLayout() throws {
        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        let grid = try source("HaiityWidget/WidgetGridViews.swift")

        XCTAssertEqual(roster.components(separatedBy: ".containerBackground(for: .widget)").count - 1, 1)
        XCTAssertTrue(grid.contains(".containerBackground(for: .widget)"))
        XCTAssertTrue(roster.contains("LargeGeometry.focusQueueHeight"))
        XCTAssertTrue(roster.contains("LargeGeometry.itemSpacing"))
        XCTAssertTrue(roster.contains("LargeGeometry.focusFeaturedHeight"))
        XCTAssertTrue(roster.contains("graphHeight: 32"))
        XCTAssertTrue(roster.contains("graphHeight: 14"))
        XCTAssertTrue(roster.contains("minHeight: 44"))
        XCTAssertTrue(grid.contains("minHeight: 44"))
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
                       + 4 * WidgetLogic.LargeGeometry.itemSpacing
                       + WidgetLogic.LargeGeometry.focusFeaturedHeight
                       + 3 * WidgetLogic.LargeGeometry.focusQueueHeight)
        XCTAssertLessThanOrEqual(WidgetLogic.LargeGeometry.focusContentHeight,
                                 WidgetLogic.LargeGeometry.contentHeight)
        XCTAssertGreaterThanOrEqual(WidgetLogic.LargeGeometry.actionHeight, 44)
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

            let dynamicType = try render(view.environment(\.sizeCategory, .accessibilityLarge)
                .frame(width: 332, height: 356), to: "large-\(name)-dynamic-type.png")
            XCTAssertEqual(dynamicType.cgImage.map { CGSize(width: $0.width, height: $0.height) },
                           CGSize(width: 664, height: 712))
            XCTAssertGreaterThan(visiblePixelCount(dynamicType), 20)
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

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath))
    }
}
