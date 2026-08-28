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
        XCTAssertTrue(roster.contains(".frame(height: 60)"))
        XCTAssertTrue(roster.contains("spacing: 4"))
        XCTAssertTrue(roster.contains(".frame(height: 100)"))
        XCTAssertTrue(roster.contains("minHeight: 44"))
        XCTAssertTrue(grid.contains("minHeight: 44"))
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
        let layouts: [LargeWidgetLayout] = [.list, .grid, .focus]
        for layout in layouts {
            let entry = HaiityEntry(date: .now, habits: [], largeItems: [], largeLayout: layout)
            let view: AnyView
            switch layout {
            case .list: view = AnyView(LargeListWidgetView(entry: entry))
            case .grid: view = AnyView(LargeGridWidgetView(entry: entry))
            case .focus: view = AnyView(LargeFocusWidgetView(entry: entry))
            }
            try render(view.frame(width: 332, height: 356), to: "large-empty-\(layout).png")
        }

        XCTAssertEqual(layouts.count, 3)
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

    private func render<Content: View>(_ content: Content, to name: String) throws {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.uiImage,
              let data = image.pngData(),
              !data.isEmpty else {
            XCTFail("Could not render \(name)")
            return
        }
        try data.write(to: URL(fileURLWithPath: "/tmp/\(name)"), options: .atomic)
    }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath))
    }
}
