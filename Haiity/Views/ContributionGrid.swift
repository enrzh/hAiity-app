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
            && a.calendar == b.calendar
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
    /// A cold graph must not make the first habit-list frame wait on date
    /// generation and intensity calculation.
    @State private var renderedSnapshot: (key: GridCalendar.HabitSnapshotKey, value: GridCalendar.Snapshot)?
    @State private var viewportWidth: CGFloat = 0
    /// Referenzmaß 100, skaliert mit Dynamic Type: `labelScale / 100` ist
    /// exakt der Faktor, mit dem `.caption2` gerade wächst. Damit lässt sich
    /// die Labelbreite messen, ohne die Trait-Collection nachzubauen.
    @ScaledMetric(relativeTo: .caption2) private var labelScale: CGFloat = 100

    private var metrics: (cell: CGFloat, gap: CGFloat) {
        if let cellSize { return (cellSize, gap ?? GridCell.gap) }
        return (ContributionChart.fittedCell(viewport: viewportWidth,
                                            cell: GridCell.size, gap: GridCell.gap), GridCell.gap)
    }

    private func loadSnapshot(for request: GridCalendar.HabitSnapshotKey) async {
        if let cached = GridCalendar.cachedSnapshot(habit: habit,
                                                    weeks: request.weeks,
                                                    today: request.today,
                                                    calendar: request.calendar) {
            renderedSnapshot = (request, cached)
            return
        }
        let habit = habit
        let graphSignpost = StartupMetrics.begin("habitGraphCalculation")
        defer { StartupMetrics.end("habitGraphCalculation", id: graphSignpost) }
        guard let snapshot = await ContributionSnapshotScheduler.perform({
            GridCalendar.snapshot(habit: habit, weeks: request.weeks, today: request.today,
                                  calendar: request.calendar)
        }), !Task.isCancelled else { return }
        renderedSnapshot = (request, snapshot)
    }

    var body: some View {
        #if DEBUG
        let _ = FrameProbe.shared.mark("grid.body")
        #endif
        let m = metrics
        let today = DayKey.today(calendar: calendar)
        let request = GridCalendar.HabitSnapshotKey(habit: habit, weeks: weeks,
                                                    today: today, calendar: calendar)
        let snapshot = renderedSnapshot.flatMap {
            $0.key.canDisplaySnapshot(for: request) ? $0.value : nil
        }
        let pitch = m.cell + m.gap
        let contentWidth = CGFloat(weeks) * pitch - m.gap
        Group {
            if let snapshot {
                if interactive {
                    if GridCalendar.needsHorizontalScroll(
                        contentWidth: contentWidth + 8,
                        viewportWidth: viewportWidth) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            graphContent(snapshot: snapshot,
                                         cell: m.cell,
                                         gap: m.gap,
                                         width: contentWidth)
                        }
                        // Start at the trailing edge only when the graph actually
                        // overflows. Fitting graphs stay optically centered.
                        .defaultScrollAnchor(.trailing)
                        .padding(.horizontal, 4)
                    } else {
                        graphContent(snapshot: snapshot,
                                     cell: m.cell,
                                     gap: m.gap,
                                     width: contentWidth)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                } else {
                    graphContent(snapshot: snapshot,
                                 cell: m.cell,
                                 gap: m.gap,
                                 width: contentWidth)
                }
            } else if interactive {
                // A fixed-width placeholder needs the same viewport as the
                // loaded graph. Otherwise fitted cells can grow the row and
                // oscillate its measured width before the snapshot arrives.
                ScrollView(.horizontal, showsIndicators: false) {
                    loadingGraph(cell: m.cell, gap: m.gap, width: contentWidth)
                }
                .defaultScrollAnchor(.trailing)
                .padding(.horizontal, 4)
            } else {
                loadingGraph(cell: m.cell, gap: m.gap, width: contentWidth)
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            // Fractional layout noise must not feed fitted tile sizing back
            // into another layout pass, particularly on narrow screens.
            guard width > 0, abs(width - viewportWidth) > 0.5 else { return }
            viewportWidth = width
        }
        .task(id: request) {
            await loadSnapshot(for: request)
        }
        // Der Abhak-Puls: ändert sich HEUTE, springt ein Ring um die
        // Heute-Zelle kurz auf — die eine Stelle, an der sich ein Check-in
        // im Raster zeigt, bekommt die eine kleine Bewegung. Bei „Bewegung
        // reduzieren" bleibt nur der Farbwechsel der Zelle.
        .onChange(of: habit.log[today]) { oldValue, newValue in
            guard interactive, !reduceMotion,
                  (newValue ?? 0) > (oldValue ?? 0),
                  !habit.isDeclined(today) else { return }
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
        .accessibilityLabel(summary(filled: snapshot?.filledCount ?? 0, streak: snapshot?.streak ?? 0))
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
        ContributionChart(snapshot: snapshot,
                                 cell: cell,
                                 gap: gap,
                                 width: width,
                                 showsMonthLabels: showsMonthLabels,
                                 labelScale: labelScale / 100,
                                 palette: style,
                                 highlightsToday: true,
                                 checkPulse: checkPulse,
                                 showsSurface: interactive)
    }

    /// Läuft der Abhak-Puls gerade? (Ring um die Heute-Zelle, kurz.)
    @State private var checkPulse = false

    private func loadingGraph(cell: CGFloat, gap: CGFloat, width: CGFloat) -> some View {
        let tileHeight = CGFloat(GridCalendar.rows) * (cell + gap) - gap
        let surfaceInset = interactive ? appearancePreferences.designStyle.graphPadding * 2 : 0
        let labelHeight = showsMonthLabels ? 16 : 0
        return RoundedRectangle(cornerRadius: CornerRadius.chip, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .frame(width: max(width, 1),
                   height: tileHeight + CGFloat(surfaceInset) + CGFloat(labelHeight))
            .overlay { ProgressView().controlSize(.small) }
            .accessibilityLabel(String(localized: "Beitragskalender wird geladen"))
    }

    private func summary(filled: Int, streak: Int) -> String {
        String(localized: "\(habit.name): \(filled) Tage im letzten Jahr, aktuelle Serie \(streak).")
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
