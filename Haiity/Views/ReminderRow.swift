import SwiftUI

enum ItemPresentation: Equatable {
    case habitCard
    case reminderRow

    static func forItem(_ item: Habit) -> ItemPresentation {
        item.isReminder ? .reminderRow : .habitCard
    }
}

struct ReminderRow: View, Equatable {
    static let rowHeight: CGFloat = 64

    let habit: Habit
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onRevert: () -> Void
    var onDelete: () -> Void = {}
    var now: Date = .now
    var calendar: Calendar = .current
    var leadingSwipe: [RevealAction] = []
    var trailingSwipe: [RevealAction] = []

    static func == (lhs: ReminderRow, rhs: ReminderRow) -> Bool {
        lhs.habit == rhs.habit
            && DayKey.key(for: lhs.now, calendar: lhs.calendar)
                == DayKey.key(for: rhs.now, calendar: rhs.calendar)
            && lhs.leadingSwipe == rhs.leadingSwipe
            && lhs.trailingSwipe == rhs.trailingSwipe
            && lhs.calendar.timeZone.identifier == rhs.calendar.timeZone.identifier
    }

    var body: some View {
        rowContent
            .contextMenu {
                Button(action: onEdit) {
                    Label(String(localized: "Bearbeiten"), systemImage: "pencil")
                }
                Button(action: onRevert) {
                    Label(String(localized: "Rückgängig"),
                          systemImage: "arrow.uturn.backward")
                }
                Button(action: onArchive) {
                    Label(String(localized: "Archivieren"), systemImage: "archivebox")
                }
                Button(role: .destructive, action: onDelete) {
                    Label(String(localized: "Löschen"), systemImage: "trash")
                }
            }
            // Compact reminders use the system interaction. It owns the
            // touch arbitration with List and keeps the action buttons
            // tappable on iOS 27.
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                ForEach(leadingSwipe) { action in
                    swipeButton(action)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                ForEach(trailingSwipe) { action in
                    swipeButton(action)
                }
            }
            .accessibilityRevealActions(leadingSwipe + trailingSwipe)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("reminder-row-\(habit.id.uuidString)")
    }

    private func swipeButton(_ action: RevealAction) -> some View {
        Button(action: action.handler) {
            Label(action.title, systemImage: action.symbol)
        }
        .tint(action.tint)
        .accessibilityIdentifier("reveal-action-\(action.operation.rawValue)")
    }

    private var rowContent: some View {
        rowLayout
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
            .appSurface()
            .contentShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                           style: .continuous))
    }

    private var rowLayout: some View {
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
            .accessibilityValue(state.isChecked(now: now, calendar: calendar)
                                ? String(localized: "Erledigt")
                                : String(localized: "Offen"))
            .accessibilityIdentifier("reminder-check-\(habit.id.uuidString)")
        }
        .padding(.horizontal, Theme.Metrics.cardPadding)
        .padding(.vertical, 10)
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

}
