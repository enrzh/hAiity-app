import Foundation
import CoreGraphics

enum StartupSplashPhase: Equatable {
    case cluster
    case spread
    case zoom
    case finished
}

enum StartupSplashTimeline {
    private static let runtimeScale: TimeInterval = 1

    static let clusterDuration: TimeInterval = 0.24 * runtimeScale
    static let spreadDuration: TimeInterval = 0.72 * runtimeScale
    static let zoomDuration: TimeInterval = 0.64 * runtimeScale
    static let zoomScale: CGFloat = 7.5
    static let duration = clusterDuration + spreadDuration + zoomDuration

    static func phase(at elapsed: TimeInterval) -> StartupSplashPhase {
        let elapsed = max(0, elapsed)
        if elapsed < clusterDuration { return .cluster }
        if elapsed < clusterDuration + spreadDuration { return .spread }
        if elapsed < duration { return .zoom }
        return .finished
    }

    static func tileOpacity(for phase: StartupSplashPhase) -> Double {
        switch phase {
        case .cluster, .spread: return 1.0
        case .zoom, .finished: return 0.0
        }
    }

    static func zoomedPosition(for position: CGPoint,
                               around center: CGPoint,
                               scale: CGFloat) -> CGPoint {
        CGPoint(x: center.x + (position.x - center.x) * scale,
                y: center.y + (position.y - center.y) * scale)
    }
}
