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
        // Müllabfuhr an der Grenze: was formal kein Tag ist oder keinen
        // positiven Zähler hat, kommt gar nicht erst in den Speicher.
        // Bewusst NUR strukturell — ein Schlüssel von morgen (Gerät in einer
        // Zeitzone voraus) oder aus 1900 bleibt erhalten und wird erst in
        // der Rechen-Schicht ignoriert, statt hier Daten zu verlieren.
        let rawLog = try c.decodeIfPresent([String: Int].self, forKey: .log) ?? [:]
        log = rawLog.filter { $0.value >= 1 && DayKey.isValid($0.key) }
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
    /// Wie weit ein importierter Tag zurückliegen darf, bevor er als Müll
    /// gilt. Bewusst als Tages-SPANNE und nicht als Jahreszahl: in einem
    /// nicht-gregorianischen Nutzerkalender (Hidschri, äthiopisch) wäre
    /// jede feste Jahresgrenze falsch.
    static let plausibleSpanDays = 366 * 30

    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 1, c.day ?? 1)
    }

    static func today(calendar: Calendar = .current) -> String {
        key(for: Date(), calendar: calendar)
    }

    /// STRIKT: nur exakt `JJJJ-MM-TT` aus ASCII-Ziffern, und nur, wenn der
    /// Kalender daraus genau denselben Schlüssel zurückrechnet. Ohne den
    /// Rückweg würde `Calendar.date(from:)` Unmögliches stillschweigend
    /// überrollen — "2026-13-45" wäre plötzlich der 14.02.2027 und ein
    /// kaputter Import würde echte Daten erfinden.
    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        guard let parts = components(key) else { return nil }
        var c = DateComponents()
        c.year = parts.year; c.month = parts.month; c.day = parts.day
        guard let date = calendar.date(from: c),
              Self.key(for: date, calendar: calendar) == key else { return nil }
        return date
    }

    /// Ist der Schlüssel überhaupt ein echtes Datum? ("quatsch",
    /// "2026-13-45", "2026-02-30", "" → nein.)
    static func isValid(_ key: String, calendar: Calendar = .current) -> Bool {
        date(from: key, calendar: calendar) != nil
    }

    /// Echtes Datum UND nicht in der Zukunft UND nicht absurd weit zurück.
    /// Genau das, was als Check-in zählen darf.
    static func isPlausible(_ key: String,
                            today: String = DayKey.today(),
                            calendar: Calendar = .current) -> Bool {
        guard let date = date(from: key, calendar: calendar), key <= today else { return false }
        guard let floor = plausibleFloor(today: today, calendar: calendar) else { return true }
        return date >= floor
    }

    /// Frühester noch plausibler Tag — einmal berechnen, dann in Schleifen
    /// wiederverwenden.
    static func plausibleFloor(today: String = DayKey.today(), calendar: Calendar = .current) -> Date? {
        guard let todayDate = date(from: today, calendar: calendar) else { return nil }
        return calendar.date(byAdding: .day, value: -plausibleSpanDays, to: todayDate)
    }

    static func shifted(_ key: String, by days: Int, calendar: Calendar = .current) -> String? {
        guard let d = date(from: key, calendar: calendar),
              let s = calendar.date(byAdding: .day, value: days, to: d) else { return nil }
        return Self.key(for: s, calendar: calendar)
    }

    /// "2026-08-09" -> (2026, 8, 9); nil bei allem, was formal kein
    /// Tagesschlüssel ist (Länge, Trennzeichen, ASCII-Ziffern).
    static func components(_ key: String) -> (year: Int, month: Int, day: Int)? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        return (y, m, d)
    }
}

extension Habit {
    func isDone(_ key: String) -> Bool { (log[key] ?? 0) >= 1 }

    /// Log-Schlüssel, mit denen überhaupt gerechnet werden darf: echtes
    /// Datum, Wert ≥ 1, nicht in der Zukunft, nicht Jahrzehnte zurück.
    /// EINE Stelle für die ganze Müllabfuhr — Serien, Statistik und
    /// Gesamtzahlen hängen alle hier dran, damit eine importierte oder
    /// synchronisierte Datei mit "quatsch", "2026-13-45", "1900-01-01"
    /// oder Werten ≤ 0 nichts verfälschen kann.
    func validDays(today: String = DayKey.today(), calendar: Calendar = .current) -> [String] {
        let floor = DayKey.plausibleFloor(today: today, calendar: calendar)
        return log.compactMap { key, value in
            guard value >= 1, key <= today,
                  let date = DayKey.date(from: key, calendar: calendar) else { return nil }
            if let floor, date < floor { return nil }
            return key
        }
    }

    /// Zählende Tage (Ziel-Semantik) über die gesamte plausible Historie —
    /// das ist die Zahl, die "Gesamt" und "Tage insgesamt" meinen. Nicht
    /// `log.count`: das zählt auch Müll und unerfüllte Mengen-Tage mit.
    func checkInCount(today: String = DayKey.today(), calendar: Calendar = .current) -> Int {
        validDays(today: today, calendar: calendar).filter {
            GoalEngine.dayCounts(habit: self, day: $0, calendar: calendar)
        }.count
    }

    /// Aktuelle Serie — dünner Durchgriff auf die GoalEngine, damit
    /// bestehende Views unverändert weiterlaufen.
    func streak(today: String = DayKey.today(), calendar: Calendar = .current) -> Int {
        GoalEngine.streak(habit: self, today: today, calendar: calendar)
    }

    /// Längste Serie über die gesamte Historie (rohe Log-Tage; Ziel-Semantik
    /// folgt in einer späteren Phase). Müll-Schlüssel fliegen vorher raus —
    /// sonst zählte "quatsch" als eigener Ein-Tages-Lauf.
    func bestStreak(today: String = DayKey.today(), calendar: Calendar = .current) -> Int {
        let keys = validDays(today: today, calendar: calendar).sorted()
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
