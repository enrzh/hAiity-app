import Foundation

/// Reine Statistik über ALLE Habits ZUSAMMEN — die Rechnungen hinter den
/// Statistik-Karten über der Liste. Wie GoalEngine und StatsMath: keine
/// Store-Abhängigkeit, expliziter Calendar, vollständig unit-testbar.
///
/// **Die Gesamt-Serie** („Streak-Flamme") überträgt die Tages-Semantik der
/// GoalEngine von einem Habit auf alle:
///
///  * Ein Tag ZÄHLT, wenn an ihm mindestens ein Check-in zählt und KEIN
///    Habit ihn reißt.
///  * Ein Habit REISST einen Tag, wenn es ihn ausdrücklich verneint hat
///    (nie durchsichtig, auch heute) — oder wenn es an ihm fällig war und
///    ihn verfehlt hat. „Verfehlt" heißt bei festen Terminen: kein
///    zählender Eintrag (heute darf noch offen sein); bei flexiblen Zielen:
///    die PERIODE des Tages ist abgelaufen und unerfüllt. Die laufende
///    Periode reißt nichts — kein Mitte-der-Woche-Malus, exakt wie in
///    `GoalEngine.periodStreak`.
///  * Ein Tag, an dem nichts fällig und nichts eingetragen ist, ist
///    DURCHSICHTIG: er bricht nichts und zählt nichts. Ein Check-in an so
///    einem Tag zählt trotzdem — Mehrleistung wird nie bestraft.
///  * Ein Tag mit offenen (noch erreichbaren) Terminen zählt NOCH nicht,
///    bricht aber auch nicht — die Serie lebt bis gestern weiter.
///
/// Keine Habits (oder nur archivierte, die der Aufrufer gar nicht erst
/// übergibt) heißt schlicht: Serie 0.
enum StatsEngine {

    // MARK: – Bausteine

    /// Erfüllte von fälligen Habits in einem Fenster (Tag oder Woche).
    struct DayCompletion: Equatable {
        var done: Int
        var total: Int

        /// 0…1; leerer Nenner = 1 („nichts fällig = nichts versäumt").
        var fraction: Double { total > 0 ? Double(done) / Double(total) : 1 }
    }

    /// Serienpaar eines einzelnen Habits — die Rückseite der Puls-Karte.
    struct HabitStreaks: Equatable {
        let name: String
        let emoji: String
        let current: Int
        let best: Int
    }

    /// Fällige und erfüllte Habits an einem Tag — der pure Spiegel von
    /// `HabitStore.dailyStatus`, nur ohne die Namensliste.
    static func dailyCompletion(habits: [Habit], day: String,
                                calendar: Calendar = .current) -> DayCompletion {
        var done = 0, total = 0
        for habit in habits where GoalEngine.isScheduled(habit: habit, day: day, calendar: calendar) {
            total += 1
            if GoalEngine.dayCounts(habit: habit, day: day, calendar: calendar) { done += 1 }
        }
        return DayCompletion(done: done, total: total)
    }

    // MARK: – Gesamt-Serie

    /// Ein Habit, vorgerechnet für den Rückwärts-/Vorwärtslauf: Termine und
    /// (bei flexiblen Zielen) die Perioden-Zählung EINMAL statt pro Tag.
    private struct Judge {
        let habit: Habit
        let schedule: Recurrence.Schedule
        let times: Int?
        let periodCounts: [Date: Int]
        let currentPeriod: Date?

        init(habit: Habit, today: String, calendar: Calendar) {
            self.habit = habit
            let schedule = habit.recurrence.schedule(calendar: calendar)
            self.schedule = schedule
            self.times = habit.recurrence.timesPerPeriod
            self.periodCounts = habit.recurrence.timesPerPeriod != nil
                ? GoalEngine.periodCounts(habit: habit, schedule: schedule,
                                          today: today, calendar: calendar)
                : [:]
            self.currentPeriod = schedule.periodStart(forDay: today)
        }

        enum Verdict {
            /// Erfüllt (zählender Eintrag bzw. erfüllte Periode).
            case met
            /// Heute fällig und noch nicht erledigt: der Tag ist noch nicht
            /// entschieden — er zählt (noch) nicht, aber er bricht nichts.
            case openToday
            /// Flexibles Ziel, laufende Periode noch unerfüllt: das Habit
            /// SCHULDET diesem Tag nichts Bestimmtes — es hält den Tag
            /// weder auf noch reißt es ihn (kein Mitte-der-Woche-Malus).
            case openPeriod
            /// Fällig und verfehlt — oder ausdrücklich verneint.
            case missed
            /// Kein Termin, kein Eintrag: durchsichtig.
            case free
        }

