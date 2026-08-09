import SwiftUI

/// Flache Habit-Karte: das Raster ist der Held, drumherum so wenig Chrom wie
/// möglich. Checkbox-Habits togglen heute; Mengen-Habits zählen hoch
/// ("2/3") und lassen sich per Langdruck zurücksetzen.
struct HabitCard: View {
    let habit: Habit
    let onToggleDay: (String) -> Void
    let onIncrement: () -> Void
    let onClear: () -> Void
    let onEdit: () -> Void
    let onArchive: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var today: String { DayKey.today() }
    private var doneToday: Bool { GoalEngine.dayCounts(habit: habit, day: today) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ContributionGrid(habit: habit, onToggle: onToggleDay)
            if habit.reminderMinutes != nil {
                Label(reminderText, systemImage: "bell")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            ShareLink(item: HabitShareImage(habit: habit, dark: scheme == .dark),
                      preview: SharePreview(habit.name)) {
                Label(String(localized: "Als Bild teilen"), systemImage: "square.and.arrow.up")
            }
            Button(action: onEdit) {
                Label(String(localized: "Bearbeiten"), systemImage: "pencil")
            }
            Button(action: onArchive) {
                Label(String(localized: "Archivieren"), systemImage: "archivebox")
            }
        }
        .accessibilityIdentifier("habit-card")
    }

    /// Kopfzeile. Ab den Accessibility-Größen bricht sie um: der Name
    /// bekommt die volle Breite, Serie und Heute-Knopf rutschen darunter.
    /// In einer Zeile bliebe bei XXL nur noch "La…" vom Habit-Namen übrig.
    @ViewBuilder
    private var header: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                nameLine
                HStack(spacing: 8) {
                    streakLabel
                    Spacer(minLength: 8)
                    todayButton
                    editButton
                }
            }
        } else {
            HStack(spacing: 8) {
                nameLine
                Spacer(minLength: 8)
                streakLabel
                todayButton
                editButton
            }
        }
    }

    private var nameLine: some View {
        HStack(spacing: 8) {
            if !habit.emoji.isEmpty {
                Text(habit.emoji).font(.body)
            }
            Text(habit.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
        }
    }

    private var streakLabel: some View {
        Text("🔥 \(habit.streak())")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityLabel(String(localized: "Serie: \(habit.streak()) Tage"))
    }

    private var editButton: some View {
        Button(action: onEdit) {
            Image(systemName: "ellipsis")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "\(habit.name) bearbeiten"))
        .accessibilityIdentifier("edit-habit")
    }

    /// Heute-Kontrolle: Checkbox toggelt, Mengenziel zählt hoch.
    @ViewBuilder
    private var todayButton: some View {
        if let target = habit.goal.target {
            let value = habit.log[today] ?? 0
            Button {
                Theme.Haptics.check()
                onIncrement()
            } label: {
                Text(verbatim: "\(value)/\(target)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(doneToday ? Theme.accentFill : Color(.tertiarySystemFill), in: Capsule())
                    .foregroundStyle(doneToday ? .white : .primary)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive, action: onClear) {
                    Label(String(localized: "Zurücksetzen"), systemImage: "arrow.counterclockwise")
                }
            }
            .accessibilityLabel(String(localized: "Heute: \(value) von \(target)"))
            .accessibilityIdentifier("check-today")
        } else {
            Button {
                Theme.Haptics.check()
                onToggleDay(today)
            } label: {
                Text(doneToday ? String(localized: "✓ Erledigt") : String(localized: "Heute"))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(doneToday ? Theme.accentFill : Color(.tertiarySystemFill), in: Capsule())
                    .foregroundStyle(doneToday ? .white : .primary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("check-today")
        }
    }

    private var reminderText: String {
        guard let m = habit.reminderMinutes else { return "" }
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}
