import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Turns one spoken or typed sentence into the fields a new item needs.
///
/// This is the only place in the app where the model reads a whole sentence for
/// a task, and it earns that: splitting "morgens um 7 Wasser trinken" into a
/// name, a time and a kind is exactly the kind of loose language work a form is
/// bad at. Everything the model returns is bounded and checked — a name has to
/// be a name, an emoji has to be an emoji, and the clock time is **not** taken
/// from the model at all when the sentence contained one, because a time in a
/// sentence is a fact and the model is the part that can be wrong.
@available(iOS 26.0, *)
enum CreateItemWriter {

    @Generable
    struct Schedule {
        @Guide(description: "Exactly one of: \"once\", \"daily\", \"weekly\", \"monthly\", \"yearly\". Use \"daily\" when the sentence says nothing about repeating. Use \"once\" only together with a real date.")
        var frequency: String
        @Guide(description: "How many periods pass between repeats: 2 for \"every 2 weeks\", 1 otherwise. Never 0.")
        var interval: Int
        @Guide(description: "The days it repeats, where 1=Sunday and 7=Saturday. Monday and Thursday is [2,5]; \"on weekdays\" is [2,3,4,5,6]. Empty list when it is not weekly or the days are not fixed.")
        var weekdays: [Int]
        @Guide(description: "A flexible count instead of fixed days: 3 for \"3 times a week\", 4 for \"4 times a month\". 0 when the days are fixed or the sentence is silent.")
        var timesPerPeriod: Int
        @Guide(description: "The day inside the month, 1 to 31, or 0 when the sentence does not name one. \"on the 15th\" is 15.")
        var dayOfMonth: Int
        @Guide(description: "The month as 1 to 12 for a yearly rule, or 0 when the sentence does not name one.")
        var month: Int
        @Guide(description: "The date as yyyy-MM-dd, or an empty string when the sentence gives no date. Required for \"once\". It must never be in the past: when the sentence gives a month and day but no year, use the next year in which that date has not yet passed — said in September, \"on 14 March\" is the March coming, not the one just gone.")
        var startDay: String
    }

    @Generable
    struct Parsed {
        @Guide(description: "The item's name with no time, no schedule words and no filler.")
        var name: String
        @Guide(description: "A single emoji, or an empty string when the sentence has none.")
        var emoji: String
        @Guide(description: "True only when the sentence clearly means a one-off reminder rather than a tracked habit.")
        var isReminder: Bool
        @Guide(description: "How often it repeats.")
        var schedule: Schedule
    }

    /// **The cleanup rule and the schedule rule are the same rule.**
    ///
    /// This prompt used to say "strip every morning" and gave the model nowhere
    /// to put it, so the words were thrown away and every sentence created a
    /// daily item. Cleaning the name is only correct once the information has a
    /// field to land in — hence the worked examples, which are the part that
    /// actually carries the behaviour.
    private static let instructions = """
    You read one sentence in which someone describes something they want to track or be reminded about, \
    and you fill in the fields of a habit-tracker item. The sentence is in the language named in the request.

    Your first job is to take the schedule OUT of the name and put it in the schedule fields. \
    "jeden Montag" is not part of the name — it is `weekdays`.

    Fields:
    - `name` is the thing itself, in that language, as a short noun phrase. Strip everything else: \
    times, schedule words, "at work", "don't forget to", please words, filler.
    - `emoji` is ONE emoji that fits the thing, or an empty string if none is obvious. Never more than one. \
    A flag, a skin tone or a family counts as one.
    - A reminder only notifies and is not tracked; a habit is tracked over time. \
    - `isReminder` is true for anything that happens ONCE — "einmal am 14. März", "tomorrow", "next \
    Tuesday" — and for a repeated thing the person asks to be NAGGED about ("remind me", "don't let me \
    forget", "erinner mich"). It is false only for a repeated thing meant to be tracked.
    - `frequency` is exactly one of "once", "daily", "weekly", "monthly", "yearly". Say "daily" when the \
    sentence says nothing about repeating — that is the honest reading, not a missing answer.
    - `interval` is how many periods pass between repeats: 2 for "every 2 weeks", 1 otherwise.
    - `weekdays` is 1=Sunday to 7=Saturday. "Monday and Thursday" is [2,5], "on weekdays" is [2,3,4,5,6]. \
    Empty when it is not weekly or the days are not fixed.
    - `timesPerPeriod` is a flexible count instead of fixed days: 3 for "3 times a week". \
    0 when the days are fixed or the sentence is silent.
    - `dayOfMonth` is 1 to 31, or 0. "on the 15th" is 15.
    - `month` is 1 to 12 for a yearly rule, or 0.
    - `startDay` is yyyy-MM-dd, or an empty string. Required for "once". It is never in the past: when the \
    sentence names a month and day but no year, use the next year in which that date has not yet passed. \
    Said in September, "on 14 March" is the March coming, not the one just gone — and the app keeps \
    showing that date in the preview, so getting it wrong is visible rather than silent.

    Rules:
    - Do not invent anything that is not in the sentence. Say "daily" with every other schedule field \
    at 0 or empty when the sentence is silent about repeating.
    - Fill only the fields the sentence actually speaks to and leave the rest alone.
    - Never leave a stated schedule in the name, and never drop a stated schedule from the fields.

    Examples, in German:
    - "jeden Montag und Donnerstag um 7 Wasser trinken" -> name "Wasser trinken", emoji for water, \
    isReminder false, frequency "weekly", interval 1, weekdays [2,5], timesPerPeriod 0, dayOfMonth 0, \
    month 0, startDay ""
    - "3 mal pro Woche joggen" -> name "Joggen", frequency "weekly", weekdays [], timesPerPeriod 3
    - "alle zwei Wochen Zahnarzt" -> name "Zahnarzt", frequency "weekly", interval 2, weekdays []
    - "einmal am 14. März" -> name "Zahnarzt", isReminder true, frequency "once", startDay that date
    - "jeden Monat am 15. Miete zahlen" -> name "Miete zahlen", frequency "monthly", dayOfMonth 15
    - "jedes Jahr im Dezember Geschenke kaufen" -> name "Geschenke kaufen", frequency "yearly", month 12
    - "Wasser trinken" -> name "Wasser trinken", frequency "daily", every other schedule field 0 or ""

    Filler goes too, and it is the part models get wrong most often:
    - "ich muss endlich wieder mehr lesen" -> name "Mehr lesen", frequency "daily"
    - "remember to call mum on fridays" -> name "Call mum", frequency "weekly", weekdays [6]
    - "don't let me forget the bins tomorrow" -> name "Bins", isReminder true, frequency "once"
    - "could you please take out the recycling tonight" -> name "Recycling", isReminder true
    - "jeden Monat Miete zahlen" -> name "Miete zahlen", isReminder false, frequency "monthly"

    Do not return a sentence as the name.
    """

