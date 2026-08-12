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

    func testNonCreateRoutesWaitForOpenCreateCover() {
        let destinations: [AppDestination] = [.habits, .more, .stats, .archive, .search]

        for destination in destinations {
            var work = RouteWork()
            let route = work.begin(destination.effect, createIsPresented: true)

            XCTAssertTrue(route.requiresCreateDismissal, "\(destination) must dismiss create first")
        }

        var work = RouteWork()
        let createRoute = work.begin(AppDestination.create.effect, createIsPresented: true)
        XCTAssertFalse(createRoute.requiresCreateDismissal)
    }

    func testLatestRouteWinsOverQueuedCreateCoverDismissal() {
        var work = RouteWork()
        let statsRoute = work.begin(AppDestination.stats.effect, createIsPresented: true)
        let habitsRoute = work.begin(AppDestination.habits.effect, createIsPresented: true)

        XCTAssertFalse(work.canDeliverAfterCreateDismissal(statsRoute))
        XCTAssertTrue(work.canDeliverAfterCreateDismissal(habitsRoute))
    }

    func testContentViewDeclaresHabitsAndMoreTabs() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("value: AppTab.habits"))
        XCTAssertTrue(source.contains("value: AppTab.more"))
        XCTAssertFalse(source.contains("enum NativeTab"))
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
