import SwiftUI
import UIKit
import Observation

/// Wie weit die Mehr-Tafel gerade aufgezogen ist — der EINE Wert, den ausser
/// der Tafel selbst noch jemand braucht: die Leiste unten, die sich dabei
/// zurückzieht (siehe `MorePanel.chromeOpacity`).
///
/// **Warum nicht einfach ein `@State` in `ContentView`.** Genau daran hing der
/// Zug einmal, und jeder Bildschritt wertete damit den ganzen
/// `ContentView.body` neu aus — samt Habit-Liste, samt jeder Karte
/// (nachgemessen mit der Bildzeit-Sonde; beim schnellen Auf- und Zuziehen
/// fielen reproduzierbar Bilder aus). Als beobachtbares Objekt hängt an dem
/// Wert nur, wer ihn AUCH LIEST: die Tafel schreibt, die kleine Hülle um die
/// Leiste liest. `ContentView` selbst liest ihn nie und wird deshalb auch
/// nicht neu ausgewertet.
///
/// **Und keine zweite Feder.** Geschrieben wird ausschließlich aus derselben
/// Rechnung (`MorePanel.progress`) und innerhalb derselben Transaktion wie
/// Höhe, Radius und Überstand. Es gibt damit weiterhin genau EINE Bewegung
/// pro Geste — eine zweite Animation auf derselben Geste war die Ursache des
/// Nachziehens, das hier schon einmal behoben werden musste.
@Observable
final class MorePanelProgress {
    /// 0 = Karte, 1 = ganze Seite.
    var value: CGFloat = 0
    /// Die untere Sicherheitszone, gemeldet von der Tafel beim Erscheinen.
    ///
    /// Sie steht HIER und wird nicht dort gelesen, wo sie gebraucht wird —
    /// und das ist keine Umständlichkeit, sondern eine Lehre: ein
    /// `PanelMetrics.current()` im Eigenschafts-Initialisierer der Hülle um
    /// die Leiste liest `window.safeAreaInsets` und damit UIKit MITTEN in der
    /// Auswertung von `ContentView.body`. Das Ergebnis war reproduzierbar
    /// kaputtes Layout: die Tafel bekam im Stapel die Höhe null und hing als
    /// 94-pt-Streifen an der Unterkante, während ihre eigene Rechnung
    /// unverändert 498,8 pt sagte. Die Tafel darf so messen — sie entsteht
    /// EINMAL, wenn sie geöffnet wird; die Hülle entsteht bei jeder
    /// Auswertung neu.
    var safeBottom: CGFloat = 0
}

/// Die Leiste unten, während die Tafel wächst — Umschalter und Anlegen-Knopf
/// ziehen sich zurück, sobald aus der Karte eine ganze Seite wird.
///
/// **Warum es diese Hülle überhaupt gibt.** Sie ist die einzige Ansicht, die
/// `MorePanelProgress` LIEST. Damit hängt der Zug an ihr — und nur an ihr.
/// Der `ContentView.body` sieht den Wert nicht und wird beim Ziehen weiterhin
/// nicht neu ausgewertet; die Leiste selbst ist ein paar Dutzend Ansichten,
/// die Habit-Liste dahinter sind es nicht.
///
/// **Der Inhalt wird nicht neu gebaut.** Er kommt als FERTIGER Wert herein,
/// nicht als Closure: was die Hülle pro Bild tut, ist Deckkraft und Versatz
/// setzen, nicht die Leiste noch einmal zusammenstellen.
///
/// **Die Höhe bleibt stehen.** Zurückziehen heißt fahren und verblassen, NICHT
/// aus dem Stapel verschwinden: der untere Überstand der Tafel ist genau auf
/// den Platz gerechnet, den die Leiste einnimmt (siehe
/// `MorePanel.bottomOverhang`). Eine Leiste, die ihre Höhe aufgibt, zöge die
/// Tafel im selben Bild um 60 pt nach unten.
struct WithdrawingChrome<Content: View>: View {
    let panel: MorePanelProgress
    let content: Content

