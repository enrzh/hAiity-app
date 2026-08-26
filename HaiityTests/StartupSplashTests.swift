import XCTest
@testable import Haiity

final class StartupSplashTests: XCTestCase {
    func testTimelineMovesFromClusterToSplitToZoomAndFinishes() {
        let splitAt = StartupSplashTimeline.clusterDuration
        let zoomAt = splitAt + StartupSplashTimeline.splitDuration
        let finishedAt = StartupSplashTimeline.duration

        XCTAssertEqual(StartupSplashTimeline.phase(at: 0), .cluster)
        XCTAssertEqual(StartupSplashTimeline.phase(at: splitAt), .split)
        XCTAssertEqual(StartupSplashTimeline.phase(at: zoomAt), .zoom)
        XCTAssertEqual(StartupSplashTimeline.phase(at: finishedAt), .finished)
    }

    func testTimelineKeepsFinishedPhaseAfterDuration() {
        XCTAssertEqual(StartupSplashTimeline.phase(at: .greatestFiniteMagnitude), .finished)
    }

    func testTilesFadeOutDuringZoomHandoff() {
        XCTAssertEqual(StartupSplashTimeline.tileOpacity(for: .cluster), 1)
        XCTAssertEqual(StartupSplashTimeline.tileOpacity(for: .split), 1)
        XCTAssertEqual(StartupSplashTimeline.tileOpacity(for: .zoom), 0)
        XCTAssertEqual(StartupSplashTimeline.tileOpacity(for: .finished), 0)
    }

    func testProgressInterpolatesFromClusterToGridAndThenZooms() {
        let splitAt = StartupSplashTimeline.clusterDuration
        let zoomAt = splitAt + StartupSplashTimeline.splitDuration

        XCTAssertEqual(StartupSplashTimeline.splitProgress(at: splitAt), 0)
        XCTAssertEqual(StartupSplashTimeline.splitProgress(at: zoomAt), 1)
        XCTAssertEqual(StartupSplashTimeline.zoomProgress(at: zoomAt), 0)
        XCTAssertEqual(StartupSplashTimeline.zoomProgress(at: StartupSplashTimeline.duration), 1)
        XCTAssertEqual(StartupSplashTimeline.tileOpacity(at: StartupSplashTimeline.duration), 0)
    }

    func testOverlayAndTilesCrossFadeDuringTheZoom() {
        let zoomAt = StartupSplashTimeline.clusterDuration
            + StartupSplashTimeline.splitDuration
        let midpoint = zoomAt + StartupSplashTimeline.zoomDuration * 0.5

        XCTAssertGreaterThan(StartupSplashTimeline.tileOpacity(at: midpoint), 0)
        XCTAssertLessThan(StartupSplashTimeline.tileOpacity(at: midpoint), 1)
        XCTAssertGreaterThan(StartupSplashTimeline.overlayOpacity(at: midpoint), 0)
        XCTAssertLessThan(StartupSplashTimeline.overlayOpacity(at: midpoint), 1)
        XCTAssertLessThan(StartupSplashTimeline.overlayOpacity(at: zoomAt), 1)
        XCTAssertEqual(StartupSplashTimeline.overlayOpacity(at: StartupSplashTimeline.duration), 0)
    }

    func testGraphCopiesAreCenterOnlyBeforeTheSplit() {
        let beforeSplit = StartupSplashTimeline.clusterDuration * 0.5

        XCTAssertEqual(StartupSplashTimeline.graphOpacity(for: .top, at: beforeSplit), 0)
        XCTAssertEqual(StartupSplashTimeline.graphOpacity(for: .center, at: beforeSplit), 1)
        XCTAssertEqual(StartupSplashTimeline.graphOpacity(for: .bottom, at: beforeSplit), 0)

        let splitComplete = StartupSplashTimeline.clusterDuration
            + StartupSplashTimeline.splitDuration
        XCTAssertEqual(StartupSplashTimeline.graphOpacity(for: .top, at: splitComplete), 1)
        XCTAssertEqual(StartupSplashTimeline.graphOpacity(for: .center, at: splitComplete), 1)
        XCTAssertEqual(StartupSplashTimeline.graphOpacity(for: .bottom, at: splitComplete), 1)
    }