        func verdict(day: String, today: String, calendar: Calendar) -> Verdict {
            // Ein Nein bricht sofort — vor allen anderen Regeln, auch an
            // einem terminfreien Tag und auch heute (siehe GoalEngine).
            if GoalEngine.dayDeclined(habit: habit, day: day) { return .missed }
            let counted = GoalEngine.dayCounts(habit: habit, day: day, calendar: calendar)
            guard schedule.isScheduled(day) else { return counted ? .met : .free }
            if let times {
                guard let period = schedule.periodStart(forDay: day) else {
                    return counted ? .met : .free
                }
                if (periodCounts[period] ?? 0) >= times { return .met }
                return period == currentPeriod ? .openPeriod : .missed
            }
            if counted { return .met }
            return day == today ? .openToday : .missed
        }
    }

    private enum DayState { case counts, transparent, breaks }

    /// Ein Tag über alle Habits: reißt einer, reißt der Tag. Ist ein FESTER
    /// Termin heute noch offen, ist der Tag noch nicht entschieden
    /// (durchsichtig). Eine noch offene FLEXIBLE Periode hält den Tag
    /// dagegen nicht auf — sie schuldet keinem einzelnen Tag etwas. Sonst
    /// zählt der Tag genau dann, wenn irgendetwas erfüllt wurde.
    private static func dayState(_ judges: [Judge], day: String, today: String,
                                 calendar: Calendar) -> DayState {
        var met = false, undecided = false
        for judge in judges {
            switch judge.verdict(day: day, today: today, calendar: calendar) {
            case .missed: return .breaks
            case .met: met = true
            case .openToday: undecided = true
            case .openPeriod, .free: break
            }
        }
        if undecided { return .transparent }
        return met ? .counts : .transparent
    }

    /// Untere Grenze des Laufs: der älteste plausible Log-Tag bzw. das
    /// plausible `createdAt` — dieselbe Klemme wie in `GoalEngine.dayStreak`,
    /// nur über alle Habits.
    private static func lowerBound(_ habits: [Habit], today: String,
                                   calendar: Calendar) -> String? {
        habits.map { habit -> String in
            let oldest = habit.validDays(today: today, calendar: calendar).min()
            let created = DayKey.isPlausible(habit.createdAt, today: today, calendar: calendar)
                ? habit.createdAt : today
            return min(created, oldest ?? created)
        }.min()
    }

    /// Aktuelle Gesamt-Serie: zusammenhängende zählende Tage bis heute,
    /// terminfreie Tage durchsichtig, heute darf offen sein.
    static func overallStreak(habits: [Habit],
                              today: String = DayKey.today(),
                              calendar: Calendar = .current) -> Int {
        guard !habits.isEmpty,
              let lower = lowerBound(habits, today: today, calendar: calendar) else { return 0 }
        let judges = habits.map { Judge(habit: $0, today: today, calendar: calendar) }
        var day = today
        var n = 0
        while day >= lower {
            switch dayState(judges, day: day, today: today, calendar: calendar) {
            case .counts: n += 1
            case .transparent: break
            case .breaks: return n
            }
            guard let previous = DayKey.shifted(day, by: -1, calendar: calendar) else { break }
            day = previous
        }
        return n
    }

    /// Längste Gesamt-Serie der Historie — Vorwärtslauf mit derselben
    /// Tages-Semantik wie `overallStreak` (sonst wäre „Best" eine andere
    /// Einheit als die Zahl daneben).
    static func bestOverallStreak(habits: [Habit],
                                  today: String = DayKey.today(),
                                  calendar: Calendar = .current) -> Int {
        guard !habits.isEmpty else { return 0 }
        let days = habits.flatMap { $0.validDays(today: today, calendar: calendar) }
        guard let oldest = days.min(), let newest = days.max() else { return 0 }
        let judges = habits.map { Judge(habit: $0, today: today, calendar: calendar) }
        var day = oldest
        var best = 0, run = 0
        while day <= newest {
            switch dayState(judges, day: day, today: today, calendar: calendar) {
            case .counts: run += 1; best = max(best, run)
            case .transparent: break
            case .breaks: run = 0
            }
            guard let next = DayKey.shifted(day, by: 1, calendar: calendar) else { break }
            day = next
        }
        return best
    }

