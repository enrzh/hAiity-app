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
    var habitIDs: [UUID]
    let move: (IndexSet, Int, Bool) -> Void
    let persist: () -> Void
    let onDraggingIDChange: (UUID?) -> Void

    func makeUIView(context: Context) -> Host {
        let host = Host(habitIDs: habitIDs, move: move, persist: persist,
                        onDraggingIDChange: onDraggingIDChange)
        host.isUserInteractionEnabled = false
        host.isHidden = true
        host.active = active
        return host
    }

    func updateUIView(_ view: Host, context: Context) {
        view.move = move
        view.persist = persist
        view.onDraggingIDChange = onDraggingIDChange
        if !view.isDragging {
            view.habitIDs = habitIDs
        }
        view.active = active
        view.reconcile()
    }

    static func dismantleUIView(_ view: Host, coordinator: ()) {
        view.active = false
        view.detach(persistIfDragging: true)
    }

    final class Host: UIView, UIGestureRecognizerDelegate {
        var habitIDs: [UUID]
        var move: (IndexSet, Int, Bool) -> Void
        var persist: () -> Void
        var onDraggingIDChange: (UUID?) -> Void
        var active = false {
            didSet {
                if oldValue != active { reconcile() }
            }
        }
        var isDragging: Bool { dragging }

        private weak var collectionView: UICollectionView?
        private var recognizer: UILongPressGestureRecognizer?
        private var displayLink: CADisplayLink?
        private var dragging = false
        private var orderChanged = false
        private var currentIndex: Int?
        private var lift: UIView?
        private var liftGrabOffset: CGPoint = .zero
        private var liftSize: CGSize = .zero
        private var rowHeights: [CGFloat] = []
        private var rowSpacing: CGFloat = 0
        private var sectionMinY: CGFloat = 0
        private var sectionOffsetY: CGFloat = 0
        private var lastMoveAt: TimeInterval?
        private var lastMoveFingerY: CGFloat?
        private var lastMoveDelta = 0
        private var draggingID: UUID?

        init(habitIDs: [UUID],
             move: @escaping (IndexSet, Int, Bool) -> Void,
             persist: @escaping () -> Void,
             onDraggingIDChange: @escaping (UUID?) -> Void) {
            self.habitIDs = habitIDs
            self.move = move
            self.persist = persist
            self.onDraggingIDChange = onDraggingIDChange
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
            guard active else {
                detach(persistIfDragging: dragging)
                return
            }
            if window == nil {
                if !dragging { detach(persistIfDragging: false) }
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
            }
            attachPress(to: collection)
        }

        func detach(persistIfDragging: Bool) {
            stopAutoScroll()
            removeLift()
            if dragging {
                dragging = false
                currentIndex = nil
                lastMoveAt = nil
                lastMoveFingerY = nil
                lastMoveDelta = 0
                rowHeights = []
                setDraggingID(nil)
                if persistIfDragging, orderChanged { persist() }
            }
            orderChanged = false
            if let collection = collectionView {
                restorePlaceholders(in: collection)
                unlockListScroll(collection)
                collection.dragInteractionEnabled = true
            }
            if let recognizer {
                recognizer.view?.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            collectionView = nil
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard active, !dragging, gestureRecognizer === recognizer,
                  let collection = collectionView, let window = collection.window,
                  let touched = window.hitTest(gestureRecognizer.location(in: window), with: nil),
                  touched === collection || touched.isDescendant(of: collection)
            else { return false }
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
            dragging && gestureRecognizer === recognizer
        }

        @objc private func pressed(_ press: UILongPressGestureRecognizer) {
            guard let collection = collectionView ?? enclosingCollectionView() else { return }
            collectionView = collection

            switch press.state {
            case .began:
                let point = press.location(in: collection)
                guard let index = habitIndex(at: point, in: collection) else { return }
                dragging = true
                orderChanged = false
                currentIndex = index
                captureRowMetrics(in: collection)
                lastMoveAt = nil
                lastMoveFingerY = nil
                lastMoveDelta = 0
                lockListScroll(collection)
                NotificationCenter.default.post(name: .swipeRevealDismissAll, object: nil)
                beginLift(at: index, press: press, in: collection)
                if habitIDs.indices.contains(index) {
                    setDraggingID(habitIDs[index])
                }
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
            guard collection.numberOfSections > HabitListLayout.habitSectionIndex,
                  collection.numberOfItems(inSection: HabitListLayout.habitSectionIndex) == habitIDs.count
            else {
                detach(persistIfDragging: true)
                return
            }
            refreshVisibleHeights(in: collection)
            let now = ProcessInfo.processInfo.systemUptime
            guard CustomHabitReorderPolicy.canApplyMove(now: now, lastMoveAt: lastMoveAt) else { return }
            let frames = logicalFrames(in: collection)
            let viewport = sortableViewport(in: collection)
            let fingerY = CustomHabitReorderPolicy.clampedValue(
                press.location(in: collection).y,
                min: viewport.minY,
                max: viewport.maxY)
            let target = CustomHabitReorderPolicy.destinationIndex(
                fingerY: fingerY,
                frames: frames,
                current: from,
                lastMoveFingerY: lastMoveFingerY,
                lastMoveDelta: lastMoveDelta)
            guard target != from else { return }
            CustomHabitReorderPolicy.applyMove(from: from, to: target, persist: false, move: move)
            orderChanged = true
            rowHeights = CustomHabitReorderPolicy.movedHeights(rowHeights, from: from, to: target)
            habitIDs = CustomHabitReorderPolicy.movedItems(habitIDs, from: from, to: target)
            currentIndex = target
            lastMoveAt = now
            lastMoveFingerY = fingerY
            lastMoveDelta = target > from ? 1 : -1
        }

        private func finishDrag(in collection: UICollectionView, save: Bool) {
            stopAutoScroll()
            if save, orderChanged { persist() }
            orderChanged = false
            settleLift(in: collection) { [weak self] in
                guard let self else { return }
                self.setDraggingID(nil)
                self.restorePlaceholders(in: collection)
                self.dragging = false
                self.currentIndex = nil
                self.lastMoveFingerY = nil
                self.lastMoveDelta = 0
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
            let snapshot = liftSnapshot(of: cell)

            let card = UIView(frame: .zero)
            card.layer.shadowColor = UIColor.black.cgColor
            card.layer.shadowOpacity = CustomHabitReorderPolicy.liftShadowOpacity
            card.layer.shadowRadius = CustomHabitReorderPolicy.liftShadowRadius
            card.layer.shadowOffset = CustomHabitReorderPolicy.liftShadowOffset
            card.layer.shadowPath = UIBezierPath(
                roundedRect: cell.bounds,
                cornerRadius: Theme.Metrics.cardRadius).cgPath
            card.isUserInteractionEnabled = false
            card.layer.zPosition = 10_000
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
            let band = movementBand(in: collection, window: window)
            let origin = CustomHabitReorderPolicy.lockedLiftOrigin(
                finger: press.location(in: window),
                grabOffset: liftGrabOffset,
                liftSize: liftSize,
                bandMinY: band.minY,
                bandMaxY: band.maxY)
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
                let band = movementBand(in: collection, window: window)
                target = CGRect(
                    origin: CustomHabitReorderPolicy.lockedLiftOrigin(
                        finger: recognizer?.location(in: window) ?? lift.center,
                        grabOffset: liftGrabOffset,
                        liftSize: liftSize,
                        bandMinY: band.minY,
                        bandMaxY: band.maxY),
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

        /// Pixel snapshot of the still-visible cell. Hiding first, then
        /// `afterScreenUpdates: true`, captures an empty view and leaves only
        /// the shadow wrapper.
        private func liftSnapshot(of cell: UICollectionViewCell) -> UIView {
            let bounds = cell.bounds
            let renderer = UIGraphicsImageRenderer(bounds: bounds)
            let image = renderer.image { ctx in
                if !cell.drawHierarchy(in: bounds, afterScreenUpdates: false),
                   !cell.drawHierarchy(in: bounds, afterScreenUpdates: true) {
                    cell.layer.render(in: ctx.cgContext)
                }
            }
            let snapshot = UIImageView(image: image)
            snapshot.contentMode = .scaleToFill
            snapshot.frame = CGRect(origin: .zero, size: bounds.size)
            snapshot.clipsToBounds = true
            snapshot.layer.cornerRadius = Theme.Metrics.cardRadius
            snapshot.layer.cornerCurve = .continuous
            snapshot.isUserInteractionEnabled = false
            return snapshot
        }

        /// Keep the press on the window so navbar/header chrome cannot cancel it.
        private func attachPress(to collection: UICollectionView) {
            guard let press = recognizer, !dragging else { return }
            let target: UIView = collection.window ?? collection
            if press.view === target { return }
            press.view?.removeGestureRecognizer(press)
            target.addGestureRecognizer(press)
        }

        private func movementBand(in collection: UICollectionView,
                                  window: UIWindow) -> CustomHabitReorderPolicy.Viewport {
            let chrome = sortableViewport(in: collection)
            let top = collection.convert(CGPoint(x: 0, y: chrome.minY), to: window).y
            let bottom = collection.convert(CGPoint(x: 0, y: chrome.maxY), to: window).y
            return CustomHabitReorderPolicy.Viewport(
                minY: min(top, bottom),
                maxY: max(top, bottom))
        }

        private func setDraggingID(_ id: UUID?) {
            guard draggingID != id else { return }
            draggingID = id
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                onDraggingIDChange(id)
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

        private func captureRowMetrics(in collection: UICollectionView) {
            let frames = habitFrames(in: collection)
            let count = collection.numberOfItems(inSection: HabitListLayout.habitSectionIndex)
            let fallback = frames.first(where: { $0.height > 1 })?.height ?? 56
            rowHeights = CustomHabitReorderPolicy.paddedHeights(
                frames.map(\.height), count: count, fallback: fallback)
            rowSpacing = 0
            if frames.count >= 2 {
                rowSpacing = max(0, frames[1].minY - frames[0].maxY)
            }
            sectionMinY = frames.first?.minY ?? 0
            sectionOffsetY = collection.contentOffset.y
        }

        private func logicalFrames(in collection: UICollectionView) -> [CGRect] {
            let count = collection.numberOfItems(inSection: HabitListLayout.habitSectionIndex)
            rowHeights = CustomHabitReorderPolicy.paddedHeights(
                rowHeights, count: count, fallback: rowHeights.last ?? 56)
            let originY = CustomHabitReorderPolicy.logicalOriginY(
                capturedSectionMinY: sectionMinY,
                contentOffsetY: collection.contentOffset.y,
                capturedOffsetY: sectionOffsetY)
            let width = collection.bounds.width
            return CustomHabitReorderPolicy.stackedFrames(
                heights: rowHeights, originY: originY, spacing: rowSpacing, width: width)
        }

        /// Off-screen rows often have no attributes or estimated 44 pt heights.
        /// As auto-scroll reveals them, replace those estimates with real frames.
        private func refreshVisibleHeights(in collection: UICollectionView) {
            let section = HabitListLayout.habitSectionIndex
            let count = collection.numberOfItems(inSection: section)
            rowHeights = CustomHabitReorderPolicy.paddedHeights(
                rowHeights, count: count, fallback: rowHeights.last ?? 56)
            var visible: [(index: Int, height: CGFloat)] = []
            if let attributes = collection.collectionViewLayout.layoutAttributesForElements(
                in: collection.bounds) {
                for attribute in attributes
                where attribute.representedElementCategory == .cell
                    && attribute.indexPath.section == section {
                    visible.append((attribute.indexPath.item, attribute.frame.height))
                }
            }
            for cell in collection.visibleCells {
                guard let path = collection.indexPath(for: cell),
                      path.section == section else { continue }
                visible.append((path.item, cell.frame.height))
            }
            rowHeights = CustomHabitReorderPolicy.mergedHeights(
                current: rowHeights,
                visible: visible,
                draggedIndex: currentIndex)
        }

        private func habitFrames(in collection: UICollectionView) -> [CGRect] {
            let section = HabitListLayout.habitSectionIndex
            let count = collection.numberOfItems(inSection: section)
            let width = collection.bounds.width
            let fallback = rowHeights.last ?? 56
            var frames: [CGRect] = []
            frames.reserveCapacity(count)
            for item in 0..<count {
                if let frame = collection.layoutAttributesForItem(
                    at: IndexPath(item: item, section: section))?.frame {
                    frames.append(frame)
                } else {
                    let y = frames.last.map { $0.maxY + rowSpacing } ?? sectionMinY
                    frames.append(CGRect(x: 0, y: y, width: width, height: fallback))
                }
            }
            return frames
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
    static let moveLockDuration: TimeInterval = 0.12
    static let moveHysteresis: CGFloat = 20
    static let reverseSlop: CGFloat = 28

    struct Viewport {
        var minY: CGFloat
        var maxY: CGFloat
    }

    static func locksListScroll(dragActive: Bool) -> Bool {
        dragActive
    }

    /// One neighbour at a time. Entering the next row by a small hysteresis
    /// is enough to swap — waiting for a tall habit's midpoint made dragging
    /// a reminder over a stack of habits look like a no-op. Reverse swaps
    /// stay locked until the finger recrosses the last swap point, otherwise
    /// the short row bounces back while the finger is still inside the habit.
    static func destinationIndex(fingerY: CGFloat,
                                 frames: [CGRect],
                                 current: Int,
                                 lastMoveFingerY: CGFloat? = nil,
                                 lastMoveDelta: Int = 0) -> Int {
        guard !frames.isEmpty else { return current }
        let bounded = min(max(current, 0), frames.count - 1)
        if bounded + 1 < frames.count {
            let next = frames[bounded + 1]
            let enter = next.minY + hysteresis(current: frames[bounded], neighbor: next)
            if fingerY > enter,
               allowsMove(direction: 1,
                          fingerY: fingerY,
                          lastMoveFingerY: lastMoveFingerY,
                          lastMoveDelta: lastMoveDelta) {
                return bounded + 1
            }
        }
        if bounded > 0 {
            let prev = frames[bounded - 1]
            let enter = prev.maxY - hysteresis(current: frames[bounded], neighbor: prev)
            if fingerY < enter,
               allowsMove(direction: -1,
                          fingerY: fingerY,
                          lastMoveFingerY: lastMoveFingerY,
                          lastMoveDelta: lastMoveDelta) {
                return bounded - 1
            }
        }
        return bounded
    }

    static func hysteresis(current: CGRect, neighbor: CGRect) -> CGFloat {
        min(moveHysteresis, min(current.height, neighbor.height) * 0.4)
    }

    static func allowsMove(direction: Int,
                           fingerY: CGFloat,
                           lastMoveFingerY: CGFloat?,
                           lastMoveDelta: Int) -> Bool {
        guard lastMoveDelta != 0,
              lastMoveDelta != direction,
              let lastMoveFingerY else { return true }
        if direction > 0 {
            return fingerY > lastMoveFingerY + reverseSlop
        }
        return fingerY < lastMoveFingerY - reverseSlop
    }

    static func liftOrigin(finger: CGPoint, grabOffset: CGPoint) -> CGPoint {
        CGPoint(x: finger.x - grabOffset.x, y: finger.y - grabOffset.y)
    }

    static func clampedValue(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(max, Swift.max(min, value))
    }

    static func lockedLiftOrigin(finger: CGPoint,
                                 grabOffset: CGPoint,
                                 liftSize: CGSize,
                                 bandMinY: CGFloat,
                                 bandMaxY: CGFloat) -> CGPoint {
        var origin = liftOrigin(finger: finger, grabOffset: grabOffset)
        let maxOriginY = Swift.max(bandMinY, bandMaxY - liftSize.height)
        origin.y = clampedValue(origin.y, min: bandMinY, max: maxOriginY)
        return origin
    }

    static func canApplyMove(now: TimeInterval, lastMoveAt: TimeInterval?) -> Bool {
        guard let lastMoveAt else { return true }
        return now - lastMoveAt >= moveLockDuration
    }

    static func stackedFrames(heights: [CGFloat],
                              originY: CGFloat,
                              spacing: CGFloat,
                              width: CGFloat) -> [CGRect] {
        var y = originY
        return heights.map { height in
            let frame = CGRect(x: 0, y: y, width: width, height: height)
            y += height + spacing
            return frame
        }
    }

    /// Cell frames live in content coordinates. Scrolling must not shift the
    /// stack, or the finger stays glued to the rows that were on screen when
    /// the drag started and auto-revealed habits never receive it.
    static func logicalOriginY(capturedSectionMinY: CGFloat,
                               contentOffsetY _: CGFloat,
                               capturedOffsetY _: CGFloat) -> CGFloat {
        capturedSectionMinY
    }

    static func paddedHeights(_ heights: [CGFloat],
                              count: Int,
                              fallback: CGFloat) -> [CGFloat] {
        if count <= 0 { return [] }
        if heights.count >= count { return Array(heights.prefix(count)) }
        let pad = max(fallback, 1)
        return heights + Array(repeating: pad, count: count - heights.count)
    }

    static func mergedHeights(current: [CGFloat],
                              visible: [(index: Int, height: CGFloat)],
                              draggedIndex: Int?) -> [CGFloat] {
        var next = current
        for item in visible {
            guard next.indices.contains(item.index),
                  item.index != draggedIndex,
                  item.height > 1 else { continue }
            next[item.index] = item.height
        }
        return next
    }

    static func movedHeights(_ heights: [CGFloat], from: Int, to: Int) -> [CGFloat] {
        movedItems(heights, from: from, to: to)
    }

    static func movedItems<T>(_ items: [T], from: Int, to: Int) -> [T] {
        guard items.indices.contains(from),
              items.indices.contains(to),
              from != to else { return items }
        var next = items
        let toOffset = to > from ? to + 1 : to
        next.move(fromOffsets: IndexSet(integer: from), toOffset: toOffset)
        return next
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
