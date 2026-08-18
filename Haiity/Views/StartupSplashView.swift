import SwiftUI
import UIKit

struct StartupSplashView: View {
    let isReady: Bool
    let onAppReveal: () -> Void
    let onFinished: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var phase: StartupSplashPhase = .cluster
    @State private var tileOpacity = 1.0
    @State private var tileZoomScale: CGFloat = 1
    @State private var started = false

    private static let columns = 21
    private static let rows = 7
    private static let clusterColumns = 7
    private static let clusterRows = 7

    var body: some View {
        GeometryReader { proxy in
            let metrics = Metrics(container: proxy.size)
            ZStack {
                Color(.systemBackground)
                    .opacity(tileOpacity)

                tiles(metrics: metrics)
                    .opacity(tileOpacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear {
            if isReady { start() }
        }
        .onChange(of: isReady) { _, ready in
            if ready { start() }
        }
    }

    private func tiles(metrics: Metrics) -> some View {
        ForEach(Self.tileData) { tile in
            RoundedRectangle(cornerRadius: metrics.cell * 0.22,
                             style: .continuous)
                .fill(Theme.level(tile.level,
                                  dark: scheme == .dark,
                                  palette: PaletteStyle.default))
                .frame(width: metrics.cell, height: metrics.cell)
                .scaleEffect(tileZoomScale)
                .position(position(for: tile, metrics: metrics))
        }
    }

    private func position(for tile: Tile, metrics: Metrics) -> CGPoint {
        let center = CGPoint(x: metrics.container.width / 2,
                             y: metrics.container.height / 2)
        let gridOrigin = CGPoint(x: center.x - metrics.gridWidth / 2,
                                 y: center.y - metrics.gridHeight / 2)
        let gridPosition = CGPoint(
            x: gridOrigin.x + CGFloat(tile.column) * metrics.pitch + metrics.cell / 2,
            y: gridOrigin.y + CGFloat(tile.row) * metrics.pitch + metrics.cell / 2)

        let clusterIndex = tile.index % (Self.clusterColumns * Self.clusterRows)
        let clusterColumn = clusterIndex % Self.clusterColumns
        let clusterRow = clusterIndex / Self.clusterColumns
        let clusterOrigin = CGPoint(
            x: center.x - CGFloat(Self.clusterColumns) * metrics.clusterPitch / 2,
            y: center.y - CGFloat(Self.clusterRows) * metrics.clusterPitch / 2)
        let clusterPosition = CGPoint(
            x: clusterOrigin.x + CGFloat(clusterColumn) * metrics.clusterPitch,
            y: clusterOrigin.y + CGFloat(clusterRow) * metrics.clusterPitch)

        let basePosition = phase == .cluster ? clusterPosition : gridPosition
        return StartupSplashTimeline.zoomedPosition(for: basePosition,
                                                    around: center,
                                                    scale: tileZoomScale)
    }

    private func start() {
        guard !started else { return }
        started = true

        let spreadAt = StartupSplashTimeline.clusterDuration
        let zoomAt = spreadAt + StartupSplashTimeline.spreadDuration
        let finishAt = StartupSplashTimeline.duration

        DispatchQueue.main.asyncAfter(deadline: .now() + spreadAt) {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.82)) {
                phase = .spread
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + zoomAt) {
            withAnimation(.easeIn(duration: StartupSplashTimeline.zoomDuration)) {
                phase = .zoom
                tileZoomScale = StartupSplashTimeline.zoomScale
                tileOpacity = 0
            }
            onAppReveal()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + finishAt) {
            phase = .finished
            onFinished()
        }
    }

    private struct Metrics {
        let container: CGSize
        let cell: CGFloat
        let pitch: CGFloat
        let clusterPitch: CGFloat
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
            self.clusterPitch = cell + 4
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

struct StartupSplashReadySignal: UIViewControllerRepresentable {
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
