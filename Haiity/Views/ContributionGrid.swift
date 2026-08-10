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

        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    if showsMonthLabels {
                        monthRow(marks, width: contentWidth)
                    }
                    HStack(alignment: .top, spacing: m.gap) {
                        ForEach(Array(snapshot.keys.enumerated()), id: \.offset) { wi, column in
                            VStack(spacing: m.gap) {
                                ForEach(0..<GridCalendar.rows, id: \.self) { r in
                                    cell(key: column[r],
                                         level: snapshot.levels[wi][r],
                                         today: snapshot.today,
                                         size: m.cell)
                                }
                            }
                            .id(wi)
                        }
                    }
                    // EIN Tipp-Erkenner für alle 371 Zellen statt einer je
                    // Zelle. Der Unterschied ist gemessen, nicht geraten:
                    // jede Zelle mit eigenem `onTapGesture` bringt ihren
                    // eigenen UIKit-Erkenner mit, und der Aufbau eines
                    // Rasters beim Hereinscrollen einer Karte kostete damit
                    // sichtbar Bilder. Getroffen wird über die Geometrie —
                    // dieselbe Rechnung, aus der die Zellen gezeichnet
                    // werden — und die Tippbarkeits-Regel bleibt Zeichen für
                    // Zeichen `GridCalendar.isTappable`.
                    .contentShape(Rectangle())
                    .modifier(GridTap(enabled: interactive && onSelectDay != nil) { location in
                        guard let key = GridCalendar.hitKey(location: location,
                                                            keys: snapshot.keys,
                                                            cell: m.cell,
                                                            gap: m.gap),
                              GridCalendar.isTappable(key: key,
                                                      interactive: interactive,
                                                      today: snapshot.today) else { return }
                        // Auswahl-Haptik, nicht die des Abhakens: hier wird
                        // nichts bestätigt, hier wird etwas ausgewählt.
                        Theme.Haptics.select()
                        onSelectDay?(key)
                    })
                }
                .padding(.vertical, 2)
            }
            .background(widthReader)
            .onAppear { scrollToToday(proxy) }
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

    @ViewBuilder
    private func cell(key: String?, level: Int, today: String, size: CGFloat) -> some View {
        GridCell(color: Theme.level(level,
                                    dark: scheme == .dark,
                                    palette: palettes.style(for: habit)),
                 size: size)
            // Zukunft: gedimmt und ohne Tipp-Wirkung (siehe isTappable im
            // gemeinsamen Erkenner). Die Regel bleibt Zeichen für Zeichen
            // dieselbe wie früher — geändert hat sich nur, WO sie geprüft
            // wird.
            .opacity(key == nil ? 0.35 : 1)
            .overlay {
                if key == today {
                    RoundedRectangle(cornerRadius: GridCell.radius, style: .continuous)
                        .strokeBorder(.primary, lineWidth: 1.2)
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

    private func scrollToToday(_ proxy: ScrollViewProxy) {
        guard weeks > 0 else { return }
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { proxy.scrollTo(weeks - 1, anchor: .trailing) }
        } else {
            proxy.scrollTo(weeks - 1, anchor: .trailing)
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
