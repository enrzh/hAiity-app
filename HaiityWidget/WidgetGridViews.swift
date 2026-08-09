import WidgetKit
import SwiftUI

/// Gemeinsame Rasterbausteine für ALLE Widgets. Sie zeichnen dieselben Zellen
/// wie die App (gleiche Stufen, gleiche gedimmte Zukunft, gleiche erzwungene
/// Leserichtung) — nur die Größe und die Farbabbildung kommen von außen.
///
/// Die Farbe kommt bewusst als Funktion herein und nicht als Palette: auf dem
/// Sperrbildschirm gibt es keine Farbe, dort zeichnet dasselbe Bauteil
/// Deckkraftstufen (siehe `WidgetInk`).

/// EIN Band: `count` Spalten × 7 Zeilen, älteste links.
struct GridBand: View {
    let snapshot: GridCalendar.Snapshot
    /// Erste Spalte dieses Bands in der GEPOLSTERTEN Folge.
    let start: Int
    let count: Int
    /// Leerspalten vor der ältesten Woche (nur beim gewickelten Jahr > 0).
    let pad: Int
    let cell: CGFloat
    let gap: CGFloat
    var radius: CGFloat = 1.5
    let level: (Int) -> Color

    var body: some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(Array(start..<(start + max(0, count))), id: \.self) { column in
                VStack(spacing: gap) {
                    ForEach(0..<GridCalendar.rows, id: \.self) { row in
                        square(column: column - pad, row: row)
                    }
                }
            }
        }
    }

    /// Keine Force-Unwraps und keine ungeprüften Indizes: ein Widget, das beim
    /// Zeichnen abstürzt, zeigt dem Nutzer nur noch ein graues Rechteck.
    @ViewBuilder
    private func square(column: Int, row: Int) -> some View {
        if column >= 0, column < snapshot.keys.count, row < GridCalendar.rows {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(level(snapshot.levels[column][row]))
                // Zukunft gedimmt — wie im Raster der App.
                .opacity(snapshot.keys[column][row] == nil ? 0.35 : 1)
                .frame(width: cell, height: cell)
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }
}

/// Die LETZTEN Wochen, so viele wie lesbar in die Fläche passen.
///
/// `maxBands` = 1 (Standard) ist der Streifen neben Text; mehr erlaubt dem
/// reinen Graphen, auf einer hohen Fläche zu wickeln.
struct TrailingGrid: View {
    let habit: Habit
    var maxWeeks: Int = 53
    var maxBands: Int = 1
    var today: String = DayKey.today()
    var radius: CGFloat = 1.5
    let level: (Int) -> Color

