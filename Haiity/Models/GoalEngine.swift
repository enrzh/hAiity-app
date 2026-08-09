import Foundation

/// Reine Ziel-Logik: Serien, Abschlussquoten und Zellintensität für alle
/// Zielarten (täglich, Ruhetage, n×/Woche, Mengenziele). Keine
/// Store-Abhängigkeit; jede Funktion nimmt wie DayKey einen Calendar —
/// Wochen respektieren damit `firstWeekday` des Nutzers.
enum GoalEngine {

    // MARK: – Tages-Semantik

    /// Zählt der Tag? Checkbox: Wert >= 1. Mengen-Habit: Wert >= target.
    /// Ruhetage werden hier bewusst NICHT behandelt — sie sind in Serien-
    /// und Quoten-Logik "frei" (brechen nichts, zählen nichts).
    static func dayCounts(habit: Habit, day: String, calendar: Calendar = .current) -> Bool {
        let value = habit.log[day] ?? 0
        // `components` ist ein reiner String-Check (kein Kalender) — billig
        // genug für den heißen Pfad und wirft offensichtlichen Müll raus.
        // Die volle Plausibilität (echtes Datum, nicht Zukunft, nicht 1900)
        // prüft `Habit.validDays` an allen Stellen, die über Log-Schlüssel
        // iterieren.
        guard value >= 1, DayKey.components(day) != nil else { return false }
        if let target = habit.goal.target { return value >= target }
        return true
    }

