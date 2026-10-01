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
        // A timezone has one day for this calculation; resolve it once even
        // when many habits inherit the same zone. Nothing survives this call.
        var days: [String?: (Calendar, String)] = [:]
        for habit in habits where habit.archivedAt == nil && habit.isTrackedHabit {
            let zone = habit.timeZoneIdentifier ?? defaultTimeZoneIdentifier
            let (itemCalendar, day): (Calendar, String)
            if let cached = days[zone] {
                (itemCalendar, day) = cached
            } else {
                itemCalendar = HabitTimeZone.calendar(identifier: zone, base: calendar)
                day = DayKey.key(for: now, calendar: itemCalendar)
                days[zone] = (itemCalendar, day)
            }
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
