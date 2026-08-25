import Foundation

/// The filters shown in the Habits toolbar. Status is evaluated for the
/// current day in each habit's effective timezone; an item that is not
/// scheduled today cannot be classified as done or not done.
struct HabitListFilter: Equatable {
    enum Status: String, CaseIterable, Equatable {
        case all
        case done
        case notDone
    }

    enum ItemType: String, CaseIterable, Equatable {
        case all
        case habit
        case reminder
    }

    var todayOnly = false
    var status: Status = .all
    var itemType: ItemType = .all

    var isEmpty: Bool {
        !todayOnly && status == .all && itemType == .all
    }

    func matches(_ habit: Habit,
                 defaultTimeZoneIdentifier: String?,
                 now: Date = .now,
                 base: Calendar = .current) -> Bool {
        guard habit.archivedAt == nil else { return false }
        switch itemType {
        case .all: break
        case .habit where !habit.isTrackedHabit: return false
        case .reminder where !habit.isReminder: return false
        default: break
        }

        let calendar = HabitTimeZone.calendar(for: habit,
                                              defaultIdentifier: defaultTimeZoneIdentifier,
                                              base: base)
        let today = DayKey.key(for: now, calendar: calendar)
        let scheduledToday = habit.recurrence.isScheduled(on: today, calendar: calendar)
        if todayOnly && !scheduledToday { return false }

        switch status {
        case .all:
            return true
        case .done:
            return scheduledToday && completed(habit, day: today)
        case .notDone:
            return scheduledToday && !completed(habit, day: today)
        }
    }

    private func completed(_ habit: Habit, day: String) -> Bool {
        let value = habit.log[day] ?? 0
        switch habit.kind {
        case .checkbox:
            return value >= 1
        case .quantity:
            return value >= (habit.recurrence.target ?? 1)
        case .yesNo:
            return habit.isAffirmed(day)
        }
    }
}
