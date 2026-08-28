import WidgetKit
import SwiftUI
import AppIntents

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
        let summary = WidgetLogic.summary(habit: habit, today: today, calendar: calendar)
        let cellPalette = entry.palettes.style(for: habit)
        return GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Link(destination: HaiityWidgetLink.habit(habit.id)) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.accent(cellPalette).opacity(dark ? 0.16 : 0.09))

                        if habit.isReminder {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 42, weight: .semibold))
                                .foregroundStyle(Theme.accentText(cellPalette).opacity(0.18))
                                .frame(maxWidth: .infinity, maxHeight: .infinity,
                                       alignment: .center)
                        } else {
                            TrailingGrid(habit: habit, today: today, radius: nil) { level in
                                HomeWidgetInk.level(level, mode: mode, dark: dark, palette: cellPalette)
                            }
                            .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 4) {
                        Link(destination: HaiityWidgetLink.habit(habit.id)) {
                            Text(verbatim: habit.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 2)
                        actionButtons(habit,
                                      summary: summary,
                                      palette: cellPalette,
                                      dark: dark)
                    }
                    Spacer(minLength: 0)
                    Link(destination: HaiityWidgetLink.habit(habit.id)) {
                        metadata(habit: habit, summary: summary,
                                 palette: cellPalette, dark: dark)
                    }
                }
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

    @ViewBuilder
    private func actionButtons(_ habit: Habit,
                               summary: WidgetItemSummary,
                               palette: PaletteStyle,
                               dark: Bool) -> some View {
        HStack(spacing: 3) {
            switch summary.kind {
            case .yesNo:
                Button(intent: AnswerYesHabitIntent(habit: habit)) {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel(String(localized: "Mit Ja beantworten"))
                Button(intent: AnswerNoHabitIntent(habit: habit)) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(String(localized: "Mit Nein beantworten"))
            case .quantity:
                Button(intent: CheckOffHabitIntent(habit: habit)) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "Menge erhöhen"))
            case .checkbox, .reminder:
                Button(intent: CheckOffHabitIntent(habit: habit)) {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel(habit.isReminder
                                    ? String(localized: "Erinnerung erledigen")
                                    : String(localized: "Habit abhaken"))
            }

            if entry.widgetResetEnabled {
                Button(intent: ResetHabitIntent(habit: habit)) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .accessibilityLabel(String(localized: "Rückgängig"))
            }
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(Theme.accentText(palette))
        .buttonStyle(.plain)
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.24), lineWidth: 0.5) }
    }

    private func metadata(habit: Habit, summary: WidgetItemSummary,
                          palette cellPalette: PaletteStyle, dark: Bool) -> some View {
        let streak = habit.streak(today: entry.today(for: habit),
                                  calendar: entry.calendar(for: habit))
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            if !habit.isReminder {
                Image(systemName: "flame.fill")
                    .font(.caption2.weight(.semibold))
                Text(verbatim: "\(streak)")
                    .font(.caption.weight(.bold).monospacedDigit())
            } else {
                Image(systemName: "bell.fill")
                    .font(.caption2.weight(.semibold))
            }
            Spacer(minLength: 4)
            Image(systemName: summary.metricSymbol)
                .font(.caption2.weight(.semibold))
            Text(verbatim: summary.metricText)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .foregroundStyle(statusTint(summary.status, palette: cellPalette, dark: dark))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.5)
        }
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

}

struct LargeWidgetHeader: View {
    let entry: HaiityEntry
    private var progress: WidgetLogic.DayProgress {
        WidgetLogic.progress(habits: entry.habits,
                             defaultTimeZoneIdentifier: entry.defaultTimeZoneIdentifier,
                             now: entry.date)
    }

