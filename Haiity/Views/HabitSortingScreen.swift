import SwiftUI
import UIKit

private struct HabitInlineSortingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var habitInlineSortingActive: Bool {
        get { self[HabitInlineSortingKey.self] }
        set { self[HabitInlineSortingKey.self] = newValue }
    }
}

/// Matches `ContentView.habitList`: header section 0, habits section 1.
enum HabitListLayout {
    static let habitSectionIndex = 1
}

/// One controller for the whole habits list. Idle pans still scroll;
/// a recognized press locks the list pan and reorders by crossing row frames.
/// No `EditMode`, no per-row overlay, no system grabber.
struct HabitSortingSession: UIViewRepresentable {
    var active: Bool
    let move: (IndexSet, Int, Bool) -> Void
    let persist: () -> Void

    func makeUIView(context: Context) -> Host {
        let host = Host(move: move, persist: persist)
        host.isUserInteractionEnabled = false
        host.isHidden = true
        host.active = active
        return host
    }

    func updateUIView(_ view: Host, context: Context) {
        view.move = move
        view.persist = persist
        view.active = active
        view.reconcile()
    }

    static func dismantleUIView(_ view: Host, coordinator: ()) {
        view.active = false
        view.detach(persistIfDragging: true)
    }

    final class Host: UIView, UIGestureRecognizerDelegate {
        var move: (IndexSet, Int, Bool) -> Void
        var persist: () -> Void
        var active = false {
            didSet {
                if oldValue != active { reconcile() }
            }
        }

        private weak var collectionView: UICollectionView?
        private var recognizer: UILongPressGestureRecognizer?
        private var displayLink: CADisplayLink?
        private var dragging = false
        private var currentIndex: Int?
        private var lift: UIView?
        private var liftGrabOffset: CGPoint = .zero
        private var liftSize: CGSize = .zero

        init(move: @escaping (IndexSet, Int, Bool) -> Void,
             persist: @escaping () -> Void) {
            self.move = move
            self.persist = persist
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        deinit { detach(persistIfDragging: false) }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            reconcile()
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            reconcile()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if collectionView?.window != nil, recognizer != nil || !active { return }
            reconcile()
        }

