import SwiftUI
import UIKit

extension Notification.Name {
    /// Sent when a vertical gesture hands control back to the enclosing list.
    /// Every visible reveal row closes itself without coupling sibling rows.
    static let swipeRevealDismissAll = Notification.Name("haiity.swipeRevealDismissAll")
    /// Sent when a row starts a horizontal gesture so other open rows settle.
    static let swipeRevealDidBegin = Notification.Name("haiity.swipeRevealDidBegin")
}

/// Der ZUG hinter dem Karten-Aufziehen (`SwipeReveal`) — als UIKit-Pan,
/// nach demselben Bauplan wie das Halten-Menü (`GraphContextMenu`):
///
///  * SwiftUI-Gesten feuern in dieser Verschachtelung (List-Zelle,
///    horizontale ScrollView im Raster) nicht zuverlässig — der Langdruck
///    hat es vorgemacht.
///  * Die unsichtbare Trägeransicht bekommt vom `background` exakt den
///    Rahmen der Zeile; der Erkenner hängt am ersten Scroll-Vorfahren
///    (der eigene Wrapper ist nur ein GESCHWISTER des Inhalts und sieht
///    keine Berührungen — nachgemessen).
///  * Beurteilt wird je Beginn: Lage im eigenen Rahmen, horizontale
///    Absicht, und ob unter dem Finger das RASTER liegt und ob es am Ende
///    steht (`SwipeReveal.canBegin`). Übernehmen wir über dem Raster, wird
///    dessen Scroll-Pan gekappt (disable/enable) — KEINE
///    Scheitern-Anforderung: die hielte die Berührungs-Zustellung in den
///    Rasterinhalt auf und tötete jeden Zellen-Tipp (nachgemessen).
///
/// Alle gemeldeten Wege sind SEMANTISCH: leading positiv, trailing negativ
/// — die RTL-Spiegelung passiert hier, am Übergang aus dem Schirmraum.
struct SwipeRevealPan: UIViewRepresentable {
    /// Darf DIESER Zug beginnen? (dx semantisch; overGrid/atEnd vom Treffer.)
    let shouldBegin: (_ towardTrailing: Bool, _ horizontal: Bool,
                      _ overGrid: Bool, _ gridAtTrailingEnd: Bool) -> Bool
    let began: () -> Void
    let changed: (_ translation: CGFloat) -> Void
    let ended: (_ translation: CGFloat, _ velocity: CGFloat) -> Void
    let cancelled: () -> Void
    let ownerID: UUID

    func makeUIView(context: Context) -> PanHost {
        PanHost(ownerID: ownerID, shouldBegin: shouldBegin, began: began,
                changed: changed, ended: ended, cancelled: cancelled)
    }

    func updateUIView(_ view: PanHost, context: Context) {
        view.ownerID = ownerID
        view.shouldBeginQuery = shouldBegin
        view.beganCallback = began
        view.changedCallback = changed
        view.endedCallback = ended
        view.cancelledCallback = cancelled
        // A List can keep the bridge view while replacing the row's content
        // after a completion. Reconcile immediately so the recognizer and its
        // callbacks belong to the current cell before the next swipe.
        view.reconcileHostForUpdate()
    }

    static func dismantleUIView(_ view: PanHost, coordinator: ()) {
        view.detach()
    }

    final class PanHost: UIView, UIGestureRecognizerDelegate {
        var ownerID: UUID
        var shouldBeginQuery: (Bool, Bool, Bool, Bool) -> Bool
        var beganCallback: () -> Void
        var changedCallback: (CGFloat) -> Void
        var endedCallback: (CGFloat, CGFloat) -> Void
        var cancelledCallback: () -> Void
        private var recognizer: UIPanGestureRecognizer?
        private weak var host: UIView?

        init(ownerID: UUID,
             shouldBegin: @escaping (Bool, Bool, Bool, Bool) -> Bool,
             began: @escaping () -> Void,
             changed: @escaping (CGFloat) -> Void,
             ended: @escaping (CGFloat, CGFloat) -> Void,
             cancelled: @escaping () -> Void) {
            self.ownerID = ownerID
            self.shouldBeginQuery = shouldBegin
            self.beganCallback = began
            self.changedCallback = changed
            self.endedCallback = ended
            self.cancelledCallback = cancelled
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        deinit { detach() }

        /// Rechts-nach-links-Spiegel: +1 in LTR, -1 in RTL.
        private var mirror: CGFloat {
            effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1
        }

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
            // A List may reuse its cell after the row model changes while
            // this hidden bridge stays mounted. Rebind before the next touch.
            reconcileHost()
        }

