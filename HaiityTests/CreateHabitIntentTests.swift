import XCTest
@testable import Haiity

/// The sentence path is the one place a language model fills in product fields,
/// so the tests are about the two things that can go wrong: a time being
/// misread, and a name that is not a name.
final class CreateHabitIntentTests: XCTestCase {

    // MARK: - The no-model time strip

    /// A clock time in a sentence is a fact, so it has to survive the model's
    /// involvement. `stripTime` is the deterministic half of that.
    func testAClockTimeIsFoundAndTakenOutOfTheName() {
        let (name, minutes) = CreateItemDraft.stripTime(from: "morgens um 7:30 Wasser trinken")
        XCTAssertEqual(minutes, 7 * 60 + 30)
        XCTAssertFalse(name.contains("7:30"), "the time must not stay in the name")
        XCTAssertTrue(name.lowercased().contains("wasser"), "the thing itself must remain")
    }

    func testTheWrittenGermanHourFormIsUnderstood() {
        let (name, minutes) = CreateItemDraft.stripTime(from: "jeden Tag 7 Uhr lesen")
        XCTAssertEqual(minutes, 7 * 60)
        XCTAssertTrue(name.lowercased().contains("lesen"))
    }

    func testDotSeparatedTimesAreUnderstood() {
        XCTAssertEqual(CreateItemDraft.stripTime(from: "Yoga um 18.15").minutes, 18 * 60 + 15)
    }

    func testEveningHoursAreUnderstood() {
        XCTAssertEqual(CreateItemDraft.stripTime(from: "call at 7 PM").minutes, 19 * 60)
    }

    /// Midnight and noon must not roll over into the wrong day.
    func testBoundaryHoursSurvive() {
        XCTAssertEqual(CreateItemDraft.stripTime(from: "mitternacht 00:30").minutes, 30)
        XCTAssertEqual(CreateItemDraft.stripTime(from: "mittag 12:00").minutes, 12 * 60)
        XCTAssertEqual(CreateItemDraft.stripTime(from: "23:45 ruhen").minutes, 23 * 60 + 45)
    }

    /// A sentence with no time in it must come through untouched. This is the
    /// path that decides NOT to guess, and it is the one most likely to be
    /// broken by an over-eager pattern.
    func testASentenceWithoutATimeIsLeftAlone() {
        for sentence in ["Wasser trinken", "Every morning stretch for ten minutes",
                         "täglich yoga", "morning pages"] {
            let (name, minutes) = CreateItemDraft.stripTime(from: sentence)
            XCTAssertNil(minutes, "\\(sentence) has no time")
            XCTAssertEqual(name, sentence, "\\(sentence) must not be rewritten")
        }
    }

    /// "Ten minutes" is a duration, not a clock time. Reading it as 10:00 would
    /// silently set the wrong notification.
    func testADurationIsNotMistakenForATime() {
        let (name, minutes) = CreateItemDraft.stripTime(from: "zehn minuten meditieren")
        XCTAssertNil(minutes)
        XCTAssertEqual(name.lowercased(), "zehn minuten meditieren")
    }

    /// A number that is not a valid hour must not be consumed.
    func testAnImpossibleHourIsNotTreatedAsATime() {
        XCTAssertNil(CreateItemDraft.stripTime(from: "99:99 lesen").minutes)
    }

    // MARK: - Reading without the model

    /// With the model switched off the sentence is still usable: a name, and a
    /// time if there was one. That is the honest degraded path.
    func testReadingWithoutTheModelStillProducesAUsableDraft() async {
        let draft = await CreateItemDraft.read(from: "morgens um 7:30 Wasser trinken",
                                               useModel: false)
        XCTAssertEqual(draft.minutes, 7 * 60 + 30)
        XCTAssertTrue(draft.name.lowercased().contains("wasser"))
        XCTAssertEqual(draft.emoji, "")
        XCTAssertFalse(draft.isReminder, "a bare sentence is a habit, not a one-off")
    }

    /// A sentence that is nothing but a time still needs a name. It must not
    /// produce an empty habit row.
    func testAnEmptyNameFallsBackToTheSentence() {
        let (name, _) = CreateItemDraft.stripTime(from: "07:00")
        XCTAssertFalse(name.isEmpty, "a name must survive even if the time was all there was")
    }

    // MARK: - Model output checks

    @available(iOS 26.0, *)
    func testAModelNameIsStrippedOfQuotesAndSentencePunctuation() {
        XCTAssertEqual(CreateItemWriter.validatedName("„Wasser trinken“"), "Wasser trinken")
        XCTAssertEqual(CreateItemWriter.validatedName("\"Wasser trinken\""), "Wasser trinken")
        XCTAssertEqual(CreateItemWriter.validatedName("Wasser trinken."), "Wasser trinken")
        XCTAssertEqual(CreateItemWriter.validatedName("  Wasser  "), "Wasser")
    }

    /// A model that echoed the whole sentence instead of extracting a name must
    /// be rejected, not stored as a habit name.
    @available(iOS 26.0, *)
    func testAnEchoedSentenceIsRejectedAsAName() {
        let sentence = String(repeating: "etwas ", count: 40)
        XCTAssertNil(CreateItemWriter.validatedName(sentence))
    }

