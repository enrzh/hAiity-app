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

    func testLongPressingGitHubGraphShowsItsReadablePreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "habits", "-demo-github-card", "-pro"]
        app.launch()

        let graph = app.descendants(matching: .any)["github-grid"].firstMatch
        XCTAssertTrue(graph.waitForExistence(timeout: 10))

        graph.press(forDuration: 1.0)

        XCTAssertTrue(app.buttons["GitHub-Profil öffnen"].waitForExistence(timeout: 3))
        let screen = XCUIScreen.main.screenshot()
        let screenshot = XCTAttachment(screenshot: screen)
        screenshot.name = "github-readable-context-menu"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        try? screen.image.pngData()?.write(to: URL(fileURLWithPath: "/tmp/haiity-github-context-runtime.png"))
    }

    func testLongPressingHabitGraphShowsItsActions() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "habits", "-pro", "on", "-seed-stats"]
        app.launch()

        let graph = app.descendants(matching: .any)["habit-grid"].firstMatch
        XCTAssertTrue(graph.waitForExistence(timeout: 10))

        graph.press(forDuration: 1.0)

        XCTAssertTrue(app.buttons["Bearbeiten"].waitForExistence(timeout: 3))
    }
}