        fileprivate func reconcileHostForUpdate() {
            reconcileHost()
        }

        private func reconcileHost() {
            guard window != nil else { detach(); return }
            var ancestor = superview
            var fallbackContainer: UIView?
            var rowContainer: UIView?
            while let view = ancestor {
                fallbackContainer = fallbackContainer ?? view
                if view is UICollectionViewCell || view is UITableViewCell {
                    rowContainer = view
                    break
                }
                if view is UIScrollView { fallbackContainer = view }
                ancestor = view.superview
            }
            guard let container = rowContainer ?? fallbackContainer else {
                detach()
                return
            }
            guard container !== host else { return }

            detach()
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
            pan.maximumNumberOfTouches = 1
            // A horizontal reveal must cancel a Button that began tracking
            // under the finger; otherwise a drag from the title can also
            // open the editor. A simple tap never begins this pan and still
            // reaches the nested checkmark/content button.
            pan.cancelsTouchesInView = true
            pan.delegate = self
            recognizer = pan
            host = container
            container.addGestureRecognizer(pan)

            // The List/CollectionView pan otherwise wins the race before a
            // row can reveal its actions. Let this pan make the horizontal
            // versus vertical decision first; a vertical drag still fails
            // here and immediately releases the list to scroll.
            var scrollAncestor: UIView? = container
            while let view = scrollAncestor, !(view is UIScrollView) {
                scrollAncestor = view.superview
            }
            if let scroll = scrollAncestor as? UIScrollView,
               scroll.panGestureRecognizer !== pan {
                scroll.panGestureRecognizer.require(toFail: pan)
            }
        }

        func detach() {
            if let recognizer { host?.removeGestureRecognizer(recognizer) }
            recognizer = nil
            host = nil
        }

        @objc private func panned(_ pan: UIPanGestureRecognizer) {
            guard let container = host else { return }
            let dx = pan.translation(in: container).x * mirror
            switch pan.state {
            case .began:
                NotificationCenter.default.post(name: .swipeRevealDidBegin,
                                                object: ownerID)
                beganCallback()
                changedCallback(dx)
            case .changed:
                changedCallback(dx)
            case .ended:
                endedCallback(dx, pan.velocity(in: container).x * mirror)
            case .cancelled, .failed:
                cancelledCallback()
            default:
                break
            }
        }

        // MARK: – Wer darf, wer wartet

        // `override`: UIView bringt dieselbe Signatur bereits mit (für
        // Erkenner an SICH SELBST); als Delegat des fremd angehängten Pans
        // wird exakt dieselbe Methode gerufen.
        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  pan === recognizer else { return true }
            // The recognizer is installed on the cell/list container, not on
            // this hidden SwiftUI bridge view. Validate against the host's
            // bounds. When List exposes only its shared scroll host, use the
            // bridge's converted row frame so another row cannot respond.
            guard let container = host else { return false }
            let location = pan.location(in: container)
            let activeFrame = container is UICollectionViewCell || container is UITableViewCell
                ? container.bounds
                : convert(bounds, to: container)
            guard activeFrame.contains(location) else { return false }

            let translation = pan.translation(in: container)
            let velocity = pan.velocity(in: container)
            let horizontal = SwipeReveal.horizontalIntent(dx: translation.x, dy: translation.y)
                || SwipeReveal.horizontalIntent(dx: velocity.x, dy: velocity.y)
            let direction = abs(translation.x) > 3 ? translation.x : velocity.x
            let towardTrailing = direction * mirror < 0

