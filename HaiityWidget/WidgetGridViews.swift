import WidgetKit
import SwiftUI

/// Gemeinsame Rasterbausteine für ALLE Widgets. Sie zeichnen dieselben Zellen
/// wie die App (gleiche Stufen, gleiche gedimmte Zukunft, gleiche erzwungene
/// Leserichtung) — nur die Größe und die Farbabbildung kommen von außen.
///
/// Die Farbe kommt bewusst als Funktion herein und nicht als Palette: auf dem
/// Sperrbildschirm gibt es keine Farbe, dort zeichnet dasselbe Bauteil
/// Deckkraftstufen (siehe `WidgetInk`).

/// EIN Band: `snapshot.weeks` Spalten × 7 Zeilen, älteste links, heute rechts.
struct GridBand: View {
    let snapshot: GridCalendar.Snapshot
    let cell: CGFloat
    let gap: CGFloat
    var radius: CGFloat = 1.5
    let level: (Int) -> Color

    var body: some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(0..<snapshot.keys.count, id: \.self) { column in
                VStack(spacing: gap) {
                    ForEach(0..<GridCalendar.rows, id: \.self) { row in
                        square(column: column, row: row)
                    }
                }
            }
        }
    }

    /// Keine Force-Unwraps und keine ungeprüften Indizes: ein Widget, das beim
    /// Zeichnen abstürzt, zeigt dem Nutzer nur noch ein graues Rechteck.
    @ViewBuilder
    private func square(column: Int, row: Int) -> some View {
        if column >= 0, column < snapshot.keys.count, row < snapshot.keys[column].count {
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

/// Die LETZTEN Wochen als EIN Band, das die Fläche ausfüllt.
///
/// Kein Wickeln: sieben Zeilen, links→rechts, heute in der letzten Spalte —
/// die Form, in der ein Contribution-Graph überhaupt lesbar ist (siehe
/// `GraphLayout`). Die Zelle kommt aus der HÖHE, die Wochenzahl aus der
/// Breite; der Streifen neben Text und der reine Graph rechnen also identisch
/// und unterscheiden sich nur durch die Fläche, die sie bekommen.
///
/// `radius = nil` heißt „aus der Zellgröße" — für den reinen Graphen, dessen
/// Zellen je nach Familie zwischen 17 und 40 pt liegen; ein fester 2-pt-Radius
/// wären dort scharfe Quadrate.
struct TrailingGrid: View {
    let habit: Habit
    var maxWeeks: Int = 53
    var today: String = DayKey.today()
    var radius: CGFloat? = 1.5
    /// Wohin das Band fällt, wenn nach der Rechnung ein Rest bleibt.
    var alignment: Alignment = .topLeading
    let level: (Int) -> Color

    var body: some View {
        GeometryReader { geo in
            let layout = GraphLayout.trailing(width: geo.size.width,
                                              height: geo.size.height,
                                              maxWeeks: maxWeeks)
            GridBand(snapshot: GridCalendar.snapshot(habit: habit,
                                                     weeks: layout.weeks,
                                                     today: today),
                     cell: layout.cell, gap: layout.gap,
                     radius: radius ?? layout.radius, level: level)
                .frame(width: geo.size.width, height: geo.size.height,
                       alignment: alignment)
        }
        // Chronologie nie spiegeln — wie im Contribution-Grid der App.
        .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: – Farbe vs. Deckkraft

/// Homescreen-Raster dürfen kräftiger als die App-Karte auftreten: auf dem
/// Foto sind Stufe 1 und 2 gegen den dunklen Widget-Hintergrund kaum sichtbar.
/// Leer und Nein behalten ihre Bedeutung; nur echte Beiträge rücken in den
/// leuchtenden Teil der Rampe. Sperrbildschirm-Widgets verwenden weiter
/// `WidgetInk`.
enum HomeWidgetInk {
    static let lightBackgroundOpacity = 0.08
    static let darkBackgroundOpacity = 0.16

    static func mappedLevel(_ level: Int) -> Int {
        if level == Habit.Answer.declinedLevel { return level }
        guard level > 0 else { return 0 }
        return min(4, level + 2)
    }

    static func level(_ level: Int, dark: Bool, palette: PaletteStyle) -> Color {
        Theme.level(mappedLevel(level), dark: dark, palette: palette)
    }

    /// The Home Screen can tint or make a widget vibrant when the user uses
    /// the translucent icon appearance. In those modes WidgetKit collapses
    /// arbitrary colors to one system treatment, so preserve the five data
    /// levels as opacity instead of letting every tile become white.
    static func level(_ value: Int,
                      mode: WidgetRenderingMode,
                      dark: Bool,
                      palette: PaletteStyle) -> Color {
        guard mode == .fullColor else { return WidgetInk.mono(value) }
        return level(value, dark: dark, palette: palette)
    }
}

/// Ein sehr leiser Paletten-Ton statt einer neutral schwarzen Fläche. Die
/// Deckkraft bleibt bewusst unter 20 %, damit Raster und Text den Kontrast
/// bestimmen und System-Tints weiterhin sauber greifen.
struct HomeWidgetBackground: View {
    let palette: PaletteStyle
    let dark: Bool
    let mode: WidgetRenderingMode

    var body: some View {
        if mode == .fullColor {
            ZStack {
                Color(.systemBackground)
                Theme.accent(palette)
                    .opacity(dark ? HomeWidgetInk.darkBackgroundOpacity
                                  : HomeWidgetInk.lightBackgroundOpacity)
            }
        } else {
            Color.clear
        }
    }
}

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

    /// Ein mit NEIN beantworteter Tag — auf dem Sperrbildschirm.
    ///
    /// **Hier ist die einzige Stelle der App, an der die Verneinung KEINE
    /// eigene Farbe bekommen kann**, und das ist keine Nachlässigkeit,
    /// sondern die Eigenschaft des Mediums: `.vibrant` und `.accented`
    /// rechnen alles auf EINE Achse herunter (Helligkeit), und die ist von
    /// den fünf Rasterstufen bereits vollständig belegt. Bleibt eine einzige
    /// freie Richtung: UNTER die leere Zelle. Ein verneinter Tag ist dort
    /// also dunkler als ein leerer — „schlechter als nichts", und das ist
    /// genau die Aussage. Die harte Zahl daneben (Serie) trägt den Rest.
    static let declinedOpacity = 0.05

    static func opacity(_ level: Int) -> Double {
        guard level != Habit.Answer.declinedLevel else { return declinedOpacity }
        return opacities[max(0, min(opacities.count - 1, level))]
    }

    /// Stufe 0…4 (und die Verneinung) ohne Farbe.
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
///
/// Nicht für den reinen Graphen: der zeigt NIE Schrift, auch nicht im
/// Leerfall, sondern ein leeres Raster (siehe `GraphWidgetView`).
struct WidgetEmptyState: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "square.grid.3x3")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text(verbatim: "hAiity").font(.caption.bold())
            Text(String(localized: "Noch keine Habits"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