    var body: some View {
        GeometryReader { geo in
            let layout = GraphLayout.trailing(width: geo.size.width,
                                              height: geo.size.height,
                                              maxWeeks: maxWeeks,
                                              maxBands: maxBands)
            BandedGrid(habit: habit, layout: layout, today: today,
                       radius: radius, level: level)
                .frame(width: geo.size.width, height: geo.size.height,
                       alignment: layout.bands > 1 ? .center : .topLeading)
        }
        // Chronologie nie spiegeln — wie im Contribution-Grid der App.
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// Ein fertiges Layout zeichnen: ein Band oder mehrere untereinander.
/// Liest sich wie ein Text — links→rechts, Band für Band nach unten; unten
/// rechts steht heute.
struct BandedGrid: View {
    let habit: Habit
    let layout: GraphLayout.Layout
    var today: String = DayKey.today()
    var radius: CGFloat = 1.5
    let level: (Int) -> Color

    var body: some View {
        let snapshot = GridCalendar.snapshot(habit: habit, weeks: layout.weeks, today: today)
        // Genau eine Zellhöhe Luft zwischen den Bändern — weniger, und sie
        // laufen zu einer Fläche zusammen.
        return VStack(spacing: layout.pitch) {
            ForEach(0..<max(1, layout.bands), id: \.self) { band in
                GridBand(snapshot: snapshot,
                         start: band * layout.perBand,
                         count: layout.perBand,
                         pad: layout.pad,
                         cell: layout.cell, gap: layout.gap,
                         radius: radius, level: level)
            }
        }
    }
}

/// Das GANZE Jahr, in Bänder gewickelt, mittig in der Fläche.
struct YearGrid: View {
    let habit: Habit
    var weeks: Int = 53
    var today: String = DayKey.today()
    var radius: CGFloat = 1.5
    let level: (Int) -> Color

    var body: some View {
        GeometryReader { geo in
            BandedGrid(habit: habit,
                       layout: GraphLayout.year(width: geo.size.width,
                                                height: geo.size.height,
                                                weeks: weeks),
                       today: today, radius: radius, level: level)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: – Farbe vs. Deckkraft

/// Wie eine Rasterstufe zu einer Farbe wird.
///
/// Auf dem Homescreen ist das die Palette. Auf dem SPERRBILDSCHIRM gibt es
/// keine: dort rendert WidgetKit in `.vibrant` (Helligkeit → Deckkraft eines
/// hellen Materials) oder `.accented` (alles wird auf zwei Gruppen
/// eingedampft und getönt). Eine Palette würde dort zu Matsch — fünf Stufen,
/// die nach der Umrechnung fast gleich hell sind. Deshalb zeichnet der
/// Sperrbildschirm dieselben Zellen als DECKKRAFTSTUFEN.
///
/// **Und zwar auf WEISS, nicht auf `.primary`.** Das ist der Unterschied
/// zwischen „sieht in der Vorschau gut aus" und „ist auf dem Gerät da":
/// `.primary` ist in einem hellen Farbschema SCHWARZ, und `.vibrant` rechnet
/// dunkle Bereiche in Transparenz um — ein Raster aus schwarzen Zellen wäre
/// auf dem Sperrbildschirm unsichtbar. Die Rendering-Prüfung hat genau das
/// gezeigt. Weiß ist in beiden Modi richtig: in `.vibrant` maximal deckend,
/// in `.accented` ersetzt das System die Farbe ohnehin durch den Farbton.
enum WidgetInk {
    /// Die fünf Deckkraftstufen. Sie sind STRENG steigend und liegen weit
    /// genug auseinander, dass sie auch nach der Helligkeits-Umrechnung des
    /// Sperrbildschirms noch fünf Stufen sind — das ist die einzige
    /// Eigenschaft, auf die es hier ankommt, und genau die prüft der Test.
    static let opacities: [Double] = [0.13, 0.33, 0.55, 0.78, 1.0]

    /// Kleinster erlaubter Abstand zwischen zwei Stufen.
    static let minimumStep = 0.15

    static func opacity(_ level: Int) -> Double {
        opacities[max(0, min(opacities.count - 1, level))]
    }

    /// Stufe 0…4 ohne Farbe.
    static func mono(_ level: Int) -> Color {
        Color.white.opacity(opacity(level))
    }

    /// Die richtige Abbildung für den Rendermodus: nur in `.fullColor` darf
    /// die Palette sprechen.
    static func level(_ level: Int,
                      mode: WidgetRenderingMode,
                      dark: Bool,
                      palette: PaletteStyle) -> Color {
        mode == .fullColor ? Theme.level(level, dark: dark, palette: palette) : mono(level)
    }

    /// Vordergrund für Text und Symbole auf dem Sperrbildschirm — aus
    /// demselben Grund weiß wie die Zellen.
    static func foreground(_ mode: WidgetRenderingMode) -> AnyShapeStyle {
        mode == .fullColor
            ? AnyShapeStyle(HierarchicalShapeStyle.primary)
            : AnyShapeStyle(Color.white)
    }
}

/// Was das Steuerungselement im Kontrollzentrum zeigt.
///
/// Eigenes Bauteil, obwohl es nur ein `Label` ist: das Kontrollzentrum lässt
/// sich nicht fernsteuern, und so zeichnet die Rendering-Prüfung GENAU den
/// Inhalt, der dort steht — statt einer nachgebauten Näherung, die beim
/// nächsten Anfassen auseinanderläuft.
struct HabitControlLabel: View {
    let name: String
    let emoji: String
    let done: Bool

    var body: some View {
        Label {
            Text(verbatim: emoji.isEmpty ? name : "\(emoji) \(name)")
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
        }
    }
}

/// „Noch keine Habits" — EIN Bauteil für alle Größen, damit ein leerer Store
/// überall gleich aussieht und nie ein kaputtes Layout zeigt.
struct WidgetEmptyState: View {
    var compact: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "square.grid.3x3")
                .font(compact ? .body : .title3)
                .foregroundStyle(.tertiary)
            Text(verbatim: "hAiity").font(compact ? .caption2.bold() : .caption.bold())
            if !compact {
                Text(String(localized: "Noch keine Habits"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