            // Liegt unter dem Finger das RASTER (die horizontale ScrollView
            // IN der Zeile — nicht die Liste, die ist ein VORFAHRE)?
            var overGrid = false
            var atEnd = true
            var gridScroll: UIScrollView?
            let hit = container.hitTest(location, with: nil)
            var walk: UIView? = hit
            while let view = walk, view !== container {
                if let scroll = view as? UIScrollView {
                    overGrid = true
                    gridScroll = scroll
                    // Das Raster erzwingt LTR — „Ende" ist rechts.
                    atEnd = scroll.contentOffset.x
                        >= scroll.contentSize.width - scroll.bounds.width - 2
                    break
                }
                walk = view.superview
            }
            let verdict = shouldBeginQuery(towardTrailing, horizontal, overGrid, atEnd)
            if !horizontal {
                NotificationCenter.default.post(name: .swipeRevealDismissAll, object: nil)
            }
            // Über dem Raster hat dessen Scroll-Pan den Zug meist schon
            // beansprucht, bevor wir gefragt werden — er würde unser
            // Aufziehen im nächsten Umlauf stornieren. Sein Tracking wird
            // deshalb GENAU DANN gekappt (disable/enable bricht die laufende
            // Erkennung ab), wenn wir übernehmen. Eine Scheitern-Anforderung
            // (`shouldBeRequiredToFailBy`) stand hier zuerst — sie hielt
            // aber die Berührungs-Zustellung in den Raster-INHALT auf, bis
            // unser Pan scheitert, und tötete damit jeden Zellen-Tipp
            // (nachgemessen: Pille ja, Zelle nie). Kappen statt warten lässt
            // Tipps unberührt.
            if verdict, let gridScroll {
                gridScroll.panGestureRecognizer.isEnabled = false
                gridScroll.panGestureRecognizer.isEnabled = true
            }
            return verdict
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === recognizer,
                  let container = host,
                  let otherView = otherGestureRecognizer.view else {
                return false
            }
            guard otherView === container || otherView.isDescendant(of: container) else {
                return false
            }
            // Keep the enclosing scroll view exclusive so it cannot compete
            // with the row reveal. Controls also stay exclusive: once this
            // pan commits to a horizontal reveal, `cancelsTouchesInView`
            // must terminate a nested Button's tracking; otherwise a swipe
            // beginning on the checkmark can replay the button action after
            // a revealed action was tapped. A short tap still reaches the
            // Button because this pan fails before it recognizes.
            if otherView is UIScrollView { return false }
            if otherView is UIControl { return false }
            return true
        }
    }
}

/// One motion profile for every row that exposes actions. Keeping the
/// calculation here prevents habit and reminder rows from drifting apart.
enum SwipeRevealMotion {
    static func settleAnimation(reduceMotion: Bool,
                                velocity: CGFloat,
                                distance: CGFloat) -> Animation? {
        guard !reduceMotion else { return nil }
        return .interpolatingSpring(
            mass: 0.85,
            stiffness: 250,
            damping: 22,
            initialVelocity: SwipeReveal.initialVelocity(
                velocity: velocity,
                distance: distance))
    }
}

/// Stable action underlay shared by habits and reminders. The buttons keep
/// their layout while the row moves above them, so cancellation never causes
/// a second layout jump or leaves a moving hit target behind.
struct SwipeRevealActions: View {
    let actions: [RevealAction]
    let alignment: Alignment
    let exposedWidth: CGFloat
    let height: CGFloat?
    let onAction: (RevealAction) -> Void

    private var actionWidth: CGFloat {
        SwipeReveal.revealWidth(count: actions.count)
    }

    private var progress: CGFloat {
        min(max(exposedWidth / max(actionWidth, 1), 0), 1)
    }

    private var actionStack: some View {
        HStack(spacing: SwipeReveal.buttonGap) {
            ForEach(actions) { action in
                Button { onAction(action) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: action.symbol)
                            .font(.title3.weight(.semibold))
                        Text(action.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(.white)
                    .frame(width: SwipeReveal.buttonWidth)
                    .frame(maxHeight: .infinity)
                    .background(action.tint,
                                in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                                     style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                                   style: .continuous))
                }
                .buttonStyle(.plain)
                .frame(width: SwipeReveal.buttonWidth)
                .contentShape(Rectangle())
                .zIndex(100)
                .accessibilityLabel(action.title)
                .accessibilityIdentifier("reveal-action-\(action.operation.rawValue)")
            }
        }
    }

    @ViewBuilder
    private var sizedActionStack: some View {
        if let height {
            actionStack
                .frame(width: actionWidth, height: height, alignment: alignment)
        } else {
            actionStack
                .frame(width: actionWidth, alignment: alignment)
                .frame(maxHeight: .infinity)
        }
    }

    var body: some View {
        sizedActionStack
            .opacity(progress)
            .scaleEffect(0.92 + progress * 0.08,
                         anchor: alignment == .leading ? .leading : .trailing)
            // Settle to full size before enabling the action hit targets.
            .offset(x: alignment == .leading
                    ? -(1 - progress) * 10
                    : (1 - progress) * 10)
            .frame(maxWidth: .infinity, alignment: alignment)
            .accessibilityHidden(exposedWidth < actionWidth)
            .allowsHitTesting(exposedWidth >= actionWidth)
    }
}
