import WidgetKit
import SwiftUI

/// Sperrbildschirm-Widgets (iOS 16+).
///
/// **Die eine Regel hier: nichts darf farbabhängig lesbar sein.** WidgetKit
/// zeichnet diese Familien nicht in Farbe:
///
///  * `.vibrant` — der Sperrbildschirm. Der Inhalt wird nach HELLIGKEIT in ein
///    weißes Vibrancy-Material umgerechnet; jede Farbe fällt weg. Zwei
///    Palettenstufen mit ähnlicher Helligkeit wären danach dieselbe Fläche.
///  * `.accented` — getönte Darstellung. Alles landet in einer von zwei
///    Gruppen (Akzent / Standard, gesteuert über `.widgetAccentable()`) und
///    wird eingefärbt; die eigene Farbe wird verworfen.
///  * `.fullColor` — nur dort spricht die Palette.
///
/// Deshalb zeichnen diese Ansichten Ringe und Zellen als DECKKRAFTSTUFEN auf
/// `.primary` (siehe `WidgetInk`) und die Palette nur, wenn sie darf. Wie in
/// den übrigen Widgets nimmt `content(mode:)` den Modus als ARGUMENT, damit
/// sich alle drei Modi außerhalb eines Widget-Prozesses zeichnen und prüfen
/// lassen.

// MARK: – Kreis: der Tagesring

/// accessoryCircular: erfüllte ÷ heute FÄLLIGE Habits als Ring. Ein Habit,
/// der heute keinen Termin hat, steht in keiner der beiden Zahlen — und ein
/// Tag ganz ohne Termin zeigt einen VOLLEN Ring, kein Versäumnis.
struct RingAccessoryView: View {
    @Environment(\.widgetRenderingMode) private var mode
    let entry: HaiityEntry

    var body: some View {
        content(mode: mode)
            .widgetURL(HaiityWidgetLink.habits)
    }

    func content(mode: WidgetRenderingMode) -> some View {
        let progress = WidgetLogic.progress(
            habits: entry.habits,
            defaultTimeZoneIdentifier: entry.defaultTimeZoneIdentifier,
            now: entry.date)
        let width: CGFloat = 5
        return ZStack {
            AccessoryWidgetBackground()
            Circle()
                .stroke(track(mode), lineWidth: width)
                .padding(width / 2 + 1)
            if progress.fraction > 0 {
                Circle()
                    .trim(from: 0, to: progress.fraction)
                    .stroke(arc(mode), style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(width / 2 + 1)
                    .widgetAccentable()
            }
            label(progress)
                .foregroundStyle(WidgetInk.foreground(mode))
        }
        .containerBackground(for: .widget) { Color.clear }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.isFree
                            ? String(localized: "Heute ist nichts fällig")
                            : String(localized: "\(progress.met) von \(progress.due) heute erledigt"))
    }

    @ViewBuilder
    private func label(_ progress: WidgetLogic.DayProgress) -> some View {
        if progress.isFree {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 13, weight: .semibold))
        } else {
            Text(verbatim: "\(progress.met)/\(progress.due)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .padding(.horizontal, 2)
                .environment(\.layoutDirection, .leftToRight)
        }
    }

    /// In Farbe der Akzent, sonst WEISS — in `.accented` tönt das System den
    /// Bogen ohnehin selbst (er steckt in der Akzentgruppe), in `.vibrant`
    /// zählt nur die Helligkeit, und dunkel hieße dort durchsichtig.
    private func arc(_ mode: WidgetRenderingMode) -> AnyShapeStyle {
        mode == .fullColor
            ? AnyShapeStyle(Theme.accentText(entry.palettes.style))
            : AnyShapeStyle(Color.white)
    }

    /// Die leere Bahn dahinter: sichtbar, aber leise — dieselbe Rolle wie
    /// die l0-Stufe im Raster.
    private func track(_ mode: WidgetRenderingMode) -> AnyShapeStyle {
        mode == .fullColor
            ? AnyShapeStyle(HierarchicalShapeStyle.tertiary)
            : AnyShapeStyle(Color.white.opacity(0.3))
    }
}

// MARK: – Rechteck: Identität und Status oder Habit-Historie

