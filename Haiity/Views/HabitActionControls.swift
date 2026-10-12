import SwiftUI

/// Presentation shared by Today, the collection and details. Writes stay in the root.
struct HabitActionControls: View {
    let habit: Habit
    let calendar: Calendar
    let now: Date
    let onToggleDay: (String) -> Void
    let onIncrement: () -> Void
    let onAnswer: (Bool) -> Void
    @Environment(\.palettes) private var palettes
    @Environment(\.colorScheme) private var scheme

    private var day: String { DayKey.key(for: now, calendar: calendar) }
    private var completed: Bool { GoalEngine.dayCounts(habit: habit, day: day, calendar: calendar) }
    private var style: PaletteStyle { palettes.style(for: habit) }

    @ViewBuilder var body: some View {
        switch habit.kind {
        case .checkbox:
            Button { onToggleDay(DayKey.today(calendar: calendar)) } label: {
                Label(String(localized: "Heute"), systemImage: completed ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(completed ? Theme.accentText(style) : Color.primary)
                    .frame(minWidth: Theme.Metrics.hit, minHeight: Theme.Metrics.hit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("check-today")
            .accessibilityLabel(completed ? String(localized: "✓ Erledigt") : String(localized: "Heute"))
            .accessibilityHint(completed ? String(localized: "Macht den heutigen Eintrag rückgängig.") : String(localized: "Markiert den heutigen Tag als erledigt."))
        case .quantity:
            let value = habit.log[day] ?? 0
            let target = habit.recurrence.effectiveTarget
            Button(action: onIncrement) {
                Label("\(value)/\(target)", systemImage: "plus")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(completed ? Theme.accentText(style) : Color.primary)
                    .padding(.horizontal, 10)
                    .frame(minWidth: Theme.Metrics.hit, minHeight: Theme.Metrics.hit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("check-today")
            .accessibilityLabel(String(localized: "Heute: \(value) von \(target)"))
            .accessibilityHint(String(localized: "Erhöht den Zähler um eins."))
        case .yesNo:
            HStack(spacing: 4) {
                answer(yes: true)
                answer(yes: false)
            }
        }
    }

    private func answer(yes: Bool) -> some View {
        let selected = yes ? completed : habit.isDeclined(day)
        let fill = yes ? Theme.accentFill(style) : Theme.color(style.negative(dark: scheme == .dark))
        return Button { onAnswer(yes) } label: {
            Label(yes ? String(localized: "Ja") : String(localized: "Nein"), systemImage: yes ? "checkmark" : "xmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 6)
                .frame(minWidth: Theme.Metrics.hit, minHeight: Theme.Metrics.hit)
                .background(selected ? fill : Color.clear, in: Capsule())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(yes ? "check-today" : "decline-today")
    }
}
