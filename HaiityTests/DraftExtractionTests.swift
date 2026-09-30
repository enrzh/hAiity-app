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

    /// The sentence the bug was reported with, read end to end through the
    /// downloaded model's parser — with the model answering `daily`, which is
    /// exactly what a small model does with a sentence that never says the word
    /// "once". The sentence names a day, so the sentence has to win.
    func testTomorrowAtTenIsAOneOffWhateverTheModelAnswers() throws {
        let raw = #"{"name":"Doc","emoji":"🩺","minutes":600,"isReminder":false,"schedule":"daily"}"#
        let sentence = "I want to go to Doc tomorrow at 10 am"
        let outcome = try XCTUnwrap(DraftExtraction.parse(raw, sentence: sentence))
        XCTAssertEqual(outcome.draft.schedule.frequency, .once,
                       "a day named as a shift from today cannot come round again")
        XCTAssertTrue(outcome.draft.isReminder, "a one-off is a reminder, not a habit")
        XCTAssertEqual(outcome.draft.minutes, 10 * 60)
        // The day came with it, so the reminder lands on tomorrow rather than
        // on whatever day the sentence happened to be read. `.current`, because
        // that is the calendar production reads with.
        let calendar = Calendar.current
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1,
                                                   to: Date()))
        XCTAssertEqual(outcome.draft.schedule.startDay, DayKey.key(for: tomorrow,
                                                                   calendar: calendar))
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

    /// The days a sentence can name, and the one German homograph that makes
    /// this hard.
    ///
    /// This test used to assert that a bare "morgen" is NOT a one-off, on the
    /// grounds that "morgen jeden Montag" repeats. That case was never the
    /// problem — the repetition guard underneath handles it, and left the guard
    /// out of a sentence that names one specific day meant "tomorrow at 10 am"
    /// was filed as a DAILY habit. A day that shifts from today does not come
    /// round again, so the sentence has said it happens once.
    func testASentenceThatNamesOneDayIsAOneOff() {
        XCTAssertTrue(DraftExtraction.readsAsOneOff("morgen Wasser trinken"))
        XCTAssertTrue(DraftExtraction.readsAsOneOff(
            "I want to go to Doc tomorrow at 10 am"))
        XCTAssertTrue(DraftExtraction.readsAsOneOff("heute Brot holen"))
        XCTAssertTrue(DraftExtraction.readsAsOneOff("den Flug übermorgen buchen"))
        XCTAssertTrue(DraftExtraction.readsAsOneOff("next Tuesday call the dentist"))
        XCTAssertTrue(DraftExtraction.readsAsOneOff("nächsten Dienstag zum Zahnarzt"))
    }

    /// "Morgen" is also MORNING in German, and only the neighbouring word says
    /// which. Reading it as a substring would have to be wrong about one of
    /// these two: they contain the identical character sequence.
    func testMorningIsNotTomorrow() {
        XCTAssertFalse(DraftExtraction.readsAsOneOff("jeden Morgen lesen"))
        XCTAssertFalse(DraftExtraction.readsAsOneOff("am Morgen joggen"))
        XCTAssertFalse(DraftExtraction.readsAsOneOff("morgens um 7 Wasser trinken"))
        XCTAssertFalse(DraftExtraction.readsAsOneOff("vormittags arbeiten"))
    }

    /// A cadence, not a date. These contain no one-off marker at all and must
    /// stay on the model's reading rather than being promoted.
    func testACadenceIsNotAOneOff() {
        XCTAssertFalse(DraftExtraction.readsAsOneOff("jeden Montag lesen"))
        XCTAssertFalse(DraftExtraction.readsAsOneOff("weekly flossing"))
        // "next" alone names a span, not a day: "die nächsten Wochen" and
        // "next week" are stretches of future, and only the pair with a
        // weekday settles on one date.
        XCTAssertFalse(DraftExtraction.readsAsOneOff("in den nächsten Wochen trainieren"))
        XCTAssertFalse(DraftExtraction.readsAsOneOff("next week start running"))
    }

    /// The day that came with it, or nil when the sentence named no day this
    /// can work out. Nothing is invented: a weekday or a calendar date is the
    /// models' job, and a guess here would be a reminder on the wrong date.
    func testTheNamedDayIsResolved() throws {
        let calendar = Calendar(identifier: .gregorian)
        var now = DateComponents()
        now.year = 2026; now.month = 9; now.day = 30
        let today = try XCTUnwrap(calendar.date(from: now))

        XCTAssertEqual(DraftExtraction.namedDayKey("tomorrow at 10 am",
                                                   calendar: calendar, now: today),
                       "2026-10-01")
        XCTAssertEqual(DraftExtraction.namedDayKey("morgen zum Zahnarzt",
                                                   calendar: calendar, now: today),
                       "2026-10-01")
        XCTAssertEqual(DraftExtraction.namedDayKey("heute Brot holen",
                                                   calendar: calendar, now: today),
                       "2026-09-30")
        XCTAssertEqual(DraftExtraction.namedDayKey("übermorgen fliegen",
                                                   calendar: calendar, now: today),
                       "2026-10-02")
        // "jeden Morgen" is a time of day, so it names no day — and neither
        // does a sentence that only says "montags".
        XCTAssertNil(DraftExtraction.namedDayKey("jeden Morgen lesen",
                                                 calendar: calendar, now: today))
        XCTAssertNil(DraftExtraction.namedDayKey("montags laufen",
                                                 calendar: calendar, now: today))
    }

    // MARK: - The prompt

    /// The prompt and the parser are one design: if the prompt stops asking for
    /// something, the parser's handling of it is dead weight, and if the parser
    /// stops coping with something, the prompt is asking for the impossible.
    func testThePromptAsksForExactlyWhatTheParserReads() {
        let prompt = DraftExtraction.systemPrompt
        for field in ["name", "emoji", "minutes", "isReminder", "schedule", "weekdays", "startDay"] {
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
