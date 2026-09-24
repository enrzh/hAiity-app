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
    struct Parsed {
        @Guide(description: "The item's name with no time, no schedule words and no filler.")
        var name: String
        @Guide(description: "A single emoji, or an empty string when the sentence has none.")
        var emoji: String
        @Guide(description: "True only when the sentence clearly means a one-off reminder rather than a tracked habit.")
        var isReminder: Bool
    }

    private static let instructions = """
    You read one sentence in which someone describes something they want to track or be reminded about, \
    and you fill in the fields of a habit-tracker item. The sentence is in the language named in the request.

    Rules:
    - `name` is the thing itself, in that language, as a short noun phrase. Strip everything else: times, \
    "every morning", "at work", "don't forget to", please words, filler.
    - `emoji` is ONE emoji that fits the thing, or an empty string if none is obvious. Never more than one.
    - `isReminder` is true only when the sentence clearly means a single occurrence ("remind me at 3", \
    "once at noon"). A repeated or open-ended thing is a habit and stays false.

    Do not invent anything that is not in the sentence. Do not return a sentence as the name.
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
        return CreateItemDraft(name: name, emoji: emoji, minutes: nil, isReminder: parsed.isReminder)
    }

    /// A model asked to return a name will sometimes return the whole sentence,
    /// or a name wrapped in quotation marks, or a name with a trailing full
    /// stop. None of those belong in a list row.
    static func validatedName(_ raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Includes the German opening quote U+201E alongside the closing U+201C:
        // a model quoting a name in German produces „Wasser" and trimming only
        // the closing half leaves a stray mark on the row.
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”„'«».,;: "))
        guard !name.isEmpty, name.unicodeScalars.count <= maxNameScalars else { return nil }
        // A "name" that is still mostly the original sentence means the model
        // echoed rather than extracted.
        if name.count > 80 { return nil }
        return name
    }

    /// One emoji, or nothing. Two or more means the model listed options.
    static func validatedEmoji(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.filter { !CharacterSet.whitespaces.contains($0) }
        guard scalars.count == 1 else { return "" }
        return String(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
