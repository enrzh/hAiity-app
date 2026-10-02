import AppIntents
import Foundation

/// Whether a new item is a tracked habit or a one-off reminder.
///
/// `HabitItemType` is the stored format and stays untouched — renaming it would
/// be a data break. This is the App Intents face of the same two cases, and it
/// is `AppEnum` so Shortcuts and Siri can offer it as a menu instead of making
/// the person type the word "reminder".
enum CreateItemKind: String, AppEnum {
    case habit
    case reminder

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Art")
    static var caseDisplayRepresentations: [CreateItemKind: DisplayRepresentation] = [
        .habit: DisplayRepresentation(title: "Habit", image: .init(systemName: "checkmark.circle")),
        .reminder: DisplayRepresentation(title: "Erinnerung", image: .init(systemName: "bell")),
    ]

    var itemType: HabitItemType {
        switch self {
        case .habit: return .habit
        case .reminder: return .reminder
        }
    }
}

/// Creates a habit or reminder from explicit fields.
///
/// The plain path: no model, no parsing, no guessing. Everything it needs is a
/// parameter, so a Shortcut can be built once and reused, and a voice phrase
/// like "hAiity, create a habit called Reading" is unambiguous.
///
/// The free-text variant lives in `CreateItemFromTextIntent`. Two intents
/// rather than one with an optional blob, because the person asking for it is
/// asking for two different things: "put these fields in" versus "work out what
/// I just said".
struct CreateHabitIntent: AppIntent {

    static var title: LocalizedStringResource = "Habit oder Erinnerung anlegen"
    static var description = IntentDescription(
        "Legt ein neues Habit oder eine neue Erinnerung an. Ohne KI – alle Angaben kommen aus den Feldern.")

    /// This one changes data and is not a query, so it must not show up as a
    /// suggestion the system offers unprompted. It stays reachable from the
    /// Shortcuts editor and from the phrases in `HaiityShortcuts`.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Name")
    var name: String

    @Parameter(title: "Art")
    var kind: CreateItemKind

    @Parameter(title: "Emoji", default: "")
    var emoji: String

    @Parameter(title: "Uhrzeit")
    var time: Date?

    init() {}

    init(name: String, kind: CreateItemKind, emoji: String = "", time: Date? = nil) {
        self.name = name
        self.kind = kind
        self.emoji = emoji
        self.time = time
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Legt \(\.$kind) \(\.$name) an") {
            \.$emoji
            \.$time
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let minutes = time.map {
            Calendar.current.component(.hour, from: $0) * 60
                + Calendar.current.component(.minute, from: $0)
        }
        let draft = CreateItemDraft(name: name, emoji: emoji, minutes: minutes,
                                    isReminder: kind == .reminder)
        switch await CreateItemSaver.save(draft) {
        case .saved:
            return .result(dialog: IntentDialog(stringLiteral: CreateItemSaver.confirmation(for: draft)))
        case .emptyName:
            return .result(dialog: "Der Name fehlt.")
        case .limitReached:
            return .result(dialog: IntentDialog(stringLiteral: CreateItemSaver.limitMessage))
        case .failed(let message):
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}

/// The one place a new item is written.
///
/// Both intents share it, which is the point: the free-allowance check and the
/// reschedule are product rules, and two copies of them in two intents is how a
/// Shortcut quietly starts bypassing the paywall.
enum CreateItemSaver {

    enum Outcome: Equatable {
        case saved
        case emptyName
        case limitReached
        case failed(String)
    }

    static let limitMessage =
        "Das kostenlose Limit an Habits ist erreicht. In hAiity freischalten oder eine Erinnerung anlegen."

    @MainActor
    static func save(_ draft: CreateItemDraft, into store: HabitStore? = nil) async -> Outcome {
        let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .emptyName }

        // **The store the list is already observing, when there is one.**
        //
        // A Shortcut runs with no view tree and legitimately opens its own. The
        // in-app path must not: writing through a second instance puts the habit
        // on disk and leaves the list showing yesterday, because the only re-read
        // runs on foregrounding. The item then appears to have not been created
        // at all, and it turns up after a restart.
        let target = store ?? HabitStore(url: SharedStorage.dataURL())

        let activeTracked = target.habits.filter {
            $0.itemType == .habit && $0.archivedAt == nil
        }.count
        // The free allowance is a product limit, not a technical one, so the
        // Shortcut has to respect it exactly like the in-app editor.
        guard ProGate.maySaveTrackedHabit(existingIsTracked: false,
                                          targetIsTracked: !draft.isReminder,
                                          activeCount: activeTracked,
                                          unlocked: ProStatus.shared.unlocked)
        else { return .limitReached }

        target.add(draft.makeHabit())
        if let error = target.lastWriteError { return .failed(error) }
        // The new item needs its notification and the day's summary pulled
        // along, or it would sit silent until some later settings change.
        await Reminders.reschedule(store: target)
        return .saved
    }

    static func confirmation(for draft: CreateItemDraft) -> String {
        let kind = draft.isReminder ? "Erinnerung" : "Habit"
        let when = draft.minutes.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }
        // The repeat is named here too. The Shortcut never showed a preview, so
        // this sentence was the only place the rule could surface — and it used
        // to omit it, leaving a Shortcut-created "every Monday" habit
        // indistinguishable from a daily one.
        let cadence = RecurrenceText.pattern(draft.schedule.recurrence)
        // The German quotes are U+201E and U+201C on purpose: an ASCII double
        // quote here would close the Swift literal in the middle of the German.
        return "„\(draft.name)“ als \(kind), \(cadence)"
            + (when.map { ", um \($0)" } ?? "") + ", angelegt."
    }
}

