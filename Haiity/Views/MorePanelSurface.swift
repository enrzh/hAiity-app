import SwiftUI
import UIKit

/// Die Mehr-Tafel als EIGENE Ansicht — EIN Ding, das seine Größe ändert.
///
/// **Warum sie nicht mehr in `ContentView` steht.** Größe und Zug hingen
/// vorher an `@State`-Werten des Bildschirms. Jeder Bildschritt eines Zuges
/// wertete damit den ganzen `ContentView.body` neu aus: Habit-Liste, jede
/// Karte, jedes Raster. Nachgemessen (Bildzeit-Sonde, `-frame-probe`) fielen
/// beim schnellen Auf- und Zuziehen reproduzierbar Bilder aus. Der Zustand
/// eines Zuges gehört dem Gezogenen — hier drin sieht ihn sonst niemand.
///
/// **Was sich alles mitbewegt.** Zwischen Karte und ganzer Seite gibt es
/// keinen Umschaltpunkt: Höhe, ECKRADIUS, SEITENRÄNDER und der Überstand nach
/// unten hängen alle am selben Fortschritt (`MorePanel.progress`). Bei voller
/// Größe steht die Tafel von der oberen Sicherheitszone bis an die
/// Unterkante, von Kante zu Kante, mit dem Eckradius des Bildschirms — und
/// die Leiste liegt sichtbar darauf (sie wird nach der Tafel gezeichnet).
///
/// **Der Inhalt wird auf DIESELBE Form geschnitten, die sich bewegt.** Ohne
/// das lief der Text während des Aufklappens neben dem Glas her: die Fläche
/// wächst aus der Leiste, der Inhalt steht aber sofort in voller Breite da
/// (nachgemessen und im Bild belegt). Ein Schnitt auf die animierte Form ist
/// die einzige Zusage, die in JEDEM Zwischenschritt hält — auch während
/// Radius und Ränder noch unterwegs sind.
struct MorePanelSurface: View {
    let store: HabitStore
    let cloudStatus: CloudSyncStatus
    let namespace: Namespace.ID
    let onOpen: (MoreRoute) -> Void
    /// Zug nach unten über die Schwelle: die Tafel schließt.
    let onDismiss: () -> Void

    /// Steht die Tafel auf ihrer vollen Größe? Entsteht und vergeht MIT der
    /// Tafel — deshalb öffnet sie immer klein.
    @State private var expanded = false
    /// Mitgezogen (negativ = nach oben).
    @State private var drag: CGFloat = 0
    /// Einmal beim Erscheinen gelesen: Höhe der sicheren Fläche und die
    /// untere Sicherheitszone. Beides ändert sich im Hochformat nicht, und
    /// eine Messung pro Bild wäre genau die Art Arbeit, die hier wegsollte.
    @State private var metrics = PanelMetrics.current()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        #if DEBUG
        let _ = FrameProbe.shared.mark("panel.body")
        #endif
        let height = MorePanel.height(container: metrics.container,
                                      safeBottom: metrics.safeBottom,
                                      expanded: expanded, drag: drag)
        let progress = MorePanel.progress(container: metrics.container,
                                          safeBottom: metrics.safeBottom,
                                          expanded: expanded, drag: drag)
        let radius = MorePanel.cornerRadius(progress: progress,
                                            safeBottom: metrics.safeBottom)
        let side = MorePanel.sideOverhang(progress: progress,
                                          gutter: Theme.Metrics.gutter)
        let bottom = MorePanel.bottomOverhang(progress: progress,
                                              safeBottom: metrics.safeBottom,
                                              bar: Theme.Metrics.control,
                                              gap: Theme.Metrics.gap)

        // Der Innenabstand der Liste hängt am ZIEL, nicht am laufenden Zug.
        // Er hing einmal am Fortschritt — dann rechnet die Liste bei JEDEM
        // Bildschritt eines Zuges ihre Ränder neu, und genau solche Arbeit
        // pro Bild ist das, was hier wegsollte. Sichtbar wird der Unterschied
        // nur, während der Finger unten ist; danach steht er richtig.
        let settledInset = MorePanel.bottomOverhang(progress: expanded ? 1 : 0,
                                                    safeBottom: metrics.safeBottom,
                                                    bar: Theme.Metrics.control,
                                                    gap: Theme.Metrics.gap)

