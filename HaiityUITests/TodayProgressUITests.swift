import XCTest

@MainActor
final class TodayProgressUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(_ fixture: String = "realistic", largeText: Bool = false,
                        appearance: String = "light", screen: String = "habits") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-design-fixture", fixture, "-screen", screen, "-pro", "on",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_GB",
                               "-design-appearance", appearance]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testRedesignRootAndSecondaryPagesInBothAppearances() {
        for appearance in ["light", "dark"] {
            let app = launch("crowded", appearance: appearance, screen: "more")
            let settings = app.buttons["open-appearance"].firstMatch
            XCTAssertTrue(settings.waitForExistence(timeout: 15))
            XCTAssertTrue(settings.isHittable)
            capture("redesign-more-\(appearance)")
            settings.tap()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
            capture("redesign-appearance-\(appearance)")
            app.terminate()

            let stats = launch("crowded", appearance: appearance, screen: "stats")
            let weekly = stats.descendants(matching: .any)["stats-week-card"].firstMatch
            XCTAssertTrue(weekly.waitForExistence(timeout: 15))
            capture("redesign-stats-\(appearance)")
            stats.swipeUp()
            XCTAssertTrue(stats.descendants(matching: .any)["stats-row"].firstMatch
                .waitForExistence(timeout: 5))
            capture("redesign-stats-ranking-\(appearance)")
            stats.terminate()
        }
    }

    func testContributionChartLightAndDarkScreenshots() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance)
            XCTAssertTrue(app.buttons["check-today"].firstMatch.waitForExistence(timeout: 15))
            capture("contribution-chart-\(appearance)")
            app.descendants(matching: .any)["habit-history"].firstMatch.tap()
            XCTAssertTrue(app.buttons["backfill-close"].waitForExistence(timeout: 5))
            app.buttons["history-previous-month"].tap()
            capture("history-editor-\(appearance)")
            app.terminate()
        }
    }

    func testCompletionUndoAndTodayFilterKeepFirstHabitInPlace() {
        let app = launch()
        let summary = app.descendants(matching: .any)["today-progress"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        let filter = app.segmentedControls["today-all-filter"]
        filter.buttons["Today"].tap()
        let first = app.buttons["check-today"].firstMatch
        XCTAssertTrue(first.isHittable)
        first.tap()
        XCTAssertTrue(app.buttons["check-today"].firstMatch.label.contains("Done"))
        app.buttons["check-today"].firstMatch.tap()
        XCTAssertFalse(app.buttons["check-today"].firstMatch.label.contains("Done"))
        XCTAssertTrue(app.staticTexts["Read for twenty minutes"].firstMatch.exists)
        capture("today-completion-undo")
    }

    func testSearchTabShowsFieldAndFieldTapActivatesInput() {
        let app = launch()
        let searchTab = app.tabBars.buttons["Search"].firstMatch
        XCTAssertTrue(searchTab.waitForExistence(timeout: 15))

        searchTab.tap()
        XCTAssertTrue(searchTab.waitForExistence(timeout: 5))
        XCTAssertTrue(searchTab.isSelected)
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))

        searchField.swipeUp()
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))

        searchField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    }

    func testGraphOpensHistoryAndCanEditAnEarlierMonth() {
        let app = launch()
        let history = app.descendants(matching: .any)["habit-history"].firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 15))
        XCTAssertTrue(history.isHittable)
        history.tap()
        XCTAssertTrue(app.buttons["backfill-close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["history-month-preview"].exists)
        app.buttons["history-previous-month"].tap()
        app.buttons["history-selection-mode"].tap()
        app.buttons["history-select-all"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'history-day-'"))
        XCTAssertGreaterThan(rows.count, 0)
        let status = app.staticTexts["backfill-status"]
        let originalStatus = status.label
        XCTAssertTrue(originalStatus.contains("31"))
        let before = rows.firstMatch.label
        app.buttons["backfill-action-clear"].tap()
        XCTAssertNotEqual(status.label, originalStatus)
        XCTAssertTrue(app.buttons["history-undo"].isEnabled)
        app.buttons["history-undo"].tap()
        XCTAssertEqual(rows.firstMatch.label, before)
        XCTAssertEqual(status.label, originalStatus)
        app.buttons["history-select-all"].tap()
        rows.element(boundBy: 0).tap()
        rows.element(boundBy: 1).tap()
        capture("history-entry-editor")
        app.buttons["backfill-close"].tap()
        XCTAssertTrue(history.waitForExistence(timeout: 5))
    }

    func testHistoryQuantityUpdateUndoAndMissingFilter() {
        let app = launch()
        let graphs = app.descendants(matching: .any).matching(identifier: "habit-history")
        XCTAssertTrue(graphs.firstMatch.waitForExistence(timeout: 15))
        graphs.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["backfill-close"].waitForExistence(timeout: 5))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'history-day-'"))
        let previous = rows.firstMatch.label
        rows.firstMatch.tap()
        XCTAssertNotEqual(rows.firstMatch.label, previous)
        app.buttons["history-undo"].tap()
        XCTAssertEqual(rows.firstMatch.label, previous)
        app.buttons["history-previous-month"].tap()
        app.switches["history-missing-filter"].tap()
        app.buttons["history-selection-mode"].tap()
        XCTAssertFalse(app.buttons["backfill-action-quantity"].isEnabled)
        app.buttons["history-select-all"].tap()
        XCTAssertTrue(app.buttons["backfill-action-quantity"].isEnabled)
        capture("history-quantity-editor")
    }

    func testHistoryOneTapEditsAndSequentialUndo() {
        let app = launch()
        let graph = app.descendants(matching: .any)["habit-history"].firstMatch
        XCTAssertTrue(graph.waitForExistence(timeout: 15))
        graph.tap()
        XCTAssertTrue(app.buttons["backfill-close"].waitForExistence(timeout: 5))
        app.buttons["history-previous-month"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'history-day-'"))
        let first = rows.element(boundBy: 0)
        let second = rows.element(boundBy: 1)
        let firstBefore = first.label
        let secondBefore = second.label
        XCTAssertFalse(app.buttons["backfill-action-clear"].exists)
        XCTAssertGreaterThanOrEqual(first.frame.height, 44)
        XCTAssertEqual(first.frame.width, first.frame.height, accuracy: 1)
        first.tap()
        XCTAssertNotEqual(first.label, firstBefore)
        second.tap()
        XCTAssertNotEqual(second.label, secondBefore)
        app.buttons["history-undo"].tap()
        XCTAssertEqual(second.label, secondBefore)
        XCTAssertNotEqual(first.label, firstBefore)
        app.buttons["history-undo"].tap()
        XCTAssertEqual(first.label, firstBefore)
        XCTAssertFalse(app.buttons["history-undo"].isEnabled)
        capture("compact-history-direct-edit")
    }

    func testCreationLivePreviewAndAdvancedControls() {
        let app = launch("empty")
        let create = app.buttons["create-habit"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        create.tap()
        let name = app.textFields["habit-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Morning pages\n")
        let preview = app.descendants(matching: .any)["creation-preview"].firstMatch
        XCTAssertTrue(preview.label.contains("Morning pages"))
        capture("creation-live-preview")
        let advanced = app.descendants(matching: .any)["creation-advanced"].firstMatch
        for _ in 0..<6 {
            if advanced.isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        capture("creation-advanced-navigation")
        if !advanced.exists {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "creation-accessibility-tree"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(advanced.exists)
        advanced.tap()
        for _ in 0..<4 {
            if app.buttons["habit-timezone"].isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(app.buttons["habit-timezone"].exists)
        capture("creation-advanced")
    }

    func testCrowdedListLargeTextKeepsPrimaryActionReachable() throws {
        let app = launch("crowded", largeText: true)
        let summary = app.descendants(matching: .any)["today-progress"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        capture("crowded-accessibility-xxxl")
        let check = app.buttons["check-today"].firstMatch
        for _ in 0..<6 {
            if check.isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(check.isHittable)
        XCTAssertGreaterThanOrEqual(check.frame.height, 44)
        if #available(iOS 17.0, *) {
            // Contrast is covered visually across palettes; inspect actionable
            // geometry and labels with the platform accessibility audit.
            try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription])
        }
        capture("crowded-accessible-actions")
    }

    func testLightDarkHomeAndCreationVisualMatrix() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance)
            XCTAssertTrue(app.buttons["check-today"].firstMatch.waitForExistence(timeout: 15))
            capture("home-realistic-\(appearance)")
            app.buttons["create-habit"].firstMatch.tap()
            let name = app.textFields["habit-name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            app.segmentedControls["item-type-picker"].buttons["Habit"].tap()
            name.tap()
            name.typeText("Morning pages\n")
            XCTAssertTrue(app.descendants(matching: .any)["creation-preview"].firstMatch.label.contains("Morning pages"))
            capture("creation-\(appearance)")
            app.terminate()
        }
        let empty = launch("empty")
        XCTAssertTrue(empty.buttons["create-habit"].firstMatch.waitForExistence(timeout: 15))
        capture("home-empty-light")
        empty.terminate()
        let crowded = launch("crowded")
        XCTAssertTrue(crowded.buttons["check-today"].firstMatch.waitForExistence(timeout: 15))
        capture("home-crowded-light")
    }
}
