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
    var now: Date = .now
    var calendar: Calendar = .current

    static func == (lhs: ReminderRow, rhs: ReminderRow) -> Bool {
        lhs.habit == rhs.habit
            && DayKey.key(for: lhs.now, calendar: lhs.calendar)
                == DayKey.key(for: rhs.now, calendar: rhs.calendar)
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
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)

            Button(action: onToggle) {
                Image(systemName: state.isChecked(now: now, calendar: calendar)
                      ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(state.isChecked(now: now, calendar: calendar)
                             ? Color.green : Color.secondary)
            .accessibilityLabel(String(localized: "Erledigt"))
            .accessibilityIdentifier("reminder-check-\(habit.id.uuidString)")
        }
        .padding(.horizontal, Theme.Metrics.cardPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 64)
        .appSurface()
        .contentShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                       style: .continuous))
    }

    private var state: ReminderOccurrenceState {
        ReminderOccurrenceEngine.state(for: habit, now: now, calendar: calendar)
    }

    private var subtitle: String {
        guard let occurrence = state.actionable else {
            return String(localized: "Kein weiterer Termin")
        }
        var text = ReminderOccurrenceText.label(
            for: occurrence,
            includesTime: Habit.sanitizedMinutes(habit.timeMinutes ?? habit.reminderMinutes) != nil,
            now: now,
            calendar: calendar
        )
        if state.overdueCount > 1 {
            text += " · +\(state.overdueCount - 1) \(String(localized: "offen"))"
        }
        return text
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