        return content(listInset: settledInset)
            // Feste Höhe statt „so hoch wie der Inhalt": die Liste ist immer
            // länger als der Platz, und eine gerechnete Höhe hält die Fahrt
            // ruhig.
            .frame(maxWidth: .infinity)
            .frame(height: height)
            // ITEM: der Schnitt auf die ANIMIERTE Form. Er steht VOR dem Glas
            // und vor den negativen Rändern — die Ränder schlagen die Fläche
            // erst auf ihre volle Breite auf, und genau diese Breite ist die,
            // auf die geschnitten wird.
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .modifier(PanelGlass(radius: radius, namespace: namespace))
            // Negative Ränder: der Kasten steht im Seitenrand der Leiste, die
            // FLÄCHE wächst darüber hinaus bis an die Bildschirmkanten.
            .padding(.horizontal, -side)
            .padding(.bottom, -bottom)
            .offset(y: MorePanel.offset(expanded: expanded, drag: drag))
            .transition(transition)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("more-panel")
            .accessibilityValue(expanded
                                ? String(localized: "Ganze Seite")
                                : String(localized: "Klein"))
            // Auch ohne Geste erreichbar: VoiceOver und Vollzugriff kennen
            // keinen Wisch am Griff.
            .accessibilityAction(named: expanded
                                 ? String(localized: "Tafel verkleinern")
                                 : String(localized: "Tafel vergrößern")) {
                settle(expanded: !expanded)
            }
    }

    /// `listInset` ist genau der Überstand nach unten: so weit steht die
    /// Fläche bei voller Größe UNTER der Leiste, und so weit muss der
    /// scrollbare Inhalt darüber enden — sonst liegt die letzte Zeile hinter
    /// dem Umschalter und ist nicht mehr erreichbar. Als Sicherheitszone
    /// gesetzt und nicht als Rand: die Liste soll DURCH den Bereich scrollen
    /// dürfen, nur nicht dort aufhören.
    private func content(listInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            handle
            // `.equatable()` ist hier Tempo, nicht Kosmetik: ohne das baut
            // SwiftUI die ganze Liste bei JEDEM Bildschritt eines Zuges neu
            // auf, weil der Aufrufer eine frische Closure mitgibt. Mit dem
            // Vergleich hängt die Liste nur noch an dem, was sie wirklich
            // zeigt — Änderungen am Speicher kommen weiterhin an (die laufen
            // über Observation, nicht über diesen Vergleich).
            MoreView(store: store, cloudStatus: cloudStatus, onOpen: onOpen)
                .equatable()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // Ohne `animation(nil)` läuft der Abstand die ganze
                    // Einrast-Animation lang mit und die Liste rechnet dabei
                    // Bild für Bild neu. Er darf sofort stehen: sichtbar ist
                    // erst das Ergebnis.
                    Color.clear
                        .frame(height: max(0, listInset))
                        .animation(nil, value: listInset)
                }
        }
    }

    /// Griff und Titel. Der Zug hängt HIER und nicht an der ganzen Tafel:
    /// eine Ziehgeste über der Liste würde mit deren Scrollen streiten, und
    /// der Griff ist ohnehin die Stelle, an die man greift. Er ist dafür
    /// bewusst hoch (Griff PLUS Titelzeile PLUS Ränder) — das ist die
    /// „nicht scrollende" Fläche der Tafel, und bei voller Größe sitzt sie
    /// direkt unter der Statusleiste, wo man sie wieder herunterzieht.
    private var handle: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(.tertiary)
                .frame(width: 36, height: 5)
            Text(String(localized: "Mehr"))
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("more-grabber")
    }

    /// EINE Geste für beide Richtungen: nach oben wächst die Tafel auf die
    /// ganze Seite, nach unten schrumpft sie und schließt. Was der Zug
    /// bedeutet, entscheidet `MorePanel` — hier steht nur, was mit der
    /// Entscheidung passiert.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // Reduzierte Bewegung: nicht mitziehen (das IST die
                // Bewegung), nur beim Loslassen springen.
                guard !reduceMotion else { return }
                drag = value.translation.height
            }
            .onEnded { value in
                let outcome = MorePanel.resolve(drag: value.translation.height,
                                                predicted: value.predictedEndTranslation.height,
                                                expanded: expanded)
                switch outcome {
                case .expand:   settle(expanded: true)
                case .collapse: settle(expanded: false)
                case .dismiss:  drag = 0; onDismiss()
                }
            }
    }

    /// Zug beenden. Rücksetzen des Zuges und der Zielzustand gehören in
    /// EINEN Schritt: getrennt sprang die Höhe erst ohne Animation zurück auf
    /// die Basis und federte von dort — zwei Bewegungen für eine Geste, und
    /// bei schnellen Zügen zwei Animationen übereinander.
    private func settle(expanded want: Bool) {
        if reduceMotion {
            drag = 0
            expanded = want
        } else {
            withAnimation(PanelMotion.settle) {
                drag = 0
                expanded = want
            }
        }
    }

    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        // Anker auf dem Mehr-Segment, Unterkante. Der Wert ist nachgemessen,
        // nicht geschätzt: das Segment sitzt auf einem 440-pt-Gerät bei rund
        // 162 pt, die Zeile beginnt bei 16 und ist 408 breit —
        // (162 − 16) / 408 ≈ 0,36. Die Tafel wächst damit genau dort heraus,
        // wo getippt wurde, statt aus der Mitte.
        return .scale(scale: 0.06, anchor: UnitPoint(x: 0.36, y: 1))
            .combined(with: .opacity)
    }
}

