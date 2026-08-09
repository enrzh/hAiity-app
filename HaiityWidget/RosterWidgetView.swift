import WidgetKit
import SwiftUI

/// Die Übersicht: mehrere Habits als kompakte Zeilen, damit EIN Widget die
/// ganze Liste abdeckt statt eines Habits.
///
/// Eine Zeile ist: Emoji, Name, was heute mit ihm ist, ein Mini-Raster und
/// ein Zustandsglyph. Die Kopfzeile sagt, wie viel von heute schon steht
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
    let entry: HaiityEntry

    private var palette: PaletteStyle { entry.palettes.style }
    private var today: String { DayKey.today() }

    var body: some View {
        content(family: family, dark: scheme == .dark)
            .containerBackground(for: .widget) { Color(.systemBackground) }
            .widgetURL(URL(string: "haiity://open"))
    }

    /// Familie UND Schema als Argument — siehe `HaiityWidgetView`.
    @ViewBuilder
    func content(family: WidgetFamily, dark: Bool) -> some View {
        let split = WidgetLogic.roster(entry.habits, limit: WidgetLogic.rosterLimit(for: family))
        if split.visible.isEmpty {
            WidgetEmptyState()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                header(overflow: split.overflow)
                ForEach(split.visible) { habit in
                    row(habit, large: family == .systemLarge, dark: dark)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: – Kopf

    private func header(overflow: Int) -> some View {
        let progress = WidgetLogic.progress(habits: entry.habits, today: today)
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

    // MARK: – Zeile

    private func row(_ habit: Habit, large: Bool, dark: Bool) -> some View {
        let status = WidgetLogic.status(habit: habit, today: today)
        let cellPalette = entry.palettes.style(for: habit)
        return HStack(spacing: Theme.Metrics.gap) {
            Text(verbatim: habit.emoji.isEmpty ? "•" : habit.emoji)
                .font(.caption)
                .frame(width: 16, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: habit.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(verbatim: WidgetLogic.statusText(status))
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(status == .done
                                     ? AnyShapeStyle(Theme.accentText(palette))
                                     : AnyShapeStyle(HierarchicalShapeStyle.secondary))
            }
            Spacer(minLength: 4)
            TrailingGrid(habit: habit, today: today, radius: 1) { level in
                Theme.level(level, dark: dark, palette: cellPalette)
            }
            .frame(width: large ? 116 : 88)
            .padding(.vertical, 2)
            glyph(status)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Der Zustand als Symbol — dieselben drei Fälle wie der Text daneben,
    /// nur auf einen Blick: erledigt, offen, heute gar nicht dran.
    @ViewBuilder
    private func glyph(_ status: WidgetStatus) -> some View {
        switch status {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.accentText(palette))
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
