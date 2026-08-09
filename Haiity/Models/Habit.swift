import Foundation

/// Ein Habit ist ein Jahr aus Quadraten. `log` hält abgehakte Tage als
/// lokale Tagesschlüssel ("2026-08-09") — nie UTC, sonst rutscht ein
/// Abend-Check-in auf morgen.
struct Habit: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var emoji: String
    var createdAt: String
    /// Minuten seit Mitternacht für die tägliche Erinnerung; nil = aus.
    var reminderMinutes: Int?
    var log: [String: Int]

    init(name: String, emoji: String = "", reminderMinutes: Int? = nil) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.createdAt = DayKey.today()
        self.reminderMinutes = reminderMinutes
        self.log = [:]
    }
}

/// Lokale Tagesschlüssel und Datums-Arithmetik. Alles läuft über
/// `Calendar.current` in der lokalen Zeitzone — DST-sicher, weil nur mit
/// ganzen Kalendertagen gerechnet wird, nie mit 24-Stunden-Intervallen.
enum DayKey {
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func today(calendar: Calendar = .current) -> String {
        key(for: Date(), calendar: calendar)
    }

    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        return calendar.date(from: c)
    }

    static func shifted(_ key: String, by days: Int, calendar: Calendar = .current) -> String? {
        guard let d = date(from: key),
              let s = calendar.date(byAdding: .day, value: days, to: d) else { return nil }
        return Self.key(for: s, calendar: calendar)
    }
}

extension Habit {
    func isDone(_ key: String) -> Bool { log[key] != nil }

    /// Aktuelle Serie: zusammenhängende Tage bis heute (oder bis gestern,
    /// wenn heute noch offen ist).
    func streak(today: String = DayKey.today(), calendar: Calendar = .current) -> Int {
        var day = today
        if !isDone(day) {
            guard let y = DayKey.shifted(day, by: -1, calendar: calendar) else { return 0 }
            day = y
        }
        var n = 0
        while isDone(day) {
            n += 1
            guard let p = DayKey.shifted(day, by: -1, calendar: calendar) else { break }
            day = p
        }
        return n
    }

    /// Längste Serie über die gesamte Historie.
    func bestStreak(calendar: Calendar = .current) -> Int {
        let keys = log.keys.sorted()
        var best = 0, run = 0
        var prev: String?
        for k in keys {
            if let p = prev, DayKey.shifted(p, by: 1, calendar: calendar) == k { run += 1 }
            else { run = 1 }
            prev = k
            best = max(best, run)
        }
        return best
    }

    /// Zellintensität 1…4: längere zusammenhängende Läufe leuchten heller.
    func intensity(_ key: String, calendar: Calendar = .current) -> Int {
        guard isDone(key) else { return 0 }
        var run = 1
        var day = key
        while run < 8,
              let p = DayKey.shifted(day, by: -1, calendar: calendar),
              isDone(p) {
            run += 1
            day = p
        }
        return min(4, max(1, Int(ceil(Double(run) / 2))))
    }
}
