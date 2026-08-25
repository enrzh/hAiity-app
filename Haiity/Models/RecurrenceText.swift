import Foundation

/// Die Regel als EIN Satz, den ein Mensch liest: „Jeden Montag und
/// Donnerstag", „Am letzten Freitag im Monat", „3× pro Woche, gedacht am
/// Dienstag". Rein und mit injiziertem Kalender — Wochentagsnamen,
/// Monatsnamen und die Reihenfolge der Tage kommen aus dessen Locale bzw.
/// `firstWeekday`, damit derselbe Satz in der Oberfläche und im Test
/// entsteht.
enum RecurrenceText {

    /// Der ganze Satz: Muster, optionale Uhrzeit („… um 07:30") und Ende
    /// („…, bis 31.12.2026").
    ///
    /// Die Uhrzeit gehört zum HABIT, nicht zur Regel (siehe
    /// `Habit.timeMinutes`) — sie kommt deshalb von außen herein und steht
    /// zwischen Muster und Ende, wo ein Mensch sie erwartet: „Jeden Montag um
    /// 07:30, bis 31.12.2026".
    static func summary(_ recurrence: Recurrence,
                        timeMinutes: Int? = nil,
                        calendar: Calendar = .current) -> String {
        var text = pattern(recurrence, calendar: calendar)
        if let clock = timeText(timeMinutes) {
            text += String(localized: " um \(clock)")
        }
        guard let tail = endClause(recurrence, calendar: calendar) else { return text }
        return text + tail
    }