/// The free-text path: one sentence in, a created item out.
///
/// **Why the model runs only here.** Reading a sentence and filling in fields is
/// the one thing a language model is genuinely better at than a fixed form. It
/// is also the same heat cost as the rest of the app's on-device work, which is
/// why it lives in its own intent: the person chooses "read this for me" the
/// same way they choose "write me a sentence" on the statistics page. There is
/// no background call anywhere.
///
/// **Why the fallback is not a guess.** Without the model the sentence is
/// stripped of any clock time it contains and becomes the name. That is
/// predictable and lossless-ish, where a hand-rolled parser for "every morning"
/// or "on weekdays" would be a second, worse language.
struct CreateItemFromTextIntent: AppIntent {

    static var title: LocalizedStringResource = "Aus einem Satz anlegen"
    static var description = IntentDescription(
        "Liest einen Satz wie „morgens um 7 Wasser trinken“ und legt daraus ein Habit oder eine Erinnerung an. Benötigt ein unterstütztes Gerät.")

    /// **No brand or platform names in this description.** Apple's Siri
    /// metadata validation (ITMS-90626) rejects an App Intent description that
    /// contains them — build 216 was turned away for saying "Apple
    /// Intelligence", and "iOS" is on the same blocklist, so it is out too.
    /// The requirement itself is not lost: the app's own captions say why a
    /// device cannot write a sentence, and the person finds out immediately if
    /// they run the action on one that cannot.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Satz")
    var text: String

    init() {}

    init(text: String) {
        self.text = text
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Legt an: \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return .result(dialog: "Der Satz fehlt.")
        }

        let draft = await CreateItemDraft.read(from: raw)
        switch await CreateItemSaver.save(draft) {
        case .saved:
            return .result(dialog: IntentDialog(stringLiteral: CreateItemSaver.confirmation(for: draft)))
        case .emptyName:
            return .result(dialog: "Der Satz enthielt keinen Namen.")
        case .limitReached:
            return .result(dialog: IntentDialog(stringLiteral: CreateItemSaver.limitMessage))
        case .failed(let message):
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}

/// The repeat rule, as a model reports it.
///
/// **Why flat and not a `Recurrence`.** A `Recurrence` nests a `DayRule` inside a
/// frequency inside an end clause. Handing that shape to a model invites it to
/// fill in branches that do not apply — a day of the month for a weekly rule —
/// and a wrong branch is not cosmetic, it is a habit on the wrong days. So the
/// model fills a handful of bounded values, and this type turns them into a real
/// `Recurrence` in one place. Every clamp and every fallback below is ordinary
/// test code rather than model behaviour we can only hope for.
struct CreateItemSchedule: Equatable, Sendable {

    enum Frequency: String, Equatable, Sendable {
        case once, daily, weekly, monthly, yearly
    }

    var frequency: Frequency = .daily
    /// Every n periods. Anything below 1 means every period.
    var interval: Int = 1
    /// 1 = Sunday … 7 = Saturday, matching `Calendar` and `Recurrence`.
    var weekdays: Set<Int> = []
    /// "3× per week" — a flexible target instead of fixed days. 0 = none.
    var timesPerPeriod: Int = 0
    /// Day inside the month. 0 = not stated.
    var dayOfMonth: Int = 0
    /// 1–12. 0 = not stated.
    var month: Int = 0
    /// Day key for a one-off, or nil.
    var startDay: String?

    /// The rule a sentence with no schedule words produces: every day.
    static let daily = CreateItemSchedule()

    init() {}

