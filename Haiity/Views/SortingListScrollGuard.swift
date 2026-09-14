import SwiftUI
import UIKit

/// Keeps the habit list scrollable while sorting.
///
/// SwiftUI `List` + `EditMode` adds collection-wide long-press/pan recognizers
/// so a drag on a habit card starts a reorder. Together with the row swipe pan
/// that hang never returns to idle (TestFlight watchdog). Disable those extra
/// collection gestures while sorting; only the trailing handle pan may move
/// an item. The collection's own scroll pan stays enabled.
struct SortingListScrollGuard: UIViewRepresentable {
    var active: Bool

    func makeUIView(context: Context) -> Host {
        let host = Host()
        host.isUserInteractionEnabled = false
        host.isHidden = true
        host.active = active
        return host
    }

    func updateUIView(_ view: Host, context: Context) {
        view.active = active
        view.apply()
    }

    static func dismantleUIView(_ view: Host, coordinator: ()) {
        view.active = false
        view.apply()
    }

    final class Host: UIView {
        var active = false
        private weak var collectionView: UICollectionView?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            apply()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            apply()
        }

        func apply() {
            guard let view = enclosingCollectionView() else { return }
            collectionView = view
            let scrollPan = view.panGestureRecognizer
            if view.dragInteractionEnabled == active {
                view.dragInteractionEnabled = !active
            }
            for recognizer in view.gestureRecognizers ?? [] where recognizer !== scrollPan {
                if recognizer is UILongPressGestureRecognizer || recognizer is UIPanGestureRecognizer {
                    recognizer.isEnabled = !active
                }
            }
        }

        private func enclosingCollectionView() -> UICollectionView? {
            if let collectionView, collectionView.window != nil {
                return collectionView
            }
            var ancestor: UIView? = superview
            while let current = ancestor {
                if let collection = current as? UICollectionView {
                    return collection
                }
                ancestor = current.superview
            }
            return nil
        }
    }
}

/// Starts a list reorder only from the trailing handle band. The rest of the
/// row stays a vertical scroll surface while sorting is active.
struct SortingReorderPan: UIViewRepresentable {
    func makeUIView(context: Context) -> Host {
        Host()
    }

    func updateUIView(_ view: Host, context: Context) {
        view.reconcileHostForUpdate()
    }

    static func dismantleUIView(_ view: Host, coordinator: ()) {
        view.detach()
    }

    final class Host: UIView, UIGestureRecognizerDelegate {
        private var recognizer: UIPanGestureRecognizer?
        private weak var host: UIView?
        private weak var movingCollection: UICollectionView?
        private var suppressed: [UIGestureRecognizer] = []

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        deinit { detach() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            reconcileHost()
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            reconcileHost()
        }

        fileprivate func reconcileHostForUpdate() {
            if host?.window != nil { return }
            reconcileHost()
        }

        private func reconcileHost() {
            guard window != nil else { detach(); return }
            var ancestor = superview
            var cell: UIView?
            while let view = ancestor {
                if view is UICollectionViewCell || view is UITableViewCell {
                    cell = view
                    break
                }
                ancestor = view.superview
            }
            guard let container = cell else { detach(); return }
            guard container !== host else { return }

            detach()
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
            pan.maximumNumberOfTouches = 1
            pan.cancelsTouchesInView = true
            pan.delegate = self
            recognizer = pan
            host = container
            container.addGestureRecognizer(pan)
            suppressCompetingRecognizers(on: container, besides: pan)
        }

        func detach() {
            if let movingCollection {
                movingCollection.cancelInteractiveMovement()
            }
            movingCollection = nil
            restoreSuppressedRecognizers()
            if let recognizer { host?.removeGestureRecognizer(recognizer) }
            recognizer = nil
            host = nil
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === recognizer, let container = host else { return false }
            let location = gestureRecognizer.location(in: container)
            return Self.isHandleLocation(location, in: container)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }

        @objc private func panned(_ pan: UIPanGestureRecognizer) {
            guard let container = host,
                  let collection = enclosingCollectionView(from: container) else { return }
            switch pan.state {
            case .began:
                guard let cell = container as? UICollectionViewCell,
                      let indexPath = collection.indexPath(for: cell) else { return }
                cancelTracking(collection.panGestureRecognizer)
                if collection.beginInteractiveMovementForItem(at: indexPath) {
                    movingCollection = collection
                    collection.updateInteractiveMovementTargetPosition(pan.location(in: collection))
                }
            case .changed:
                movingCollection?.updateInteractiveMovementTargetPosition(pan.location(in: collection))
            case .ended:
                movingCollection?.endInteractiveMovement()
                movingCollection = nil
            case .cancelled, .failed:
                movingCollection?.cancelInteractiveMovement()
                movingCollection = nil
            default:
                break
            }
        }

        private func enclosingCollectionView(from view: UIView) -> UICollectionView? {
            var ancestor: UIView? = view
            while let current = ancestor {
                if let collection = current as? UICollectionView { return collection }
                ancestor = current.superview
            }
            return nil
        }

        private func suppressCompetingRecognizers(on container: UIView,
                                                  besides keep: UIGestureRecognizer) {
            restoreSuppressedRecognizers()
            for recognizer in container.gestureRecognizers ?? [] where recognizer !== keep {
                if recognizer is UILongPressGestureRecognizer || recognizer is UIPanGestureRecognizer,
                   recognizer.isEnabled {
                    recognizer.isEnabled = false
                    suppressed.append(recognizer)
                }
            }
        }

        private func restoreSuppressedRecognizers() {
            for recognizer in suppressed {
                recognizer.isEnabled = true
            }
            suppressed.removeAll()
        }

        private func cancelTracking(_ recognizer: UIGestureRecognizer?) {
            guard let recognizer else { return }
            recognizer.isEnabled = false
            recognizer.isEnabled = true
        }

        static func isHandleLocation(_ location: CGPoint, in container: UIView) -> Bool {
            let band = Theme.Metrics.hit
            if container.effectiveUserInterfaceLayoutDirection == .rightToLeft {
                return location.x <= band
            }
            return location.x >= container.bounds.maxX - band
        }
    }
}
