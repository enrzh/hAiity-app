import SwiftUI
import UIKit

/// Das Herzstück: 53 Wochen × 7 Tage, Sonntag oben, Monatsmarken darüber,
/// scrollt zu heute. Zukunft ist gedimmt und tot.
///
/// The grid is display-only. Editing past days is deliberately available only
/// through the card's long-press menu, where the Nacharbeiten action is named
/// explicitly instead of making every tiny cell an accidental navigation
/// target.
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
/// sichtbaren Raster mit, weil die frisch gebauten Werte für SwiftUI nie
/// gleich aussehen.
struct ContributionGrid: View, Equatable {
    static func == (a: ContributionGrid, b: ContributionGrid) -> Bool {
        a.habit == b.habit
            && a.weeks == b.weeks
            && a.cellSize == b.cellSize
            && a.gap == b.gap
            && a.interactive == b.interactive
            && a.showsMonthLabels == b.showsMonthLabels
            && a.calendar.timeZone.identifier == b.calendar.timeZone.identifier
    }

    let habit: Habit
    var weeks: Int = 53
    /// nil = adaptiv (aus der verfügbaren Breite); gesetzt = feste Größe
    /// (Teilen-Karte, Vorschauen).
    var cellSize: CGFloat?
    var gap: CGFloat?
    var interactive: Bool = true
    var showsMonthLabels: Bool = true
    var calendar: Calendar = .current
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearancePreferences) private var appearancePreferences
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
    private static let referencePitch: CGFloat = GridCell.size + GridCell.gap

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
        let snapshot = GridCalendar.snapshot(habit: habit,
                                             weeks: weeks,
                                             today: DayKey.today(calendar: calendar),
                                             calendar: calendar)
        let contentWidth = CGFloat(weeks) * pitch - m.gap
        Group {
            if interactive {
                ScrollView(.horizontal, showsIndicators: false) {
                    graphContent(snapshot: snapshot,
                                 cell: m.cell,
                                 gap: m.gap,
                                 width: contentWidth)
                }
                .softScrollEdges()
                // Startet AN der rechten Kante — heute — statt nach dem
                // Aufbau dorthin zu scrollen.
                .defaultScrollAnchor(.trailing)
                // Recent habits use a viewport-sized history window. Disable
                // the gesture once layout confirms there is no extra content.
                .scrollDisabled(available > 0
                                && !GridCalendar.needsHorizontalScroll(
                                    contentWidth: contentWidth,
                                    viewportWidth: available))
            } else {
                // Context-menu previews must not contain a disabled
                // ScrollView. UIKit can preserve its trailing content offset
                // while relaying out the lifted preview, clipping the left
                // half of an otherwise correctly sized graph.
                graphContent(snapshot: snapshot,
                             cell: m.cell,
                             gap: m.gap,
                             width: contentWidth)
            }
        }
        .background(widthReader)
        // Der Abhak-Puls: ändert sich HEUTE, springt ein Ring um die
        // Heute-Zelle kurz auf — die eine Stelle, an der sich ein Check-in
        // im Raster zeigt, bekommt die eine kleine Bewegung. Bei „Bewegung
        // reduzieren" bleibt nur der Farbwechsel der Zelle.
        .onChange(of: habit.log[DayKey.today(calendar: calendar)]) { oldValue, newValue in
            guard interactive, !reduceMotion,
                  (newValue ?? 0) > (oldValue ?? 0),
                  !habit.isDeclined(DayKey.today(calendar: calendar)) else { return }
            checkPulse = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55).delay(0.02)) {
                checkPulse = false
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { checkPulse = false }
        }
        // Chronologie wird nie gespiegelt — auch nicht in ar/ur.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary(filled: snapshot.filledCount))
        .accessibilityIdentifier("contribution-grid")
    }

    @ViewBuilder
    private func graphContent(snapshot: GridCalendar.Snapshot,
                              cell: CGFloat,
                              gap: CGFloat,
                              width: CGFloat) -> some View {
        let style = Theme.adaptivePalette(palettes.style(for: habit),
                                          preferences: appearancePreferences,
                                          dark: scheme == .dark)
        VStack(alignment: .leading, spacing: 4) {
            ContributionGridRenderer(snapshot: snapshot,
                                     cell: cell,
                                     gap: gap,
                                     width: width,
                                     showsMonthLabels: showsMonthLabels,
                                     labelScale: labelScale / 100,
                                     palette: style,
                                     highlightsToday: true,
                                     checkPulse: checkPulse)
            if showsMonthLabels {
                ContributionChartLegend(palette: style)
                    .padding(.trailing, 2)
            }
        }
    }

    /// Läuft der Abhak-Puls gerade? (Ring um die Heute-Zelle, kurz.)
    @State private var checkPulse = false

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

private struct GridWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
