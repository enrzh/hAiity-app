import Foundation

/// Eine Wiederholungsregel, wie ein Kalendereintrag sie kennt: Häufigkeit
/// (täglich / wöchentlich / monatlich / jährlich) mal INTERVALL, dazu die
/// feinere Regel (Wochentagsmenge, Tag im Monat, n-ter Wochentag), ein
/// Startdatum und ein optionales Ende.
///
/// **Zwei Betriebsarten** — daran hängt die ganze Auswertung:
///
///  * **FEST** (`timesPerPeriod == nil`): die Regel benennt die TAGE. Nur
///    diese Tage sind Termine, und jeder einzelne zählt (Serie =
///    aufeinanderfolgende erfüllte Termine, Quote = erfüllte ÷ fällige).
///  * **FLEXIBEL** (`timesPerPeriod == n`): die Regel benennt nur die
///    PERIODE. „3× pro Woche" — welche drei Tage, entscheidet der Nutzer;
///    JEDER Tag einer aktiven Periode ist ein möglicher Termin, und erfüllt
///    ist die Periode, sobald n zählende Tage darin liegen. Das ist exakt
///    die alte `.weekly(times:)`-Semantik und bleibt als Fall erhalten,
///    nicht als Sonderweg daneben.
///
/// Alles rechnet über `Calendar` in ganzen Kalendertagen — nie mit
/// 24-Stunden-Abständen, sonst kippt jede Sommerzeitgrenze.
struct Recurrence: Equatable {

    enum Frequency: String, CaseIterable, Equatable {
        case once, daily, weekly, monthly, yearly
    }

    /// Der Tag INNERHALB eines Monats — für Monats- wie für Jahresregeln.
    /// Findet ein Monat den Tag nicht (31. im Februar, 5. Dienstag in einem
    /// Monat mit nur vier), fällt der Termin AUS. Er rutscht bewusst nicht
    /// auf den 28. oder den letzten Dienstag: „am 31." heißt am 31.
    enum DayRule: Equatable {
        case dayOfMonth(Int)                     // 1…31
        case lastDayOfMonth
        case nthWeekday(nth: Int, weekday: Int)  // nth 1…5 oder `last`; weekday 1 = So … 7 = Sa
        /// Several day numbers in the selected month. This is the additive
        /// form used by the simplified monthly/yearly editor.
        case multipleDays(Set<Int>)

        /// „Der letzte" — als Zahl, damit `nthWeekday` EIN Fall bleibt.
        static let last = -1

        /// Bereinigt; nil, wenn nichts Sinnvolles übrig bleibt.
        var sanitized: DayRule? {
            switch self {
            case .dayOfMonth(let day):
                return (1...31).contains(day) ? self : nil
            case .lastDayOfMonth:
                return self
            case .nthWeekday(let nth, let weekday):
                guard (1...7).contains(weekday),
                      nth == Self.last || (1...5).contains(nth) else { return nil }
                return self
            case .multipleDays(let days):
                let sanitized = Set(days.filter { (1...31).contains($0) })
                return sanitized.isEmpty ? nil : .multipleDays(sanitized)
            }
        }
    }

    /// Wann die Regel aufhört. `after` zählt TERMINE, nicht Tage — „nach 10
    /// Malen" ist bei einer Monatsregel etwas völlig anderes als 10 Tage.
    enum End: Equatable {
        case never
        case on(String)     // Tagesschlüssel, EINSCHLIESSLICH
        case after(Int)     // N Termine ab dem Start
    }

    /// Alle Felder sind nur lesbar: die Normalisierung sitzt im Init, und ein
    /// nachträglich gesetztes `interval = 0` würde sie umgehen.
    private(set) var frequency: Frequency
    /// Jede N-te Periode (1 = jede).
    private(set) var interval: Int
    /// Wochentage als Calendar-Nummern (1 = Sonntag … 7 = Samstag).
    ///
    /// Nur bei `.weekly` bedeutsam. **Leer + fest = KEIN Termin** (das ist
    /// die Alt-Form „alle sieben Tage sind Ruhetage": nichts ist fällig,
    /// Check-ins zählen trotzdem). Die Oberfläche wählt deshalb beim
    /// Umschalten auf „wöchentlich" von sich aus einen Tag vor.
    private(set) var weekdays: Set<Int>
    /// Monats-/Jahresregel; bei `.monthly`/`.yearly` immer gesetzt (aus dem
    /// Start abgeleitet, wenn sie nicht angegeben wurde).
    private(set) var rule: DayRule?
    /// Monat der Jahresregel (1…12).
    private(set) var month: Int?
    /// Ab wann die Regel gilt. **nil = schon immer** — genau das brauchen
    /// migrierte Alt-Ziele: sie hatten nie einen Start, und ein nachträglich
    /// erfundener würde Quoten und Serien rückwirkend verändern.
    private(set) var start: String?
    private(set) var end: End
    /// Optional label for the finite recurrence cycle, shown in summaries
    /// and carried into native Calendar/Reminders titles.
    private(set) var endTitle: String?
    /// Flexibles Ziel: n zählende Tage pro Periode. nil = feste Termine.
    private(set) var timesPerPeriod: Int?
    /// Mengen-Habits: ein Tag zählt ab diesem Log-Wert. nil = Checkbox.
    private(set) var target: Int?

