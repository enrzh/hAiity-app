import SwiftUI
import WidgetKit
import AppIntents

struct WidgetItemIdentity: View {
    let habit: Habit
    let entry: HaiityEntry
    var compact = false
    var maximumLines = 2

    private var titleFont: Font {
        .system(compact ? .caption : .headline,
                design: entry.designStyle == .studio ? .serif : .default,
                weight: entry.designStyle == .quiet ? .medium : .semibold)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if !habit.emoji.isEmpty {
                Text(verbatim: habit.emoji).accessibilityHidden(true)
            } else if habit.isReminder {
                Image(systemName: "bell").accessibilityHidden(true)
            }
            Text(verbatim: habit.name)
                .font(titleFont)
                .lineLimit(maximumLines)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(habit.name)
    }
}

struct WidgetItemStatus: View {
    let summary: WidgetItemSummary
    let palette: PaletteStyle
    let dark: Bool
    var mode: WidgetRenderingMode = .fullColor
    var compact = false

    private var color: Color {
        guard mode == .fullColor else { return .white }
        switch summary.status {
        case .done: return Theme.accentText(palette)
        case .declined: return Theme.color(palette.negative(dark: dark))
        case .open, .free: return .secondary
        }
    }

    var body: some View {
        let text = summary.metricText.hasPrefix("✓ ") || summary.metricText.hasPrefix("✗ ")
            ? String(summary.metricText.dropFirst(2)) : summary.metricText
        Label {
            Text(text)
                .foregroundStyle(mode == .fullColor && summary.status == .declined ? Color.primary : color)
        } icon: {
            Image(systemName: summary.metricSymbol).foregroundStyle(color)
        }
            .font(compact ? .caption2 : .caption)
            .foregroundStyle(color)
            .lineLimit(compact ? 1 : 2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(summary.metricText)
    }
}

/// Intent buttons have independent hit targets, outside app-opening links.
struct WidgetItemActions: View {
    let habit: Habit
    let entry: HaiityEntry
    let dark: Bool
    var mode: WidgetRenderingMode = .fullColor
    var includesReset = true
    var summary: WidgetItemSummary? = nil

    var body: some View {
        let summary = self.summary ?? WidgetLogic.summary(habit: habit, today: entry.today(for: habit),
                                                          calendar: entry.calendar(for: habit), now: entry.date)
        HStack(spacing: 0) {
            switch summary.kind {
            case .yesNo:
                action(AnswerYesHabitIntent(habit: habit), symbol: "checkmark",
                       label: String(localized: "Mit Ja beantworten"),
                       summary: summary, selected: summary.answer == .yes, negative: false)
                action(AnswerNoHabitIntent(habit: habit), symbol: "xmark",
                       label: String(localized: "Mit Nein beantworten"),
                       summary: summary, selected: summary.answer == .no, negative: true)
            case .quantity:
                action(CheckOffHabitIntent(habit: habit), symbol: "plus",
                       label: String(localized: "Menge erhöhen"),
                       summary: summary, selected: false, negative: false)
            case .checkbox, .reminder:
                action(CheckOffHabitIntent(habit: habit), symbol: "checkmark",
                       label: habit.isReminder ? String(localized: "Erinnerung erledigen")
                                              : String(localized: "Habit abhaken"),
                       summary: summary, selected: summary.status == .done, negative: false)
                    .disabled(summary.status == .done)
            }
            if includesReset {
                WidgetResetButton(habit: habit, entry: entry, dark: dark, mode: mode)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
    }

    private func action<I: AppIntent>(_ intent: I, symbol: String, label: String,
                                      summary: WidgetItemSummary,
                                      selected: Bool, negative: Bool) -> some View {
        let palette = entry.palettes.style(for: habit)
        let accent = negative ? Theme.color(palette.negative(dark: dark)) : Theme.accentText(entry.palettes.style)
        let filled = selected && !negative
        return Button(intent: intent) {
            Image(systemName: selected && negative ? "xmark.circle.fill" : symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(mode == .fullColor ? (filled ? Color.white : accent) : Color.white)
                .frame(width: 30, height: 30)
                .background {
                    Circle().fill(mode == .fullColor
                                  ? (filled ? Theme.accentFill(entry.palettes.style) : accent.opacity(0.09))
                                  : Color.white.opacity(selected ? 0.3 : 0.1))
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(summary.metricText)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct WidgetResetButton: View {
    let habit: Habit
    let entry: HaiityEntry
    let dark: Bool
    var mode: WidgetRenderingMode = .fullColor

    var body: some View {
        if entry.showsReset(for: habit) {
            Button(intent: ResetHabitIntent(habit: habit)) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(mode == .fullColor ? Color.secondary : Color.white.opacity(0.75))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Rückgängig"))
        }
    }
}

struct WidgetProgressHeader: View {
    let entry: HaiityEntry
    var dark = false
    var mode: WidgetRenderingMode = .fullColor

    var body: some View {
        let progress = WidgetLogic.progress(habits: entry.habits,
            defaultTimeZoneIdentifier: entry.defaultTimeZoneIdentifier, now: entry.date)
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "Heute"))
                    .font(.system(.subheadline, design: entry.designStyle == .studio ? .serif : .default,
                                  weight: .semibold))
                Spacer(minLength: 4)
                Text(progress.isFree ? String(localized: "frei") : "\(progress.met)/\(progress.due)")
                    .font(.caption.weight(.semibold).monospacedDigit())
            }
            .foregroundStyle(WidgetInk.foreground(mode))
            if !progress.isFree {
                GeometryReader { geometry in
                    Capsule().fill(mode == .fullColor ? Color.primary.opacity(0.1) : Color.white.opacity(0.15))
                    Capsule().fill(mode == .fullColor ? Theme.accentText(entry.palettes.style) : .white)
                        .frame(width: geometry.size.width * progress.fraction)
                }
                    .frame(height: 3)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.isFree ? String(localized: "Heute ist nichts fällig")
            : String(localized: "\(progress.met) von \(progress.due) heute erledigt"))
    }
}
