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
        - "isReminder": true, wenn der Satz EINEN bestimmten Tag nennt \
        ("einmal", "morgen um 10", "heute", "nächsten Dienstag") oder etwas \
        Einmaliges verlangt. false bei etwas, das sich wiederholt.
        - "schedule": "once" für EINEN bestimmten Tag, "daily" wenn der Satz \
        nichts über eine Wiederholung sagt, "weekly", "monthly" oder "yearly" \
        bei einer Wiederholung.
        - "weekdays": Zahlen von 1 bis 7, wobei SONNTAG 1 ist, Montag 2, \
        Dienstag 3, Mittwoch 4, Donnerstag 5, Freitag 6, Samstag 7.
        - "startDay": JJJJ-MM-TT, und leer wenn der Satz keinen Tag nennt. \
        Nötig für "once": "morgen" -> das morgige Datum, \
        "nächsten Dienstag" -> der nächste Dienstag. Nie in der Vergangenheit.

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
        // when the model disagrees, applied AFTER the schedule is known because
        // it is the schedule that says whether something happens once. A 0.5B
        // model asked about "morgen Zahnarzt um 10" answering `daily` is entirely
        // ordinary, and without this it becomes a permanent habit tracked
        // forever. The day goes with it.
        pinOneOff(&draft.schedule, sentence: sentence)
        // Derived from the schedule rather than trusted from the model, so the
        // flag and the frequency cannot disagree: a once-only thing under
        // habits is tracked forever and counts against the free allowance.
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
    /// Deliberately narrow — but "narrow" used to mean *explicit one-off words
    /// only*, which misses the commonest case there is: **a sentence that names
    /// one particular day.** "tomorrow at 10" carries no "einmal", so the model's
    /// answer was taken as read and the once-only thing was filed as a habit.
    /// A day named as a shift from today cannot come round again, so the
    /// sentence has said this happens once whether or not it also says "einmal".
    ///
    /// A repetition word anywhere in the sentence wins first, against every
    /// marker below: that is what makes "morgen" safe to list at all. German
    /// uses the same word for MORNING, and "jeden Morgen lesen" is daily — the
    /// guard above is the only thing that says so.
    static func readsAsOneOff(_ sentence: String) -> Bool {
        let text = sentence.lowercased()

        let repeating = ["jeden", "jede", "jedes", "immer", "täglich", "taeglich",
                         "wöchentlich", "woechentlich", "monatlich", "jeweils",
                         "regelmäßig", "regelmaessig", "am tag", "pro tag",
                         "a day", "per day", "every", "each", "daily",
                         "weekly", "monthly", "yearly", "annually"]
        if repeating.contains(where: { text.contains($0) }) { return false }

        // Where the person has said it outright.
        let explicit = ["einmal", "ein mal", "nur einmal", "one time", "once"]
        if explicit.contains(where: { text.contains($0) }) { return true }

        return namesASingleDay(text)
    }

    /// Whether the sentence names one particular day rather than a cadence.
    ///
    /// "morgen" is read WITH ITS NEIGHBOUR, not as a substring. That is the whole
    /// difference: "jeden Morgen" and "morgen um 10" contain the identical
    /// character sequence, and a substring test would have to be wrong about one
    /// of them. The repetition guard has already removed the first, so what is
    /// left here is the phrasings that carry no repetition word at all —
    /// "morgens um 7" and "am Morgen", where the word is a TIME OF DAY.
    private static func namesASingleDay(_ sentence: String) -> Bool {
        let tokens = words(of: sentence)
        for (index, token) in tokens.enumerated() {
            if singleDays.contains(token) {
                if token == "morgen", index > 0, morningOfTheDay.contains(tokens[index - 1]) {
                    continue
                }
                return true
            }
            // "next Tuesday" / "nächsten Dienstag": the pair names a day. On its
            // own "next" says nothing — "next week" is a span and "die nächsten
            // Wochen" is a stretch of future, neither of them one date.
            if nextCue.contains(token),
               index + 1 < tokens.count, weekdays.contains(tokens[index + 1]) {
                return true
            }
        }
        return false
    }

    /// The day a sentence points at, as a `DayKey`, or nil when it names no day
    /// this can work out.
    ///
    /// Only words that carry an offset from today, because those are the ones
    /// where the meaning is fixed: "tomorrow" is always tomorrow. A weekday or a
    /// calendar date needs to know which week or year is meant, and that is what
    /// the models are for and what their date fields are for. Guessing it here
    /// would be worse than leaving it blank — a reminder dated yesterday fires
    /// nowhere at all.
    static func namedDayKey(_ sentence: String, calendar: Calendar = .current,
                            now: Date = Date()) -> String? {
        let offsets: [String: Int] = ["today": 0, "tonight": 0, "heute": 0,
                                      "tomorrow": 1, "morgen": 1,
                                      "übermorgen": 2, "uebermorgen": 2]
        let tokens = words(of: sentence)
        for (index, token) in tokens.enumerated() {
            guard let offset = offsets[token] else { continue }
            if token == "morgen", index > 0, morningOfTheDay.contains(tokens[index - 1]) {
                continue
            }
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else {
                return nil
            }
            return DayKey.key(for: day, calendar: calendar)
        }
        return nil
    }

    /// The sentence as lowercase words, so a token can be read with its
    /// neighbour. `morgen`, `Morgen!` and `morgen,` are the same word.
    private static func words(of text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
    }

    /// Days named as a shift from today. These do not repeat.
    private static let singleDays: Set<String> =
        ["morgen", "tomorrow", "today", "heute", "tonight",
         "übermorgen", "uebermorgen"]

    /// Words in front of "morgen" that turn it into MORNING rather than tomorrow.
    private static let morningOfTheDay: Set<String> =
        ["am", "im", "den", "des", "jeden", "jede", "jedes", "vom", "an", "bis"]

    /// The cue that makes the NEXT word be a particular date.
    private static let nextCue: Set<String> =
        ["nächsten", "naechsten", "nächste", "naechste", "next"]

    private static let weekdays: Set<String> = [
        "montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag",
        "sonntag", "monday", "tuesday", "wednesday", "thursday", "friday",
        "saturday", "sunday"]

    /// The one decision a sentence makes about itself, applied to a schedule
    /// whatever model produced it.
    ///
    /// **Called from every reading path, which is the fix.** The rule already
    /// existed and its comment already claimed to live "below the model" — but
    /// only one of the three paths ever reached it, so "tomorrow at 10" came back
    /// as a daily habit and the sentence never had a chance. A once-only thing
    /// filed under habits is tracked forever and counts against the free
    /// allowance, so the direction of the miss is always the same one.
    ///
    /// `isReminder` is NOT set here: `CreateItemDraft.isReminder` derives it from
    /// the frequency once this has run, so it cannot disagree with it.
    static func pinOneOff(_ schedule: inout CreateItemSchedule, sentence: String) {
        guard readsAsOneOff(sentence) else { return }
        schedule.frequency = .once
        // The named day wins over whatever the model guessed, because the word
        // is a fact about the sentence and the guess is not.
        if let day = namedDayKey(sentence) {
            schedule.startDay = day
        }
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