    /// Minuten seit Mitternacht als „07:30". nil für nil und für alles
    /// außerhalb eines Tages — dieselbe Grenze wie `Habit.sanitizedMinutes`,
    /// damit ein kaputter Wert nirgends als „25:00" auftaucht.
    static func timeText(_ minutes: Int?) -> String? {
        guard let minutes, (0..<24 * 60).contains(minutes) else { return nil }
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    // MARK: – Muster

    static func pattern(_ recurrence: Recurrence, calendar: Calendar = .current) -> String {
        if let times = recurrence.timesPerPeriod {
            return flexible(times: times, recurrence: recurrence, calendar: calendar)
        }
        switch recurrence.frequency {
        case .once:
            guard let start = recurrence.start else { return String(localized: "Keine Termine") }
            if calendar.locale?.language.languageCode?.identifier == "en" {
                return "Once on \(dayText(start))"
            }
            return String(localized: "Einmal am \(dayText(start))")
        case .daily:
            return recurrence.interval == 1
                ? String(localized: "Jeden Tag")
                : String(localized: "Alle \(recurrence.interval) Tage")
        case .weekly:
            guard !recurrence.weekdays.isEmpty else {
                // Eine Wochenregel ohne Tage sieht nichts vor. Ehrlicher
                // Satz statt eines erfundenen Tages (siehe `Recurrence`).
                return String(localized: "Keine Termine")
            }
            let days = weekdayList(recurrence.weekdays, calendar: calendar)
            return recurrence.interval == 1
                ? String(localized: "Jeden \(days)")
                : String(localized: "Jeden \(recurrence.interval). \(days)")
        case .monthly:
            let rule = ruleText(recurrence.rule, calendar: calendar)
            guard recurrence.interval == 1 else {
                return String(localized: "Alle \(recurrence.interval) Monate am \(rule.short)")
            }
            return rule.monthly
        case .yearly:
            let rule = ruleText(recurrence.rule, calendar: calendar)
            let month = monthName(recurrence.month ?? 1, calendar: calendar)
            let when = rule.inMonth(month)
            return recurrence.interval == 1
                ? String(localized: "Jedes Jahr am \(when)")
                : String(localized: "Alle \(recurrence.interval) Jahre am \(when)")
        }
    }

    /// „3× pro Woche", „5× alle 2 Monate", jeweils mit der optionalen
    /// Verabredung („…, gedacht am Dienstag").
    private static func flexible(times: Int, recurrence: Recurrence, calendar: Calendar) -> String {
        let count = times == 1 ? String(localized: "Einmal") : String(localized: "\(times)×")
        var sentence: String
        switch (recurrence.frequency, recurrence.interval) {
        case (.once, _):    sentence = String(localized: "Keine Termine")
        case (.weekly, 1):  sentence = String(localized: "\(count) pro Woche")
        case (.weekly, let n): sentence = String(localized: "\(count) alle \(n) Wochen")
        case (.monthly, 1): sentence = String(localized: "\(count) pro Monat")
        case (.monthly, let n): sentence = String(localized: "\(count) alle \(n) Monate")
        case (.yearly, 1):  sentence = String(localized: "\(count) pro Jahr")
        case (.yearly, let n): sentence = String(localized: "\(count) alle \(n) Jahre")
        case (.daily, _):   sentence = String(localized: "Jeden Tag")
        }
        if !recurrence.weekdays.isEmpty {
            let days = weekdayList(recurrence.weekdays, calendar: calendar)
            sentence += String(localized: ", gedacht am \(days)")
        }
        return sentence
    }

    // MARK: – Monats-/Jahresregel

    /// Drei Formen derselben Regel: die kurze („15.", „letzten Freitag"), die
    /// monatliche („Am 15. jedes Monats") und die mit Monatsnamen („15. März").
    private struct RuleText {
        let short: String
        let monthly: String
        let inMonth: (String) -> String
    }

    private static func ruleText(_ rule: Recurrence.DayRule?, calendar: Calendar) -> RuleText {
        switch rule ?? .dayOfMonth(1) {
        case .dayOfMonth(let day):
            return RuleText(
                short: String(localized: "\(day)."),
                monthly: String(localized: "Am \(day). jedes Monats"),
                // EIGENER Schlüssel, obwohl der deutsche Satz („15. März")
                // zeichengleich mit dem des n-ten Wochentags („3. Freitag")
                // ist: das sind zwei GRAMMATIKEN, nicht ein Text. Deutsch
                // verdeckt das; „the 15 March" und „the 3rd Friday" brauchen
                // in fast jeder anderen Sprache verschiedene Sätze.
                inMonth: { month in
                    String(localized: "recurrence.date.dayInMonth",
                           defaultValue: "\(day). \(month)",
                           comment: "Tag + Monatsname einer Jahresregel: „15. März“") })
        case .lastDayOfMonth:
            return RuleText(
                short: String(localized: "letzten Tag"),
                monthly: String(localized: "Am letzten Tag des Monats"),
                inMonth: { month in String(localized: "letzten Tag im \(month)") })
        case .nthWeekday(let nth, let weekday):
            let name = weekdayName(weekday, calendar: calendar)
            if nth == Recurrence.DayRule.last {
                return RuleText(
                    short: String(localized: "letzten \(name)"),
                    monthly: String(localized: "Am letzten \(name) im Monat"),
                    inMonth: { month in String(localized: "letzten \(name) im \(month)") })
            }
            // Die Position als fertige ORDNUNGSZAHL, nicht als nackte Zahl:
            // ein `%lld` kann im Englischen nur „the 3. Friday" werden.
            let position = ordinal(nth, locale: calendar.locale ?? .current)
            return RuleText(
                short: String(localized: "recurrence.nthWeekday.short",
                              defaultValue: "\(position) \(name)",
                              comment: "Kurzform des n-ten Wochentags: „3. Freitag“"),
                monthly: String(localized: "recurrence.nthWeekday.monthly",
                                defaultValue: "Am \(position) \(name) im Monat",
                                comment: "Monatsregel: „Am 3. Freitag im Monat“"),
                inMonth: { month in
                    String(localized: "recurrence.nthWeekday.inMonth",
                           defaultValue: "\(position) \(name) im \(month)",
                           comment: "Jahresregel: „3. Freitag im März“") })
        case .multipleDays(let days):
            let list = days.sorted().map { "\($0)." }.joined(separator: ", ")
            return RuleText(
                short: list,
                monthly: String(localized: "recurrence.multipleDays.monthly",
                                defaultValue: "Am \(list) jedes Monats",
                                comment: "Mehrere Monatstage: „Am 5., 15. jedes Monats“"),
                inMonth: { month in
                    String(localized: "recurrence.multipleDays.inMonth",
                           defaultValue: "\(list) im \(month)",
                           comment: "Mehrere Tage einer Jahresregel: „5., 15. im März“") })
        case .multipleMonthDays(let dates):
            let list = dates.sorted()
                .map { String(format: "%02d.%02d.", $0.day, $0.month) }
                .joined(separator: ", ")
            return RuleText(
                short: list,
                monthly: String(localized: "recurrence.multipleMonthDays.monthly",
                                defaultValue: "Am \(list)",
                                comment: "Mehrere Tage einer Jahresregel"),
                inMonth: { _ in
                    String(localized: "recurrence.multipleMonthDays.inYear",
                           defaultValue: "\(list)",
                           comment: "Mehrere Monatstage einer Jahresregel: „12.03., 05.10.“") })
        }
    }

    /// Die Position als Ordnungszahl in der Sprache des Nutzers — „3." (de),
    /// „3rd" (en), „3." (tr), „第3" (ja), „3번째" (ko), „ke-3" (id).
    ///
    /// Der Katalog kann das nicht: eine feste Zeichenkette mit `%lld` müsste
    /// sich im Englischen zwischen 1st/2nd/3rd/4th entscheiden, bevor die
    /// Zahl bekannt ist. Die Regeln dafür stecken in ICU, und `NumberFormatter`
    /// ist der Weg dorthin. Wo eine Sprache gar keine eigene Form kennt (ru,
    /// ar), kommt die blanke Zahl zurück und die Grammatik ringsherum steht
    /// im Katalog.
    ///
    /// `Recurrence.DayRule.last` (-1) kommt hier NIE an — „der letzte Freitag"
    /// ist ein eigener Satz, keine Ordnungszahl.
    static func ordinal(_ n: Int, locale: Locale = .current) -> String {
        formatter(for: locale).string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// Ein `NumberFormatter` je Sprache. Der Ordnungszahl-Stil zieht ein
    /// ICU-Regelwerk hoch; das lohnt sich nicht pro Habit-Karte neu.
    private static let formatterLock = NSLock()
    private static var formatters: [String: NumberFormatter] = [:]

    private static func formatter(for locale: Locale) -> NumberFormatter {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        if let cached = formatters[locale.identifier] { return cached }
        let made = NumberFormatter()
        made.numberStyle = .ordinal
        made.locale = locale
        formatters[locale.identifier] = made
        return made
    }

    // MARK: – Ende

    private static func endClause(_ recurrence: Recurrence, calendar: Calendar) -> String? {
        let clause: String
        switch recurrence.end {
        case .never:
            return nil
        case .on(let day):
            clause = String(localized: ", bis \(dayText(day))")
        case .after(let n):
            clause = n == 1
                ? String(localized: ", endet nach 1 Termin")
                : String(localized: ", endet nach \(n) Terminen")
        }
        guard let title = recurrence.endTitle else { return clause }
        return clause + String(localized: "recurrence.end.titleSuffix",
                               defaultValue: " (\(title))",
                               comment: "Optionaler Titel eines endlichen Wiederholungszyklus")
    }

    /// Tagesschlüssel als deutsches Datum. Bewusst von Hand gesetzt und
    /// nicht über einen DateFormatter: der Satz ringsherum ist deutsch, also
    /// ist es das Datum darin auch — und der Test bekommt eine feste Form.
    static func dayText(_ day: String) -> String {
        guard let parts = DayKey.components(day) else { return day }
        return String(format: "%02d.%02d.%04d", parts.day, parts.month, parts.year)
    }

    // MARK: – Namen

    /// Wochentage in der Reihenfolge des Nutzerkalenders, mit „und" verbunden.
    static func weekdayList(_ weekdays: Set<Int>, calendar: Calendar = .current) -> String {
        let names = ordered(weekdays, calendar: calendar).map { weekdayName($0, calendar: calendar) }
        guard names.count > 1 else { return names.first ?? "" }
        let formatter = ListFormatter()
        formatter.locale = calendar.locale ?? .current
        return formatter.string(from: names) ?? names.joined(separator: ", ")
    }

    /// 1 = Sonntag … 7 = Samstag, sortiert ab `firstWeekday`.
    static func ordered(_ weekdays: Set<Int>, calendar: Calendar = .current) -> [Int] {
        weekdays.filter { (1...7).contains($0) }
            .sorted { position($0, calendar: calendar) < position($1, calendar: calendar) }
    }

    private static func position(_ weekday: Int, calendar: Calendar) -> Int {
        (weekday - calendar.firstWeekday + 7) % 7
    }

    static func weekdayName(_ weekday: Int, calendar: Calendar = .current) -> String {
        let symbols = calendar.weekdaySymbols
        guard weekday >= 1, weekday <= symbols.count else { return "" }
        return symbols[weekday - 1]
    }

    static func shortWeekdayName(_ weekday: Int, calendar: Calendar = .current) -> String {
        let symbols = calendar.shortWeekdaySymbols
        guard weekday >= 1, weekday <= symbols.count else { return "" }
        let symbol = symbols[weekday - 1]
        return symbol.hasSuffix(".") ? String(symbol.dropLast()) : symbol
    }

    static func monthName(_ month: Int, calendar: Calendar = .current) -> String {
        let symbols = calendar.monthSymbols
        guard month >= 1, month <= symbols.count else { return "" }
        return symbols[month - 1]
    }
}
