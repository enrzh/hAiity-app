import XCTest
import SwiftUI
import UIKit
@testable import Haiity

final class SearchFlowTests: XCTestCase {
    func testSearchPageUsesAVisibleNativeSearchField() throws {
        let source = try contentSource()
        let nativeSearch = try NSRegularExpression(pattern:
            #"\.searchable\(text:\s*\$\w+,\s*placement:\s*\.navigationBarDrawer\(displayMode:\s*\.always\)"#)
        XCTAssertEqual(nativeSearch.numberOfMatches(in: source, range: NSRange(source.startIndex..., in: source)), 1,
                       "the dedicated search page owns one visible native field")
        XCTAssertEqual(source.components(separatedBy: ".searchFocused(").count - 1, 1)
    }

    func testSearchPageDoesNotCarryTheOldPresentationWorkaround() throws {
        let source = try contentSource()

        XCTAssertTrue(source.contains("TabView(selection: $nativeTab)"))
        XCTAssertFalse(source.contains("nativeTabSelection"))
        XCTAssertFalse(source.contains("searchPresentationTask"))
        XCTAssertFalse(source.contains("searchCloseTask"))
        XCTAssertFalse(source.contains("SearchFieldWatcher"))
        XCTAssertFalse(source.contains("SearchFieldProbe"))
        XCTAssertFalse(source.contains("SearchFlow"))
        XCTAssertFalse(source.contains("SearchFieldReading"))
    }

    func testSearchPageKeepsTheNativeSearchTabAndRetainsQueryWhenLeaving() throws {
        let source = try contentSource()
        XCTAssertTrue(source.contains("value: AppTab.search, role: .search"))
        XCTAssertTrue(source.contains("value: AppTab.search, role: .prominent"))

        let tabChange = try XCTUnwrap(source.range(of: ".onChange(of: nativeTab)"))
        let nextChange = try XCTUnwrap(source.range(of: ".onReceive(Timer.publish",
                                                     range: tabChange.upperBound..<source.endIndex))
        let tabBody = source[tabChange.lowerBound..<nextChange.lowerBound]
        XCTAssertTrue(tabBody.contains("old == .search, tab != .search"))
        XCTAssertTrue(tabBody.contains("searchFieldFocused = false"),
                      "leaving Search releases keyboard focus without clearing the query")
        XCTAssertNil(tabBody.range(of: #"\b(search|committedSearch)\s*="#, options: .regularExpression),
                     "tab navigation must retain both the typed and committed query")
    }

    func testProminentSearchTabKeepsTheBarSplitFromContentTabs() throws {
        let source = try contentSource()
        let prominent = try NSRegularExpression(pattern: #"value:\s*AppTab.search,\s*role:\s*\.prominent"#)
        XCTAssertEqual(prominent.numberOfMatches(in: source, range: NSRange(source.startIndex..., in: source)), 1)
        let contentTabs = try NSRegularExpression(pattern: #"value:\s*AppTab\.(today|habits|stats)\)"#)
        XCTAssertEqual(contentTabs.numberOfMatches(in: source, range: NSRange(source.startIndex..., in: source)), 6)
        XCTAssertFalse(source.contains("value: AppTab.more"))
    }

    @MainActor
    func testCompactSearchRowsGrowAtAX5InRTLWithoutHorizontalOverflow() {
        for itemType in [HabitItemType.habit, .reminder] {
            let habit = Habit(name: "A long item name that must stay readable while browsing search results",
                              itemType: itemType, notificationMode: .off)
            let row = SearchResultRow(habit: habit, onEdit: {}, onDetails: {})
            for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                let normal = UIHostingController(rootView: row.environment(\.dynamicTypeSize, .large)
                    .environment(\.layoutDirection, direction))
                let accessible = UIHostingController(rootView: row.environment(\.dynamicTypeSize, .accessibility5)
                    .environment(\.layoutDirection, direction))
                let proposal = CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
                let size = accessible.sizeThatFits(in: proposal)
                XCTAssertLessThanOrEqual(size.width, 320)
                XCTAssertGreaterThan(size.height, normal.sizeThatFits(in: proposal).height)
                XCTAssertGreaterThanOrEqual(size.height, Theme.Metrics.hit)
            }
        }
    }

    private func contentSource() throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Haiity/Views/ContentView.swift"))
    }
}