    /// Takes the model's raw answers and keeps only what means something.
    ///
    /// The frequency arrives as a string on purpose. A model asked for an enum
    /// can only answer with a case or fail, and a misread schedule is far more
    /// damaging than an absent one — so anything unrecognised becomes daily
    /// rather than something plausible and wrong.
    init(frequency: String, interval: Int, weekdays: [Int],
         timesPerPeriod: Int, dayOfMonth: Int, month: Int, startDay: String) {
        self.frequency = Frequency(
            rawValue: frequency.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ) ?? .daily
        self.interval = max(1, interval)
        self.weekdays = Set(weekdays.filter { (1...7).contains($0) })
        self.timesPerPeriod = max(0, timesPerPeriod)
        self.dayOfMonth = (1...31).contains(dayOfMonth) ? dayOfMonth : 0
        self.month = (1...12).contains(month) ? month : 0
        // A key that is not a real day is worse than no key at all: `Recurrence`
        // drops it silently, so the one-off would quietly move to another day.
        let trimmed = startDay.trimmingCharacters(in: .whitespacesAndNewlines)
        self.startDay = DayKey.components(trimmed) != nil ? trimmed : nil
    }

    /// The real rule. `Recurrence`'s own init does the last mile of clamping.
    var recurrence: Recurrence {
        switch frequency {
        case .once:
            // "Once" with no date can only mean from today, and a one-off whose
            // day has already gone would create a habit that can never fire —
            // it would not appear on any day at all, which is the worst possible
            // outcome for something the person just asked to be created. Both
            // move to a day that can still happen.
            return Recurrence(frequency: .once, start: Self.upcoming(startDay ?? DayKey.today()))
        case .daily:
            return Recurrence(frequency: .daily)
        case .weekly:
            // A flexible target is how the engine fills in unspecified days
            // (`isActivePeriod` plus `isFlexible`), and it is the only thing that
            // makes "every 2 weeks" work at all: a weekly rule with an interval
            // but no named days otherwise matches nothing at all and reads
            // "Keine Termine". So the days, the count and the interval are three
            // ways of saying the same thing and exactly one of them is set.
            if timesPerPeriod > 0 {
                return Recurrence(frequency: .weekly,
                                  interval: interval,
                                  weekdays: weekdays,
                                  timesPerPeriod: timesPerPeriod)
            }
            if !weekdays.isEmpty {
                return Recurrence(frequency: .weekly,
                                  interval: interval,
                                  weekdays: weekdays)
            }
            return Recurrence(frequency: .weekly, interval: interval, timesPerPeriod: 1)
        case .monthly:
            return Recurrence(frequency: .monthly,
                              interval: interval,
                              rule: dayOfMonth > 0 ? .dayOfMonth(dayOfMonth) : nil,
                              start: startDay)
        case .yearly:
            return Recurrence(frequency: .yearly,
                              interval: interval,
                              rule: dayOfMonth > 0 ? .dayOfMonth(dayOfMonth) : nil,
                              month: month > 0 ? month : nil,
                              start: startDay)
        }
    }

    // MARK: - Moving a day that has gone

    /// The same month and day in the next year in which it has not passed yet.
    ///
    /// Said in September, "einmal am 14. März" means the March that is coming,
    /// not the one that just went. Left in the past it would be a habit that
    /// never appears again, created by a button whose whole promise is that the
    /// thing now exists. The preview shows the moved date before anything is
    /// saved, so the correction is visible rather than silent.
    static func upcoming(_ day: String, calendar: Calendar = .current) -> String {
        let today = DayKey.today(calendar: calendar)
        // Validate before comparing: a string that is not a date at all sorts
        // unpredictably against one, and must never be handed on as a day.
        guard let parts = DayKey.components(day) else { return today }
        guard day < today else { return day }

        // Count forward from the CURRENT year, not from the year the model
        // supplied. A supplied year far in the past is the very thing being
        // repaired, and starting there would walk decades forward to no effect:
        // 1999-07-04 said today means 2027-07-04, not "give up and use today".
        let now = DayKey.date(from: today, calendar: calendar) ?? Date()
        let year = calendar.component(.year, from: now)
        for candidate in [year, year + 1] {
            guard let key = clampedKey(year: candidate, month: parts.month,
                                       day: parts.day, calendar: calendar)
            else { continue }
            if key >= today { return key }
        }
        return today
    }

