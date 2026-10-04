import Foundation

/// Device-local Heute/Alle choice. Status and type filters stay session-only;
/// this picker is a viewing mode and must survive the next launch.
enum HabitListFilterPreferences {
    static let todayOnlyKey = "habitListFilterTodayOnly"

    static var defaults: UserDefaults {
        #if DEBUG && targetEnvironment(simulator)
        if DesignFixture.scenario != nil {
            return UserDefaults(suiteName: "haiity.design-fixture.filters") ?? .standard
        }
        #endif
        return UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard
    }

    static func todayOnly(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: todayOnlyKey)
    }

    static func setTodayOnly(_ value: Bool, in defaults: UserDefaults) {
        defaults.set(value, forKey: todayOnlyKey)
    }

    static func persistTodayOnly(_ value: Bool) {
        setTodayOnly(value, in: defaults)
    }
}

/// The filters shown in the Habits toolbar. Status is evaluated for the
/// current day in each habit's effective timezone. Heute keeps what is
/// scheduled today, and also an unfinished reminder whose due time has
/// already passed: that reminder is postponed work. Erledigt is a scheduled
/// item that is complete and not overdue. Nicht erledigt includes the
/// overdue reminder.
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

    static func restored(from defaults: UserDefaults? = nil) -> HabitListFilter {
        let resolved = defaults ?? HabitListFilterPreferences.defaults
        return HabitListFilter(todayOnly: HabitListFilterPreferences.todayOnly(in: resolved))
    }

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
        let overdue = isOverdueReminder(habit, now: now, calendar: calendar)
        if todayOnly && !scheduledToday && !overdue { return false }
        // The canonical answer to "is this done?", from the engine the rest of
        // the app asks — not a private second opinion. This used to be a copy,
        // and two implementations of a completion test are one of them changing.
        let done = GoalEngine.dayCounts(habit: habit, day: today, calendar: calendar)

        switch status {
        case .all:
            return true
        case .done:
            return scheduledToday && !overdue && done
        case .notDone:
            return overdue || (scheduledToday && !done)
        }
    }

    /// A reminder still open after its due time. The list treats that as
    /// postponed work, including when the scheduled day is already in the past.
    private func isOverdueReminder(_ habit: Habit, now: Date, calendar: Calendar) -> Bool {
        guard habit.isReminder else { return false }
        return ReminderOccurrenceEngine.state(for: habit,
                                              now: now,
                                              calendar: calendar).overdueCount > 0
    }

}
