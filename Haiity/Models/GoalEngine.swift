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
        guard value >= 1 else { return false }
        if let target = habit.goal.target { return value >= target }
        return true
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
        // Historie.
        let lower = min(habit.createdAt, habit.log.keys.min() ?? habit.createdAt)
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
        let counts = weeklyCounts(habit: habit, calendar: calendar)
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

    /// Zählende Tage pro Kalenderwoche, gebuckelt nach Wochen-Startdatum.
    private static func weeklyCounts(habit: Habit, calendar: Calendar) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for day in habit.log.keys where dayCounts(habit: habit, day: day, calendar: calendar) {
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
            let counts = weeklyCounts(habit: habit, calendar: calendar)
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

    /// 1…4. Mengen-Habits schattieren nach Zielerreichung
    /// (ceil(4 · Wert / target), geklemmt auf 1…4 — auch Teilfortschritt
    /// leuchtet). Checkbox-Habits behalten die v1-Lauflängen-Semantik:
    /// längere zusammenhängende Läufe leuchten heller.
    static func intensity(habit: Habit, key: String, calendar: Calendar = .current) -> Int {
        let value = habit.log[key] ?? 0
        guard value >= 1 else { return 0 }
        if let target = habit.goal.target {
            return min(4, max(1, Int(ceil(4 * Double(value) / Double(target)))))
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
