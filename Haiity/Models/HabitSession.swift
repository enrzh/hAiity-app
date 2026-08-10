import Foundation

/// Eine laufende Habit-Session: „ich mache das JETZT". Genau eine zur Zeit —
/// wer eine neue startet, beendet damit die alte (siehe
/// `HabitSessionManager`). Der Wert liegt als JSON in den App-Group-Defaults,
/// damit ein Force-Quit oder Relaunch die Session wiederfindet: die
/// Live-Aktivität überlebt den Prozess ohnehin, der Zustand hier muss es
/// auch.
struct HabitSession: Codable, Equatable {
    var habitID: UUID
    /// Der Tag, dem die Session gutgeschrieben wird — der Tag des STARTS.
    /// Eine Session über Mitternacht zählt für den Abend, an dem sie
    /// begonnen hat; alles andere hieße, dass ein 23:50-Lauf den falschen
    /// Tag abhakt.
    var day: String
    var startedAt: Date
    /// Geplante Dauer in Minuten zum ZEITPUNKT des Starts; nil = limitless.
    /// Eine Kopie und kein Durchgriff auf das Habit: die Live-Aktivität
    /// zeigt den Plan, gegen den gestartet wurde, auch wenn der Editor ihn
    /// zwischendurch ändert.
    var plannedMinutes: Int?
}

/// Reine Session-Arithmetik — alles, was die Live-Aktivität, die Intents und
/// die Stats über Zeit wissen müssen, ohne UI und ohne Uhr im Zustand.
enum HabitSessionMath {
    /// Nach dieser Spanne gilt eine Session als vergessen und wird beim
    /// nächsten App-Start still beendet, ohne den Tag abzuhaken. 8 Stunden:
    /// länger ist keine Session, das ist ein liegen gelassenes Telefon.
    static let staleCutoff: TimeInterval = 8 * 60 * 60

    static func isStale(startedAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(startedAt) >= staleCutoff
    }

    /// Verstrichene GANZE Minuten, mindestens 1: eine beendete Session von
    /// 40 Sekunden war eine Session, keine Null. Negative Spannen (Uhr
    /// zurückgestellt) fallen auf 1 statt auf Unsinn.
    static func elapsedMinutes(startedAt: Date, endedAt: Date) -> Int {
        max(1, Int(endedAt.timeIntervalSince(startedAt) / 60))
    }

    /// Wann der Plan erfüllt wäre; nil ohne Plan. Das Enddatum des
    /// Countdown-Intervalls der Live-Aktivität.
    static func plannedEnd(startedAt: Date, plannedMinutes: Int?) -> Date? {
        plannedMinutes.map { startedAt.addingTimeInterval(TimeInterval($0) * 60) }
    }

    /// Tatsächlich gegen geplant, gedeckelt bei 1; nil ohne Plan („limitless"
    /// hat keinen Fortschritt, nur eine Dauer).
    static func progress(actualMinutes: Int, plannedMinutes: Int?) -> Double? {
        guard let planned = plannedMinutes, planned > 0 else { return nil }
        return min(1, Double(max(0, actualMinutes)) / Double(planned))
    }

    /// Minuten als kurzer Satzbaustein: „25 Min", „1 Std", „1 Std 05 Min".
    /// EINE Stelle für die Schreibweise — Editor, Karte und Live-Aktivität
    /// dürfen dieselbe Dauer nicht verschieden buchstabieren.
    static func durationText(minutes: Int) -> String {
        let m = max(0, minutes)
        let hours = m / 60, rest = m % 60
        if hours == 0 { return String(localized: "\(m) Min") }
        if rest == 0 { return String(localized: "\(hours) Std") }
        return String(localized: "\(hours) Std \(rest) Min")
    }
}

/// Ablage der laufenden Session in den App-Group-Defaults — dort, weil die
/// Intents im selben Prozess wie die App laufen können, aber nicht müssen,
/// und beide Seiten denselben Stand sehen sollen. Defaults injizierbar, damit
/// Tests keine echte App-Group brauchen.
enum HabitSessionStorage {
    static let key = "activeHabitSession"

    static func defaults() -> UserDefaults {
        UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard
    }

    static func load(from defaults: UserDefaults = defaults()) -> HabitSession? {
        guard let raw = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HabitSession.self, from: raw)
    }

    static func save(_ session: HabitSession, to defaults: UserDefaults = defaults()) {
        if let raw = try? JSONEncoder().encode(session) {
            defaults.set(raw, forKey: key)
        }
    }

    static func clear(from defaults: UserDefaults = defaults()) {
        defaults.removeObject(forKey: key)
    }
}

/// Was das ENDE einer Session mit den Daten macht — pur und getestet,
/// getrennt vom Intent (dasselbe Muster wie `CheckOffLogic`).
enum HabitSessionCompletion {
    /// Fertig: der Tag geht durch denselben Abhak-Trichter wie jeder andere
    /// Check-in (`CheckOffLogic.apply` — idempotent, nimmt nie zurück), und
    /// die tatsächlichen Minuten landen in der Tages-Karte. Rückgabe: die
    /// gutgeschriebenen Minuten.
    @discardableResult
    static func finish(store: HabitStore, session: HabitSession, now: Date = Date()) -> Int {
        let minutes = HabitSessionMath.elapsedMinutes(startedAt: session.startedAt, endedAt: now)
        CheckOffLogic.apply(to: store, habitId: session.habitID, day: session.day)
        store.recordSessionMinutes(session.habitID, day: session.day, minutes: minutes)
        return minutes
    }
}
