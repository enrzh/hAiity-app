import UIKit

/// Was gerade ÜBER der App liegt — gefragt bei UIKit, nicht bei SwiftUI.
///
/// **Warum es diese Frage überhaupt gibt.** Ein Blatt darf nicht über einem
/// Blatt aufgehen: iOS verschluckt den zweiten Versuch stillschweigend, und
/// zurück bleibt ein `true` in einem Zustand, zu dem es keine Ansicht gibt.
/// Wer das verhindern will, muss wissen, ob GERADE etwas präsentiert wird.
///
/// **Warum nicht die SwiftUI-Zustände zählen.** Eine Ansicht kennt nur ihre
/// EIGENEN Präsentationen. Die Blätter von „Mehr" (Farbe anlegen, Umbenennen,
/// Kaufblatt, Import), das Kaufblatt der Statistik und die Teilen-Blätter aus
/// den Karten hängen tiefer im Baum — für die Wurzel sind sie unsichtbar.
/// Eine Aufzählung dort wäre eine Liste, die bei jedem neuen Blatt irgendwo
/// im Baum stillschweigend falsch wird. UIKit weiß es dagegen immer: JEDE
/// Präsentation — SwiftUI-Blatt, Vollbild, Meldung, Dateiwähler, das
/// System-Teilen-Blatt — ist am Ende ein präsentierter Ansichtscontroller.
///
/// **Warum das aktive Fenster und nicht der Bildschirm.** Im Split View und
/// im Stage Manager gehört der Bildschirm mehreren Fenstern; präsentiert wird
/// immer in EINEM (dieselbe Begründung wie bei `HabitCard.windowWidth`).
enum ModalPresentation {
    /// Das Fenster, in dem der Mensch gerade steht.
    private static var activeWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.keyWindow
    }

    /// Der oberste Ansichtscontroller: von der Wurzel so lange nach oben, bis
    /// niemand mehr etwas präsentiert. Das ist der Einzige, über dem sich noch
    /// etwas zeigen lässt.
    static var topViewController: UIViewController? {
        guard var top = activeWindow?.rootViewController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    /// Liegt gerade IRGENDETWAS über der App?
    ///
    /// Gefragt wird nur die Wurzel: präsentiert jemand tiefer im Stapel, dann
    /// präsentiert auch sie (ein Stapel beginnt immer bei ihr). Ein Blatt, das
    /// gerade zufährt, zählt bewusst noch mit — in der halben Sekunde
    /// Animation ist „lieber nichts" die richtige Antwort.
    static var isPresenting: Bool {
        activeWindow?.rootViewController?.presentedViewController != nil
    }
}
