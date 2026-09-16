import SwiftUI
import UIKit

/// Keeps the habit list scrollable while sorting.
///
/// SwiftUI `List` + `EditMode` adds collection-wide long-press/pan recognizers
/// so a drag on a habit card starts a reorder. Together with the row swipe pan
/// that hang never returns to idle (TestFlight watchdog). Disable those extra
/// collection gestures while sorting; a row moves only after a short press on
/// that row. The collection's own scroll pan stays enabled until that press
/// becomes a move.
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

/// Press-and-drag on a sorting-mode row. Idle pans still scroll the list;
/// auto-scroll runs only while this press is moving an item.
enum SortingReorderPolicy {
    static let pressDuration: TimeInterval = 0.25
    static let allowableMovement: CGFloat = 20
    static let edgeBand: CGFloat = 56
    static let maxSpeed: CGFloat = 360

    static func autoScrollTranslation(locationY: CGFloat,
                                      viewportMinY: CGFloat,
                                      viewportMaxY: CGFloat,
                                      dt: TimeInterval) -> CGFloat {
        guard dt > 0, viewportMaxY > viewportMinY else { return 0 }
        let band = edgeBand
        let top = viewportMinY + band
        let bottom = viewportMaxY - band
        let step = CGFloat(dt) * maxSpeed
        if locationY < top {
            let depth = min(1, (top - locationY) / band)
            return -step * depth
        }
        if locationY > bottom {
            let depth = min(1, (locationY - bottom) / band)
            return step * depth
        }
        return 0
    }

    static func clampedOffset(_ y: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(max, Swift.max(min, y))
    }
}

/// Starts a list reorder after a short press anywhere on the row. The list
/// stays a vertical scroll surface until that press is recognized.
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
        private var recognizer: UILongPressGestureRecognizer?
        private weak var host: UIView?
        private weak var movingCollection: UICollectionView?
        private var suppressed: [UIGestureRecognizer] = []
        private var displayLink: CADisplayLink?

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
            let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed))
            press.minimumPressDuration = SortingReorderPolicy.pressDuration
            press.allowableMovement = SortingReorderPolicy.allowableMovement
            press.cancelsTouchesInView = true
            press.delegate = self
            recognizer = press
            host = container
            container.addGestureRecognizer(press)
            suppressCompetingRecognizers(on: container, besides: press)
        }

        func detach() {
            stopAutoScroll()
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
            gestureRecognizer === recognizer && host != nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }

        @objc private func pressed(_ press: UILongPressGestureRecognizer) {
            guard let container = host,
                  let collection = enclosingCollectionView(from: container) else { return }
            switch press.state {
            case .began:
                guard let cell = container as? UICollectionViewCell,
                      let indexPath = collection.indexPath(for: cell) else { return }
                cancelTracking(collection.panGestureRecognizer)
                if collection.beginInteractiveMovementForItem(at: indexPath) {
                    movingCollection = collection
                    collection.updateInteractiveMovementTargetPosition(press.location(in: collection))
                    startAutoScroll()
                }
            case .changed:
                movingCollection?.updateInteractiveMovementTargetPosition(press.location(in: collection))
            case .ended:
                stopAutoScroll()
                movingCollection?.endInteractiveMovement()
                movingCollection = nil
            case .cancelled, .failed:
                stopAutoScroll()
                movingCollection?.cancelInteractiveMovement()
                movingCollection = nil
            default:
                break
            }
        }

        private func startAutoScroll() {
            stopAutoScroll()
            let link = CADisplayLink(target: self, selector: #selector(autoScrollTick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        private func stopAutoScroll() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func autoScrollTick(_ link: CADisplayLink) {
            guard let collection = movingCollection,
                  let press = recognizer else { return }
            let location = press.location(in: collection)
            let visibleMin = collection.bounds.minY + collection.adjustedContentInset.top
            let visibleMax = collection.bounds.maxY - collection.adjustedContentInset.bottom
            let delta = SortingReorderPolicy.autoScrollTranslation(
                locationY: location.y,
                viewportMinY: visibleMin,
                viewportMaxY: visibleMax,
                dt: link.duration)
            if delta != 0 {
                let minY = -collection.adjustedContentInset.top
                let maxY = max(minY,
                               collection.contentSize.height
                                - collection.bounds.height
                                + collection.adjustedContentInset.bottom)
                var offset = collection.contentOffset
                offset.y = SortingReorderPolicy.clampedOffset(offset.y + delta,
                                                              min: minY,
                                                              max: maxY)
                collection.setContentOffset(offset, animated: false)
            }
            collection.updateInteractiveMovementTargetPosition(press.location(in: collection))
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
    }
}
