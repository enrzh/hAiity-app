import XCTest
@testable import Haiity

final class AppNavigationTests: XCTestCase {
    func testPrimaryDeepLinksSelectTheirTabs() {
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://habits")!), .habits)
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://more")!), .more)
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
