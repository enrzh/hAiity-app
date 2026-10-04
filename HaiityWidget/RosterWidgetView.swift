import WidgetKit
import SwiftUI

/// Retained overview: source order stays in WidgetLogic; available height
/// determines how many readable rows fit beside independent 44pt actions.
struct RosterWidgetView: View {
    let entry: HaiityEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var mode
    @ScaledMetric(relativeTo: .caption) private var rowMinimum: CGFloat = 64
    @ScaledMetric(relativeTo: .caption2) private var overflowHeight: CGFloat = 16

    var body: some View {
        content(family: family, dark: scheme == .dark, mode: mode)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .containerBackground(for: .widget) {
                HomeWidgetBackground(palette: entry.palettes.style,
                                     dark: scheme == .dark, mode: mode,
                                     designStyle: entry.designStyle)
            }
    }

    @ViewBuilder
    func content(family: WidgetFamily,
                 dark: Bool,
                 mode: WidgetRenderingMode = .fullColor) -> some View {
        if entry.habits.allSatisfy({ $0.archivedAt != nil }) {
            Link(destination: HaiityWidgetLink.habits) { WidgetEmptyState() }
        } else {
            VStack(alignment: .leading, spacing: min(4, entry.designStyle.rowGap)) {
                WidgetProgressHeader(entry: entry, dark: dark, mode: mode)
                GeometryReader { geometry in
                    let gap = min(4, entry.designStyle.rowGap)
                    let capacity = max(1, Int((max(0, geometry.size.height - overflowHeight) + gap)
                                              / (max(44, rowMinimum) + gap)))
                    let split = WidgetLogic.roster(entry.habits, limit: min(
                        WidgetLogic.rosterLimit(for: family), capacity))
                    VStack(spacing: gap) {
                        GeometryReader { rows in
                            let count = split.visible.count
                            let height = max(0, (rows.size.height - CGFloat(max(0, count - 1)) * gap)
                                             / CGFloat(max(1, count)))
                            VStack(spacing: gap) {
                                ForEach(Array(split.visible.enumerated()), id: \.element.id) { index, habit in
                                    WidgetGraphRow(habit: habit, entry: entry, dark: dark, mode: mode)
                                        .frame(height: height)
                                        .overlay(alignment: .bottom) {
                                            if index < count - 1 { Divider() }
                                        }
                                }
                            }
                        }
                        if split.overflow > 0 {
                            Text(verbatim: "+\(split.overflow)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(WidgetInk.foreground(mode))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

/// Every selected item receives an equal share of the space below today's
/// header. Sparse selections grow the real rows instead of inventing slots.
struct LargeListWidgetView: View {
    let entry: HaiityEntry
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        Group {
            if entry.largeItems.isEmpty {
                Link(destination: HaiityWidgetLink.habits) { WidgetEmptyState() }
            } else {
                VStack(alignment: .leading, spacing: min(4, entry.designStyle.rowGap)) {
                    WidgetProgressHeader(entry: entry, dark: scheme == .dark, mode: mode)
                    WidgetGraphRows(items: Array(entry.largeItems.prefix(4)), entry: entry,
                                    dark: scheme == .dark, mode: mode)
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .containerBackground(for: .widget) {
            HomeWidgetBackground(palette: entry.palettes.style,
                                 dark: scheme == .dark, mode: mode,
                                 designStyle: entry.designStyle)
        }
    }
}

/// Two selections have equal graph-led regions without a competing page header.
struct LargeDualWidgetView: View {
    let entry: HaiityEntry
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        Group {
            if entry.largeItems.isEmpty {
                Link(destination: HaiityWidgetLink.habits) { WidgetEmptyState() }
            } else {
                GeometryReader { geometry in
                    let items = Array(entry.largeItems.prefix(2))
                    let gap = min(8, entry.designStyle.rowGap * 2)
                    let height = max(0, (geometry.size.height - CGFloat(items.count - 1) * gap)
                                     / CGFloat(items.count))
                    VStack(spacing: gap) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, habit in
                            WidgetGraphPanel(habit: habit, entry: entry,
                                             dark: scheme == .dark, mode: mode)
                                .frame(height: height)
                                .overlay(alignment: .bottom) {
                                    if index < items.count - 1 { Divider() }
                                }
                        }
                    }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

/// The first selection gets the space left by three quiet task rows.
/// Only that first row mounts a graph; reminders always remain task content.
struct LargeFocusWidgetView: View {
    let entry: HaiityEntry
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if let habit = entry.largeItems.first {
                VStack(alignment: .leading, spacing: min(4, entry.designStyle.rowGap)) {
                    WidgetProgressHeader(entry: entry, dark: scheme == .dark, mode: mode)
                    if dynamicTypeSize.isAccessibilitySize {
                        WidgetGraphRows(items: Array(entry.largeItems.prefix(4)), entry: entry,
                                        dark: scheme == .dark, mode: mode)
                    } else {
                        WidgetGraphRow(habit: habit, entry: entry,
                                       dark: scheme == .dark, mode: mode, compact: false)
                            .frame(maxHeight: .infinity)
                            .layoutPriority(1)
                        ForEach(entry.largeItems.dropFirst().prefix(3)) { queued in
                            Divider()
                            WidgetTaskRow(habit: queued, entry: entry,
                                          dark: scheme == .dark, mode: mode)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(minHeight: 44)
                        }
                    }
                }
            } else {
                Link(destination: HaiityWidgetLink.habits) { WidgetEmptyState() }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .containerBackground(for: .widget) {
            HomeWidgetBackground(palette: entry.palettes.style,
                                 dark: scheme == .dark, mode: mode,
                                 designStyle: entry.designStyle)
        }
    }
}

struct WidgetGraphRows: View {
    let items: [Habit]
    let entry: HaiityEntry
    let dark: Bool
    let mode: WidgetRenderingMode

    var body: some View {
        GeometryReader { geometry in
            let gap = min(4, entry.designStyle.rowGap)
            let height = max(0, (geometry.size.height - CGFloat(max(0, items.count - 1)) * gap)
                             / CGFloat(max(1, items.count)))
            VStack(spacing: gap) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, habit in
                    WidgetGraphRow(habit: habit, entry: entry, dark: dark, mode: mode)
                        .frame(height: height)
                        .overlay(alignment: .bottom) {
                            if index < items.count - 1 { Divider() }
                        }
                }
            }
        }
    }
}

/// Identity and graph share one navigation target. Intent actions are siblings.
private struct WidgetGraphRow: View {
    let habit: Habit
    let entry: HaiityEntry
    let dark: Bool
    let mode: WidgetRenderingMode
    var compact = true

    var body: some View {
        let summary = WidgetLogic.summary(habit: habit, today: entry.today(for: habit),
                                          calendar: entry.calendar(for: habit), now: entry.date)
        let palette = entry.palettes.style(for: habit)
        HStack(alignment: .center, spacing: min(4, entry.designStyle.rowGap)) {
            Link(destination: HaiityWidgetLink.habits) {
                VStack(alignment: .leading, spacing: min(4, entry.designStyle.rowGap)) {
                    WidgetItemIdentity(habit: habit, entry: entry, compact: compact)
                    if !habit.isReminder {
                        TrailingGrid(habit: habit, today: entry.today(for: habit),
                                     radius: nil, calendar: entry.calendar(for: habit), alignment: .center) { level in
                            HomeWidgetInk.level(level, mode: mode, dark: dark, palette: palette)
                        }
                        .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .foregroundStyle(WidgetInk.foreground(mode))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)

            VStack(alignment: .trailing, spacing: 0) {
                WidgetItemStatus(summary: summary, palette: palette, dark: dark, mode: mode,
                                 compact: true)
                WidgetItemActions(habit: habit, entry: entry, dark: dark, mode: mode, summary: summary)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct WidgetTaskRow: View {
    let habit: Habit
    let entry: HaiityEntry
    let dark: Bool
    let mode: WidgetRenderingMode

    var body: some View {
        let summary = WidgetLogic.summary(habit: habit, today: entry.today(for: habit),
                                          calendar: entry.calendar(for: habit), now: entry.date)
        HStack(spacing: min(4, entry.designStyle.rowGap)) {
            Link(destination: HaiityWidgetLink.habits) {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetItemIdentity(habit: habit, entry: entry, compact: true, maximumLines: 1)
                    WidgetItemStatus(summary: summary, palette: entry.palettes.style(for: habit),
                                     dark: dark, mode: mode, compact: true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .foregroundStyle(WidgetInk.foreground(mode))
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            WidgetItemActions(habit: habit, entry: entry, dark: dark, mode: mode, summary: summary)
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Shared by dual and 2x2 compositions: a flexible graph between a readable
/// identity and a 44pt action row. Reset has its own title-side target.
struct WidgetGraphPanel: View {
    let habit: Habit
    let entry: HaiityEntry
    let dark: Bool
    let mode: WidgetRenderingMode
    var compact = false

    var body: some View {
        let summary = WidgetLogic.summary(habit: habit, today: entry.today(for: habit),
                                          calendar: entry.calendar(for: habit), now: entry.date)
        let palette = entry.palettes.style(for: habit)
        VStack(alignment: .leading, spacing: min(4, entry.designStyle.rowGap)) {
            ZStack(alignment: .topTrailing) {
                Link(destination: HaiityWidgetLink.habits) {
                    VStack(alignment: .leading, spacing: min(4, entry.designStyle.rowGap)) {
                        WidgetItemIdentity(habit: habit, entry: entry, compact: compact)
                            .padding(.trailing, entry.showsReset(for: habit) ? 44 : 0)
                            .frame(minHeight: entry.showsReset(for: habit) ? 44 : 0,
                                   alignment: .topLeading)
                        if habit.isReminder {
                            WidgetItemStatus(summary: summary, palette: palette, dark: dark, mode: mode)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        } else {
                            TrailingGrid(habit: habit, today: entry.today(for: habit),
                                         radius: nil, calendar: entry.calendar(for: habit), alignment: .center) { level in
                                HomeWidgetInk.level(level, mode: mode, dark: dark, palette: palette)
                            }
                            .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .foregroundStyle(WidgetInk.foreground(mode))
                WidgetResetButton(habit: habit, entry: entry, dark: dark, mode: mode)
            }
            HStack(spacing: 0) {
                if !habit.isReminder {
                    WidgetItemStatus(summary: summary, palette: palette, dark: dark, mode: mode,
                                     compact: compact)
                }
                Spacer(minLength: 0)
                WidgetItemActions(habit: habit, entry: entry, dark: dark, mode: mode,
                                  includesReset: false, summary: summary)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
