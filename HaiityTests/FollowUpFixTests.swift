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

        XCTAssertTrue(source.contains("final class MenuHost: UIView, UIContextMenuInteractionDelegate"),
                      "the card host must own the context-menu delegate")
        XCTAssertTrue(source.contains("private lazy var interaction = UIContextMenuInteraction(delegate: self)"),
                      "each card must create its own context interaction")
        XCTAssertTrue(source.contains("addInteraction(interaction)"),
                      "each card host must receive its own interaction")
        XCTAssertTrue(source.contains("UITargetedPreview(view: self"),
                      "the lifted card must be the preview source")
        XCTAssertFalse(source.contains("GraphContextMenuHub"),
                       "the interaction must not be attached to a shared list cell")
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
        XCTAssertTrue(grid.contains("if interactive {"),
                      "the live graph may scroll while its fixed geometry remains stable")
        XCTAssertTrue(grid.contains(".defaultScrollAnchor(.trailing)"),
                      "the live graph must still open at the current-day edge")
        XCTAssertFalse(grid.contains("widthReader"),
                       "the graph must not trigger a state update just to measure its width")
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

    func testHabitPreviewUsesTheSelectedSurfaceWithoutASecondOpaqueHalo() throws {
        let habit = try source("Haiity/Views/HabitCard.swift")

        XCTAssertTrue(habit.contains("habitPreview"),
                      "the context menu must keep a complete card preview")
        XCTAssertTrue(habit.contains(".appSurface()"),
                      "the enlarged card must use the selected appearance material")
        XCTAssertTrue(habit.contains("appearancePreferences"),
                      "the preview must inherit the selected appearance outside the list")
        XCTAssertFalse(habit.contains(".background(Color(scheme == .dark"),
                       "the preview must not add a second hard-coded opaque surface")
    }

    func testGitHubPreviewTilesFitItsActualInnerWidth() throws {
        let github = try source("Haiity/Views/GitHubContributionCard.swift")

        XCTAssertTrue(github.contains("previewWidth - 2 * Theme.Metrics.gutter"),
                      "GitHub tiles must use the preview's real inner width")
        XCTAssertTrue(github.contains("return max(8"),
                      "the minimum tile size must remain readable in the compact preview")
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

        XCTAssertTrue(content.contains("ToolbarItemGroup(placement: .topBarLeading)"),
                      "the leading toolbar group should own filtering and sorting")
        XCTAssertTrue(content.contains("habitFilterMenu"),
                      "the leading toolbar group should keep the direct filter menu")
        XCTAssertFalse(content.contains("accessibilityIdentifier(\"habit-management\")"),
                       "the old ellipsis management button must be gone")
        XCTAssertTrue(content.contains("filter-toast"),
                      "active filters need a visible toast hint")
        XCTAssertTrue(content.contains("clear-filters"),
                      "the filter toast needs a direct reset action")
    }

    func testHabitToolbarRestoresSortingAlongsideFiltering() throws {
        let content = try source("Haiity/Views/ContentView.swift")

        XCTAssertTrue(content.contains("habitSortingActive"))
        XCTAssertTrue(content.contains("accessibilityIdentifier(\"reorder-habits\")"),
                      "sorting needs a stable toolbar action")
        XCTAssertTrue(content.contains("HabitSortingRow("))
        XCTAssertTrue(content.contains("withHabitChromeAnimation"))
        XCTAssertTrue(content.contains("accessibilityIdentifier(\"finish-reordering\")"),
                      "sorting needs a way to leave inline sort mode")
    }

    func testTodayFilterIsNotOfferedInTheMenu() throws {
        let content = try source("Haiity/Views/ContentView.swift")

        XCTAssertFalse(content.contains("accessibilityIdentifier(\"filter-today\")"))
        XCTAssertFalse(content.contains("Toggle(isOn: $habitFilter.todayOnly)"))
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
        XCTAssertTrue(menu.contains("UITargetedPreview(view: self"),
                      "the card-scoped bridge view must own the lift")
        XCTAssertTrue(menu.contains("roundedRect: bounds"),
                      "the rounded path must use the card target's local coordinates")
        XCTAssertTrue(menu.contains("parameters.shadowPath = cardPath"),
                      "UIKit should use the converted card path for the lift shadow")
    }

    func testContextPreviewConstrainsItsShadowToTheCardPath() throws {
        let menu = try source("Haiity/Views/HabitCard.swift")

        XCTAssertTrue(menu.contains("let cardPath = UIBezierPath"),
                      "the lift needs one explicit rounded card path")
        XCTAssertTrue(menu.contains("parameters.visiblePath = cardPath"),
                      "the visible lift must use the card path")
        XCTAssertTrue(menu.contains("parameters.shadowPath = cardPath"),
                      "the lift shadow must not be derived from the larger list host")
    }

    func testStatsUseDynamicTypeAndCombineRowsForVoiceOver() throws {
        let stats = try source("Haiity/Views/StatsView.swift")
        let rowStart = try XCTUnwrap(stats.range(of: "private func statsHabitRow"))
        let rowEnd = try XCTUnwrap(stats.range(of: "private func statsHabitAccessibilityValue",
                                               range: rowStart.upperBound..<stats.endIndex))
        let row = stats[rowStart.lowerBound..<rowEnd.lowerBound]

        XCTAssertFalse(stats.contains(".font(.system(size:"),
                       "large statistics values must scale with Dynamic Type")
        XCTAssertTrue(row.contains(".accessibilityElement(children: .combine)"),
                      "each habit statistics row should be one readable VoiceOver element")
        XCTAssertTrue(stats.contains("statsTodayAccessibilityValue"),
                      "the today card must expose its open count, streak, and week percent")
        XCTAssertTrue(stats.contains("statsRhythmAccessibilityValue"),
                      "the rhythm card must expose how many days are filled")
        XCTAssertTrue(stats.contains("statsWeekAccessibilityValue"),
                      "the week card must expose the seven daily percents")
        XCTAssertTrue(stats.contains("accessibilityElement(children: .ignore)"),
                      "each statistics block stays one VoiceOver element")
        XCTAssertTrue(stats.contains(".navigationChrome()"),
                      "statistics navigation must keep the selected header material")
        XCTAssertFalse(stats.contains(".background(AppearanceBackground(preferences: store.appearancePreferences))"),
                       "the statistics page must use the single page-level appearance layer")
    }

    func testStatsHabitRowCommitOpensTheHabitCard() throws {
        let stats = try source("Haiity/Views/StatsView.swift")

        // The commit decision lives in its own function, not as an `if/else`
        // inside the @ViewBuilder: a builder reads an if/else as a view branch,
        // so deciding a closure in there only compiles behind an explicit
        // `return`, which disables the builder for the whole body.
        XCTAssertTrue(stats.contains("private func statsContextHabitID(_ id: String) -> UUID?"),
                      "the habit behind a context-menu id must be derived in one place")
        XCTAssertTrue(stats.contains("id.hasPrefix(\"habit-\")"))
        XCTAssertTrue(stats.contains("private func statsContextCommit(for id: String) -> () -> Void"))
        XCTAssertTrue(stats.contains("return { openHabit(habitID) }"),
                      "a per-habit card must open that habit")
        XCTAssertTrue(stats.contains("return openStatsAdjustments"),
                      "every other menu must open the customize sheet")

        XCTAssertTrue(stats.contains("openURL(AppDestination.habit(id).url)"),
                      "a ranking row must open the existing habit card")
        XCTAssertTrue(stats.contains("commit: statsContextCommit(for: id)"))
        XCTAssertTrue(stats.contains("performsCommitOnTap: statsContextHabitID(id) != nil"),
                      "a short tap on the ranking row must run that same commit")
    }

    func testEmptyStatisticsContainsTheCreateButton() throws {
        let stats = try source("Haiity/Views/StatsView.swift")
        let start = try XCTUnwrap(stats.range(of: "private var emptyState"))
        let end = try XCTUnwrap(stats.range(of: "private var statsList",
                                            range: start.upperBound..<stats.endIndex))
        let empty = stats[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(empty.contains("add-first-habit"))
        XCTAssertTrue(empty.contains("Ersten Habit anlegen"))
        XCTAssertTrue(empty.contains("openURL(AppDestination.create.url)"),
                      "empty statistics must use the existing create route")
    }

    func testStatsAccessibilityValuesIncludeTheChartNumbers() throws {
        let stats = try source("Haiity/Views/StatsView.swift")
        let today = try functionBody(stats, "private func statsTodayAccessibilityValue")
        let rhythm = try functionBody(stats, "private func statsRhythmAccessibilityValue")
        let week = try functionBody(stats, "private func statsWeekAccessibilityValue")

        XCTAssertTrue(today.contains("offen"))
        XCTAssertTrue(today.contains("Serie"))
        XCTAssertTrue(today.contains("diese Woche"))
        XCTAssertTrue(rhythm.contains("Nur mit hAiity Pro"))
        XCTAssertTrue(rhythm.contains("letzten fünf Monaten"))
        XCTAssertTrue(rhythm.contains("level > 0"))
        XCTAssertTrue(week.contains("Self.momentumSentence(current: snapshot.week, previous: snapshot.previousWeek)"))
        XCTAssertTrue(week.contains("%"))
        XCTAssertTrue(stats.contains(".accessibilityValue(statsTodayAccessibilityValue(snapshot))"))
        XCTAssertTrue(stats.contains(".accessibilityValue(statsRhythmAccessibilityValue(snapshot))"))
        XCTAssertTrue(stats.contains(".accessibilityValue(statsWeekAccessibilityValue(snapshot))"))
    }

    private func functionBody(_ source: String, _ name: String) throws -> Substring {
        let start = try XCTUnwrap(source.range(of: name))
        let next = source.range(of: "\n    private func ", range: start.upperBound..<source.endIndex)
            ?? source.range(of: "\n    private var ", range: start.upperBound..<source.endIndex)
        let end = next?.lowerBound ?? source.endIndex
        return source[start.lowerBound..<end]
    }

    func testStatsPreviewsKeepOneSurfaceAndAFlexibleHeight() throws {
        let stats = try source("Haiity/Views/StatsView.swift")
        let previewStart = try XCTUnwrap(stats.range(of: "private func statsPreview"))
        let previewEnd = try XCTUnwrap(stats.range(of: "private func streakChip",
                                                    range: previewStart.upperBound..<stats.endIndex))
        let preview = stats[previewStart.lowerBound..<previewEnd.lowerBound]

        XCTAssertTrue(preview.contains(".frame(minHeight: height"),
                      "enlarged statistics cards must grow with their content")
        XCTAssertFalse(preview.contains(".frame(height: height"),
                       "enlarged statistics cards must not clip at a fixed height")
        XCTAssertTrue(preview.contains(".appSurface()"),
                      "the preview wrapper must provide one visible selected-material surface")
    }

    func testGitHubPreviewUsesAReadableRecentWindow() throws {
        let github = try source("Haiity/Views/GitHubContributionCard.swift")

        XCTAssertTrue(github.contains("previewGraphWeeks = 16"),
                      "the enlarged GitHub graph should show a readable recent window")
        XCTAssertTrue(github.contains("return max(8"),
                      "GitHub preview tiles should stay close to the normal graph size")
        XCTAssertTrue(github.contains("showsMonthLabels: false"),
                      "the enlarged GitHub graph should spend its height on tiles")
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
        XCTAssertTrue(filter.contains("nativeTab == .habits"),
                      "the filter hint belongs only to the Habits page")
    }

}
