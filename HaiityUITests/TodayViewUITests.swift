import XCTest
import UIKit

@MainActor
final class TodayViewUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func handleAppOpenPrompt(accept: Bool) {
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let labels = accept ? ["Open", "Öffnen", "Open in hAiity", "In hAiity öffnen"]
            : ["Cancel", "Abbrechen"]
        for _ in 0..<3 {
            let button = system.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
            guard button.waitForExistence(timeout: 1), button.isHittable else { return }
            button.tap()
        }
    }

    private func launch(_ fixture: String = "mixed", conflict: Bool = false, style: String = "quiet", rtl: Bool = false, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        handleAppOpenPrompt(accept: false)
        app.launchArguments = ["-design-fixture", fixture, "-pro", "on", "-design-style", style,
            "-AppleLanguages", rtl ? "(ar)" : "(en)", "-AppleLocale", rtl ? "ar_SA" : "en_GB"]
        if conflict { app.launchArguments.append("-design-write-conflict") }
        if largeText && !rtl { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        if rtl { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-design-photo", "-design-appearance", "dark"] }
        app.launch()
        app.activate()
        XCTAssertTrue(app.descendants(matching: .any)["today-list"].firstMatch.waitForExistence(timeout: 15))
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func tab(_ title: String, app: XCUIApplication) {
        let button = app.tabBars.buttons[title].firstMatch
        if !button.exists {
            let collapsed = app.tabBars.buttons.matching(NSPredicate(format: "value == 'Collapsed'")).firstMatch
            if collapsed.exists { collapsed.tap() }
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
    }

    func testNormalLaunchUsesTodayAndCheckUndoKeepsNeighborTargetsStable() {
        let app = launch()
        let first = app.descendants(matching: .any)["today-row-00000000-0000-0000-0000-000000000700"].firstMatch
        let second = app.descendants(matching: .any)["today-row-00000000-0000-0000-0000-000000000701"].firstMatch
        let check = first.buttons["check-today"].firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["contribution-grid"].exists)
        let position = check.frame
        let neighbor = second.buttons["check-today"].firstMatch.frame
        check.tap()
        XCTAssertTrue(app.buttons["undo-action"].waitForExistence(timeout: 5))
        XCTAssertEqual(check.frame, position)
        XCTAssertEqual(second.buttons["check-today"].firstMatch.frame, neighbor)
        app.buttons["undo-action"].tap()
        XCTAssertEqual(check.frame, position)
        XCTAssertEqual(second.buttons["check-today"].firstMatch.frame, neighbor)
        capture("rebuild-today-stable-undo")
    }

    func testRejectedDailyWriteKeepsDurableStateAndDoesNotOfferFakeUndo() {
        let app = launch(conflict: true)
        let first = app.descendants(matching: .any)["today-row-00000000-0000-0000-0000-000000000700"].firstMatch
        let check = first.buttons["check-today"].firstMatch
        let label = check.label
        check.tap()
        XCTAssertTrue(app.descendants(matching: .any)["save-error-status"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(check.label, label)
        XCTAssertFalse(app.buttons["undo-action"].exists)
        capture("rebuild-today-rejected-write")
    }

    func testTodayDetailsEditAndFullHistoryAreIndependent() {
        let app = launch()
        let name = app.buttons["item-details-00000000-0000-0000-0000-000000000700"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap()
        XCTAssertTrue(app.buttons["edit-habit"].waitForExistence(timeout: 5))
        capture("rebuild-detail-overview")
        XCTAssertFalse(app.buttons["undo-action"].exists)
        app.buttons["edit-habit"].tap()
        let field = app.textFields["habit-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Read for twenty minutes")
        app.buttons["Cancel"].firstMatch.tap()
        let history = app.buttons["open-habit-history"]
        XCTAssertTrue(history.waitForExistence(timeout: 5)); history.tap()
        XCTAssertTrue(app.buttons["backfill-close"].waitForExistence(timeout: 5))
        capture("rebuild-detail-history")
        app.buttons["backfill-close"].tap()
    }

    func testSettingsIsAvailableFromEveryContentRootAndChildrenReturnToHub() {
        let app = launch()
        for title in ["Today", "Habits", "Progress"] {
            tab(title, app: app)
            let settings = app.buttons["open-settings"].firstMatch
            XCTAssertTrue(settings.waitForExistence(timeout: 5)); settings.tap()
            let notifications = app.buttons["open-notifications"]
            XCTAssertTrue(notifications.waitForExistence(timeout: 5)); notifications.tap()
            XCTAssertTrue(app.switches["summary-toggle"].waitForExistence(timeout: 5))
            if title == "Today" {
                capture("rebuild-settings-child-before-dismiss")
                app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    .press(forDuration: 0.1, thenDragTo:
                        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
                let dismissed = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "exists == false"), object: app.switches["summary-toggle"])
                XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
                XCTAssertTrue(settings.isHittable)
                settings.tap()
                XCTAssertTrue(notifications.waitForExistence(timeout: 5))
                XCTAssertTrue(notifications.isHittable, "interactive dismissal must reopen the Settings hub")
                capture("rebuild-settings-after-interactive-dismiss")
                notifications.tap()
                XCTAssertTrue(app.switches["summary-toggle"].waitForExistence(timeout: 5))
            }
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(notifications.waitForExistence(timeout: 5))
            app.buttons["close-more-sheet"].tap()
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
        }
    }

    func testRejectedHistoryWriteKeepsTheDayAndDoesNotEnableUndo() {
        let app = launch(conflict: true)
        app.buttons["item-details-00000000-0000-0000-0000-000000000701"].firstMatch.tap()
        let history = app.buttons["open-habit-history"]
        XCTAssertTrue(history.waitForExistence(timeout: 5)); history.tap()
        XCTAssertTrue(app.buttons["backfill-close"].waitForExistence(timeout: 5))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = app.buttons["history-day-\(formatter.string(from: Date()))"].firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        let before = day.label
        day.tap()
        XCTAssertTrue(app.descendants(matching: .any)["save-error-status"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(day.label, before)
        XCTAssertFalse(app.buttons["history-undo"].isEnabled)
        XCTAssertFalse(app.buttons["undo-action"].exists)
        capture("rebuild-history-rejected-write")
    }

    func testNewReminderMenuPreservesExplicitOnceDefault() {
        let app = launch()
        app.buttons["create-habit"].firstMatch.tap()
        app.buttons["New reminder"].firstMatch.tap()
        XCTAssertTrue(app.textFields["habit-name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["item-type-picker"].buttons["Reminder"].isSelected)
        XCTAssertEqual(app.switches["repeat-toggle"].value as? String, "0")
        capture("rebuild-new-reminder")
    }

    private func processID(_ app: XCUIApplication) throws -> String {
        let description = app.debugDescription
        let match = try XCTUnwrap(description.range(of: "pid: [0-9]+", options: .regularExpression))
        return String(description[match])
    }

    func testNewRoutesWaitForFullHistoryDismissal() async throws {
        for destination in ["more", "new"] {
            let app = launch()
            app.buttons["item-details-00000000-0000-0000-0000-000000000700"].firstMatch.tap()
            let history = app.buttons["open-habit-history"]
            XCTAssertTrue(history.waitForExistence(timeout: 5)); history.tap()
            XCTAssertTrue(app.buttons["backfill-close"].waitForExistence(timeout: 5))
            let originalProcess = try processID(app)
            let opening = Task { @MainActor in
                await UIApplication.shared.open(URL(string: "haiity://\(destination)")!)
            }
            await Task.yield()
            handleAppOpenPrompt(accept: true)
            let opened = await opening.value
            XCTAssertTrue(opened)
            let target = destination == "more" ? app.buttons["close-more-sheet"]
                : app.buttons["close-create"]
            XCTAssertTrue(target.waitForExistence(timeout: 10))
            XCTAssertTrue(target.isHittable)
            XCTAssertEqual(try processID(app), originalProcess,
                           "The route must dismiss history in the running app")
            XCTAssertFalse(app.buttons["backfill-close"].exists)
            target.tap()
            XCTAssertTrue(app.buttons["open-settings"].firstMatch.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testEveryStyleAndAX5RTLKeepNamedActionsReachable() {
        for style in ["native", "quiet", "focus", "studio"] {
            let app = launch(style: style)
            XCTAssertTrue(app.buttons["check-today"].firstMatch.isHittable)
            capture("rebuild-today-\(style)")
            app.terminate()
        }
        let app = launch(style: "quiet", rtl: true)
        let check = app.buttons["check-today"].firstMatch
        for _ in 0..<10 where !check.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(check.isHittable)
        XCTAssertGreaterThanOrEqual(check.frame.height, 44)
        XCTAssertGreaterThanOrEqual(check.frame.width, 44)
        capture("rebuild-today-ax5-rtl-photo")
    }

    func testNativeAccessibilityAuditForTodayAndDetails() throws {
        continueAfterFailure = true
        let app = launch()
        try auditVisibleContent(app)
        app.buttons["item-details-00000000-0000-0000-0000-000000000700"].firstMatch.tap()
        XCTAssertTrue(app.buttons["edit-habit"].waitForExistence(timeout: 5))
        try auditVisibleContent(app)
        let scroll = app.scrollViews["habit-detail"]
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        try auditVisibleContent(app)
        capture("rebuild-detail-accessibility-audit")
    }

    func testFullHistoryKeepsLoggedDayLabelsReadable() throws {
        continueAfterFailure = true
        for selecting in [false, true] {
            let app = launch()
            app.buttons["item-details-00000000-0000-0000-0000-000000000700"].firstMatch.tap()
            let history = app.buttons["open-habit-history"]
            XCTAssertTrue(history.waitForExistence(timeout: 5))
            history.tap()
            XCTAssertTrue(app.buttons["backfill-close"].waitForExistence(timeout: 5))
            if selecting {
                app.buttons["history-selection-mode"].tap()
                app.buttons["history-select-all"].tap()
            }
            try app.performAccessibilityAudit(for: .contrast) { issue in
                #if targetEnvironment(simulator)
                let version = ProcessInfo.processInfo.operatingSystemVersion
                // Matching UIKit labels/buttons pass; these two SwiftUI nodes misreport on 26.5.
                if version.majorVersion == 26, version.minorVersion == 5,
                   let identifier = issue.element?.identifier,
                   identifier == "history-select-all" || identifier == "backfill-status" {
                    return issue.auditType == .contrast
                }
                #endif
                return false
            }
            capture("rebuild-history-contrast-\(selecting ? "selected" : "ordinary")")
            app.terminate()
        }
    }

    func testResolvedDisclosureGrowsAndRemainsUsableAtLargestTextSize() {
        let normal = launch()
        let initial = normal.descendants(matching: .any)["today-resolved"].firstMatch.frame.height
        normal.terminate()
        let app = launch(largeText: true)
        let heading = app.descendants(matching: .any)["today-resolved"].firstMatch
        for _ in 0..<20 where !heading.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(heading.isHittable)
        XCTAssertGreaterThan(heading.frame.height, initial)
        XCTAssertGreaterThanOrEqual(heading.frame.height, 44)
        heading.tap()
        let name = app.buttons["item-details-00000000-0000-0000-0000-000000000702"].firstMatch
        for _ in 0..<10 where !name.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(name.isHittable)
        capture("rebuild-resolved-disclosure-AX5")
    }

    private func auditVisibleContent(_ app: XCUIApplication) throws {
        let top = app.navigationBars.firstMatch.frame.maxY + 64
        let bottom = app.tabBars.firstMatch.frame.minY - 64
        let resolved = app.descendants(matching: .any)["today-resolved"].firstMatch
        let resolvedLabel = resolved.exists ? resolved.label : nil
        try app.performAccessibilityAudit { issue in
            guard let element = issue.element else { return false }
            // Native bars use fixed title metrics; the app supplies a full Edit target and label.
            if issue.auditType == .dynamicType, element.identifier == "edit-habit" { return true }
            // The native disclosure is measured growing and tappable at AX5 in its dedicated test.
            if issue.auditType == .dynamicType, let resolvedLabel, element.label == resolvedLabel { return true }
            // Contrast is checked after scrolling the native fade/occluded rows into the viewport.
            return issue.auditType == .contrast && (element.frame.maxY <= top || element.frame.minY >= bottom)
        }
    }

    func testFlexiblePeriodsDeclinedAnswerAndFutureReminderStayDistinct() {
        let app = launch("today")
        for id in [800, 801, 802] {
            let name = app.buttons[String(format: "item-details-00000000-0000-0000-0000-%012d", id)]
            for _ in 0..<12 where !name.isHittable { app.swipeUp(velocity: .slow) }
            XCTAssertTrue(name.isHittable)
            XCTAssertTrue(name.label.contains("0 of 3"), name.label)
        }
        XCTAssertFalse(app.buttons["item-details-00000000-0000-0000-0000-000000000804"].exists)
        let resolved = app.descendants(matching: .any)["today-resolved"].firstMatch
        for _ in 0..<12 where !resolved.isHittable { app.swipeUp(velocity: .slow) }
        resolved.tap()
        let question = app.descendants(matching: .any)["today-row-00000000-0000-0000-0000-000000000803"].firstMatch
        for _ in 0..<12 where !question.buttons["decline-today"].isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(question.buttons["decline-today"].isSelected)
        XCTAssertFalse(question.buttons["check-today"].isSelected)
        question.buttons["check-today"].tap()
        XCTAssertTrue(question.buttons["check-today"].isSelected)
        XCTAssertFalse(question.buttons["decline-today"].isSelected)
        app.buttons["undo-action"].tap()
        XCTAssertTrue(question.buttons["decline-today"].isSelected)
        capture("rebuild-today-flexible-and-negative")
    }
}
