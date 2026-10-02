import SwiftUI
import UIKit

/// Wo die schwebende System-Tableiste WIRKLICH steht — ausgemessen an der
/// echten Ansicht, nicht aus Sicherheitszonen gerechnet.
///
/// Warum nicht gerechnet: die Leiste hängt an der BILDSCHIRMKANTE, nicht an
/// der Sicherheitszone. Ein Gerät mit Home-Indikator hat unten 34 pt Zone,
/// eines ohne 0 — dieselbe Rechnung landet auf beiden auf verschiedenen
/// Linien (nachgemessen: auf dem 17 Pro Max saß der Kreis 34 pt ÜBER der
/// Kapsel, auf dem SE stimmte er). Gemessen stimmt beides: die Leiste meldet
/// dieselbe Geometrie relativ zur Unterkante (Kapsel 62 pt hoch mit 21 pt
/// Abstand, minimierter Teller 48 pt mit 28 pt — beide um DIESELBE Mittellinie).
///
/// Beobachtbar, damit ausschließlich der Kreis neu zeichnet und nicht der
/// ganze Bildschirm (dieselbe Lehre wie bei `ChromeScrollBox`).
@available(iOS 26, *)
@Observable final class TabBarPlatters {
    struct Placement: Equatable {
        /// Mittelpunkt des Kreises in Fensterkoordinaten. Er ist in BEIDEN
        /// Leisten-Zuständen derselbe — die Leiste schrumpft um ihre Mitte.
        var center: CGPoint
        /// Aktueller Durchmesser: die Höhe des gerade sichtbaren Tellers.
        var diameter: CGFloat
    }
    var placement: Placement?
    /// Wurde überhaupt je eine Leiste gefunden? Trennt „die Leiste ist gerade
    /// weg" (dann gehört auch der Kreis weg) von „hier misst nichts" (dann
    /// muss der Rückfallwert her).
    var everFound = false
}

/// Der Ausmesser: eine unsichtbare Ansicht, die im Fenster die Tableiste
/// sucht und ihre Teller meldet. Gelesen werden nur öffentliche
/// UIView-Eigenschaften (`frame`, `isHidden`, `alpha`) — keine private
/// Programmierschnittstelle, kein Verändern der Systemansichten.
@available(iOS 26, *)
struct TabBarPlatterReader: UIViewRepresentable {
    let platters: TabBarPlatters
    /// Nur damit SwiftUI `updateUIView` aufruft, wenn sich einer dieser
    /// Zustände ändert — dann lohnt ein neuer Messversuch.
    let remeasureOn: [Bool]

    func makeUIView(context: Context) -> UIView { PlatterProbe(platters: platters) }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Mit zurückgesetztem Zähler: hat sich an der Oberfläche etwas
        // geändert (Suche zu, Farbe gewechselt), lohnt ein neuer Anlauf.
        (uiView as? PlatterProbe)?.measure(retrying: true)
    }
}

@available(iOS 26, *)
private final class PlatterProbe: UIView {
    private let platters: TabBarPlatters
    /// Ansichten, an denen ein Beobachter hängt. BEWUSST stark gehalten: eine
    /// Ansicht, die mit angemeldetem Beobachter abgeräumt wird, ist ein
    /// Absturz. Abgemeldet wird beim nächsten Ausmessen oder beim Abbau.
    private var observed: [UIView] = []
    /// Die Leiste steht nicht sofort im Fenster (und ist bei offener Suche
    /// zeitweise gar nicht da). Solange nichts zu messen ist, wird es in
    /// Ruhe noch einmal versucht, statt für immer auf den Rückfallwerten
    /// stehen zu bleiben.
    private var retries = 0
    private static let maxRetries = 40

    init(platters: TabBarPlatters) {
        self.platters = platters
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit { unobserve() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { unobserve(); return }
        // Die Leiste steht erst NACH diesem Umlauf im Fenster.
        measure(retrying: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        measure(retrying: true)
    }

    /// Erneut ausmessen und dabei den Wiederhol-Zähler zurücksetzen — von
    /// aussen aufgerufen, wenn sich die Lage geändert haben kann (Suche zu,
    /// Farbe gewechselt).
    func measure(retrying: Bool) {
        if retrying { retries = 0 }
        measure()
    }

    /// Höchstens EIN wartender Versuch — sonst legt jedes Aktualisieren der
    /// Ansicht eine weitere Kette an.
    private var retryPending = false

    private func retryLater() {
        guard retries < Self.maxRetries, !retryPending else { return }
        retries += 1
        retryPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.retryPending = false
            self?.measure()
        }
    }

    /// Das Minimieren der Leiste ist kein Weg, den man interpolieren könnte:
    /// die Teller behalten ihre Rahmen, das System blendet den einen ein und
    /// den anderen aus (nachgemessen mit einem Bildtakt-Mitschnitt). Ein
    /// Beobachter auf `hidden` ist deshalb genau das richtige Signal — und es
    /// ist DAS DES SYSTEMS, nicht unsere eigene Scroll-Vermutung.
    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        measure()
    }

