import SwiftUI
import UIKit

/// Das Herzstück: 53 Wochen × 7 Tage, Sonntag oben, Monatsmarken darüber,
/// scrollt zu heute. Zukunft ist gedimmt und tot.
///
/// **Ein Tipp auf eine Zelle SCHREIBT NICHT.** Er WÄHLT den Tag aus und
/// öffnet damit die Nacharbeiten-Karte an genau diesem Datum
/// (`onSelectDay`). Vorher hakte er direkt ab: auf einem 8- bis 12-pt-Quadrat
/// heißt das, dass ein Fehlgriff still einen vergangenen Tag umschreibt — an
/// der einzigen Stelle der App, an der Wochen alter Verlauf mit einem Finger
/// erreichbar ist. Geschrieben wird jetzt erst in der Karte, auf eine
/// benannte Aktion. Deshalb ist die Rückmeldung hier auch eine
/// AUSWAHL-Haptik und nicht mehr der Stups des Abhakens: es ist nichts
/// bestätigt worden.
///
/// Drei Dinge, die hier bewusst NICHT der Umgebung folgen:
///  * **Layout-Richtung**: die Chronologie läuft immer links→rechts, auch
///    in ar/ur. Ein gespiegelter Jahresverlauf ist kein RTL-Feature,
///    sondern ein Lesefehler.
///  * **Zellgröße**: skaliert mit der verfügbaren BREITE (SE/mini bekommen
///    kleinere Quadrate), aber nie mit Dynamic Type — ein Raster aus
///    riesigen Quadraten ist nicht die Idee. Nur die Labels wachsen mit.
///  * **Scroll-zu-heute**: bei „Bewegung reduzieren" ohne Animation.
/// `Equatable`, damit `.equatable()` an den heißen Stellen greift: das Raster
/// ist mit Abstand der teuerste Teilbaum einer Karte (371 Zellen), und es
/// hängt an KEINEM der Werte, die sich bei Chrom-Umbauten ändern (collapsed,
/// Tafel, Toast). Ohne den Vergleich riss jede `ContentView`-Auswertung alle
/// sichtbaren Raster mit, weil die frisch gebauten Closures für SwiftUI nie
/// gleich aussehen. Der Callback bleibt darum ausdrücklich AUSSERHALB des
/// Vergleichs — er ist Verhalten, nicht Anzeige, und an den `.equatable()`-
/// Stellen in jeder Auswertung semantisch derselbe.
struct ContributionGrid: View, Equatable {
    static func == (a: ContributionGrid, b: ContributionGrid) -> Bool {
        a.habit == b.habit
            && a.weeks == b.weeks
            && a.cellSize == b.cellSize
            && a.gap == b.gap
            && a.interactive == b.interactive
            && a.showsMonthLabels == b.showsMonthLabels
            && (a.onSelectDay == nil) == (b.onSelectDay == nil)
    }

    let habit: Habit
    var weeks: Int = 53
    /// nil = adaptiv (aus der verfügbaren Breite); gesetzt = feste Größe
    /// (Teilen-Karte, Vorschauen).
    var cellSize: CGFloat?
    var gap: CGFloat?
    var interactive: Bool = true
    var showsMonthLabels: Bool = true
    /// Tag AUSGEWÄHLT (nicht geändert): der Aufrufer öffnet damit die
    /// Nacharbeiten-Karte. Nil = das Raster ist nur Anzeige.
    var onSelectDay: ((String) -> Void)?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// GLOBALE Farbe + eigene Paletten; die Habit-eigene Farbe legt sich
    /// darüber (aufgelöst in `PaletteStyle.resolve`).
    @Environment(\.palettes) private var palettes
    /// Gemessene Breite des Rasters; 0 bis zur ersten Layout-Runde.
    @State private var available: CGFloat = 0
    /// Referenzmaß 100, skaliert mit Dynamic Type: `labelScale / 100` ist
    /// exakt der Faktor, mit dem `.caption2` gerade wächst. Damit lässt sich
    /// die Labelbreite messen, ohne die Trait-Collection nachzubauen.
    @ScaledMetric(relativeTo: .caption2) private var labelScale: CGFloat = 100

    /// Referenz: 11 pt Zelle + 3 pt Lücke ergeben auf einem 393-pt-Gerät
    /// rund 24 sichtbare Spalten. Diese Spaltenzahl halten wir konstant und
    /// leiten die Zellgröße daraus ab — auf einem SE werden die Quadrate
    /// kleiner statt gedrängt, auf einem Max nicht endlos größer.
    private static let referenceColumns: CGFloat = 24
    private static let referencePitch: CGFloat = 14

