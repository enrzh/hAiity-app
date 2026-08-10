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
    }

    func content(mode: WidgetRenderingMode) -> some View {
        let progress = WidgetLogic.progress(habits: entry.habits)
        let width: CGFloat = 5
        return ZStack {
            AccessoryWidgetBackground()
            Circle()
                .stroke(track(mode), lineWidth: width)
                .padding(width / 2 + 1)
            Circle()
                .trim(from: 0, to: max(0.02, progress.fraction))
                .stroke(arc(mode), style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(width / 2 + 1)
                .widgetAccentable()
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
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, 2)
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

// MARK: – Rechteck: Habit, Serie, Mini-Raster

/// accessoryRectangular: EIN Habit mit Serie und einem kleinen Raster.
struct StreakAccessoryView: View {
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.colorScheme) private var scheme
    let entry: HaiityEntry

    private var today: String { DayKey.today() }

    var body: some View {
        content(mode: mode, dark: scheme == .dark)
    }

    /// Modus UND Schema als Argument — siehe `HaiityWidgetView`.
    @ViewBuilder
    func content(mode: WidgetRenderingMode, dark: Bool) -> some View {
        if let habit = entry.habit {
            let palette = entry.palettes.style(for: habit)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if !habit.emoji.isEmpty { Text(verbatim: habit.emoji).font(.caption2) }
                    Text(verbatim: habit.name)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .widgetAccentable()
                    Spacer(minLength: 2)
                    (Text(Image(systemName: "flame.fill"))
                        + Text(verbatim: " \(habit.streak(today: today))"))
                        .font(.caption.monospacedDigit())
                }
                TrailingGrid(habit: habit, today: today, radius: 1) { level in
                    WidgetInk.level(level, mode: mode, dark: dark, palette: palette)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Ganze Zeile hell: `.primary` wäre in einem hellen Farbschema
            // schwarz und damit auf dem Sperrbildschirm durchsichtig.
            .foregroundStyle(WidgetInk.foreground(mode))
            .containerBackground(for: .widget) { Color.clear }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "\(habit.name), Serie \(habit.streak(today: today)) Tage"))
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

    var body: some View { content(mode: mode) }

    /// Die Farbe setzt bei `accessoryInline` das System (es übernimmt den
    /// Stil der Uhr daneben und ignoriert eigene Angaben). Der helle
    /// Vordergrund steht trotzdem hier: er kostet auf dem Gerät nichts und
    /// hält die Rendering-Prüfung ehrlich — sonst zeigte sie schwarze
    /// Schrift auf einem Sperrbildschirm, den es so nie gibt.
    @ViewBuilder
    func content(mode: WidgetRenderingMode) -> some View {
        if let habit = entry.habit {
            let status = WidgetLogic.status(habit: habit)
            Label {
                Text(verbatim: inlineText(habit, status: status))
            } icon: {
                Image(systemName: symbol(status))
            }
            .foregroundStyle(WidgetInk.foreground(mode))
        } else {
            Text(verbatim: "hAiity")
        }
    }

    /// Erledigt zeigt die Serie, offen zeigt „heute", frei zeigt den nächsten
    /// Termin — eine Zeile hat Platz für genau EINE Aussage.
    private func inlineText(_ habit: Habit, status: WidgetStatus) -> String {
        switch status {
        case .done:
            return String(localized: "\(habit.name): Serie \(habit.streak())")
        case .open:
            return String(localized: "\(habit.name): heute offen")
        case .declined:
            return String(localized: "\(habit.name): heute Nein")
        case .free(nil):
            return String(localized: "\(habit.name): keine Termine mehr")
        case .free(let weekday?):
            return String(localized: "\(habit.name): frei bis \(RecurrenceText.shortWeekdayName(weekday))")
        }
    }

    private func symbol(_ status: WidgetStatus) -> String {
        switch status {
        case .done: return "checkmark.circle.fill"
        case .open: return "circle"
        case .declined: return "xmark.circle.fill"
        case .free: return "circle.dashed"
        }
    }
}
