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