    static let maxInterval = 99
    static let maxOccurrences = 999

    /// Ersatz-Anker für Regeln OHNE Start: nur die PHASE eines Intervalls > 1
    /// hängt daran, und ohne Start ist die ohnehin frei erfunden. Fest
    /// verdrahtet, damit sie wenigstens reproduzierbar ist.
    static let fallbackAnchorDay = "2000-01-03"   // ein Montag

    init(frequency: Frequency = .daily,
         interval: Int = 1,
         weekdays: Set<Int> = [],
         rule: DayRule? = nil,
         month: Int? = nil,
         start: String? = nil,
         end: End = .never,
         endTitle: String? = nil,
         timesPerPeriod: Int? = nil,
         target: Int? = nil) {
        self.frequency = frequency
        self.interval = frequency == .once ? 1 : min(Self.maxInterval, max(1, interval))
        // „n× pro Tag" gibt es nicht — das IST das Mengenziel.
        let flexible: Int? = frequency == .daily || frequency == .once
            ? nil
            : timesPerPeriod.flatMap { $0 >= 1 ? min($0, Self.maxTimes(for: frequency)) : nil }
        self.timesPerPeriod = flexible
        // Wochentage gibt es nur wöchentlich; Monats-/Jahresregeln nur dort.
        // Bei einem flexiblen Ziel benennt die Regel nur die PERIODE — ein
        // Tag im Monat wäre dort bedeutungslos und fiele nur als Rauschen
        // auf die Platte. (Der Wochentag bleibt: er ist die Verabredung.)
        self.weekdays = frequency == .weekly ? weekdays.filter { (1...7).contains($0) } : []
        self.rule = flexible == nil && (frequency == .monthly || frequency == .yearly)
            ? rule?.sanitized : nil
        self.month = flexible == nil && frequency == .yearly
            ? month.flatMap { (1...12).contains($0) ? $0 : nil } : nil
        self.start = start.flatMap { DayKey.components($0) != nil ? $0 : nil }
        self.target = frequency == .once ? nil : target.flatMap { $0 > 0 ? $0 : nil }
        let normalizedEnd: End
        switch frequency == .once ? .never : end {
        case .never:
            normalizedEnd = .never
        case .on(let day):
            normalizedEnd = DayKey.components(day) != nil ? .on(day) : .never
        case .after(let n):
            normalizedEnd = n >= 1 ? .after(min(n, Self.maxOccurrences)) : .never
        }
        self.end = normalizedEnd
        self.endTitle = Self.sanitizedEndTitle(endTitle, for: normalizedEnd)
        // Feste Monats-/Jahresregeln brauchen einen konkreten Tag. Fehlt er,
        // kommt er aus dem Start — wie im Kalender, wo „monatlich" ohne
        // weitere Angabe den Tag des ersten Termins meint. Reine
        // String-Zerlegung, damit der Init ohne Calendar auskommt.
        if flexible == nil, frequency == .monthly || frequency == .yearly {
            if self.rule == nil {
                self.rule = .dayOfMonth(self.start.flatMap { DayKey.components($0)?.day } ?? 1)
            }
            if frequency == .yearly, self.month == nil {
                self.month = self.start.flatMap { DayKey.components($0)?.month } ?? 1
            }
        }
    }

    /// Wie viele Termine eine Periode überhaupt fassen kann.
    static func maxTimes(for frequency: Frequency) -> Int {
        switch frequency {
        case .once: return 1
        case .daily: return 1
        case .weekly: return 7
        case .monthly: return 31
        case .yearly: return 366
        }
    }

    var isFlexible: Bool { timesPerPeriod != nil }

    static let maxEndTitleLength = 80

    private static func sanitizedEndTitle(_ value: String?, for end: End) -> String? {
        guard case .never = end else {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { return nil }
            return String(trimmed.prefix(maxEndTitleLength))
        }
        return nil
    }