    // MARK: – Wochenbilanz

    /// Erfüllte gegen fällige Termine in der Woche, in der `anchor` liegt,
    /// geklemmt auf `upTo` — der pure Spiegel von `HabitStore.weeklyStatus`
    /// (dieselben Regeln: flexible Wochenziele zählen mit ihrer ANZAHL,
    /// flexible Monats-/Jahresziele stehen in keiner Wochenbilanz).
    /// Der Wochenanfang folgt dem Kalender des Nutzers.
    static func weekCompletion(habits: [Habit], anchor: String,
                               upTo limit: String,
                               calendar: Calendar = .current) -> DayCompletion {
        guard let anchorDate = DayKey.date(from: anchor, calendar: calendar),
              let interval = calendar.dateInterval(of: .weekOfYear, for: anchorDate),
              let lastDate = calendar.date(byAdding: .day, value: -1, to: interval.end)
        else { return DayCompletion(done: 0, total: 0) }
        let firstDay = DayKey.key(for: interval.start, calendar: calendar)
        let lastDay = min(DayKey.key(for: lastDate, calendar: calendar), limit)
        guard firstDay <= lastDay else { return DayCompletion(done: 0, total: 0) }

        var done = 0, total = 0
        for habit in habits {
            let schedule = habit.recurrence.schedule(calendar: calendar)
            var due = 0, met = 0
            if let times = habit.recurrence.timesPerPeriod {
                guard habit.recurrence.frequency == .weekly,
                      schedule.isActivePeriod(interval.start),
                      schedule.isScheduled(firstDay) || schedule.isScheduled(lastDay)
                else { continue }
                due = times
                var day = firstDay, counting = 0
                while day <= lastDay {
                    if GoalEngine.dayCounts(habit: habit, day: day, calendar: calendar) { counting += 1 }
                    guard let next = DayKey.shifted(day, by: 1, calendar: calendar) else { break }
                    day = next
                }
                met = min(times, counting)
            } else {
                var day = firstDay
                while day <= lastDay {
                    if schedule.isScheduled(day) {
                        due += 1
                        if GoalEngine.dayCounts(habit: habit, day: day, calendar: calendar) { met += 1 }
                    }
                    guard let next = DayKey.shifted(day, by: 1, calendar: calendar) else { break }
                    day = next
                }
            }
            guard due > 0 else { continue }
            total += due
            done += met
        }
        return DayCompletion(done: done, total: total)
    }

    /// Die laufende Woche bis einschließlich heute.
    static func thisWeekCompletion(habits: [Habit],
                                   today: String = DayKey.today(),
                                   calendar: Calendar = .current) -> DayCompletion {
        weekCompletion(habits: habits, anchor: today, upTo: today, calendar: calendar)
    }

    /// Die VOLLE Vorwoche — der Vergleichswert der Momentum-Karte.
    static func previousWeekCompletion(habits: [Habit],
                                       today: String = DayKey.today(),
                                       calendar: Calendar = .current) -> DayCompletion {
        guard let anchor = DayKey.shifted(today, by: -7, calendar: calendar) else {
            return DayCompletion(done: 0, total: 0)
        }
        return weekCompletion(habits: habits, anchor: anchor, upTo: today, calendar: calendar)
    }

    /// Delta in PROZENTPUNKTEN gegen die Vorwoche; nil, wenn eine der beiden
    /// Wochen keinen einzigen fälligen Termin hatte — dann gibt es nichts zu
    /// vergleichen, und der Satz auf der Karte fällt neutral aus.
    static func momentumDeltaPoints(current: DayCompletion,
                                    previous: DayCompletion) -> Int? {
        guard current.total > 0, previous.total > 0 else { return nil }
        return Int(((current.fraction - previous.fraction) * 100).rounded())
    }

    /// Tages-Abschlussquoten der letzten 7 Tage (älteste zuerst, heute
    /// zuletzt) — die Sparkline der Momentum-Karte.
    static func last7DailyFractions(habits: [Habit],
                                    today: String = DayKey.today(),
                                    calendar: Calendar = .current) -> [Double] {
        (-6...0).compactMap { offset in
            guard let day = DayKey.shifted(today, by: offset, calendar: calendar) else { return nil }
            return dailyCompletion(habits: habits, day: day, calendar: calendar).fraction
        }
    }

    // MARK: – Jahres-Puls (vereinigtes Raster)

