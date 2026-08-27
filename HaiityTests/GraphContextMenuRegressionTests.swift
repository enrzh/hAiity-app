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

    func testContextMenuHidesTheSourceSurfaceWhileItIsPresented() throws {
        let source = try source("Haiity/Views/HabitCard.swift")
        let hostStart = try XCTUnwrap(source.range(of: "final class MenuHost: UIView"))
        let hostEnd = try XCTUnwrap(source.range(of: "/// UIKit may lay out a context-menu preview",
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
        let start = try XCTUnwrap(stats.range(of: "private var statsList"))
        let end = try XCTUnwrap(stats.range(of: "private var statsSelectionEmpty",
                                            range: start.upperBound..<stats.endIndex))
        let list = stats[start.lowerBound..<end.lowerBound]

        XCTAssertFalse(list.contains(".settingsListRow()"),
                       "a section-wide surface remains visible behind a lifted card")
        XCTAssertTrue(list.contains(".listRowBackground(Color.clear)"),
                      "the list background must stay clear behind individual card surfaces")
    }

    func testContextPreviewProvidesTheSelectedAppearanceBackdrop() throws {
        let source = try source("Haiity/Views/HabitCard.swift")
        let start = try XCTUnwrap(source.range(of: "struct GraphContextMenu: UIViewRepresentable"))
        let end = try XCTUnwrap(source.range(of: "final class MenuHost: UIView",
                                             range: start.upperBound..<source.endIndex))
        let menu = source[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(menu.contains("@Environment(\\.appearancePreferences)"),
                      "the shared preview bridge must receive the selected appearance")
        XCTAssertTrue(menu.contains("AppearanceBackground(preferences: appearancePreferences)"),
                      "material previews need the same page backdrop as the source card")
        XCTAssertTrue(menu.contains("ZStack"),
                      "the page backdrop must sit behind the preview card")
        XCTAssertTrue(menu.contains(".clipShape(RoundedRectangle(cornerRadius: radius"),
                      "the backdrop must remain inside one rounded preview boundary")
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

    func testPreviewUsesMeasuredContentHeightInsteadOfShadowPadding() throws {
        let source = try source("Haiity/Views/HabitCard.swift")

        XCTAssertTrue(source.contains("measuredHeight > 0"),
                      "the preview host must size itself to the visible card")
        XCTAssertFalse(source.contains("max(height, ceil(measuredHeight))"),
                       "a larger fallback frame creates the halo below enlarged cards")
    }

    func testHabitReorderingRequiresExplicitSortingMode() throws {
        let content = try source("Haiity/Views/ContentView.swift")

        XCTAssertTrue(content.contains("canSortHabits && editMode == .active"),
                      "drag reordering must be enabled only in explicit sorting mode")
    }

    func testReminderContextMenuIsLayeredAboveTheRow() throws {
        let row = try source("Haiity/Views/ReminderRow.swift")

        XCTAssertTrue(row.contains(".overlay {\n                GraphContextMenu"),
                      "the reminder hold interaction must sit above row content")
        XCTAssertFalse(row.contains(".background {\n                GraphContextMenu"),
                       "a background interaction host is blocked by the reminder row")
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
