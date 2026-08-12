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
    }

    func testUnknownAndForeignURLsAreIgnored() {
        XCTAssertNil(AppDestination.resolve(url: URL(string: "https://aiity.de")!))
        XCTAssertNil(AppDestination.resolve(url: URL(string: "haiity://unknown")!))
    }

    func testNestedMoreDestinationsSelectMoreTab() {
        XCTAssertEqual(AppDestination.stats.selectedTab, .more)
        XCTAssertEqual(AppDestination.archive.selectedTab, .more)
        XCTAssertEqual(AppDestination.more.selectedTab, .more)
        XCTAssertEqual(AppDestination.search.selectedTab, .habits)
        XCTAssertEqual(AppDestination.create.selectedTab, .create)
    }

    func testStatsAndArchiveRouteViaMoreTab() {
        XCTAssertEqual(AppDestination.stats.effect,
                       AppRouteEffect(tab: .more, morePage: .stats,
                                      opensSearch: false, opensCreate: false))
        XCTAssertEqual(AppDestination.archive.effect,
                       AppRouteEffect(tab: .more, morePage: .archive,
                                      opensSearch: false, opensCreate: false))
    }

    func testSearchAndCreateHaveExplicitEffects() {
        XCTAssertEqual(AppDestination.search.effect.tab, .habits)
        XCTAssertTrue(AppDestination.search.effect.opensSearch)
        XCTAssertTrue(AppDestination.create.effect.opensCreate)
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

    func testStatsToArchiveDismissesThenAppliesAfterMoreOnDismiss() {
        var work = RouteWork()
        let archive = work.begin(AppDestination.archive.effect)

        XCTAssertEqual(work.nextStep(for: archive,
                                     presentation: .init(more: .presented,
                                                         morePage: .stats)),
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
                                                             morePage: .stats)),
                           .dismissMore,
                           "\(destination) must depart More through onDismiss")
        }
    }

    func testAlreadyPresentedMoreDestinationDoesNotDismissOrRepresent() {
        for destination in [AppDestination.stats, .archive] {
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

    func testContentViewDeclaresHabitsAndMoreTabs() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("value: AppTab.habits"))
        XCTAssertTrue(source.contains("value: AppTab.more"))
        XCTAssertFalse(source.contains("enum NativeTab"))
    }

    func testFallbackKeepsBothDestinationTreesMounted() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
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

    func testCreateAccessibilityContractIsSharedAcrossCustomControls() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("static let label = String(localized: \"Neuer Habit\")"))
        XCTAssertTrue(source.contains("static let identifier = \"create-habit\""))
        XCTAssertEqual(source.components(separatedBy:
            ".accessibilityLabel(CreateAccessibility.label)").count - 1, 2)
        XCTAssertEqual(source.components(separatedBy:
            ".accessibilityIdentifier(CreateAccessibility.identifier)").count - 1, 2)
        XCTAssertTrue(source.contains("Tab(CreateAccessibility.label, systemImage: \"plus\""))
    }

    func testContentViewKeepsHabitReorderingReachable() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("@State private var editMode: EditMode = .inactive"))
        XCTAssertTrue(source.contains(".environment(\\.editMode, $editMode)"))
        XCTAssertTrue(source.contains("EditButton()"))
        XCTAssertTrue(source.contains(".onMove(perform: search.isEmpty"))
    }

    private func sourceURL(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }
}
