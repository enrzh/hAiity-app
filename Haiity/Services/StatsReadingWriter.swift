import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reads the reader's own statistics back to them in one calm sentence.
///
/// **Why the model is not asked a question.** The interesting work here is not
/// generation, it is restraint. The facts are already on screen; what a person
/// cannot get from a grid is the sentence a friend would say about it. So the
/// writer gets a closed list of numbers and is forbidden from adding, adjusting
/// or explaining any of them — and `StatsReadingValidator` checks the output
/// against that list before a single word reaches the card.
///
/// **Why the fallback is the chart and not a sentence.** If the model is
/// unavailable, refuses, or says anything the validator rejects, the card is not
/// shown. The statistics themselves are untouched. A missing sentence is a much
/// smaller loss than a wrong number, which is the whole point of the feature
/// being optional.
@available(iOS 26.0, *)
enum StatsReadingWriter {

    @Generable
    struct Reading {
        @Guide(description: "One or two calm sentences describing the given facts, no line breaks.")
        var text: String
    }

    private static let instructions = """
    You describe a habit tracker's own numbers back to the person who owns them, \
    in the language named in the request.

    Voice: calm, warm, concrete, occasionally dry — the voice of the product, not a coach and not a \
    motivational speaker. Speak of squares, cells, rows, the grid, streaks, checking in.

    Hard rules:
    - Use only the numbers given. Never add, subtract, convert, round, or estimate one. Never mention a \
    number that is not in the list, and never guess at a percentage.
    - The screen already tells the reader what today is. Do not restate today; describe the pattern over     time that the screen does not already spell out.
    - Do not calculate anything the reader could do themselves.
    - Do not give advice, do not assign a mood, do not congratulate or scold, do not ask a question.
    - At most two sentences, at most 220 characters, no line breaks, no lists, no headings.
    - If the facts are thin, say something brief and true about what is there. Never pad.
    """

    enum Failure: Swift.Error, Equatable {
        case notAvailable
        case rejected(StatsReadingValidator.Rejection)
    }

    static func text(facts: StatsReadingFacts, language: String) async throws -> String {
        guard OnDeviceModel.isAvailable else { throw Failure.notAvailable }
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: request(facts: facts, language: language),
                                                 generating: Reading.self)
        switch StatsReadingValidator.validate(response.content.text, facts: facts) {
        case .success(let text): return text
        case .failure(let rejection): throw Failure.rejected(rejection)
        }
    }

    static func request(facts: StatsReadingFacts, language: String) -> String {
        """
        Write in this language: \(language).

        These are the facts, and the only ones you may use:
        \(facts.promptFacts)
        """
    }
}

/// One reading per day, kept next to the facts it was written from.
///
/// Cached per day rather than per data change on purpose. A reading that
/// rewrote itself every time a square was filled would flicker while the person
/// was looking at it, and would cost a model call per tap. Once a day is also
/// the cadence the sentence is written for.
struct StatsReading: Codable, Equatable, Sendable {
    var dayKey: String
    var text: String
}

enum StatsReadingStore {

    private static let key = "stats.reading.v1"

    private struct Payload: Codable {
        var current: StatsReading?
        init(current: StatsReading? = nil) { self.current = current }
    }

    private static func payload(in defaults: UserDefaults) -> Payload {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data)
        else { return Payload() }
        return decoded
    }

    static func reading(for dayKey: String, in defaults: UserDefaults) -> StatsReading? {
        guard let current = payload(in: defaults).current, current.dayKey == dayKey else { return nil }
        return current
    }

    static func record(_ text: String, for dayKey: String, in defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(Payload(current: StatsReading(dayKey: dayKey, text: text)))
        else { return }
        defaults.set(data, forKey: key)
    }

    static func clear(in defaults: UserDefaults) {
        defaults.removeObject(forKey: key)
    }
}

/// What the always-visible reading block is showing.
enum StatsReadingPhase: Equatable {
    /// Nothing yet. This is the invitation, not an absence.
    case idle
    /// The person tapped and the model is working.
    case working
    case shown(String)
    /// The model cannot run here. Explained, never a dead control.
    case unavailable(OnDeviceModelAvailability)
    /// It ran and produced nothing usable. A miss is cheaper than a wrong number.
    case failed
}

/// Reading and writing the day's reading — deliberately two different things.
///
/// Writing is only ever reached from a deliberate tap. The statistics page is
/// the screen people open most, so a reading generated on every visit would
/// spend heat continuously for something the person may never look at. Reading
/// is free, so restoring yesterday's reading on open costs a defaults lookup.
enum StatsReadingDaily {

    typealias Writer = (_ facts: StatsReadingFacts, _ language: String) async -> String?

    static let onDeviceWriter: Writer = { facts, language in
        guard #available(iOS 26.0, *), OnDeviceModel.isAvailable else { return nil }
        do {
            return try await StatsReadingWriter.text(facts: facts, language: language)
        } catch {
            NSLog("StatsReadingDaily: on-device read failed: %@", String(describing: error))
            return nil
        }
    }

    /// Today's reading if one was already written. A pure read, so the block can
    /// show yesterday's result immediately on open without touching the model.
    static func cachedReading(for dayKey: String, in defaults: UserDefaults) -> String? {
        StatsReadingStore.reading(for: dayKey, in: defaults)?.text
    }

    /// Write a reading because the person asked for one.
    ///
    /// - Parameter reroll: `true` spends a second model call to replace a
    ///   reading they did not like. It is never inferred — the caller has to
    ///   mean it.
    /// - Returns: the reading, or `nil` when nothing usable came back. Every
    ///   failure mode — old system, ineligible device, Apple Intelligence off,
    ///   a refusal, or output the validator rejected — is the same `nil`, and
    ///   the block explains rather than guessing which one it was.
    static func write(for dayKey: String,
                      facts: StatsReadingFacts,
                      language: String,
                      defaults: UserDefaults,
                      reroll: Bool = false,
                      available: Bool = OnDeviceModel.isAvailable,
                      write: Writer) async -> String? {
        if !reroll, let cached = StatsReadingStore.reading(for: dayKey, in: defaults) {
            return cached.text
        }
        guard available, facts.hasSomethingToSay else { return nil }
        guard let text = await write(facts, language) else { return nil }
        StatsReadingStore.record(text, for: dayKey, in: defaults)
        return text
    }
}
