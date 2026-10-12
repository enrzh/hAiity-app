import XCTest
import SwiftUI
import UIKit
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
        let widgetLogic = try String(contentsOf: root.appendingPathComponent(
            "HaiityWidget/WidgetLogic.swift"))
        let id = UUID()
        let destination = AppDestination.habit(id)
        XCTAssertEqual(AppDestination.resolve(url: destination.url), destination)
        XCTAssertEqual(destination.effect.habitID, id)
        XCTAssertEqual(destination.effect.tab, .habits)
        XCTAssertTrue(widgetLogic.contains("haiity://habits?habit="),
                      "specific widgets must link to their selected habit")
    }

    func testUnknownAndForeignURLsAreIgnored() {
        XCTAssertNil(AppDestination.resolve(url: URL(string: "https://aiity.de")!))
        XCTAssertNil(AppDestination.resolve(url: URL(string: "haiity://unknown")!))
        for host in ["settings", "notifications", "personalization", "localModel", "dataTransfer",
                     "about", "developer", "appearance", "habitBehavior", "github", "calendar"] {
            XCTAssertNil(AppDestination.resolve(url: URL(string: "haiity://\(host)")!), host)
        }
    }

    func testDestinationsSelectTheirTabs() {
        XCTAssertEqual(AppDestination.stats.selectedTab, .stats)
        XCTAssertEqual(AppDestination.archive.selectedTab, .today)
        XCTAssertEqual(AppDestination.more.selectedTab, .today)
        XCTAssertEqual(AppDestination.cleanup.selectedTab, .today)
        XCTAssertEqual(AppDestination.search.selectedTab, .search)
        XCTAssertEqual(AppDestination.create.selectedTab, .create)
    }

    func testProgressIsAContentTabAndLegacySettingsRoutesUseToday() {
        XCTAssertEqual(AppDestination.stats.effect,
                       AppRouteEffect(tab: .stats, morePage: nil,
                                      opensSearch: false, opensCreate: false))
        XCTAssertEqual(AppDestination.archive.effect,
                       AppRouteEffect(tab: .today, morePage: .archive,
                                      opensSearch: false, opensCreate: false))
        XCTAssertEqual(AppDestination.more.effect,
                       AppRouteEffect(tab: .today, morePage: .settings,
                                      opensSearch: false, opensCreate: false))
    }

    func testSearchAndCreateHaveExplicitEffects() {
        XCTAssertEqual(AppDestination.search.effect.tab, .search)
        XCTAssertTrue(AppDestination.search.effect.opensSearch)
        XCTAssertTrue(AppDestination.create.effect.opensCreate)
        XCTAssertEqual(AppDestination.create.effect.tab, .today)
    }

    func testCleanupRouteOpensSettingsOnTodayAndRunsOnlyExplicitCleanup() {
        XCTAssertEqual(AppDestination.cleanup.effect,
                       AppRouteEffect(tab: .today, morePage: .settings,
                                      opensSearch: false, opensCreate: false,
                                      runsNativeSyncCleanup: true))
        XCTAssertFalse(AppDestination.more.effect.runsNativeSyncCleanup)
        XCTAssertFalse(AppDestination.archive.effect.runsNativeSyncCleanup)
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

    func testCancelledSnapshotRequestDoesNotComputeOrPublish() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await ContributionSnapshotScheduler.perform {
                XCTFail("An already cancelled page must not calculate a snapshot")
                return 42
            }
        }
        let value = await task.value
        XCTAssertNil(value)
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

    /// A tab that has been visited is not thrown away again.
    ///
    /// Building only the selected tab is deliberate — three pages of cards and
    /// grids are too much for the first frame. But `if nativeTab == tab` also
    /// DESTROYS the tabs you are not looking at, and with them their @State.
    /// That is what made the Statistik page flash on every visit: the stats
    /// snapshot starts nil again, the loading placeholder goes up, and the real
    /// page pops in over it.
    func testAVisitedTabKeepsItsContentInTheTree() throws {
        let content = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))

        XCTAssertTrue(content.contains("if nativeTab == tab || builtTabs.contains(tab)"),
                      "a tab that has been opened must stay built, or its @State is lost on every visit")
        XCTAssertFalse(content.contains("if nativeTab == tab { content() }"),
                       "the selected-only guard is what destroys a visited tab's state")
        // The startup win this guard was added for has to survive: only the
        // starting tab is built before anyone has tapped anything.
        let initialTab = try NSRegularExpression(pattern: #"@State\s+(?:private\s+)?var\s+\w+:\s*AppTab\s*=\s*\.today"#)
        XCTAssertEqual(initialTab.numberOfMatches(in: content, range: NSRange(content.startIndex..., in: content)), 1)
        let initialTrees = try NSRegularExpression(pattern: #"Set<AppTab>\s*=\s*\[\.today\]"#)
        XCTAssertEqual(initialTrees.numberOfMatches(in: content, range: NSRange(content.startIndex..., in: content)), 1,
                       "normal launch builds Today, while explicit routes may select another tab")
        XCTAssertTrue(content.contains("builtTabs.insert(tab)"),
                      "opening a tab has to latch it as built")
    }

    /// Child pages push in one settings sheet; current-page bookkeeping is
    /// separate from the external URL whitelist.
    func testSettingsHubRoutesPushWithinItsSingleSheetStack() throws {
        let content = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        let more = try String(contentsOf: sourceURL("Haiity/Views/MoreView.swift"))
        let behavior = try String(contentsOf: sourceURL("Haiity/Views/MoreBehavior.swift"))
        XCTAssertEqual(content.components(separatedBy: ".sheet(item: $moreSheet,").count - 1, 1)
        XCTAssertEqual(content.components(separatedBy: "NavigationStack(path: $moreSheetPath)").count - 1, 1)
        XCTAssertEqual(content.components(separatedBy: ".navigationDestination(for: MoreRoute.self").count - 1, 1)
        for route in ["notifications", "personalization", "appearance", "habitBehavior", "calendar", "github", "dataTransfer", "archive", "about"] {
            XCTAssertTrue(more.contains("onOpen(.\(route))"), route)
        }
        XCTAssertTrue(behavior.contains("NavigationLink(value: MoreRoute.localModel)"))
        XCTAssertFalse(more.contains("$showingPersonalSettings"))
        XCTAssertFalse(more.contains("$showingNotificationSettings"))
    }

    /// The model page carries the same surface as the other More pages. A page
    /// with no panel is bare text on the wallpaper, which reads as a screen that
    /// was never finished rather than as a deliberate one.
    ///
    /// **What it asserts now used to be the defect.** The old version required
    /// the page to call `.morePanel()` itself, so when `localModelSection`
    /// became an `AppSettingsGroup` — whose own job is to apply that panel — the
    /// page still qualified for this test by painting a SECOND one around it: a
    /// panel inside a panel, the group's label and footer trapped between the
    /// two, and no gutter to the screen edge.
    ///
    /// So the page composes the group and must not paint its own surface.
    func testTheModelPageCarriesTheSamePanelAsTheOtherMorePages() throws {
        let more = try String(contentsOf: sourceURL("Haiity/Views/MoreLocalModel.swift"), encoding: .utf8)
        let host = try String(contentsOf: sourceURL("Haiity/Views/MoreView.swift"), encoding: .utf8)
        XCTAssertTrue(host.contains("case .localModel: localModelSettings"),
                      "the root must compose the extracted model page")
        XCTAssertTrue(host.contains("var modelService = LocalModelService()"),
                      "the root must retain ownership of the model service")
        XCTAssertFalse(more.contains("LocalModelService()"),
                       "the extracted page must use the root's service")

        // Two slices, because two declarations are involved and each has its own
        // claim. Slicing only the page body (what this did first) meant
        // `AppSettingsGroup` was matched from the prose comment that introduces
        // the next declaration — an assertion that passed on documentation
        // instead of on the component being documented.
        let page = try XCTUnwrap(more.range(of: "var localModelSettings"))
        let section = try XCTUnwrap(more.range(of: "var localModelSection"))
        XCTAssertLessThan(page.upperBound, section.lowerBound)

        let pageBody = more[page.upperBound..<section.lowerBound]
        XCTAssertTrue(pageBody.contains("localModelSection"),
                      "the page must render its catalogue")
        XCTAssertFalse(pageBody.contains(".morePanel()"),
                       "the group brings its own panel; a second one nests inside it")
        XCTAssertTrue(pageBody.contains("SettingsPage"),
                      "the model page sits in the shell every sibling page sits in")

        // And the catalogue itself is built from the shared group, which is what
        // carries the surface the page must show.
        let search = section.lowerBound..<more.endIndex
        let sectionEnd = try XCTUnwrap(more.range(of: "func localModelRow(", range: search))
        let sectionBody = more[section.lowerBound..<sectionEnd.lowerBound]
        XCTAssertTrue(sectionBody.contains("AppSettingsGroup"),
                      "the model page needs the same group surface as Darstellung and Verhalten & Teilen")
    }

    @MainActor
    func testCompactRootHeadingsFitAtAX5InEveryStyleAndDirection() {
        for style in AppDesignStyle.allCases {
            var preferences = AppearancePreferences()
            preferences.designStyle = style
            for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                for title in ["Heute", "Habits", "Fortschritt"] {
                    let host = UIHostingController(rootView: RootPageTitle(title: title, compact: true)
                        .environment(\.appearancePreferences, preferences)
                        .environment(\.layoutDirection, direction)
                        .environment(\.dynamicTypeSize, .accessibility5))
                    let size = host.sizeThatFits(in: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude))
                    XCTAssertLessThanOrEqual(size.width, 320)
                    XCTAssertGreaterThanOrEqual(size.height, Theme.Metrics.hit)
                    XCTAssertTrue(size.height.isFinite)
                }
            }
        }
    }

    func testRootTitleProgressKeepsTheLastMeasuredValueAcrossEmptyChildren() {
        var value: CGFloat? = nil
        RootPageTitleProgressKey.reduce(value: &value, nextValue: { 0.25 })
        XCTAssertEqual(value, 0.25)
        RootPageTitleProgressKey.reduce(value: &value, nextValue: { nil })
        XCTAssertEqual(value, 0.25)
        RootPageTitleProgressKey.reduce(value: &value, nextValue: { 1 })
        XCTAssertEqual(value, 1)
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
        let end = try XCTUnwrap(more.range(of: "var accentColor: Color",
                                           range: start.upperBound..<more.endIndex))
        let main = more[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(main.contains("ScrollView"))
        XCTAssertTrue(main.contains("AppSettingsGroup"))
        XCTAssertTrue(main.contains("\"open-appearance\""))
        XCTAssertTrue(main.contains("\"open-habit-behavior\""))
        XCTAssertFalse(main.contains("defaultTimeZonePicker"),
                       "the default time zone moved to Verhalten & Teilen")
        XCTAssertFalse(main.contains("List {"),
                       "the rebuilt hub must not collapse multiple routes into one List row")
    }

    func testDefaultTimeZoneUsesTheWholeSettingsRowAsTheMenuLabel() throws {
        let more = try String(contentsOf: sourceURL("Haiity/Views/MoreBehavior.swift"), encoding: .utf8)
        let behavior = try XCTUnwrap(more.range(of: "var habitBehaviorSettings: some View"))
        let behaviorEnd = try XCTUnwrap(more.range(of: "var cloudSyncSection: some View",
                                                   range: behavior.upperBound..<more.endIndex))
        XCTAssertTrue(more[behavior.lowerBound..<behaviorEnd.lowerBound].contains("defaultTimeZoneGroup"),
                      "the default time zone belongs to Verhalten & Teilen")
        let start = try XCTUnwrap(more.range(of: "var defaultTimeZonePicker: some View"))
        let end = try XCTUnwrap(more.range(of: "var swipeActionsSection: some View",
                                           range: start.upperBound..<more.endIndex))
        let picker = more[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(picker.contains("Menu {"),
                      "the timezone selector should remain a native menu")
        XCTAssertTrue(picker.contains("} label: {\n            AppSettingsRow("),
                      "the entire settings row must open the timezone menu")
        XCTAssertFalse(picker.contains("symbol: \"globe\") {\n            Menu {"),
                       "the row must not be nested inside a trailing-only menu label")
    }

    func testSettingsNavigationDoesNotReplaySetupOrAuthenticateFromTheHub() throws {
        let more = try String(contentsOf: sourceURL("Haiity/Views/MoreView.swift"))
        let notifications = try String(contentsOf: sourceURL("Haiity/Views/MoreNotifications.swift"))
        XCTAssertFalse(more.contains("showReminderSetup = true"))
        XCTAssertFalse(more.contains("SignInWithAppleButton("))
        XCTAssertFalse(more.contains("signOutFromApple()"))
        XCTAssertTrue(more.contains("onOpen(.calendar)"))
        XCTAssertTrue(more.contains("onOpen(.personalization)"))
        XCTAssertTrue(notifications.contains("motivationSourceControl"))
        XCTAssertTrue(notifications.contains("var motivationSourceControl: some View"))
    }

    func testSettingsAndArchiveRoutesCannotReuseEachOthersPresentedDestination() {
        for (incoming, current) in [(AppDestination.more, AppMoreDestination.archive),
                                    (.archive, .settings), (.cleanup, .archive)] {
            var work = RouteWork()
            let route = work.begin(incoming.effect)
            XCTAssertEqual(work.nextStep(for: route, presentation: .init(more: .presented, morePage: current)),
                           .dismissMore)
            XCTAssertEqual(work.nextStep(for: route, presentation: .init(more: .dismissing, morePage: current)),
                           .waitForMoreDismissal)
            XCTAssertEqual(work.nextStep(for: route, presentation: .init()), .apply)
            XCTAssertEqual(route.effect.tab, .today)
        }
        for page in [AppMoreDestination.notifications, .personalization, .localModel, .dataTransfer] {
            var work = RouteWork()
            let route = work.begin(AppDestination.more.effect)
            XCTAssertEqual(work.nextStep(for: route, presentation: .init(more: .presented, morePage: page)),
                           .dismissMore, "An external settings route must return from \(page) to the root")
            XCTAssertEqual(work.nextStep(for: route, presentation: .init(more: .dismissing, morePage: page)),
                           .waitForMoreDismissal)
            XCTAssertEqual(work.nextStep(for: route, presentation: .init()), .apply)
        }
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
        let more = try String(contentsOf: sourceURL("Haiity/Views/MoreAppearance.swift"), encoding: .utf8)

        XCTAssertTrue(theme.contains("var performanceMode: Bool"))
        XCTAssertTrue(theme.contains("performanceMode"))
        for material in AppearanceMaterial.allCases {
            let preferences = AppearancePreferences(material: material, performanceMode: true)
            XCTAssertEqual(Theme.effectiveMaterial(preferences), .solid,
                           "performance mode must bypass expensive glass for \(material)")
        }
        XCTAssertTrue(more.contains("performance-mode-toggle"))
    }

    func testNativeCalendarMaintenanceUsesButtonTreatment() throws {
        let more = try String(contentsOf: sourceURL("Haiity/Views/MoreCalendar.swift"), encoding: .utf8)
        let calendar = try XCTUnwrap(more.range(of: "var calendarSection"))
        let end = try XCTUnwrap(more.range(of: "func cleanupNativeEntries",
                                           range: calendar.upperBound..<more.endIndex))
        let section = more[calendar.lowerBound..<end.lowerBound]
        XCTAssertTrue(section.contains(".buttonStyle(.bordered)"))
    }

    func testAliasAndAppleRowsUseTheSameLeadingIconSlot() throws {
        let more = try String(contentsOf: sourceURL("Haiity/Views/MorePersonal.swift"), encoding: .utf8)

        XCTAssertTrue(more.contains("func personalLeadingIcon"),
                      "personal rows need one shared icon layout")
        XCTAssertTrue(more.contains("personalLeadingIcon(\"person.crop.circle\")"))
        XCTAssertTrue(more.contains("personalLeadingIcon(\"person.crop.circle.badge.checkmark\")"))
    }

    @MainActor
    func testDetailDestinationResolvesRenamedArchivedAndDeletedItemsFromTheLiveStore() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("detail-route-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url, loadFromDisk: false)
        var habit = Habit(name: "Before")
        store.add(habit)
        let view = HabitDetailView(store: store, habitID: habit.id, now: .now,
            onEdit: { _ in }, onHistory: { _ in }, onToggleDay: { _, _ in },
            onIncrement: { _ in }, onAnswer: { _, _ in }, onToggleReminder: { _ in },
            onArchive: { _ in }, onDelete: { _ in })
        XCTAssertEqual(view.currentHabit?.name, "Before")
        habit.name = "After sync"
        store.update(habit)
        XCTAssertEqual(view.currentHabit?.name, "After sync")
        habit.archivedAt = "2026-10-10"
        store.update(habit)
        XCTAssertNil(view.currentHabit)
        store.remove(habit.id)
        XCTAssertNil(view.currentHabit, "A stale route must not create a replacement")
    }

    #if DEBUG
    @MainActor
    func testDetailsFollowLiveProEligibilityWhileArchivedHistoryRemainsReadOnly() {
        let defaults = UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard
        let keys = [HabitVisibility.proUnlockedKey, HabitVisibility.proEntitlementExpirationKey]
        let saved = keys.map { defaults.object(forKey: $0) }
        let originalOverride = Pro.debugOverride
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
            Pro.setDebugUnlocked(nil)
            if let originalOverride { Pro.setDebugUnlocked(originalOverride) }
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("detail-eligibility-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url, loadFromDisk: false)
        let active = (1...4).map { Habit(name: "Habit \($0)", notificationMode: .off) }
        for habit in active { store.add(habit) }
        var archived = Habit(name: "Archived", notificationMode: .off)
        archived.archivedAt = "2026-10-10"
        archived.log["2026-10-09"] = 1
        store.add(archived)
        let ids = store.habits.map(\.id)

        func detail(_ id: UUID, allowsArchived: Bool = false) -> HabitDetailView {
            HabitDetailView(store: store, habitID: id, now: .now,
                onEdit: { _ in }, onHistory: { _ in }, onToggleDay: { _, _ in },
                onIncrement: { _ in }, onAnswer: { _, _ in }, onToggleReminder: { _ in },
                onArchive: { _ in }, onDelete: { _ in }, allowsArchived: allowsArchived)
        }
        let fourth = detail(active[3].id)
        let activeArchivedLink = detail(archived.id)
        let archivedHistory = detail(archived.id, allowsArchived: true)
        Pro.setDebugUnlocked(false)
        XCTAssertFalse(Pro.isUnlocked)
        XCTAssertEqual(detail(active[0].id).currentHabit?.id, active[0].id)
        XCTAssertNil(fourth.currentHabit, "A widget or direct UUID route must not expose the fourth free-tier habit")
        XCTAssertNil(activeArchivedLink.currentHabit)
        XCTAssertEqual(archivedHistory.currentHabit?.log["2026-10-09"], 1)
        XCTAssertFalse(ProGate.mayUnarchiveTrackedHabit(isTracked: archived.isTrackedHabit,
            activeCount: store.activeTrackedHabits.count, unlocked: Pro.isUnlocked))

        Pro.setDebugUnlocked(true)
        XCTAssertTrue(Pro.isUnlocked)
        XCTAssertEqual(fourth.currentHabit?.id, active[3].id)
        XCTAssertNil(activeArchivedLink.currentHabit, "Pro must not silently unarchive an item")
        XCTAssertEqual(store.habits.map(\.id), ids, "Entitlement changes must preserve over-limit data")
        Pro.setDebugUnlocked(false)
        XCTAssertNil(fourth.currentHabit, "The same detail view must become unavailable again on entitlement loss")
        XCTAssertEqual(archivedHistory.currentHabit?.id, archived.id)

        store.remove(active[3].id)
        store.remove(archived.id)
        Pro.setDebugUnlocked(true)
        XCTAssertNil(fourth.currentHabit)
        XCTAssertNil(archivedHistory.currentHabit)
        XCTAssertEqual(store.habits.map(\.id), Array(active.prefix(3)).map(\.id),
                       "Resolving stale detail routes must never create replacement items")
    }
    #endif

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

    func testPersonalizationHubKeepsAuthenticationOnlyOnItsSecondaryPage() throws {
        let more = try String(contentsOf: sourceURL("Haiity/Views/MoreView.swift"))
        let personal = try String(contentsOf: sourceURL("Haiity/Views/MorePersonal.swift"))
        XCTAssertTrue(more.contains("onOpen(.personalization)"))
        XCTAssertFalse(more.contains("SignInWithAppleButton("))
        XCTAssertFalse(more.contains("signOutFromApple()"))
        XCTAssertFalse(more.contains("apple-signout-more"))
        XCTAssertFalse(more.contains("apple-signin-more"))
        XCTAssertTrue(personal.contains("SignInWithAppleButton(.signIn)"))
        XCTAssertTrue(personal.contains("personal-apple-connection"))
        XCTAssertTrue(more.contains("refreshPersonalIdentity()"))
    }

    func testNativeContentDestinationsReuseTheSingleStoreAndIndependentUUIDPaths() throws {
        let content = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        for path in ["todayPath", "habitsPath", "statsPath", "searchPath"] {
            XCTAssertTrue(content.contains("NavigationStack(path: $\(path))"), path)
        }
        XCTAssertTrue(content.contains("AppearanceBackground(preferences: store.appearancePreferences)"))
        XCTAssertFalse(content.contains("StatsView(store: HabitStore("))
        XCTAssertFalse(content.contains("HabitDetailView(store: HabitStore("))
        XCTAssertFalse(content.contains("HabitsView(store: HabitStore("))
        XCTAssertFalse(content.contains("TodayView(store: HabitStore("))
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

    func testEveryRouteDismissesOrWaitsForTheCurrentCreatorLifecycle() {
        let destinations: [AppDestination] = [.habits, .more, .stats, .archive, .search, .create, .cleanup]

        for destination in destinations {
            var work = RouteWork()
            let route = work.begin(destination.effect)

            XCTAssertEqual(work.nextStep(for: route,
                                         presentation: .init(create: .requested)),
                           .dismissCreate,
                           "\(destination) must cancel a creator that has not appeared")
            XCTAssertEqual(work.nextStep(for: route,
                                         presentation: .init(create: .presented)),
                           .dismissCreate,
                           "\(destination) must dismiss create first")
            XCTAssertEqual(work.nextStep(for: route,
                                         presentation: .init(create: .dismissing)),
                           .waitForCreateDismissal,
                           "\(destination) must wait for create onDismiss")
            XCTAssertEqual(work.nextStep(for: route, presentation: .init()), .apply)
        }
    }

    func testNewCreateRouteDismissesSentenceChildThenCreatorBeforeReopening() {
        var work = RouteWork()
        let replaced = work.begin(AppDestination.create.effect)
        let latest = work.begin(AppDestination.create.effect)
        var presentation = RoutePresentation(create: .presented, sentenceCreation: .presented)
        XCTAssertNil(work.nextStep(for: replaced, presentation: presentation))
        XCTAssertEqual(work.nextStep(for: latest, presentation: presentation), .dismissSentenceCreation)
        presentation.sentenceCreation = .dismissing
        XCTAssertEqual(work.nextStep(for: latest, presentation: presentation), .waitForSentenceCreationDismissal)
        presentation.sentenceCreation = .absent
        XCTAssertEqual(work.nextStep(for: latest, presentation: presentation), .dismissCreate)
        presentation.create = .dismissing
        XCTAssertEqual(work.nextStep(for: latest, presentation: presentation), .waitForCreateDismissal)
        presentation.create = .absent
        XCTAssertEqual(work.nextStep(for: latest, presentation: presentation), .apply)
        XCTAssertTrue(latest.effect.opensCreate)
    }

    func testRouteArrivingDuringCreatorDismissalSupersedesPendingReopen() {
        var work = RouteWork()
        let reopen = work.begin(AppDestination.create.effect)
        XCTAssertEqual(work.nextStep(for: reopen, presentation: .init(create: .presented)), .dismissCreate)
        let search = work.begin(AppDestination.search.effect)
        XCTAssertNil(work.nextStep(for: reopen, presentation: .init(create: .dismissing)))
        XCTAssertEqual(work.nextStep(for: search, presentation: .init(create: .dismissing)), .waitForCreateDismissal)
        XCTAssertNil(work.nextStep(for: reopen, presentation: .init()))
        XCTAssertEqual(work.nextStep(for: search, presentation: .init()), .apply)
        XCTAssertTrue(search.effect.opensSearch)
        XCTAssertFalse(search.effect.opensCreate)
    }

    func testEveryRouteDismissesOrWaitsForHistoryBeforeApplying() {
        let destinations: [AppDestination] = [.habits, .habit(UUID()), .more, .stats,
                                              .archive, .search, .create, .cleanup]
        for destination in destinations {
            var work = RouteWork()
            let route = work.begin(destination.effect)
            for phase in [RoutePresentationPhase.requested, .presented] {
                XCTAssertEqual(work.nextStep(for: route, presentation: .init(history: phase)),
                               .dismissHistory, "\(destination) must dismiss \(phase) history")
            }
            XCTAssertEqual(work.nextStep(for: route, presentation: .init(history: .dismissing)),
                           .waitForHistoryDismissal, "\(destination) must wait for history onDismiss")
            XCTAssertEqual(work.nextStep(for: route, presentation: .init(history: .absent)), .apply)
        }
    }

    func testHistoryDismissalFollowsEditorAndPrecedesCreatorAndSettings() {
        var work = RouteWork()
        let route = work.begin(AppDestination.stats.effect)
        var presentation = RoutePresentation()
        presentation.editor = .presented
        presentation.history = .presented
        presentation.create = .presented
        presentation.more = .presented
        presentation.morePage = .settings
        XCTAssertEqual(work.nextStep(for: route, presentation: presentation), .dismissEditor)
        presentation.editor = .dismissing
        XCTAssertEqual(work.nextStep(for: route, presentation: presentation), .waitForEditorDismissal)
        presentation.editor = .absent
        XCTAssertEqual(work.nextStep(for: route, presentation: presentation), .dismissHistory)
        presentation.history = .dismissing
        XCTAssertEqual(work.nextStep(for: route, presentation: presentation), .waitForHistoryDismissal)
        presentation.history = .absent
        XCTAssertEqual(work.nextStep(for: route, presentation: presentation), .dismissCreate)
        presentation.create = .dismissing
        XCTAssertEqual(work.nextStep(for: route, presentation: presentation), .waitForCreateDismissal)
        presentation.create = .absent
        XCTAssertEqual(work.nextStep(for: route, presentation: presentation), .dismissMore)
        presentation.more = .dismissing
        XCTAssertEqual(work.nextStep(for: route, presentation: presentation), .waitForMoreDismissal)
        presentation.more = .absent
        XCTAssertEqual(work.nextStep(for: route, presentation: presentation), .apply)
    }

    func testLatestRouteWinsWhileHistoryDismissalIsPending() {
        var work = RouteWork()
        let stats = work.begin(AppDestination.stats.effect)
        XCTAssertEqual(work.nextStep(for: stats, presentation: .init(history: .presented)), .dismissHistory)
        let create = work.begin(AppDestination.create.effect)
        XCTAssertNil(work.nextStep(for: stats, presentation: .init(history: .dismissing)))
        XCTAssertEqual(work.nextStep(for: create, presentation: .init(history: .dismissing)), .waitForHistoryDismissal)
        XCTAssertNil(work.nextStep(for: stats, presentation: .init(history: .absent)))
        XCTAssertEqual(work.nextStep(for: create, presentation: .init(history: .absent)), .apply)
        XCTAssertTrue(create.effect.opensCreate)
    }

    func testEveryDeepLinkDismissesTheEditorBeforeApplying() {
        for destination in [AppDestination.habits, .more, .stats, .archive, .search, .create] {
            var work = RouteWork()
            let route = work.begin(destination.effect)
            XCTAssertEqual(work.nextStep(for: route, presentation: .init(editor: .requested)), .dismissEditor)
            XCTAssertEqual(work.nextStep(for: route, presentation: .init(editor: .presented)), .dismissEditor)
            XCTAssertEqual(work.nextStep(for: route, presentation: .init(editor: .dismissing)), .waitForEditorDismissal)
            XCTAssertEqual(work.nextStep(for: route, presentation: .init()), .apply)
        }
    }

    func testOnlyLatestDeepLinkContinuesAfterEditorDismissal() {
        var work = RouteWork()
        let stats = work.begin(AppDestination.stats.effect)
        XCTAssertEqual(work.nextStep(for: stats, presentation: .init(editor: .presented)), .dismissEditor)
        let create = work.begin(AppDestination.create.effect)
        XCTAssertNil(work.nextStep(for: stats, presentation: .init()))
        XCTAssertEqual(work.nextStep(for: create, presentation: .init(editor: .dismissing)), .waitForEditorDismissal)
        XCTAssertEqual(work.nextStep(for: create, presentation: .init()), .apply)
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
        for destination in [AppDestination.more, .archive, .cleanup] {
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
        let tabs: [AppTab] = [.today, .habits, .stats, .search]
        for selected in tabs {
            for tab in tabs {
                XCTAssertEqual(AppTabLayerState(tab: tab, selectedTab: selected),
                               tab == selected
                               ? .init(opacity: 1, allowsHitTesting: true, accessibilityHidden: false, zIndex: 1)
                               : .init(opacity: 0, allowsHitTesting: false, accessibilityHidden: true, zIndex: 0))
            }
            XCTAssertTrue(AppTabLayerState(tab: .more, selectedTab: selected).accessibilityHidden)
        }
    }

    func testNativeShellDeclaresTodayHabitsProgressAndSeparateSearchWithoutMoreTab() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        let pattern = try NSRegularExpression(pattern: #"value:\s*AppTab\.(\w+)"#)
        let names = pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        }
        XCTAssertEqual(Set(names), ["today", "habits", "stats", "search"])
        for name in ["today", "habits", "stats"] {
            XCTAssertEqual(names.filter { $0 == name }.count, 2, "Both native OS shells must include \(name)")
        }
        XCTAssertTrue(source.contains("role: .search"))
        XCTAssertTrue(source.contains("role: .prominent"))
    }

    func testFallbackKeepsTodayHabitsAndProgressMountedWithoutLegacyMoreContent() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        let pattern = try NSRegularExpression(pattern: #"fallbackTabLayer\(\.(\w+)\)"#)
        let tabs = pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        }
        XCTAssertEqual(tabs, ["today", "stats", "habits"])
        XCTAssertTrue(source.contains(".opacity(state.opacity)"))
        XCTAssertTrue(source.contains(".allowsHitTesting(state.allowsHitTesting)"))
        XCTAssertTrue(source.contains(".accessibilityHidden(state.accessibilityHidden)"))
    }

    func testSingleSettingsSheetDeliversPendingRoutesAfterNativeDismissal() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertEqual(source.components(separatedBy: "onDismiss: deliverPendingMoreDismissalRoute").count - 1, 1)
        XCTAssertEqual(source.components(separatedBy: ".onAppear { moreSheetDidPresent(route) }").count - 1, 1)
        XCTAssertEqual(source.components(separatedBy: "NavigationStack(path: $moreSheetPath)").count - 1, 1)
    }

    func testMoreRouteCanReplaceARequestedButNotPresentedSheet() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("let waitsForOnDismiss = moreSheetIsPresented"))
        XCTAssertTrue(source.contains("if !waitsForOnDismiss"))
        XCTAssertTrue(source.contains("advance(route)"))
    }

    func testSentenceAndCreatorDismissalSequenceKeepsOnlyTheLatestRoute() {
        var work = RouteWork()
        let old = work.begin(AppDestination.search.effect)
        let route = work.begin(AppDestination.more.effect)
        var presentation = RoutePresentation(create: .presented, sentenceCreation: .presented)
        XCTAssertNil(work.nextStep(for: old, presentation: presentation))
        XCTAssertEqual(work.nextStep(for: route, presentation: presentation), .dismissSentenceCreation)
        presentation.sentenceCreation = .dismissing
        XCTAssertEqual(work.nextStep(for: route, presentation: presentation), .waitForSentenceCreationDismissal)
        presentation.sentenceCreation = .absent
        XCTAssertEqual(work.nextStep(for: route, presentation: presentation), .dismissCreate)
        presentation.create = .dismissing
        XCTAssertEqual(work.nextStep(for: route, presentation: presentation), .waitForCreateDismissal)
        presentation.create = .absent
        XCTAssertEqual(work.nextStep(for: route, presentation: presentation), .apply)
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
        XCTAssertTrue(source.contains("HabitSortingRow("))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"reorder-habits\")"))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"finish-reordering\")"))
    }

    func testMainMorePageNavigatesToGitHubAndKeepsConnectionActionsOnItsPage() throws {
        let more = try String(contentsOf: sourceURL("Haiity/Views/MoreView.swift"))
        let content = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        let about = try String(contentsOf: sourceURL("Haiity/Views/AboutView.swift"), encoding: .utf8)
        let settings = try String(contentsOf: sourceURL("Haiity/Views/GitHubSettingsView.swift"), encoding: .utf8)

        XCTAssertTrue(more.contains("let github: GitHubContributionStore"))
        XCTAssertTrue(more.contains("private var moreGitHubRow: some View"))
        XCTAssertTrue(more.contains("accessibilityIdentifier(\"open-github-settings\")"))
        XCTAssertFalse(more.contains("accessibilityIdentifier(\"disconnect-github\")"))
        XCTAssertFalse(more.contains("accessibilityIdentifier(\"connect-github\")"))
        XCTAssertTrue(settings.contains("github-disconnect"))
        XCTAssertTrue(settings.contains("github-connect"))
        XCTAssertTrue(content.contains("GitHubSettingsView(store: github,"),
                      "the secondary page must reuse the same connected GitHub store")
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

    func testMoreHubKeepsTheArchiveRoute() throws {
        let more = try String(contentsOf: sourceURL("Haiity/Views/MoreView.swift"))
        let mainStart = try XCTUnwrap(more.range(of: "private var mainSettings: some View"))
        let mainEnd = try XCTUnwrap(more.range(of: "var accentColor: Color",
                                               range: mainStart.upperBound..<more.endIndex))
        let main = more[mainStart.lowerBound..<mainEnd.lowerBound]
        let archive = try XCTUnwrap(main.range(of: "identifier: \"open-archive\""))
        let end = try XCTUnwrap(main.range(of: "}", range: archive.upperBound..<main.endIndex))
        XCTAssertTrue(main[archive.upperBound..<end.lowerBound].contains("onOpen(.archive)"))
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

    func testSearchRouteWaitsForSettingsDismissalAndNeverOpensCreation() {
        var work = RouteWork()
        let route = work.begin(AppDestination.search.effect)
        XCTAssertEqual(work.nextStep(for: route, presentation: .init(more: .presented, morePage: .settings)),
                       .dismissMore)
        XCTAssertEqual(work.nextStep(for: route, presentation: .init(more: .dismissing)),
                       .waitForMoreDismissal)
        XCTAssertEqual(work.nextStep(for: route, presentation: .init()), .apply)
        XCTAssertEqual(route.effect.tab, .search)
        XCTAssertTrue(route.effect.opensSearch)
        XCTAssertFalse(route.effect.opensCreate)
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
