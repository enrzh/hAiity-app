import XCTest

@MainActor
final class HabitCardProductUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(style: String = "quiet", accessibleRTL: Bool = false,
                        fixture: String = "realistic") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-design-fixture", fixture, "-screen", "habits", "-pro", "on",
                               "-design-style", style, "-design-appearance", "light",
                               "-AppleLanguages", accessibleRTL ? "(ar)" : "(en)",
                               "-AppleLocale", accessibleRTL ? "ar_SA" : "en_GB"]
        if accessibleRTL {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<16 where !element.isHittable {
            if element.exists && element.frame.maxY < app.navigationBars.firstMatch.frame.maxY {
                app.swipeDown(velocity: .slow)
            } else {
                app.swipeUp(velocity: .slow)
            }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
    }

    private func firstCard(_ app: XCUIApplication) -> XCUIElement {
        let card = app.descendants(matching: .any)["habit-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        return card
    }

    private func selectTab(_ title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[title].firstMatch
        if !tab.exists {
            let collapsed = app.tabBars.buttons.matching(NSPredicate(format: "value == 'Collapsed'")).firstMatch
            if collapsed.exists { collapsed.tap() }
        }
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
    }

    private func assertIndependentTargets(_ card: XCUIElement, in app: XCUIApplication? = nil) {
        let name = card.buttons["habit-name"].firstMatch
        let check = card.buttons["check-today"].firstMatch
        for button in [name, check] {
            if let app { reveal(button, in: app) }
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.width + 0.001, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height + 0.001, 44)
            XCTAssertFalse(button.label.isEmpty)
        }
        XCTAssertFalse(name.frame.intersects(check.frame))
        XCTAssertFalse(card.buttons["edit-habit"].exists, "Editing belongs in details")
        XCTAssertFalse(card.buttons["open-habit-history"].exists, "The graph opens full history directly")
    }

    private func openDetails(_ name: XCUIElement, in app: XCUIApplication) {
        name.tap()
        XCTAssertTrue(app.buttons["edit-habit"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["habit-detail"].firstMatch.exists)
        XCTAssertFalse(app.buttons["backfill-close"].exists, "The name opens details, not the history sheet")
        XCTAssertFalse(app.textFields["habit-name"].exists, "Opening details must not start editing")
    }

    private func returnToCollection(in app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.isHittable)
        back.tap()
        _ = firstCard(app)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNameGraphAndVisibleEditOpenTheirOwnRoutesWithoutCheckingOff() {
        let app = launch()
        let card = firstCard(app)
        assertIndependentTargets(card)
        let check = card.buttons["check-today"].firstMatch
        let before = check.label
        openDetails(card.buttons["habit-name"].firstMatch, in: app)
        XCTAssertFalse(app.buttons["undo-action"].exists)
        app.buttons["edit-habit"].firstMatch.tap()
        let field = app.textFields["habit-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Read for twenty minutes")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["edit-habit"].firstMatch.waitForExistence(timeout: 5))
        returnToCollection(in: app)
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        XCTAssertEqual(check.label, before)
        card.descendants(matching: .any)["habit-history"].firstMatch.tap()
        XCTAssertTrue(app.buttons["backfill-close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["history-previous-month"].exists)
        app.buttons["backfill-close"].tap()
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        XCTAssertEqual(check.label, before)
        XCTAssertFalse(app.buttons["undo-action"].exists)
        let grid = card.descendants(matching: .any)["contribution-grid"].firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        let graphBefore = grid.label
        check.tap()
        expectation(for: NSPredicate(format: "label != %@", graphBefore), evaluatedWith: grid)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(check.label.contains("Done"))
        app.buttons["undo-action"].tap()
        expectation(for: NSPredicate(format: "label == %@", graphBefore), evaluatedWith: grid)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(check.label, before)
        capture("habit-card-independent-routes-and-undo")
    }

    func testCompactPreferenceKeepsTodayNameAndEditSeparateAcrossAllStyles() {
        for style in ["native", "quiet", "focus", "studio"] {
            let app = launch(style: style)
            _ = firstCard(app)
            app.open(URL(string: "haiity://more")!)
            let appearance = app.buttons["open-appearance"].firstMatch
            reveal(appearance, in: app)
            appearance.tap()
            let customize = app.descendants(matching: .any)["appearance-customize"].buttons.firstMatch
            reveal(customize, in: app)
            customize.tap()
            let compact = app.switches["compact-mode-toggle"].firstMatch
            reveal(compact, in: app)
            if compact.value as? String == "0" {
                compact.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            }
            XCTAssertEqual(compact.value as? String, "1")
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.buttons["close-more-sheet"].waitForExistence(timeout: 5))
            app.buttons["close-more-sheet"].tap()
            selectTab("Habits", in: app)
            let card = firstCard(app)
            assertIndependentTargets(card)
            let check = card.buttons["check-today"].firstMatch
            let before = check.label
            openDetails(card.buttons["habit-name"].firstMatch, in: app)
            returnToCollection(in: app)
            XCTAssertEqual(check.label, before)
            check.tap()
            XCTAssertTrue(app.buttons["undo-action"].waitForExistence(timeout: 5))
            XCTAssertNotEqual(check.label, before)
            app.buttons["undo-action"].tap()
            XCTAssertEqual(check.label, before)
            let graph = card.descendants(matching: .any)["contribution-grid"].firstMatch
            XCTAssertLessThan(graph.frame.height, 220)
            capture("habit-card-compact-\(style)")
            app.terminate()
        }
    }

    func testQuantityIncrementAndUndoRetainExactValueWithoutOpeningHistory() {
        let app = launch()
        _ = firstCard(app)
        let card = app.descendants(matching: .any).matching(identifier: "habit-card").element(boundBy: 1)
        reveal(card.buttons["check-today"].firstMatch, in: app)
        let check = card.buttons["check-today"].firstMatch
        let before = check.label
        XCTAssertTrue(before.contains("1"))
        check.tap()
        XCTAssertTrue(app.buttons["undo-action"].waitForExistence(timeout: 5))
        XCTAssertTrue(check.label.contains("2"))
        XCTAssertFalse(app.buttons["backfill-close"].exists)
        app.buttons["undo-action"].tap()
        XCTAssertEqual(check.label, before)
        openDetails(card.buttons["habit-name"].firstMatch, in: app)
        returnToCollection(in: app)
        XCTAssertEqual(check.label, before)
    }

    func testReminderNameOpensDetailsIndependentlyOfCompletionAndPreview() {
        let app = launch(fixture: "mixed")
        _ = firstCard(app)
        let id = "00000000-0000-0000-0000-000000000799"
        let name = app.buttons["reminder-name-\(id)"].firstMatch
        let check = app.buttons["reminder-check-\(id)"].firstMatch
        reveal(name, in: app)
        reveal(check, in: app)
        for button in [name, check] {
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.width + 0.001, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height + 0.001, 44)
        }
        XCTAssertFalse(name.frame.intersects(check.frame))
        XCTAssertFalse(app.buttons["reminder-edit-\(id)"].exists)
        let before = check.value as? String
        openDetails(name, in: app)
        app.buttons["edit-habit"].firstMatch.tap()
        XCTAssertTrue(app.textFields["habit-name"].waitForExistence(timeout: 5))
        XCTAssertTrue((app.textFields["habit-name"].value as? String)?.hasPrefix("Call the dentist") == true)
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["edit-habit"].firstMatch.waitForExistence(timeout: 5))
        returnToCollection(in: app)
        reveal(check, in: app)
        XCTAssertEqual(check.value as? String, before)
        XCTAssertFalse(app.buttons["undo-action"].exists)
    }

    func testTodayAndSearchCompactRowsShareCheckOffUndoAndDetailNavigation() {
        let id = "00000000-0000-0000-0000-000000000700"
        for tab in ["Today", "Search"] {
            let app = launch()
            _ = firstCard(app)
            selectTab(tab, in: app)
            if tab == "Search" {
                let field = app.searchFields.firstMatch
                XCTAssertTrue(field.waitForExistence(timeout: 5))
                field.tap()
                field.typeText("Read for twenty minutes")
            }
            let identifier = tab == "Today" ? "today-row-\(id)" : "search-result-\(id)"
            let row = app.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            let name = row.buttons["item-details-\(id)"].firstMatch
            let check = row.buttons["check-today"].firstMatch
            XCTAssertTrue(name.isHittable)
            XCTAssertTrue(check.isHittable)
            XCTAssertFalse(name.frame.intersects(check.frame))
            XCTAssertFalse(row.descendants(matching: .any)["contribution-grid"].exists)
            for button in [name, check] {
                XCTAssertGreaterThanOrEqual(button.frame.width + 0.001, 44)
                XCTAssertGreaterThanOrEqual(button.frame.height + 0.001, 44)
            }
            let before = check.label
            check.tap()
            XCTAssertTrue(app.buttons["undo-action"].waitForExistence(timeout: 5))
            XCTAssertNotEqual(check.label, before)
            app.buttons["undo-action"].tap()
            XCTAssertEqual(check.label, before)
            openDetails(name, in: app)
            XCTAssertFalse(app.buttons["undo-action"].exists)
            app.terminate()
        }
    }

    func testLargestRTLTextKeepsActionsReachableAndGraphBounded() {
        let app = launch(accessibleRTL: true)
        let card = app.descendants(matching: .any).matching(identifier: "habit-card")
            .containing(.button, identifier: "Read for twenty minutes").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        reveal(card.buttons["check-today"].firstMatch, in: app)
        assertIndependentTargets(card, in: app)
        let name = card.buttons["habit-name"].firstMatch
        XCTAssertEqual(name.label, "Read for twenty minutes")
        let graph = card.descendants(matching: .any)["habit-history"].firstMatch
        reveal(graph, in: app)
        // Labels grow with Dynamic Type while tiles keep their readable measured pitch.
        XCTAssertLessThan(graph.frame.height, 300)
        capture("habit-card-rtl-ax5")
        graph.tap()
        XCTAssertTrue(app.buttons["backfill-close"].waitForExistence(timeout: 5))
    }

    func testNativeLongPressPreviewRemainsAnOptionalEditShortcut() {
        let app = launch()
        let card = firstCard(app)
        card.descendants(matching: .any)["habit-history"].firstMatch.press(forDuration: 1)
        let preview = app.otherElements["Preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.tap()
        XCTAssertTrue(app.textFields["habit-name"].waitForExistence(timeout: 5))
    }

    func testFirstHabitShowsARecentWindowAndItsFirstCompletedSquare() {
        let app = launch(fixture: "empty")
        let create = app.buttons["add-first-habit"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        create.tap()
        let name = app.textFields["habit-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Read a page\n")
        app.buttons["save-habit"].tap()
        let card = firstCard(app)
        assertIndependentTargets(card)
        let graph = card.descendants(matching: .any)["contribution-grid"].firstMatch
        XCTAssertTrue(graph.waitForExistence(timeout: 5))
        let weeks = Int(floor((graph.frame.width + 3) / 15))
        XCTAssertTrue(graph.label.contains("\(weeks) weeks"))
        XCTAssertLessThan(graph.frame.height, 220)
        card.buttons["check-today"].firstMatch.tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "1 days"), evaluatedWith: graph)
        waitForExpectations(timeout: 5)
        capture("habit-card-first-completed-square")
    }
}
