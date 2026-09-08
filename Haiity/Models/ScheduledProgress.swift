import Foundation

/// Daily appointments and flexible period goals are different units. Keep
/// them separate so a three-times-weekly goal never becomes seven obligations.
enum ScheduledProgress {
    struct Today: Equatable {
        var completed = 0
        var scheduled = 0
        var flexibleCompleted = 0
        var flexible = 0

        var fraction: Double {
            scheduled > 0 ? Double(completed) / Double(scheduled) : 0
        }
    }

    static func today(habits: [Habit], defaultTimeZoneIdentifier: String?,
                      now: Date = .now, calendar: Calendar = .current) -> Today {
        var result = Today()
        for habit in habits where habit.archivedAt == nil && habit.isTrackedHabit {
            let itemCalendar = HabitTimeZone.calendar(for: habit,
                defaultIdentifier: defaultTimeZoneIdentifier, base: calendar)
            let day = DayKey.key(for: now, calendar: itemCalendar)
            guard GoalEngine.isScheduled(habit: habit, day: day, calendar: itemCalendar) else { continue }
            if habit.recurrence.isFlexible {
                result.flexible += 1
                if GoalEngine.periodSatisfied(habit: habit, day: day, today: day, calendar: itemCalendar) {
                    result.flexibleCompleted += 1
                }
            } else {
                result.scheduled += 1
                if GoalEngine.dayCounts(habit: habit, day: day, calendar: itemCalendar) {
                    result.completed += 1
                }
            }
        }
        return result
    }
}
