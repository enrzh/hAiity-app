import SwiftUI
import UIKit

struct StartupSplashView: View {
    let onContentReady: () -> Void
    let onFinished: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var startedAt: Date?

    private static let columns = 21
    private static let rows = 7

    var body: some View {
        GeometryReader { proxy in
            // Measure the window before the animation clock starts. A reader
            // nested inside TimelineView can receive a zero-size first frame,
            // leaving every tile outside the visible window during launch.
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
                let elapsed = elapsed(at: context.date)
                let splitProgress = StartupSplashTimeline.splitProgress(at: elapsed)
                let zoomProgress = StartupSplashTimeline.zoomProgress(at: elapsed)
                let splashOpacity = StartupSplashTimeline.overlayOpacity(at: elapsed)
                let container = StartupSplashTimeline.resolvedContainerSize(
                    measured: proxy.size,
                    fallback: UIScreen.main.bounds.size)
                let metrics = Metrics(container: container)

                ZStack {
                    Color(.systemGroupedBackground)
                        .opacity(splashOpacity)
                        .ignoresSafeArea()

                    tiles(metrics: metrics,
                          elapsed: elapsed,
                          splitProgress: splitProgress,
                          zoomProgress: zoomProgress)
                        .opacity(StartupSplashTimeline.tileOpacity(at: elapsed))

                }
                .frame(width: container.width, height: container.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .overlay {
            StartupSplashReadySignal(onReady: start)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func elapsed(at date: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, date.timeIntervalSince(startedAt))
    }

    private func tiles(metrics: Metrics,
                       elapsed: TimeInterval,
                       splitProgress: CGFloat,
                       zoomProgress: CGFloat) -> some View {
        Canvas(opaque: false, colorMode: .extendedLinear, rendersAsynchronously: true) { context, _ in
            let center = CGPoint(x: metrics.container.width / 2,
                                 y: metrics.container.height / 2)
            let graphScale = StartupSplashTimeline.graphScale(
                splitProgress: splitProgress,
                zoomProgress: zoomProgress)
            var shading: [Int: GraphicsContext.Shading] = [:]

            for graph in StartupSplashGraph.allCases {
                var graphContext = context
                graphContext.opacity = StartupSplashTimeline.graphOpacity(for: graph,
                                                                          at: elapsed)
                drawGraph(&graphContext,
                          graph: graph,
                          metrics: metrics,
                          center: center,
                          splitProgress: splitProgress,
                          graphScale: graphScale,
                          shading: &shading)
        }
    }
        .frame(width: metrics.container.width, height: metrics.container.height)
    }

    private func drawGraph(_ context: inout GraphicsContext,
                           graph: StartupSplashGraph,
                           metrics: Metrics,
                           center: CGPoint,
                           splitProgress: CGFloat,
                           graphScale: CGFloat,
                           shading: inout [Int: GraphicsContext.Shading]) {
        let graphCenter = StartupSplashTimeline.graphCenter(
            for: graph,
            around: center,
            separation: metrics.verticalSeparation,
            progress: splitProgress)
        let gridOrigin = CGPoint(x: graphCenter.x - metrics.gridWidth / 2,
                                 y: graphCenter.y - metrics.gridHeight / 2)

        for tile in Self.tileData {
            let gridPosition = CGPoint(
                x: gridOrigin.x + CGFloat(tile.column) * metrics.pitch + metrics.cell / 2,
                y: gridOrigin.y + CGFloat(tile.row) * metrics.pitch + metrics.cell / 2)
            let position = StartupSplashTimeline.zoomedPosition(for: gridPosition,
                                                                around: center,
                                                                scale: graphScale)
            let cell = metrics.cell * graphScale
            let rect = CGRect(x: position.x - cell / 2,
                              y: position.y - cell / 2,
                              width: cell,
                              height: cell)
            if shading[tile.level] == nil {
                shading[tile.level] = .color(
                    Theme.level(tile.level,
                                dark: scheme == .dark,
                                palette: PaletteStyle.default))
            }
            context.fill(Path(roundedRect: rect, cornerRadius: cell * 0.22),
                         with: shading[tile.level]!)
        }
    }

    private func start() {
        guard startedAt == nil else { return }
        // Let the overlay reach the first render pass before mounting the
        // larger store/UI tree. Otherwise the system launch screen can remain
        // visible while ContentView is being constructed.
        startedAt = Date()
        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            onContentReady()
        }
        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(StartupSplashTimeline.duration
                                                           * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }

    private struct Metrics {
        let container: CGSize
        let cell: CGFloat
        let pitch: CGFloat
        let gridWidth: CGFloat
        let gridHeight: CGFloat
        let verticalSeparation: CGFloat

        init(container: CGSize) {
            self.container = container
            let width = min(max(container.width - 48, 220), 360)
            let gap: CGFloat = 3
            let cell = max(7, min(13, (width - CGFloat(StartupSplashView.columns - 1) * gap)
                                   / CGFloat(StartupSplashView.columns)))
            self.cell = cell
            self.pitch = cell + gap
            self.gridWidth = CGFloat(StartupSplashView.columns) * pitch - gap
            self.gridHeight = CGFloat(StartupSplashView.rows) * pitch - gap
            self.verticalSeparation = gridHeight + cell * 2
        }
    }

    private struct Tile: Identifiable {
        let index: Int
        let column: Int
        let row: Int
        let level: Int

        var id: Int { index }
    }

    private static let tileData: [Tile] = {
        (0..<(columns * rows)).map { index in
            let column = index % columns
            let row = index / columns
            let hash = (index * 17 + column * 5 + row * 11) % 13
            let level: Int
            switch hash {
            case 0...3: level = 0
            case 4...6: level = 1
            case 7...9: level = 2
            case 10...11: level = 3
            default: level = 4
            }
            return Tile(index: index, column: column, row: row, level: level)
        }
    }()
}

private struct StartupSplashReadySignal: UIViewControllerRepresentable {
    let onReady: () -> Void

    func makeUIViewController(context: Context) -> ReadyViewController {
        let controller = ReadyViewController()
        controller.view.backgroundColor = .clear
        controller.onReady = onReady
        return controller
    }

    func updateUIViewController(_ controller: ReadyViewController, context: Context) {
        controller.onReady = onReady
    }

    final class ReadyViewController: UIViewController {
        var onReady: (() -> Void)?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            let callback = onReady
            onReady = nil
            callback?()
        }
    }
}
