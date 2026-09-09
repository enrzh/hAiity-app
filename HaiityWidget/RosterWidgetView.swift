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
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Link(destination: HaiityWidgetLink.habits) {
                        Text(verbatim: habit.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 4)
                    Link(destination: HaiityWidgetLink.habits) {
                        metadata(habit: habit, summary: summary,
                                 palette: cellPalette, dark: dark)
                    }
                    actionButtons(habit, summary: summary,
                                  palette: cellPalette, dark: dark)
                }
                .frame(height: 22)

                Link(destination: HaiityWidgetLink.habits) {
                    if habit.isReminder {
                        Label(summary.metricText, systemImage: "bell.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity,
                                   alignment: .leading)
                    } else {
                        TrailingGrid(habit: habit, today: today, radius: nil) { level in
                            HomeWidgetInk.level(level, mode: mode, dark: dark,
                                                palette: cellPalette)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(width: geometry.size.width, height: geometry.size.height,
                   alignment: .topLeading)
            .widgetTileSurface(palette: cellPalette, dark: dark, mode: mode, radius: 8)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .contain)
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

            if entry.showsReset(for: habit) {
                Button(intent: ResetHabitIntent(habit: habit)) {
                    Image(systemName: "arrow.uturn.backward").foregroundStyle(.secondary)
                }
                .accessibilityLabel(String(localized: "Rückgängig"))
            }
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(Theme.accentText(palette))
        .buttonStyle(.plain)
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
        .foregroundStyle(statusTint(summary.status, palette: cellPalette, dark: dark))
        .fixedSize(horizontal: true, vertical: false)
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
            Text(String(localized: "Heute geplant")).font(.subheadline.weight(.semibold))
            Spacer()
            Text(progress.isFree
                 ? String(localized: "frei")
                 : "\(progress.met)/\(progress.due)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(progress.isFree
            ? String(localized: "Heute keine festen Termine")
            : String(localized: "\(progress.met) von \(progress.due) geplanten Habits erledigt"))
    }
}