        func reconcile() {
            guard window != nil, active else {
                detach(persistIfDragging: dragging)
                return
            }
            guard let collection = enclosingCollectionView() else { return }
            collectionView = collection
            collection.dragInteractionEnabled = false
            if recognizer == nil {
                let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed))
                press.minimumPressDuration = CustomHabitReorderPolicy.pressDuration
                press.allowableMovement = CustomHabitReorderPolicy.allowableMovement
                press.cancelsTouchesInView = true
                press.delegate = self
                recognizer = press
                collection.addGestureRecognizer(press)
            }
        }

        func detach(persistIfDragging: Bool) {
            stopAutoScroll()
            removeLift()
            if dragging {
                dragging = false
                currentIndex = nil
                if persistIfDragging { persist() }
            }
            if let collection = collectionView {
                restorePlaceholders(in: collection)
                unlockListScroll(collection)
                collection.dragInteractionEnabled = true
                if let recognizer {
                    collection.removeGestureRecognizer(recognizer)
                }
            }
            recognizer = nil
            collectionView = nil
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === recognizer,
                  let collection = collectionView else { return false }
            let point = gestureRecognizer.location(in: collection)
            return habitIndex(at: point, in: collection) != nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            guard !dragging,
                  let collection = collectionView,
                  other === collection.panGestureRecognizer else {
                return false
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            false
        }

        @objc private func pressed(_ press: UILongPressGestureRecognizer) {
            guard let collection = collectionView ?? enclosingCollectionView() else { return }
            collectionView = collection

            switch press.state {
            case .began:
                let point = press.location(in: collection)
                guard let index = habitIndex(at: point, in: collection) else { return }
                dragging = true
                currentIndex = index
                lockListScroll(collection)
                NotificationCenter.default.post(name: .swipeRevealDismissAll, object: nil)
                beginLift(at: index, press: press, in: collection)
                syncPlaceholder(in: collection)
                Theme.Haptics.select()
                startAutoScroll()
            case .changed:
                applyFinger(press, in: collection)
                moveLift(press, in: collection)
            case .ended:
                applyFinger(press, in: collection)
                finishDrag(in: collection, save: true)
            case .cancelled, .failed:
                finishDrag(in: collection, save: dragging)
            default:
                break
            }
        }

        private func applyFinger(_ press: UILongPressGestureRecognizer,
                                 in collection: UICollectionView) {
            guard dragging, let from = currentIndex else { return }
            let y = press.location(in: collection).y
            let frames = habitFrames(in: collection)
            let target = CustomHabitReorderPolicy.destinationIndex(
                fingerY: y, frames: frames, current: from)
            guard target != from else { return }
            CustomHabitReorderPolicy.applyMove(from: from, to: target, persist: false, move: move)
            currentIndex = target
            collection.layoutIfNeeded()
            syncPlaceholder(in: collection)
        }

        private func finishDrag(in collection: UICollectionView, save: Bool) {
            stopAutoScroll()
            if save { persist() }
            collection.layoutIfNeeded()
            syncPlaceholder(in: collection)
            settleLift(in: collection) { [weak self] in
                guard let self else { return }
                self.restorePlaceholders(in: collection)
                self.dragging = false
                self.currentIndex = nil
                self.unlockListScroll(collection)
            }
        }

        private func beginLift(at index: Int,
                               press: UILongPressGestureRecognizer,
                               in collection: UICollectionView) {
            removeLift()
            guard let cell = collection.cellForItem(
                at: IndexPath(item: index, section: HabitListLayout.habitSectionIndex)),
                  let window = collection.window else { return }
            let renderer = UIGraphicsImageRenderer(bounds: cell.bounds)
            let image = renderer.image { _ in
                cell.drawHierarchy(in: cell.bounds, afterScreenUpdates: true)
            }
            let snapshot = UIImageView(image: image)
            snapshot.frame = CGRect(origin: .zero, size: cell.bounds.size)
            snapshot.contentMode = .scaleToFill
            snapshot.clipsToBounds = true
            snapshot.layer.cornerRadius = Theme.Metrics.cardRadius
            snapshot.layer.cornerCurve = .continuous

            let card = UIView(frame: .zero)
            card.layer.shadowColor = UIColor.black.cgColor
            card.layer.shadowOpacity = CustomHabitReorderPolicy.liftShadowOpacity
            card.layer.shadowRadius = CustomHabitReorderPolicy.liftShadowRadius
            card.layer.shadowOffset = CustomHabitReorderPolicy.liftShadowOffset
            card.layer.shadowPath = UIBezierPath(
                roundedRect: cell.bounds,
                cornerRadius: Theme.Metrics.cardRadius).cgPath
            card.isUserInteractionEnabled = false
            card.addSubview(snapshot)
            let frame = collection.convert(cell.frame, to: window)
            card.frame = frame
            window.addSubview(card)
            let finger = press.location(in: window)
            liftGrabOffset = CGPoint(x: finger.x - frame.minX, y: finger.y - frame.minY)
            liftSize = frame.size
            lift = card
            UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                card.transform = CGAffineTransform(scaleX: CustomHabitReorderPolicy.liftScale,
                                                   y: CustomHabitReorderPolicy.liftScale)
            }
        }

        private func moveLift(_ press: UILongPressGestureRecognizer,
                              in collection: UICollectionView) {
            guard let lift, let window = collection.window ?? lift.window else { return }
            let origin = CustomHabitReorderPolicy.liftOrigin(
                finger: press.location(in: window),
                grabOffset: liftGrabOffset)
            lift.center = CGPoint(x: origin.x + liftSize.width / 2,
                                  y: origin.y + liftSize.height / 2)
        }

        private func settleLift(in collection: UICollectionView, completion: @escaping () -> Void) {
            guard let lift else {
                completion()
                return
            }
            let window = collection.window ?? lift.window
            let target: CGRect
            if let index = currentIndex,
               let cell = collection.cellForItem(
                at: IndexPath(item: index, section: HabitListLayout.habitSectionIndex)),
               let window {
                target = collection.convert(cell.frame, to: window)
            } else if let window {
                target = CGRect(
                    origin: CustomHabitReorderPolicy.liftOrigin(
                        finger: recognizer?.location(in: window) ?? lift.center,
                        grabOffset: liftGrabOffset),
                    size: liftSize)
            } else {
                target = lift.frame
            }
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn]) {
                lift.transform = .identity
                lift.frame = target
                lift.layer.shadowOpacity = 0
            } completion: { _ in
                self.removeLift()
                completion()
            }
        }

        private func removeLift() {
            lift?.removeFromSuperview()
            lift = nil
            liftGrabOffset = .zero
            liftSize = .zero
        }

        private func syncPlaceholder(in collection: UICollectionView) {
            guard dragging, let currentIndex else {
                restorePlaceholders(in: collection)
                return
            }
            for cell in collection.visibleCells {
                let path = collection.indexPath(for: cell)
                let hidden = path?.section == HabitListLayout.habitSectionIndex
                    && path?.item == currentIndex
                cell.alpha = hidden ? 0 : 1
            }
        }

        private func restorePlaceholders(in collection: UICollectionView) {
            for cell in collection.visibleCells {
                cell.alpha = 1
            }
        }

        private func lockListScroll(_ collection: UICollectionView) {
            collection.isScrollEnabled = false
            collection.panGestureRecognizer.isEnabled = false
        }

        private func unlockListScroll(_ collection: UICollectionView) {
            collection.isScrollEnabled = true
            collection.panGestureRecognizer.isEnabled = true
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
            guard dragging,
                  let collection = collectionView,
                  let press = recognizer,
                  CustomHabitReorderPolicy.locksListScroll(dragActive: true) else { return }
            let location = press.location(in: collection)
            let viewport = sortableViewport(in: collection)
            let delta = CustomHabitReorderPolicy.autoScrollTranslation(
                locationY: location.y,
                viewportMinY: viewport.minY,
                viewportMaxY: viewport.maxY,
                dt: link.duration)
            if delta != 0 {
                let minY = -collection.adjustedContentInset.top
                let maxY = max(minY,
                               collection.contentSize.height
                                - collection.bounds.height
                                + collection.adjustedContentInset.bottom)
                var offset = collection.contentOffset
                offset.y = CustomHabitReorderPolicy.clampedOffset(offset.y + delta,
                                                                  min: minY,
                                                                  max: maxY)
                collection.setContentOffset(offset, animated: false)
            }
            applyFinger(press, in: collection)
            moveLift(press, in: collection)
            syncPlaceholder(in: collection)
        }

        private func sortableViewport(in collection: UICollectionView) -> CustomHabitReorderPolicy.Viewport {
            CustomHabitReorderPolicy.chromeViewport(
                boundsMinY: collection.bounds.minY,
                boundsMaxY: collection.bounds.maxY,
                adjustedTop: collection.adjustedContentInset.top,
                adjustedBottom: collection.adjustedContentInset.bottom,
                safeTop: collection.safeAreaInsets.top,
                safeBottom: collection.safeAreaInsets.bottom)
        }

        private func habitIndex(at point: CGPoint, in collection: UICollectionView) -> Int? {
            if let path = collection.indexPathForItem(at: point),
               path.section == HabitListLayout.habitSectionIndex {
                return path.item
            }
            for cell in collection.visibleCells {
                guard collection.indexPath(for: cell)?.section == HabitListLayout.habitSectionIndex,
                      cell.frame.contains(point) else { continue }
                return collection.indexPath(for: cell)?.item
            }
            return nil
        }

        private func habitFrames(in collection: UICollectionView) -> [CGRect] {
            let section = HabitListLayout.habitSectionIndex
            let count = collection.numberOfItems(inSection: section)
            return (0..<count).compactMap { item in
                collection.layoutAttributesForItem(
                    at: IndexPath(item: item, section: section))?.frame
            }
        }

        private func enclosingCollectionView() -> UICollectionView? {
            if let collectionView, collectionView.window != nil {
                return collectionView
            }
            var ancestor: UIView? = superview
            while let current = ancestor {
                if let collection = current as? UICollectionView { return collection }
                ancestor = current.superview
            }
            ancestor = superview
            while let current = ancestor {
                if let found = nearbyCollection(from: current) { return found }
                ancestor = current.superview
            }
            return nil
        }

        private func nearbyCollection(from root: UIView) -> UICollectionView? {
            if let collection = root as? UICollectionView { return collection }
            for subview in root.subviews {
                if let collection = subview as? UICollectionView { return collection }
            }
            for subview in root.subviews {
                for nested in subview.subviews {
                    if let collection = nested as? UICollectionView { return collection }
                }
            }
            return nil
        }
    }
}

