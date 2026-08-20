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

    func testProgressInterpolatesFromClusterToGridAndThenZooms() {
        let spreadAt = StartupSplashTimeline.clusterDuration
        let zoomAt = spreadAt + StartupSplashTimeline.spreadDuration

        XCTAssertEqual(StartupSplashTimeline.spreadProgress(at: spreadAt), 0)
        XCTAssertEqual(StartupSplashTimeline.spreadProgress(at: zoomAt), 1)
        XCTAssertEqual(StartupSplashTimeline.zoomProgress(at: zoomAt), 0)
        XCTAssertEqual(StartupSplashTimeline.zoomProgress(at: StartupSplashTimeline.duration), 1)
        XCTAssertEqual(StartupSplashTimeline.tileOpacity(at: StartupSplashTimeline.duration), 0)
    }

    func testOverlayAndTilesCrossFadeDuringTheZoom() {
        let zoomAt = StartupSplashTimeline.clusterDuration
            + StartupSplashTimeline.spreadDuration
        let midpoint = zoomAt + StartupSplashTimeline.zoomDuration * 0.5

        XCTAssertGreaterThan(StartupSplashTimeline.tileOpacity(at: midpoint), 0)
        XCTAssertLessThan(StartupSplashTimeline.tileOpacity(at: midpoint), 1)
        XCTAssertGreaterThan(StartupSplashTimeline.overlayOpacity(at: midpoint), 0)
        XCTAssertLessThan(StartupSplashTimeline.overlayOpacity(at: midpoint), 1)
        XCTAssertLessThan(StartupSplashTimeline.overlayOpacity(at: zoomAt), 1)
        XCTAssertEqual(StartupSplashTimeline.overlayOpacity(at: StartupSplashTimeline.duration), 0)
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

    func testSplashUsesFallbackViewportBeforeGeometryIsMeasured() {
        let fallback = CGSize(width: 420, height: 912)

        XCTAssertEqual(
            StartupSplashTimeline.resolvedContainerSize(measured: .zero, fallback: fallback),
            fallback)
        XCTAssertEqual(
            StartupSplashTimeline.resolvedContainerSize(
                measured: CGSize(width: 390, height: 844), fallback: fallback),
            CGSize(width: 390, height: 844))
    }

    func testSplashKeepsTheFullScreenAppMountedBehindTheOverlay() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let splash = try String(contentsOf: root.appendingPathComponent("Haiity/Views/StartupSplashView.swift"))
        let app = try String(contentsOf: root.appendingPathComponent("Haiity/HaiityApp.swift"))

        XCTAssertTrue(splash.contains("start()"))
        XCTAssertTrue(splash.contains("spreadProgress"))
        XCTAssertTrue(splash.contains("splashOpacity"))
        XCTAssertFalse(app.contains("startupAppVisible"))
        XCTAssertFalse(app.contains("onAppReveal"))
        XCTAssertFalse(app.contains(".opacity(startupAppVisible ? 1 : 0)"))
        XCTAssertFalse(app.contains(".transition(.opacity)"))
    }

    func testSplashReadinessUsesRootSceneLifecycle() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(contentsOf: root.appendingPathComponent("Haiity/HaiityApp.swift"))

        XCTAssertFalse(app.contains("StartupSplashReadySignal"))
    }

    func testAppContentKeepsTheFullScreenHandoffSurface() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(contentsOf: root.appendingPathComponent("Haiity/HaiityApp.swift"))

        let content = try XCTUnwrap(app.range(of: "ContentView()"))
        let tail = app[content.upperBound...]
        XCTAssertTrue(tail.contains(".ignoresSafeArea()"),
                      "the revealed app must cover the same window as the splash")
        XCTAssertTrue(tail.contains(".allowsHitTesting(!startupSplashVisible)"))
    }

    func testTilesGrowFromCompactGraphToFullZoom() {
        XCTAssertEqual(StartupSplashTimeline.tileScale(spreadProgress: 0,
                                                        zoomProgress: 0),
                       StartupSplashTimeline.compactScale)
        XCTAssertEqual(StartupSplashTimeline.tileScale(spreadProgress: 1,
                                                        zoomProgress: 0), 1)
        XCTAssertEqual(StartupSplashTimeline.tileScale(spreadProgress: 1,
                                                        zoomProgress: 1),
                       StartupSplashTimeline.zoomScale)
    }

    func testSplashLeavesASettledHandoffAfterTheVisualZoom() {
        XCTAssertGreaterThan(StartupSplashTimeline.duration,
                             StartupSplashTimeline.clusterDuration
                             + StartupSplashTimeline.spreadDuration
                             + StartupSplashTimeline.zoomDuration)
    }

    func testSplashUsesOneFrameDrivenTimelineForTheFullWindow() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let splash = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/StartupSplashView.swift"))

        XCTAssertTrue(splash.contains("TimelineView(.animation)"),
                      "launch animation must be driven by one continuous clock")
        XCTAssertTrue(splash.contains(".frame(maxWidth: .infinity, maxHeight: .infinity)"),
                      "the splash must own the complete window during the handoff")
        XCTAssertTrue(splash.contains(".ignoresSafeArea()"),
                      "the splash surface must cover the window safe areas")
        XCTAssertFalse(splash.contains("containerRelativeFrame([.horizontal, .vertical])"),
                       "the splash must not be constrained to the safe-area container")
        XCTAssertFalse(splash.contains("DispatchQueue.main.asyncAfter"),
                       "queued phase jumps make the launch handoff visibly discontinuous")
    }

    func testSplashMeasuresTheWindowBeforeStartingItsTimeline() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let splash = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/StartupSplashView.swift"))

        let geometry = try XCTUnwrap(splash.range(of: "GeometryReader {"))
        let timeline = try XCTUnwrap(splash.range(of: "TimelineView(.animation)"))
        XCTAssertLessThan(geometry.lowerBound, timeline.lowerBound,
                          "the animation must start inside an already measured window")
        XCTAssertTrue(splash.contains("Metrics(container: container)"),
                      "tile positions must use the resolved window, not a zero-size first frame")
    }

    func testSplashFadesItsWindowOverlayBeforeRemovingTheView() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let splash = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/StartupSplashView.swift"))

        XCTAssertTrue(splash.contains("overlayOpacity"),
                      "the mounted app must be revealed by the splash overlay")
        XCTAssertTrue(splash.contains("tileOpacity"),
                      "tiles must fade with the handoff instead of disappearing at a phase boundary")
    }

    func testLaunchScreenUsesTheSameGroupedBackgroundAsTheApp() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plist = try String(contentsOf: root.appendingPathComponent("Haiity/Info.plist"))
        let project = try String(contentsOf: root.appendingPathComponent("project.yml"))
        let asset = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Assets.xcassets/LaunchBackground.colorset/Contents.json"))

        XCTAssertTrue(plist.contains("UIColorName") && plist.contains("LaunchBackground"))
        XCTAssertTrue(plist.contains("UIImageName") && plist.contains("LaunchTiles"))
        XCTAssertTrue(project.contains("UIColorName: LaunchBackground"))
        XCTAssertTrue(project.contains("UIImageName: LaunchTiles"))
        XCTAssertTrue(asset.contains("0.949") && asset.contains("0.110"),
                      "the launch asset needs light and dark grouped-background variants")
    }

    func testSplashAndAppRootUseTheGroupedBackground() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let splash = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/StartupSplashView.swift"))
        let app = try String(contentsOf: root.appendingPathComponent("Haiity/HaiityApp.swift"))

        XCTAssertTrue(splash.contains("Color(.systemGroupedBackground)"))
        XCTAssertTrue(app.contains("Color(.systemGroupedBackground)"))
    }

    func testAppMountsContentAfterTheSplashHasRendered() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(contentsOf: root.appendingPathComponent("Haiity/HaiityApp.swift"))
        let splash = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/StartupSplashView.swift"))

        XCTAssertTrue(app.contains("startupContentMounted"))
        XCTAssertTrue(app.contains("if startupContentMounted"))
        XCTAssertTrue(app.contains("StartupSplashView(onContentReady:"))
        XCTAssertTrue(splash.contains("onContentReady()"))
    }
}