private struct LargeWidgetItem: View {
    let habit: Habit
    let entry: HaiityEntry
    var compact = false
    var graphHeight: CGFloat = 22
    var graph = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var mode
    var body: some View {
        let today = entry.today(for: habit)
        let summary = WidgetLogic.summary(habit: habit, today: today, calendar: entry.calendar(for: habit))
        let palette = entry.palettes.style(for: habit)
        let identityHeight = compact
            ? WidgetLogic.LargeGeometry.focusIdentityBandHeight
            : WidgetLogic.LargeGeometry.listIdentityBandHeight
        let actionHeight = compact
            ? WidgetLogic.LargeGeometry.focusActionBandHeight
            : WidgetLogic.LargeGeometry.listActionBandHeight
        // Reserved bands: listIdentityBandHeight, listVisualBandHeight, listActionBandHeight.
        // Fokus uses the same identityBand / visualBand / actionBand ownership.
        let identityBand = HStack(alignment: .firstTextBaseline, spacing: 4) {
            if !habit.emoji.isEmpty {
                Text(verbatim: habit.emoji).fixedSize(horizontal: true, vertical: false)
            }
            Text(verbatim: habit.name)
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
            Spacer(minLength: 2)
            if habit.isReminder {
                Image(systemName: "bell.fill")
            } else {
                compactStatus(summary)
            }
        }
        .font(.caption2)
        .foregroundStyle(Color.primary)
        .lineLimit(1)
        .frame(height: identityHeight, alignment: .leading)

        let visualBand = Group {
            if graph && habit.isReminder {
                Text(verbatim: summary.metricText)
                    .font(compact ? .caption2 : .caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else if graph {
                TrailingGrid(habit: habit, maxWeeks: 53, today: today, radius: nil) { level in
                    HomeWidgetInk.level(level, mode: mode, dark: scheme == .dark, palette: palette)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }

        HStack(alignment: .top, spacing: WidgetLogic.LargeGeometry.itemSpacing) {
            Link(destination: HaiityWidgetLink.habits) {
                VStack(alignment: .leading, spacing: WidgetLogic.LargeGeometry.itemSpacing) {
                    let titleStatusBand = identityBand
                    titleStatusBand
                    if graph {
                        visualBand
                            .frame(height: graphHeight)
                            .clipped()
                    } else {
                        visualBand
                            .frame(height: max(0, WidgetLogic.LargeGeometry.focusQueueHeight
                                                - identityHeight
                                                - WidgetLogic.LargeGeometry.itemSpacing))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            let actionBand = HStack(spacing: 3) {
                switch summary.kind {
                case .yesNo:
                    largeActionButton(intent: AnswerYesHabitIntent(habit: habit), symbol: "checkmark",
                                      label: String(localized: "Mit Ja beantworten"))
                    largeActionButton(intent: AnswerNoHabitIntent(habit: habit), symbol: "xmark",
                                      label: String(localized: "Mit Nein beantworten"))
                case .quantity:
                    largeActionButton(intent: CheckOffHabitIntent(habit: habit), symbol: "plus",
                                      label: String(localized: "Menge erhöhen"))
                case .checkbox, .reminder:
                    largeActionButton(intent: CheckOffHabitIntent(habit: habit), symbol: "checkmark",
                                      label: habit.isReminder
                                        ? String(localized: "Erinnerung erledigen")
                                        : String(localized: "Habit abhaken"))
                }
                if entry.showsReset(for: habit) {
                    largeActionButton(intent: ResetHabitIntent(habit: habit), symbol: "arrow.uturn.backward",
                                      label: String(localized: "Rückgängig"))
                }
            }
            .buttonStyle(.plain)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Theme.accentText(palette))
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: actionHeight,
                   minHeight: actionHeight,
                   maxHeight: actionHeight,
                   alignment: .topTrailing)
            actionBand
        }
        .padding(.horizontal, compact ? 0 : 6)

        .frame(maxWidth: .infinity,
               minHeight: compact ? nil : identityHeight + graphHeight + WidgetLogic.LargeGeometry.itemSpacing,
               maxHeight: compact ? nil : identityHeight + graphHeight + WidgetLogic.LargeGeometry.itemSpacing,
               alignment: .topLeading)
    }

    @ViewBuilder
    private func compactStatus(_ summary: WidgetItemSummary) -> some View {
        switch summary.kind {
        case .checkbox:
            Image(systemName: summary.metricSymbol)
        case .quantity, .yesNo:
            Label(summary.metricText, systemImage: summary.metricSymbol)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        case .reminder:
            EmptyView()
        }
    }

    private func statusTint(_ status: WidgetStatus, palette: PaletteStyle) -> AnyShapeStyle {
        switch status {
        case .done: return AnyShapeStyle(Theme.accentText(palette))
        case .declined: return AnyShapeStyle(Theme.color(palette.negative(dark: scheme == .dark)))
        case .open, .free: return AnyShapeStyle(HierarchicalShapeStyle.secondary)
        }
    }

    private func largeActionButton<I: AppIntent>(intent: I, symbol: String, label: String) -> some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .frame(width: WidgetLogic.LargeGeometry.actionHeight,
                       height: WidgetLogic.LargeGeometry.actionHeight)
        }
        .contentShape(Rectangle())
        .accessibilityLabel(label)
        .foregroundStyle(symbol == "arrow.uturn.backward" ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Theme.accentText(entry.palettes.style(for: habit))))
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

private struct LargeFeaturedWidgetItem: View {
    let habit: Habit
    let entry: HaiityEntry
    var maxWeeks: Int = 53
    var showsSurface: Bool = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let today = entry.today(for: habit)
        let summary = WidgetLogic.summary(habit: habit, today: today, calendar: entry.calendar(for: habit))
        let palette = entry.palettes.style(for: habit)
        let identityBand = HStack(alignment: .firstTextBaseline, spacing: 4) {
            if !habit.emoji.isEmpty { Text(verbatim: habit.emoji).fixedSize(horizontal: true, vertical: false) }
            Text(verbatim: habit.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                .minimumScaleFactor(0.8).layoutPriority(1)
            Spacer(minLength: 2)
            if habit.isReminder {
                Image(systemName: "bell.fill")
            } else {
                compactStatus(summary)
                    .foregroundStyle(statusTint(summary.status, palette: palette))
            }
        }
        .font(.caption2).foregroundStyle(Color.primary).lineLimit(1)
        let visualBand = Group {
            if habit.isReminder {
                if summary.status == .open {
                    Label("", systemImage: summary.metricSymbol)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else {
                    Label(summary.metricText, systemImage: "bell.fill")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                        .minimumScaleFactor(0.8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            } else {
                TrailingGrid(habit: habit, maxWeeks: maxWeeks, today: today, radius: nil) { level in
                    HomeWidgetInk.level(level, mode: mode, dark: scheme == .dark, palette: palette)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        let actionBand = actions(summary: summary, palette: palette)

        let card = VStack(alignment: .leading, spacing: 0) {
            Link(destination: HaiityWidgetLink.habits) {
                VStack(alignment: .leading, spacing: 0) {
                    identityBand.frame(height: WidgetLogic.LargeGeometry.featuredIdentityBandHeight)
                    visualBand.frame(maxWidth: .infinity)
                        .frame(height: WidgetLogic.LargeGeometry.featuredVisualBandHeight)
                }
            }
            actionBand.frame(height: WidgetLogic.LargeGeometry.featuredActionBandHeight)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: WidgetLogic.LargeGeometry.featuredListHeight, alignment: .topLeading)

        if showsSurface {
            card.widgetTileSurface(palette: palette,
                                   dark: scheme == .dark,
                                   mode: mode)
        } else {
            card
        }
    }

    @ViewBuilder
    private func compactStatus(_ summary: WidgetItemSummary) -> some View {
        switch summary.kind {
        case .checkbox: Image(systemName: summary.metricSymbol)
        case .quantity, .yesNo: Label(summary.metricText, systemImage: summary.metricSymbol).lineLimit(1).minimumScaleFactor(0.8)
        case .reminder: EmptyView()
        }
    }

    private func actions(summary: WidgetItemSummary, palette: PaletteStyle) -> some View {
        HStack(spacing: 3) {
            if summary.status == .open && (summary.kind == .checkbox || summary.kind == .reminder) {
                Color.clear.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label(summary.metricText, systemImage: summary.metricSymbol)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            switch summary.kind {
            case .yesNo:
                largeActionButton(intent: AnswerYesHabitIntent(habit: habit), symbol: "checkmark", label: String(localized: "Mit Ja beantworten"))
                largeActionButton(intent: AnswerNoHabitIntent(habit: habit), symbol: "xmark", label: String(localized: "Mit Nein beantworten"))
            case .quantity:
                largeActionButton(intent: CheckOffHabitIntent(habit: habit), symbol: "plus", label: String(localized: "Menge erhöhen"))
            case .checkbox, .reminder:
                largeActionButton(intent: CheckOffHabitIntent(habit: habit), symbol: "checkmark", label: habit.isReminder ? String(localized: "Erinnerung erledigen") : String(localized: "Habit abhaken"))
            }
            if entry.showsReset(for: habit) {
                largeActionButton(intent: ResetHabitIntent(habit: habit), symbol: "arrow.uturn.backward", label: String(localized: "Rückgängig"))
            }
        }
        .buttonStyle(.plain).font(.caption2.weight(.bold)).foregroundStyle(Theme.accentText(palette))
        .frame(height: WidgetLogic.LargeGeometry.featuredActionBandHeight, alignment: .trailing)
    }

    private func largeActionButton<I: AppIntent>(intent: I, symbol: String, label: String) -> some View {
        Button(intent: intent) { Image(systemName: symbol).frame(width: 44, height: 44) }
            .contentShape(Rectangle()).accessibilityLabel(label)
            .foregroundStyle(symbol == "arrow.uturn.backward" ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.accentText(entry.palettes.style(for: habit))))
    }

    private func statusTint(_ status: WidgetStatus, palette: PaletteStyle) -> AnyShapeStyle {
        switch status {
        case .done: return AnyShapeStyle(Theme.accentText(palette))
        case .declined: return AnyShapeStyle(Theme.color(palette.negative(dark: scheme == .dark)))
        case .open, .free: return AnyShapeStyle(HierarchicalShapeStyle.secondary)
        }
    }
}

private struct LargeCompactWidgetRow: View {
    let habit: Habit
    let entry: HaiityEntry
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let today = entry.today(for: habit)
        let summary = WidgetLogic.summary(habit: habit, today: today, calendar: entry.calendar(for: habit))
        let palette = entry.palettes.style(for: habit)
        HStack(spacing: WidgetLogic.LargeGeometry.itemSpacing) {
            Link(destination: HaiityWidgetLink.habits) {
                HStack(spacing: 4) {
                    if !habit.emoji.isEmpty { Text(verbatim: habit.emoji).fixedSize(horizontal: true, vertical: false) }
                    Text(verbatim: habit.name).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 2)
                    if habit.isReminder {
                        Label(summary.metricText, systemImage: "bell.fill")
                    } else {
                        Label(summary.metricText, systemImage: summary.metricSymbol)
                    }
                }
                .lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(Color.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actions(summary: summary, palette: palette)
        }
        .frame(maxWidth: .infinity)
        .frame(height: WidgetLogic.LargeGeometry.compactListRowHeight)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func actions(summary: WidgetItemSummary, palette: PaletteStyle) -> some View {
        HStack(spacing: 3) {
            switch summary.kind {
            case .yesNo:
                largeActionButton(intent: AnswerYesHabitIntent(habit: habit), symbol: "checkmark", label: String(localized: "Mit Ja beantworten"))
                largeActionButton(intent: AnswerNoHabitIntent(habit: habit), symbol: "xmark", label: String(localized: "Mit Nein beantworten"))
            case .quantity:
                largeActionButton(intent: CheckOffHabitIntent(habit: habit), symbol: "plus", label: String(localized: "Menge erhöhen"))
            case .checkbox, .reminder:
                largeActionButton(intent: CheckOffHabitIntent(habit: habit), symbol: "checkmark", label: habit.isReminder ? String(localized: "Erinnerung erledigen") : String(localized: "Habit abhaken"))
            }
            if entry.showsReset(for: habit) {
                largeActionButton(intent: ResetHabitIntent(habit: habit), symbol: "arrow.uturn.backward", label: String(localized: "Rückgängig"))
            }
        }
        .buttonStyle(.plain).font(.caption2.weight(.bold)).foregroundStyle(Theme.accentText(palette))
        .fixedSize(horizontal: true, vertical: false).frame(height: WidgetLogic.LargeGeometry.compactListRowHeight)
    }

    private func largeActionButton<I: AppIntent>(intent: I, symbol: String, label: String) -> some View {
        Button(intent: intent) { Image(systemName: symbol).frame(width: 44, height: 44) }
            .contentShape(Rectangle()).accessibilityLabel(label)
            .foregroundStyle(symbol == "arrow.uturn.backward" ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.accentText(entry.palettes.style(for: habit))))
    }

    private func statusTint(_ status: WidgetStatus, palette: PaletteStyle) -> AnyShapeStyle {
        switch status {
        case .done: return AnyShapeStyle(Theme.accentText(palette))
        case .declined: return AnyShapeStyle(Theme.color(palette.negative(dark: scheme == .dark)))
        case .open, .free: return AnyShapeStyle(HierarchicalShapeStyle.secondary)
        }
    }
}

struct LargeListWidgetView: View {
    let entry: HaiityEntry
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var mode
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entry.largeItems.isEmpty {
                Link(destination: HaiityWidgetLink.habits) { WidgetEmptyState() }
            } else {
                LargeWidgetHeader(entry: entry)
                    .frame(height: WidgetLogic.LargeGeometry.featuredListHeaderHeight)
                Color.clear.frame(height: WidgetLogic.LargeGeometry.featuredListHeaderGap)
                if let featured = entry.largeItems.first {
                    LargeFeaturedWidgetItem(habit: featured, entry: entry, showsSurface: true)
                }
                VStack(alignment: .leading, spacing: WidgetLogic.LargeGeometry.compactListRowGap) {
                    ForEach(entry.largeItems.dropFirst().prefix(3)) { habit in
                        LargeCompactWidgetRow(habit: habit, entry: entry)
                    }
                }
            }
        }
        .padding(WidgetLogic.LargeGeometry.outerPadding)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .largeWidgetBackground(entry: entry, scheme: scheme, mode: mode)
    }
}

/// Die Hauptansicht des hAiity-Widgets im großen Format: zwei ausgewählte
/// Karten mit derselben vollständigen Darstellung wie die bestehende Habit-
/// Karte. Es gibt bewusst keine zusätzliche „Heute“-Kopfzeile, damit beide
/// Karten den verfügbaren Platz für ihren Graphen nutzen.
struct LargeDualWidgetView: View {
    let entry: HaiityEntry

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetLogic.LargeGeometry.compactListRowGap) {
            if entry.largeItems.isEmpty {
                Link(destination: HaiityWidgetLink.habits) { WidgetEmptyState() }
            } else {
                ForEach(entry.largeItems.prefix(2)) { habit in
                    LargeFeaturedWidgetItem(habit: habit, entry: entry, maxWeeks: 24,
                                            showsSurface: true)
                }
            }
        }
        .padding(WidgetLogic.LargeGeometry.outerPadding)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

struct LargeFocusWidgetView: View {
    let entry: HaiityEntry
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var mode
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entry.largeItems.isEmpty {
                Link(destination: HaiityWidgetLink.habits) { WidgetEmptyState() }
            } else {
                LargeWidgetHeader(entry: entry).frame(height: WidgetLogic.LargeGeometry.focusHeaderHeight)
                Color.clear.frame(height: WidgetLogic.LargeGeometry.focusHeaderGap)
                if let focus = entry.largeItems.first {
                    LargeWidgetItem(habit: focus, entry: entry,
                                    graphHeight: WidgetLogic.LargeGeometry.focusFeaturedGraphMinimumHeight)
                        .frame(height: WidgetLogic.LargeGeometry.focusFeaturedHeight)
                }
                Color.clear.frame(height: WidgetLogic.LargeGeometry.focusFeaturedQueueGap)
                VStack(alignment: .leading, spacing: WidgetLogic.LargeGeometry.itemSpacing) {
                    ForEach(entry.largeItems.dropFirst().prefix(3)) { habit in
                        LargeWidgetItem(habit: habit, entry: entry, compact: true,
                                        graph: false)
                            .frame(height: WidgetLogic.LargeGeometry.focusQueueHeight)
                    }
                }
            }
        }
        .padding(WidgetLogic.LargeGeometry.outerPadding)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .largeWidgetBackground(entry: entry, scheme: scheme, mode: mode)
    }
}