    private var metrics: (cell: CGFloat, gap: CGFloat) {
        if let cellSize { return (cellSize, gap ?? GridCell.gap) }
        let pitch = available > 0
            ? available / Self.referenceColumns
            : Self.referencePitch
        return (min(GridCell.size, max(8, pitch * 11 / Self.referencePitch)),
                min(GridCell.gap, max(2, pitch * 3 / Self.referencePitch)))
    }

    var body: some View {
        #if DEBUG
        let _ = FrameProbe.shared.mark("grid.body")
        #endif
        let m = metrics
        let pitch = m.cell + m.gap
        let snapshot = GridCalendar.snapshot(habit: habit, weeks: weeks, today: DayKey.today())
        let contentWidth = CGFloat(weeks) * pitch - m.gap
        let marks = GridCalendar.placeMarks(snapshot.marks,
                                            pitch: pitch,
                                            contentWidth: contentWidth) { mark in
            ContributionGrid.labelWidth(GridCalendar.label(for: mark), scale: labelScale / 100)
        }

        ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    if showsMonthLabels {
                        monthRow(marks, width: contentWidth)
                    }
                    // EIN Canvas statt 371 Einzel-Ansichten. Der Unterschied
                    // ist gemessen, nicht geraten: mit einer Shape-Ansicht je
                    // Zelle trug jede Karte ~371 lebende Views — der Aufbau
                    // einer Liste, eines Tabs oder eines Suchtreffers
                    // multiplizierte das mit der Kartenzahl (FrameProbe:
                    // ~0,5 s Erst-Aufbau des Such-Tabs). Gezeichnet wird aus
                    // EXAKT derselben Geometrie, aus der auch der
                    // Tipp-Treffer gerechnet wird.
                    cellCanvas(snapshot: snapshot, cell: m.cell, gap: m.gap,
                               width: contentWidth)
                        .id(Self.gridID)
                        // EIN Tipp-Erkenner für alle 371 Zellen. Getroffen
                        // wird über die Geometrie — die Tippbarkeits-Regel
                        // bleibt Zeichen für Zeichen `GridCalendar.isTappable`.
                        .contentShape(Rectangle())
                        .modifier(GridTap(enabled: interactive && onSelectDay != nil) { location in
                            guard let key = GridCalendar.hitKey(location: location,
                                                                keys: snapshot.keys,
                                                                cell: m.cell,
                                                                gap: m.gap),
                                  GridCalendar.isTappable(key: key,
                                                          interactive: interactive,
                                                          today: snapshot.today) else { return }
                            // Auswahl-Haptik, nicht die des Abhakens: hier
                            // wird nichts bestätigt, hier wird ausgewählt.
                            Theme.Haptics.select()
                            onSelectDay?(key)
                        })
                }
                .padding(.vertical, 2)
        }
        // Startet AN der rechten Kante — heute — statt nach dem Aufbau
        // dorthin zu scrollen: das alte `scrollTo` je Karte zwang beim
        // Listen-/Tab-Aufbau acht breite ScrollViews zu doppeltem Layout
        // (mitgemessen im Such-Tab-Aufbau).
        .defaultScrollAnchor(.trailing)
        .background(widthReader)
        // Der Abhak-Puls: ändert sich HEUTE, springt ein Ring um die
        // Heute-Zelle kurz auf — die eine Stelle, an der sich ein Check-in
        // im Raster zeigt, bekommt die eine kleine Bewegung. Bei „Bewegung
        // reduzieren" bleibt nur der Farbwechsel der Zelle.
        .onChange(of: habit.log[DayKey.today()]) { _, _ in
            guard interactive, !reduceMotion else { return }
            checkPulse = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55).delay(0.02)) {
                checkPulse = false
            }
        }
        // Chronologie wird nie gespiegelt — auch nicht in ar/ur.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary(filled: snapshot.filledCount))
        .accessibilityIdentifier("contribution-grid")
    }

    // MARK: – Bausteine

    /// Monatszeile: absolut positionierte Labels über „ihrer" Spalte. Ein
    /// unsichtbarer Platzhalter gibt der Zeile die (mit Dynamic Type
    /// wachsende) Höhe, damit nichts ins Raster rutscht.
    private func monthRow(_ marks: [GridCalendar.PlacedMark], width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Text(verbatim: "Mmm").font(.caption2).hidden()
            ForEach(marks, id: \.mark) { placed in
                Text(verbatim: GridCalendar.label(for: placed.mark))
                    .font(.caption2)
                    // .secondary käme auf Weiß nur auf ~3,5:1 — für 11-pt-
                    // Text zu wenig. Gedämpftes Label statt Sekundärfarbe.
                    .foregroundStyle(Color(.label).opacity(0.7))
                    .fixedSize()
                    .offset(x: placed.x)
            }
        }
        .frame(width: max(width, 0), alignment: .topLeading)
        .accessibilityHidden(true)
    }

    /// Echte Textbreite der Monatsabkürzung in der aktuellen Schriftgröße.
    /// Gemessen statt geschätzt: "Aug." und "أغسطس" unterscheiden sich um
    /// den Faktor zwei, und bei Accessibility-Größen nochmal.
    private static func labelWidth(_ text: String, scale: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let size = max(1, 11 * scale)
        let key = "\(Int(size.rounded()))|\(text)"
        if let cached = labelWidthCache.withLock({ $0[key] }) { return cached }
        let width = (text as NSString)
            .size(withAttributes: [.font: UIFont.systemFont(ofSize: size)]).width
        labelWidthCache.withLock { $0[key] = width }
        return width
    }

    private static let labelWidthCache = Locked([String: CGFloat]())

    /// Anker fürs Scroll-zu-heute: das Canvas selbst; `anchor: .trailing`
    /// bringt seine rechte Kante — heute — ins Bild.
    private static let gridID = "grid-canvas"

    /// Läuft der Abhak-Puls gerade? (Ring um die Heute-Zelle, kurz.)
    @State private var checkPulse = false

    private func cellCanvas(snapshot: GridCalendar.Snapshot,
                            cell: CGFloat, gap: CGFloat,
                            width: CGFloat) -> some View {
        let pitch = cell + gap
        let height = CGFloat(GridCalendar.rows) * pitch - gap
        let style = palettes.style(for: habit)
        let dark = scheme == .dark
        // Heute-Zelle für Rahmen und Puls: letzte Spalte, Zeile aus dem
        // Schnappschuss.
        let todayRect: CGRect? = snapshot.keys.last
            .flatMap { $0.firstIndex(of: snapshot.today) }
            .map { row in CGRect(x: CGFloat(snapshot.keys.count - 1) * pitch,
                                 y: CGFloat(row) * pitch,
                                 width: cell, height: cell) }
        return Canvas { context, _ in
            // Farben EINMAL je Stufe auflösen, nicht je Zelle: 371 dynamische
            // Color-Auflösungen und 371 Continuous-Bezier-Pfade machten den
            // Aufbau TEURER als die alten Einzel-Views (FrameProbe: ~1 s
            // Such-Tab-Aufbau). Ein Pfad je STUFE, per Translation
            // wiederverwendet, und schlichte runde Ecken — bei 2 pt Radius
            // vom Continuous-Profil nicht zu unterscheiden.
            var shading: [Int: GraphicsContext.Shading] = [:]
            var dimmedShading: [Int: GraphicsContext.Shading] = [:]
            let cellPath = Path(roundedRect: CGRect(x: 0, y: 0, width: cell, height: cell),
                                cornerRadius: GridCell.radius)
            for (wi, column) in snapshot.keys.enumerated() {
                for row in 0..<GridCalendar.rows {
                    let level = snapshot.levels[wi][row]
                    let future = column[row] == nil
                    // Zukunft: gedimmt und ohne Tipp-Wirkung (isTappable im
                    // gemeinsamen Erkenner). Die Regel bleibt dieselbe —
                    // geändert hat sich nur, WO sie gezeichnet wird.
                    let fill: GraphicsContext.Shading
                    if future {
                        if dimmedShading[level] == nil {
                            dimmedShading[level] = .color(
                                Theme.level(level, dark: dark, palette: style).opacity(0.35))
                        }
                        fill = dimmedShading[level]!
                    } else {
                        if shading[level] == nil {
                            shading[level] = .color(
                                Theme.level(level, dark: dark, palette: style))
                        }
                        fill = shading[level]!
                    }
                    var cellContext = context
                    cellContext.translateBy(x: CGFloat(wi) * pitch,
                                            y: CGFloat(row) * pitch)
                    cellContext.fill(cellPath, with: fill)
                }
            }
            if let todayRect {
                context.stroke(Path(roundedRect: todayRect.insetBy(dx: 0.6, dy: 0.6),
                                    cornerRadius: GridCell.radius),
                               with: .color(.primary), lineWidth: 1.2)
            }
        }
        .frame(width: max(width, 0), height: height)
        // Der Puls liegt ÜBER dem Canvas — das Canvas selbst animiert
        // nicht (es zeichnet Zustände, keine Übergänge).
        .overlay(alignment: .topLeading) {
            if let todayRect {
                RoundedRectangle(cornerRadius: GridCell.radius, style: .continuous)
                    .strokeBorder(Theme.accentText(style), lineWidth: 1.4)
                    .frame(width: todayRect.width, height: todayRect.height)
                    .offset(x: todayRect.minX, y: todayRect.minY)
                    .scaleEffect(checkPulse ? 1.9 : 1)
                    .opacity(checkPulse ? 0.9 : 0)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Misst die Breite, die dem Raster zur Verfügung steht — daraus fällt
    /// die Zellgröße. Kein Layout-Zirkel: die Breite hängt am Container,
    /// nicht am Inhalt.
    private var widthReader: some View {
        GeometryReader { geo in
            Color.clear.preference(key: GridWidthKey.self, value: geo.size.width)
        }
        .onPreferenceChange(GridWidthKey.self) { width in
            if abs(width - available) > 0.5 { available = width }
        }
    }

    private func summary(filled: Int) -> String {
        String(localized: "\(habit.name): \(filled) Tage im letzten Jahr, aktuelle Serie \(habit.streak()).")
    }
}

// MARK: – Die Zelle

/// EINE Rasterzelle. Eigenes Bauteil, weil sie nicht nur im Jahresraster
/// vorkommt: die Farbwahl in „Mehr" und im Bearbeiten-Blatt zeigt dieselben
/// Quadrate — gleiche Kantenlänge, gleicher Eckradius, gleicher Abstand. Eine
/// nachgebaute Vorschau würde beim nächsten Anfassen des Rasters auseinander
/// laufen; hier kann sie das nicht.
struct GridCell: View {
    let color: Color
    var size: CGFloat = GridCell.size

    /// Eckradius jeder Zelle.
    static let radius: CGFloat = 2
    /// Kantenlänge im ausgewachsenen Raster (die adaptive Skala läuft von 8
    /// bis hierher) — und damit das Maß, das die Vorschauen nehmen.
    static let size: CGFloat = 12
    /// Abstand zwischen zwei Zellen im ausgewachsenen Raster.
    static let gap: CGFloat = 3

    var body: some View {
        RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
    }
}

/// Die Palette als das, was sie später IST: fünf Rasterzellen l0…l4 in
/// Rastermaßen und Rasterreihenfolge. Das ist die Farbwahl der App — keine
/// Farbtupfer, keine Kreise, keine Annäherung.
struct RampSwatch: View {
    let style: PaletteStyle
    let dark: Bool
    var size: CGFloat = GridCell.size

    var body: some View {
        HStack(spacing: GridCell.gap) {
            ForEach(0..<5, id: \.self) { level in
                GridCell(color: Theme.level(level, dark: dark, palette: style), size: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Winziger Mutex um einen Wert — reicht für den Messcache und hält den
/// Zustand auch außerhalb des Main-Threads sauber.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

private struct GridWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Tipp-Erkenner fürs GANZE Raster — nur angehängt, wenn das Raster
/// überhaupt interaktiv ist (Teilen-Karte und Vorschau bekommen gar keine
/// Gestenerkennung, nicht bloß einen `guard` im Handler).
private struct GridTap: ViewModifier {
    let enabled: Bool
    let action: (CGPoint) -> Void

    func body(content: Content) -> some View {
        if enabled {
            // `onTapGesture(coordinateSpace:)`, NICHT `SpatialTapGesture` in
            // `.gesture` — Letzterer feuert in dieser Verschachtelung
            // (List-Zelle mit gehobenem `contextMenu`, horizontale
            // ScrollView) schlicht nicht (nachgemessen: kein einziger
            // Treffer). Der Tap-Erkenner hier ist derselbe Mechanismus, den
            // vorher jede Zelle einzeln trug.
            content.onTapGesture(coordinateSpace: .local) { action($0) }
        } else {
            content
        }
    }
}
