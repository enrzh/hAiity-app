import SwiftUI
import UIKit

struct StartupSplashView: View {
    let onFinished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        StartupSplashAnimationSurface(onFinished: onFinished,
                                      reduceMotion: reduceMotion)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

private struct StartupSplashAnimationSurface: UIViewRepresentable {
    let onFinished: () -> Void
    let reduceMotion: Bool

    func makeUIView(context: Context) -> StartupSplashAnimationView {
        let view = StartupSplashAnimationView()
        view.onFinished = onFinished
        view.reduceMotion = reduceMotion
        return view
    }

    func updateUIView(_ view: StartupSplashAnimationView, context: Context) {
        view.onFinished = onFinished
        view.reduceMotion = reduceMotion
    }
}

private final class StartupSplashAnimationView: UIView {
    private static let columns = 21
    private static let rows = 7

    private let backgroundLayer = CALayer()
    private var tileLayers: [CALayer] = []
    private var launchImage: CGImage?
    private var startTask: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var hasStarted = false
    private var scheduledBounds = CGSize.zero

    var onFinished: (() -> Void)?
    var reduceMotion = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = .clear
        layer.addSublayer(backgroundLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        startTask?.cancel()
        finishTask?.cancel()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            startTask?.cancel()
            startTask = nil
            scheduledBounds = .zero
            return
        }
        scheduleStartIfReady()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundLayer.frame = bounds
        if !hasStarted, startTask != nil, scheduledBounds != bounds.size {
            startTask?.cancel()
            startTask = nil
            launchImage = nil
        }
        scheduleStartIfReady()
    }

