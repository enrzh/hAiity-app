import SwiftUI
import UIKit

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

    func makeUIView(context: Context) -> PanHost {
        PanHost(shouldBegin: shouldBegin, began: began, changed: changed, ended: ended)
    }

    func updateUIView(_ view: PanHost, context: Context) {
        view.shouldBeginQuery = shouldBegin
        view.beganCallback = began
        view.changedCallback = changed
        view.endedCallback = ended
    }

    static func dismantleUIView(_ view: PanHost, coordinator: ()) {
        view.detach()
    }

    final class PanHost: UIView, UIGestureRecognizerDelegate {
        var shouldBeginQuery: (Bool, Bool, Bool, Bool) -> Bool
        var beganCallback: () -> Void
        var changedCallback: (CGFloat) -> Void
        var endedCallback: (CGFloat, CGFloat) -> Void
        private var recognizer: UIPanGestureRecognizer?
        private weak var host: UIView?

        init(shouldBegin: @escaping (Bool, Bool, Bool, Bool) -> Bool,
             began: @escaping () -> Void,
             changed: @escaping (CGFloat) -> Void,
             ended: @escaping (CGFloat, CGFloat) -> Void) {
            self.shouldBeginQuery = shouldBegin
            self.beganCallback = began
            self.changedCallback = changed
            self.endedCallback = ended
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
            guard window != nil else { detach(); return }
            guard recognizer == nil else { return }
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
            guard let container = rowContainer ?? fallbackContainer else { return }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
            pan.maximumNumberOfTouches = 1
            pan.cancelsTouchesInView = false
            pan.delegate = self
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
            recognizer = pan
            host = container
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
                beganCallback()
                changedCallback(dx)
            case .changed:
                changedCallback(dx)
            case .ended, .cancelled, .failed:
                endedCallback(dx, pan.velocity(in: container).x * mirror)
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
            let horizontal = SwipeReveal.horizontalIntent(dx: translation.x, dy: translation.y)
            let towardTrailing = translation.x * mirror < 0

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
            trace("revealpan: begin? loc=\(location) bounds=\(bounds) dx=\(translation.x) dy=\(translation.y) trailing=\(towardTrailing) horiz=\(horizontal) grid=\(overGrid) end=\(atEnd) -> \(verdict)")
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
            // A nested SwiftUI control may own the initial touch. Let the
            // row pan still observe a horizontal drag without enabling
            // simultaneous recognition with the surrounding List scroll.
            return !(otherView is UIScrollView)
        }
    }
}
