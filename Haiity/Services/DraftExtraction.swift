import Foundation

/// Turning a model's answer into a draft, or refusing to.
///
/// A small local model is not a JSON API. It will wrap the object in a code
/// fence, put a sentence of German around it, drop a field, quote a time as
/// "07:00" or "7 Uhr", or answer with prose instead of an object at all. Every
/// one of those is ordinary output from a 0.5B model and none of them is
/// acceptable to a habit tracker, because a habit is a standing commitment the
/// person then has to discover and delete.
///
/// So the rule here is: **extract what is unambiguous, invent nothing, and say so
/// when there is nothing.** A missing field falls back to the deterministic
/// parser rather than to a guess, and a value that cannot be read at all makes the
/// whole reading fail — because a half-understood draft shown as a confident card
/// is worse than no card.
enum DraftExtraction {

    /// What a reading produced, including whether it was trustworthy.
    struct Outcome: Equatable {
        var draft: CreateItemDraft
        /// False when the model answered something unusable and the caller should
        /// say so rather than present the draft as the model's opinion.
        var isConfident: Bool
    }

    /// The instruction the model is given. Kept next to the parser because the
    /// two are one design: every clause here exists because the parser would
    /// otherwise have to cope with its absence.
    static let systemPrompt = """
        Du liest einen Satz und machst daraus genau ein Element für eine \
        Gewohnheits-App. Antworte ausschließlich mit einem JSON-Objekt, ohne \
        Text davor oder danach, ohne Codefences.

        Felder:
        - "name": der Name ohne Uhrzeit und ohne Wiederholung. \
        "jeden Montag und Donnerstag morgens um 7 Wasser trinken" -> \
        "jeden Montag und Donnerstag morgens Wasser trinken"
        - "emoji": genau ein einzelnes Zeichen, das zum Namen passt.
        - "minutes": Uhrzeit in Minuten seit Mitternacht, Zahl von 0 bis 1439, \
        oder null wenn der Satz keine Uhrzeit nennt. "um 7" -> 420, "um 07:30" -> 450.
        - "isReminder": true, wenn es etwas EINMALIGES ist ("einmal", "morgen", \
        "nächsten Dienstag"). false bei etwas, das sich wiederholt.
        - "schedule": "once", "daily", "weekly", "monthly" oder "yearly".
        - "weekdays": Zahlen von 1 bis 7, wobei SONNTAG 1 ist, Montag 2, \
        Dienstag 3, Mittwoch 4, Donnerstag 5, Freitag 6, Samstag 7.

        Kein Feld auslassen. Kein Feld erfinden. Keine Erklärung.
        """

    // MARK: - The prompt

    static func userPrompt(for sentence: String) -> String {
        "Satz: \(sentence)"
    }

    // MARK: - Parsing