    enum Failure: Swift.Error, Equatable {
        case notAvailable
        case rejected(String)
    }

    /// Name and emoji limits. A habit name that does not fit on one line is not
    /// a name, it is a paragraph the person did not mean to write.
    static let maxNameScalars = 60

    static func draft(from sentence: String, language: String) async throws -> CreateItemDraft {
        guard OnDeviceModel.isAvailable else { throw Failure.notAvailable }
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: "Sentence: \(sentence)",
            generating: Parsed.self)
        let parsed = response.content
        let name = validatedName(parsed.name) ?? sentence
        let emoji = validatedEmoji(parsed.emoji)
        let schedule = CreateItemSchedule(
            frequency: parsed.schedule.frequency,
            interval: parsed.schedule.interval,
            weekdays: parsed.schedule.weekdays,
            timesPerPeriod: parsed.schedule.timesPerPeriod,
            dayOfMonth: parsed.schedule.dayOfMonth,
            month: parsed.schedule.month,
            startDay: parsed.schedule.startDay)
        let isReminder = CreateItemDraft.isReminder(parsed.isReminder, schedule: schedule)
        return CreateItemDraft(name: name, emoji: emoji, minutes: nil,
                               isReminder: isReminder, schedule: schedule)
    }

    /// A model asked to return a name will sometimes return the whole sentence,
    /// or a name wrapped in quotation marks, or a name with a trailing full
    /// stop. None of those belong in a list row.
    static func validatedName(_ raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Includes the German opening quote U+201E alongside the closing U+201C:
        // a model quoting a name in German produces „Wasser" and trimming only
        // the closing half leaves a stray mark on the row.
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”„'«».,;:! \t-–—•"))
        // A name that came back wrapped across lines, or with the gap a quoted
        // answer leaves behind, is one name. Collapsing runs of whitespace keeps
        // "Wasser  trinken" from becoming a habit called that.
        name = name.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // One bound, and only one: a Character is never shorter than a scalar,
        // so a name inside `maxNameScalars` can never exceed a larger character
        // count either. A second check was here and could not be reached — which
        // meant it also advertised an echo-detector the function did not have.
        // An echoed sentence is caught by this guard, since a sentence that is
        // mostly the original has more than 60 scalars.
        guard !name.isEmpty, name.unicodeScalars.count <= maxNameScalars else { return nil }
        return name
    }

    /// One emoji, or nothing. Two or more means the model listed options.
    ///
    /// Counted in `Character`s, not scalars, because that is what one emoji is.
    /// A flag (🇩🇪), a skin tone (👍🏽), a family (👨‍👩‍👧) and a gendered verb (🏃‍♀️)
    /// are each a single emoji a person would recognise, and each is several
    /// scalars — counting scalars threw away every one of them and left only the
    /// plainest single-codepoint symbols.
    static func validatedEmoji(_ raw: String) -> String {
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.count == 1 else { return "" }
        // One character is not enough on its own: a model that answers "a" has
        // not chosen an emoji. ASCII digits and letters are emoji-capable in
        // Unicode, so they are excluded by requiring a non-ASCII emoji scalar.
        guard candidate.unicodeScalars.contains(where: {
            $0.properties.isEmoji && !$0.isASCII
        }) else { return "" }
        return candidate
    }
}
