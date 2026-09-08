import XCTest

@MainActor
final class TodayProgressUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(_ fixture: String = "realistic", largeText: Bool = false,
                        appearance: String = "light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-design-fixture", fixture, "-screen", "habits", "-pro", "on",
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

    func testVisibleHistoryAndEditOpenWithoutLongPress() {
        let app = launch()
        let history = app.buttons["habit-history"].firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 15))
        XCTAssertTrue(history.isHittable)
        history.tap()
        XCTAssertTrue(app.buttons["backfill-close"].waitForExistence(timeout: 5))
        capture("history-from-visible-action")
        app.buttons["backfill-close"].tap()
        app.buttons["edit-habit"].firstMatch.tap()
        XCTAssertTrue(app.textFields["habit-name"].waitForExistence(timeout: 5))
        capture("edit-from-visible-action")
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
