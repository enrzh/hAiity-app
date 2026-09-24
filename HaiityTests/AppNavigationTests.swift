import XCTest
@testable import Haiity

final class AppNavigationTests: XCTestCase {
    func testPrimaryDeepLinksSelectTheirTabs() {
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://habits")!), .habits)
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://more")!), .more)
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://sync")!), .more)
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://stats")!), .stats)
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://archive")!), .archive)
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://search")!), .search)
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://new")!), .create)
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://cleanup")!), .cleanup)
    }

    func testHabitWidgetDeepLinksCarryTheHabitIdentifier() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let navigation = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Models/AppNavigation.swift"))
        let widgetLogic = try String(contentsOf: root.appendingPathComponent(
            "HaiityWidget/WidgetLogic.swift"))

        XCTAssertTrue(navigation.contains("URLComponents"),
                      "app navigation must parse widget query items")
        XCTAssertTrue(navigation.contains("habitID"),
                      "habit routes must carry the selected habit")
        XCTAssertTrue(widgetLogic.contains("haiity://habits?habit="),
                      "specific widgets must link to their selected habit")
    }

    func testUnknownAndForeignURLsAreIgnored() {
        XCTAssertNil(AppDestination.resolve(url: URL(string: "https://aiity.de")!))
        XCTAssertNil(AppDestination.resolve(url: URL(string: "haiity://unknown")!))
    }

    func testDestinationsSelectTheirTabs() {
        XCTAssertEqual(AppDestination.stats.selectedTab, .stats)
        XCTAssertEqual(AppDestination.archive.selectedTab, .more)
        XCTAssertEqual(AppDestination.more.selectedTab, .more)
        XCTAssertEqual(AppDestination.search.selectedTab, .search)
        XCTAssertEqual(AppDestination.create.selectedTab, .create)
    }

    func testStatsIsARealTabAndArchiveRoutesViaMoreTab() {
        XCTAssertEqual(AppDestination.stats.effect,
                       AppRouteEffect(tab: .stats, morePage: nil,
                                      opensSearch: false, opensCreate: false))
        XCTAssertEqual(AppDestination.archive.effect,
                       AppRouteEffect(tab: .more, morePage: .archive,
                                      opensSearch: false, opensCreate: false))
    }

    func testSearchAndCreateHaveExplicitEffects() {
        XCTAssertEqual(AppDestination.search.effect.tab, .search)
        XCTAssertTrue(AppDestination.search.effect.opensSearch)
        XCTAssertTrue(AppDestination.create.effect.opensCreate)
    }

    func testCleanupRouteSelectsMoreAndRunsNativeCleanup() {
        XCTAssertEqual(AppDestination.cleanup.selectedTab, .more)
        XCTAssertTrue(AppDestination.cleanup.effect.runsNativeSyncCleanup)
        XCTAssertFalse(AppDestination.cleanup.effect.opensSearch)
        XCTAssertFalse(AppDestination.cleanup.effect.opensCreate)
    }

    func testStatsSettingsUseLeadingToolbarAndContextPreview() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let stats = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/StatsView.swift"))

        XCTAssertTrue(stats.contains("ToolbarItem(placement: .topBarLeading)"),
                      "stats adjustments belong on the leading side")
        XCTAssertTrue(stats.contains("GraphContextMenu"),
                      "stats cards need the same full-width hold preview as habit graphs")
        XCTAssertTrue(stats.contains("previewWidth"),
                      "the stats preview must use the full active window width")
    }

    func testStatsSnapshotDoesNotBlockSynchronousPageConstruction() throws {
        let stats = try String(contentsOf: sourceURL("Haiity/Views/StatsView.swift"))
        let listStart = try XCTUnwrap(stats.range(of: "private var statsList"))
        let cardStart = try XCTUnwrap(stats.range(of: "private func statsTodayCard",
                                                   range: listStart.upperBound..<stats.endIndex))
        let list = stats[listStart.lowerBound..<cardStart.lowerBound]

        XCTAssertFalse(list.contains("StatsEngine.snapshot("),
                       "opening statistics must not synchronously calculate its snapshot")
        XCTAssertTrue(stats.contains(".task(id: statsRefreshKey)"),
                      "statistics should refresh through a cancellable task")
        XCTAssertTrue(stats.contains("ContributionSnapshotScheduler.perform"),
                      "statistics should use the shared cancellable snapshot scheduler")
        XCTAssertFalse(stats.contains("Task.detached"),
                       "statistics must not leave work running after the tab disappears")
        XCTAssertTrue(stats.contains("LazyVStack(spacing: 0)"),
                      "per-habit statistics should be mounted lazily")
    }

    func testContributionGraphsDeferColdSnapshotWork() throws {
        let grid = try String(contentsOf: sourceURL("Haiity/Views/ContributionGrid.swift"))
        let github = try String(contentsOf: sourceURL("Haiity/Views/GitHubContributionGraph.swift"))

        let graphSources: [(String, String)] = [
            (grid, "struct ContributionGrid: View, Equatable"),
            (github, "struct GitHubContributionGraph: View, Equatable")
        ]

        for (source, typeDeclaration) in graphSources {
            let typeStart = try XCTUnwrap(source.range(of: typeDeclaration))
            let bodyStart = try XCTUnwrap(source.range(of: "var body: some View",
                                                       range: typeStart.upperBound..<source.endIndex))
            let bodyEnd = try XCTUnwrap(
                source.range(of: "private var widthReader",
                             range: bodyStart.upperBound..<source.endIndex)
                ?? source.range(of: ".task(id: request)",
                                range: bodyStart.upperBound..<source.endIndex)
            )
            let body = source[bodyStart.lowerBound..<bodyEnd.lowerBound]
            XCTAssertFalse(body.contains("GridCalendar.snapshot("),
                           "graph body must not build its cold snapshot synchronously")
            XCTAssertTrue(source.contains(".task(id: request)"),
                          "graph snapshots should load through a cancellable task")
            XCTAssertTrue(source.contains("ContributionSnapshotScheduler.perform"),
                          "graph snapshots should use the shared cancellable scheduler")
            XCTAssertTrue(source.contains("cachedSnapshot"),
                          "warm graph snapshots should bypass the background queue")
            XCTAssertFalse(source.contains("Task.detached"),
                           "graph snapshots must not outlive the requesting view")
        }
    }

    func testGraphAndStatsUseOneSerialSnapshotScheduler() throws {
        let gridCalendar = try String(contentsOf: sourceURL("Haiity/Models/GridCalendar.swift"))
        XCTAssertTrue(gridCalendar.contains("enum ContributionSnapshotScheduler"),
                      "cold graph work needs one shared scheduler")
        XCTAssertTrue(gridCalendar.contains("DispatchQueue("),
                      "snapshot work should run off the main actor")
        XCTAssertTrue(gridCalendar.contains("label: \"com.aiity.haiity.snapshot-work\""),
                      "the scheduler should remain a single serial queue")
        XCTAssertTrue(gridCalendar.contains("withTaskCancellationHandler"),
                      "queued snapshot work must follow view-task cancellation")
    }

    func testGitHubGraphUsesStableGeometryForScrollableWindows() throws {
        let github = try String(contentsOf: sourceURL("Haiity/Views/GitHubContributionGraph.swift"))
        let habits = try String(contentsOf: sourceURL("Haiity/Views/ContributionGrid.swift"))

        XCTAssertTrue(github.contains("ContributionChart.fittedCell(viewport: viewportWidth"),
                      "the auto-sized GitHub graph must share the habit graph's fitted columns")
        XCTAssertTrue(habits.contains("ContributionChart.fittedCell(viewport: viewportWidth"),
                      "habit graphs keep the same fitted-column geometry")
        XCTAssertTrue(github.contains("onGeometryChange(for: CGFloat.self, of: { $0.size.width })"),
                      "viewport width must come from the visible frame, not scrolling content")
        XCTAssertFalse(github.contains("@State private var available: CGFloat = 0"),
                       "the scrollable GitHub graph must not feed its content width back into layout")
        XCTAssertFalse(github.contains("private var widthReader"),
                       "the scrollable GitHub graph must not measure its own unbounded content")
    }

    func testNativeTabRootsOwnOneFullFrameAppearanceSurface() throws {
        let content = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))

        XCTAssertTrue(content.contains("private func nativeTabRoot"),
                      "native tabs need one shared full-frame background root")
        XCTAssertTrue(content.contains("nativeTabContent(.stats) { statsTabContent }"))
        XCTAssertTrue(content.contains("nativeTabContent(.habits) { habitsTabContent }"))
        XCTAssertTrue(content.contains("nativeTabContent(.more) { moreTabContent }"))
        XCTAssertTrue(content.contains("nativeTabRoot { searchTabContent }"))
    }

    func testNativeRootPagesUseSharedLeadingScrollingTitles() throws {
        let content = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        let stats = try String(contentsOf: sourceURL("Haiity/Views/StatsView.swift"))
        let more = try String(contentsOf: sourceURL("Haiity/Views/MoreView.swift"))

        XCTAssertTrue(content.contains("RootPageTitle(title: String(localized: \"Habits\"),"),
                      "the habits root list needs the shared leading title")
        XCTAssertTrue(stats.contains("RootPageTitle(title: String(localized: \"Statistik\")"),
                      "the stats root list needs the shared leading title")
        XCTAssertTrue(more.contains("RootPageTitle(title: screen.title,"),
                      "the Mehr root list needs the shared leading title")
        XCTAssertTrue(content.contains(".coordinateSpace(.named(RootPageTitle.coordinateSpace))"))
        XCTAssertTrue(stats.contains(".coordinateSpace(.named(RootPageTitle.coordinateSpace))"))
        XCTAssertTrue(more.contains(".coordinateSpace(.named(RootPageTitle.coordinateSpace))"))
        let habitsStart = try XCTUnwrap(content.range(of: "private var habitsScreen"))
        let habitsEnd = try XCTUnwrap(content.range(of: "private var habitsTabSource",
                                                      range: habitsStart.upperBound..<content.endIndex))
        let habitsScreen = content[habitsStart.lowerBound..<habitsEnd.lowerBound]
        XCTAssertFalse(habitsScreen.contains(".navigationTitle(\"Habits\")"),
                       "the habits root must have one visible title owner")
        XCTAssertFalse(stats.contains(".navigationTitle(String(localized: \"Statistik\"))"),
                       "the stats root must have one visible title owner")
        XCTAssertTrue(more.contains(".navigationBarTitleDisplayMode(screen == .main ? .inline : .large)"),
                      "Mehr should use the compact root title and large secondary titles")
        XCTAssertTrue(more.contains("screen == .main ? \"\" : screen.title"),
                      "the Mehr root must hide the native title while subpages keep theirs")

        let theme = try String(contentsOf: sourceURL("Haiity/Theme.swift"))
        XCTAssertTrue(theme.contains("struct RootPageTitle: View"))
        XCTAssertTrue(theme.contains("accessibilityReduceMotion"))
        XCTAssertTrue(theme.contains("RootPageTitleProgressKey"),
                      "the shared title must report scroll progress to its compact toolbar title")

        let start = try XCTUnwrap(content.range(of: "private var moreTabContent"))
        let end = try XCTUnwrap(content.range(of: "private var fallbackMoreContent",
                                              range: start.upperBound..<content.endIndex))
        let moreTab = content[start.lowerBound..<end.lowerBound]
        XCTAssertFalse(moreTab.contains(".navigationTitle(String(localized: \"Mehr\"))"),
                       "the root Mehr title must have one owner")
    }

    func testSecondaryPagesUseSharedHeaderChrome() throws {
        let theme = try String(contentsOf: sourceURL("Haiity/Theme.swift"))
        let content = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        let backfill = try String(contentsOf: sourceURL("Haiity/Views/BackfillCard.swift"))
        let edit = try String(contentsOf: sourceURL("Haiity/Views/EditHabitSheet.swift"))
        let paywall = try String(contentsOf: sourceURL("Haiity/Views/PaywallView.swift"))
        let reminders = try String(contentsOf: sourceURL("Haiity/Views/ReminderSetupView.swift"))
        let more = try String(contentsOf: sourceURL("Haiity/Views/MoreView.swift"))

        XCTAssertTrue(theme.contains("func pageHeaderChrome()"))
        XCTAssertTrue(theme.contains("func pageHeaderChrome(visible: Bool)"))
        XCTAssertTrue(theme.contains("private struct PageHeaderChromeModifier"))
        XCTAssertTrue(content.contains(".pageHeaderChrome()"),
                      "Search should use the shared header chrome")
        XCTAssertTrue(backfill.contains(".pageHeaderChrome()"))
        XCTAssertTrue(edit.contains(".pageHeaderChrome()"))
        XCTAssertTrue(paywall.contains(".pageHeaderChrome()"))
        XCTAssertTrue(reminders.contains(".pageHeaderChrome()"))
        XCTAssertTrue(more.contains(".pageHeaderChrome(visible: screen != .main)"),
                      "the More hub must reuse the shared header without duplicating its root veil")
    }

    func testRootPagesHandOffToCenteredCompactTitles() throws {
        let content = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        let stats = try String(contentsOf: sourceURL("Haiity/Views/StatsView.swift"))
        let more = try String(contentsOf: sourceURL("Haiity/Views/MoreView.swift"))
        let theme = try String(contentsOf: sourceURL("Haiity/Theme.swift"))

        XCTAssertTrue(content.contains("rootTitleProgress"))
        XCTAssertTrue(stats.contains("rootTitleProgress"))
        XCTAssertTrue(more.contains("rootTitleProgress"))
        XCTAssertTrue(content.contains("ToolbarItem(placement: .principal)"))
        XCTAssertTrue(stats.contains("ToolbarItem(placement: .principal)"))
        XCTAssertTrue(more.contains("ToolbarItem(placement: .principal)"))
        XCTAssertTrue(theme.contains("scrollEdgeEffectStyle(.soft, for: .all)"),
                      "the native root should retain the progressive edge blur")
    }

    func testMorePageRowsDoNotShareOneInteractiveListRow() throws {
        let more = try String(contentsOf: sourceURL("Haiity/Views/MoreView.swift"))
        let start = try XCTUnwrap(more.range(of: "private var mainSettings: some View"))
        let end = try XCTUnwrap(more.range(of: "private var appearanceSettings: some View",
                                           range: start.upperBound..<more.endIndex))
        let main = more[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(main.contains("ScrollView"))
        XCTAssertTrue(main.contains("AppSettingsGroup"))
        XCTAssertTrue(main.contains("pageRow(MoreRoute.appearance"))
        XCTAssertTrue(main.contains("pageRow(MoreRoute.habitBehavior"))
        XCTAssertFalse(main.contains("defaultTimeZonePicker"),
                       "the default time zone moved to Verhalten & Teilen")
        XCTAssertFalse(main.contains("List {"),
                       "the rebuilt hub must not collapse multiple routes into one List row")
    }

    func testDefaultTimeZoneUsesTheWholeSettingsRowAsTheMenuLabel() throws {
        let more = try String(contentsOf: sourceURL("Haiity/Views/MoreView.swift"))
        let behavior = try XCTUnwrap(more.range(of: "private var habitBehaviorSettings: some View"))
        let behaviorEnd = try XCTUnwrap(more.range(of: "private var cloudSyncSection: some View",
                                                   range: behavior.upperBound..<more.endIndex))
        XCTAssertTrue(more[behavior.lowerBound..<behaviorEnd.lowerBound].contains("defaultTimeZoneGroup"),
                      "the default time zone belongs to Verhalten & Teilen")
        let start = try XCTUnwrap(more.range(of: "private var defaultTimeZonePicker: some View"))
        let end = try XCTUnwrap(more.range(of: "private var compactModeSection: some View",
                                           range: start.upperBound..<more.endIndex))
        let picker = more[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(picker.contains("Menu {"),
                      "the timezone selector should remain a native menu")
        XCTAssertTrue(picker.contains("} label: {\n            AppSettingsRow("),
                      "the entire settings row must open the timezone menu")
        XCTAssertFalse(picker.contains("symbol: \"globe\") {\n            Menu {"),
                       "the row must not be nested inside a trailing-only menu label")
    }

    func testMoreRowsKeepTheirOwnRouteAndBoundedSourceControl() throws {
        let more = try String(contentsOf: sourceURL("Haiity/Views/MoreView.swift"))
        let content = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))

        XCTAssertTrue(more.contains("Button {\n            onOpen(route)"),
                      "each More row must dispatch the route it was given")
        XCTAssertTrue(more.contains("motivationSourceControl"),
                      "the motivation source must remain selectable from the rows")
        XCTAssertTrue(more.contains("private var motivationSourceControl: some View"),
                      "the source control needs its own declaration to be a bounded target")
        XCTAssertTrue(content.contains("morePageRoute = nil"),
                      "a new More destination must not inherit a stale child route")
        XCTAssertTrue(content.contains("moreRoutePresentationTask"),
                      "replacing an open More child must wait for the old sheet to dismiss")
    }

    func testMoreChildPagesKeepIndependentViewIdentity() throws {
        let content = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))

        XCTAssertTrue(content.contains("case .appearance:"),
                      "Darstellung needs its own destination branch")
        XCTAssertTrue(content.contains("screen: .appearance"),
                      "Darstellung must not inherit Verhalten & Teilen's screen")
        XCTAssertTrue(content.contains("screen: .habitBehavior"),
                      "Verhalten & Teilen must keep its own screen")
        XCTAssertTrue(content.contains(".id(\"more-destination-\\(fallback)\")"),
                      "replaced More sheets must be mounted with route identity")
    }

    func testSettingsSurfacesUseTheSharedMaterialTint() throws {
        let theme = try String(contentsOf: sourceURL("Haiity/Theme.swift"))
        let settings = try XCTUnwrap(theme.range(of: "struct SettingsRowSurface"))
        let end = try XCTUnwrap(theme.range(of: "private struct SettingsSurfaceModifier",
                                             range: settings.upperBound..<theme.endIndex))
        let surface = theme[settings.lowerBound..<end.lowerBound]

        XCTAssertTrue(surface.contains("Theme.surfaceTint(preferences: preferences"),
                      "settings rows must use the same tint source as app surfaces")
        XCTAssertTrue(surface.contains("if #available(iOS 26, *)"),
                      "settings rows must keep the native glass and legacy paths distinct")
        XCTAssertTrue(surface.contains("Color(.systemBackground).opacity(0.16)"),
                      "legacy glass needs a readable system-background fallback")
    }

    func testAppearancePerformanceModeUsesOneSharedSolidSurfacePath() throws {
        let theme = try String(contentsOf: sourceURL("Haiity/Theme.swift"))
        let more = try String(contentsOf: sourceURL("Haiity/Views/MoreView.swift"))

        XCTAssertTrue(theme.contains("var performanceMode: Bool"))
        XCTAssertTrue(theme.contains("performanceMode"))
        XCTAssertTrue(theme.contains("preferences.performanceMode ? .solid : preferences.material"),
                      "performance mode must bypass expensive glass rendering through the shared material resolver")
        XCTAssertTrue(more.contains("performance-mode-toggle"))
    }

    func testNativeCalendarMaintenanceUsesButtonTreatment() throws {
        let more = try String(contentsOf: sourceURL("Haiity/Views/MoreView.swift"))
        let calendar = try XCTUnwrap(more.range(of: "private var calendarSection"))
        let end = try XCTUnwrap(more.range(of: "private func cleanupNativeEntries",
                                           range: calendar.upperBound..<more.endIndex))
        let section = more[calendar.lowerBound..<end.lowerBound]
        XCTAssertTrue(section.contains(".buttonStyle(.bordered)"))
    }

    func testAliasAndAppleRowsUseTheSameLeadingIconSlot() throws {
        let more = try String(contentsOf: sourceURL("Haiity/Views/MoreView.swift"))

        XCTAssertTrue(more.contains("private func personalLeadingIcon"),
                      "personal rows need one shared icon layout")
        XCTAssertTrue(more.contains("personalLeadingIcon(\"person.crop.circle\")"))
        XCTAssertTrue(more.contains("personalLeadingIcon(\"person.crop.circle.badge.checkmark\")"))
    }

    func testHabitDeepLinkRetriesAfterItsListRowsMount() throws {
        let content = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))

        XCTAssertTrue(content.contains("onChange(of: habitsTabSource.map(\\.id))"),
                      "a widget route must retry when lazy list data mounts")
        XCTAssertTrue(content.contains("Task.sleep(for: .milliseconds"),
                      "the first scroll request can arrive before the row exists")
    }

    func testStatsPreviewFramesAfterItsSurfacePadding() throws {
        let content = try String(contentsOf: sourceURL("Haiity/Views/StatsView.swift"))
        let start = try XCTUnwrap(content.range(of: "private func statsPreview<Content: View>"))
        let preview = content[start.lowerBound...]
        let framed = try XCTUnwrap(preview.range(of: "let framed = AnyView(surfaced"))
        XCTAssertTrue(framed.lowerBound >= preview.startIndex,
                      "the preview must build its final frame after choosing its content")
        XCTAssertTrue(content.contains("statsPreview(statsMetric(card, snapshot: snapshot),"),
                      "metric previews must use their own content in the shared surface")
        XCTAssertTrue(content.contains("statsPreview(statsRhythmContent(snapshot),"),
                      "rhythm previews must use their own content in the shared surface")
        XCTAssertTrue(preview.contains("height: CGFloat"),
                      "stats previews need a stable height for UIContextMenu")
        XCTAssertTrue(preview.contains(".appSurface()"),
                      "the preview must own exactly one appearance surface")
        XCTAssertTrue(preview.contains(".frame(width: statsPreviewWidth,"),
                      "the preview frame must constrain both axes")
    }

    func testGraphContextMenuUsesAnExplicitStablePreviewFrame() throws {
        let habitCard = try String(contentsOf: sourceURL("Haiity/Views/HabitCard.swift"))
        let githubCard = try String(contentsOf: sourceURL("Haiity/Views/GitHubContributionCard.swift"))

        XCTAssertTrue(habitCard.contains("let previewHeight: CGFloat"),
                      "graph context menus need an explicit height")
        XCTAssertTrue(habitCard.contains("controller.view.frame = CGRect"),
                      "the hosting view must receive the same stable frame as the menu")
        XCTAssertTrue(habitCard.contains("controller.preferredContentSize = size"),
                      "UIKit must be told the final preview size")
        XCTAssertTrue(githubCard.contains("previewHeight:"),
                      "the GitHub graph must opt into the stable preview height")
        XCTAssertTrue(habitCard.contains("contextPreviewHeight: CGFloat = 160"),
                      "the enlarged habit graph must use a compact stable fallback height")
    }

    func testGraphContextMenuRejectsUnboundedUIKitProposals() throws {
        let habitCard = try String(contentsOf: sourceURL("Haiity/Views/HabitCard.swift"))

        XCTAssertTrue(habitCard.contains("func sizeThatFits(_ proposal: ProposedViewSize"),
                      "the UIKit bridge must answer SwiftUI's unbounded size proposals")
        XCTAssertTrue(habitCard.contains("value.isFinite && value > 0"),
                      "the bridge must reject NaN, infinity, and zero dimensions")
        XCTAssertTrue(habitCard.contains("override var frame: CGRect"),
                      "the UIKit host must clamp invalid frames that bypass SwiftUI sizing")
        XCTAssertTrue(habitCard.contains(".frame(maxWidth: previewWidth)"),
                      "habit overlays must cap the UIKit host to a finite width")
        XCTAssertTrue(habitCard.contains("measuredHeight.isFinite && measuredHeight > 0"),
                      "context previews must not turn a non-finite measurement into a frame")
    }

    func testMonthlyAndYearlyEditorUsesDateAndOptionalMultipleDaysOnly() throws {
        let editor = try String(contentsOf: sourceURL("Haiity/Views/EditHabitSheet.swift"))

        XCTAssertTrue(editor.contains("Mehrere Tage"))
        XCTAssertTrue(editor.contains("multipleDaysEnabled"))
        XCTAssertTrue(editor.contains("multipleDays"))
        XCTAssertTrue(editor.contains("multiple-date-list"),
                      "Mehrere Tage should be presented as an editable list")
        XCTAssertTrue(editor.contains("multiple-date-add"),
                      "Mehrere Tage needs an add action")
        XCTAssertFalse(editor.contains("monthly-rule-picker"))
        XCTAssertFalse(editor.contains("Tag im Monat"))
        XCTAssertFalse(editor.contains("Letzter Tag"))
        XCTAssertFalse(editor.contains("month-nth"))
        XCTAssertFalse(editor.contains("month-weekday"))
        XCTAssertTrue(editor.contains("if draft.showsIntervalStepper"),
                      "the interval stepper must be limited to daily and weekly recurrence")
    }

    func testAppleAccountActionSitsBesideIdentity() throws {
        let more = try String(contentsOf: sourceURL("Haiity/Views/MoreView.swift"))
        let start = try XCTUnwrap(more.range(of: "private var personalSection: some View"))
        let end = try XCTUnwrap(more.range(of: "private var appleSignInButton",
                                           range: start.upperBound..<more.endIndex))
        let section = more[start.lowerBound..<end.lowerBound]
        let account = try XCTUnwrap(section.range(of: "if let storedAppleUserID"))
        let accountBlock = section[account.lowerBound...]

        XCTAssertTrue(accountBlock.contains("HStack(spacing: Theme.Metrics.gap)"),
                      "the account identity and sign-out action should share a row")
    }

    func testNativePagesUseTheAppearanceBackgroundAtTheirVisibleRoots() throws {
        let content = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        let nativeRoot = try XCTUnwrap(content.range(of: "private func nativePageRoot"))
        let nextFunction = content.range(of: "private var nativeToastOverlay",
                                         range: nativeRoot.upperBound..<content.endIndex)
        let rootBody = content[nativeRoot.lowerBound..<(nextFunction?.lowerBound ?? content.endIndex)]
        XCTAssertTrue(rootBody.contains("AppearanceBackground(preferences: store.appearancePreferences)"),
                      "the shared background must be inside each native NavigationStack page")
        XCTAssertTrue(content.contains("nativePageRoot {\n                StatsView"),
                      "the stats page must mount the page-level background")
        XCTAssertTrue(content.contains("nativePageRoot { habitsScreen }"),
                      "the habits page must mount the page-level background")
        XCTAssertTrue(content.contains("nativePageRoot {\n                MoreView"),
                      "the more page must mount the page-level background")

        let start = try XCTUnwrap(content.range(of: "private var searchList"))
        let end = try XCTUnwrap(content.range(of: "/// Der Inhalt des Habits-Tabs",
                                              range: start.upperBound..<content.endIndex))
        let searchList = content[start.lowerBound..<end.lowerBound]
        XCTAssertFalse(searchList.contains("AppearanceBackground(preferences: store.appearancePreferences)"),
                       "the search list must not mount a second image layer")
    }

    func testHabitsListUsesTheAppearanceBackgroundAtItsVisibleSurface() throws {
        let content = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        let start = try XCTUnwrap(content.range(of: "private var habitList: some View"))
        let end = try XCTUnwrap(content.range(of: "/// Fußabdruck des Chroms",
                                              range: start.upperBound..<content.endIndex))
        let habitList = content[start.lowerBound..<end.lowerBound]

        XCTAssertFalse(habitList.contains(".background(AppearanceBackground"),
                       "the native list must use the single page-level appearance layer")
    }

    func testMoreRouteWinsOverQueuedSearchWork() {
        var work = RouteWork()
        let searchRoute = work.begin()
        let moreRoute = work.begin()

        // The queued `haiity://search` callback must not apply after
        // `haiity://more` has become the current route.
        XCTAssertFalse(work.isCurrent(searchRoute))
        XCTAssertTrue(work.isCurrent(moreRoute))
    }

    func testNonCreateRoutesDismissOrWaitForCreateCoverLifecycle() {
        let destinations: [AppDestination] = [.habits, .more, .stats, .archive, .search]

        for destination in destinations {
            var work = RouteWork()
            let route = work.begin(destination.effect)

            XCTAssertEqual(work.nextStep(for: route,
                                         presentation: .init(create: .presented)),
                           .dismissCreate,
                           "\(destination) must dismiss create first")
            XCTAssertEqual(work.nextStep(for: route,
                                         presentation: .init(create: .dismissing)),
                           .waitForCreateDismissal,
                           "\(destination) must wait for create onDismiss")
        }

        var work = RouteWork()
        let createRoute = work.begin(AppDestination.create.effect)
        XCTAssertEqual(work.nextStep(for: createRoute,
                                     presentation: .init(create: .presented)),
                       .apply)
    }

    func testRapidCreateToSearchCancelsBeforeContentPresentation() {
        var work = RouteWork()
        let cover = CreateCoverPresentation()
        _ = work.begin(AppDestination.create.effect)
        let search = work.begin(AppDestination.search.effect)

        XCTAssertEqual(work.nextStep(for: search,
                                     presentation: .init(create: cover.phase(requested: true))),
                       .dismissCreate)
        XCTAssertFalse(cover.dismissalIsOwed)
        XCTAssertEqual(work.nextStep(for: search,
                                     presentation: .init(create: cover.phase(requested: false))),
                       .apply)
    }

    func testRapidCreateToStatsCancelsBeforeContentPresentation() {
        var work = RouteWork()
        let cover = CreateCoverPresentation()
        _ = work.begin(AppDestination.create.effect)
        let stats = work.begin(AppDestination.stats.effect)

        XCTAssertEqual(work.nextStep(for: stats,
                                     presentation: .init(create: cover.phase(requested: true))),
                       .dismissCreate)
        XCTAssertFalse(cover.dismissalIsOwed)
        XCTAssertEqual(work.nextStep(for: stats,
                                     presentation: .init(create: cover.phase(requested: false))),
                       .apply)
    }

    func testLatestRouteWinsDuringRequestedCreateCancellation() {
        var work = RouteWork()
        let cover = CreateCoverPresentation()
        _ = work.begin(AppDestination.create.effect)
        let search = work.begin(AppDestination.search.effect)
        let stats = work.begin(AppDestination.stats.effect)

        XCTAssertNil(work.nextStep(for: search,
                                   presentation: .init(create: cover.phase(requested: false))))
        XCTAssertEqual(work.nextStep(for: stats,
                                     presentation: .init(create: cover.phase(requested: false))),
                       .apply)
    }

    /// Das Kaufblatt ist die oberste Präsentation und wird von KEINER Route
    /// gewollt. Bleibt es stehen, wechselt der Bereich darunter und der
    /// Nutzer sitzt auf einer Kaufseite fest, die zu seinem Tipp nicht mehr
    /// gehört (im Simulator reproduziert: `haiity://new` → Kaufblatt,
    /// danach `haiity://stats` → Blatt blieb).
    func testEveryRouteDismissesAnOpenPaywallFirst() {
        let destinations: [AppDestination] = [.habits, .more, .stats, .archive,
                                              .search, .create]

        for destination in destinations {
            var work = RouteWork()
            let route = work.begin(destination.effect)

            XCTAssertEqual(work.nextStep(for: route,
                                         presentation: .init(paywall: .presented)),
                           .dismissPaywall,
                           "\(destination) must dismiss the paywall first")
            XCTAssertEqual(work.nextStep(for: route,
                                         presentation: .init(paywall: .dismissing)),
                           .waitForPaywallDismissal,
                           "\(destination) must wait for the paywall onDismiss")
            // Ist es weg, geht die Route ihren gewohnten Weg weiter.
            XCTAssertEqual(work.nextStep(for: route, presentation: .init()), .apply)
        }
    }

    /// Das Kaufblatt gewinnt gegen das Anlege-Cover UND gegen die
    /// Mehr-Seite: es liegt über beiden.
    func testPaywallIsDismissedBeforeCoverAndMoreSheet() {
        var work = RouteWork()
        let route = work.begin(AppDestination.stats.effect)

        XCTAssertEqual(work.nextStep(for: route,
                                     presentation: .init(create: .presented,
                                                         paywall: .presented,
                                                         more: .presented,
                                                         morePage: .archive)),
                       .dismissPaywall)
    }

    func testPaywallSheetIsWiredIntoTheRouteStateMachine() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("onDismiss: deliverPendingPaywallDismissalRoute"))
        XCTAssertTrue(source.contains(".onAppear { paywallDidPresent(context) }"))
        XCTAssertTrue(source.contains("let waitsForOnDismiss = paywallIsPresented"))
        // Die Bereiche mit EIGENEM Kaufblatt räumen es am Routen-Zähler weg.
        XCTAssertTrue(source.contains("routeToken &+= 1"))
        for host in ["Haiity/Views/MoreView.swift", "Haiity/Views/StatsView.swift"] {
            let text = try String(contentsOf: sourceURL(host))
            XCTAssertTrue(text.contains(".onChange(of: routeToken)"), host)
        }
    }

    func testCreateCoverSeparatesRequestFromActualPresentation() {
        var cover = CreateCoverPresentation()

        XCTAssertEqual(cover.phase(requested: true), .requested)
        XCTAssertFalse(cover.dismissalIsOwed)

        cover.didPresent()
        XCTAssertEqual(cover.phase(requested: true), .presented)
        XCTAssertEqual(cover.phase(requested: false), .dismissing)
        XCTAssertTrue(cover.dismissalIsOwed)

        cover.didDismiss()
        XCTAssertEqual(cover.phase(requested: false), .absent)
        XCTAssertFalse(cover.dismissalIsOwed)
    }

    func testArchiveRouteDismissesForeignSheetThenAppliesAfterOnDismiss() {
        var work = RouteWork()
        let archive = work.begin(AppDestination.archive.effect)

        // Ein fremdes Blatt (z. B. "Ueber", morePage nil) muss erst weichen.
        XCTAssertEqual(work.nextStep(for: archive,
                                     presentation: .init(more: .presented,
                                                         morePage: nil)),
                       .dismissMore)
        XCTAssertEqual(work.nextStep(for: archive,
                                     presentation: .init(more: .dismissing)),
                       .waitForMoreDismissal)
        XCTAssertEqual(work.nextStep(for: archive, presentation: .init()), .apply)
    }

    func testRoutesLeavingMoreDismissPresentedSheetOnBothHosts() {
        let destinations: [AppDestination] = [.create, .search, .habits]

        for destination in destinations {
            var work = RouteWork()
            let route = work.begin(destination.effect)

            // RoutePresentation is deliberately platform-neutral: the same
            // transition governs fallback moreSheet and native morePageRoute.
            XCTAssertEqual(work.nextStep(for: route,
                                         presentation: .init(more: .presented,
                                                             morePage: .archive)),
                           .dismissMore,
                           "\(destination) must depart More through onDismiss")
        }
    }

    func testAlreadyPresentedMoreDestinationDoesNotDismissOrRepresent() {
        for destination in [AppDestination.archive] {
            var work = RouteWork()
            let route = work.begin(destination.effect)

            XCTAssertEqual(work.nextStep(for: route,
                                         presentation: .init(more: .presented,
                                                             morePage: destination.effect.morePage)),
                           .keepCurrentMorePage)
        }
    }

    func testLatestRouteWinsOverStaleDismissalCallbacks() {
        var work = RouteWork()
        let stats = work.begin(AppDestination.stats.effect)
        let habits = work.begin(AppDestination.habits.effect)

        XCTAssertNil(work.nextStep(for: stats, presentation: .init()))
        XCTAssertEqual(work.nextStep(for: habits, presentation: .init()), .apply)
    }

    func testFallbackTabLayersExposeOnlyTheSelectedMountedTree() {
        let habits = AppTabLayerState(tab: .habits, selectedTab: .habits)
        let hiddenMore = AppTabLayerState(tab: .more, selectedTab: .habits)

        XCTAssertEqual(habits, .init(opacity: 1, allowsHitTesting: true,
                                    accessibilityHidden: false, zIndex: 1))
        XCTAssertEqual(hiddenMore, .init(opacity: 0, allowsHitTesting: false,
                                        accessibilityHidden: true, zIndex: 0))
        XCTAssertEqual(AppTabLayerState(tab: .habits, selectedTab: .more), hiddenMore)
        XCTAssertEqual(AppTabLayerState(tab: .more, selectedTab: .more), habits)
    }

    func testContentViewDeclaresAllFourTabs() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("value: AppTab.stats"))
        XCTAssertTrue(source.contains("value: AppTab.habits"))
        XCTAssertTrue(source.contains("value: AppTab.more"))
        XCTAssertTrue(source.contains("value: AppTab.search, role: .search"))
        XCTAssertTrue(source.contains("value: AppTab.search, role: .prominent"))
        XCTAssertFalse(source.contains("enum NativeTab"))
    }

    func testFallbackKeepsBothDestinationTreesMounted() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("fallbackTabLayer(.stats) { fallbackStatsContent }"))
        XCTAssertTrue(source.contains("fallbackTabLayer(.habits) { habitsStack }"))
        XCTAssertTrue(source.contains("fallbackTabLayer(.more) { fallbackMoreContent }"))
        XCTAssertFalse(source.contains("if nativeTab == .more {"))
        XCTAssertTrue(source.contains(".opacity(state.opacity)"))
        XCTAssertTrue(source.contains(".allowsHitTesting(state.allowsHitTesting)"))
        XCTAssertTrue(source.contains(".accessibilityHidden(state.accessibilityHidden)"))
    }

    func testBothMoreSheetHostsDeliverPendingRouteFromOnDismiss() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertEqual(source.components(separatedBy:
            "onDismiss: deliverPendingMoreDismissalRoute").count - 1, 2)
        XCTAssertEqual(source.components(separatedBy:
            ".onAppear { moreSheetDidPresent(route) }").count - 1, 2)
        XCTAssertTrue(source.contains("moreSheetIsPresented"))
        XCTAssertTrue(source.contains("pendingRoute"))
    }

    func testMoreRouteCanReplaceARequestedButNotPresentedSheet() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("let waitsForOnDismiss = moreSheetIsPresented"))
        XCTAssertTrue(source.contains("if !waitsForOnDismiss"))
        XCTAssertTrue(source.contains("advance(route)"))
    }

    func testCreateRouteCanReplaceARequestedButNotPresentedCover() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("createPage.onAppear { createCoverDidPresent() }"))
        XCTAssertTrue(source.contains("guard showAdd else { return }"))
        XCTAssertTrue(source.contains("let waitsForOnDismiss = createCover.dismissalIsOwed"))
        XCTAssertTrue(source.contains("if !waitsForOnDismiss { advance(route) }"))
        XCTAssertTrue(source.contains("createCover.phase(requested: showAdd)"))
        XCTAssertFalse(source.contains("searchFlow"),
                       "the search tab must not be coupled to create-cover presentation")
        XCTAssertFalse(source.contains("if open { createCoverIsPresented = true }"))
    }

    func testCreateAccessibilityContractIsSharedAcrossCustomControls() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("static let label = String(localized: \"Neuer Habit\")"))
        XCTAssertTrue(source.contains("static let identifier = \"create-habit\""))
        XCTAssertGreaterThanOrEqual(source.components(separatedBy:
            ".accessibilityLabel(CreateAccessibility.label)").count - 1, 2)
        XCTAssertGreaterThanOrEqual(source.components(separatedBy:
            ".accessibilityIdentifier(CreateAccessibility.identifier)").count - 1, 2)
        XCTAssertTrue(source.contains("private var createToolbarItem: some ToolbarContent"))
    }

    func testContentViewExposesExplicitSortingMode() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("habitSortingActive"))
        XCTAssertTrue(source.contains("HabitSortingSession("))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"reorder-habits\")"))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"finish-reordering\")"))
    }

    func testMainMorePageExposesGitHubConnectionAndLogout() throws {
        let more = try String(contentsOf: sourceURL("Haiity/Views/MoreView.swift"))
        let content = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        let aboutStart = try XCTUnwrap(more.range(of: "struct AboutView: View"))
        let about = more[aboutStart.lowerBound...]

        XCTAssertTrue(more.contains("let github: GitHubContributionStore"))
        XCTAssertTrue(more.contains("private var githubSection: some View"))
        XCTAssertTrue(more.contains("accessibilityIdentifier(\"open-github-settings\")"))
        XCTAssertTrue(more.contains("accessibilityIdentifier(\"disconnect-github\")"))
        XCTAssertGreaterThanOrEqual(content.components(separatedBy: "github: github").count - 1, 4)
        XCTAssertFalse(about.contains("NavigationLink(value: MoreRoute.github)"))
    }

    func testHabitToolbarKeepsManagementDestinationsReachable() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("habitFilterMenu"))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"habit-filter\")"))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"filter-toast\")"))
        // Statistik ist ein eigener Tab; Archive is now inside the filter menu.
        XCTAssertFalse(source.contains("accessibilityIdentifier(\"open-stats\")"))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"open-archive\")"))
        XCTAssertTrue(source.contains("String(localized: \"Filter\")"))
        for label in ["Erledigt", "Nicht erledigt", "Erinnerung", "Habit"] {
            XCTAssertTrue(source.contains("String(localized: \"\(label)\")"), label)
        }
    }

    func testArchiveIsNotListedOnTheMorePage() throws {
        let more = try String(contentsOf: sourceURL("Haiity/Views/MoreView.swift"))
        let main = try XCTUnwrap(more.range(of: "private var mainSettings: some View"))
        let tail = more[main.lowerBound...]
        XCTAssertFalse(tail.contains("pageRow(MoreRoute.archive"))
    }

    func testSearchIsARealTabWithItsOwnSearchable() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("value: AppTab.search, role: .search"))
        XCTAssertTrue(source.contains("value: AppTab.search, role: .prominent"))
        XCTAssertTrue(source.contains("private var searchTabContent: some View"))
        XCTAssertTrue(source.contains(".searchable(text: $search"))
        XCTAssertTrue(source.contains("role: .search"))
        XCTAssertTrue(source.contains("TabView(selection: $nativeTab)"))
        XCTAssertTrue(source.contains("placement: .navigationBarDrawer(displayMode: .always)"),
                      "the search field must stay visible and collapse natively while scrolling")
        XCTAssertFalse(source.contains("nativeTabSelection"))
        XCTAssertFalse(source.contains("searchPresentationTask"))
        XCTAssertFalse(source.contains("SearchFieldWatcher"))
    }

    func testSelectingSearchTabDoesNotUseAKeyboardBridge() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        let tabChange = try XCTUnwrap(source.range(of: ".onChange(of: nativeTab)"))
        let handlerEnd = try XCTUnwrap(source.range(of: "\n    }\n\n    // MARK: – Bereiche",
                                                    range: tabChange.upperBound..<source.endIndex))
        let tabBody = source[tabChange.lowerBound..<handlerEnd.lowerBound]

        XCTAssertTrue(tabBody.contains("searchFieldFocused = false"))
        XCTAssertFalse(tabBody.contains("openSearch("))
        XCTAssertTrue(source.contains(".searchFocused($searchFieldFocused)"),
                      "the dedicated search page must own keyboard focus")
    }

    func testSearchableIsScopedToTheSearchTab() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        let nativeStart = try XCTUnwrap(source.range(of: "private var nativeShell"))
        let searchStart = try XCTUnwrap(source.range(of: "private var searchTabContent",
                                                      range: nativeStart.upperBound..<source.endIndex))
        let nativeShell = source[nativeStart.lowerBound..<searchStart.lowerBound]
        XCTAssertFalse(nativeShell.contains(".searchable(text: $search"),
                       "the root TabView must not expose a search bar on every page")

        let searchEnd = try XCTUnwrap(source.range(of: "private var searchList",
                                                   range: searchStart.upperBound..<source.endIndex))
        let searchTab = source[searchStart.lowerBound..<searchEnd.lowerBound]
        XCTAssertTrue(searchTab.contains(".searchable(text: $search"),
                      "the search bar must belong to the dedicated search page")
        XCTAssertTrue(searchTab.contains("displayMode: .always"))
        XCTAssertFalse(searchTab.contains("isPresented:"))
        XCTAssertTrue(searchTab.contains(".searchFocused($searchFieldFocused)"))
    }

    func testNativeShellKeepsSearchRoleCompatibleWithCloudToolchains() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("role: .prominent"))
        XCTAssertTrue(source.contains("#if compiler(>=6.4)"))
        XCTAssertTrue(source.contains("value: AppTab.search, role: .search"))
        XCTAssertTrue(source.contains("private var splitShell"))
        XCTAssertTrue(source.contains("private var nativeShell: some View"))
    }

    private func sourceURL(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }
}