    var body: some View {
        HStack {
            Text(String(localized: "Heute")).font(.headline.weight(.semibold))
            Spacer()
            Text(progress.isFree
                 ? String(localized: "Heute frei")
                 : String(localized: "\(progress.met) von \(progress.due) heute"))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct LargeWidgetItem: View {
    let habit: Habit
    let entry: HaiityEntry
    var compact = false
    var graphHeight: CGFloat = 22
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var mode
    var body: some View {
        let today = entry.today(for: habit)
        let summary = WidgetLogic.summary(habit: habit, today: today, calendar: entry.calendar(for: habit))
        let palette = entry.palettes.style(for: habit)
        HStack(spacing: 8) {
            Link(destination: HaiityWidgetLink.habit(habit.id)) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        if !habit.emoji.isEmpty { Text(verbatim: habit.emoji) }
                        Text(verbatim: habit.name).font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
                    }
                    if habit.isReminder {
                        Label(summary.metricText, systemImage: "bell.fill").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                            Text(verbatim: String(habit.streak(today: today, calendar: entry.calendar(for: habit))))
                            Image(systemName: summary.metricSymbol)
                            Text(verbatim: summary.metricText).lineLimit(1)
                        }.font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        TrailingGrid(habit: habit, maxWeeks: compact ? 12 : 18, today: today, radius: nil) { level in
                            HomeWidgetInk.level(level, mode: mode, dark: scheme == .dark, palette: palette)
                        }
                        .frame(height: graphHeight)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 3) {
                switch summary.kind {
                case .yesNo:
                    largeActionButton(intent: AnswerYesHabitIntent(habit: habit), symbol: "checkmark")
                    largeActionButton(intent: AnswerNoHabitIntent(habit: habit), symbol: "xmark")
                case .quantity:
                    largeActionButton(intent: CheckOffHabitIntent(habit: habit), symbol: "plus")
                case .checkbox, .reminder:
                    largeActionButton(intent: CheckOffHabitIntent(habit: habit), symbol: "checkmark")
                }
                if entry.widgetResetEnabled {
                    largeActionButton(intent: ResetHabitIntent(habit: habit), symbol: "arrow.uturn.backward")
                }
            }
            .buttonStyle(.plain).font(.caption2.weight(.bold)).foregroundStyle(Theme.accentText(palette))
        }
        .padding(compact ? 4 : 4)
        .frame(maxHeight: .infinity)
        .background(Theme.accent(palette).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func largeActionButton<I: AppIntent>(intent: I, symbol: String) -> some View {
        Button(intent: intent) { Image(systemName: symbol).frame(minWidth: 44, minHeight: 44) }
    }
}

private extension View {
    func largeWidgetBackground(entry: HaiityEntry, scheme: ColorScheme, mode: WidgetRenderingMode) -> some View {
        containerBackground(for: .widget) {
            HomeWidgetBackground(palette: entry.palettes.style,
                                 dark: scheme == .dark,
                                 mode: mode)
        }
    }
}

struct LargeListWidgetView: View {
    let entry: HaiityEntry
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var mode
    var body: some View {
        VStack(alignment: .leading, spacing: WidgetLogic.LargeGeometry.itemSpacing) {
            if entry.largeItems.isEmpty {
                Link(destination: HaiityWidgetLink.habits) { WidgetEmptyState() }
            } else {
                LargeWidgetHeader(entry: entry).frame(height: WidgetLogic.LargeGeometry.listHeaderHeight)
                ForEach(entry.largeItems.prefix(4)) { habit in
                    LargeWidgetItem(habit: habit, entry: entry, graphHeight: 14)
                        .frame(height: WidgetLogic.LargeGeometry.listRowHeight)
                }
            }
        }
        .padding(12)
        .largeWidgetBackground(entry: entry, scheme: scheme, mode: mode)
    }
}

struct LargeFocusWidgetView: View {
    let entry: HaiityEntry
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var mode
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if entry.largeItems.isEmpty {
                Link(destination: HaiityWidgetLink.habits) { WidgetEmptyState() }
            } else {
                LargeWidgetHeader(entry: entry).frame(height: WidgetLogic.LargeGeometry.focusHeaderHeight)
                if let focus = entry.largeItems.first {
                    LargeWidgetItem(habit: focus, entry: entry, graphHeight: 32)
                        .frame(height: WidgetLogic.LargeGeometry.focusFeaturedHeight)
                }
                ForEach(entry.largeItems.dropFirst().prefix(3)) { habit in
                    LargeWidgetItem(habit: habit, entry: entry, compact: true, graphHeight: 12)
                        .frame(height: WidgetLogic.LargeGeometry.focusQueueHeight)
                }
            }
        }
        .padding(12)
        .largeWidgetBackground(entry: entry, scheme: scheme, mode: mode)
    }
}
