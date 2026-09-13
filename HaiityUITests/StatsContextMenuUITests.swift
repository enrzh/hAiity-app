import XCTest
import UIKit

final class StatsContextMenuUITests: XCTestCase {
    private func brightnessVariation(of image: UIImage, in frame: CGRect) -> Double {
        guard let cgImage = image.cgImage,
              let provider = cgImage.dataProvider,
              let data = provider.data,
              let bytes = CFDataGetBytePtr(data) else { return 0 }

        let scale = image.scale
        let bounds = CGRect(x: 0, y: 0,
                            width: CGFloat(cgImage.width) / scale,
                            height: CGFloat(cgImage.height) / scale)
        let sample = frame.insetBy(dx: 12, dy: 12).intersection(bounds)
        let minX = max(0, Int(sample.minX * scale))
        let maxX = min(cgImage.width, Int(sample.maxX * scale))
        let minY = max(0, Int(sample.minY * scale))
        let maxY = min(cgImage.height, Int(sample.maxY * scale))
        let bytesPerPixel = max(1, cgImage.bitsPerPixel / 8)
        guard minX < maxX, minY < maxY else { return 0 }

        var values: [Double] = []
        for y in minY..<maxY {
            for x in minX..<maxX {
                let offset = y * cgImage.bytesPerRow + x * bytesPerPixel
                let channels = min(3, bytesPerPixel)
                let brightness = (0..<channels).reduce(0.0) {
                    $0 + Double(bytes[offset + $1])
                } / Double(channels)
                values.append(brightness)
            }
        }
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0.0) { partial, value in
            partial + pow(value - mean, 2)
        } / Double(values.count)
        return variance.squareRoot()
    }

    func testLongPressingSmallStatsTileKeepsItsSiblingsVisible() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "stats", "-pro", "on", "-seed-stats"]
        app.launch()

        let streak = app.descendants(matching: .any)["stats-card-streakFlame"].firstMatch
        let today = app.descendants(matching: .any)["stats-card-todayRing"]
        let week = app.descendants(matching: .any)["stats-card-weekMomentum"]
        let totals = app.descendants(matching: .any)["stats-card-totals"]

        XCTAssertTrue(streak.waitForExistence(timeout: 10))
        XCTAssertTrue(today.waitForExistence(timeout: 2))
        XCTAssertTrue(week.waitForExistence(timeout: 2))
        XCTAssertTrue(totals.waitForExistence(timeout: 2))

        // UIKit temporarily reports a zero accessibility frame for siblings
        // while its context-menu dimming view is active. Keep the frame from
        // the rendered state so the assertion checks pixels, not that UIKit
        // bookkeeping detail.
        let totalsFrame = totals.frame
        XCTAssertGreaterThan(totalsFrame.width, 0)
        XCTAssertGreaterThan(totalsFrame.height, 0)

        streak.press(forDuration: 1.0)

        XCTAssertTrue(app.buttons["Statistik anpassen"].waitForExistence(timeout: 3))
        let screen = XCUIScreen.main.screenshot()
        XCTAssertGreaterThan(brightnessVariation(of: screen.image, in: totalsFrame), 12,
                             "The sibling total tile must remain rendered while another tile is enlarged")
        let screenshot = XCTAttachment(screenshot: screen)
        screenshot.name = "stats-small-tile-context-menu"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        try? screen.image.pngData()?.write(to: URL(fileURLWithPath: "/tmp/haiity-stats-context-runtime.png"))
        XCTAssertTrue(today.exists)
        XCTAssertTrue(week.exists)
        XCTAssertTrue(totals.exists)
    }

    func testLongPressingPerHabitStatsRowCapturesItsCardBoundary() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "stats", "-pro", "on", "-seed-stats"]
        app.launch()

        let row = app.descendants(matching: .any)["stats-row"].firstMatch
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 10))
        for _ in 0..<8 where !row.exists {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let rowFrame = row.frame
        XCTAssertGreaterThan(rowFrame.width, 0)
        XCTAssertGreaterThan(rowFrame.height, 0)

        row.press(forDuration: 1.0)

        XCTAssertTrue(app.buttons["Statistik anpassen"].waitForExistence(timeout: 3))
        let preview = app.descendants(matching: .any)["stats-preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 2),
                      "The enlarged preview must expose its own card boundary")
        let previewFrame = preview.frame
        // UIKit can report the source row's inner content width after the
        // scroll, while the lifted preview reports the full card boundary.
        XCTAssertGreaterThanOrEqual(previewFrame.width, rowFrame.width)
        XCTAssertGreaterThan(previewFrame.height, 0)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "stats-per-habit-context-menu"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        try? XCUIScreen.main.screenshot().image.pngData()?.write(
            to: URL(fileURLWithPath: "/tmp/haiity-stats-per-habit-context-runtime.png"))
    }

    func testLongPressingGitHubGraphShowsItsReadablePreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "habits", "-demo-github-card", "-pro",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
        app.launch()

        let graph = app.descendants(matching: .any)["github-grid"].firstMatch
        XCTAssertTrue(graph.waitForExistence(timeout: 10))

        graph.press(forDuration: 1.0)

        let openProfile = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'GitHub'")
        ).firstMatch
        XCTAssertTrue(openProfile.waitForExistence(timeout: 3))
        let screen = XCUIScreen.main.screenshot()
        let screenshot = XCTAttachment(screenshot: screen)
        screenshot.name = "github-readable-context-menu"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        try? screen.image.pngData()?.write(to: URL(fileURLWithPath: "/tmp/haiity-github-context-runtime.png"))
    }

    func testLongPressingHabitGraphShowsItsActions() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "habits", "-pro", "on", "-seed-stats",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
        app.launch()

        let graph = app.descendants(matching: .any)["habit-history"].firstMatch
        XCTAssertTrue(graph.waitForExistence(timeout: 10))

        graph.press(forDuration: 1.0)

        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 3))
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.textFields["habit-name"].waitForExistence(timeout: 5))
    }

}

