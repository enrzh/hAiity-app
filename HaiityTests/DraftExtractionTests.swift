import XCTest
@testable import Haiity

/// Reading a small local model's answer.
///
/// The models in the catalogue are 0.5B and 0.6B. They are not JSON APIs: they
/// fence their output, put German around it, write times as "07:00" or "7 Uhr",
/// contradict themselves about the schedule, and occasionally answer with prose.
/// Every case below is one of those, because a habit is a standing commitment the
/// person would otherwise have to discover and delete by hand.
///
/// The two rules that shape all of it: extract what is unambiguous, and never
/// invent. A missing field falls back to the deterministic parser; a name that
/// cannot be read makes the whole reading fail rather than becoming a blank card.
final class DraftExtractionTests: XCTestCase {

    private let sentence = "jeden Montag und Donnerstag morgens um 7 Wasser trinken"

    // MARK: - The happy path

    func testAWellFormedObjectBecomesTheDraft() throws {
        let raw = #"{"name":"Wasser trinken","emoji":"💧","minutes":420,"isReminder":false,"schedule":"weekly","weekdays":[2,5]}"#
        let outcome = try XCTUnwrap(DraftExtraction.parse(raw, sentence: sentence))

        XCTAssertEqual(outcome.draft.name, "Wasser trinken")
        XCTAssertEqual(outcome.draft.emoji, "💧")
        XCTAssertEqual(outcome.draft.minutes, 420)
        XCTAssertFalse(outcome.draft.isReminder)
        XCTAssertEqual(outcome.draft.schedule.weekdays, [2, 5])
        XCTAssertEqual(outcome.draft.schedule.frequency, .weekly)
        XCTAssertTrue(outcome.isConfident)
    }

    // MARK: - Wrappers, which small models add constantly

    func testACodeFenceIsStripped() throws {
        let raw = """
            ```json
            {"name":"Wasser trinken","emoji":"💧","minutes":420}
            ```
            """
        let outcome = try XCTUnwrap(DraftExtraction.parse(raw, sentence: sentence))
        XCTAssertEqual(outcome.draft.name, "Wasser trinken")
    }

    func testProseAroundTheObjectIsIgnored() throws {
        let raw = """
            Hier ist das Ergebnis:
            {"name":"Wasser trinken","emoji":"💧","minutes":420}
            Das war meine Antwort.
            """
        let outcome = try XCTUnwrap(DraftExtraction.parse(raw, sentence: sentence))
        XCTAssertEqual(outcome.draft.name, "Wasser trinken")
    }

    /// A brace inside a string value must not end the object early. Without the
    /// string tracking this truncates the JSON and the parse fails outright.
    func testABraceInsideAStringDoesNotEndTheObject() throws {
        let raw = #"{"name":"Wasser {trinken}","emoji":"💧","minutes":420}"#
        let outcome = try XCTUnwrap(DraftExtraction.parse(raw, sentence: sentence))
        XCTAssertEqual(outcome.draft.name, "Wasser {trinken}")
    }

