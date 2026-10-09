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
        let edit = card.buttons["edit-habit"].firstMatch
        let check = card.buttons["check-today"].firstMatch
        for button in [name, edit, check] {
            if let app { reveal(button, in: app) }
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.width + 0.001, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height + 0.001, 44)
            XCTAssertFalse(button.label.isEmpty)
        }
        XCTAssertFalse(name.frame.intersects(check.frame))
        XCTAssertFalse(name.frame.intersects(edit.frame))
        XCTAssertFalse(edit.frame.intersects(check.frame))
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
        for history in [card.buttons["habit-name"].firstMatch,
                        card.descendants(matching: .any)["habit-history"].firstMatch] {
            history.tap()
            XCTAssertTrue(app.buttons["backfill-close"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["history-previous-month"].exists)
            app.buttons["backfill-close"].tap()
            XCTAssertTrue(check.waitForExistence(timeout: 5))
            XCTAssertEqual(check.label, before)
            XCTAssertFalse(app.buttons["undo-action"].exists)
        }
        card.buttons["edit-habit"].firstMatch.tap()
        let field = app.textFields["habit-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Read for twenty minutes")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        XCTAssertEqual(check.label, before)
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
            selectTab("More", in: app)
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
            app.buttons["close-more-sheet"].tap()
            selectTab("Habits", in: app)
            let card = firstCard(app)
            assertIndependentTargets(card)
            let check = card.buttons["check-today"].firstMatch
            let before = check.label
            card.buttons["habit-name"].firstMatch.tap()
            XCTAssertTrue(app.buttons["backfill-close"].waitForExistence(timeout: 5))
            app.buttons["backfill-close"].tap()
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
        card.buttons["habit-name"].firstMatch.tap()
        XCTAssertTrue(app.buttons["backfill-close"].waitForExistence(timeout: 5))
        app.buttons["backfill-close"].tap()
        XCTAssertEqual(check.label, before)
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
