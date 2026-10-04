import WidgetKit
import SwiftUI

/// Nur der Graph. Keine Schrift, kein Knopf, kein Rahmen — EIN Band aus
/// sieben Zeilen, das die Fläche ausfüllt.
///
/// Genau die Form von GitHubs eigenem Widget, und das ist keine Nachahmung um
/// ihrer selbst willen: sieben Zeilen (So…Sa) mal N Spalten (je eine Woche)
/// sind die einzige Anordnung, in der ein Contribution-Graph seine Bedeutung
/// behält. Eine Zwischenzeit lang hat dieses Widget das Jahr in mehrere
/// Bänder gewickelt, um mehr Wochen unterzubringen; das sieht dicht aus, aber
/// eine Zeile heißt dann nicht mehr „Montag", eine Spalte nicht mehr „eine
/// Woche", und zwischen Bandende und Bandanfang steht ein unsichtbarer
/// Zeitsprung. Lieber weniger Wochen, die man lesen kann.
///
/// Die Zellgröße fällt aus der HÖHE (Höhe ÷ 7), die Wochenzahl aus der Breite
/// — deshalb zeigt eine fast quadratische Fläche wenige große Zellen und eine
/// breite viele. Die Rechnung steht in `GraphLayout` und wird dort geprüft.
struct GraphWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var mode
    let entry: HaiityEntry

    /// Kein Habit heißt: leeres Raster. Ein stabiler Wert (kein neuer je
    /// Zeichenvorgang), damit der Snapshot-Cache nicht bei jedem Aufbau
    /// überläuft.
    private static let blank = Habit(name: "")

    var body: some View {
        content(family: family, dark: scheme == .dark, mode: mode)
            .containerBackground(for: .widget) {
                HomeWidgetBackground(palette: entry.resolvedGraphPalette,
                                     dark: scheme == .dark,
                                     mode: mode,
                                     designStyle: entry.designStyle)
            }
    }

    /// Familie UND Schema als Argument — siehe `HaiityWidgetView`.
    @ViewBuilder
    func content(family: WidgetFamily,
                 dark: Bool,
                 mode: WidgetRenderingMode = .fullColor) -> some View {
        Group {
            if entry.graphSource == .github {
                GitHubWidgetGraph(content: WidgetLogic.gitHubWidgetContent(snapshot: entry.githubSnapshot,
                                                                           anchor: entry.date),
                                  palette: entry.resolvedGraphPalette,
                                  mode: mode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "GitHub-Beitragskalender"))
            } else {
                let habit = entry.habit
                let cellPalette = entry.resolvedGraphPalette
                let level: (Int) -> Color = {
                    HomeWidgetInk.level($0, mode: mode, dark: dark, palette: cellPalette)
                }
                // Ohne Habit dasselbe Raster, nur leer — dieses Widget zeigt NIE
                // Schrift, auch nicht „Noch keine Habits". Eine Fläche aus l0-Zellen
                // ist die ehrlichere Aussage: das ist der Graph, er ist bloß noch leer.
                let today = habit.map { entry.today(for: $0) }
                    ?? DayKey.key(for: entry.date, calendar: HabitTimeZone.calendar(identifier: entry.defaultTimeZoneIdentifier))
                Link(destination: HaiityWidgetLink.habits) {
                    TrailingGrid(habit: habit ?? Self.blank,
                                 today: today,
                                 radius: nil,
                                 calendar: habit.map { entry.calendar(for: $0) }
                                    ?? HabitTimeZone.calendar(identifier: entry.defaultTimeZoneIdentifier),
                                 alignment: .center,
                                 level: level)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(label(habit))
                }
            }
        }
        // The large family earns its larger tiles, with a restrained inset
        // that keeps the graph from touching the widget edge.
        .padding(family == .systemLarge ? WidgetLogic.LargeGeometry.outerPadding : 0)
    }

    private func label(_ habit: Habit?) -> String {
        guard let habit else { return String(localized: "Noch keine Habits") }
        return String(localized: "\(habit.name): \(habit.checkInCount()) Tage, aktuelle Serie \(habit.streak(today: entry.today(for: habit), calendar: entry.calendar(for: habit))).")
    }
}
