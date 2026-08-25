import WidgetKit
import SwiftUI
import AppIntents

/// Die Haupt-Widget-Oberfläche: EIN Habit mit Serie, heutigem Zustand,
/// Raster und Abhak-Knopf. Klein und mittel.
///
/// Drei Dinge, die sie mit der Karte in der App teilt — und teilen MUSS,
/// sonst behauptet der Homescreen etwas anderes als die Liste:
///
///  * **Farbe**: aufgelöst über `PaletteStyle.resolve` — Habit-eigene Farbe
///    schlägt globale, eigene Paletten des Nutzers eingeschlossen.
///  * **Termine**: ein Habit, der heute gar nicht dran ist, sagt nicht
///    „Heute noch offen", sondern wann er wieder dran ist. Abhaken bleibt
///    trotzdem möglich — Mehrleistung wird nie bestraft (siehe GoalEngine).
///  * **Idempotenz**: der Knopf hakt nur AN, nie ab.
///
/// Bewusst zweigeteilt: `body` liest Familie und Schema aus der Umgebung (so
/// arbeitet WidgetKit), `content(family:dark:)` nimmt beides als Argument.
/// Nur dadurch lassen sich alle Größen außerhalb eines Widget-Prozesses
/// zeichnen und prüfen — `\.widgetFamily` ist von außen nicht setzbar, und
/// eine Umgebung, die erst UM diese View gelegt wird, kommt in einer Methode,
/// die den Baum schon gebaut hat, nicht mehr an (dieselbe Lektion wie bei der
/// Teilen-Karte: das Schema muss durchgereicht, nicht gelesen werden).
struct HaiityWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var mode
    let entry: HaiityEntry

    /// Akzente folgen der GLOBALEN Farbe (wie die Knöpfe in der App); nur das
    /// Raster nimmt die Habit-eigene.
    private var palette: PaletteStyle { entry.palettes.style }
    private var today: String {
        guard let habit = entry.habit else { return DayKey.today() }
        return entry.today(for: habit)
    }

    private var calendar: Calendar {
        guard let habit = entry.habit else { return .current }
        return entry.calendar(for: habit)
    }

    var body: some View {
        content(family: family, dark: scheme == .dark, mode: mode)
            .containerBackground(for: .widget) {
                HomeWidgetBackground(palette: entry.palettes.style(for: entry.habit),
                                     dark: scheme == .dark,
                                     mode: mode)
            }
    }

    @ViewBuilder
    func content(family: WidgetFamily,
                 dark: Bool,
                 mode: WidgetRenderingMode = .fullColor) -> some View {
        if let habit = entry.habit {
            if habit.isReminder {
                reminderContent(habit, family: family, dark: dark)
            } else {
                switch family {
                case .systemMedium: medium(habit, dark: dark, mode: mode)
                default: small(habit, dark: dark, mode: mode)
                }
            }
        } else {
            WidgetEmptyState()
        }
    }

    /// Reminders are to-dos, not tracked habits: no streak, no graph and no
    /// habit-kind affordance in the widget.
    private func reminderContent(_ habit: Habit,
                                 family: WidgetFamily,
                                 dark: Bool) -> some View {
        let summary = WidgetLogic.summary(habit: habit, today: today, calendar: calendar)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Link(destination: HaiityWidgetLink.habit(habit.id)) {
                    nameRun(habit, font: family == .systemMedium
                            ? .headline : .subheadline.weight(.semibold))
                }
                Spacer(minLength: 4)
                checkButton(habit, dark: dark)
            }
            Spacer(minLength: 0)
            Link(destination: HaiityWidgetLink.habit(habit.id)) {
                metricLine(summary,
                           palette: entry.palettes.style(for: habit),
                           dark: dark)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: – Klein

    private func small(_ habit: Habit,
                       dark: Bool,
                       mode: WidgetRenderingMode) -> some View {
        let summary = WidgetLogic.summary(habit: habit, today: today, calendar: calendar)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Link(destination: HaiityWidgetLink.habit(habit.id)) {
                    nameRun(habit, font: .subheadline.weight(.semibold))
                }
                Spacer(minLength: 4)
                checkButton(habit, dark: dark)
            }
            Link(destination: HaiityWidgetLink.habit(habit.id)) {
                VStack(alignment: .leading, spacing: 5) {
                    streakRun(habit)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.primary)
                    metricLine(summary,
                               palette: entry.palettes.style(for: habit),
                               dark: dark)
                    grid(habit, dark: dark, mode: mode)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .bottomLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: – Mittel

    private func medium(_ habit: Habit,
                        dark: Bool,
                        mode: WidgetRenderingMode) -> some View {
        let summary = WidgetLogic.summary(habit: habit, today: today, calendar: calendar)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Theme.Metrics.gap) {
                Link(destination: HaiityWidgetLink.habit(habit.id)) {
                    nameRun(habit, font: .headline)
                }
                Spacer(minLength: Theme.Metrics.gap)
                Link(destination: HaiityWidgetLink.habit(habit.id)) {
                    streakRun(habit)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                checkButton(habit, dark: dark)
            }
            Link(destination: HaiityWidgetLink.habit(habit.id)) {
                VStack(alignment: .leading, spacing: 6) {
                    metricLine(summary,
                               palette: entry.palettes.style(for: habit),
                               dark: dark)
                    grid(habit, dark: dark, mode: mode)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .bottomLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: – Bausteine

    /// Emoji und Name als eine Zeile auf DERSELBEN Schriftgrundlinie — wie im
    /// Kopf der Karte.
    private func nameRun(_ habit: Habit, font: Font) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if !habit.emoji.isEmpty { Text(verbatim: habit.emoji).font(font) }
            Text(verbatim: habit.name)
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// Symbol und Zahl als EIN Textlauf — so sitzt das Glyph auf der
    /// Grundlinie der Ziffern statt auf der Mitte seines Kastens (App-Regel).
    private func streakRun(_ habit: Habit) -> Text {
        Text(Image(systemName: "flame.fill"))
            + Text(verbatim: " \(habit.streak(today: today, calendar: calendar))")
    }

    private func metricLine(_ summary: WidgetItemSummary,
                            palette: PaletteStyle,
                            dark: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: summary.metricSymbol)
            Text(verbatim: summary.metricText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(statusTint(summary.status, palette: palette, dark: dark))
    }

    private func statusTint(_ status: WidgetStatus,
                            palette: PaletteStyle,
                            dark: Bool) -> AnyShapeStyle {
        switch status {
        case .done:
            return AnyShapeStyle(Theme.accentText(palette))
        case .declined:
            return AnyShapeStyle(Theme.color(palette.negative(dark: dark)))
        case .open, .free:
            return AnyShapeStyle(HierarchicalShapeStyle.secondary)
        }
    }

    /// Abhak-Knopf: Checkbox-Habits zeigen ✓ (gefüllt, wenn der Tag zählt)
    /// und sind nur offen tippbar — der Intent ent-hakt nie. Mengen-Habits
    /// zeigen n/Ziel und zählen bei jedem Tipp weiter, auch über das Ziel
    /// hinaus. Ja/Nein-Habits zeigen ihre Antwort (✓ / ✗ / leerer Kreis) und
    /// setzen auf Tipp JA — auch über ein bestehendes Nein hinweg, denn der
    /// Homescreen hat für zwei Knöpfe keinen Platz und der eine, der da ist,
    /// heißt „abhaken". Auch an einem terminfreien Tag bedienbar: der Bonus
    /// zählt.
    private func checkButton(_ habit: Habit, dark: Bool) -> some View {
        let done = GoalEngine.dayCounts(habit: habit, day: today, calendar: calendar)
        let declined = habit.isDeclined(today)
        return HStack(spacing: 5) {
            if habit.kind == .yesNo, habit.isTrackedHabit {
                Button(intent: AnswerYesHabitIntent(habit: habit)) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.accentText(palette))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Mit Ja beantworten"))

                Button(intent: AnswerNoHabitIntent(habit: habit)) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.color(entry.palettes.style(for: habit)
                            .negative(dark: dark)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Mit Nein beantworten"))
            } else {
                Button(intent: CheckOffHabitIntent(habit: habit)) {
                    if habit.kind == .quantity, let target = habit.recurrence.target {
                        Text(verbatim: "\(habit.log[today] ?? 0)/\(target)")
                            .font(.caption2.bold().monospacedDigit())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(done ? Theme.accentFill(palette) : Color(.tertiarySystemFill),
                                        in: Capsule())
                            .foregroundStyle(done ? .white : .primary)
                    } else {
                        Image(systemName: declined
                              ? "xmark.circle.fill"
                              : (done ? "checkmark.circle.fill" : "circle"))
                            .font(.title3)
                            .foregroundStyle(negativeOrAccent(declined: declined,
                                                               done: done,
                                                               dark: dark))
                    }
                }
                .buttonStyle(.plain)
                .disabled(habit.kind != .quantity && done)
                .accessibilityLabel(habit.isReminder
                                    ? String(localized: "Erinnerung erledigen")
                                    : String(localized: "Habit abhaken"))
            }

            if entry.widgetResetEnabled {
                Button(intent: ResetHabitIntent(habit: habit)) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Rückgängig"))
            }
        }
    }

    /// Verneint zeichnet in der Verneinungsfarbe DIESES Habits — dieselbe,
    /// die im Raster darunter steht; sonst hieße dasselbe Nein oben rot und
    /// unten anders.
    private func negativeOrAccent(declined: Bool, done: Bool, dark: Bool) -> AnyShapeStyle {
        if declined {
            let cellPalette = entry.palettes.style(for: entry.habit)
            return AnyShapeStyle(Theme.color(cellPalette.negative(dark: dark)))
        }
        return done
            ? AnyShapeStyle(Theme.accentText(palette))
            : AnyShapeStyle(HierarchicalShapeStyle.tertiary)
    }

    /// Dasselbe Raster wie in der App, nur kleiner — Habit-eigene Farbe
    /// schlägt die globale (dieselbe Regel, dieselbe Funktion).
    private func grid(_ habit: Habit,
                      dark: Bool,
                      mode: WidgetRenderingMode) -> some View {
        let cellPalette = entry.palettes.style(for: habit)
        return TrailingGrid(habit: habit, today: today) { level in
            HomeWidgetInk.level(level, mode: mode, dark: dark, palette: cellPalette)
        }
    }
}
