import SwiftUI

struct HabitCard: View {
    let habit: Habit
    let onToggleDay: (String) -> Void
    let onEdit: () -> Void

    private var doneToday: Bool { habit.isDone(DayKey.today()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if !habit.emoji.isEmpty {
                    Text(habit.emoji).font(.title3)
                }
                Text(habit.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("🔥 \(habit.streak())")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(String(localized: "Serie: \(habit.streak()) Tage"))
                Button {
                    Theme.Haptics.check()
                    onToggleDay(DayKey.today())
                } label: {
                    Text(doneToday ? String(localized: "✓ Erledigt") : String(localized: "Heute"))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(doneToday ? Theme.accent : Color(.secondarySystemBackground),
                                    in: Capsule())
                        .foregroundStyle(doneToday ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("check-today")
                Button(action: onEdit) {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "\(habit.name) bearbeiten"))
                .accessibilityIdentifier("edit-habit")
            }
            ContributionGrid(habit: habit, onToggle: onToggleDay)
            if habit.reminderMinutes != nil {
                Label(reminderText, systemImage: "bell")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("habit-card")
    }

    private var reminderText: String {
        guard let m = habit.reminderMinutes else { return "" }
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}