    // MARK: – Bequeme Formen

    static let daily = Recurrence()

    /// Feste Wochentage („Mo, Mi, Fr").
    static func weekdays(_ days: Set<Int>,
                         interval: Int = 1,
                         start: String? = nil,
                         end: End = .never) -> Recurrence {
        Recurrence(frequency: .weekly, interval: interval, weekdays: days,
                   start: start, end: end)
    }

    /// Flexibles Ziel („3× pro Woche"). `weekdays` ist dabei nur die
    /// VERABREDUNG (Erinnerung, Beschriftung), keine Prüfung.
    static func times(_ n: Int,
                      per frequency: Frequency,
                      interval: Int = 1,
                      weekdays: Set<Int> = [],
                      start: String? = nil,
                      end: End = .never) -> Recurrence {
        Recurrence(frequency: frequency, interval: interval, weekdays: weekdays,
                   start: start, end: end, timesPerPeriod: n)
    }

    static func monthly(_ rule: DayRule,
                        interval: Int = 1,
                        start: String? = nil,
                        end: End = .never) -> Recurrence {
        Recurrence(frequency: .monthly, interval: interval, rule: rule,
                   start: start, end: end)
    }

    static func yearly(month: Int,
                       _ rule: DayRule,
                       interval: Int = 1,
                       start: String? = nil,
                       end: End = .never) -> Recurrence {
        Recurrence(frequency: .yearly, interval: interval, rule: rule, month: month,
                   start: start, end: end)
    }

    // MARK: – Die Kernfrage

    /// Ist an diesem Tag ein Termin? Reine Rechnung, Calendar injiziert.
    func isScheduled(on day: String, calendar: Calendar = .current) -> Bool {
        schedule(calendar: calendar).isScheduled(day)
    }

    /// Alle Termine im (einschließenden) Fenster, aufsteigend.
    func occurrences(in range: ClosedRange<String>,
                     calendar: Calendar = .current,
                     limit: Int = 1000) -> [String] {
        schedule(calendar: calendar).occurrences(in: range, limit: limit)
    }

    /// Der nächste Termin NACH diesem Tag; nil, wenn keiner mehr kommt.
    func nextOccurrence(after day: String, calendar: Calendar = .current) -> String? {
        schedule(calendar: calendar).next(after: day)
    }

    /// Einmal aufgelöste Regel — siehe `Schedule`.
    func schedule(calendar: Calendar = .current) -> Schedule {
        Schedule(self, calendar: calendar)
    }
}

// MARK: – Aufgelöster Fahrplan

extension Recurrence {
    /// Die EINMAL aufgelöste Regel. Es gibt sie aus einem einzigen Grund:
    /// Tempo. `isScheduled` beantwortet 365 Rasterzellen und jede Serie läuft
    /// über die halbe Historie — die Ende-Auflösung („nach 10 Terminen" muss
    /// zehn Termine abzählen) darf dabei nicht pro Tag noch einmal laufen.
    /// Alle Rechenfunktionen der GoalEngine ziehen sich deshalb EINEN
    /// Fahrplan und fragen den.
    struct Schedule {
        let recurrence: Recurrence
        let calendar: Calendar
        /// Start als Tagesbeginn; nil = gilt schon immer.
        let startDate: Date?
        /// Anker für die Phase eines Intervalls > 1.
        let anchor: Date
        /// Letzter gültiger Tag (aus `.on` bzw. aus `.after` abgezählt);
        /// nil = offenes Ende.
        let lastDay: String?

        /// Wie weit vorwärts überhaupt nach einem Termin gesucht wird. Eine
        /// Regel kann leer laufen („jeden 31. Februar"), also braucht die
        /// Suche eine Grenze statt einer Endlosschleife.
        private static let maxPeriodSteps = 400

        init(_ recurrence: Recurrence, calendar: Calendar) {
            let open = Schedule(recurrence, calendar: calendar, lastDay: nil)
            switch recurrence.end {
            case .never:
                self = open
            case .on(let day):
                self = Schedule(recurrence, calendar: calendar,
                                lastDay: DayKey.isValid(day, calendar: calendar) ? day : nil)
            case .after(let n):
                // Ohne Start lässt sich nichts abzählen -> offenes Ende.
                self = Schedule(recurrence, calendar: calendar, lastDay: open.nthOccurrence(n))
            }
        }

        private init(_ recurrence: Recurrence, calendar: Calendar, lastDay: String?) {
            let start = recurrence.start.flatMap { DayKey.date(from: $0, calendar: calendar) }
            self.recurrence = recurrence
            self.calendar = calendar
            self.startDate = start
            self.anchor = start
                ?? DayKey.date(from: Recurrence.fallbackAnchorDay, calendar: calendar)
                ?? Date(timeIntervalSince1970: 0)
            self.lastDay = lastDay
        }

