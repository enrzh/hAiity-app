import SwiftUI

enum ItemPresentation: Equatable {
    case habitCard
    case reminderRow

    static func forItem(_ item: Habit) -> ItemPresentation {
        item.isReminder ? .reminderRow : .habitCard
    }
}

struct ReminderRow: View, Equatable {
    let habit: Habit
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onArchive: () -> Void

    static func == (lhs: ReminderRow, rhs: ReminderRow) -> Bool {
        lhs.habit == rhs.habit
    }

    private var previewWidth: CGFloat {
        HabitCard.previewMetrics(windowWidth: HabitCard.windowWidth()).width
    }

    var body: some View {
        rowContent
            .background {
                GraphContextMenu(cardRadius: Theme.Metrics.cardRadius,
                                 previewWidth: previewWidth,
                                 preview: { AnyView(reminderPreview) },
                                 actions: menuActions,
                                 commit: onEdit)
            }
    }

    private var rowContent: some View {
        HStack(spacing: Theme.Metrics.gap) {
            HStack(spacing: Theme.Metrics.gap) {
                if habit.emoji.isEmpty {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 28)
                } else {
                    Text(habit.emoji)
                        .font(.title3)
                        .frame(width: 28)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    Text(RecurrenceText.summary(
                        habit.recurrence,
                        timeMinutes: habit.timeMinutes ?? habit.reminderMinutes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)

            Button(action: onToggle) {
                Image(systemName: habit.isDone(DayKey.today())
                      ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(habit.isDone(DayKey.today()) ? Color.green : Color.secondary)
            .accessibilityLabel(String(localized: "Erledigt"))
            .accessibilityIdentifier("reminder-check-\(habit.id.uuidString)")
        }
        .padding(.horizontal, Theme.Metrics.cardPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                         style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                       style: .continuous))
    }

    private var reminderPreview: some View {
        rowContent
            .frame(width: previewWidth)
            .accessibilityIdentifier("reminder-preview")
    }

    private var menuActions: [GraphMenuAction] {
        [GraphMenuAction(title: String(localized: "Bearbeiten"),
                         symbol: "pencil", handler: onEdit),
         GraphMenuAction(title: String(localized: "Archivieren"),
                         symbol: "archivebox", handler: onArchive)]
    }
}
