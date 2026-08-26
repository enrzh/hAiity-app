import XCTest

final class FollowUpFixTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative))
    }

    func testContextMenuOwnsAnIndependentCardHost() throws {
        let source = try source("Haiity/Views/HabitCard.swift")

        XCTAssertTrue(source.contains("GraphContextMenuHub"),
                      "a UIKit host may have only one context interaction")
        XCTAssertTrue(source.contains("register(self)"),
                      "each card must register its own frame and actions")
        XCTAssertTrue(source.contains("activeMenu"),
                      "the hub must resolve the held card before building a preview")
        XCTAssertTrue(source.contains("UITargetedPreview(view: host"),
                      "the transition must target the lifted card, not its list-cell siblings")
        XCTAssertTrue(source.contains("roundedRect: host.bounds"),
                      "the lifted card must retain its own rounded bounds")
        XCTAssertTrue(source.contains("isHidden = false"),
                      "the card host must remain in the overlay layout")
    }

    func testGraphPreviewsFitWithoutAHorizontalScrollGesture() throws {
        let habit = try source("Haiity/Views/HabitCard.swift")
        let github = try source("Haiity/Views/GitHubContributionCard.swift")
        let grid = try source("Haiity/Views/ContributionGrid.swift")

        XCTAssertTrue(habit.contains("weeks: gridWeeks"),
                      "habit previews need the complete visible graph window")
        XCTAssertTrue(habit.contains("cellSize: previewGraphCellSize"),
                      "habit preview tiles must fit the popup width")
        XCTAssertTrue(habit.contains("showsMonthLabels: false"),
                      "the enlarged graph should spend its height on tiles")
        XCTAssertTrue(github.contains("showsMonthLabels: false"),
                      "GitHub previews should use the same tile-only treatment")
        XCTAssertTrue(grid.contains(".scrollDisabled(available > 0"),
                      "interactive grids must retain their no-extra-content guard")
    }

    func testHabitPreviewFitsItsFullVisibleGrid() throws {
        let habit = try source("Haiity/Views/HabitCard.swift")

        XCTAssertTrue(habit.contains("weeks: gridWeeks"),
                      "the enlarged habit graph must keep the full visible history")
        XCTAssertTrue(habit.contains("cellSize: previewGraphCellSize"),
                      "the enlarged habit graph must fit its tiles to the popup width")
        XCTAssertTrue(habit.contains("private var previewGraphCellSize"),
                      "the popup needs an explicit tile-size calculation")
    }

    func testGitHubPreviewTilesFitItsActualInnerWidth() throws {
        let github = try source("Haiity/Views/GitHubContributionCard.swift")

        XCTAssertTrue(github.contains("previewWidth - 2 * Theme.Metrics.gutter"),
                      "GitHub tiles must use the preview's real inner width")
        XCTAssertTrue(github.contains("return max(2"),
                      "the minimum tile size must not force the 53 columns to overflow")
    }

    func testNonInteractiveGraphPreviewsDoNotEmbedATrailingScrollView() throws {
        let habitGrid = try source("Haiity/Views/ContributionGrid.swift")
        let githubGrid = try source("Haiity/Views/GitHubContributionGraph.swift")

        XCTAssertTrue(habitGrid.contains("if interactive {"),
                      "habit previews need a direct non-scrollable rendering path")
        XCTAssertTrue(githubGrid.contains("if interactive {"),
                      "GitHub previews need a direct non-scrollable rendering path")
    }

    func testHabitToolbarStartsFilterDirectlyAndShowsResetToast() throws {
        let content = try source("Haiity/Views/ContentView.swift")

        XCTAssertTrue(content.contains("ToolbarItem(placement: .topBarLeading) {\n                        habitFilterMenu"),
                      "the leading toolbar item should be the filter menu itself")
        XCTAssertFalse(content.contains("accessibilityIdentifier(\"habit-management\")"),
                       "the old ellipsis management button must be gone")
        XCTAssertTrue(content.contains("filter-toast"),
                      "active filters need a visible toast hint")
        XCTAssertTrue(content.contains("clear-filters"),
                      "the filter toast needs a direct reset action")
    }

    func testSetupExposesNativeCalendarAndReminderPermissionActions() throws {
        let setup = try source("Haiity/Views/ReminderSetupView.swift")

        XCTAssertTrue(setup.contains("setup-calendar-permission"))
        XCTAssertTrue(setup.contains("setup-reminders-permission"))
        XCTAssertTrue(setup.contains("requestCalendarPermission"))
        XCTAssertTrue(setup.contains("requestRemindersPermission"))
        XCTAssertTrue(setup.contains("calendarPermissionCard"))
    }

    func testMultipleDatePickerUsesAHalfHeightSheet() throws {
        let editor = try source("Haiity/Views/EditHabitSheet.swift")

        XCTAssertTrue(editor.contains(".presentationDetents([.medium])"),
                      "additional recurrence dates should use a half-height sheet")
        XCTAssertTrue(editor.contains(".presentationDragIndicator(.visible)"),
                      "the reduced sheet needs an obvious grab affordance")
    }

    func testContextPreviewUsesMeasuredHeightAndRoundedBounds() throws {
        let menu = try source("Haiity/Views/HabitCard.swift")
        let stats = try source("Haiity/Views/StatsView.swift")

        XCTAssertTrue(menu.contains("sizeThatFits("),
                      "context previews must size themselves from their content")
        XCTAssertTrue(menu.contains("view.layer.cornerRadius = cardRadius"),
                      "the enlarged preview must keep the card silhouette")
        XCTAssertTrue(menu.contains("view.clipsToBounds = true"),
                      "the rounded preview must not spill past its bounds")
        XCTAssertTrue(stats.contains("minHeight: height"),
                      "stats previews need room to grow when their content is taller")
        XCTAssertFalse(stats.contains("height: height,\n                           alignment: .topLeading"),
                       "surface previews must not clip content to a fixed height")
    }

    func testContextPreviewReappliesItsMaskAfterUIKitRelayout() throws {
        let menu = try source("Haiity/Views/HabitCard.swift")

        XCTAssertTrue(menu.contains("RoundedPreviewHostingController"),
                      "UIKit must use a host that can restore the card mask")
        XCTAssertTrue(menu.contains("override func viewDidLayoutSubviews()"),
                      "the system can relayout a context preview after creation")
        XCTAssertTrue(menu.contains("parameters.backgroundColor = .clear"),
                      "the system preview background must not square off the card")
    }

    func testFilterResetUsesTheSameActionToastLayoutAsUndo() throws {
        let content = try source("Haiity/Views/ContentView.swift")
        let filterStart = try XCTUnwrap(content.range(of: "private var filterToast"))
        let filterEnd = try XCTUnwrap(content.range(of: "private var habitsStack",
                                                     range: filterStart.upperBound..<content.endIndex))
        let filter = content[filterStart.lowerBound..<filterEnd.lowerBound]

        XCTAssertTrue(content.contains("private func actionToast<Label: View>"),
                      "action toasts need one shared layout source")
        XCTAssertTrue(content.contains("actionToast(label:"),
                      "the filter hint and undo toast must use the shared layout")
        XCTAssertFalse(filter.contains(".font(.footnote.weight(.semibold))"),
                       "the filter hint must not use a smaller toast-only font")
        XCTAssertFalse(filter.contains(".padding(.horizontal, 16)\n            .padding(.vertical, 10)"),
                       "the filter hint must not keep its old compact spacing")
    }

}