        // MARK: Termin-Prüfung

        func isScheduled(_ day: String) -> Bool {
            guard let date = DayKey.date(from: day, calendar: calendar) else { return false }
            // Tagesschlüssel sind nullgepolstert — Stringvergleich IST hier
            // der Datumsvergleich.
            if let start = recurrence.start, day < start { return false }
            if let lastDay, day > lastDay { return false }
            return matchesPattern(date)
        }

        /// Nur das MUSTER (ohne Start-/Ende-Grenzen).
        func matchesPattern(_ date: Date) -> Bool {
            switch recurrence.frequency {
            case .once:
                guard let startDate else { return false }
                return calendar.isDate(date, inSameDayAs: startDate)
            case .daily:
                guard recurrence.interval > 1 else { return true }
                return mod(dayDiff(from: anchor, to: date), recurrence.interval) == 0
            case .weekly:
                guard let week = periodStart(for: date), isActivePeriod(week) else { return false }
                if recurrence.isFlexible { return true }
                return recurrence.weekdays.contains(calendar.component(.weekday, from: date))
            case .monthly:
                guard let month = periodStart(for: date), isActivePeriod(month) else { return false }
                if recurrence.isFlexible { return true }
                return matchesRule(date)
            case .yearly:
                guard let year = periodStart(for: date), isActivePeriod(year) else { return false }
                if recurrence.isFlexible { return true }
                guard calendar.component(.month, from: date) == (recurrence.month ?? 1) else { return false }
                return matchesRule(date)
            }
        }

        private func matchesRule(_ date: Date) -> Bool {
            let day = calendar.component(.day, from: date)
            let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 31
            switch recurrence.rule ?? .dayOfMonth(1) {
            case .dayOfMonth(let wanted):
                return day == wanted
            case .lastDayOfMonth:
                return day == daysInMonth
            case .nthWeekday(let nth, let weekday):
                guard calendar.component(.weekday, from: date) == weekday else { return false }
                if nth == DayRule.last { return day + 7 > daysInMonth }
                return (day - 1) / 7 + 1 == nth
            case .multipleDays(let days):
                return days.contains(day)
            }
        }

        // MARK: Perioden

        /// Die Kalendereinheit, in der diese Regel denkt.
        var periodUnit: Calendar.Component {
            switch recurrence.frequency {
            case .once: return .day
            case .daily: return .day
            case .weekly: return .weekOfYear
            case .monthly: return .month
            case .yearly: return .year
            }
        }

        /// Anfang der Periode, in der dieser Tag liegt (Wochenanfang nach
        /// `firstWeekday` des Nutzers, Monats-/Jahresanfang).
        func periodStart(for date: Date) -> Date? {
            if periodUnit == .day { return calendar.startOfDay(for: date) }
            return calendar.dateInterval(of: periodUnit, for: date)?.start
        }

        func periodStart(forDay day: String) -> Date? {
            DayKey.date(from: day, calendar: calendar).flatMap { periodStart(for: $0) }
        }

        /// Fällt diese Periode ins Raster des Intervalls?
        func isActivePeriod(_ periodStart: Date) -> Bool {
            guard recurrence.interval > 1 else { return true }
            guard let anchorPeriod = self.periodStart(for: anchor) else { return true }
            return mod(periodDiff(from: anchorPeriod, to: periodStart), recurrence.interval) == 0
        }

        func periodDiff(from: Date, to: Date) -> Int {
            calendar.dateComponents([periodUnit], from: from, to: to).value(for: periodUnit) ?? 0
        }

        func shiftPeriod(_ periodStart: Date, by n: Int) -> Date? {
            calendar.date(byAdding: periodUnit, value: n, to: periodStart)
                .flatMap { self.periodStart(for: $0) }
        }

        /// Die nächste AKTIVE Periode nach dieser (auch, wenn diese selbst
        /// nicht aktiv ist).
        func nextActivePeriod(after periodStart: Date) -> Date? {
            let step = recurrence.interval
            guard step > 1, let anchorPeriod = self.periodStart(for: anchor) else {
                return shiftPeriod(periodStart, by: 1)
            }
            let diff = periodDiff(from: anchorPeriod, to: periodStart)
            let rest = mod(diff, step)
            return shiftPeriod(periodStart, by: step - rest)
        }