    /// Ist die KALENDERWOCHE, in der `day` liegt, erfüllt?
    ///
    /// Bei täglicher Kadenz ist das schlicht der Tag selbst. Bei
    /// Wochen-Kadenz zählt die Anzahl zählender Tage in dieser Woche gegen
    /// `times`.
    ///
    /// **Fester Wochentag (`goal.weekday`):** `times` ist dann per
    /// Normalisierung 1 — die Woche ist also erfüllt, sobald IRGENDEIN Tag
    /// dieser Woche zählt. Der Check-in am festgelegten Tag erfüllt sie,
    /// einer am Tag davor oder danach aber genauso. Der feste Tag ist eine
    /// Verabredung für die Erinnerung, keine Prüfung: früh oder spät
    /// abzuhaken darf keine Serie kosten. (Gegenentwurf wäre „nur der
    /// Dienstag zählt" — das würde ausgerechnet die bestrafen, die die
    /// Woche trotzdem geschafft haben.)
    static func weekSatisfied(habit: Habit,
                              day: String,
                              today: String = DayKey.today(),
                              calendar: Calendar = .current) -> Bool {
        guard case .weekly(let times) = habit.goal.cadence else {
            return dayCounts(habit: habit, day: day, calendar: calendar)
        }
        guard let date = DayKey.date(from: day, calendar: calendar),
              let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return false }
        let counts = weeklyCounts(habit: habit, today: today, calendar: calendar)
        return (counts[week.start] ?? 0) >= times
    }

    /// Ruhetag? Nur für .daily bedeutsam; Wochentage nach Calendar-Nummern
    /// (1 = Sonntag … 7 = Samstag).
    static func isRestDay(habit: Habit, day: String, calendar: Calendar = .current) -> Bool {
        guard case .daily = habit.goal.cadence,
              !habit.goal.restDays.isEmpty,
              let date = DayKey.date(from: day, calendar: calendar) else { return false }
        return habit.goal.restDays.contains(calendar.component(.weekday, from: date))
    }

    // MARK: – Serien

    static func streak(habit: Habit, today: String = DayKey.today(), calendar: Calendar = .current) -> Int {
        switch habit.goal.cadence {
        case .daily:
            return dailyStreak(habit: habit, today: today, calendar: calendar)
        case .weekly(let times):
            return weeklyStreak(habit: habit, times: times, today: today, calendar: calendar)
        }
    }

    /// Tägliche Serie: zusammenhängende zählende Tage bis heute. Ruhetage
    /// brechen nie und zählen nie mit; ein Check-in AN einem Ruhetag zählt
    /// trotzdem. Heute darf noch offen sein (Serie lebt bis gestern).
    private static func dailyStreak(habit: Habit, today: String, calendar: Calendar) -> Int {
        // Untere Grenze hält die Schleife endlich — auch wenn alle sieben
        // Wochentage Ruhetage sind, endet der Rückwärtslauf am Anfang der
        // Historie. Nur PLAUSIBLE Tage zählen als Grenze: ein importiertes
        // "1900-01-01" (oder ein createdAt aus 1900) würde sonst 46.000
        // Kalenderschritte pro Aufruf kosten.
        let oldestLogged = habit.validDays(today: today, calendar: calendar).min()
        let created = DayKey.isPlausible(habit.createdAt, today: today, calendar: calendar)
            ? habit.createdAt : today
        let lower = min(created, oldestLogged ?? created)
        var day = today
        var n = 0
        while day >= lower {
            if dayCounts(habit: habit, day: day, calendar: calendar) {
                n += 1
            } else if isRestDay(habit: habit, day: day, calendar: calendar) {
                // frei — weder Bruch noch Zählung
            } else if day == today {
                // heute noch offen — Serie bis gestern zählt weiter
            } else {
                break
            }
            guard let p = DayKey.shifted(day, by: -1, calendar: calendar) else { break }
            day = p
        }
        return n
    }

    /// Wochen-Serie: aufeinanderfolgende Kalenderwochen (nach `firstWeekday`
    /// des Kalenders) mit mindestens `times` zählenden Tagen. Die laufende
    /// Woche zählt mit, sobald sie erfüllt ist; solange sie noch erreichbar
    /// ist, bricht sie die Serie nicht (kein Mitte-der-Woche-Malus). Erst
    /// wenn das Ziel in dieser Woche nicht mehr erreichbar ist, ist die
    /// Serie 0.
    private static func weeklyStreak(habit: Habit, times: Int, today: String, calendar: Calendar) -> Int {
        guard let todayDate = DayKey.date(from: today, calendar: calendar),
              let currentWeek = calendar.dateInterval(of: .weekOfYear, for: todayDate) else { return 0 }
        let counts = weeklyCounts(habit: habit, today: today, calendar: calendar)
        var streak = 0
        let currentCount = counts[currentWeek.start] ?? 0
        if currentCount >= times {
            streak += 1
        } else {
            // Noch erreichbar? Erfüllte Tage + verbleibende offene Tage
            // (heute eingeschlossen) müssen das Ziel noch schaffen können.
            var openDays = 0
            var dayKey = today
            while let date = DayKey.date(from: dayKey, calendar: calendar), date < currentWeek.end {
                if !dayCounts(habit: habit, day: dayKey, calendar: calendar) { openDays += 1 }
                guard let next = DayKey.shifted(dayKey, by: 1, calendar: calendar) else { break }
                dayKey = next
            }
            if currentCount + openDays < times { return 0 }
        }
        // Rückwärts über abgeschlossene Vorwochen.
        var cursor = currentWeek.start
        while let prev = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor),
              let prevStart = calendar.dateInterval(of: .weekOfYear, for: prev)?.start,
              (counts[prevStart] ?? 0) >= times {
            streak += 1
            cursor = prevStart
        }
        return streak
    }

    /// Längste Serie der GESAMTEN Historie — mit derselben Ziel-Semantik wie
    /// `streak`. Ein Mengen-Habit zählt nur Tage ab `target`, Ruhetage
    /// überbrücken (sie brechen nichts und zählen nichts), und bei
    /// Wochen-Kadenz sind es aufeinanderfolgende erfüllte WOCHEN — dieselbe
    /// Bucketierung wie in `streak`. Ohne das wäre "Best" eine andere
    /// Einheit als die Serie darüber.
    static func bestStreak(habit: Habit, today: String = DayKey.today(), calendar: Calendar = .current) -> Int {
        switch habit.goal.cadence {
        case .daily:
            return dailyBestStreak(habit: habit, today: today, calendar: calendar)
        case .weekly(let times):
            return weeklyBestStreak(habit: habit, times: times, today: today, calendar: calendar)
        }
    }

    /// Vorwärtslauf über die plausible Historie. Grenzen sind der älteste und
    /// der jüngste plausible Log-Tag: davor und danach kann kein Lauf liegen,
    /// und ein Habit mit `createdAt` aus 1900 kostet so trotzdem nur so viele
    /// Schritte, wie er echte Daten hat.
    private static func dailyBestStreak(habit: Habit, today: String, calendar: Calendar) -> Int {
        let days = habit.validDays(today: today, calendar: calendar)
        guard let oldest = days.min(), let newest = days.max() else { return 0 }
        var day = oldest
        var best = 0, run = 0
        // Schlüssel sind nullgepolstertes JJJJ-MM-TT — String-Vergleich ist
        // hier dieselbe Ordnung wie der Datumsvergleich.
        while day <= newest {
            if dayCounts(habit: habit, day: day, calendar: calendar) {
                run += 1
                best = max(best, run)
            } else if isRestDay(habit: habit, day: day, calendar: calendar) {
                // frei — überbrückt den Lauf, ohne ihn zu verlängern
            } else {
                run = 0
            }
            guard let n = DayKey.shifted(day, by: 1, calendar: calendar) else { break }
            day = n
        }
        return best
    }

    /// Längste Kette aufeinanderfolgender erfüllter Kalenderwochen. Iteriert
    /// nur über Wochen MIT zählenden Tagen; die Lücke erkennt der
    /// Datumsvergleich (nächste Wochenstart-Grenze), nicht die Wochennummer —
    /// sonst risse jede Kette am Jahreswechsel (KW 52 -> KW 1).
    private static func weeklyBestStreak(habit: Habit, times: Int, today: String, calendar: Calendar) -> Int {
        let counts = weeklyCounts(habit: habit, today: today, calendar: calendar)
        var best = 0, run = 0
        var lastMet: Date?
        for week in counts.keys.sorted() where (counts[week] ?? 0) >= times {
            let follows = lastMet.flatMap {
                calendar.date(byAdding: .weekOfYear, value: 1, to: $0)
                    .flatMap { calendar.dateInterval(of: .weekOfYear, for: $0)?.start }
            } == week
            run = follows ? run + 1 : 1
            lastMet = week
            best = max(best, run)
        }
        return best
    }

    /// Zählende Tage pro Kalenderwoche, gebuckelt nach Wochen-Startdatum.
    /// Nur plausible Tage — Müll und Zukunft dürfen keine Woche erfüllen.
    private static func weeklyCounts(habit: Habit, today: String, calendar: Calendar) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for day in habit.validDays(today: today, calendar: calendar)
        where dayCounts(habit: habit, day: day, calendar: calendar) {
            guard let date = DayKey.date(from: day, calendar: calendar),
                  let week = calendar.dateInterval(of: .weekOfYear, for: date) else { continue }
            counts[week.start, default: 0] += 1
        }
        return counts
    }

    // MARK: – Abschlussquote

    /// Anteil erfüllter Einheiten in den letzten N Tagen, als Bruch 0…1.
    /// .daily: Zähler und Nenner sind die Nicht-Ruhetage im Fenster
    /// (Ruhetage bleiben komplett außen vor). .weekly: gemessen in den
    /// Kalenderwochen, die das Fenster berührt; die laufende Woche zählt
    /// nur mit, wenn sie schon erfüllt ist. Leerer Nenner -> 0.
    static func completion(habit: Habit, lastNDays: Int, today: String = DayKey.today(), calendar: Calendar = .current) -> Double {
        guard lastNDays > 0 else { return 0 }
        switch habit.goal.cadence {
        case .daily:
            var done = 0, denom = 0
            var day = today
            for _ in 0..<lastNDays {
                if !isRestDay(habit: habit, day: day, calendar: calendar) {
                    denom += 1
                    if dayCounts(habit: habit, day: day, calendar: calendar) { done += 1 }
                }
                guard let p = DayKey.shifted(day, by: -1, calendar: calendar) else { break }
                day = p
            }
            return denom > 0 ? Double(done) / Double(denom) : 0
        case .weekly(let times):
            guard let todayDate = DayKey.date(from: today, calendar: calendar),
                  let currentWeek = calendar.dateInterval(of: .weekOfYear, for: todayDate),
                  let windowStartKey = DayKey.shifted(today, by: -(lastNDays - 1), calendar: calendar),
                  let windowStart = DayKey.date(from: windowStartKey, calendar: calendar) else { return 0 }
            let counts = weeklyCounts(habit: habit, today: today, calendar: calendar)
            var met = 0, denom = 0
            var weekStart = calendar.dateInterval(of: .weekOfYear, for: windowStart)?.start
            while let ws = weekStart, ws <= currentWeek.start {
                let ok = (counts[ws] ?? 0) >= times
                let isCurrent = ws == currentWeek.start
                if !isCurrent || ok { // laufende Woche nur zählen, wenn erfüllt
                    denom += 1
                    if ok { met += 1 }
                }
                weekStart = calendar.date(byAdding: .weekOfYear, value: 1, to: ws)
                    .flatMap { calendar.dateInterval(of: .weekOfYear, for: $0)?.start }
            }
            return denom > 0 ? Double(met) / Double(denom) : 0
        }
    }

    // MARK: – Zellintensität

    /// 1…4. Mengen-Habits schattieren nach Zielerreichung: der ERSTE Zähler
    /// ist immer Stufe 1, das erreichte Ziel immer Stufe 4, dazwischen wird
    /// linear verteilt (`1 + 3·(Wert−1)/(target−1)`, ganzzahlig). Die alte
    /// Formel `ceil(4 · Wert / target)` sprang bei kleinen Zielen sofort auf
    /// Stufe 2 — bei target 3 war `ceil(4/3) = 2`, Stufe 1 also unerreichbar.
    /// Ein Ziel von 1 kennt nur den erfüllten Tag und ist damit Stufe 4.
    /// Checkbox-Habits behalten die v1-Lauflängen-Semantik: längere
    /// zusammenhängende Läufe leuchten heller.
    static func intensity(habit: Habit, key: String, calendar: Calendar = .current) -> Int {
        let value = habit.log[key] ?? 0
        guard value >= 1 else { return 0 }
        if let target = habit.goal.target {
            guard target > 1 else { return 4 }
            // Bewusst Ganzzahl-Arithmetik: `3 · 3 / 9` muss exakt 1 sein,
            // in Double wäre es 0,9999… und fiele eine Stufe zu tief.
            return min(4, max(1, 1 + (3 * (value - 1)) / (target - 1)))
        }
        var run = 1
        var day = key
        while run < 8,
              let p = DayKey.shifted(day, by: -1, calendar: calendar),
              (habit.log[p] ?? 0) >= 1 {
            run += 1
            day = p
        }
        return min(4, max(1, Int(ceil(Double(run) / 2))))
    }
}
