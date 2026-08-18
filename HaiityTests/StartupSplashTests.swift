import XCTest
@testable import Haiity

final class StartupSplashTests: XCTestCase {
    func testTimelineMovesFromClusterToSpreadToZoomAndFinishes() {
        let spreadAt = StartupSplashTimeline.clusterDuration
        let zoomAt = spreadAt + StartupSplashTimeline.spreadDuration
        let finishedAt = StartupSplashTimeline.duration

        XCTAssertEqual(StartupSplashTimeline.phase(at: 0), .cluster)
        XCTAssertEqual(StartupSplashTimeline.phase(at: spreadAt), .spread)
        XCTAssertEqual(StartupSplashTimeline.phase(at: zoomAt), .zoom)
        XCTAssertEqual(StartupSplashTimeline.phase(at: finishedAt), .finished)
    }

    func testTimelineKeepsFinishedPhaseAfterDuration() {
        XCTAssertEqual(StartupSplashTimeline.phase(at: .greatestFiniteMagnitude), .finished)
    }

    func testTilesFadeOutDuringZoomHandoff() {
        XCTAssertEqual(StartupSplashTimeline.tileOpacity(for: .cluster), 1)
        XCTAssertEqual(StartupSplashTimeline.tileOpacity(for: .spread), 1)
        XCTAssertEqual(StartupSplashTimeline.tileOpacity(for: .zoom), 0)
        XCTAssertEqual(StartupSplashTimeline.tileOpacity(for: .finished), 0)
    }

    func testZoomMotionMovesEachTileAwayFromTheCenter() {
        let center = CGPoint(x: 100, y: 100)
        let tile = CGPoint(x: 120, y: 80)

        let zoomed = StartupSplashTimeline.zoomedPosition(
            for: tile,
            around: center,
            scale: 7.5
        )

        XCTAssertEqual(zoomed.x, 250)
        XCTAssertEqual(zoomed.y, -50)
    }

    func testSplashStartsAfterTheFirstVisibleFrame() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let splash = try String(contentsOf: root.appendingPathComponent("Haiity/Views/StartupSplashView.swift"))
        let app = try String(contentsOf: root.appendingPathComponent("Haiity/HaiityApp.swift"))

        XCTAssertTrue(splash.contains("isReady"))
        XCTAssertTrue(splash.contains("onChange(of: isReady)"))
        XCTAssertTrue(splash.contains("onAppReveal"))
        XCTAssertTrue(app.contains("StartupSplashReadySignal"))
        XCTAssertTrue(app.contains("startupAppVisible"))
    }
}