enum CustomHabitReorderPolicy {
    static let pressDuration: TimeInterval = 0.25
    static let allowableMovement: CGFloat = 20
    static let edgeBand: CGFloat = 56
    static let maxSpeed: CGFloat = 360
    static let liftScale: CGFloat = 1.04
    static let liftShadowOpacity: Float = 0.28
    static let liftShadowRadius: CGFloat = 18
    static let liftShadowOffset = CGSize(width: 0, height: 10)

    struct Viewport {
        var minY: CGFloat
        var maxY: CGFloat
    }

    static func locksListScroll(dragActive: Bool) -> Bool {
        dragActive
    }

    /// One neighbour at a time, only after the finger crosses that neighbour's
    /// midpoint. Frame-containment ping-pongs a short reminder through a tall
    /// habit: after the swap the finger is still inside the habit.
    static func destinationIndex(fingerY: CGFloat,
                                 frames: [CGRect],
                                 current: Int) -> Int {
        guard !frames.isEmpty else { return current }
        let bounded = min(max(current, 0), frames.count - 1)
        if bounded + 1 < frames.count, fingerY > frames[bounded + 1].midY {
            return bounded + 1
        }
        if bounded > 0, fingerY < frames[bounded - 1].midY {
            return bounded - 1
        }
        return bounded
    }

