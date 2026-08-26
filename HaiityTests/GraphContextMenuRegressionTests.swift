import XCTest

final class GraphContextMenuRegressionTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative))
    }

    func testPreviewLiftUsesACardOwnedSource() throws {
        let source = try source("Haiity/Views/HabitCard.swift")
        let start = try XCTUnwrap(source.range(of: "private func targetedPreview"))
        let preview = source[start.lowerBound...]

        XCTAssertTrue(preview.contains("UITargetedPreview(view: self"),
                      "UIKit must snapshot the held card host")
        XCTAssertTrue(preview.contains("roundedRect: bounds"),
                      "the lift path must stay in the card host's coordinate space")
        XCTAssertFalse(preview.contains("UITargetedPreview(view: container"),
                       "lifting a shared list cell hides sibling stats cards")
        XCTAssertTrue(source.contains(".overlay {\n                GraphContextMenu"),
                      "graph cards must place the interaction above their scrollable content")
    }

    func testContextInteractionIsOwnedByTheHeldCard() throws {
        let source = try source("Haiity/Views/HabitCard.swift")
        let hostStart = try XCTUnwrap(source.range(of: "final class MenuHost: UIView"))
        let hostEnd = try XCTUnwrap(source.range(of: "/// UIKit may lay out a context-menu preview",
                                                 range: hostStart.upperBound..<source.endIndex))
        let host = source[hostStart.lowerBound..<hostEnd.lowerBound]

        XCTAssertTrue(host.contains("UIContextMenuInteraction(delegate: self)"),
                      "UIKit must own one interaction per card host")
        XCTAssertTrue(host.contains("addInteraction(interaction)"),
                      "the card host must receive its own context interaction")
        XCTAssertTrue(host.contains("isUserInteractionEnabled = true"),
                      "the card host must be able to receive the long press")
        XCTAssertFalse(host.contains("GraphContextMenuHub"),
                       "a card must not delegate ownership to a shared list-cell hub")
    }

    func testDebugStatsRouteExistsForTheRenderedCardRegression() throws {
        let content = try source("Haiity/Views/ContentView.swift")

        XCTAssertTrue(content.contains("guard let i = args.firstIndex(of: \"-screen\")"),
                      "the UI regression needs a deterministic screen route")
        XCTAssertTrue(content.contains("URL(string: \"haiity://\\(args[i + 1])\")"),
                      "the screen route must use the app's normal deep-link resolver")
        XCTAssertTrue(content.contains("handleDeepLink(url)"),
                      "the screen route must exercise the production navigation path")
        XCTAssertTrue(content.contains("args.contains(\"-seed-stats\")"),
                      "the UI regression must seed its own stats data")
        XCTAssertTrue(content.contains("UserDefaults.standard.set(true, forKey: ReminderSetup.completedKey)"),
                      "the stats seed must bypass first-run setup on a clean simulator")
        XCTAssertTrue(content.contains("store.add(habit)"),
                      "the stats seed must use the store's normal write path")
    }
}