        /// Die vorige AKTIVE Periode.
        func previousActivePeriod(before periodStart: Date) -> Date? {
            let step = recurrence.interval
            guard step > 1, let anchorPeriod = self.periodStart(for: anchor) else {
                return shiftPeriod(periodStart, by: -1)
            }
            let diff = periodDiff(from: anchorPeriod, to: periodStart)
            let rest = mod(diff, step)
            return shiftPeriod(periodStart, by: rest == 0 ? -step : -rest)
        }

        // MARK: Vorwärtssuche

        /// Erster Termin an oder nach diesem Tag.
        func first(onOrAfter day: String) -> String? {
            guard let raw = DayKey.date(from: day, calendar: calendar) else { return nil }
            var cursor = calendar.startOfDay(for: raw)
            if let startDate, cursor < startDate { cursor = startDate }
            let cursorKey = DayKey.key(for: cursor, calendar: calendar)
            if let lastDay, cursorKey > lastDay { return nil }
            guard let found = search(from: cursor) else { return nil }
            if let lastDay, found > lastDay { return nil }
            return found
        }

        func next(after day: String) -> String? {
            guard let following = DayKey.shifted(day, by: 1, calendar: calendar) else { return nil }
            return first(onOrAfter: following)
        }

        func occurrences(in range: ClosedRange<String>, limit: Int) -> [String] {
            var out: [String] = []
            var cursor = first(onOrAfter: range.lowerBound)
            while let day = cursor, day <= range.upperBound, out.count < limit {
                out.append(day)
                cursor = next(after: day)
            }
            return out
        }

        /// Der n-te Termin ab dem Start (1-basiert) — die Grundlage für
        /// „endet nach N Terminen". Ohne Start gibt es nichts abzuzählen.
        func nthOccurrence(_ n: Int) -> String? {
            guard n >= 1, let start = recurrence.start else { return nil }
            var day = first(onOrAfter: start)
            var i = 1
            while let current = day, i < n {
                day = next(after: current)
                i += 1
            }
            return day
        }

        /// Sucht periodenweise vorwärts — nie Tag für Tag. „Alle 3 Monate am
        /// letzten Freitag" springt so von Kandidat zu Kandidat, statt
        /// neunzig Tage einzeln zu prüfen.
        private func search(from cursor: Date) -> String? {
            let cursorDay = calendar.startOfDay(for: cursor)
            switch recurrence.frequency {
            case .once:
                guard let startDate, startDate >= cursorDay else { return nil }
                return DayKey.key(for: startDate, calendar: calendar)
            case .daily:
                let interval = recurrence.interval
                guard interval > 1 else { return DayKey.key(for: cursorDay, calendar: calendar) }
                let rest = mod(dayDiff(from: anchor, to: cursorDay), interval)
                let add = rest == 0 ? 0 : interval - rest
                return calendar.date(byAdding: .day, value: add, to: cursorDay)
                    .map { DayKey.key(for: $0, calendar: calendar) }
            case .weekly:
                guard recurrence.isFlexible || !recurrence.weekdays.isEmpty else { return nil }
                guard var week = periodStart(for: cursorDay) else { return nil }
                for _ in 0..<Self.maxPeriodSteps {
                    if isActivePeriod(week) {
                        if recurrence.isFlexible {
                            return DayKey.key(for: max(week, cursorDay), calendar: calendar)
                        }
                        for offset in 0..<7 {
                            guard let day = calendar.date(byAdding: .day, value: offset, to: week),
                                  day >= cursorDay,
                                  recurrence.weekdays.contains(calendar.component(.weekday, from: day))
                            else { continue }
                            return DayKey.key(for: day, calendar: calendar)
                        }
                    }
                    guard let following = shiftPeriod(week, by: 1) else { return nil }
                    week = following
                }
                return nil
            case .monthly, .yearly:
                guard var period = periodStart(for: cursorDay) else { return nil }
                for _ in 0..<Self.maxPeriodSteps {
                    if isActivePeriod(period) {
                        if recurrence.isFlexible {
                            return DayKey.key(for: max(period, cursorDay), calendar: calendar)
                        }
                        if let day = ruleDay(inPeriod: period), day >= cursorDay {
                            return DayKey.key(for: day, calendar: calendar)
                        }
                    }
                    guard let following = shiftPeriod(period, by: 1) else { return nil }
                    period = following
                }
                return nil
            }
        }