    @available(iOS 26.0, *)
    func testAnEmptyOrOversizedNameIsRejected() {
        XCTAssertNil(CreateItemWriter.validatedName(""))
        XCTAssertNil(CreateItemWriter.validatedName("   "))
        let long = String(repeating: "a", count: CreateItemWriter.maxNameScalars + 1)
        XCTAssertNil(CreateItemWriter.validatedName(long))
    }

    /// One emoji or none. A list of options is not an emoji.
    @available(iOS 26.0, *)
    func testOnlyExactlyOneEmojiIsAccepted() {
        XCTAssertEqual(CreateItemWriter.validatedEmoji("💧"), "💧")
        XCTAssertEqual(CreateItemWriter.validatedEmoji(" 💧 "), "💧")
        XCTAssertEqual(CreateItemWriter.validatedEmoji("💧🏃"), "")
        XCTAssertEqual(CreateItemWriter.validatedEmoji("water"), "")
        XCTAssertEqual(CreateItemWriter.validatedEmoji(""), "")
    }

    // MARK: - The draft

    func testTheDraftProducesTheStoredHabitShape() {
        let draft = CreateItemDraft(name: "Wasser", emoji: "💧", minutes: 7 * 60,
                                    isReminder: false)
        let habit = draft.makeHabit()
        XCTAssertEqual(habit.name, "Wasser")
        XCTAssertEqual(habit.emoji, "💧")
        XCTAssertEqual(habit.timeMinutes, 7 * 60)
        XCTAssertEqual(habit.itemType, .habit)
    }

    func testAReminderDraftProducesAReminder() {
        let draft = CreateItemDraft(name: "Anruf", emoji: "", minutes: 15 * 60,
                                    isReminder: true)
        XCTAssertEqual(draft.makeHabit().itemType, .reminder)
        XCTAssertEqual(draft.kind, .reminder)
    }

    // MARK: - The free allowance

    /// The Shortcut path is a creation path, so the free habit limit has to
    /// apply to it exactly as it does in the editor. This is the test that stops
    /// a shortcut from becoming a way around the paywall.
    func testTheFreeHabitLimitAppliesToTheShortcutToo() {
        let free = ProGate.freeHabitLimit
        for count in 0..<free {
            XCTAssertTrue(ProGate.maySaveTrackedHabit(existingIsTracked: false,
                                                       targetIsTracked: true,
                                                       activeCount: count,
                                                       unlocked: false),
                          "count \\(count) should still be inside the free allowance")
        }
        XCTAssertFalse(ProGate.maySaveTrackedHabit(existingIsTracked: false,
                                                    targetIsTracked: true,
                                                    activeCount: free,
                                                    unlocked: false),
                       "the limit must hold for a shortcut-created habit")
        // A reminder stays free, and unlocking lifts the limit.
        XCTAssertTrue(ProGate.maySaveTrackedHabit(existingIsTracked: false,
                                                   targetIsTracked: false,
                                                   activeCount: free + 10,
                                                   unlocked: false))
        XCTAssertTrue(ProGate.maySaveTrackedHabit(existingIsTracked: false,
                                                   targetIsTracked: true,
                                                   activeCount: free + 10,
                                                   unlocked: true))
    }

    private func sourceURL(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }

    // MARK: - Published surface

    /// Both intents stay reachable from the Shortcuts editor, and the one that
    /// needs the model says so where a person will read it before building an
    /// automation around it.
    func testBothCreateIntentsArePublishedWithHonestDescriptions() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Intents/CreateHabitIntent.swift"))
        XCTAssertTrue(source.contains("struct CreateHabitIntent: AppIntent"))
        XCTAssertTrue(source.contains("struct CreateItemFromTextIntent: AppIntent"))
        XCTAssertTrue(source.contains("Braucht iOS 26 und Apple Intelligence"),
                      "the model-backed intent must state its requirement up front")
    }

    /// An `AppShortcut` phrase may only interpolate an `AppEntity`, because Siri
    /// builds its corpus from the entities it can offer. A free-text `String`
    /// parameter has no such list, so a phrase naming one does not work — it
    /// emits an "unresolved variable" warning for every utterance and silently
    /// contributes nothing. That was 187 build warnings; this is the guard.
    func testNoShortcutPhraseInterpolatesAFreeTextParameter() throws {
        let shortcuts = try String(contentsOf: sourceURL("Haiity/Intents/HaiityShortcuts.swift"))
        for phrase in ["\\.$name", "\\.$text", "\\.$title", "\\.$query"] {
            XCTAssertFalse(shortcuts.contains(phrase),
                           "a Siri phrase cannot interpolate the free-text parameter \(phrase)")
        }
        // The entity-based phrases are the ones that resolve, and they stay.
        XCTAssertTrue(shortcuts.contains("\\.$habit"))
        XCTAssertTrue(shortcuts.contains("intent: CheckOffHabitIntent()"))
        XCTAssertTrue(shortcuts.contains("intent: HabitStatusIntent()"))
        // And the reason is written down, so nobody helpfully re-adds them.
        XCTAssertTrue(shortcuts.contains("may only interpolate an `AppEntity`"),
                      "the reason for omitting these phrases must be documented in the file")
    }
}
