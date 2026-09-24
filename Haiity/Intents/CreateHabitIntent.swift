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
    }

    static let limitMessage =
        "Das kostenlose Limit an Habits ist erreicht. In hAiity freischalten oder eine Erinnerung anlegen."

    @MainActor
    static func save(_ draft: CreateItemDraft) async -> Outcome {
        let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .emptyName }

        let store = HabitStore(url: SharedStorage.dataURL())
        let activeTracked = store.habits.filter {
            $0.itemType == .habit && $0.archivedAt == nil
        }.count
        // The free allowance is a product limit, not a technical one, so the
        // Shortcut has to respect it exactly like the in-app editor.
        guard ProGate.maySaveTrackedHabit(existingIsTracked: false,
                                          targetIsTracked: !draft.isReminder,
                                          activeCount: activeTracked,
                                          unlocked: ProStatus.shared.unlocked)
        else { return .limitReached }

        store.add(draft.makeHabit())
        // The new item needs its notification and the day's summary pulled
        // along, or it would sit silent until some later settings change.
        await Reminders.reschedule(store: store)
        return .saved
    }

    static func confirmation(for draft: CreateItemDraft) -> String {
        let kind = draft.isReminder ? "Erinnerung" : "Habit"
        let when = draft.minutes.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }
        // The German quotes are U+201E and U+201C on purpose: an ASCII double
        // quote here would close the Swift literal in the middle of the German.
        return "„\(draft.name)“ als \(kind)\(when.map { " für \($0)" } ?? "") angelegt."
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
        "Liest einen Satz wie „morgens um 7 Wasser trinken“ und legt daraus ein Habit oder eine Erinnerung an. Braucht iOS 26 und Apple Intelligence.")

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
        }
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

    var kind: CreateItemKind { isReminder ? .reminder : .habit }

    // MARK: - Reading a sentence

    /// Remove a clock time from free text without inventing anything.
    ///
    /// This is the no-model path, so it deliberately does far less than the
    /// model: it finds `7:30`, `7.30` and `7 Uhr` and takes them out, and leaves
    /// the rest alone. "Every morning" survives as part of the name, which is
    /// honest — a wrong schedule silently applied would be worse than a name the
    /// person edits.
    static func stripTime(from text: String) -> (name: String, minutes: Int?) {
        // Three forms, because people write all three: `7:30`, `7.30 Uhr`, and a
        // bare `7 Uhr` / `7 PM` with no minutes at all.
        let pattern = "(?<!\\d)([01]?\\d|2[0-3])[:.]([0-5]\\d)\\s*(?:Uhr|AM|PM)?"
            + "|\\b([01]?\\d|2[0-3])\\s*(?:Uhr|AM|PM)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return (text, nil)
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let whole = Range(match.range, in: text) else {
            return (text, nil)
        }

        var hours = 0
        var minutes = 0
        if let hourRange = Range(match.range(at: 1), in: text),
           let hour = Int(text[hourRange]) {
            hours = hour
            if let minuteRange = Range(match.range(at: 2), in: text),
               let minute = Int(text[minuteRange]) {
                minutes = minute
            }
        } else if let hourRange = Range(match.range(at: 3), in: text),
                  let hour = Int(text[hourRange]) {
            hours = hour
        }
        if matched(text, whole).lowercased().contains("pm"), hours < 12 { hours += 12 }

        let name = text.replacingCharacters(in: whole, with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (name.isEmpty ? text : name, hours * 60 + minutes)
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
            return CreateItemDraft(name: stripped.name, emoji: "", minutes: stripped.minutes)
        }
        var parsed: CreateItemDraft?
        if #available(iOS 26.0, *) {
            parsed = try? await CreateItemWriter.draft(from: text, language: language)
        }
        guard let parsed else {
            return CreateItemDraft(name: stripped.name, emoji: "", minutes: stripped.minutes)
        }
        // The deterministic time wins over the model's: a clock time in the
        // sentence is a fact, and the model is the part that can be wrong.
        return CreateItemDraft(name: parsed.name.isEmpty ? stripped.name : parsed.name,
                               emoji: parsed.emoji,
                               minutes: stripped.minutes ?? parsed.minutes,
                               isReminder: parsed.isReminder)
    }

    func makeHabit() -> Habit {
        Habit(name: name, emoji: emoji, itemType: kind.itemType, timeMinutes: minutes)
    }
}
