import SwiftUI
import UIKit
import XCTest
@testable import Haiity

@MainActor
final class WidgetRenderingTests: XCTestCase {
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
}
