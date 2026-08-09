import WidgetKit
import SwiftUI

/// Nur der Graph. Keine Schrift, kein Knopf, kein Rahmen — die Zellen füllen
/// die Fläche.
///
/// Klein und mittel zeigen die LETZTEN Wochen — so viele, wie bei noch
/// lesbarer Zelle hineinpassen. Groß zeigt das GANZE Jahr, 53 Wochen.
///
/// Beide dürfen WICKELN, und das ist hier keine Spielerei, sondern Geometrie:
/// sieben Zeilen mal 53 Wochen sind 7,6-mal so breit wie hoch. In einer
/// quadratischen kleinen Fläche zeigt EIN Band sieben Wochen mit riesigen
/// Quadraten; zwei Bänder zeigen dreißig. In der großen Fläche wäre ein
/// einzelnes Jahresband ein 40-pt-Streifen in 350 pt Leere; in drei Bändern
/// sind die Zellen dreimal so groß. Die Chronologie bleibt in jedem Fall
/// (links→rechts, Band für Band nach unten), und heute steht unten rechts.
struct GraphWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let entry: HaiityEntry

    var body: some View {
        content(family: family, dark: scheme == .dark)
            .containerBackground(for: .widget) { Color(.systemBackground) }
            .widgetURL(URL(string: "haiity://open"))
    }

    /// Familie UND Schema als Argument — siehe `HaiityWidgetView`.
    @ViewBuilder
    func content(family: WidgetFamily, dark: Bool) -> some View {
        if let habit = entry.habit {
            let cellPalette = entry.palettes.style(for: habit)
            let level: (Int) -> Color = { Theme.level($0, dark: dark, palette: cellPalette) }
            Group {
                if family == .systemLarge {
                    YearGrid(habit: habit, radius: 2.5, level: level)
                } else {
                    // Darf wickeln: EIN Band zeigt auf einer kleinen,
                    // fast quadratischen Fläche nur sieben Wochen.
                    TrailingGrid(habit: habit, maxBands: 4, radius: 2, level: level)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary(habit))
        } else {
            WidgetEmptyState(compact: family == .systemSmall)
        }
    }

    private func summary(_ habit: Habit) -> String {
        String(localized: "\(habit.name): \(habit.checkInCount()) Tage, aktuelle Serie \(habit.streak()).")
    }
}
