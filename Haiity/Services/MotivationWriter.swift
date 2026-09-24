import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Writes one motivational line with the on-device model.
///
/// **Why the model only writes the line, not the greeting.** `Motivation`
/// already owns the greeting (`openersNamed` / `openersPlain`), and those are
/// translated into every language the app ships. Asking a model to produce
/// "Hallo Anna" would replace a reviewed, catalog-backed string with an
/// unreviewed one for no gain. The repetition problem lives in the *lines* —
/// there are only 24 of them — so that is the only job handed to the model.
///
/// **Why the tone lives in the instructions.** The house voice is documented in
/// `Motivation`: calm, warm, concrete, occasionally dry, speaking the app's own
/// vocabulary (squares, cells, rows, grid, streaks). A model has never seen that
/// comment, so the instructions restate it. This is the app's voice, not a
/// generic encouragement prompt.
@available(iOS 26.0, *)
enum MotivationWriter {

    /// Structured output rather than free text: a preamble, a quotation mark or
    /// a bulleted list would all be schema violations instead of sentences the
    /// caller has to defend against.
    @Generable
    struct Draft {
        @Guide(description: "One single motivational sentence, no line breaks.")
        var line: String
    }

    /// A sentence is a notification body and a Live Activity line. These caps
    /// match the retired feed's own limits so neither surface can be flooded.
    static let maxScalars = 140
    static let minScalars = 12

    enum Failure: Swift.Error, Equatable {
        case notAvailable
        case rejected(String)
    }

    /// The voice, as instructions. Kept apart from the request so a change to
    /// the day's context does not accidentally rewrite the tone.
    private static let instructions = """
    You write one short motivational sentence for a habit tracker, in the language named in the request.

    Voice: calm, warm, concrete, occasionally dry. Speak the language of the product — squares, cells, \
    rows, the grid, streaks, showing up. Never empty encouragement, never hustle, never guilt, never \
    invented urgency, never exclamation marks, never advice about a medical or mental condition.

    Hard rules: exactly one sentence, at most 140 characters, no line breaks. Do not greet, do not use \
    the reader's name, do not add a title. Do not mention a number, a date, a streak length, or a \
    percentage — you do not know the reader's data and must not invent any. Do not ask a question.
    """

    /// - Parameter language: BCP-47 code the sentence must be written in.
    /// - Parameter recent: lines already shown, so the model does not repeat
    ///   itself. Passed as negative examples rather than trusted to remember.
    static func line(language: String, recent: [String]) async throws -> String {
        guard OnDeviceModel.isAvailable else { throw Failure.notAvailable }

        let request = prompt(language: language, recent: recent)
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: request, generating: Draft.self)
        return try validated(response.content.line, recent: recent)
    }

    // MARK: - Request

    static func prompt(language: String, recent: [String]) -> String {
        var request = "Write today's sentence in this language: \(language)."
        if !recent.isEmpty {
            let shown = recent.suffix(recentLimit).map { "• \($0)" }.joined(separator: "\n")
            request += "\n\nThese sentences were already shown. Do not repeat them or paraphrase them:\n\(shown)"
        }
        return request
    }

    /// How much history to show. Enough that a near-duplicate is recognisable,
    /// short enough to stay a rounding error next to the model's context.
    static let recentLimit = 12

    // MARK: - Guardrails

    /// The model is asked for one clean sentence, not trusted to deliver one.
    /// A response that breaks the shape the notification surface depends on is
    /// rejected so the caller can fall back to the built-in line.
    static func validated(_ raw: String, recent: [String]) throws -> String {
        let line = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        guard line.count >= minScalars else { throw Failure.rejected(raw) }
        guard line.unicodeScalars.count <= maxScalars else { throw Failure.rejected(raw) }
        // A model that echoes one of its own examples back has not written
        // anything new, and repeating yesterday is the one thing this feature
        // exists to prevent.
        let needle = line.lowercased()
        guard !recent.contains(where: { $0.lowercased() == needle }) else {
            throw Failure.rejected(raw)
        }
        return line
    }
}
