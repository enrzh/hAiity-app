import Foundation

struct ReminderOccurrence: Equatable, Sendable {
    let day: String
    let dueDate: Date
}

struct ReminderOccurrenceState: Equatable, Sendable {
    let actionable: ReminderOccurrence?
    let overdueCount: Int
    let mostRecentCompleted: ReminderOccurrence?
}

enum ReminderOccurrenceEngine {
    private static let historyLimit = 10_000

    static func state(for reminder: Habit,
                      now: Date = .now,
                      calendar: Calendar = .current) -> ReminderOccurrenceState {
        let schedule = reminder.recurrence.schedule(calendar: calendar)
        let today = DayKey.key(for: now, calendar: calendar)
        let floor = [reminder.createdAt, reminder.recurrence.start, reminder.reminderCursor]
            .compactMap { $0 }
            .max() ?? reminder.createdAt

        let scheduledThroughToday: [String]
        if floor <= today {
            scheduledThroughToday = schedule.occurrences(in: floor...today,
                                                         limit: historyLimit)
        } else {
            scheduledThroughToday = []
        }

        let unfinished = scheduledThroughToday.filter { reminder.log[$0] == nil }
        let actionableDay = unfinished.first ?? nextUnfinishedDay(
            schedule: schedule,
            reminder: reminder,
            floor: floor,
            today: today
        )
        let actionable = actionableDay.flatMap {
            occurrence(day: $0, reminder: reminder, calendar: calendar)
        }

        let overdueCount: Int
        if reminder.repeatsWhileIncomplete {
            overdueCount = unfinished.reduce(into: 0) { count, day in
                guard let due = dueDate(day: day, reminder: reminder, calendar: calendar),
                      due <= now else { return }
                count += 1
            }
        } else if let actionable, actionable.dueDate <= now {
            overdueCount = 1
        } else {
            overdueCount = 0
        }

        let completed = reminder.log.keys
            .filter { $0 >= floor && schedule.isScheduled($0) }
            .sorted()
            .last
            .flatMap { occurrence(day: $0, reminder: reminder, calendar: calendar) }

        return ReminderOccurrenceState(actionable: actionable,
                                       overdueCount: overdueCount,
                                       mostRecentCompleted: completed)
    }

    private static func nextUnfinishedDay(schedule: Recurrence.Schedule,
                                          reminder: Habit,
                                          floor: String,
                                          today: String) -> String? {
        var candidate = floor > today
            ? schedule.first(onOrAfter: floor)
            : schedule.next(after: today)
        var remaining = historyLimit
        while let day = candidate, reminder.log[day] != nil, remaining > 0 {
            candidate = schedule.next(after: day)
            remaining -= 1
        }
        return candidate
    }

    private static func occurrence(day: String,
                                   reminder: Habit,
                                   calendar: Calendar) -> ReminderOccurrence? {
        dueDate(day: day, reminder: reminder, calendar: calendar)
            .map { ReminderOccurrence(day: day, dueDate: $0) }
    }

    static func dueDate(day: String,
                        reminder: Habit,
                        calendar: Calendar = .current) -> Date? {
        guard let start = DayKey.date(from: day, calendar: calendar) else { return nil }
        let minutes = Habit.sanitizedMinutes(reminder.timeMinutes ?? reminder.reminderMinutes) ?? 0
        return calendar.date(byAdding: .minute, value: minutes, to: start)
    }
}