        /// Die Tage, die eine Monats-/Jahresregel in dieser Periode trifft —
        /// leer, wenn die Periode keinen passenden Tag hat (31. im Februar,
        /// 5. Dienstag in einem Vier-Dienstage-Monat).
        func ruleDays(inPeriod periodStart: Date) -> [Date] {
            var monthStart = periodStart
            if recurrence.frequency == .yearly {
                var comps = calendar.dateComponents([.year], from: periodStart)
                comps.month = recurrence.month ?? 1
                comps.day = 1
                guard let start = calendar.date(from: comps) else { return [] }
                monthStart = start
            }
            guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
            let daysInMonth = range.count
            var comps = calendar.dateComponents([.year, .month], from: monthStart)
            switch recurrence.rule ?? .dayOfMonth(1) {
            case .dayOfMonth(let day):
                guard day <= daysInMonth else { return [] }
                comps.day = day
                return calendar.date(from: comps).map { [$0] } ?? []
            case .lastDayOfMonth:
                comps.day = daysInMonth
                return calendar.date(from: comps).map { [$0] } ?? []
            case .nthWeekday(let nth, let weekday):
                var hits: [Date] = []
                for day in 1...daysInMonth {
                    comps.day = day
                    guard let date = calendar.date(from: comps),
                          calendar.component(.weekday, from: date) == weekday else { continue }
                    hits.append(date)
                }
                if nth == DayRule.last { return hits.last.map { [$0] } ?? [] }
                guard nth >= 1, nth <= hits.count else { return [] }
                return [hits[nth - 1]]
            case .multipleDays(let days):
                return days.sorted().compactMap { day in
                    guard day <= daysInMonth else { return nil }
                    comps.day = day
                    return calendar.date(from: comps)
                }
            }
        }

        func ruleDay(inPeriod periodStart: Date) -> Date? {
            ruleDays(inPeriod: periodStart).first
        }

        // MARK: Kleinkram

        func dayDiff(from: Date, to: Date) -> Int {
            calendar.dateComponents([.day],
                                    from: calendar.startOfDay(for: from),
                                    to: calendar.startOfDay(for: to)).day ?? 0
        }

        /// Modulo, das auch für negative Zahlen im Bereich 0..<n bleibt —
        /// `%` in Swift tut das nicht, und Tage VOR dem Anker sind negativ.
        private func mod(_ a: Int, _ n: Int) -> Int {
            guard n > 0 else { return 0 }
            let r = a % n
            return r < 0 ? r + n : r
        }
    }
}

// MARK: – Altes Ziel-Format (nur noch Migrationsquelle)

/// Das Ziel-Format der ausgelieferten Versionen: flach, tolerant dekodiert.
/// Es wird NICHT mehr ausgewertet — es wird gelesen und in eine `Recurrence`
/// übersetzt (`Recurrence.from(legacy:)`), und dorthin zurück geschrieben,
/// solange die neue Regel sich darin ausdrücken lässt (siehe
/// `Recurrence.legacyMirror`). Damit liest ein ausgelieferter Build seine
/// eigene Datei weiter — ohne Versionssprung, der ihn aussperren würde.
struct LegacyGoal: Equatable {
    enum Cadence: Equatable {
        case daily
        case weekly(times: Int)
    }

    var cadence: Cadence
    /// Ruhetage als Calendar-Wochentagsnummern (1 = So … 7 = Sa).
    var restDays: Set<Int>
    var target: Int?
    /// Fester Wochentag der Wochen-Kadenz; nil = frei wählbar.
    var weekday: Int?

    /// Dieselbe Normalisierung wie früher: ein fester Tag zieht `times` auf 1,
    /// ein Tag außerhalb 1…7 fällt weg, täglich kennt keinen festen Tag.
    init(cadence: Cadence = .daily, restDays: Set<Int> = [], target: Int? = nil, weekday: Int? = nil) {
        let day = weekday.flatMap { (1...7).contains($0) ? $0 : nil }
        if case .weekly(let times) = cadence {
            self.cadence = .weekly(times: day != nil ? 1 : min(7, max(1, times)))
            self.weekday = day
        } else {
            self.cadence = .daily
            self.weekday = nil
        }
        self.restDays = restDays.filter { (1...7).contains($0) }
        self.target = target.flatMap { $0 > 0 ? $0 : nil }
    }

    static let daily = LegacyGoal()
    static func weekly(times: Int, weekday: Int? = nil) -> LegacyGoal {
        LegacyGoal(cadence: .weekly(times: times), weekday: weekday)
    }
}