    private func measure() {
        guard let window, let bar = Self.findTabBar(in: window) else {
            publish(nil)
            retryLater()
            return
        }
        let barFrame = bar.convert(bar.bounds, to: window)
        // Die „Teller" der Leiste: die Kapsel (ruhend) und der kleine Teller
        // (minimiert). Beide existieren immer, sichtbar ist einer.
        //
        // Erkannt werden sie an der LAGE, nicht am Klassennamen: ein Teller
        // ist ein Stück in Leistenhöhe, das VOLLSTÄNDIG in der Leiste liegt.
        // Das ist die Prüfung, die den Umbett-Behälter der Glas-Animation
        // aussortiert (100 × 100 an der Leistenkante — er ragt hinaus und
        // hätte als „größter Teller" die ganze Messung verdorben).
        let platterViews = bar.subviews.filter { view in
            let f = view.convert(view.bounds, to: window)
            return f.height >= 30 && f.height <= 90 && f.width >= 30
                && barFrame.insetBy(dx: -1, dy: -1).contains(f)
        }
        observe(bar: bar, platters: platterViews)
        // Bei offener Suche nimmt das System die Leiste aus dem Bild — der
        // Kreis gehört zu ihr und geht mit.
        guard !bar.isHidden, bar.alpha > 0.05, barFrame.intersects(window.bounds),
              // Der GRÖSSTE Teller ist die Kapsel: sie gibt Linie,
              // Randabstand und den ruhenden Durchmesser. (Der kleine Teller
              // sitzt um dieselbe Mitte, einer reicht also für die Linie.)
              let capsule = platterViews.max(by: { $0.bounds.height < $1.bounds.height })
        else {
            publish(nil)
            retryLater()
            return
        }
        let capsuleFrame = capsule.convert(capsule.bounds, to: window)
        // Der Abstand der Leiste zur Unterkante ist AUCH ihr Seitenabstand —
        // die schwebende Leiste ist rundum gleich eingerückt (nachgemessen in
        // beiden Zuständen, mit und ohne Home-Indikator).
        let gutter = window.bounds.maxY - capsuleFrame.maxY
        let resting = capsuleFrame.height
        guard gutter >= 0, gutter <= 60 else {
            trace("platter probe: implausible bar \(capsuleFrame) gutter \(gutter)")
            publish(nil)
            retryLater()
            return
        }
        retries = 0
        // Während des Umschaltens sind beide Teller kurz sichtbar; der
        // KLEINERE gewinnt, damit der Kreis mit dem Anfang der System-
        // Animation schrumpft statt an ihrem Ende zu springen.
        let shown = platterViews.filter { !$0.isHidden && $0.alpha > 0.05 }
        let diameter = shown.map(\.bounds.height).min() ?? resting
        publish(.init(center: CGPoint(x: window.bounds.maxX - gutter - resting / 2,
                                      y: capsuleFrame.midY),
                      diameter: min(max(diameter, 28), resting)))
    }

    /// Erst im nächsten Umlauf schreiben: `measure()` läuft auch aus
    /// `updateUIView`, und ein Zustandsschreiben MITTEN im Auswerten der
    /// Ansicht ist genau die Warnung, die man nicht ignorieren soll.
    private func publish(_ placement: TabBarPlatters.Placement?) {
        let found = placement != nil
        guard platters.placement != placement || (found && !platters.everFound) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if found { platters.everFound = true }
            guard platters.placement != placement else { return }
            platters.placement = placement
        }
    }

    private func observe(bar: UIView, platters: [UIView]) {
        let wanted = [bar] + platters
        guard observed.map(ObjectIdentifier.init) != wanted.map(ObjectIdentifier.init) else { return }
        unobserve()
        for view in wanted {
            view.addObserver(self, forKeyPath: "hidden", options: [], context: nil)
            view.addObserver(self, forKeyPath: "alpha", options: [], context: nil)
        }
        observed = wanted
    }

    private func unobserve() {
        for view in observed {
            view.removeObserver(self, forKeyPath: "hidden")
            view.removeObserver(self, forKeyPath: "alpha")
        }
        observed = []
    }

    /// Die Tableiste im Fenster. `UITabBar` ist eine ÖFFENTLICHE Klasse; ihre
    /// Teller sind es nicht, werden hier aber nur als gewöhnliche UIViews
    /// gelesen. Findet sich keine, meldet der Ausmesser schlicht nichts und
    /// der Kreis fällt auf die nachgemessenen Werte zurück.
    static func findTabBar(in view: UIView) -> UIView? {
        if view is UITabBar { return view }
        for sub in view.subviews.reversed() {
            if let found = findTabBar(in: sub) { return found }
        }
        return nil
    }
}