    func testGraphCopiesSeparateVerticallyFromTheCenter() {
        let center = CGPoint(x: 100, y: 200)
        let separation: CGFloat = 120

        XCTAssertEqual(
            StartupSplashTimeline.graphCenter(for: .top,
                                              around: center,
                                              separation: separation,
                                              progress: 1),
            CGPoint(x: 100, y: 80))
        XCTAssertEqual(
            StartupSplashTimeline.graphCenter(for: .center,
                                              around: center,
                                              separation: separation,
                                              progress: 1),
            center)
        XCTAssertEqual(
            StartupSplashTimeline.graphCenter(for: .bottom,
                                              around: center,
                                              separation: separation,
                                              progress: 1),
            CGPoint(x: 100, y: 320))
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

        XCTAssertTrue(splash.contains("startAnimation(metrics:"))
        XCTAssertTrue(splash.contains("CAKeyframeAnimation"))
        XCTAssertTrue(splash.contains("backgroundLayer"))
        XCTAssertFalse(app.contains("startupAppVisible"))
        XCTAssertFalse(app.contains("onAppReveal"))
        XCTAssertFalse(app.contains(".opacity(startupAppVisible ? 1 : 0)"))
        XCTAssertFalse(app.contains(".transition(.opacity)"))
        XCTAssertFalse(app.contains("startupAppOpacity"))
        XCTAssertFalse(app.contains(".opacity(startupAppOpacity)"))
        XCTAssertFalse(app.contains("withAnimation(.easeInOut(duration: StartupSplashTimeline.zoomDuration + 0.08)"))
    }

    func testSplashReadinessUsesRootSceneLifecycle() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(contentsOf: root.appendingPathComponent("Haiity/HaiityApp.swift"))

