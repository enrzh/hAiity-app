import XCTest

final class SearchFlowTests: XCTestCase {
    func testSearchPageUsesAVisibleNativeSearchField() throws {
        let source = try contentSource()
        let start = try XCTUnwrap(source.range(of: "private var searchTabContent"))
        let end = try XCTUnwrap(source.range(of: "private var searchList",
                                             range: start.upperBound..<source.endIndex))
        let searchPage = source[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(searchPage.contains(".searchable(text: $search"))
        XCTAssertTrue(searchPage.contains("placement: .navigationBarDrawer(displayMode: .always)"))
        XCTAssertFalse(searchPage.contains("isPresented:"))
        XCTAssertTrue(searchPage.contains(".searchFocused($searchFieldFocused)"))
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

    func testSearchPageKeepsTheNativeSearchTabAndClearsQueryWhenLeaving() throws {
        let source = try contentSource()
        XCTAssertTrue(source.contains("value: AppTab.search, role: .search"))
        XCTAssertTrue(source.contains("value: AppTab.search, role: .prominent"))

        let tabChange = try XCTUnwrap(source.range(of: ".onChange(of: nativeTab)"))
        let nextChange = try XCTUnwrap(source.range(of: ".onChange(of:",
                                                     range: tabChange.upperBound..<source.endIndex))
        let tabBody = source[tabChange.lowerBound..<nextChange.lowerBound]
        XCTAssertTrue(tabBody.contains("old == .search, tab != .search"))
        XCTAssertTrue(tabBody.contains("committedSearch = \"\""))
    }

    func testProminentSearchTabKeepsTheBarSplitFromContentTabs() throws {
        let source = try contentSource()
        let start = try XCTUnwrap(source.range(of: "private var splitShell"))
        let end = try XCTUnwrap(source.range(of: "private func nativeTabRoot",
                                             range: start.upperBound..<source.endIndex))
        let split = source[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(split.contains("value: AppTab.stats"))
        XCTAssertTrue(split.contains("value: AppTab.habits"))
        XCTAssertTrue(split.contains("value: AppTab.more"))
        XCTAssertTrue(split.contains("role: .prominent"))
        XCTAssertFalse(split.contains(".tabViewSearchActivation"))
    }

    func testSearchListUsesCompactRowsWithoutContributionGraphs() throws {
        let source = try contentSource()
        let start = try XCTUnwrap(source.range(of: "private var searchList: some View"))
        let end = try XCTUnwrap(source.range(of: "private var habitsTabContent",
                                             range: start.upperBound..<source.endIndex))
        let searchList = source[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(searchList.contains("searchResults"))
        XCTAssertTrue(searchList.contains("searchRow(for: habit)"))
        XCTAssertFalse(searchList.contains("row(for: habit, inSearchTab: true)"))
        XCTAssertFalse(searchList.contains("HabitCard("))
        XCTAssertFalse(searchList.contains("ContributionGrid"))
        XCTAssertFalse(searchList.contains("GitHubContributionCard"))
        XCTAssertTrue(source.contains("private var searchResults: [Habit]"))
        XCTAssertTrue(source.contains("let active = visibleActiveHabits"))
        XCTAssertTrue(source.contains("SearchResultRow(habit:"))
        XCTAssertFalse(source.contains("rowProbe"),
                       "sorting must not install row probes that fight list scrolling")
    }

    private func contentSource() throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Haiity/Views/ContentView.swift"))
    }
}
