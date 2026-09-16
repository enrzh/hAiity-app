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
        let start = try XCTUnwrap(source.range(of: "configurationForMenuAtLocation"))
        let provider = try XCTUnwrap(source.range(of: "}, actionProvider:",
                                                 range: start.upperBound..<source.endIndex))
        let preview = source[start.lowerBound..<provider.lowerBound]

        XCTAssertTrue(preview.contains("previewProvider: {"),
                      "UIKit must provide the held card's preview")
        XCTAssertTrue(preview.contains("let root = AnyView(makePreview()"),
                      "the preview provider must build the rounded card root")
        XCTAssertTrue(source.contains(".overlay {"),
                      "graph cards must place the interaction above their scrollable content")
        let overlay = try XCTUnwrap(source.range(of: ".overlay {"))
        let graphMenu = try XCTUnwrap(source.range(of: "GraphContextMenu(",
                                                 range: overlay.upperBound..<source.endIndex))
        XCTAssertFalse(source[overlay.upperBound..<graphMenu.lowerBound]
            .contains("interactionBridgesReady"),
                       "graph card interaction must mount with the card to stay responsive")
    }

    func testContextInteractionIsOwnedByTheHeldCard() throws {
        let source = try source("Haiity/Views/HabitCard.swift")
        let hostStart = try XCTUnwrap(source.range(of: "final class MenuHost: UIView"))
        let hostEnd = try XCTUnwrap(source.range(of: "// MARK: – Wisch-Aktionen (Daten)",
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

    func testContextMenuHidesTheSourceSurfaceWhileItIsPresented() throws {
        let source = try source("Haiity/Views/HabitCard.swift")
        let hostStart = try XCTUnwrap(source.range(of: "final class MenuHost: UIView"))
        let hostEnd = try XCTUnwrap(source.range(of: "// MARK: – Wisch-Aktionen (Daten)",
                                                 range: hostStart.upperBound..<source.endIndex))
        let host = source[hostStart.lowerBound..<hostEnd.lowerBound]

        XCTAssertTrue(host.contains("willDisplayMenuFor"),
                      "the source surface must be hidden as the menu is displayed")
        XCTAssertTrue(host.contains("willEndFor"),
                      "the source surface must be restored when the menu ends")
        XCTAssertTrue(source.contains("onMenuVisibilityChanged"),
                      "the UIKit host needs a visibility callback to the card")
        XCTAssertTrue(source.contains(".opacity(isContextMenuVisible ? 0 : 1)"),
                      "only the original card surface should disappear during the lift")
    }

    func testAllStatsPreviewCallersHideOnlyTheirActiveSourceSurface() throws {
        let stats = try source("Haiity/Views/StatsView.swift")

        XCTAssertTrue(stats.contains("activeContextMenuID"),
                      "stats previews need per-card visibility state")
        XCTAssertTrue(stats.contains("onMenuVisibilityChanged"),
                      "stats previews must report their presentation state")
        XCTAssertTrue(stats.contains("activeContextMenuID =="),
                      "a held stats card must hide only its own source")
    }

    func testStatsCardsDoNotInstallASectionWideSurfaceBehindTheLift() throws {
        let stats = try source("Haiity/Views/StatsView.swift")
        let start = try XCTUnwrap(stats.range(of: "private func statsMetricGrid"))
        let end = try XCTUnwrap(stats.range(of: "@ViewBuilder\n    private func statsMetric",
                                            range: start.upperBound..<stats.endIndex))
        let list = stats[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(list.contains("LazyVGrid"),
                      "statistics metrics must be laid out as individual grid items")
        XCTAssertFalse(list.contains(".settingsListRow()"),
                       "a section-wide surface remains visible behind a lifted card")
        XCTAssertTrue(list.contains(".appSurface()"),
                      "the metrics group must keep the selected appearance material")
    }

    func testContextPreviewProvidesTheSelectedAppearanceBackdrop() throws {
        let source = try source("Haiity/Views/HabitCard.swift")
        let hostStart = try XCTUnwrap(source.range(of: "final class MenuHost: UIView"))
        let start = try XCTUnwrap(source.range(of: "configurationForMenuAtLocation",
                                               range: hostStart.upperBound..<source.endIndex))
        let end = try XCTUnwrap(source.range(of: "}, actionProvider:",
                                             range: start.upperBound..<source.endIndex))
        let menu = source[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(source.contains("@Environment(\\.appearancePreferences)"),
                      "the shared preview bridge must receive the selected appearance")
        XCTAssertFalse(menu.contains("AppearanceBackground(preferences: appearancePreferences)"),
                       "the host must not add a second page-sized preview surface")
        XCTAssertTrue(menu.contains(".appSurface(cornerRadius: radius)"),
                      "the context-menu root must own the single rounded preview surface")
    }

    func testSharedPreviewUsesOneRoundedTargetPath() throws {
        let habit = try source("Haiity/Views/HabitCard.swift")
        let start = try XCTUnwrap(habit.range(of: "private func targetedPreview"))
        let preview = habit[start.lowerBound...]

        XCTAssertTrue(preview.contains("parameters.visiblePath = cardPath"))
        XCTAssertTrue(preview.contains("parameters.shadowPath = cardPath"))
        XCTAssertFalse(preview.contains("shadowPath = UIBezierPath(rect:"),
                       "the shared lift must not add a second rectangular shadow")
    }

    func testStatsPreviewLeavesSurfaceToGraphContextMenuRoot() throws {
        let source = try source("Haiity/Views/StatsView.swift")
        let start = try XCTUnwrap(source.range(of: "let framed = AnyView(surfaced"))
        let end = try XCTUnwrap(source.range(of: "@ViewBuilder", range: start.upperBound..<source.endIndex))
        let returned = source[start.lowerBound..<end.lowerBound]
        XCTAssertTrue(returned.contains("let framed = AnyView(surfaced"))
        XCTAssertFalse(returned.contains("framed.appSurface()"),
                       "the shared context-menu root must own the final preview surface")
    }

    func testPreviewUsesMeasuredContentHeightInsteadOfShadowPadding() throws {
        let source = try source("Haiity/Views/HabitCard.swift")

        XCTAssertTrue(source.contains("measuredHeight > 0"),
                      "the preview host must size itself to the visible card")
        XCTAssertFalse(source.contains("max(height, ceil(measuredHeight))"),
                       "a larger fallback frame creates the halo below enlarged cards")
        XCTAssertTrue(source.contains("RoundedPreviewHostingController"),
                      "the preview host must reapply the card mask after UIKit relayout")
    }

    func testHabitReorderingRequiresExplicitSortingMode() throws {
        let content = try source("Haiity/Views/ContentView.swift")

        XCTAssertTrue(content.contains("habitSortingActive"))
        XCTAssertTrue(content.contains("HabitSortingSession("))
    }

    func testReminderContextMenuUsesTheSharedPreviewBridge() throws {
        let row = try source("Haiity/Views/ReminderRow.swift")

        XCTAssertTrue(row.contains("GraphContextMenu("),
                      "the reminder must use the same reliable preview bridge as graphs")
        XCTAssertTrue(row.contains("previewWidth: previewWidth"))
        XCTAssertTrue(row.contains("commit: onEdit"),
                      "the enlarged reminder must open the editor")
        XCTAssertFalse(row.contains(".contextMenu {"),
                       "the default menu cannot commit the enlarged preview")
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
        XCTAssertTrue(content.contains("store.add(habit)"),
                      "the stats seed must use the store's normal write path")
    }
}