/// Die beiden Bewegungen der Tafel an EINER Stelle — und die Möglichkeit,
/// sie für eine Aufnahme zu strecken. Eine Fahrt von 0,3 s lässt sich mit
/// `simctl io screenshot` nicht zuverlässig in der Mitte erwischen; ohne
/// nachprüfbares Standbild bleibt „sieht jetzt richtig aus" eine Behauptung.
enum PanelMotion {
    /// Streckfaktor. Nur im Debug-Build und nur mit `-slow-panel`.
    static var factor: Double {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-slow-panel") ? 8 : 1
        #else
        1
        #endif
    }

    /// Auf- und Zuklappen (die Tafel kommt und geht).
    static var open: Animation { .spring(response: 0.42 * factor, dampingFraction: 0.84) }
    /// Einrasten nach einem Zug (Karte ↔ ganze Seite).
    static var settle: Animation { .snappy(duration: 0.3 * factor) }
}

/// Höhe der sicheren Fläche und untere Sicherheitszone — die zwei Maße, aus
/// denen die volle Größe der Tafel fällt.
///
/// Gelesen wird am FENSTER, nicht am Bildschirm: im Split View auf dem iPad
/// ist der Bildschirm nicht die App. Nur wenn gar keine Szene erreichbar ist
/// (Vorschauen, Tests), fällt es auf den Bildschirm zurück.
struct PanelMetrics: Equatable {
    let container: CGFloat
    let safeBottom: CGFloat

    static func current() -> PanelMetrics {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let window = scene?.keyWindow, window.bounds.height > 0 else {
            return PanelMetrics(container: UIScreen.main.bounds.height, safeBottom: 0)
        }
        let insets = window.safeAreaInsets
        return PanelMetrics(container: max(0, window.bounds.height - insets.top - insets.bottom),
                            safeBottom: insets.bottom)
    }
}

/// Die Mehr-Tafel. Ab iOS 26 echtes Liquid Glass im SELBEN
/// `GlassEffectContainer` wie die Leiste (damit beide dieselbe Rechnung und
/// dieselbe Lichtstimmung bekommen), aber mit EIGENER Form — die Vereinigung
/// mit der Kapsel war zu viel des Guten, siehe `ContentView.chromeUnion`.
/// Darunter dieselbe Material-Attrappe wie beim Chrom.
///
/// Der Radius kommt von aussen: er läuft mit der Größe mit (Kartenecke →
/// Bildschirmecke), und Glas und Schnitt müssen DIESELBE Form benutzen —
/// sonst steht in der Fahrt eine Kante neben der anderen.
struct PanelGlass: ViewModifier {
    let radius: CGFloat
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular.tint(Color(.systemBackground).opacity(0.6)),
                             in: .rect(cornerRadius: radius, style: .continuous))
                .glassEffectID("more-panel", in: namespace)
        } else {
            content
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.quaternary))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        }
    }
}