/// Reminders show their occurrence state; only tracked habits have history.
struct StreakAccessoryView: View {
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.colorScheme) private var scheme
    let entry: HaiityEntry

    var body: some View {
        content(mode: mode, dark: scheme == .dark)
            .widgetURL(HaiityWidgetLink.habits)
    }

    /// Modus UND Schema als Argument — siehe `HaiityWidgetView`.
    @ViewBuilder
    func content(mode: WidgetRenderingMode, dark: Bool) -> some View {
        if let habit = entry.habit {
            let today = entry.today(for: habit)
            let calendar = entry.calendar(for: habit)
            let palette = entry.palettes.style(for: habit)
            let summary = WidgetLogic.summary(habit: habit, today: today,
                                              calendar: calendar, now: entry.date)
            Group {
                if habit.isReminder {
                    VStack(alignment: .leading, spacing: 4) {
                        WidgetItemIdentity(habit: habit, entry: entry, compact: true)
                            .widgetAccentable()
                        WidgetItemStatus(summary: summary, palette: palette, dark: dark, mode: mode)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "\(habit.name), \(summary.metricText)"))
                } else {
                    let streak = habit.streak(today: today, calendar: calendar)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            WidgetItemIdentity(habit: habit, entry: entry, compact: true)
                                .widgetAccentable()
                            Label {
                                Text(verbatim: String(streak))
                            } icon: {
                                Image(systemName: "flame.fill")
                            }
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        TrailingGrid(habit: habit, today: today, radius: 1,
                                     calendar: entry.calendar(for: habit)) { level in
                            WidgetInk.level(level, mode: mode, dark: dark, palette: palette)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "\(habit.name), Serie \(streak) Tage"))
                    .accessibilityValue(summary.metricText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(WidgetInk.foreground(mode))
            .containerBackground(for: .widget) { Color.clear }
            .privacySensitive()
        } else {
            Text(verbatim: "hAiity")
                .font(.headline)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .containerBackground(for: .widget) { Color.clear }
        }
    }
}

// MARK: – Zeile: neben der Uhr

/// accessoryInline: eine Zeile mit Symbol. Das System setzt Schrift und
/// Farbe selbst — hier gibt es nur Symbol und Text, sonst nichts.
struct InlineAccessoryView: View {
    @Environment(\.widgetRenderingMode) private var mode
    let entry: HaiityEntry

    var body: some View {
        content(mode: mode)
            .widgetURL(HaiityWidgetLink.habits)
    }

    /// Die Farbe setzt bei `accessoryInline` das System (es übernimmt den
    /// Stil der Uhr daneben und ignoriert eigene Angaben). Der helle
    /// Vordergrund steht trotzdem hier: er kostet auf dem Gerät nichts und
    /// hält die Rendering-Prüfung ehrlich — sonst zeigte sie schwarze
    /// Schrift auf einem Sperrbildschirm, den es so nie gibt.
    @ViewBuilder
    func content(mode: WidgetRenderingMode) -> some View {
        if let habit = entry.habit {
            let today = entry.today(for: habit)
            let calendar = entry.calendar(for: habit)
            let summary = WidgetLogic.summary(habit: habit, today: today,
                                              calendar: calendar, now: entry.date)
            Label {
                Text(verbatim: inlineText(habit,
                                          summary: summary,
                                          today: today,
                                          calendar: calendar))
            } icon: {
                Image(systemName: summary.metricSymbol)
            }
            .foregroundStyle(WidgetInk.foreground(mode))
            .privacySensitive()
        } else {
            Text(verbatim: "hAiity")
        }
    }

    /// Reminders keep their occurrence status; a completed habit shows its streak.
    private func inlineText(_ habit: Habit,
                            summary: WidgetItemSummary,
                            today: String,
                            calendar: Calendar) -> String {
        if habit.isReminder {
            return "\(habit.name): \(summary.metricText)"
        }
        switch summary.status {
        case .done:
            return String(localized: "\(habit.name): Serie \(habit.streak(today: today, calendar: calendar))")
        case .open:
            return String(localized: "\(habit.name): heute offen")
        case .declined:
            return String(localized: "\(habit.name): heute Nein")
        case .free(nil):
            return String(localized: "\(habit.name): keine Termine mehr")
        case .free(let weekday?):
            return String(localized: "\(habit.name): frei bis \(RecurrenceText.shortWeekdayName(weekday, calendar: calendar))")
        }
    }

}