    /// A real day key for that month, with the day pulled inside the month.
    ///
    /// The clamp is what keeps 29 February from rolling into March: `Calendar`
    /// would happily turn 2027-02-29 into 2027-03-01, and then the person asked
    /// for the 29th and got the 1st.
    private static func clampedKey(year: Int, month: Int, day: Int,
                                   calendar: Calendar) -> String? {
        var probe = DateComponents()
        probe.year = year
        probe.month = month
        probe.day = 1
        guard let firstOfMonth = calendar.date(from: probe),
              let days = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count
        else { return nil }
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = min(day, days)
        guard let date = calendar.date(from: parts) else { return nil }
        return DayKey.key(for: date, calendar: calendar)
    }
}

/// What a sentence turned into. Plain data, so the intent and the tests never
/// need the model to talk about it.
struct CreateItemDraft: Equatable, Sendable {
    var name: String
    var emoji: String
    /// Minutes since midnight, or nil for "no time in the sentence".
    var minutes: Int?
    /// A one-off reminder rather than a tracked habit. Defaults to a habit,
    /// because that is what people mean when they do not say otherwise.
    var isReminder: Bool = false
    /// How often it repeats. Defaults to daily, which is both what an
    /// unremarkable sentence means and what the no-model path can honestly
    /// promise — the deterministic parser reads a clock time and nothing else.
    var schedule: CreateItemSchedule = .daily

    var kind: CreateItemKind { isReminder ? .reminder : .habit }

    /// **A one-off is a reminder, whatever the model said.**
    ///
    /// The prompt asks for this, but a model that answers `isReminder: false` for
    /// "einmal morgen Zahnarzt" files a thing that happens once under habits,
    /// where it is tracked forever and counts against the free allowance. Wrong on
    /// both counts, so the rule is applied here instead of trusted. A repeated
    /// thing still decides for itself, which is where "remind me every Monday"
    /// means something the frequency cannot.
    ///
    /// It lives on the draft rather than in the writer so it is testable without
    /// a model, and so every path that fills a draft gets it — including the
    /// Shortcut.
    static func isReminder(_ proposed: Bool, schedule: CreateItemSchedule) -> Bool {
        proposed || schedule.frequency == .once
    }

    // MARK: - Reading a sentence

    /// Remove clock times from free text without inventing anything.
    ///
    /// This is the no-model path, so it deliberately does far less than the
    /// model: it finds times and takes them out, and leaves everything else
    /// alone. "Every morning" survives as part of the name, which is honest — a
    /// wrong schedule silently applied would be worse than a name the person
    /// edits.
    ///
    /// A bare hour is only a time when a word introduces it. `7 Uhr`, `7:30` and
    /// `at 7` are times; `7 Tage` and `backlog at 5 items` are not, and reading
    /// those as midnight would set the wrong notification on a habit about
    /// something that has nothing to do with the clock.
    static func stripTime(from text: String) -> (name: String, minutes: Int?) {
        // Four forms, because people write all four: `7:30`, `7.30 Uhr`, a bare
        // `7 Uhr` / `7 PM`, and a bare hour introduced by a word — `um 7`, `at 7`,
        // `gegen 7`. The introducing word is part of the match so that `um 7:30`
        // does not leave a stray "um" at the front of the name.
        //
        // The last form is the one that can misfire, because English puts "at" in
        // front of quantities as well as clock times: "3 sets at 10 reps" is not
        // a reminder at ten o'clock. A short list of unit words after the number
        // is what keeps that apart, and it only has to cover the words a habit
        // sentence realistically contains.
        let units = "(?!\\s*(?:reps?|kg|ml|km|cm|min|minuten|sek|sec|std|mal|x)\\b)"
        let lead = "(?:\\b(?:um|at|around|gegen|ca\\.|circa)\\s+)?"
        let pattern = "(?<![\\d:])" + lead + "([01]?\\d|2[0-3])[:.]([0-5]\\d)\\s*(?:Uhr|AM|PM)?"
            + "|" + lead + "\\b([01]?\\d|2[0-3])\\s*(?:Uhr|AM|PM)\\b"
            + "|\\b(?:um|at|around|gegen|ca\\.|circa)\\s+([01]?\\d|2[0-3])\\b"
            + units + "\\s*(?:Uhr|AM|PM|o'?clock)?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return (text, nil)
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard let first = matches.first, let whole = Range(first.range, in: text) else {
            return (text, nil)
        }

        var hours = 0
        var minutes = 0
        if let hourRange = Range(first.range(at: 1), in: text),
           let hour = Int(text[hourRange]) {
            hours = hour
            if let minuteRange = Range(first.range(at: 2), in: text),
               let minute = Int(text[minuteRange]) {
                minutes = minute
            }
        } else if let hourRange = Range(first.range(at: 3), in: text),
                  let hour = Int(text[hourRange]) {
            hours = hour
        } else if let hourRange = Range(first.range(at: 4), in: text),
                  let hour = Int(text[hourRange]) {
            hours = hour
        }
        if matched(text, whole).lowercased().contains("pm"), hours < 12 { hours += 12 }

        // Every occurrence goes, not just the first. "7:30 Wasser und 18 Uhr Yoga"
        // is one sentence with two times in it, and leaving the second behind
        // puts it in the name where it reads as part of the thing. Working
        // backwards keeps the ranges from the untouched text valid as the string
        // shrinks. The first one is the time; there is only one time on a habit.
        var name = text
        for match in matches.reversed() {
            guard let r = Range(match.range, in: text) else { continue }
            name = name.replacingCharacters(in: r, with: " ")
        }
        name = name
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (name.isEmpty ? text : name, hours * 60 + minutes)
    }

