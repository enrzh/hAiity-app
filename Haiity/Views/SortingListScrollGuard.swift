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
            for cell in view.visibleCells {
                SortingListReorderChrome.apply(active: active, to: cell)
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

/// List chrome while sorting: no side grabber, no system drag-and-drop escape.
enum SortingListReorderChrome {
    /// Matches `ContentView.habitList`: header section 0, movable habits section 1.
    static let habitSectionIndex = 1

    static func apply(active: Bool, to root: UIView) {
        setReorderControlsHidden(active, in: root)
        setSystemDragAndDropLocked(active, in: root)
    }

    static func setReorderControlsHidden(_ hidden: Bool, in root: UIView) {
        if let tableCell = root as? UITableViewCell {
            tableCell.showsReorderControl = !hidden
        }
        for subview in root.subviews {
            let name = String(describing: type(of: subview))
            if name.localizedCaseInsensitiveContains("reorder") {
                subview.isHidden = hidden
                subview.isUserInteractionEnabled = !hidden
                subview.alpha = hidden ? 0 : 1
            }
            setReorderControlsHidden(hidden, in: subview)
        }
    }

    /// Reordering is in-list only — never spring-loaded export or drop targets.
    static func setSystemDragAndDropLocked(_ locked: Bool, in root: UIView) {
        for interaction in root.interactions {
            if let drag = interaction as? UIDragInteraction {
                drag.isEnabled = !locked
            }
        }
        for subview in root.subviews {
            setSystemDragAndDropLocked(locked, in: subview)
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
    /// Horizontal slack before we treat a move as leaving the list band.
    static let horizontalSlack: CGFloat = 12

    struct Frame {
        var minY: CGFloat
        var maxY: CGFloat
    }

    struct Viewport {
        var minY: CGFloat
        var maxY: CGFloat
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

    /// Visible list area after overlay chrome. The list scrolls under the
    /// navbar, so the safe-area inset is the floor even when content insets
    /// are smaller.
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

    /// Drop and auto-scroll live in the habit rows, not in the title / Heute
    /// header or under the navbar. Immovable rows that currently occupy the
    /// top or bottom of the chrome viewport push that range inward.
    static func sortableBounds(chromeMinY: CGFloat,
                               chromeMaxY: CGFloat,
                               immovableFrames: [Frame]) -> Viewport {
        var minY = chromeMinY
        var maxY = chromeMaxY
        for frame in immovableFrames.sorted(by: { $0.minY < $1.minY }) {
            if frame.minY <= minY + 1, frame.maxY > minY {
                minY = max(minY, frame.maxY)
            }
        }
        for frame in immovableFrames.sorted(by: { $0.maxY > $1.maxY }) {
            if frame.maxY >= maxY - 1, frame.minY < maxY {
                maxY = min(maxY, frame.minY)
            }
        }
        guard maxY - minY >= edgeBand else {
            return Viewport(minY: chromeMinY, maxY: chromeMaxY)
        }
        return Viewport(minY: minY, maxY: maxY)
    }

    static func intersection(_ a: Viewport, _ b: Viewport) -> Viewport {
        let minY = max(a.minY, b.minY)
        let maxY = min(a.maxY, b.maxY)
        guard maxY >= minY else { return a }
        return Viewport(minY: minY, maxY: maxY)
    }

    /// Layout span of every movable row — the finger cannot leave this band.
    static func itemBand(section: Int,
                         itemCount: Int,
                         layoutAttributes: (Int) -> UICollectionViewLayoutAttributes?) -> Viewport? {
        guard itemCount > 0 else { return nil }
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for item in 0..<itemCount {
            guard let frame = layoutAttributes(item)?.frame else { continue }
            minY = min(minY, frame.minY)
            maxY = max(maxY, frame.maxY)
        }
        guard maxY > minY, minY.isFinite, maxY.isFinite else { return nil }
        return Viewport(minY: minY, maxY: maxY)
    }

    /// Vertical clamp only — used by unit tests and auto-scroll bands.
    static func movementY(fingerY: CGFloat, sortable: Viewport) -> CGFloat {
        clampedOffset(fingerY, min: sortable.minY, max: sortable.maxY)
    }

    /// Hard in-list target: clamp Y to chrome + habit rows, X to the list column.
    static func lockedMovementTarget(finger: CGPoint,
                                     collectionBounds: CGRect,
                                     contentInset: UIEdgeInsets,
                                     sortable: Viewport,
                                     itemBand: Viewport?) -> CGPoint {
        let band = itemBand.map { intersection(sortable, $0) } ?? sortable
        let y = clampedOffset(finger.y, min: band.minY, max: band.maxY)
        let minX = contentInset.left + horizontalSlack
        let maxX = collectionBounds.width - contentInset.right - horizontalSlack
        let x = clampedOffset(finger.x, min: minX, max: maxX)
        return CGPoint(x: x, y: y)
    }

    /// Treat touches above/below the habit band like edge drags for auto-scroll.
    static func autoScrollFingerY(_ fingerY: CGFloat, sortable: Viewport) -> CGFloat {
        if fingerY < sortable.minY { return sortable.minY - 1 }
        if fingerY > sortable.maxY { return sortable.maxY + 1 }
        return fingerY
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
        private weak var rowCell: UIView?
        private weak var movingCollection: UICollectionView?
        private var suppressed: [UIGestureRecognizer] = []
        private var displayLink: CADisplayLink?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = true
            backgroundColor = .clear
            isAccessibilityElement = false
            accessibilityElementsHidden = true
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

        override func layoutSubviews() {
            super.layoutSubviews()
            if let rowCell {
                frame = rowCell.bounds
                rowCell.bringSubviewToFront(self)
            }
        }

        fileprivate func reconcileHostForUpdate() {
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
            if container === rowCell, superview === container {
                setNeedsLayout()
                return
            }

            detach()
            let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed))
            press.minimumPressDuration = SortingReorderPolicy.pressDuration
            press.allowableMovement = SortingReorderPolicy.allowableMovement
            press.cancelsTouchesInView = true
            press.delegate = self
            recognizer = press
            rowCell = container
            addGestureRecognizer(press)
            container.addSubview(self)
            frame = container.bounds
            autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.bringSubviewToFront(self)
            suppressCompetingRecognizers(on: container, besides: press)
        }

        func detach() {
            stopAutoScroll()
            if let movingCollection {
                movingCollection.cancelInteractiveMovement()
                restoreScrollPan(on: movingCollection)
            }
            movingCollection = nil
            restoreSuppressedRecognizers()
            if let recognizer { removeGestureRecognizer(recognizer) }
            recognizer = nil
            removeFromSuperview()
            rowCell = nil
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer === recognizer && rowCell != nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }

        @objc private func pressed(_ press: UILongPressGestureRecognizer) {
            guard let container = rowCell,
                  let collection = enclosingCollectionView(from: container) else { return }
            switch press.state {
            case .began:
                guard let cell = container as? UICollectionViewCell,
                      let indexPath = collection.indexPath(for: cell),
                      indexPath.section == SortingListReorderChrome.habitSectionIndex else { return }
                SortingListReorderChrome.apply(active: true, to: cell)
                cancelTracking(collection.panGestureRecognizer)
                collection.panGestureRecognizer.isEnabled = false
                if collection.beginInteractiveMovementForItem(at: indexPath) {
                    movingCollection = collection
                    collection.updateInteractiveMovementTargetPosition(
                        movementTarget(for: press, in: collection))
                    startAutoScroll()
                }
            case .changed:
                movingCollection?.updateInteractiveMovementTargetPosition(
                    movementTarget(for: press, in: collection))
            case .ended:
                stopAutoScroll()
                movingCollection?.endInteractiveMovement()
                restoreScrollPan(on: collection)
                movingCollection = nil
            case .cancelled, .failed:
                stopAutoScroll()
                movingCollection?.cancelInteractiveMovement()
                restoreScrollPan(on: collection)
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
            let sortable = sortableViewport(in: collection)
            let scrollBand = lockedSortableBand(in: collection, sortable: sortable)
            let edgeY = SortingReorderPolicy.autoScrollFingerY(location.y, sortable: scrollBand)
            let delta = SortingReorderPolicy.autoScrollTranslation(
                locationY: edgeY,
                viewportMinY: scrollBand.minY,
                viewportMaxY: scrollBand.maxY,
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
            collection.updateInteractiveMovementTargetPosition(
                movementTarget(for: press, in: collection))
            for cell in collection.visibleCells {
                SortingListReorderChrome.apply(active: true, to: cell)
            }
        }

        private func movementTarget(for press: UILongPressGestureRecognizer,
                                    in collection: UICollectionView) -> CGPoint {
            let location = press.location(in: collection)
            let sortable = sortableViewport(in: collection)
            return SortingReorderPolicy.lockedMovementTarget(
                finger: location,
                collectionBounds: collection.bounds,
                contentInset: collection.adjustedContentInset,
                sortable: sortable,
                itemBand: habitItemBand(in: collection))
        }

        private func habitItemBand(in collection: UICollectionView) -> SortingReorderPolicy.Viewport? {
            let section = SortingListReorderChrome.habitSectionIndex
            let count = collection.numberOfItems(inSection: section)
            return SortingReorderPolicy.itemBand(section: section, itemCount: count) { item in
                collection.layoutAttributesForItem(at: IndexPath(item: item, section: section))
            }
        }

        private func lockedSortableBand(in collection: UICollectionView,
                                        sortable: SortingReorderPolicy.Viewport) -> SortingReorderPolicy.Viewport {
            if let band = habitItemBand(in: collection) {
                return SortingReorderPolicy.intersection(sortable, band)
            }
            return sortable
        }

        private func restoreScrollPan(on collection: UICollectionView) {
            collection.panGestureRecognizer.isEnabled = true
        }

        private func sortableViewport(in collection: UICollectionView) -> SortingReorderPolicy.Viewport {
            let chrome = SortingReorderPolicy.chromeViewport(
                boundsMinY: collection.bounds.minY,
                boundsMaxY: collection.bounds.maxY,
                adjustedTop: collection.adjustedContentInset.top,
                adjustedBottom: collection.adjustedContentInset.bottom,
                safeTop: collection.safeAreaInsets.top,
                safeBottom: collection.safeAreaInsets.bottom)
            return SortingReorderPolicy.sortableBounds(
                chromeMinY: chrome.minY,
                chromeMaxY: chrome.maxY,
                immovableFrames: immovableFrames(in: collection))
        }

        private func immovableFrames(in collection: UICollectionView) -> [SortingReorderPolicy.Frame] {
            collection.visibleCells.compactMap { cell in
                guard !isMovableCell(cell) else { return nil }
                return SortingReorderPolicy.Frame(minY: cell.frame.minY, maxY: cell.frame.maxY)
            }
        }

        private func isMovableCell(_ cell: UICollectionViewCell) -> Bool {
            cell.containsSortingReorderOverlay
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

private extension UIView {
    var containsSortingReorderOverlay: Bool {
        if self is SortingReorderPan.Host { return true }
        return subviews.contains { $0.containsSortingReorderOverlay }
    }
}
