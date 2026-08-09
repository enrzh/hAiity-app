import Foundation

/// Ein Habit ist ein Jahr aus Quadraten. `log` hält Check-ins als lokale
/// Tagesschlüssel ("2026-08-09") — nie UTC, sonst rutscht ein
/// Abend-Check-in auf morgen. Log-Werte sind Zähler: 1 für Checkbox-Habits,
/// beliebige Zählstände für Mengen-Habits (ein Tag zählt ab
/// `recurrence.target`).
struct Habit: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var emoji: String
    var createdAt: String
    /// Minuten seit Mitternacht für die Erinnerung; nil = aus.
    var reminderMinutes: Int?
    var log: [String: Int]
    /// Tagesschlüssel der Archivierung; nil = aktiv. Archivierte Habits
    /// behalten ihre Historie, verschwinden aber aus Liste und Summary.
    var archivedAt: String?
    /// Wiederholungsregel samt Mengenziel. Fehlt das Feld im JSON, lädt es
    /// als „täglich" — v1-Dateien bleiben unverändert lesbar; ein Alt-Ziel
    /// (`{"cadence":…}`) wird beim Lesen migriert (siehe `Recurrence`).
    var recurrence: Recurrence
    /// Eigene Rasterfarbe; nil = die App-Palette (Standardfall). Bewusst
    /// eine SEPARATE Einstellung von der globalen Palette: wer alles blau
    /// will, stellt es einmal um; wer EIN Habit hervorheben will, färbt nur
    /// dieses. Zeigt entweder auf eine eingebaute Familie oder auf eine
    /// eigene Farbe des Nutzers.
    var palette: PaletteRef?

    init(name: String,
         emoji: String = "",
         reminderMinutes: Int? = nil,
         recurrence: Recurrence = .daily) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.createdAt = DayKey.today()
        self.reminderMinutes = reminderMinutes
        self.log = [:]
        self.archivedAt = nil
        self.recurrence = recurrence
        self.palette = nil
    }

    /// Bequemer Weg für Alt-Ziele: legt das Habit mit der MIGRIERTEN Regel
    /// an — genau der Pfad, den auch eine ausgelieferte Datei nimmt.
    init(name: String, emoji: String = "", reminderMinutes: Int? = nil, legacy: LegacyGoal) {
        self.init(name: name, emoji: emoji, reminderMinutes: reminderMinutes,
                  recurrence: .from(legacy: legacy))
    }
}

extension Habit {
    private enum CodingKeys: String, CodingKey {
        case id, name, emoji, createdAt, reminderMinutes, log, archivedAt, goal, palette
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
        // EIN Schlüssel für beide Formate: `Recurrence` erkennt am fehlenden
        // `freq`, dass dort ein Alt-Ziel steht, und migriert es. Ein kaputtes
        // Ziel darf das Habit nicht kosten — dann eben täglich.
        recurrence = ((try? c.decodeIfPresent(Recurrence.self, forKey: .goal)) ?? nil) ?? .daily
        // Unbekannte Paletten (Datei aus einer neueren Version) lesen als
        // "keine Übersteuerung" — nie als Fehler, sonst verliert ein
        // älterer Build beim nächsten Speichern das ganze Habit.
        palette = (try c.decodeIfPresent(String.self, forKey: .palette))
            .flatMap(PaletteRef.init(rawValue:))
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
        // Der Standard bleibt implizit — Dateien sehen für einfache Habits
        // exakt aus wie v1 (plus Versionsnummer). Alles andere schreibt die
        // neue Regel UND, wo möglich, ihren Alt-Spiegel unter denselben
        // Schlüssel `goal` — ein ausgelieferter Build liest die Datei damit
        // unverändert weiter (kein Versionssprung, der ihn aussperrt).
        if recurrence != .daily { try c.encode(recurrence, forKey: .goal) }
        try c.encodeIfPresent(palette?.rawValue, forKey: .palette)
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

    /// Längste Serie über die gesamte Historie — dünner Durchgriff auf die
    /// GoalEngine, exakt wie `streak`. Die Ziel-Semantik (Mengenziel,
    /// Termine, flexible Perioden) liegt dort, damit "Best" dieselbe Einheit
    /// misst wie die laufende Serie.
    func bestStreak(today: String = DayKey.today(), calendar: Calendar = .current) -> Int {
        GoalEngine.bestStreak(habit: self, today: today, calendar: calendar)
    }

    /// Zellintensität 1…4 — dünner Durchgriff auf die GoalEngine.
    func intensity(_ key: String, calendar: Calendar = .current) -> Int {
        GoalEngine.intensity(habit: self, key: key, calendar: calendar)
    }
}
