import WidgetKit
import SwiftUI

/// Die Übersicht: mehrere Habits als kompakte Karten, damit EIN Widget die
/// ganze Liste abdeckt statt eines Habits.
///
/// Eine Karte ist: Titel, aktuelle Serie, heutiger Zustand und ein
/// vollbreites Mini-Raster darunter. Die Kopfzeile sagt, wie viel von heute schon steht
/// (dieselbe Zählung wie der Ring auf dem Sperrbildschirm: erfüllte ÷ heute
/// FÄLLIGE) — und, falls mehr Habits da sind als Zeilen passen, wie viele
/// noch darunter liegen.
///
/// Die Reihenfolge bleibt die der Liste. Eine Übersicht, die ihre Zeilen
/// selbst nach „heute offen" umsortiert, wäre beim nächsten Blick eine
/// andere Übersicht — und der Nutzer sucht dann jedes Mal neu.
struct RosterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var mode
    let entry: HaiityEntry

    private var palette: PaletteStyle { entry.palettes.style }

    var body: some View {
        content(family: family, dark: scheme == .dark, mode: mode)
            .containerBackground(for: .widget) {
                HomeWidgetBackground(palette: palette,
                                     dark: scheme == .dark,
                                     mode: mode)
            }
            .widgetURL(URL(string: "haiity://open"))
    }

    /// Familie UND Schema als Argument — siehe `HaiityWidgetView`.
    @ViewBuilder
    func content(family: WidgetFamily,
                 dark: Bool,
                 mode: WidgetRenderingMode = .fullColor) -> some View {
        let split = WidgetLogic.roster(entry.habits, limit: WidgetLogic.rosterLimit(for: family))
        if split.visible.isEmpty {
            WidgetEmptyState()
        } else {
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 4) {
                    header(overflow: split.overflow)
                        .frame(width: geometry.size.width, alignment: .leading)
                    ForEach(split.visible) { habit in
                        row(habit, width: geometry.size.width, dark: dark, mode: mode)
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height,
                       alignment: .topLeading)
            }
        }
    }

    // MARK: – Kopf

    private func header(overflow: Int) -> some View {
        let progress = WidgetLogic.progress(
            habits: entry.habits,
            defaultTimeZoneIdentifier: entry.defaultTimeZoneIdentifier,
            now: entry.date)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(String(localized: "Heute"))
                .font(.caption.weight(.semibold))
            Spacer(minLength: 4)
            if overflow > 0 {
                Text(verbatim: "+\(overflow)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text(verbatim: progress.isFree
                 ? String(localized: "frei")
                 : "\(progress.met)/\(progress.due)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(progress.isComplete
                                 ? AnyShapeStyle(Theme.accentText(palette))
                                 : AnyShapeStyle(HierarchicalShapeStyle.secondary))
        }
    }

    // MARK: – Karte

    private func row(_ habit: Habit,
                     width: CGFloat,
                     dark: Bool,
                     mode: WidgetRenderingMode) -> some View {
        let today = entry.today(for: habit)
        let calendar = entry.calendar(for: habit)
        let status = WidgetLogic.status(habit: habit, today: today,
                                        calendar: calendar)
        let cellPalette = entry.palettes.style(for: habit)
        return GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.accent(cellPalette).opacity(dark ? 0.16 : 0.09))

                TrailingGrid(habit: habit, today: today, radius: nil) { level in
                    HomeWidgetInk.level(level, mode: mode, dark: dark, palette: cellPalette)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)

                metadata(habit: habit, today: today, calendar: calendar, status: status,
                         palette: cellPalette, dark: dark)
                    .padding(6)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.accentText(cellPalette).opacity(0.2), lineWidth: 0.5)
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func streakRun(_ habit: Habit, today: String, calendar: Calendar) -> Text {
        Text(Image(systemName: "flame.fill"))
            + Text(verbatim: " \(habit.streak(today: today, calendar: calendar))")
    }

    private func metadata(habit: Habit, today: String, calendar: Calendar,
                          status: WidgetStatus,
                          palette cellPalette: PaletteStyle, dark: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if !habit.emoji.isEmpty {
                Text(verbatim: habit.emoji)
                    .font(.caption)
            }
            Text(verbatim: habit.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            streakRun(habit, today: today, calendar: calendar)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
            glyph(status, palette: cellPalette, dark: dark)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.5)
        }
    }

    /// Der Zustand als Symbol — dieselben Fälle wie der Text daneben, nur auf
    /// einen Blick: erledigt, verneint, offen, heute gar nicht dran.
    @ViewBuilder
    private func glyph(_ status: WidgetStatus, palette cellPalette: PaletteStyle,
                       dark: Bool) -> some View {
        switch status {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.accentText(palette))
        case .declined:
            Image(systemName: "xmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.color(cellPalette.negative(dark: dark)))
        case .open:
            Image(systemName: "circle")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        case .free:
            Image(systemName: "circle.dashed")
                .font(.footnote)
                .foregroundStyle(.quaternary)
        }
    }
}