    static func liftOrigin(finger: CGPoint, grabOffset: CGPoint) -> CGPoint {
        CGPoint(x: finger.x - grabOffset.x, y: finger.y - grabOffset.y)
    }

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

    static func chromeViewport(boundsMinY: CGFloat,
                               boundsMaxY: CGFloat,
                               adjustedTop: CGFloat,
                               adjustedBottom: CGFloat,
                               safeTop: CGFloat,
                               safeBottom: CGFloat) -> Viewport {
        let minY = boundsMinY + max(adjustedTop, safeTop)
        let maxY = boundsMaxY - max(adjustedBottom, safeBottom)
        guard maxY > minY else {
            return Viewport(minY: boundsMinY, maxY: boundsMaxY)
        }
        return Viewport(minY: minY, maxY: maxY)
    }

    static func applyMove(from sourceIndex: Int,
                          to destinationIndex: Int,
                          persist: Bool,
                          move: (IndexSet, Int, Bool) -> Void) {
        guard sourceIndex != destinationIndex else { return }
        let toOffset = destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
        move(IndexSet(integer: sourceIndex), toOffset, persist)
    }
}

#if DEBUG
enum CustomHabitReorderPolicyTestsHook {
    static func destinationOffset(from sourceIndex: Int, to destinationIndex: Int) -> Int {
        destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
    }
}
#endif
