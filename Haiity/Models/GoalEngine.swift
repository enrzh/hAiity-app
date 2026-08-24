import Foundation

/// Reine Ziel-Logik: Serien, Abschlussquoten und Zellintensität — jetzt über
/// TERMINE statt über „jeder Tag zählt". Keine Store-Abhängigkeit; jede
/// Funktion nimmt wie DayKey einen Calendar, Wochen respektieren also
/// `firstWeekday` des Nutzers.
///
/// **Die eine Regel, aus der alles folgt:** ein Tag ohne Termin ist
/// DURCHSICHTIG. Er bricht keine Serie und zählt nicht in den Nenner. Wer an
/// so einem Tag trotzdem abhakt, bekommt ihn geschenkt (er zählt in der
/// Serie mit) — Mehrleistung darf nie bestraft werden. Das ist exakt die
/// alte Ruhetag-Regel, nur verallgemeinert: Ruhetage sind jetzt schlicht die
/// Tage, an denen die Wochentagsmenge keinen Termin vorsieht.
///
/// **Die eine Ausnahme von der Durchsichtigkeit:** eine ausdrückliche
/// VERNEINUNG (Habit-Art „Ja/Nein"). Sie ist nie durchsichtig — sie bricht
/// die Serie an jedem Tag, an dem sie steht, auch an einem terminfreien, und
/// sie steht im Nenner der Quote. Das ist genau der Unterschied zwischen
/// „nicht beantwortet" und „mit Nein beantwortet": das eine ist eine Lücke,
/// das andere eine Aussage. Ohne diese Ausnahme wäre die ganze Habit-Art
/// bedeutungslos — ein Nein verhielte sich wie gar kein Eintrag.
enum GoalEngine {

    // MARK: – Tages-Semantik

    /// Zählt der Tag? Checkbox: Wert >= 1. Mengen-Habit: Wert >= target.
    /// Ja/Nein: nur ein JA (eine Verneinung ist ein Wert ≥ 1 und darf hier
    /// auf keinen Fall durchrutschen).
    /// Termine werden hier bewusst NICHT geprüft — ein Check-in zählt auch
    /// an einem terminfreien Tag (siehe oben).
    static func dayCounts(habit: Habit, day: String, calendar: Calendar = .current) -> Bool {
        let value = habit.log[day] ?? 0
        // `components` ist ein reiner String-Check (kein Kalender) — billig
        // genug für den heißen Pfad und wirft offensichtlichen Müll raus.
        // Die volle Plausibilität (echtes Datum, nicht Zukunft, nicht 1900)
        // prüft `Habit.validDays` an allen Stellen, die über Log-Schlüssel
        // iterieren.
        guard value >= 1, DayKey.components(day) != nil else { return false }
        // Die ART gewinnt über das Mengenziel: ein Ja/Nein-Habit, in dessen
        // Regel noch ein altes `target` steht, bleibt ein Ja/Nein-Habit.
        switch habit.kind {
        case .yesNo:    return value != Habit.Answer.no
        case .quantity: return value >= (habit.recurrence.target ?? 1)
        case .checkbox: return true
        }
    }

    /// Ausdrücklich verneint? Der Gegenspieler zu `dayCounts` — und der
    /// EINZIGE Grund, warum eine Serie an einem terminfreien Tag reißen kann.
    static func dayDeclined(habit: Habit, day: String) -> Bool {
        guard DayKey.components(day) != nil else { return false }
        return habit.isDeclined(day) || habit.isMissed(day)
    }

    /// Ist an diesem Tag ein Termin fällig?
    static func isScheduled(habit: Habit, day: String, calendar: Calendar = .current) -> Bool {
        habit.recurrence.schedule(calendar: calendar).isScheduled(day)
    }

    /// Ist die PERIODE, in der `day` liegt, erfüllt?
    ///
    /// Bei festen Terminen ist das schlicht der Tag selbst. Bei einem
    /// flexiblen Ziel („3× pro Woche", „5× pro Monat") zählt die Anzahl
    /// zählender Tage in der Periode gegen `timesPerPeriod`.
    ///
    /// **Die Regel, die bleibt:** eine Wochentagsmenge NEBEN einem flexiblen
    /// Ziel ist eine Verabredung, keine Prüfung. „Einmal pro Woche, gedacht
    /// am Dienstag" ist erfüllt, sobald IRGENDEIN Tag dieser Woche zählt —
    /// der Dienstag steuert nur die Erinnerung und die Beschriftung. Wer zu
    /// früh oder zu spät dran ist, soll seine Serie nicht verlieren; alles
    /// andere bestraft genau die Leute, die trotzdem drangeblieben sind.
    static func periodSatisfied(habit: Habit,
                                day: String,
                                today: String = DayKey.today(),
                                calendar: Calendar = .current) -> Bool {
        guard let times = habit.recurrence.timesPerPeriod else {
            return dayCounts(habit: habit, day: day, calendar: calendar)
        }
        let schedule = habit.recurrence.schedule(calendar: calendar)
        guard let period = schedule.periodStart(forDay: day) else { return false }
        let counts = periodCounts(habit: habit, schedule: schedule, today: today, calendar: calendar)
        return (counts[period] ?? 0) >= times
    }

