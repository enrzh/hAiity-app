import XCTest
import SwiftUI
import UIKit
@testable import Haiity

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
        XCTAssertTrue(habit.contains("showsMonthLabels: !preview && showsMonthLabels"),
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

    @MainActor
    func testHabitPreviewFitsItsOwnWindowWidth() {
        for width in [CGFloat(320), 375, 402, 440, 760] {
            let preview = HabitCard.previewMetrics(windowWidth: width)
            XCTAssertLessThanOrEqual(preview.width, width)
            let innerWidth = preview.width - 2 * Theme.Metrics.gutter
            let band = ContributionChart.bandMetrics(width: innerWidth, gap: 2)
            XCTAssertGreaterThanOrEqual(band.cell, 12)
            XCTAssertEqual(CGFloat(band.weeks) * band.cell + CGFloat(band.weeks - 1) * 2,
                           innerWidth, accuracy: 0.001)
        }
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

    @MainActor
    func testWeeklyResultGrowsAtAX5WithoutHorizontalOverflowAcrossStyles() {
        let suite = "stats-style-layout-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HabitStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("stats-style-layout-\(UUID()).json"), loadFromDisk: false)
        let view = StatsView(store: store, viewPreferences: ViewPreferencesStore(defaults: defaults))
        let snapshot = StatsEngine.snapshot(habits: [], today: "2026-10-07")
        for style in AppDesignStyle.allCases {
            var preferences = AppearancePreferences()
            preferences.designStyle = style
            let normal = UIHostingController(rootView: view.statsWeekCard(snapshot)
                .environment(\.appearancePreferences, preferences).environment(\.dynamicTypeSize, .large))
            let accessible = UIHostingController(rootView: view.statsWeekCard(snapshot)
                .environment(\.appearancePreferences, preferences).environment(\.dynamicTypeSize, .accessibility5))
            let proposal = CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
            let size = accessible.sizeThatFits(in: proposal)
            XCTAssertLessThanOrEqual(size.width, 320)
            XCTAssertGreaterThan(size.height, normal.sizeThatFits(in: proposal).height)
        }
    }

    @MainActor
    func testProgressDetailsAndHistoryUseIndependentUUIDCallbacksWithoutChangingPreferences() {
        let suite = "stats-route-callbacks-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ViewPreferencesStore(defaults: defaults)
        preferences.update { $0.statsCards = StatsCardPrefs(active: [], customized: true) }
        let before = preferences.statsCards
        let store = HabitStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("stats-route-callbacks-\(UUID()).json"), loadFromDisk: false)
        var detailIDs: [UUID] = [], historyIDs: [UUID] = []
        let view = StatsView(store: store, viewPreferences: preferences,
            onOpenHabit: { detailIDs.append($0) }, onOpenHistory: { historyIDs.append($0) })
        let first = UUID(), second = UUID()
        view.openHabit(first)
        XCTAssertEqual(detailIDs, [first])
        XCTAssertTrue(historyIDs.isEmpty)
        view.openHistory(second)
        XCTAssertEqual(detailIDs, [first])
        XCTAssertEqual(historyIDs, [second])
        XCTAssertEqual(preferences.statsCards, before)
        XCTAssertTrue(store.habits.isEmpty)
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

    @MainActor
    func testSelectedProgressMetricsRetainCountsAndNeverInventAnEmptyDenominator() throws {
        var snapshot = StatsEngine.snapshot(habits: [], today: "2026-10-07")
        let path = try XCTUnwrap(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: path))
        let locale = Locale(identifier: "en")
        XCTAssertEqual(StatsView.statsMetricValue(.todayRing, snapshot: snapshot, bundle: bundle, locale: locale),
                       "No habit due")
        XCTAssertEqual(StatsView.weekCompletionSummary(snapshot.week, bundle: bundle, locale: locale),
                       "Nothing due this week")
        snapshot.todayDone = 2
        snapshot.todayTotal = 3
        snapshot.totalCheckIns = 42
        snapshot.week = .init(done: 7, total: 9)
        XCTAssertEqual(StatsView.statsMetricValue(.todayRing, snapshot: snapshot), "2/3")
        XCTAssertEqual(StatsView.statsMetricValue(.totals, snapshot: snapshot), "42")
        XCTAssertEqual(StatsView.weekCompletionSummary(snapshot.week, bundle: bundle, locale: locale),
                       "7 of 9 completed · 78 %")
        XCTAssertEqual(StatsView.statsMetricValue(.weekMomentum, snapshot: snapshot, bundle: bundle, locale: locale),
                       "In the weekly summary")
        XCTAssertEqual(StatsEngine.pulseWeeks, 20)
        XCTAssertEqual(snapshot.mergedLevels.count, 20)
    }


    @MainActor
    func testNativePreviewHostClampsInvalidFramesAndDetachesItsInteraction() throws {
        var visibility: [Bool] = []
        let host = GraphContextMenu.MenuHost(cardRadius: 16, previewWidth: 320, previewHeight: 104,
            previewOwnsSurface: true, previewAccessibilityIdentifier: "stats-preview",
            preview: { AnyView(Text("Preview")) }, actions: [], commit: {},
            palettes: PaletteBook(), appearancePreferences: AppearancePreferences(),
            onMenuVisibilityChanged: { visibility.append($0) })
        host.frame = CGRect(x: CGFloat.nan, y: CGFloat.infinity,
                            width: CGFloat.infinity, height: CGFloat.nan)
        XCTAssertEqual(host.frame, CGRect(x: 0, y: 0, width: 320, height: 104))
        XCTAssertEqual(host.interactions.filter { $0 is UIContextMenuInteraction }.count, 1)
        let interaction = try XCTUnwrap(host.interactions.compactMap { $0 as? UIContextMenuInteraction }.first)
        XCTAssertTrue(interaction.delegate === host)
        XCTAssertTrue(interaction.view === host)
        let unrelated = UIPointerInteraction(delegate: nil)
        host.addInteraction(unrelated)
        XCTAssertNotNil(host.contextMenuInteraction(interaction,
            configurationForMenuAtLocation: CGPoint(x: 16, y: 16)))
        XCTAssertEqual(visibility, [true])
        GraphContextMenu.dismantleUIView(host, coordinator: ())
        XCTAssertFalse(host.interactions.contains { $0 === interaction })
        XCTAssertNil(interaction.view)
        XCTAssertTrue(host.interactions.contains { $0 === unrelated },
                      "dismantling the context menu must preserve other interactions")
        XCTAssertEqual(visibility, [true, false])
        host.detach()
        XCTAssertFalse(host.interactions.contains { $0 === interaction })
        XCTAssertTrue(host.interactions.contains { $0 === unrelated })
        XCTAssertEqual(visibility, [true, false], "repeated detach must not publish another dismissal")
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
