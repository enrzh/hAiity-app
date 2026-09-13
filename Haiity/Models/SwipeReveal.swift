import Foundation
import CoreGraphics

/// Die reine Mechanik des Karten-Aufziehens — ohne UIKit, ohne SwiftUI,
/// damit Klemmen, Gummiband und Schnapp-Entscheidungen im Test stehen.
///
/// **Warum es diese Mechanik überhaupt gibt.** Die System-Wischknöpfe von
/// iOS 26 sind auf hohen Zeilen KAPSELN FESTER GRÖSSE — neben einer
/// 300-pt-Rasterkarte wirken sie verloren (vom Gerät gemeldet), und ihre
/// Höhe ist nicht beeinflussbar (nachgemessen: Label-Frames und
/// Zeilenhintergrund ändern nichts). Kartenhohe Knöpfe heißt: das Aufziehen
/// selbst bauen. Die GESTE liefert UIKit (`SwipeRevealPan`), die REGELN
/// stehen hier.
///
/// Alle Größen sind SEMANTISCH (leading/trailing), nicht links/rechts —
/// die RTL-Spiegelung besorgt die Ansicht.
enum SwipeReveal {
    /// Ein Knopf: so breit wie eine bequeme Trefferfläche, so hoch wie die
    /// Karte (die Höhe kommt vom Layout, nicht von hier).
    static let buttonWidth: CGFloat = 72
    static let buttonGap: CGFloat = 8

    /// Ruheweite einer aufgezogenen Seite: alle Knöpfe plus Luft zur Karte.
    static func revealWidth(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * buttonWidth + CGFloat(count) * buttonGap
    }

    /// Gummiband hinter der Ruheweite: asymptotisch gegen `limit`, damit die
    /// Karte spürbar bremst statt endlos mitzulaufen.
    static func rubberBand(_ excess: CGFloat, limit: CGFloat = 64) -> CGFloat {
        guard excess > 0 else { return 0 }
        return limit * (1 - 1 / (excess / limit + 1))
    }

    /// Velocity in the unit expected by an interpolating spring. A clamp keeps
    /// an unusually fast physical swipe from producing an unstable settle.
    static func initialVelocity(velocity: CGFloat, distance: CGFloat) -> Double {
        guard distance > 1 else { return 0 }
        let normalized = velocity / distance
        return Double(min(max(normalized, -8), 8))
    }

    /// Sichtbarer Versatz aus Startlage + Fingerweg. Innerhalb der
    /// Ruheweiten 1:1, dahinter Gummiband. Positiv = leading aufgezogen.
    static func offset(start: CGFloat, translation: CGFloat,
                       leadingWidth: CGFloat, trailingWidth: CGFloat) -> CGFloat {
        let raw = start + translation
        if raw > leadingWidth {
            return leadingWidth + rubberBand(raw - leadingWidth)
        }
        if raw < -trailingWidth {
            return -(trailingWidth + rubberBand(-raw - trailingWidth))
        }
        return raw
    }

    enum Resting: Equatable {
        case closed, leading, trailing
        /// Voll-Wisch: die ERSTE Aktion der Seite wird ausgelöst.
        case commitLeading, commitTrailing
    }

    /// Wohin die Karte beim Loslassen schnappt.
    ///
    /// **`pull` ist der ROHE Zug** (Startlage + Fingerweg), nicht der
    /// gummierte Versatz: das Gummiband deckelt die Anzeige bei
    /// Ruheweite + `limit` — am gummierten Wert gemessen wäre der
    /// Voll-Wisch unerreichbar (so gebaut, so im Simulator ertappt).
    /// Geschwindigkeit projiziert den Zug ein Stück weiter (~80 ms), damit
    /// ein flotter kurzer Wisch öffnet und ein Zurückschnipsen schließt.
    static func resting(pull: CGFloat, velocity: CGFloat,
                        leadingWidth: CGFloat, trailingWidth: CGFloat,
                        cardWidth: CGFloat) -> Resting {
        if cardWidth > 0 {
            if trailingWidth > 0, pull < -max(cardWidth * 0.55, trailingWidth + 72) {
                return .commitTrailing
            }
            if leadingWidth > 0, pull > max(cardWidth * 0.55, leadingWidth + 72) {
                return .commitLeading
            }
        }
        let projected = pull + velocity * 0.08
        if trailingWidth > 0, projected < -trailingWidth * 0.5 { return .trailing }
        if leadingWidth > 0, projected > leadingWidth * 0.5 { return .leading }
        return .closed
    }

    /// Darf ein Zug das Aufziehen BEGINNEN?
    ///
    ///  * Nur bei klar horizontaler Absicht — sonst gehört die Bewegung der
    ///    Liste.
    ///  * Offen steuert JEDER horizontale Zug (auch über dem Raster): sonst
    ///    ließe sich eine offene Karte über dem Raster nicht zuschieben.
    ///  * Zu, Richtung trailing, ÜBER dem Raster: nur wenn das Raster am
    ///    Ende steht — mitten in der Historie gehört der Zug dem Scrollen.
    ///  * Zu, Richtung leading, ÜBER dem Raster: nie — rückwärts ist IMMER
    ///    die Historie (das Raster ruht am Ende, rückwärts gibt es dort
    ///    immer etwas zu sehen). Vom Kopf aus geht leading weiterhin.
    static func canBegin(towardTrailing: Bool,
                         horizontalIntent: Bool,
                         open: Bool,
                         hasLeading: Bool, hasTrailing: Bool,
                         overGrid: Bool, gridAtTrailingEnd: Bool) -> Bool {
        guard horizontalIntent else { return false }
        if open { return true }
        if towardTrailing {
            guard hasTrailing else { return false }
            if overGrid, !gridAtTrailingEnd { return false }
            return true
        }
        guard hasLeading else { return false }
        return !overGrid
    }

    /// Klar horizontale Absicht: deutlich mehr Weg zur Seite als nach
    /// unten/oben, und überhaupt genug Weg, um kein Zittern zu sein.
    static func horizontalIntent(dx: CGFloat, dy: CGFloat) -> Bool {
        abs(dx) > abs(dy) * 1.08 && abs(dx) > 3
    }
}