    // MARK: – Serien

    static func streak(habit: Habit, today: String = DayKey.today(), calendar: Calendar = .current) -> Int {
        let schedule = habit.recurrence.schedule(calendar: calendar)
        if let times = habit.recurrence.timesPerPeriod {
            return periodStreak(habit: habit, times: times, schedule: schedule,
                                today: today, calendar: calendar)
        }
        return dayStreak(habit: habit, schedule: schedule, today: today, calendar: calendar)
    }

    /// Serie über TERMINE: zusammenhängende erfüllte Termine bis heute.
    /// Terminfreie Tage sind durchsichtig (sie brechen nichts und zählen
    /// nichts); ein Check-in an so einem Tag zählt trotzdem. Heute darf noch
    /// offen sein (die Serie lebt bis gestern).
    ///
    /// **Ein Nein bricht sofort** — vor allen anderen Regeln, also auch an
    /// einem terminfreien Tag und auch HEUTE. „Heute noch offen" ist eine
    /// Aussage über einen Tag, der noch nichts gesagt hat; ein Nein hat
    /// gesprochen.
    private static func dayStreak(habit: Habit,
                                  schedule: Recurrence.Schedule,
                                  today: String,
                                  calendar: Calendar) -> Int {
        // Untere Grenze hält die Schleife endlich — auch wenn die Regel gar
        // keine Termine mehr vorsieht, endet der Rückwärtslauf am Anfang der
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
            } else if dayDeclined(habit: habit, day: day) {
                break   // ausdrücklich verneint — nie durchsichtig
            } else if !schedule.isScheduled(day) {
                // kein Termin — weder Bruch noch Zählung
            } else if day == today {
                // heute noch offen — Serie bis gestern zählt weiter
            } else {
                break
            }
            guard let previous = DayKey.shifted(day, by: -1, calendar: calendar) else { break }
            day = previous
        }
        return n
    }

    /// Serie über PERIODEN (flexibles Ziel): aufeinanderfolgende AKTIVE
    /// Perioden mit mindestens `times` zählenden Tagen. Die laufende Periode
    /// zählt mit, sobald sie erfüllt ist; solange sie noch erreichbar ist,
    /// bricht sie die Serie nicht (kein Mitte-der-Woche-Malus). Erst wenn das
    /// Ziel dort nicht mehr erreichbar ist, ist die Serie 0. Perioden, die
    /// das Intervall auslässt („alle 2 Wochen"), sind durchsichtig.
    private static func periodStreak(habit: Habit,
                                     times: Int,
                                     schedule: Recurrence.Schedule,
                                     today: String,
                                     calendar: Calendar) -> Int {
        guard let todayDate = DayKey.date(from: today, calendar: calendar),
              let current = schedule.periodStart(for: todayDate) else { return 0 }
        let counts = periodCounts(habit: habit, schedule: schedule, today: today, calendar: calendar)
        var streak = 0
        if schedule.isActivePeriod(current) {
            if (counts[current] ?? 0) >= times {
                streak += 1
            } else if (counts[current] ?? 0) + openDays(habit: habit, schedule: schedule,
                                                        from: today, in: current,
                                                        calendar: calendar) < times {
                return 0   // in dieser Periode nicht mehr zu schaffen
            }
        }
        var cursor = current
        while let previous = schedule.previousActivePeriod(before: cursor),
              (counts[previous] ?? 0) >= times {
            streak += 1
            cursor = previous
        }
        return streak
    }

    /// Noch offene (nicht zählende) Tage von `from` bis zum Ende der Periode
    /// — das, was in dieser Periode überhaupt noch erreichbar ist.
    private static func openDays(habit: Habit,
                                 schedule: Recurrence.Schedule,
                                 from day: String,
                                 in period: Date,
                                 calendar: Calendar) -> Int {
        var open = 0
        var cursor = day
        // Obergrenze: die längste Periode ist ein Jahr.
        for _ in 0..<366 {
            guard let date = DayKey.date(from: cursor, calendar: calendar),
                  schedule.periodStart(for: date) == period else { break }
            if !dayCounts(habit: habit, day: cursor, calendar: calendar) { open += 1 }
            guard let next = DayKey.shifted(cursor, by: 1, calendar: calendar) else { break }
            cursor = next
        }
        return open
    }

    /// Längste Serie der GESAMTEN Historie — mit derselben Semantik wie
    /// `streak`. Ein Mengen-Habit zählt nur Tage ab `target`, terminfreie
    /// Tage überbrücken, und bei einem flexiblen Ziel sind es
    /// aufeinanderfolgende erfüllte PERIODEN — dieselbe Bucketierung wie in
    /// `streak`. Ohne das wäre „Best" eine andere Einheit als die Serie
    /// darüber.
    static func bestStreak(habit: Habit, today: String = DayKey.today(), calendar: Calendar = .current) -> Int {
        let schedule = habit.recurrence.schedule(calendar: calendar)
        if let times = habit.recurrence.timesPerPeriod {
            return periodBestStreak(habit: habit, times: times, schedule: schedule,
                                    today: today, calendar: calendar)
        }
        return dayBestStreak(habit: habit, schedule: schedule, today: today, calendar: calendar)
    }

    /// Vorwärtslauf über die plausible Historie. Grenzen sind der älteste und
    /// der jüngste plausible Log-Tag: davor und danach kann kein Lauf liegen,
    /// und ein Habit mit `createdAt` aus 1900 kostet so trotzdem nur so viele
    /// Schritte, wie er echte Daten hat.
    private static func dayBestStreak(habit: Habit,
                                      schedule: Recurrence.Schedule,
                                      today: String,
                                      calendar: Calendar) -> Int {
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
            } else if dayDeclined(habit: habit, day: day) {
                run = 0   // dieselbe Ausnahme wie in `dayStreak`
            } else if !schedule.isScheduled(day) {
                // kein Termin — überbrückt den Lauf, ohne ihn zu verlängern
            } else {
                run = 0
            }
            guard let next = DayKey.shifted(day, by: 1, calendar: calendar) else { break }
            day = next
        }
        return best
    }

    /// Längste Kette aufeinanderfolgender erfüllter Perioden. Iteriert nur
    /// über Perioden MIT zählenden Tagen; die Lücke erkennt der
    /// Datumsvergleich (nächste aktive Periodengrenze), nicht die
    /// Wochennummer — sonst risse jede Kette am Jahreswechsel (KW 52 -> KW 1).
    private static func periodBestStreak(habit: Habit,
                                         times: Int,
                                         schedule: Recurrence.Schedule,
                                         today: String,
                                         calendar: Calendar) -> Int {
        let counts = periodCounts(habit: habit, schedule: schedule, today: today, calendar: calendar)
        var best = 0, run = 0
        var lastMet: Date?
        for period in counts.keys.sorted()
        where (counts[period] ?? 0) >= times && schedule.isActivePeriod(period) {
            let follows = lastMet.flatMap { schedule.nextActivePeriod(after: $0) } == period
            run = follows ? run + 1 : 1
            lastMet = period
            best = max(best, run)
        }
        return best
    }

    /// Zählende Tage pro Periode, gebuckelt nach Periodenanfang. Nur
    /// plausible Tage — Müll und Zukunft dürfen keine Periode erfüllen.
    /// Intern statt privat: die Gesamt-Serie über alle Habits (StatsEngine)
    /// braucht exakt dieselbe Bucketierung — zweimal implementiert wäre sie
    /// irgendwann zweimal verschieden.
    static func periodCounts(habit: Habit,
                                     schedule: Recurrence.Schedule,
                                     today: String,
                                     calendar: Calendar) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for day in habit.validDays(today: today, calendar: calendar)
        where dayCounts(habit: habit, day: day, calendar: calendar) {
            guard let date = DayKey.date(from: day, calendar: calendar),
                  let period = schedule.periodStart(for: date) else { continue }
            counts[period, default: 0] += 1
        }
        return counts
    }

    // MARK: – Abschlussquote

    /// Anteil erfüllter Einheiten in den letzten N Tagen, als Bruch 0…1.
    ///
    /// Feste Termine: erfüllte ÷ FÄLLIGE Tage im Fenster (terminfreie Tage
    /// stehen in keinem der beiden). Flexibles Ziel: gemessen in den aktiven
    /// Perioden, die das Fenster berührt; die laufende Periode zählt nur mit,
    /// wenn sie schon erfüllt ist. Leerer Nenner -> 0.
    ///
    /// **Beantwortete Tage stehen immer im Nenner** — auch, wenn an ihnen
    /// gar kein Termin war. Wer an einem freien Tag „Nein" sagt, hat etwas
    /// gesagt, und die Quote ist die Stelle, an der es zählt; wer dort „Ja"
    /// sagt, hebt sie (Nenner UND Zähler wachsen um eins, das kann eine
    /// Quote nie senken). Für Checkbox- und Mengen-Habits ändert das nichts:
    /// `isAnswered` ist dort immer falsch.
    static func completion(habit: Habit,
                           lastNDays: Int,
                           today: String = DayKey.today(),
                           calendar: Calendar = .current) -> Double {
        guard lastNDays > 0 else { return 0 }
        let schedule = habit.recurrence.schedule(calendar: calendar)
        guard let times = habit.recurrence.timesPerPeriod else {
            var done = 0, denom = 0
            var day = today
            for _ in 0..<lastNDays {
                if schedule.isScheduled(day) || habit.isAnswered(day) {
                    denom += 1
                    if dayCounts(habit: habit, day: day, calendar: calendar) { done += 1 }
                }
                guard let previous = DayKey.shifted(day, by: -1, calendar: calendar) else { break }
                day = previous
            }
            return denom > 0 ? Double(done) / Double(denom) : 0
        }
        guard let todayDate = DayKey.date(from: today, calendar: calendar),
              let current = schedule.periodStart(for: todayDate),
              let windowStartKey = DayKey.shifted(today, by: -(lastNDays - 1), calendar: calendar),
              var cursor = schedule.periodStart(forDay: windowStartKey) else { return 0 }
        let counts = periodCounts(habit: habit, schedule: schedule, today: today, calendar: calendar)
        var met = 0, denom = 0
        while cursor <= current {
            if schedule.isActivePeriod(cursor) {
                let ok = (counts[cursor] ?? 0) >= times
                if cursor != current || ok {   // laufende Periode nur zählen, wenn erfüllt
                    denom += 1
                    if ok { met += 1 }
                }
            }
            guard let next = schedule.shiftPeriod(cursor, by: 1) else { break }
            cursor = next
        }
        return denom > 0 ? Double(met) / Double(denom) : 0
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
    ///
    /// Termine ändern hier bewusst NICHTS: eine leere Zelle ist eine leere
    /// Zelle, ob der Tag fällig war oder nicht. Das Raster ist die Historie,
    /// keine zweite Darstellung der Regel — ein eigener Grauton für „war
    /// nicht fällig" hätte 365 Zellen pro Habit eine dritte Bedeutung
    /// gegeben, die niemand ohne Legende liest.
    ///
    /// **Ja/Nein hat keine Menge** — es gibt nichts zu schattieren. Ein Ja
    /// bekommt deshalb dieselbe Lauflängen-Schattierung wie eine Checkbox
    /// (längere Ketten leuchten heller, gezählt werden nur JA-Tage), und ein
    /// Nein bekommt die reservierte Stufe `Answer.declinedLevel`. Sie ist
    /// die einzige Ausnahme von „eine leere Zelle ist eine leere Zelle": ein
    /// Nein ist kein leerer Tag, sondern die Gegenaussage — die einzige
    /// dritte Bedeutung, die das Raster je bekommt, und die einzige, die man
    /// ohne Legende liest, weil sie eine eigene FARBE hat und keinen
    /// Grauton.
    static func intensity(habit: Habit, key: String, calendar: Calendar = .current) -> Int {
        if habit.isDeclined(key) || habit.isMissed(key) {
            return Habit.Answer.declinedLevel
        }
        let value = habit.log[key] ?? 0
        guard value >= 1 else { return 0 }
        if habit.kind == .quantity, let target = habit.recurrence.target {
            guard target > 1 else { return 4 }
            // Bewusst Ganzzahl-Arithmetik: `3 · 3 / 9` muss exakt 1 sein,
            // in Double wäre es 0,9999… und fiele eine Stufe zu tief.
            return min(4, max(1, 1 + (3 * (value - 1)) / (target - 1)))
        }
        var run = 1
        var day = key
        while run < 8,
              let previous = DayKey.shifted(day, by: -1, calendar: calendar),
              // Ein Nein unterbricht den Lauf, statt ihn zu verlängern —
              // sonst leuchtete eine Kette aus Verneinungen am hellsten.
              habit.isDone(previous) {
            run += 1
            day = previous
        }
        return min(4, max(1, Int(ceil(Double(run) / 2))))
    }
}
