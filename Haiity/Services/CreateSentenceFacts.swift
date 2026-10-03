import Foundation

/// Deterministic date and clock facts shared by preview and model-backed reads.
struct CreateSentenceFacts {
    let name: String
    let startDay: String?
    let minutes: Int?
    let hasDate: Bool
    let hasTime: Bool
    let validationMessage: String?

    init(_ sentence: String, locale: Locale = .current,
         calendar: Calendar = .current, now: Date = .now) {
        let sentence = sentence.replacingOccurrences(of: "\u{00a0}", with: " ")
        let ns = sentence as NSString
        var reserved: [NSRange] = []
        var validDates: [(NSRange, Date)] = []
        var issues: [String] = []
        let datePatterns = [
            #"(?<![\p{L}\d./-])(\d{4})-(\d{1,2})-(\d{1,2})(?![\p{L}\d/-])"#,
            #"(?<![\p{L}\d./-])(\d{1,2})[./-](\d{1,2})[./-](\d{4})(?![\p{L}\d/-])"#,
            #"(?<![\p{L}\d])(\d{1,2})\s+(\d{1,2})\s+(\d{4})(?![\p{L}\d])"#
        ]
        for (patternIndex, pattern) in datePatterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: sentence, range: NSRange(location: 0, length: ns.length))
                where !reserved.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                reserved.append(match.range)
                let first = Int(ns.substring(with: match.range(at: 1))) ?? 0
                let second = Int(ns.substring(with: match.range(at: 2))) ?? 0
                let third = Int(ns.substring(with: match.range(at: 3))) ?? 0
                let (year, month, day): (Int, Int, Int)
                if patternIndex == 0 { (year, month, day) = (first, second, third) }
                else if patternIndex == 2 || locale.region?.identifier == "DE"
                    || locale.language.languageCode?.identifier == "de" {
                    (year, month, day) = (third, second, first)
                } else if locale.region?.identifier == "US" {
                    (year, month, day) = (third, first, second)
                } else {
                    (year, month, day) = (third, second, first)
                }
                if let date = Self.gregorianDate(year: year, month: month, day: day,
                                                 timeZone: calendar.timeZone) {
                    validDates.append((match.range, date))
                } else {
                    issues.append(String(localized: "Das Datum ist ungültig. Bitte korrigieren."))
                }
            }
        }

        // A plain dotted pair is a clock. Date context or a third component
        // makes it an incomplete date instead; reserve it before clock matching.
        if let incomplete = try? NSRegularExpression(
            pattern: #"(?<![\p{L}\d./-])(?:\d{4}-\d{1,2}(?:-\d{0,2})?|\d{1,2}[./-]\d{1,2}[./-]\d{0,3}|\d{1,2}[/\-]\d{1,2}|(?:am|ab|on)\s+\d{1,2}\.\d{1,2}|\d{1,2}\s+\d{1,2}(?:\s+\d{1,3})?\s*$)(?!\d)"#,
            options: [.caseInsensitive]) {
            for match in incomplete.matches(in: sentence, range: NSRange(location: 0, length: ns.length))
                where !reserved.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                reserved.append(match.range)
                issues.append(String(localized: "Das Datum ist unvollständig. Bitte ergänzen."))
            }
        }

        let relativeDays = DraftExtraction.namedDayKeys(sentence, calendar: calendar, now: now)
        let hasDate = !reserved.isEmpty || !relativeDays.isEmpty
        let dateKeys = validDates.map { DayKey.key(for: $0.1, calendar: calendar) } + relativeDays
        if Set(dateKeys).count > 1 { issues.append(String(localized: "Es wurden mehrere unterschiedliche Daten genannt.")) }
        if validDates.contains(where: { calendar.startOfDay(for: $0.1) < calendar.startOfDay(for: now) }) {
            issues.append(String(localized: "Das Datum liegt in der Vergangenheit. Bitte korrigieren."))
        }
        let explicitDay = dateKeys.first

        var text = sentence as NSString
        for range in reserved.sorted(by: { $0.location > $1.location }) {
            text = text.replacingCharacters(in: range, with: String(repeating: " ", count: range.length)) as NSString
        }
        let timeText = text as String
        let timeNS = timeText as NSString
        let lead = #"(?:(?:um|at|around|gegen|ca\.|circa)\s+)?"#
        let timePattern = #"(?<![\p{L}\d:.])"# + lead
            + #"(\d+)(?::|\.)(\d+)\s*(Uhr|AM|PM)?(?![\p{L}\d:])|(?<![\p{L}\d:.])"# + lead
            + #"(\d+)\s*(Uhr|AM|PM|o'?clock)\b|\b(?:um|at|around|gegen|ca\.|circa)\s+(\d+)(?![\p{L}\d:.])|\b"# + lead
            + #"(null|eins|ein|zwei|drei|vier|fünf|fuenf|sechs|sieben|acht|neun|zehn|elf|zwölf|zwoelf|dreizehn|vierzehn|fünfzehn|fuenfzehn|sechzehn|siebzehn|achtzehn|neunzehn|zwanzig|einundzwanzig|zweiundzwanzig|dreiundzwanzig)\s+Uhr\b"#
        var timeRanges: [NSRange] = []
        var validTimeRanges: [NSRange] = []
        var values: [Int] = []
        if let regex = try? NSRegularExpression(pattern: timePattern, options: [.caseInsensitive]) {
            for match in regex.matches(in: timeText, range: NSRange(location: 0, length: timeNS.length)) {
                let tail = timeNS.substring(from: NSMaxRange(match.range))
                if tail.range(of: #"^\s*(?:reps?|sets?|items?|kg|ml|km|cm|min(?:utes?|uten)?|sek(?:unden)?|seconds?|sec|std|hours?|stunden|tage|days?|mal|x)\b"#,
                              options: [.regularExpression, .caseInsensitive]) != nil { continue }
                let hourText = [1, 4, 6].compactMap { index -> String? in
                    guard match.range(at: index).location != NSNotFound else { return nil }
                    return timeNS.substring(with: match.range(at: index))
                }.first
                let wordHour = match.range(at: 7).location != NSNotFound
                let hour: Int? = wordHour
                    ? Self.germanHours[timeNS.substring(with: match.range(at: 7)).lowercased()]
                    : hourText.flatMap(Int.init)
                let minute = match.range(at: 2).location == NSNotFound
                    ? 0 : Int(timeNS.substring(with: match.range(at: 2))) ?? 99
                let suffixRange = match.range(at: 3).location != NSNotFound ? match.range(at: 3)
                    : (match.range(at: 5).location != NSNotFound ? match.range(at: 5) : NSRange(location: 0, length: 0))
                let suffix = suffixRange.length == 0 ? "" : timeNS.substring(with: suffixRange).lowercased()
                timeRanges.append(match.range)
                guard var h = hour, hourText.map({ $0.count <= 2 }) ?? true,
                      match.range(at: 2).length <= 2,
                      (0...23).contains(h), (0...59).contains(minute),
                      suffix != "am" && suffix != "pm" || (1...12).contains(h) else {
                    issues.append(String(localized: "Die Uhrzeit ist ungültig. Bitte korrigieren."))
                    continue
                }
                if suffix == "am" { if h == 12 { h = 0 } }
                if suffix == "pm", h < 12 { h += 12 }
                values.append(h * 60 + minute)
                validTimeRanges.append(match.range)
            }
        }
        if Set(values).count > 1 { issues.append(String(localized: "Es wurden mehrere unterschiedliche Uhrzeiten genannt.")) }
        let hasTime = !timeRanges.isEmpty
        var name = sentence as NSString
        for range in (validDates.map(\.0) + validTimeRanges).sorted(by: { $0.location > $1.location }) {
            name = name.replacingCharacters(in: range, with: String(repeating: " ", count: range.length)) as NSString
        }
        self.name = (name as String)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.startDay = explicitDay
        self.minutes = values.first
        self.hasDate = hasDate
        self.hasTime = hasTime
        self.validationMessage = issues.first
    }

    private static let germanHours: [String: Int] = [
        "null": 0, "eins": 1, "ein": 1, "zwei": 2, "drei": 3, "vier": 4, "fünf": 5,
        "fuenf": 5, "sechs": 6, "sieben": 7, "acht": 8, "neun": 9,
        "zehn": 10, "elf": 11, "zwölf": 12, "zwoelf": 12,
        "dreizehn": 13, "vierzehn": 14, "fünfzehn": 15, "fuenfzehn": 15,
        "sechzehn": 16, "siebzehn": 17, "achtzehn": 18, "neunzehn": 19,
        "zwanzig": 20, "einundzwanzig": 21, "zweiundzwanzig": 22, "dreiundzwanzig": 23
    ]

    private static func gregorianDate(year: Int, month: Int, day: Int, timeZone: TimeZone) -> Date? {
        guard (1...9999).contains(year) else { return nil }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        guard let date = gregorian.date(from: components) else { return nil }
        let check = gregorian.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }
}
