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
            TimelineView(.animation) { context in
                let elapsed = elapsed(at: context.date)
                let spreadProgress = StartupSplashTimeline.spreadProgress(at: elapsed)
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
                          spreadProgress: spreadProgress,
                          zoomProgress: zoomProgress)
                        .opacity(StartupSplashTimeline.tileOpacity(at: elapsed))
                }
                .frame(width: container.width, height: container.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear {
            start()
        }
    }

    private func elapsed(at date: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, date.timeIntervalSince(startedAt))
    }

    private func tiles(metrics: Metrics,
                       spreadProgress: CGFloat,
                       zoomProgress: CGFloat) -> some View {
        ForEach(Self.tileData) { tile in
            RoundedRectangle(cornerRadius: metrics.cell * 0.22,
                             style: .continuous)
                .fill(Theme.level(tile.level,
                                  dark: scheme == .dark,
                                  palette: PaletteStyle.default))
                .frame(width: metrics.cell, height: metrics.cell)
                .scaleEffect(StartupSplashTimeline.tileScale(
                    spreadProgress: spreadProgress,
                    zoomProgress: zoomProgress))
                .position(position(for: tile,
                                   metrics: metrics,
                                   spreadProgress: spreadProgress,
                                   zoomProgress: zoomProgress))
        }
    }

    private func position(for tile: Tile,
                          metrics: Metrics,
                          spreadProgress: CGFloat,
                          zoomProgress: CGFloat) -> CGPoint {
        let center = CGPoint(x: metrics.container.width / 2,
                             y: metrics.container.height / 2)
        let gridOrigin = CGPoint(x: center.x - metrics.gridWidth / 2,
                                 y: center.y - metrics.gridHeight / 2)
        let gridPosition = CGPoint(
            x: gridOrigin.x + CGFloat(tile.column) * metrics.pitch + metrics.cell / 2,
            y: gridOrigin.y + CGFloat(tile.row) * metrics.pitch + metrics.cell / 2)

        let clusterPosition = StartupSplashTimeline.zoomedPosition(
            for: gridPosition,
            around: center,
            scale: StartupSplashTimeline.compactScale)

        let basePosition = CGPoint(
            x: clusterPosition.x + (gridPosition.x - clusterPosition.x) * spreadProgress,
            y: clusterPosition.y + (gridPosition.y - clusterPosition.y) * spreadProgress)
        return StartupSplashTimeline.zoomedPosition(for: basePosition,
                                                    around: center,
                                                    scale: 1 + (StartupSplashTimeline.zoomScale - 1)
                                                        * zoomProgress)
    }

    private func start() {
        guard startedAt == nil else { return }
        // Mount the app only after this lightweight overlay has produced its
        // first frame. A large store/UI tree must not delay the launch visual.
        startedAt = Date()
        onContentReady()
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