final class ReminderInteractionUITests: XCTestCase {
    private let seededReminderID = "00000000-0000-0000-0000-000000000108"

    override func tearDown() {
        let cleanup = XCUIApplication()
        cleanup.launchArguments = ["-screen", "habits", "-cleanup-reminder-interactions"]
        cleanup.launch()
        cleanup.terminate()
        super.tearDown()
    }

    func testReminderCheckmarkAndRevealButtonsRespondToTouches() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "habits", "-seed-reminder-interactions", "-pro", "on"]
        app.launch()

        let row = app.descendants(matching: .any)[
            "reminder-row-\(seededReminderID)"
        ].firstMatch
        for _ in 0..<10 where !row.exists {
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 3),
                      "the seeded reminder must be reachable after scrolling")

        let check = app.buttons["reminder-check-\(seededReminderID)"]
        XCTAssertTrue(check.waitForExistence(timeout: 2))
        let initialValue = check.value as? String

        check.tap()
        waitUntil(
            predicate: NSPredicate(format: "value != %@", initialValue ?? ""),
            on: check,
            timeout: 3,
            message: "the reminder checkmark must update the occurrence")
        check.tap()
        waitUntil(
            predicate: NSPredicate(format: "value == %@", initialValue ?? ""),
            on: check,
            timeout: 3,
            message: "tapping the checkmark again must revert the occurrence")

        // Start on the nested control as well as the row surface. The
        // production pan is attached to the cell, so both touch paths must
        // reveal the same actions.
        // XCTest's convenience swipe on an accessibility container can be
        // claimed by List's own pan before the row surface sees it. Use the
        // same continuous coordinate drag a user performs instead.
        let surfaceStart = row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        // Stop after exposing the action instead of crossing the full-swipe
        // commit threshold. Full-swipe completion is covered by SwipeRevealTests.
        let surfaceEnd = row.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.5))
        surfaceStart.press(forDuration: 0.1,
                           thenDragTo: surfaceEnd,
                         withVelocity: .fast,
                         thenHoldForDuration: 0)
        let done = row.buttons["reveal-action-done"]
        let doneAppeared = done.waitForExistence(timeout: 3)
        if !doneAppeared {
            let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screen.name = "reminder-after-checkmark-swipe"
            screen.lifetime = .keepAlways
            add(screen)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "reminder-after-checkmark-swipe-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(doneAppeared,
                      "swiping right must reveal the reminder Done action")
        guard doneAppeared else { return }
        done.tap()
        let earlyCompletion = app.buttons["reminder-early-completion-confirm"]
        if earlyCompletion.waitForExistence(timeout: 1) {
            earlyCompletion.tap()
        }
        waitUntil(
            predicate: NSPredicate(format: "value != %@", initialValue ?? ""),
            on: check,
            timeout: 3,
            message: "tapping the revealed Done action must complete the reminder")

        let swipeStart = check.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let swipeEnd = row.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
        swipeStart.press(forDuration: 0.1,
                         thenDragTo: swipeEnd,
                         withVelocity: .fast,
                         thenHoldForDuration: 0)
        let reset = row.buttons["reveal-action-reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 3),
                      "swiping left must reveal the reminder Reset action")
        reset.tap()
        waitUntil(
            predicate: NSPredicate(format: "value == %@", initialValue ?? ""),
            on: check,
            timeout: 3,
            message: "tapping the revealed Reset action must revert the reminder")

        // The next intentional checkmark tap must not be swallowed by the
        // stale-event guard belonging to the preceding swipe.
        check.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        waitUntil(
            predicate: NSPredicate(format: "value != %@", initialValue ?? ""),
            on: check,
            timeout: 3,
            message: "the next deliberate checkmark tap must remain interactive")
    }

    func testReminderSwipeStartingOnCheckmarkRevealsReset() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "habits", "-seed-reminder-interactions", "-pro", "on"]
        app.launch()

        let row = app.descendants(matching: .any)[
            "reminder-row-\(seededReminderID)"
        ].firstMatch
        for _ in 0..<10 where !row.exists {
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 3))

        let check = app.buttons["reminder-check-\(seededReminderID)"]
        XCTAssertTrue(check.waitForExistence(timeout: 3))
        let initialValue = check.value as? String
        check.tap()
        waitUntil(
            predicate: NSPredicate(format: "value != %@", initialValue ?? ""),
            on: check,
            timeout: 3,
            message: "the reminder must be completed before testing reset")

        let swipeStart = check.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let swipeEnd = row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        swipeStart.press(forDuration: 0.1,
                         thenDragTo: swipeEnd,
                         withVelocity: .fast,
                         thenHoldForDuration: 0)
        let reset = row.buttons["reveal-action-reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 3),
                      "a swipe beginning on the checkmark must reveal Reset")
    }

    func testLongPressingReminderPreviewOpensItsEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "habits", "-seed-reminder-interactions", "-pro",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
        app.launch()

        let row = app.descendants(matching: .any)[
            "reminder-row-\(seededReminderID)"
        ].firstMatch
        for _ in 0..<10 where !row.exists {
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5),
                      "the seeded reminder must be reachable")

        row.press(forDuration: 1.0)

        // UIKit exposes a lifted UIContextMenu preview as an Other element
        // labelled Preview; the SwiftUI identifier remains inside its host.
        let preview = app.otherElements["Preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 3),
                      "the enlarged reminder must expose its full preview surface")
        preview.tap()

        XCTAssertTrue(app.textFields["habit-name"].waitForExistence(timeout: 5),
                      "tapping the enlarged reminder must open reminder settings")
    }

    private func waitUntil(predicate: NSPredicate,
                            on element: XCUIElement,
                            timeout: TimeInterval,
                            message: String) {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, message)
    }
}