extension LegacyGoal: Codable {
    enum CodingKeys: String, CodingKey { case cadence, times, restDays, target, weekday }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decodeIfPresent(String.self, forKey: .cadence) ?? "daily"
        let raw: Cadence = kind == "weekly"
            ? .weekly(times: try c.decodeIfPresent(Int.self, forKey: .times) ?? 1)
            : .daily   // unbekannte Werte tolerant als Standard lesen
        self = LegacyGoal(cadence: raw,
                          restDays: Set(try c.decodeIfPresent([Int].self, forKey: .restDays) ?? []),
                          target: try c.decodeIfPresent(Int.self, forKey: .target),
                          weekday: try c.decodeIfPresent(Int.self, forKey: .weekday))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try encodeMirror(into: &c)
    }

    /// Schreibt die Alt-Schlüssel in einen SCHON offenen Container — so
    /// liegen neue und alte Darstellung derselben Regel nebeneinander in
    /// EINEM Objekt.
    func encodeMirror(into c: inout KeyedEncodingContainer<CodingKeys>) throws {
        switch cadence {
        case .daily:
            try c.encode("daily", forKey: .cadence)
        case .weekly(let times):
            try c.encode("weekly", forKey: .cadence)
            try c.encode(times, forKey: .times)
            try c.encodeIfPresent(weekday, forKey: .weekday)
        }
        if !restDays.isEmpty { try c.encode(restDays.sorted(), forKey: .restDays) }
        if let target { try c.encode(target, forKey: .target) }
    }
}

// MARK: – Migration (rein)

extension Recurrence {
    /// Alt-Ziel -> Wiederholungsregel. REIN und verlustfrei in dem, was
    /// zählt: jede Alt-Form landet auf einer Regel, die dieselben Antworten
    /// gibt (Termine, Serien, Quoten).
    ///
    ///  | alt                                   | neu                                          |
    ///  |---------------------------------------|----------------------------------------------|
    ///  | `.daily`                              | täglich, Intervall 1                          |
    ///  | `.daily` + Ruhetage R                 | wöchentlich an den Tagen 1…7 ohne R           |
    ///  | `.daily` + alle 7 Tage Ruhetag        | wöchentlich mit LEERER Tagesmenge (kein Termin) |
    ///  | `.weekly(times: n)`                   | wöchentlich, flexibel n× pro Woche             |
    ///  | `.weekly(times: 1)` + Wochentag d      | wöchentlich, flexibel 1×, Tag d als Verabredung |
    ///  | `+ target t`                          | `+ target t`                                   |
    ///
    /// Kein Startdatum: Alt-Ziele galten „schon immer". Ein aus `createdAt`
    /// erfundener Start würde jede bestehende Quote rückwirkend ändern.
    /// Ruhetage einer WOCHEN-Kadenz fallen weg — sie haben auch vorher nichts
    /// bewirkt (`isRestDay` galt nur für `.daily`).
    static func from(legacy goal: LegacyGoal) -> Recurrence {
        switch goal.cadence {
        case .daily:
            guard !goal.restDays.isEmpty else {
                return Recurrence(frequency: .daily, target: goal.target)
            }
            return Recurrence(frequency: .weekly,
                              weekdays: Set(1...7).subtracting(goal.restDays),
                              target: goal.target)
        case .weekly(let times):
            return Recurrence(frequency: .weekly,
                              weekdays: goal.weekday.map { [$0] } ?? [],
                              timesPerPeriod: times,
                              target: goal.target)
        }
    }

    /// Dieselbe Regel im ALTEN Format — oder nil, wenn sie sich dort nicht
    /// ausdrücken lässt (Intervall > 1, Monats-/Jahresregeln, Start, Ende).
    /// Wird zusätzlich zur neuen Darstellung geschrieben, damit ein
    /// ausgelieferter Build dieselbe Datei unverändert weiterversteht.
    var legacyMirror: LegacyGoal? {
        guard interval == 1, start == nil, end == .never else { return nil }
        switch frequency {
        case .once:
            return nil
        case .daily:
            return LegacyGoal(cadence: .daily, target: target)
        case .weekly:
            if let times = timesPerPeriod {
                if weekdays.isEmpty {
                    return LegacyGoal(cadence: .weekly(times: times), target: target)
                }
                guard weekdays.count == 1, times == 1 else { return nil }
                return LegacyGoal(cadence: .weekly(times: 1), target: target, weekday: weekdays.first)
            }
            if weekdays.count == 7 { return LegacyGoal(cadence: .daily, target: target) }
            guard !weekdays.isEmpty else { return nil }
            return LegacyGoal(cadence: .daily,
                              restDays: Set(1...7).subtracting(weekdays),
                              target: target)
        case .monthly, .yearly:
            return nil
        }
    }
}

// MARK: – Codable (tolerant, ohne Versionssprung)

