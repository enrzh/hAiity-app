import Foundation

/// Die Regel als EIN Satz, den ein Mensch liest: „Jeden Montag und
/// Donnerstag", „Am letzten Freitag im Monat", „3× pro Woche, gedacht am
/// Dienstag". Rein und mit injiziertem Kalender — Wochentagsnamen,
/// Monatsnamen und die Reihenfolge der Tage kommen aus dessen Locale bzw.
/// `firstWeekday`, damit derselbe Satz in der Oberfläche und im Test
/// entsteht.
enum RecurrenceText {

    /// Der ganze Satz: Muster plus Ende („…, bis 31.12.2026").
    static func summary(_ recurrence: Recurrence, calendar: Calendar = .current) -> String {
        let base = pattern(recurrence, calendar: calendar)
        guard let tail = endClause(recurrence.end, calendar: calendar) else { return base }
        return base + tail
    }

    // MARK: – Muster

    static func pattern(_ recurrence: Recurrence, calendar: Calendar = .current) -> String {
        if let times = recurrence.timesPerPeriod {
            return flexible(times: times, recurrence: recurrence, calendar: calendar)
        }
        switch recurrence.frequency {
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
                inMonth: { month in String(localized: "\(day). \(month)") })
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
            return RuleText(
                short: String(localized: "\(nth). \(name)"),
                monthly: String(localized: "Am \(nth). \(name) im Monat"),
                inMonth: { month in String(localized: "\(nth). \(name) im \(month)") })
        }
    }

    // MARK: – Ende

    private static func endClause(_ end: Recurrence.End, calendar: Calendar) -> String? {
        switch end {
        case .never:
            return nil
        case .on(let day):
            return String(localized: ", bis \(dayText(day))")
        case .after(let n):
            return n == 1
                ? String(localized: ", endet nach 1 Termin")
                : String(localized: ", endet nach \(n) Terminen")
        }
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
