import XCTest

@MainActor
final class StatsProductUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(largeText: Bool = false, rtl: Bool = false,
                        appearance: String = "light", pro: Bool = true,
                        customCards: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-design-fixture", "crowded", "-screen", "stats",
                               "-pro", pro ? "on" : "off", "-design-appearance", appearance,
                               "-AppleLanguages", rtl ? "(ar)" : "(en)",
                               "-AppleLocale", rtl ? "ar_SA" : "en_GB"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        if customCards { app.launchArguments += ["-seed-stats"] }
        app.launch()
        XCTAssertTrue(element("stats-today-summary", app).waitForExistence(timeout: 15))
        return app
    }

    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func reveal(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        let target = element(id, app)
        for _ in 0..<25 where !target.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(target.isHittable, id)
        return target
    }

    func testTodayAndWeeklyDetailsPreserveSummaryValues() {
        let app = launch()
        let today = element("stats-today-summary", app)
        let todayValue = today.value as? String
        XCTAssertNotNil(todayValue)
        XCTAssertFalse(element("stats-today-explanation", app).exists)
        reveal("stats-today-details", app).tap()
        XCTAssertTrue(element("stats-today-explanation", app).waitForExistence(timeout: 3))
        XCTAssertEqual(today.value as? String, todayValue)
        reveal("stats-today-details", app).tap()
        XCTAssertFalse(element("stats-today-explanation", app).exists)

        let week = reveal("stats-week-card", app)
        let weekValue = week.value as? String
        XCTAssertNotNil(weekValue)
        XCTAssertFalse(element("stats-week-explanation", app).exists)
        reveal("stats-week-details", app).tap()
        XCTAssertTrue(element("stats-week-explanation", app).waitForExistence(timeout: 3))
        XCTAssertEqual(week.value as? String, weekValue)
        reveal("stats-week-details", app).tap()
        XCTAssertFalse(element("stats-week-explanation", app).exists)
    }

    func testOptionalReadingExpandsWithoutStartingGenerationOrChangingStatistics() {
        let app = launch()
        let weekValue = reveal("stats-week-card", app).value as? String
        XCTAssertFalse(element("stats-reading-action", app).exists)
        reveal("stats-reading-toggle", app).tap()
        XCTAssertTrue(element("stats-reading-action", app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["stats-reading-action"].isEnabled)
        reveal("stats-reading-toggle", app).tap()
        XCTAssertFalse(element("stats-reading-action", app).exists)
        app.open(URL(string: "haiity://stats")!)
        for _ in 0..<25 where !element("stats-today-summary", app).isHittable { app.swipeDown(velocity: .slow) }
        XCTAssertEqual(reveal("stats-week-card", app).value as? String, weekValue)
    }

    func testPerHabitExplanationPreservesRateAndRowOpensNativeHistory() {
        let app = launch()
        let row = reveal("stats-row", app)
        let originalValue = row.value as? String
        for _ in 0..<5 where !element("stats-habit-details", app).isHittable { app.swipeDown(velocity: .slow) }
        let details = element("stats-habit-details", app)
        XCTAssertTrue(details.isHittable)
        details.tap()
        XCTAssertTrue(element("stats-habit-explanation", app).waitForExistence(timeout: 3))
        XCTAssertEqual(row.value as? String, originalValue)
        reveal("stats-row", app).tap()
        let history = element("habit-history", app)
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        for _ in 0..<5 where !history.isHittable { app.swipeUp(velocity: .slow) }
        history.tap()
        XCTAssertTrue(app.buttons["backfill-close"].waitForExistence(timeout: 5))
    }

    func testCustomMetricSelectionRemainsAvailableAfterPrimarySections() {
        let app = launch(customCards: true)
        for card in ["streakFlame", "todayRing", "weekMomentum", "totals"] {
            XCTAssertTrue(reveal("stats-card-\(card)", app).exists)
        }
        XCTAssertTrue(element("stats-rhythm-card", app).exists)
    }

    func testAX5WeeklySummaryAndDetailsRemainReachableInRTLAndBothAppearances() {
        for appearance in ["light", "dark"] {
            let app = launch(largeText: true, rtl: true, appearance: appearance)
            let week = reveal("stats-week-card", app)
            XCTAssertLessThanOrEqual(week.frame.width, app.frame.width)
            let before = week.value as? String
            let details = reveal("stats-week-details", app)
            XCTAssertGreaterThanOrEqual(details.frame.height, 44)
            details.tap()
            XCTAssertTrue(element("stats-week-explanation", app).waitForExistence(timeout: 3))
            XCTAssertEqual(week.value as? String, before)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "stats-product-AX5-RTL-\(appearance)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }

    func testFreeTierKeepsWeeklySummaryAndExistingDetailsGate() {
        let app = launch(pro: false)
        XCTAssertTrue(reveal("stats-week-card", app).exists)
        XCTAssertTrue(reveal("stats-pro-lock", app).exists)
        XCTAssertFalse(element("stats-row", app).exists)
        for _ in 0..<5 where !app.buttons["stats-adjustments"].isHittable { app.swipeDown(velocity: .slow) }
        app.buttons["stats-adjustments"].tap()
        XCTAssertFalse(app.switches["stats-adjustment-yearPulse"].exists)
        XCTAssertTrue(app.buttons["paywall-purchase"].waitForExistence(timeout: 5))
    }
}