    /// Reads a model's answer, or returns nil when there is nothing to read.
    ///
    /// Deliberately total: it never throws and never traps, because a crash on
    /// malformed model output is the worst possible failure for a feature that is
    /// explicitly optional and explicitly manual.
    static func parse(_ raw: String, sentence: String) -> Outcome? {
        guard let object = firstJSONObject(in: raw) else { return nil }

        // The name is the one field with no safe default: a draft with no name is
        // not a habit, it is a question. Everything else can fall back.
        guard let name = (object["name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }

        var draft = fallbackDraft(from: sentence, name: name)

        // Minutes: accept a number, or a clock the model wrote as a string.
        if let minutes = minutes(from: object["minutes"]) {
            draft.minutes = minutes
        }
        if let emoji = (object["emoji"] as? String),
           let symbol = singleSymbol(in: emoji) {
            draft.emoji = symbol
        }
        // A model that says `isReminder: false` for "einmal morgen Zahnarzt" would
        // file a once-only thing under habits, where it is tracked forever and
        // counts against the free allowance. So the model may only ever RAISE this
        // flag. The deterministic rule below already decided the rest, and
        // overwriting it here is exactly the bug that rule exists to prevent.
        if let schedule = schedule(from: object) {
            draft.schedule = schedule
        }
        // A sentence that plainly says it happens ONCE is a once-only thing even
        // when the model disagrees. This has to be deterministic: the rule below
        // only fires on the schedule, and a 0.5B model asked about "einmal morgen
        // Zahnarzt" answering `daily` with `isReminder: false` is entirely
        // ordinary. Without this a once-only thing becomes a permanent habit,
        // tracked forever, counting against the free allowance.
        if readsAsOneOff(sentence) {
            draft.schedule.frequency = .once
        }
        // The one-off rule, applied AFTER the schedule is known, because it is the
        // schedule that says whether something happens once. A model that answers
        // `isReminder: false` for "einmal morgen Zahnarzt" would file a once-only
        // thing under habits, where it is tracked forever and counts against the
        // free allowance.
        draft.isReminder = CreateItemDraft.isReminder(
            (object["isReminder"] as? Bool) == true, schedule: draft.schedule)

        // Confidence is about the STRUCTURE, not the values: a model that
        // answered with a well-formed object and one wrong field is still more
        // useful than nothing, and the card shows the name for correction.
        return Outcome(draft: draft, isConfident: true)
    }

    /// What the deterministic half alone can say about a sentence.
    private static func fallbackDraft(from sentence: String, name: String? = nil) -> CreateItemDraft {
        let stripped = CreateItemDraft.stripTime(from: sentence)
        return CreateItemDraft(name: name ?? stripped.name, emoji: "",
                              minutes: stripped.minutes)
    }

    /// One symbol out of whatever the model put in the emoji field.
    ///
    /// Stripped of the invisible parts a real emoji carries — the variation
    /// selector and the zero-width joiner, without which a family or a
    /// skin-toned symbol renders as several boxes. A multi-scalar sequence that
    /// leaves exactly one visible character is therefore still one character.
    /// Anything that is whitespace, a control, or a brace is refused: those are
    /// the shapes a model produces when it is answering with a placeholder.
    static func singleSymbol(in text: String) -> String? {
        // The invisible parts that change how a glyph is drawn rather than what it
        // is. A skin tone or a joiner is not a separate character to a reader.
        let scalars = Array(text.unicodeScalars).filter {
            $0.value != 0xFE0E && $0.value != 0xFE0F && $0.value != 0x20E3
        }
        guard !scalars.isEmpty else { return nil }
        // Whitespace and controls never form a symbol, and the brace and backslash
        // are what a model writes when it is answering with a placeholder.
        if scalars.contains(where: { $0.value != 0x200D && !$0.isInk }) { return nil }
        if scalars.contains(where: { $0 == "{" || $0 == "}" || $0 == "\\" }) { return nil }

        // A joined sequence renders as ONE glyph whatever it is built from, so it
        // is taken whole: a family is three people and is still one symbol.
        let joined = scalars.contains { $0.value == 0x200D }
        if joined {
            return scalars.contains(where: { $0.isInk }) ? String(String.UnicodeScalarView(scalars)) : nil
        }
        // Otherwise it is one base plus any skin-tone modifiers hanging off it, and
        // "Wasser" or "💧💧" — several bases with nothing joining them — is a word
        // or a mistake rather than an icon.
        let bases = scalars.filter { !(0x1F3FB...0x1F3FF).contains($0.value) && $0.value != 0x200D }
        guard bases.count == 1 else { return nil }
        return String(String.UnicodeScalarView(scalars))
    }

    // MARK: - Finding the object

    /// Models fence their JSON, prefix it with "Hier ist das Ergebnis:" and
    /// sometimes trail a sentence. Brace matching from the first `{` finds the
    /// object whatever is around it, and a quoted brace inside a string does not
    /// end it.
    static func firstJSONObject(in raw: String) -> [String: Any]? {
        let characters = Array(raw)
        guard let start = characters.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var escaped = false
        var index = start

        while index < characters.endIndex {
            let character = characters[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
            } else {
                switch character {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        let slice = String(characters[start...index])
                        return (try? JSONSerialization.jsonObject(with: Data(slice.utf8)))
                            as? [String: Any]
                    }
                default: break
                }
            }
            index += 1
        }
        return nil
    }

    // MARK: - Reading one field

    /// A time, from a number or from a clock written as text.
    ///
    /// "420" and "07:00" and "7 Uhr" all mean the same thing to a person, and a
    /// 0.5B model produces all three. Rejecting the string forms would throw away
    /// correct answers, so they are read. What is NOT done is guessing: a value
    /// that parses to nothing leaves the deterministic time in place.
    static func minutes(from value: Any?) -> Int? {
        switch value {
        case let number as Int:
            return (0...1439).contains(number) ? number : nil
        case let number as Double where number == number.rounded():
            let whole = Int(number)
            return (0...1439).contains(whole) ? whole : nil
        case let text as String:
            return minutes(fromClockText: text)
        case let number as NSNumber:
            let whole = number.intValue
            return (0...1439).contains(whole) ? whole : nil
        default:
            return nil
        }
    }

    private static func minutes(fromClockText text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 7:30 / 07:30
        let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
           (0...23).contains(hour), (0...59).contains(minute) {
            return hour * 60 + minute
        }
        // A bare hour, optionally with "Uhr" after it.
        var digits = trimmed
        for suffix in ["Uhr", "uhr", "U"] where digits.hasSuffix(suffix) {
            digits = String(digits.dropLast(suffix.count))
            break
        }
        digits = digits.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hour = Int(digits), (0...23).contains(hour) { return hour * 60 }
        return nil
    }

    /// The schedule, from whatever the model put in the object.
    ///
    /// This is not a second implementation. `CreateItemSchedule` already has an
    /// init that takes a model's raw answers and keeps only what means something,
    /// and it is the one that knows a bad weekday, an impossible day-of-month and
    /// an unrecognised frequency all have to be dropped rather than clamped. This
    /// only decides WHICH of its arguments the model's keys feed, because a small
    /// model names its keys inconsistently and the mapping is the part that has to
    /// be forgiving.
    static func schedule(from object: [String: Any]) -> CreateItemSchedule? {
        let frequency = (object["schedule"] as? String)
            ?? (object["frequency"] as? String)
            ?? (object["schedule"] as? Int).map { String($0) }
        let weekdays = weekdayNumbers(from: object["weekdays"] ?? object["days"])
        let interval = (object["interval"] as? Int) ?? weekdays?.first ?? 1
        let times = (object["timesPerWeek"] as? Int) ?? (object["timesPerPeriod"] as? Int) ?? 0
        // `isReminder` is the model's word for a one-off; `once` is the value the
        // schedule itself is built from. With neither, the schedule is daily, which
        // is what an unremarkable sentence means.
        let rawFrequency = frequency
            ?? ((object["isReminder"] as? Bool) == true ? "once" : "daily")

        return CreateItemSchedule(
            frequency: rawFrequency,
            interval: interval,
            weekdays: weekdays ?? [],
            timesPerPeriod: times,
            dayOfMonth: (object["dayOfMonth"] as? Int) ?? 0,
            month: (object["month"] as? Int) ?? 0,
            startDay: (object["startDay"] as? String) ?? (object["date"] as? String) ?? "")
    }

    /// Whether the sentence itself says this happens once.
    ///
    /// Deliberately narrow: only the unambiguous words, no date arithmetic and no
    /// inference. "einmal" is a decision by the person; "morgen" on its own is not,
    /// because "morgen jeden Montag" is a repeating thing. A marker only counts
    /// when the sentence has nothing else in it that says it repeats.
    static func readsAsOneOff(_ sentence: String) -> Bool {
        let text = sentence.lowercased()
        let oneOff = ["einmal", "ein mal", "one time", "once", "nur einmal"]
        guard oneOff.contains(where: { text.contains($0) }) else { return false }
        // "einmal morgen und dann jeden Montag" is not a one-off.
        let repeating = ["jeden", "jede", "jedes", "immer", "täglich", "taeglich",
                         "wöchentlich", "woechentlich", "monatlich", "every", "daily"]
        return !repeating.contains(where: { text.contains($0) })
    }

    /// A weekday list, a bare number, or English and German day names.
    ///
    /// **Sunday is 1**, matching `Calendar` and `Recurrence`, which is the
    /// convention the schedule this feeds uses throughout. Getting that wrong by
    /// one day is the kind of error nobody notices until a habit fires on the
    /// wrong day for a month.
    static func weekdayNumbers(from value: Any?) -> [Int]? {
        switch value {
        case let list as [Any]:
            let numbers = list.compactMap { item -> Int? in
                if let n = item as? Int { return n }
                if let s = item as? String { return weekdayNumber(named: s) }
                return nil
            }
            .filter { (1...7).contains($0) }
            return numbers.isEmpty ? nil : Array(Set(numbers)).sorted()
        case let text as String:
            let map = ["sonntag": 1, "montag": 2, "dienstag": 3, "mittwoch": 4,
                       "donnerstag": 5, "freitag": 6, "samstag": 7]
            var found: [Int] = []
            for (name, number) in map where text.lowercased().contains(name) {
                found.append(number)
            }
            if !found.isEmpty { return Array(Set(found)).sorted() }
            if let n = Int(text.trimmingCharacters(in: .whitespaces)), (1...7).contains(n) {
                return [n]
            }
            return nil
        case let number as Int where (1...7).contains(number):
            return [number]
        default:
            return nil
        }
    }

    private static func weekdayNumber(named text: String) -> Int? {
        weekdayNumbers(from: text)?.first
    }
}


private extension Unicode.Scalar {
    /// Ink means "draws something". Whitespace, the joiner and the variation
    /// selectors are layout, not glyphs.
    var isInk: Bool {
        if value == 0x200D || value == 0xFE0E || value == 0xFE0F || value == 0x20E3 {
            return false
        }
        return !CharacterSet.whitespacesAndNewlines.contains(self)
            && !CharacterSet.controlCharacters.contains(self)
    }
}
