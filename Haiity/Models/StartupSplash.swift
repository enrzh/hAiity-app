import Foundation
import CoreGraphics

enum StartupSplashPhase: Equatable {
    case cluster
    case split
    case zoom
    case finished
}

enum StartupSplashGraph: CaseIterable {
    case top
    case center
    case bottom
}

enum StartupSplashTimeline {
    private static let runtimeScale: TimeInterval = 1

    static let clusterDuration: TimeInterval = 0.24 * runtimeScale
    static let splitDuration: TimeInterval = 0.80 * runtimeScale
    static let zoomDuration: TimeInterval = 0.72 * runtimeScale
    static let handoffDuration: TimeInterval = 0.16 * runtimeScale
    static let startDelay: TimeInterval = 0.05 * runtimeScale
    static let compactScale: CGFloat = 0.36
    static let zoomScale: CGFloat = 7.5
    static let duration = clusterDuration + splitDuration + zoomDuration + handoffDuration

    static func phase(at elapsed: TimeInterval) -> StartupSplashPhase {
        let elapsed = max(0, elapsed)
        if elapsed < clusterDuration { return .cluster }
        if elapsed < clusterDuration + splitDuration { return .split }
        if elapsed < duration { return .zoom }
        return .finished
    }

    static func tileOpacity(for phase: StartupSplashPhase) -> Double {
        switch phase {
        case .cluster, .split: return 1.0
        case .zoom, .finished: return 0.0
        }
    }

    static func splitProgress(at elapsed: TimeInterval) -> CGFloat {
        eased(progress(at: elapsed - clusterDuration, duration: splitDuration))
    }

    static func zoomProgress(at elapsed: TimeInterval) -> CGFloat {
        eased(progress(at: elapsed - clusterDuration - splitDuration,
                       duration: zoomDuration))
    }

    static func graphOpacity(for graph: StartupSplashGraph,
                             at elapsed: TimeInterval) -> Double {
        switch graph {
        case .center: return 1
        case .top, .bottom: return Double(splitProgress(at: elapsed))
        }
    }

    static func graphCenter(for graph: StartupSplashGraph,
                            around center: CGPoint,
                            separation: CGFloat,
                            progress: CGFloat) -> CGPoint {
        let progress = max(0, min(1, progress))
        let direction: CGFloat
        switch graph {
        case .top: direction = -1
        case .center: direction = 0
        case .bottom: direction = 1
        }
        return CGPoint(x: center.x,
                       y: center.y + direction * separation * progress)
    }

    static func resolvedContainerSize(measured: CGSize, fallback: CGSize) -> CGSize {
        guard measured.width > 0, measured.height > 0 else { return fallback }
        return measured
    }

    static func tileOpacity(at elapsed: TimeInterval) -> Double {
        let zoom = zoomProgress(at: elapsed)
        // Keep the last split frame readable, then fade the grid while it
        // expands so the mounted app is revealed instead of blinking in.
        let fade = max(0, min(1, (zoom - 0.28) / 0.72))
        return 1 - Double(eased(fade))
    }

    static func overlayOpacity(at elapsed: TimeInterval) -> Double {
        let zoomStart = clusterDuration + splitDuration
        // Start a few frames before zoom so the first zoom frame is already
        // revealing the mounted app instead of exposing a hard boundary.
        let revealStart = zoomStart - 0.08
        let revealDuration = zoomDuration + 0.08
        let reveal = eased(progress(at: elapsed - revealStart,
                                    duration: revealDuration))
        return 1 - Double(reveal)
    }

    private static func progress(at elapsed: TimeInterval,
                                 duration: TimeInterval) -> CGFloat {
        guard elapsed > 0 else { return 0 }
        guard duration > 0 else { return 1 }
        return CGFloat(min(1, elapsed / duration))
    }

    private static func eased(_ value: CGFloat) -> CGFloat {
        let t = max(0, min(1, value))
        return t * t * (3 - 2 * t)
    }

    static func zoomedPosition(for position: CGPoint,
                               around center: CGPoint,
                               scale: CGFloat) -> CGPoint {
        CGPoint(x: center.x + (position.x - center.x) * scale,
                y: center.y + (position.y - center.y) * scale)
    }

    static func graphScale(splitProgress: CGFloat,
                           zoomProgress: CGFloat) -> CGFloat {
        let split = max(0, min(1, splitProgress))
        let zoom = max(0, min(1, zoomProgress))
        let compact = compactScale + (1 - compactScale) * split
        return compact * (1 + (zoomScale - 1) * zoom)
    }
}