    /// A name with no clock time left in it, whatever produced it.
    ///
    /// The prompt asks the model for a name with no time in it and it mostly
    /// complies. When it does not, the time is something we can find without the
    /// model, so it is taken back out deterministically instead of being left
    /// sitting in a list row.
    static func cleanedName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutTime = stripTime(from: trimmed).name
        // A name that was nothing but a time is not a name; the caller falls back
        // to the whole sentence rather than saving an empty row.
        return withoutTime.isEmpty ? trimmed : withoutTime
    }

    private static func matched(_ text: String, _ range: Range<String.Index>) -> String {
        String(text[range])
    }

    /// The sentence → draft decision. `useModel` is passed in rather than read
    /// here so the caller — and the test — decides whether heat is spent.
    static func read(from text: String,
                     language: String = Locale.current.language.languageCode?.identifier ?? "en",
                     useModel: Bool = true) async -> CreateItemDraft {
        let stripped = stripTime(from: text)
        guard useModel, OnDeviceModel.isAvailable else {
            // Reading a clock and nothing else is the honest degraded path, but
            // "tomorrow at 10" is still a one-off reminder dated tomorrow, and
            // that needs no model at all: the sentence named the day itself.
            return pinned(CreateItemDraft(name: stripped.name, emoji: "",
                                          minutes: stripped.minutes),
                          sentence: text)
        }
        var parsed: CreateItemDraft?
        if #available(iOS 26.0, *) {
            parsed = try? await CreateItemWriter.draft(from: text, language: language)
        }
        guard let parsed else {
            return pinned(CreateItemDraft(name: stripped.name, emoji: "",
                                          minutes: stripped.minutes),
                          sentence: text)
        }
        // The deterministic time wins over the model's: a clock time in the
        // sentence is a fact, and the model is the part that can be wrong. The
        // name gets the same treatment — a time that survived into it is taken
        // back out rather than saved, because "Wasser trinken um 7" is not a
        // name, and the time is already a field of its own.
        return pinned(CreateItemDraft(name: CreateItemDraft.cleanedName(
                                          parsed.name.isEmpty ? stripped.name : parsed.name),
                                      emoji: parsed.emoji,
                                      minutes: stripped.minutes ?? parsed.minutes,
                                      isReminder: parsed.isReminder,
                                      schedule: parsed.schedule),
                      sentence: text)
    }

    /// The sentence's own decision about itself, applied on the way out of every
    /// branch above.
    ///
    /// **Why it has to be here and not only in the prompt.** `DraftExtraction`
    /// already did this for the downloaded model, and the comment there claimed
    /// the rule lives "below the model" — but this function is the OTHER model,
    /// the Shortcut and the no-model fallback, and it never applied it. "I want
    /// to go to Doc tomorrow at 10 am" was therefore read as a daily habit:
    /// correct in the prompt, enforced on one path of three. One choke point
    /// rather than a rule per path is what stops that recurring.
    ///
    /// `isReminder` is recomputed from the resulting schedule rather than passed
    /// through, so the two cannot disagree: a once-only thing filed under
    /// habits is tracked forever and counts against the free allowance.
    private static func pinned(_ draft: CreateItemDraft, sentence: String) -> CreateItemDraft {
        var schedule = draft.schedule
        DraftExtraction.pinOneOff(&schedule, sentence: sentence)
        return CreateItemDraft(name: draft.name, emoji: draft.emoji,
                               minutes: draft.minutes,
                               isReminder: CreateItemDraft.isReminder(draft.isReminder,
                                                                      schedule: schedule),
                               schedule: schedule)
    }

    func makeHabit() -> Habit {
        Habit(name: name, emoji: emoji, itemType: kind.itemType,
              timeMinutes: minutes, recurrence: schedule.recurrence)
    }
}