extension Recurrence: Codable {
    private enum CodingKeys: String, CodingKey {
        // Neu:
        case freq, interval, weekdays, ruleKind, ruleDay, ruleDays, ruleNth, ruleWeekday
        case month, start, endDate, endCount, endTitle
        // Geteilt mit dem Alt-Format (gleiche Bedeutung, deshalb derselbe Schlüssel):
        case times, target
        // Nur alt (der Spiegel):
        case cadence, restDays, weekday
    }

    /// Fehlt `freq` (oder steht dort etwas Unbekanntes), ist das eine Datei
    /// aus einer ausgelieferten Version — dann wird das ALTE Ziel gelesen und
    /// migriert. Genau dieselbe Regel greift für eine Datei aus einer
    /// NEUEREN Version mit unbekannter Häufigkeit: lieber der gespiegelte
    /// Alt-Stand als ein Fehler, der das ganze Habit verlieren würde.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let raw = try c.decodeIfPresent(String.self, forKey: .freq),
              let frequency = Frequency(rawValue: raw) else {
            self = Recurrence.from(legacy: try LegacyGoal(from: decoder))
            return
        }
        let rule: DayRule?
        switch try c.decodeIfPresent(String.self, forKey: .ruleKind) {
        case "day":
            rule = (try c.decodeIfPresent(Int.self, forKey: .ruleDay)).map { DayRule.dayOfMonth($0) }
        case "lastDay":
            rule = .lastDayOfMonth
        case "nth":
            let nth = try c.decodeIfPresent(Int.self, forKey: .ruleNth) ?? 1
            let weekday = try c.decodeIfPresent(Int.self, forKey: .ruleWeekday) ?? 2
            rule = .nthWeekday(nth: nth, weekday: weekday)
        case "multiple":
            rule = .multipleDays(Set(try c.decodeIfPresent([Int].self,
                                                            forKey: .ruleDays) ?? []))
        default:
            rule = nil
        }
        let end: End
        if let day = try c.decodeIfPresent(String.self, forKey: .endDate) {
            end = .on(day)
        } else if let count = try c.decodeIfPresent(Int.self, forKey: .endCount) {
            end = .after(count)
        } else {
            end = .never
        }
        // Über den bezeichneten Init, damit die Normalisierung für Dateien
        // GENAUSO gilt wie für die Oberfläche.
        self = Recurrence(
            frequency: frequency,
            interval: try c.decodeIfPresent(Int.self, forKey: .interval) ?? 1,
            weekdays: Set(try c.decodeIfPresent([Int].self, forKey: .weekdays) ?? []),
            rule: rule,
            month: try c.decodeIfPresent(Int.self, forKey: .month),
            start: try c.decodeIfPresent(String.self, forKey: .start),
            end: end,
            endTitle: try c.decodeIfPresent(String.self, forKey: .endTitle),
            timesPerPeriod: try c.decodeIfPresent(Int.self, forKey: .times),
            target: try c.decodeIfPresent(Int.self, forKey: .target))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(frequency.rawValue, forKey: .freq)
        if interval != 1 { try c.encode(interval, forKey: .interval) }
        if !weekdays.isEmpty { try c.encode(weekdays.sorted(), forKey: .weekdays) }
        switch rule {
        case .dayOfMonth(let day)?:
            try c.encode("day", forKey: .ruleKind)
            try c.encode(day, forKey: .ruleDay)
        case .lastDayOfMonth?:
            try c.encode("lastDay", forKey: .ruleKind)
        case .nthWeekday(let nth, let weekday)?:
            try c.encode("nth", forKey: .ruleKind)
            try c.encode(nth, forKey: .ruleNth)
            try c.encode(weekday, forKey: .ruleWeekday)
        case .multipleDays(let days)?:
            try c.encode("multiple", forKey: .ruleKind)
            try c.encode(days.sorted(), forKey: .ruleDays)
        case nil:
            break
        }
        try c.encodeIfPresent(month, forKey: .month)
        try c.encodeIfPresent(start, forKey: .start)
        switch end {
        case .never: break
        case .on(let day): try c.encode(day, forKey: .endDate)
        case .after(let n): try c.encode(n, forKey: .endCount)
        }
        try c.encodeIfPresent(endTitle, forKey: .endTitle)
        // `times` und `target` teilen sich den Schlüssel mit dem Alt-Format —
        // der Spiegel darf sie deshalb nicht noch einmal schreiben.
        try c.encodeIfPresent(timesPerPeriod, forKey: .times)
        try c.encodeIfPresent(target, forKey: .target)
        if let mirror = legacyMirror {
            var legacy = encoder.container(keyedBy: LegacyGoal.CodingKeys.self)
            try mirror.encodeMirror(into: &legacy)
        }
    }
}