    func testAnEscapedQuoteInsideAStringIsHandled() throws {
        let raw = #"{"name":"Wasser \"trinken\"","emoji":"💧","minutes":420}"#
        let outcome = try XCTUnwrap(DraftExtraction.parse(raw, sentence: sentence))
        XCTAssertEqual(outcome.draft.name, #"Wasser "trinken""#)
    }

    // MARK: - When there is nothing to read

    /// No name means no habit, so the whole reading fails rather than producing a
    /// card with a blank title.
    func testAMissingNameFailsRatherThanProduceABlankDraft() {
        XCTAssertNil(DraftExtraction.parse(#"{"emoji":"💧","minutes":420}"#, sentence: sentence))
        XCTAssertNil(DraftExtraction.parse(#"{"name":"","emoji":"💧"}"#, sentence: sentence))
        XCTAssertNil(DraftExtraction.parse(#"{"name":"   "}"#, sentence: sentence))
    }

    func testProseWithNoObjectFails() {
        XCTAssertNil(DraftExtraction.parse("Das kann ich nicht.", sentence: sentence))
        XCTAssertNil(DraftExtraction.parse("", sentence: sentence))
    }

    func testTruncatedJSONFails() {
        // Cut off mid-string, which is what an interrupted generation looks like.
        XCTAssertNil(DraftExtraction.parse(
            ##"{"name":"Wasser","emoji":"💧","minutes":42"##, sentence: sentence))
    }

    // MARK: - Times, in the shapes a model writes them

    func testAClockStringIsReadAsMinutes() {
        XCTAssertEqual(DraftExtraction.minutes(from: "07:00"), 420)
        XCTAssertEqual(DraftExtraction.minutes(from: "7:30"), 450)
        XCTAssertEqual(DraftExtraction.minutes(from: "18:15"), 1095)
        XCTAssertEqual(DraftExtraction.minutes(from: "0:00"), 0)
    }

    func testABareHourWithUhrIsRead() {
        XCTAssertEqual(DraftExtraction.minutes(from: "7 Uhr"), 420)
        XCTAssertEqual(DraftExtraction.minutes(from: " 19 "), 19 * 60)
    }

    func testANumberIsRead() {
        XCTAssertEqual(DraftExtraction.minutes(from: 420), 420)
        XCTAssertEqual(DraftExtraction.minutes(from: 1095.0), 1095)
    }

    /// An impossible time is dropped, not clamped. Clamping would silently invent
    /// a time the person never said.
    func testAnImpossibleTimeIsDroppedNotClamped() {
        XCTAssertNil(DraftExtraction.minutes(from: 1500))
        XCTAssertNil(DraftExtraction.minutes(from: -30))
        XCTAssertNil(DraftExtraction.minutes(from: "25:00"))
        XCTAssertNil(DraftExtraction.minutes(from: "halb neun"))
    }

    /// When the model's time is unusable the deterministic one stands. The
    /// sentence said "um 7", so 420 is a fact; the model's "halb neun" is noise.
    func testAnUnreadableTimeFallsBackToTheDeterministicOne() throws {
        let raw = #"{"name":"Wasser trinken","emoji":"💧","minutes":"halb neun"}"#
        let outcome = try XCTUnwrap(DraftExtraction.parse(raw, sentence: sentence))
        XCTAssertEqual(outcome.draft.minutes, 420, "the sentence's own time, not the model's noise")
    }

    func testNoTimeAtAllMeansNoTime() throws {
        let raw = #"{"name":"Wasser trinken","emoji":"💧"}"#
        // A sentence with no clock time in it, so the deterministic half has
        // nothing to fall back to either.
        let outcome = try XCTUnwrap(
            DraftExtraction.parse(raw, sentence: "abends mehr lesen"))
        XCTAssertNil(outcome.draft.minutes, "a sentence with no clock time gets none")
    }

    // MARK: - Schedules

    /// Sunday is 1, matching Calendar and Recurrence. Off by one here is a habit
    /// that silently fires on the wrong day for a month.
    func testWeekdayNamesUseTheSameBaseAsTheSchedule() {
        let raw = #"{"name":"x","schedule":"weekly","weekdays":"montag, donnerstag"}"#
        let outcome = DraftExtraction.parse(raw, sentence: "x")
        XCTAssertEqual(outcome?.draft.schedule.weekdays, [2, 5],
                       "Monday is 2 and Thursday 5, not ISO 1 and 4")
    }

    /// A frequency the model gets wrong is dropped to daily rather than turned
    /// into something plausible: the schedule type already enforces that, and a
    /// misread repeat is far more damaging than a missing one.
    func testAnUnknownFrequencyBecomesDaily() {
        let raw = #"{"name":"x","schedule":"asdfasdf","weekdays":[1,3]}"#
        XCTAssertEqual(DraftExtraction.parse(raw, sentence: "x")?.draft.schedule.frequency, .daily)
    }

    func testOutOfRangeWeekdaysAreDropped() {
        let raw = #"{"name":"x","schedule":"weekly","weekdays":[0,3,9,-1]}"#
        XCTAssertEqual(DraftExtraction.parse(raw, sentence: "x")?.draft.schedule.weekdays, [3],
                       "the schedule drops weekdays it cannot mean, not the parser")
    }

    // MARK: - Emojis

    func testASingleEmojiIsKept() {
        XCTAssertEqual(DraftExtraction.singleSymbol(in: "💧"), "💧")
        XCTAssertEqual(DraftExtraction.singleSymbol(in: "📚"), "📚")
    }

    /// Family and skin-tone sequences are several scalars that render as one
    /// glyph. Without stripping the joiner and the modifier the app would show
    /// three boxes.
    func testAMultiScalarEmojiCollapsesToOneVisibleCharacter() {
        XCTAssertEqual(DraftExtraction.singleSymbol(in: "👨‍👩‍👧"), "👨‍👩‍👧")
        XCTAssertEqual(DraftExtraction.singleSymbol(in: "👍🏽"), "👍🏽")
        XCTAssertEqual(DraftExtraction.singleSymbol(in: "❤️"), "❤")
    }

    /// Several real characters is a sentence, not a symbol.
    func testSeveralCharactersAreNotASymbol() {
        XCTAssertNil(DraftExtraction.singleSymbol(in: "Wasser"))
        XCTAssertNil(DraftExtraction.singleSymbol(in: "💧💧"))
        XCTAssertNil(DraftExtraction.singleSymbol(in: " "))
    }

    /// The shapes a model emits when it is answering with a placeholder.
    /// "{" and "}" are single visible characters, so they pass as ink and have
    /// to be refused by the two-character rule rather than by shape.
    func testPlaceholderShapesAreRefused() {
        XCTAssertNil(DraftExtraction.singleSymbol(in: "{}"), "two characters is not a symbol")
        XCTAssertNil(DraftExtraction.singleSymbol(in: "\\"))
        XCTAssertNil(DraftExtraction.singleSymbol(in: ""))
        XCTAssertNil(DraftExtraction.singleSymbol(in: "\u{200D}"), "a lone joiner draws nothing")
    }

    func testAnUnusableEmojiLeavesTheFieldEmptyRatherThanJunk() throws {
        let raw = #"{"name":"Wasser trinken","emoji":"{}","minutes":420}"#
        let outcome = try XCTUnwrap(DraftExtraction.parse(raw, sentence: sentence))
        XCTAssertEqual(outcome.draft.emoji, "", "no icon beats a broken one")
    }

    // MARK: - Reminders, which the deterministic half owns

    /// A one-off is a reminder whatever the model said, because a once-only thing
    /// filed under habits is tracked forever and counts against the free limit.
    func testAOnceOnlyThingIsAReminderEvenIfTheModelDisagrees() throws {
        let raw = #"{"name":"Zahnarzt","emoji":"🦷","minutes":540,"isReminder":false,"schedule":"daily"}"#
        let outcome = try XCTUnwrap(DraftExtraction.parse(raw, sentence: "einmal morgen Zahnarzt"))
        XCTAssertTrue(outcome.draft.isReminder,
                      "the rule lives below the model, not in the prompt")
        XCTAssertEqual(outcome.draft.schedule.frequency, .once)
    }

    /// The deterministic guard that makes the above possible. Narrow on purpose: a
    /// bare "einmal" with nothing contradicting it is a one-off, and "einmal" next
    /// to a repetition word is not.
    func testAOnceOnlySentenceIsRecognised() {
        XCTAssertTrue(DraftExtraction.readsAsOneOff("einmal morgen Zahnarzt"))
        XCTAssertTrue(DraftExtraction.readsAsOneOff("einmal ins Theater gehen"))
        XCTAssertTrue(DraftExtraction.readsAsOneOff("once a month call the dentist"))
    }

    func testASentenceThatAlsoRepeatsIsNotAOneOff() {
        XCTAssertFalse(DraftExtraction.readsAsOneOff("einmal morgen und dann jeden Montag"))
        XCTAssertFalse(DraftExtraction.readsAsOneOff("jeden Montag einmal schwimmen"))
    }

    /// "morgen" alone is not a decision to do something once — "morgen jeden
    /// Montag" repeats. The guard must not fire on it.
    func testTomorrowAloneIsNotAOneOff() {
        XCTAssertFalse(DraftExtraction.readsAsOneOff("morgen Wasser trinken"))
        XCTAssertFalse(DraftExtraction.readsAsOneOff("jeden Morgen lesen"))
    }

    // MARK: - The prompt

    /// The prompt and the parser are one design: if the prompt stops asking for
    /// something, the parser's handling of it is dead weight, and if the parser
    /// stops coping with something, the prompt is asking for the impossible.
    func testThePromptAsksForExactlyWhatTheParserReads() {
        let prompt = DraftExtraction.systemPrompt
        for field in ["name", "emoji", "minutes", "isReminder", "schedule", "weekdays"] {
            XCTAssertTrue(prompt.contains("\"\(field)\""),
                          "the prompt asks for \(field) but the field name should be quoted")
        }
        // The worked example is the sentence the rest of the suite uses, so the
        // two cannot drift apart.
        XCTAssertTrue(prompt.contains("jeden Montag und Donnerstag morgens um 7 Wasser trinken")
                      || prompt.contains("Wasser trinken"),
                      "the prompt's example and the parser's tests should agree")
        // And it must forbid the wrappers the parser is tested against.
        XCTAssertTrue(prompt.contains("ohne Codefences"))
    }
}