    var body: some View {
        #if DEBUG
        let _ = FrameProbe.shared.mark("chrome.body")
        #endif
        let progress = panel.value
        let safeBottom = panel.safeBottom
        // Deckkraft, Versatz und Trefferbarkeit kommen aus DEMSELBEN Verlauf
        // — auseinanderlaufen können sie damit nicht.
        let interactive = MorePanel.chromeInteractive(progress: progress)
        return content
            .opacity(MorePanel.chromeOpacity(progress: progress))
            .offset(y: MorePanel.chromeOffset(progress: progress,
                                              bar: Theme.Metrics.control,
                                              gap: Theme.Metrics.gap,
                                              safeBottom: safeBottom))
            // NICHT bloß Kosmetik: eine Ansicht mit `opacity(0)` ist in
            // SwiftUI weiterhin treffbar. Ohne diese Zeile läge auf der ganzen
            // Seite ein unsichtbarer Anlegen-Knopf, und ein Tipp dorthin
            // öffnete das Anlegen-Blatt aus dem Nichts.
            .allowsHitTesting(interactive)
            // Dasselbe für VoiceOver: was nicht da ist, soll auch nicht
            // vorgelesen werden.
            .accessibilityHidden(!interactive)
    }
}

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
/// keinen Umschaltpunkt: Höhe, ECKRADIUS, SEITENRÄNDER, der Überstand nach
/// unten UND das Zurückziehen der Leiste hängen alle am selben Fortschritt
/// (`MorePanel.progress`). Bei voller Größe steht die Tafel von der oberen
/// Sicherheitszone bis an die Unterkante, von Kante zu Kante, mit dem
/// Eckradius des Bildschirms.
///
/// **Auf der Karte liegt die Leiste darauf, auf der ganzen Seite nicht mehr.**
/// Die Leiste wird nach der Tafel gezeichnet und deckt deren unteren Überstand
/// ab — auf der Karte ist das richtig, die Tafel wächst schließlich aus ihr
/// heraus. Sobald die Tafel den Bildschirm füllt, gibt es aber kein „daneben"
/// mehr, über dem etwas schweben dürfte: Umschalter und Anlegen-Knopf ziehen
/// sich zurück (`WithdrawingChrome`), und der GRIFF ist ab da der einzige Weg
/// zurück. Er bleibt deshalb während der ganzen Fahrt sichtbar und treffbar.
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
    /// Wohin der Fortschritt gemeldet wird. NUR schreibend benutzt — diese
    /// Ansicht liest ihn nie, sie rechnet ihn ohnehin selbst.
    let chrome: MorePanelProgress
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
    @Environment(\.colorScheme) private var scheme

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
            // DER INHALT BEHÄLT SEINE BREITE. Der Überstand nach den Seiten
            // wird hier als Rand WIEDER ABGEZOGEN, bevor die negativen Ränder
            // unten die Fläche aufschlagen: die Tafel wächst auf die volle
            // Bildschirmbreite, die Liste darin bleibt exakt so breit wie im
            // kleinen Zustand.
            //
            // Ohne das bekommt die Liste bei JEDEM Bildschritt eines Zuges
            // eine andere Breite (nachgemessen: 408 → 440 pt) und setzt ihre
            // Zeilen jedes Mal neu — Fußnoten brechen anders um, Häkchen und
            // Chevrons wandern. Genau das war „the content adjusts itself".
            // Die Höhe darf mitlaufen: eine Liste, die höher wird, zeigt
            // einfach mehr Zeilen, ihre Zeilen bleiben stehen.
            //
            // Und es ist nicht bloß der ruhigere Weg, sondern der richtigere:
            // die Textspalte ist in beiden Ruhelagen dieselbe. Die Tafel
            // WÄCHST, sie setzt sich nicht neu.
            .padding(.horizontal, side)
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
            .offset(y: MorePanel.offset(container: metrics.container,
                                        safeBottom: metrics.safeBottom,
                                        expanded: expanded, drag: drag))
            .transition(transition)
            // Die Tafel öffnet immer klein — also steht die Leiste beim
            // Erscheinen. Und beim Verschwinden steht sie WIEDER: das ist die
            // letzte Sicherung gegen den einen Zustand, den es hier nicht
            // geben darf — eine geschlossene Tafel und dazu keine Leiste. Der
            // reguläre Weg setzt den Wert schon beim Schließen zurück (siehe
            // ContentView.select), hier fällt nichts mehr an; es kostet aber
            // auch nichts und deckt jeden Weg ab, der die Tafel sonst noch
            // aus dem Baum nimmt.
            .onAppear {
                chrome.value = 0
                // Die Tafel misst ohnehin — und sie darf es: sie entsteht
                // einmal beim Öffnen, nicht bei jeder Auswertung.
                chrome.safeBottom = metrics.safeBottom
            }
            .onDisappear { chrome.value = 0 }
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
            grabber
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

    /// Der Zugbalken.
    ///
    /// Auf der ganzen Seite ist er der EINZIGE Weg zurück — es gibt kein
    /// „daneben" mehr, auf das man tippen könnte, und die Leiste unten hat
    /// sich zurückgezogen. Ein Griff, den man im Dunkeln suchen muss, ist
    /// deshalb nicht bloß unschön, sondern die Sackgasse selbst. Genau das
    /// war die Rückmeldung.
    ///
    /// `.tertiary` ist in beiden Schemata gleich schwach (rund 0,3 Deckkraft)
    /// — auf dem hellen Tafelglas reicht das, auf dem dunklen nicht. Also
    /// zwei gemessene Werte statt einer hierarchischen Stufe, und im Dunkeln
    /// zusätzlich eine hauchdünne dunkle Kante: sie setzt den hellen Balken
    /// vom aufgehellten Glas ab, ohne ihn im Hellen zu verändern.
    private var grabber: some View {
        let dark = scheme == .dark
        return Capsule()
            .fill(Color.primary.opacity(MorePanel.grabberOpacity(dark: dark)))
            .frame(width: MorePanel.grabberWidth, height: MorePanel.grabberHeight)
            .overlay {
                if dark {
                    Capsule().strokeBorder(Color.black.opacity(0.22), lineWidth: 0.5)
                }
            }
            .accessibilityHidden(true)
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
                // In DERSELBEN Runde wie die Höhe und aus DERSELBEN Rechnung.
                publish(drag: drag, expanded: expanded)
            }
            .onEnded { value in
                // Aus dem großen Zustand liegt die Karte bei `shrinkTravel`,
                // nicht bei 0 — die Auflösung muss dieselbe Strecke sehen wie
                // die Geometrie, sonst schlösse ein Zug an einer anderen
                // Stelle, als er die Tafel hingezogen hat.
                let travel = expanded
                    ? MorePanel.shrinkTravel(container: metrics.container,
                                             safeBottom: metrics.safeBottom)
                    : 0
                let outcome = MorePanel.resolve(drag: value.translation.height,
                                                predicted: value.predictedEndTranslation.height,
                                                expanded: expanded,
                                                travel: travel)
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
            publish(drag: 0, expanded: want)
        } else {
            withAnimation(PanelMotion.settle) {
                drag = 0
                expanded = want
                // MIT in der Transaktion: die Leiste bekommt damit exakt
                // dieselbe Feder wie Höhe und Radius. Eine eigene Animation
                // an dieser Stelle wäre die zweite Bewegung auf einer Geste
                // — genau der Fehler, der das Nachziehen verursacht hat.
                publish(drag: 0, expanded: want)
            }
        }
    }

    /// Den Fortschritt nach draussen melden — aus derselben Rechnung, mit der
    /// die Tafel selbst ihre Höhe, ihren Radius und ihre Überstände bildet.
    /// Es gibt keine zweite Quelle: was hier ankommt, IST `MorePanel.progress`.
    private func publish(drag: CGFloat, expanded: Bool) {
        chrome.value = MorePanel.progress(container: metrics.container,
                                          safeBottom: metrics.safeBottom,
                                          expanded: expanded, drag: drag)
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
