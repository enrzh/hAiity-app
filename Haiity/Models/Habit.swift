import Foundation

/// Ein Habit ist ein Jahr aus Quadraten. `log` hält Check-ins als lokale
/// Tagesschlüssel ("2026-08-09") — nie UTC, sonst rutscht ein
/// Abend-Check-in auf morgen. Log-Werte sind Zähler: 1 für Checkbox-Habits,
/// beliebige Zählstände für Mengen-Habits (ein Tag zählt ab `goal.target`).
struct Habit: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var emoji: String
    var createdAt: String
    /// Minuten seit Mitternacht für die tägliche Erinnerung; nil = aus.
    var reminderMinutes: Int?
    var log: [String: Int]
    /// Tagesschlüssel der Archivierung; nil = aktiv. Archivierte Habits
    /// behalten ihre Historie, verschwinden aber aus Liste und Summary.
    var archivedAt: String?
    /// Ziel-Definition; fehlt das Feld im JSON, lädt es als .daily ohne
    /// Ruhetage — v1-Dateien bleiben unverändert lesbar.
    var goal: Goal

    init(name: String, emoji: String = "", reminderMinutes: Int? = nil, goal: Goal = .daily) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.createdAt = DayKey.today()
        self.reminderMinutes = reminderMinutes
        self.log = [:]
        self.archivedAt = nil
        self.goal = goal
    }
}

/// Ziel eines Habits. Flaches Codable-Format, tolerant dekodiert:
/// `{"cadence":"weekly","times":3,"restDays":[1,7],"target":5}` —
/// fehlende Felder fallen auf .daily / keine Ruhetage / Checkbox zurück,
/// unbekannte `cadence`-Werte ebenfalls (Vorwärts-Kompatibilität).
struct Goal: Equatable {
    enum Cadence: Equatable {
        case daily
        /// 1…7 Check-ins pro Kalenderwoche (Woche des Nutzer-Kalenders).
        case weekly(times: Int)
    }

    var cadence: Cadence
    /// Ruhetage als Calendar-Wochentagsnummern (1 = Sonntag … 7 = Samstag).
    /// Nur für .daily bedeutsam: Ruhetage brechen keine Serie und zählen
    /// nicht mit.
    var restDays: Set<Int>
    /// Mengen-Habits: ein Tag zählt, wenn der Log-Wert >= target ist.
    /// nil = einfache Checkbox.
    var target: Int?

    init(cadence: Cadence = .daily, restDays: Set<Int> = [], target: Int? = nil) {
        self.cadence = cadence
        self.restDays = restDays
        self.target = target
    }

    static let daily = Goal()
    static func weekly(times: Int) -> Goal { Goal(cadence: .weekly(times: clampTimes(times))) }
    static func clampTimes(_ n: Int) -> Int { min(7, max(1, n)) }
}

extension Goal: Codable {
    private enum CodingKeys: String, CodingKey { case cadence, times, restDays, target }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decodeIfPresent(String.self, forKey: .cadence) ?? "daily"
        if kind == "weekly" {
            let times = try c.decodeIfPresent(Int.self, forKey: .times) ?? 1
            cadence = .weekly(times: Self.clampTimes(times))
        } else {
            cadence = .daily // unbekannte Werte tolerant als Standard lesen
        }
        let days = try c.decodeIfPresent([Int].self, forKey: .restDays) ?? []
        restDays = Set(days.filter { (1...7).contains($0) })
        let t = try c.decodeIfPresent(Int.self, forKey: .target)
        target = t.flatMap { $0 > 0 ? $0 : nil }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch cadence {
        case .daily:
            try c.encode("daily", forKey: .cadence)
        case .weekly(let times):
            try c.encode("weekly", forKey: .cadence)
            try c.encode(times, forKey: .times)
        }
        if !restDays.isEmpty { try c.encode(restDays.sorted(), forKey: .restDays) }
        if let target { try c.encode(target, forKey: .target) }
    }
}

extension Habit {
    private enum CodingKeys: String, CodingKey {
        case id, name, emoji, createdAt, reminderMinutes, log, archivedAt, goal
    }

    /// Tolerantes Dekodieren: v1-Dateien (ohne goal/archivedAt) laden
    /// unverändert — keine Migration auf der Platte nötig.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? ""
        createdAt = try c.decode(String.self, forKey: .createdAt)
        reminderMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderMinutes)
        log = try c.decodeIfPresent([String: Int].self, forKey: .log) ?? [:]
        archivedAt = try c.decodeIfPresent(String.self, forKey: .archivedAt)
        goal = try c.decodeIfPresent(Goal.self, forKey: .goal) ?? .daily
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(emoji, forKey: .emoji)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(reminderMinutes, forKey: .reminderMinutes)
        try c.encode(log, forKey: .log)
        try c.encodeIfPresent(archivedAt, forKey: .archivedAt)
        // Der Standard bleibt implizit — v2-Dateien sehen für einfache
        // Habits exakt aus wie v1 (plus Versionsnummer).
        if goal != .daily { try c.encode(goal, forKey: .goal) }
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

    /// Aktuelle Serie — dünner Durchgriff auf die GoalEngine, damit
    /// bestehende Views unverändert weiterlaufen.
    func streak(today: String = DayKey.today(), calendar: Calendar = .current) -> Int {
        GoalEngine.streak(habit: self, today: today, calendar: calendar)
    }

    /// Längste Serie über die gesamte Historie (rohe Log-Tage; Ziel-Semantik
    /// folgt in einer späteren Phase).
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

    /// Zellintensität 1…4 — dünner Durchgriff auf die GoalEngine.
    func intensity(_ key: String, calendar: Calendar = .current) -> Int {
        GoalEngine.intensity(habit: self, key: key, calendar: calendar)
    }
}
