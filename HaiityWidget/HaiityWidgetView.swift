import WidgetKit
import SwiftUI

/// One current item, with actions separate from its app-opening surface.
struct HaiityWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var mode
    let entry: HaiityEntry

    var body: some View {
        content(family: family, dark: scheme == .dark, mode: mode)
            .containerBackground(for: .widget) {
                HomeWidgetBackground(palette: entry.palettes.style(for: entry.habit),
                                     dark: scheme == .dark, mode: mode,
                                     designStyle: entry.designStyle)
            }
    }

    @ViewBuilder
    func content(family: WidgetFamily, dark: Bool,
                 mode: WidgetRenderingMode = .fullColor) -> some View {
        if family == .systemLarge {
            LargeDualWidgetView(entry: entry)
        } else if let habit = entry.habit {
            let summary = WidgetLogic.summary(habit: habit, today: entry.today(for: habit),
                                              calendar: entry.calendar(for: habit), now: entry.date)
            VStack(alignment: .leading, spacing: entry.designStyle.rowGap + 2) {
                HStack(alignment: .top, spacing: 0) {
                    Link(destination: HaiityWidgetLink.habits) {
                        WidgetItemIdentity(habit: habit, entry: entry,
                                           compact: family == .systemSmall)
                            .foregroundStyle(WidgetInk.foreground(mode))
                    }
                    .buttonStyle(.plain)
                    WidgetResetButton(habit: habit, entry: entry, dark: dark, mode: mode)
                }
                .frame(minHeight: family == .systemSmall ? 24 : 30)

                Link(destination: HaiityWidgetLink.habits) {
                    if habit.isReminder {
                        Text(verbatim: summary.metricText)
                            .font(.system(.title3, design: entry.designStyle == .studio ? .serif : .default,
                                          weight: .semibold))
                            .foregroundStyle(WidgetInk.foreground(mode))
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    } else {
                        TrailingGrid(habit: habit, today: entry.today(for: habit),
                                     radius: nil, calendar: entry.calendar(for: habit),
                                     alignment: .center) {
                            HomeWidgetInk.level($0, mode: mode, dark: dark,
                                                palette: entry.palettes.style(for: habit))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(String(localized: "\(habit.name), Serie \(habit.streak(today: entry.today(for: habit), calendar: entry.calendar(for: habit))) Tage"))
                    }
                }
                .buttonStyle(.plain)
                HStack(alignment: .center, spacing: 0) {
                    if habit.isReminder {
                        Spacer(minLength: 0)
                    } else {
                        WidgetItemStatus(summary: summary, palette: entry.palettes.style(for: habit),
                                         dark: dark, mode: mode)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    WidgetItemActions(habit: habit, entry: entry, dark: dark, mode: mode,
                                      includesReset: false, summary: summary)
                }
                .frame(minHeight: 44)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        } else {
            Link(destination: HaiityWidgetLink.habits) { WidgetEmptyState() }
        }
    }
}