        XCTAssertFalse(app.contains("StartupSplashReadySignal"))
    }

    func testSplashCompletionCommitsAndRemovesTheOverlayInOneCallback() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(contentsOf: root.appendingPathComponent("Haiity/HaiityApp.swift"))

        let callbackStart = try XCTUnwrap(app.range(of: "StartupSplashView {"))
        let callbackEnd = try XCTUnwrap(app.range(of: ".allowsHitTesting(startupSplashVisible)",
                                                   range: callbackStart.upperBound..<app.endIndex))
        let callback = app[callbackStart.lowerBound..<callbackEnd.lowerBound]
        XCTAssertTrue(callback.contains("finishStartupAnimation()"),
                      "the completion callback must not read stale @State")
        XCTAssertFalse(callback.contains("revealStartupIfReady()"),
                       "the old two-step state handoff leaves the transparent overlay mounted")

        let methodStart = try XCTUnwrap(app.range(of: "private func finishStartupAnimation()"))
        let methodEnd = app.range(of: "\n    }", range: methodStart.upperBound..<app.endIndex)
            .map(\.lowerBound) ?? app.endIndex
        let method = app[methodStart.lowerBound..<methodEnd]
        XCTAssertTrue(method.contains("startupContentMounted = true"))
        XCTAssertTrue(method.contains("startupSplashVisible = false"))
        XCTAssertFalse(method.contains("startupAppOpacity = 1"))
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
        XCTAssertFalse(tail.contains(".allowsHitTesting(!startupSplashVisible)"),
                       "the splash overlay must own launch blocking; a stale root gate also blocks presented sheets")
        XCTAssertTrue(app.contains(".allowsHitTesting(startupSplashVisible)"),
                      "the splash surface must be the only launch-time hit-test blocker")
    }

    func testGraphGroupGrowsFromCompactGraphToFullZoom() {
        XCTAssertEqual(StartupSplashTimeline.graphScale(splitProgress: 0,
                                                        zoomProgress: 0),
                       StartupSplashTimeline.compactScale)
        XCTAssertEqual(StartupSplashTimeline.graphScale(splitProgress: 1,
                                                        zoomProgress: 0), 1)
        XCTAssertEqual(StartupSplashTimeline.graphScale(splitProgress: 1,
                                                        zoomProgress: 1),
                       StartupSplashTimeline.zoomScale)
        XCTAssertLessThan(StartupSplashTimeline.graphScale(splitProgress: 1,
                                                           zoomProgress: 0.4),
                          StartupSplashTimeline.graphScale(splitProgress: 1,
                                                           zoomProgress: 0.8))
    }

    func testSplashLeavesASettledHandoffAfterTheVisualZoom() {
        XCTAssertGreaterThan(StartupSplashTimeline.duration,
                             StartupSplashTimeline.clusterDuration
                             + StartupSplashTimeline.splitDuration
                             + StartupSplashTimeline.zoomDuration)
    }

    func testSplashUsesCoreAnimationForTheFullWindow() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let splash = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/StartupSplashView.swift"))

        XCTAssertTrue(splash.contains("StartupSplashAnimationSurface"),
                      "the launch surface should be hosted by a UIKit renderer")
        XCTAssertTrue(splash.contains("CAAnimation"),
                      "launch motion should be interpolated by Core Animation")
        XCTAssertFalse(splash.contains("TimelineView("),
                       "a SwiftUI display-rate clock rebuilds the launch hierarchy every frame")
        XCTAssertTrue(splash.contains(".frame(maxWidth: .infinity, maxHeight: .infinity)"),
                      "the splash must own the complete window during the handoff")
        XCTAssertTrue(splash.contains(".ignoresSafeArea()"),
                      "the splash surface must cover the window safe areas")
        XCTAssertFalse(splash.contains("containerRelativeFrame([.horizontal, .vertical])"),
                       "the splash must not be constrained to the safe-area container")
        XCTAssertFalse(splash.contains("DispatchQueue.main.asyncAfter"),
                       "queued phase jumps make the launch handoff visibly discontinuous")
    }

    func testSplashUsesCachedLaunchTilesInsteadOfPerFrameCanvasRendering() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let splash = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/StartupSplashView.swift"))

        XCTAssertTrue(splash.contains("UIGraphicsImageRenderer"),
                      "the startup graph should be rasterized once before animation")
        XCTAssertTrue(splash.contains("contents = launchImage"),
                      "each graph layer should reuse the single rasterized launch asset")
        XCTAssertFalse(splash.contains("Canvas("),
                       "a per-frame Canvas rebuilds hundreds of vector paths during launch")
    }

    func testSplashMeasuresTheWindowBeforeStartingCoreAnimation() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let splash = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/StartupSplashView.swift"))

        XCTAssertTrue(splash.contains("layoutSubviews"),
                      "the animation must wait for a measured window")
        XCTAssertTrue(splash.contains("bounds.width > 0"),
                      "tile positions must not be calculated from a zero-size first frame")
    }

    func testSplashFadesItsWindowOverlayBeforeRemovingTheView() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let splash = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/StartupSplashView.swift"))

        XCTAssertTrue(splash.contains("backgroundLayer"),
                      "the mounted app must be revealed by the splash overlay")
        XCTAssertTrue(splash.contains("fadeAnimation"),
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

    func testAppMountsContentBehindTheSplashImmediately() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(contentsOf: root.appendingPathComponent("Haiity/HaiityApp.swift"))
        let splash = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/StartupSplashView.swift"))

        XCTAssertTrue(app.contains("@State private var startupContentMounted = true"),
                      "the app tree must mount while the splash is covering it")
        XCTAssertTrue(app.contains("if startupContentMounted"))
        XCTAssertTrue(app.contains("StartupSplashView {"))
        XCTAssertFalse(splash.contains("onContentReady?()"))
    }

    func testImageBackedLaunchPreparesAppearanceBeforeReveal() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(contentsOf: root.appendingPathComponent("Haiity/HaiityApp.swift"))

        XCTAssertTrue(app.contains("AppearanceImageCache.prewarmTask(data:"),
                      "launch should keep a cancellable prewarm task while the splash is visible")
        XCTAssertFalse(app.contains("startupContentMounted = startupAppearanceReady"),
                       "background preparation must not block mounting the app tree")
        XCTAssertTrue(app.contains("startupBackgroundPrewarmTask"),
                      "launch-specific prewarm work must be released when it is no longer needed")
    }

    func testAppearanceBackgroundDoesNotDecodeOnItsFirstBodyEvaluation() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let theme = try String(contentsOf: root.appendingPathComponent("Haiity/Theme.swift"))
        let start = try XCTUnwrap(theme.range(of: "struct AppearanceBackground: View"))
        let end = try XCTUnwrap(theme.range(of: "private struct AppSurfaceModifier",
                                            range: start.upperBound..<theme.endIndex))
        let background = theme[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(background.contains("@State private var preparedImage"),
                      "the full-screen background must own asynchronous image readiness")
        XCTAssertTrue(background.contains(".task(id: imageData)"),
                      "image decoding must happen off the first synchronous body pass")
        XCTAssertFalse(background.contains("preferences.backgroundImage}"),
                       "the background must not synchronously decode a JPEG during layout")
    }

    func testSplashHasAnAccessibilityReduceMotionPath() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let splash = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/StartupSplashView.swift"))

        XCTAssertTrue(splash.contains("accessibilityReduceMotion"),
                      "launch motion must respect the system Reduce Motion setting")
        XCTAssertTrue(splash.contains("reduceMotion"),
                      "the UIKit animation surface must receive the reduced-motion state")
    }

    func testReducedMotionHandoffSkipsLaunchRasterizationWork() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let splash = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/StartupSplashView.swift"))

        let scheduleStart = try XCTUnwrap(splash.range(of: "private func scheduleStartIfReady()"))
        let startAnimation = try XCTUnwrap(splash.range(of: "private func startAnimation(",
                                                        range: scheduleStart.upperBound..<splash.endIndex))
        let scheduleBody = splash[scheduleStart.lowerBound..<startAnimation.lowerBound]

        let reduceMotion = try XCTUnwrap(scheduleBody.range(of: "if self.reduceMotion {"))
        let raster = try XCTUnwrap(scheduleBody.range(of: "prepareLaunchImage("))

        XCTAssertLessThan(reduceMotion.lowerBound, raster.lowerBound,
                          "reduce motion should bypass launch-image preparation before any raster work starts")
        XCTAssertTrue(scheduleBody.contains("self.onFinished?()"),
                      "reduce motion should hand off immediately once the splash is on screen")
    }

    func testSplashPreparesItsLaunchImageBeforeStartingTheAnimation() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let splash = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/StartupSplashView.swift"))

        XCTAssertTrue(splash.contains("prepareLaunchImage("),
                      "the graph raster should be prepared before the animation begins")

        let startRange = try XCTUnwrap(splash.range(of: "private func startAnimation("))
        let configureRange = try XCTUnwrap(splash.range(of: "private func configureLayers",
                                                        range: startRange.upperBound..<splash.endIndex))
        let startAnimation = splash[startRange.lowerBound..<configureRange.lowerBound]
        XCTAssertFalse(startAnimation.contains("rasterizedLaunchImage("),
                       "animation start must not rebuild the launch graph bitmap on the handoff path")
    }

    func testAppearancePrewarmCanBeCancelledAndSharedAcrossLaunchConsumers() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let theme = try String(contentsOf: root.appendingPathComponent("Haiity/Theme.swift"))
        let app = try String(contentsOf: root.appendingPathComponent("Haiity/HaiityApp.swift"))

        XCTAssertTrue(theme.contains("inFlight"),
                      "the appearance image cache should reuse one in-flight decode for duplicate launch requests")
        XCTAssertTrue(theme.contains("prewarmTask(data:"),
                      "launch prewarm should return a cancellable task handle")
        XCTAssertTrue(app.contains("cancelStartupBackgroundPrewarm()"),
                      "the app should release launch-specific prewarm work when the splash is done or leaves the foreground")
    }
}