    /// Zellstufen des VEREINIGTEN Rasters: pro Tag die Anzahl zählender
    /// Habits, skaliert auf 1…4 gegen das Maximum im Fenster — dieselbe
    /// Rampenformel wie die Zielerreichung der Mengen-Habits (der erste
    /// Zähler ist Stufe 1, das Maximum Stufe 4). Spalten/Zeilen exakt wie
    /// `GridCalendar.keys` (Zukunft = 0).
    static func mergedLevels(habits: [Habit], weeks: Int,
                             today: String = DayKey.today(),
                             calendar: Calendar = .current) -> [[Int]] {
        let keys = GridCalendar.keys(weeks: weeks, today: today, calendar: calendar)
        var counts: [String: Int] = [:]
        for habit in habits {
            for day in habit.validDays(today: today, calendar: calendar)
            where GoalEngine.dayCounts(habit: habit, day: day, calendar: calendar) {
                counts[day, default: 0] += 1
            }
        }
        let maxCount = counts.values.max() ?? 0
        return keys.map { column in
            column.map { key in
                guard let key, let c = counts[key], c >= 1, maxCount >= 1 else { return 0 }
                guard maxCount > 1 else { return 4 }
                return min(4, max(1, 1 + (3 * (c - 1)) / (maxCount - 1)))
            }
        }
    }

    // MARK: – Schnappschuss mit Memo

    /// Wochenfenster des Puls-Rasters: klein genug für eine Karte, groß
    /// genug für einen erkennbaren Verlauf.
    static let pulseWeeks = 20

    /// Alles, was die Karten brauchen, EINMAL gerechnet. `Equatable`, damit
    /// die Kartenansicht per `.equatable()` an genau diesem Wert hängt.
    struct Snapshot: Equatable {
        var today: String
        var todayDone: Int
        var todayTotal: Int
        var streak: Int
        var bestStreak: Int
        var week: DayCompletion
        var previousWeek: DayCompletion
        var last7: [Double]
        var mergedLevels: [[Int]]
        var perHabit: [HabitStreaks]
    }

    /// Echte Neuberechnungen — der Beleg im Test, dass Scroll- und
    /// Chrom-Umbauten nicht jedes Mal 365 Tage rechnen.
    private(set) static var computeCount = 0

    private static let lock = NSLock()
    private static var cachedKey: (habits: [Habit], today: String, firstWeekday: Int)?
    private static var cachedSnapshot: Snapshot?

    /// Memoisiert über (Habits, heute, Wochenanfang): eine `body`-Auswertung
    /// kostet nur den Gleichheitsvergleich; neu gerechnet wird bei einer
    /// echten Datenänderung oder beim Tageswechsel.
    static func snapshot(habits: [Habit],
                         today: String = DayKey.today(),
                         calendar: Calendar = .current) -> Snapshot {
        lock.lock()
        if let key = cachedKey, let snap = cachedSnapshot,
           key.habits == habits, key.today == today,
           key.firstWeekday == calendar.firstWeekday {
            lock.unlock()
            return snap
        }
        lock.unlock()

        let todayCompletion = dailyCompletion(habits: habits, day: today, calendar: calendar)
        let snap = Snapshot(
            today: today,
            todayDone: todayCompletion.done,
            todayTotal: todayCompletion.total,
            streak: overallStreak(habits: habits, today: today, calendar: calendar),
            bestStreak: bestOverallStreak(habits: habits, today: today, calendar: calendar),
            week: thisWeekCompletion(habits: habits, today: today, calendar: calendar),
            previousWeek: previousWeekCompletion(habits: habits, today: today, calendar: calendar),
            last7: last7DailyFractions(habits: habits, today: today, calendar: calendar),
            mergedLevels: mergedLevels(habits: habits, weeks: pulseWeeks,
                                       today: today, calendar: calendar),
            perHabit: habits.prefix(6).map {
                HabitStreaks(name: $0.name, emoji: $0.emoji,
                             current: GoalEngine.streak(habit: $0, today: today, calendar: calendar),
                             best: GoalEngine.bestStreak(habit: $0, today: today, calendar: calendar))
            })

        lock.lock()
        cachedKey = (habits, today, calendar.firstWeekday)
        cachedSnapshot = snap
        computeCount += 1
        lock.unlock()
        return snap
    }

    /// Nur für Tests.
    static func resetCache() {
        lock.lock()
        cachedKey = nil
        cachedSnapshot = nil
        computeCount = 0
        lock.unlock()
    }
}
