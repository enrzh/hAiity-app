import Foundation

struct ReminderOccurrence: Equatable, Sendable {
    let day: String
    let dueDate: Date
}

struct ReminderOccurrenceState: Equatable, Sendable {
    let actionable: ReminderOccurrence?
    let overdueCount: Int
    let mostRecentCompleted: ReminderOccurrence?

    func isChecked(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let completed = mostRecentCompleted else { return false }
        let today = DayKey.key(for: now, calendar: calendar)
        return completed.day >= today && (actionable?.day ?? "9999-12-31") > completed.day
    }
}

enum ReminderOccurrenceEngine {
    private static let historyLimit = 10_000

    static func state(for reminder: Habit,
                      now: Date = .now,
                      calendar: Calendar = .current) -> ReminderOccurrenceState {
        let schedule = reminder.recurrence.schedule(calendar: calendar)
        let today = DayKey.key(for: now, calendar: calendar)
        let cursor = reminder.repeatsWhileIncomplete ? nil : reminder.reminderCursor
        let historyFloor = [reminder.createdAt, reminder.recurrence.start]
            .compactMap { $0 }
            .max() ?? reminder.createdAt
        let floor = [historyFloor, cursor]
            .compactMap { $0 }
            .max() ?? historyFloor

        let scheduledThroughToday: [String]
        if floor <= today {
            scheduledThroughToday = schedule.occurrences(in: floor...today,
                                                         limit: historyLimit)
        } else {
            scheduledThroughToday = []
        }

        let unfinished = scheduledThroughToday.filter {
            reminder.log[$0] == nil && !reminder.missedDays.contains($0)
        }
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
                guard let boundary = completionBoundary(day: day,
                                                        reminder: reminder,
                                                        calendar: calendar),
                      boundary <= now else { return }
                count += 1
            }
        } else if let actionableBoundary = actionable.flatMap({
            completionBoundary(day: $0.day, reminder: reminder, calendar: calendar)
        }), actionableBoundary <= now {
            overdueCount = 1
        } else {
            overdueCount = 0
        }

        let completed = reminder.log.keys
            .filter { $0 >= historyFloor && schedule.isScheduled($0) }
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

    /// Returns past scheduled days that were due before today and are still
    /// unanswered. Today stays actionable so the user can still complete it.
    static func missedDays(for reminder: Habit,
                           now: Date = .now,
                           calendar: Calendar = .current) -> [String] {
        let today = DayKey.key(for: now, calendar: calendar)
        guard let yesterday = DayKey.shifted(today, by: -1, calendar: calendar) else {
            return []
        }
        let schedule = reminder.recurrence.schedule(calendar: calendar)
        let cursor = reminder.repeatsWhileIncomplete ? nil : reminder.reminderCursor
        let floor = [reminder.createdAt, reminder.recurrence.start, cursor]
            .compactMap { $0 }
            .max() ?? reminder.createdAt
        guard floor <= yesterday else { return [] }

        return schedule.occurrences(in: floor...yesterday, limit: historyLimit)
            .filter { day in
                guard reminder.log[day] == nil,
                      !reminder.missedDays.contains(day),
                      let boundary = completionBoundary(day: day,
                                                         reminder: reminder,
                                                         calendar: calendar)
                else { return false }
                return boundary <= now
            }
    }

    /// Scheduled occurrences whose own boundary has passed without a user
    /// decision. An explicit time closes the occurrence at that local time;
    /// without one, the local day closes at the next midnight.
    static func expiredOccurrences(for habit: Habit,
                                   now: Date = .now,
                                   calendar: Calendar = .current) -> [String] {
        let today = DayKey.key(for: now, calendar: calendar)
        let cursor = habit.isReminder && !habit.repeatsWhileIncomplete
            ? habit.reminderCursor : nil
        let floor = [habit.createdAt, habit.recurrence.start, cursor]
            .compactMap { $0 }
            .max() ?? habit.createdAt
        guard floor <= today else { return [] }

        let schedule = habit.recurrence.schedule(calendar: calendar)
        return schedule.occurrences(in: floor...today, limit: historyLimit)
            .filter { day in
                guard habit.log[day] == nil,
                      !habit.missedDays.contains(day),
                      let boundary = completionBoundary(day: day,
                                                        reminder: habit,
                                                        calendar: calendar) else {
                    return false
                }
                return boundary <= now
            }
    }

    /// The local point at which an occurrence can no longer remain open.
    /// An entry without an explicit time belongs to the whole scheduled day;
    /// its boundary is the following local midnight, never the notification
    /// fallback used by `dueDate`.
    static func completionBoundary(day: String,
                                   reminder: Habit,
                                   calendar: Calendar = .current) -> Date? {
        guard let start = DayKey.date(from: day, calendar: calendar) else { return nil }
        if let minutes = Habit.sanitizedMinutes(reminder.timeMinutes ?? reminder.reminderMinutes) {
            return calendar.date(byAdding: .minute, value: minutes, to: start)
        }
        return calendar.date(byAdding: .day, value: 1, to: start)
    }

    /// The actionable/display date. A reminder without a time still needs a
    /// concrete date for notification planning and labels, so those callers
    /// retain the historical 09:00 fallback. Completion logic must use
    /// `completionBoundary` instead.
    static func dueDate(day: String,
                        reminder: Habit,
                        calendar: Calendar = .current) -> Date? {
        guard let start = DayKey.date(from: day, calendar: calendar) else { return nil }
        let minutes = Habit.sanitizedMinutes(reminder.timeMinutes ?? reminder.reminderMinutes)
            ?? Habit.defaultNotificationMinutes
        return calendar.date(byAdding: .minute, value: minutes, to: start)
    }

    static func cursorAfterCompleting(_ occurrence: ReminderOccurrence,
                                      reminder: Habit,
                                      now: Date = .now,
                                      calendar: Calendar = .current) -> String? {
        let schedule = reminder.recurrence.schedule(calendar: calendar)
        let today = DayKey.key(for: now, calendar: calendar)
        var candidate = schedule.next(after: occurrence.day)
        var remaining = historyLimit
        while let day = candidate, remaining > 0 {
            guard let boundary = completionBoundary(day: day,
                                                    reminder: reminder,
                                                    calendar: calendar) else {
                return nil
            }
            if day > today || boundary > now { return day }
            candidate = schedule.next(after: day)
            remaining -= 1
        }
        return nil
    }
}

enum ReminderOccurrenceText {
    static func label(for occurrence: ReminderOccurrence,
                      includesTime: Bool,
                      now: Date = .now,
                      calendar: Calendar = .current,
                      locale: Locale = .current) -> String {
        let due = occurrence.dueDate
        let dueDay = calendar.startOfDay(for: due)
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)

        let datePart: String
        if dueDay == today {
            datePart = String(localized: "Heute")
        } else if dueDay == tomorrow {
            datePart = String(localized: "Morgen")
        } else {
            datePart = formatted(due, format: "dd.MM.yyyy", calendar: calendar,
                                 locale: locale)
        }

        let value = includesTime
            ? "\(datePart), \(formatted(due, format: "HH:mm", calendar: calendar, locale: locale))"
            : datePart
        return due < now ? "\(String(localized: "Überfällig")) · \(value)" : value
    }

    private static func formatted(_ date: Date,
                                  format: String,
                                  calendar: Calendar,
                                  locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
