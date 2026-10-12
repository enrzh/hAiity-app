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
                               "-seed-stats",
                               "-AppleLanguages", rtl ? "(ar)" : "(en)",
                               "-AppleLocale", rtl ? "ar_SA" : "en_GB"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(element("stats-week-card", app).waitForExistence(timeout: 15))
        if pro && !customCards { selectCards(["yearPulse", "totals"], app, rtl: rtl) }
        return app
    }

    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func selectTab(_ title: String, _ app: XCUIApplication) {
        let tab = app.tabBars.buttons[title].firstMatch
        if !tab.exists {
            let collapsed = app.tabBars.buttons.matching(NSPredicate(format: "value == 'Collapsed'")).firstMatch
            if collapsed.exists { collapsed.tap() }
        }
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
    }

    private func reveal(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        let target = element(id, app)
        for _ in 0..<25 where !target.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(target.isHittable, id)
        return target
    }

    private func selectCards(_ cards: [String], _ app: XCUIApplication, rtl: Bool = false) {
        for _ in 0..<25 where !app.buttons["stats-adjustments"].isHittable { app.swipeDown(velocity: .slow) }
        app.buttons["stats-adjustments"].tap()
        let all = ["yearPulse", "streakFlame", "todayRing", "weekMomentum", "totals"]
        for card in all {
            let toggle = app.switches["stats-adjustment-\(card)"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 3))
            revealToggle(toggle, in: app)
            if toggle.value as? String == "1" {
                toggle.coordinate(withNormalizedOffset: CGVector(dx: rtl ? 0.1 : 0.9, dy: 0.5)).tap()
                XCTAssertEqual(toggle.value as? String, "0")
            }
        }
        for card in cards {
            let toggle = app.switches["stats-adjustment-\(card)"]
            let first = app.switches["stats-adjustment-yearPulse"]
            for _ in 0..<10 where !first.isHittable { app.swipeDown(velocity: .slow) }
            revealToggle(toggle, in: app)
            toggle.coordinate(withNormalizedOffset: CGVector(dx: rtl ? 0.1 : 0.9, dy: 0.5)).tap()
            XCTAssertEqual(toggle.value as? String, "1")
        }
        app.buttons["stats-adjustments-done"].tap()
        XCTAssertFalse(app.switches["stats-adjustment-yearPulse"].exists)
    }

    private func revealToggle(_ toggle: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<20 {
            let top = app.navigationBars.firstMatch.frame.maxY + 8
            if toggle.exists, toggle.isHittable,
               toggle.frame.midY > top, toggle.frame.midY < app.frame.maxY - 80 { break }
            if toggle.exists, toggle.frame.midY <= top { app.swipeDown(velocity: .slow) }
            else { app.swipeUp(velocity: .slow) }
        }
        XCTAssertTrue(toggle.isHittable)
    }

    func testProgressLeadsWithWeeklyResultThenSelectedMetricsThenHabits() {
        let app = launch()
        let week = element("stats-week-card", app)
        XCTAssertTrue(week.isHittable)
        XCTAssertTrue(app.staticTexts["Progress"].exists)
        XCTAssertFalse(element("stats-today-summary", app).exists)
        XCTAssertFalse(element("stats-card-todayRing", app).exists)
        let rhythm = reveal("stats-rhythm-card", app)
        XCTAssertLessThan(week.frame.minY, rhythm.frame.minY)
        let totals = reveal("stats-card-totals", app)
        let row = reveal("stats-row", app)
        XCTAssertLessThan(totals.frame.minY, row.frame.minY)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "stats-weekly-first"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testWeeklyDetailsPreserveSummaryValues() {
        let app = launch()
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
        XCTAssertFalse(app.staticTexts["Thinking…"].exists)
        reveal("stats-reading-toggle", app).tap()
        XCTAssertFalse(element("stats-reading-action", app).exists)
        app.open(URL(string: "haiity://stats")!)
        for _ in 0..<25 where !element("stats-week-card", app).isHittable { app.swipeDown(velocity: .slow) }
        XCTAssertEqual(reveal("stats-week-card", app).value as? String, weekValue)
    }

    func testPerHabitExplanationPreservesRateAndRowOpensDetails() {
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
        XCTAssertTrue(element("habit-detail", app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["backfill-close"].exists)
        reveal("open-habit-history", app).tap()
        XCTAssertTrue(app.buttons["backfill-close"].waitForExistence(timeout: 5))
    }

    func testAllFiveChoicesRemainBeforeHabitsWithOnlyOneWeeklyResult() {
        let app = launch(customCards: true)
        let rhythm = reveal("stats-rhythm-card", app)
        XCTAssertTrue((rhythm.value as? String)?.contains("20 weeks") == true)
        for card in ["streakFlame", "todayRing", "weekMomentum", "totals"] {
            XCTAssertTrue(reveal("stats-card-\(card)", app).exists)
        }
        XCTAssertTrue(element("stats-rhythm-card", app).exists)
        XCTAssertEqual(element("stats-card-todayRing", app).value as? String, "8/12")
        XCTAssertEqual(element("stats-card-weekMomentum", app).value as? String, "In the weekly summary")
        let totals = reveal("stats-card-totals", app)
        let row = reveal("stats-row", app)
        XCTAssertLessThan(totals.frame.minY, row.frame.minY)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "stats-week-card").count, 1)
        XCTAssertFalse(element("stats-today-summary", app).exists)
    }

    func testEmptySelectionStaysEmptyWhileWeeklyResultAndHabitsRemain() {
        let app = launch()
        selectCards([], app)
        XCTAssertTrue(element("stats-week-card", app).exists)
        XCTAssertFalse(element("stats-metrics", app).exists)
        XCTAssertFalse(element("stats-rhythm-card", app).exists)
        XCTAssertFalse(element("stats-card-todayRing", app).exists)
        XCTAssertTrue(reveal("stats-row", app).exists)
        selectTab("Habits", app)
        selectTab("Progress", app)
        XCTAssertFalse(element("stats-metrics", app).exists)
    }

    func testCustomOrderIncludesRhythmAtItsSavedPositionAndSurvivesNavigation() {
        let app = launch()
        selectCards(["todayRing", "totals", "yearPulse", "weekMomentum", "streakFlame"], app)
        let ids = ["stats-card-todayRing", "stats-card-totals", "stats-rhythm-card",
                   "stats-card-weekMomentum", "stats-card-streakFlame", "stats-row"]
        for pair in zip(ids, ids.dropFirst()) {
            let first = reveal(pair.0, app)
            let second = reveal(pair.1, app)
            XCTAssertLessThan(first.frame.minY, second.frame.minY, "\(pair.0) precedes \(pair.1)")
        }
        selectTab("Habits", app)
        selectTab("Progress", app)
        for _ in 0..<25 where !element(ids[0], app).isHittable { app.swipeDown(velocity: .slow) }
        XCTAssertEqual(reveal(ids[0], app).value as? String, "8/12")
        XCTAssertFalse(element("stats-today-summary", app).exists)
    }

    func testDirectHistoryActionOpensFullHistoryWithoutOpeningDetails() {
        let app = launch()
        reveal("stats-history-00000000-0000-0000-0000-000000000700", app).tap()
        XCTAssertTrue(app.buttons["backfill-close"].waitForExistence(timeout: 5))
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