    private func scheduleStartIfReady() {
        guard window != nil,
              !hasStarted,
              startTask == nil,
              bounds.width > 0,
              bounds.height > 0 else { return }

        scheduledBounds = bounds.size
        startTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if self.reduceMotion {
                self.hasStarted = true
                self.startTask = nil
                self.launchImage = nil
                self.onFinished?()
                return
            }
            let metrics = Metrics(container: self.bounds.size)
            self.launchImage = self.prepareLaunchImage(
                size: metrics.gridSize,
                scale: self.window?.screen.scale ?? UIScreen.main.scale)
            try? await Task.sleep(nanoseconds: UInt64(StartupSplashTimeline.startDelay
                                                       * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.startAnimation(metrics: metrics)
        }
    }

    private func startAnimation(metrics: Metrics) {
        guard !hasStarted else { return }
        hasStarted = true
        startTask = nil

        configureLayers(metrics: metrics)

        let startTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        addAnimations(startTime: startTime, metrics: metrics)

        finishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(StartupSplashTimeline.duration
                                                       * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.onFinished?()
        }
    }

    private func prepareLaunchImage(size: CGSize, scale: CGFloat) -> CGImage? {
        rasterizedLaunchImage(size: size, scale: scale)
    }

    private func configureLayers(metrics: Metrics) {
        backgroundLayer.frame = bounds
        backgroundLayer.backgroundColor = UIColor.systemGroupedBackground.cgColor
        backgroundLayer.opacity = 1
        backgroundLayer.removeAllAnimations()

        tileLayers.forEach { $0.removeFromSuperlayer() }
        tileLayers.removeAll(keepingCapacity: true)

        for graph in StartupSplashGraph.allCases {
            let tileLayer = CALayer()
            tileLayer.bounds = CGRect(origin: .zero, size: metrics.gridSize)
            tileLayer.position = metrics.center
            tileLayer.contents = launchImage
            tileLayer.contentsScale = window?.screen.scale ?? UIScreen.main.scale
            tileLayer.contentsGravity = .resize
            tileLayer.minificationFilter = .trilinear
            tileLayer.magnificationFilter = .linear
            tileLayer.transform = scaleTransform(StartupSplashTimeline.compactScale)
            tileLayer.opacity = graph == .center ? 1 : 0
            layer.addSublayer(tileLayer)
            tileLayers.append(tileLayer)
        }
    }

    private func addAnimations(startTime: CFTimeInterval, metrics: Metrics) {
        let visualDuration = StartupSplashTimeline.clusterDuration
            + StartupSplashTimeline.splitDuration
            + StartupSplashTimeline.zoomDuration
        let splitEnd = StartupSplashTimeline.clusterDuration
            + StartupSplashTimeline.splitDuration
        let fadeStart = splitEnd + StartupSplashTimeline.zoomDuration * 0.28
        let splitKeyTime = StartupSplashTimeline.clusterDuration / visualDuration
        let zoomKeyTime = splitEnd / visualDuration
        let fadeKeyTime = fadeStart / visualDuration
        let positionKeyTimes: [NSNumber] = [NSNumber(value: 0),
                                            NSNumber(value: splitKeyTime),
                                            NSNumber(value: zoomKeyTime),
                                            NSNumber(value: 1)]
        let opacityKeyTimes: [NSNumber] = [NSNumber(value: 0),
                                           NSNumber(value: splitKeyTime),
                                           NSNumber(value: zoomKeyTime),
                                           NSNumber(value: fadeKeyTime),
                                           NSNumber(value: 1)]

        for (index, graph) in StartupSplashGraph.allCases.enumerated() {
            let tileLayer = tileLayers[index]
            let splitPosition = StartupSplashTimeline.graphCenter(
                for: graph,
                around: metrics.center,
                separation: metrics.verticalSeparation,
                progress: 1)
            let finalPosition = StartupSplashTimeline.zoomedPosition(
                for: splitPosition,
                around: metrics.center,
                scale: StartupSplashTimeline.zoomScale)

            tileLayer.position = finalPosition
            tileLayer.transform = scaleTransform(StartupSplashTimeline.zoomScale)
            tileLayer.opacity = 0

            let position = CAKeyframeAnimation(keyPath: "position")
            position.values = [
                NSValue(cgPoint: metrics.center),
                NSValue(cgPoint: metrics.center),
                NSValue(cgPoint: splitPosition),
                NSValue(cgPoint: finalPosition)
            ]
            position.keyTimes = positionKeyTimes
            position.calculationMode = .linear

            let transform = CAKeyframeAnimation(keyPath: "transform")
            transform.values = [
                NSValue(caTransform3D: scaleTransform(StartupSplashTimeline.compactScale)),
                NSValue(caTransform3D: scaleTransform(StartupSplashTimeline.compactScale)),
                NSValue(caTransform3D: scaleTransform(1)),
                NSValue(caTransform3D: scaleTransform(StartupSplashTimeline.zoomScale))
            ]
            transform.keyTimes = positionKeyTimes
            transform.calculationMode = .linear

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            if graph == .center {
                opacity.values = [1, 1, 1, 1, 0]
            } else {
                opacity.values = [0, 0, 1, 1, 0]
            }
            opacity.keyTimes = opacityKeyTimes
            opacity.calculationMode = .linear

            let group = CAAnimationGroup()
            group.animations = [position, transform, opacity]
            group.beginTime = startTime
            group.duration = visualDuration
            group.fillMode = .both
            group.isRemovedOnCompletion = false
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            tileLayer.add(group, forKey: "startupSplash")
        }

        backgroundLayer.opacity = 0
        backgroundLayer.add(fadeAnimation(from: 1,
                                          to: 0,
                                          beginTime: startTime + splitEnd - 0.08,
                                          duration: StartupSplashTimeline.zoomDuration + 0.08),
                            forKey: "startupSplashBackgroundFade")
    }

    private func fadeAnimation(from: Float,
                               to: Float,
                               beginTime: CFTimeInterval,
                               duration: TimeInterval) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.beginTime = beginTime
        animation.duration = duration
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }

    private func scaleTransform(_ scale: CGFloat) -> CATransform3D {
        CATransform3DMakeScale(scale, scale, 1)
    }

    private func rasterizedLaunchImage(size: CGSize, scale: CGFloat) -> CGImage? {
        guard size.width > 0, size.height > 0,
              let source = UIImage(named: "LaunchTiles") else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }

    private struct Metrics {
        let center: CGPoint
        let gridSize: CGSize
        let verticalSeparation: CGFloat

        init(container: CGSize) {
            center = CGPoint(x: container.width / 2,
                             y: container.height / 2)
            let width = min(max(container.width - 48, 220), 360)
            let gap: CGFloat = 3
            let cell = max(7, min(13, (width - CGFloat(StartupSplashAnimationView.columns - 1) * gap)
                                   / CGFloat(StartupSplashAnimationView.columns)))
            let pitch = cell + gap
            gridSize = CGSize(width: CGFloat(StartupSplashAnimationView.columns) * pitch - gap,
                              height: CGFloat(StartupSplashAnimationView.rows) * pitch - gap)
            verticalSeparation = gridSize.height + cell * 2
        }
    }
}
