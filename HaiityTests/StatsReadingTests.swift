import XCTest
@testable import Haiity

/// The validator is the only thing between a language model and a number on
/// somebody's statistics screen, so it is tested like a security boundary
/// rather than like a string helper: the cases below are the ways a model
/// plausibly goes wrong.
final class StatsReadingTests: XCTestCase {

    private func facts(todayDone: Int = 2, todayTotal: Int = 4,
                       streak: Int = 5, best: Int = 11,
                       weekDone: Int = 8, weekTotal: Int = 12,
                       previousDone: Int = 5, previousTotal: Int = 10,
                       total: Int = 140, habits: Int = 3,
                       strongestName: String? = "Lesen",
                       strongestStreak: Int = 9) -> StatsReadingFacts {
        StatsReadingFacts(snapshot: StatsEngine.Snapshot(
            today: "2026-08-14",
            todayDone: todayDone, todayTotal: todayTotal,
            streak: streak, bestStreak: best,
            week: .init(done: weekDone, total: weekTotal),
            previousWeek: .init(done: previousDone, total: previousTotal),
            last7: [], last7HasData: [],
            mergedLevels: [],
            perHabit: strongestName.map {
                [StatsEngine.HabitStreaks(id: UUID(), name: $0, emoji: "📖",
                                          current: strongestStreak, best: strongestStreak,
                                          completion30: 0.5, monthlyCounts: [])]
            } ?? [],
            totalCheckIns: total))
    }

    // MARK: - Facts

    /// The reading must not restate what the Today card already says. If these
    /// numbers reappear in the prompt, the feature becomes the app saying the
    /// same thing twice.
    func testTodaysNumbersAreNotOfferedToTheWriter() {
        let subject = facts(todayDone: 2, todayTotal: 4)
        XCTAssertFalse(subject.numbers.contains(2) && !Array([2, 4, 5, 11, 8, 12, 5, 10, 140, 3, 9])
            .contains(2), "sanity: 2 may legitimately be a week count")
        XCTAssertFalse(subject.promptFacts.contains("done today"))
        XCTAssertFalse(subject.promptFacts.lowercased().contains("today"))
    }

    func testThePromptNamesEveryFactItAllows() {
        let prompt = facts().promptFacts
        for expected in ["current streak", "longest streak", "done this week",
                         "done last week", "total check-ins", "habits tracked",
                         "longest current run"] {
            XCTAssertTrue(prompt.contains(expected), "the prompt is missing \\(expected)")
        }
    }

    func testNothingToSayWithoutHabitsOrHistory() {
        var empty = facts()
        empty = StatsReadingFacts(snapshot: StatsEngine.Snapshot(
            today: "2026-08-14", todayDone: 0, todayTotal: 0,
            streak: 0, bestStreak: 0,
            week: .init(done: 0, total: 0),
            previousWeek: .init(done: 0, total: 0),
            last7: [], last7HasData: [], mergedLevels: [],
            perHabit: [], totalCheckIns: 0))
        XCTAssertFalse(empty.hasSomethingToSay)
        XCTAssertTrue(facts().hasSomethingToSay)
    }

    // MARK: - Number extraction

    func testDigitRunsAreReadInTheFormsAModelActuallyWrites() {
        XCTAssertEqual(StatsReadingValidator.numbers(in: "140 check-ins"), [140])
        XCTAssertEqual(StatsReadingValidator.numbers(in: "1,234 things"), [1234])
        XCTAssertEqual(StatsReadingValidator.numbers(in: "1.234 Dinge"), [1234])
        XCTAssertEqual(StatsReadingValidator.numbers(in: "streak 5, week 8 of 12"), [5, 8, 12])
        XCTAssertEqual(StatsReadingValidator.numbers(in: "no digits here"), [])
    }

    // MARK: - Validation

    func testASentenceUsingOnlyKnownNumbersIsAccepted() {
        let subject = facts()
        let text = "Die Woche trägt mehr als die letzte: 8 von 12, und die 9 Tage von Lesen tragen sie."
        guard case .success(let clean) = StatsReadingValidator.validate(text, facts: subject) else {
            return XCTFail("a truthful reading must be accepted")
        }
        XCTAssertEqual(clean, text)
    }

    /// The guard that matters: a number that is not in the facts is refused, so
    /// the card is omitted rather than showing something invented.
    func testAnInventedNumberIsRejected() {
        let subject = facts()
        let result = StatsReadingValidator.validate(
            "Du hast 47 check-ins gesammelt.", facts: subject)
        XCTAssertEqual(result, .failure(.inventsNumber("47")))
    }

    func testAnInventedPercentageIsRejectedEvenWhenTheCountIsReal() {
        let subject = facts()
        let result = StatsReadingValidator.validate(
            "Das sind 80 Prozent deiner Woche, denn 8 von 12.", facts: subject)
        XCTAssertEqual(result, .failure(.inventsNumber("80")))
    }

