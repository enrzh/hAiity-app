import Foundation

/// Reine Statistik-Mathematik für die Statistik-Ansicht. Wie die GoalEngine
/// ohne Store-Abhängigkeit und mit explizitem Calendar — vollständig
/// unit-testbar. "Zählend" heißt überall GoalEngine.dayCounts: Checkbox ab 1,
/// Mengen-Habit ab Zielwert.
enum StatsMath {

    /// Zählende Tage pro Kalendermonat — genau `months` Einträge, älteste
    /// zuerst, endend im Monat von `today`. Müll-Schlüssel und Monate
    /// außerhalb des Fensters (auch Zukunft) werden ignoriert.
    static func monthlyCounts(habit: Habit, months: Int,
                              today: String = DayKey.today(),
                              calendar: Calendar = .current) -> [Int] {
        guard months > 0, let anchor = yearMonth(today) else { return [] }
        var counts = Array(repeating: 0, count: months)
        for key in habit.log.keys {
            guard let ym = yearMonth(key),
                  GoalEngine.dayCounts(habit: habit, day: key, calendar: calendar) else { continue }
            // 0 = aktueller Monat, 1 = Vormonat, …; negativ = Zukunft.
            let offset = (anchor.year - ym.year) * 12 + (anchor.month - ym.month)
            guard (0..<months).contains(offset) else { continue }
            counts[months - 1 - offset] += 1
        }
        return counts
    }

    /// Summe aller zählenden Tage über die übergebenen Habits.
    static func totalCheckIns(_ habits: [Habit], calendar: Calendar = .current) -> Int {
        habits.reduce(0) { sum, habit in
            sum + habit.log.keys.filter {
                GoalEngine.dayCounts(habit: habit, day: $0, calendar: calendar)
            }.count
        }
    }

    /// "2026-08-09" -> (2026, 8); nil bei allem, was kein Tagesschlüssel ist.
    static func yearMonth(_ key: String) -> (year: Int, month: Int)? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }
}