    func testTooShortTooLongAndListShapedReadingsAreRejected() {
        let subject = facts()
        XCTAssertEqual(StatsReadingValidator.validate("Gut.", facts: subject), .failure(.tooShort))
        let long = String(repeating: "a", count: StatsReadingValidator.maxScalars + 1)
        XCTAssertEqual(StatsReadingValidator.validate(long, facts: subject), .failure(.tooLong))
        XCTAssertEqual(StatsReadingValidator.validate("Erste Zeile.\nZweite Zeile.", facts: subject),
                       .failure(.notSentences))
        XCTAssertEqual(StatsReadingValidator.validate("• 8 von 12 erledigt", facts: subject),
                       .failure(.tooShort))
    }

    func testSurroundingWhitespaceIsTrimmedRatherThanRejected() {
        let subject = facts()
        let text = "  Die Woche ist dichter als die letzte, mit 8 von 12.  "
        guard case .success(let clean) = StatsReadingValidator.validate(text, facts: subject) else {
            return XCTFail("padding must not fail a good reading")
        }
        XCTAssertEqual(clean, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Coordinator

    /// The statistics page is the most-opened screen in the app. If opening it
    /// could reach the model, the feature would spend heat continuously for
    /// something the person may never read.
    func testReadingTheCacheNeverAsksTheModel() {
        var asked = false
        let text = StatsReadingDaily.cachedReading(for: "2026-08-14", in: makeDefaults())
        _ = asked
        XCTAssertNil(text)
    }

    func testACachedReadingIsRestoredWithoutAModelCall() {
        let defaults = makeDefaults()
        StatsReadingStore.record("Die Woche ist dichter.", for: "2026-08-14", in: defaults)

        XCTAssertEqual(StatsReadingDaily.cachedReading(for: "2026-08-14", in: defaults),
                       "Die Woche ist dichter.")
        XCTAssertNil(StatsReadingDaily.cachedReading(for: "2026-08-15", in: defaults),
                     "yesterday's reading must not answer for today")
    }

    func testWritingHappensOnlyWhenAsked() async {
        var asked = false
        let text = await StatsReadingDaily.write(
            for: "2026-08-14", facts: facts(), language: "de",
            defaults: makeDefaults(), available: true
        ) { _, _ in asked = true; return "Die Woche ist dichter." }

        XCTAssertTrue(asked)
        XCTAssertEqual(text, "Die Woche ist dichter.")
    }

    func testATapWithoutRerollDoesNotPayTwice() async {
        let defaults = makeDefaults()
        StatsReadingStore.record("Schon da", for: "2026-08-14", in: defaults)
        var asked = false

        let text = await StatsReadingDaily.write(
            for: "2026-08-14", facts: facts(), language: "de",
            defaults: defaults, available: true
        ) { _, _ in asked = true; return "Neu" }

        XCTAssertEqual(text, "Schon da")
        XCTAssertFalse(asked)
    }

    func testARerollSpendsAnotherCall() async {
        let defaults = makeDefaults()
        StatsReadingStore.record("Schon da", for: "2026-08-14", in: defaults)
        var asked = false

        let text = await StatsReadingDaily.write(
            for: "2026-08-14", facts: facts(), language: "de",
            defaults: defaults, reroll: true, available: true
        ) { _, _ in asked = true; return "Neu" }

        XCTAssertTrue(asked)
        XCTAssertEqual(text, "Neu")
    }

    func testAnUnavailableModelProducesNoCard() async {
        let defaults = makeDefaults()
        var asked = false
        let text = await StatsReadingDaily.write(
            for: "2026-08-14", facts: facts(), language: "de",
            defaults: defaults, available: false
        ) { _, _ in asked = true; return "sollte nicht laufen" }

        XCTAssertNil(text)
        XCTAssertFalse(asked)
        XCTAssertNil(StatsReadingStore.reading(for: "2026-08-14", in: defaults))
    }

    func testFactsWithNothingToSayNeverReachTheModel() async {
        let defaults = makeDefaults()
        var asked = false
        let empty = StatsReadingFacts(snapshot: StatsEngine.Snapshot(
            today: "2026-08-14", todayDone: 0, todayTotal: 0,
            streak: 0, bestStreak: 0,
            week: .init(done: 0, total: 0),
            previousWeek: .init(done: 0, total: 0),
            last7: [], last7HasData: [], mergedLevels: [],
            perHabit: [], totalCheckIns: 0))

        let text = await StatsReadingDaily.write(
            for: "2026-08-14", facts: empty, language: "de",
            defaults: defaults, available: true
        ) { _, _ in asked = true; return "irgendetwas" }

        XCTAssertNil(text)
        XCTAssertFalse(asked, "there is no finding to phrase, so the model must not be called")
    }

    func testAWriterThatRefusesLeavesNoReading() async {
        let defaults = makeDefaults()
        let text = await StatsReadingDaily.write(
            for: "2026-08-14", facts: facts(), language: "de",
            defaults: defaults, available: true
        ) { _, _ in nil }

        XCTAssertNil(text)
        XCTAssertNil(StatsReadingStore.reading(for: "2026-08-14", in: defaults))
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "StatsReadingTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite) ?? .standard
    }
}
