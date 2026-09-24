import XCTest
@testable import Haiity

/// The on-device line has one job the built-in pool cannot do: never repeat
/// itself. Everything here is about that promise and about the fallback, since
/// the pool is what keeps a message existing when the model refuses.
final class GeneratedMotivationTests: XCTestCase {

    private var defaults: UserDefaults!
    private let day = "2026-08-14"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "GeneratedMotivationTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        for key in defaults.dictionaryRepresentation().keys { defaults.removeObject(forKey: key) }
        defaults = nil
        super.tearDown()
    }

    // MARK: - Store

    func testARecordedLineIsReturnedOnlyForItsOwnDay() {
        MotivationGeneratedStore.record("Heute zählt die Zelle.", for: day, in: defaults)

        XCTAssertEqual(MotivationGeneratedStore.line(for: day, in: defaults), "Heute zählt die Zelle.")
        XCTAssertNil(MotivationGeneratedStore.line(for: "2026-08-15", in: defaults),
                     "yesterday's line must not answer for today")
    }

    func testTheRetainedWindowStaysCapped() {
        for offset in 0..<(MotivationGeneratedStore.windowLimit + 20) {
            let key = "2026-08-\(String(format: "%02d", (offset % 28) + 1))-\(offset)"
            MotivationGeneratedStore.record("Line \(offset)", for: key, in: defaults)
        }
        let retained = MotivationGeneratedStore.recentLines(in: defaults)
        XCTAssertLessThanOrEqual(retained.count, MotivationGeneratedStore.windowLimit)
        XCTAssertGreaterThan(retained.count, 0)
    }

    /// Re-recording the same day replaces the line. It must not push a duplicate
    /// of the same text into the history, or the negative examples the model
    /// sees would fill up with yesterday's line repeated.
    func testRecordingTheSameDayTwiceDoesNotDuplicateHistory() {
        MotivationGeneratedStore.record("First", for: day, in: defaults)
        MotivationGeneratedStore.record("Second", for: day, in: defaults)

        XCTAssertEqual(MotivationGeneratedStore.line(for: day, in: defaults), "Second")
        XCTAssertEqual(MotivationGeneratedStore.recentLines(in: defaults), ["Second"],
                       "the superseded line must stop counting as already shown")
    }

    /// Rolling to a new day pushes the outgoing line into the history, which is
    /// what the next prompt uses to avoid repeating it.
    func testRollingToANewDayKeepsTheOutgoingLineAsANegativeExample() {
        MotivationGeneratedStore.record("Montagssatz", for: "2026-08-13", in: defaults)
        MotivationGeneratedStore.record("Dienstagssatz", for: day, in: defaults)

        let retained = MotivationGeneratedStore.recentLines(in: defaults)
        XCTAssertTrue(retained.contains("Montagssatz"))
        XCTAssertTrue(retained.contains("Dienstagssatz"))
    }

    func testClearRemovesTheLineAndItsHistory() {
        MotivationGeneratedStore.record("Etwas", for: day, in: defaults)
        MotivationGeneratedStore.clear(in: defaults)

        XCTAssertNil(MotivationGeneratedStore.line(for: day, in: defaults))
        XCTAssertTrue(MotivationGeneratedStore.recentLines(in: defaults).isEmpty)
    }

    /// The retired feed's cached quotes must be deleted once, then left alone so
    /// a user's own defaults are not rewritten on every launch.
    func testRetiredFeedCacheIsDiscardedExactlyOnce() {
        defaults.set("[]", forKey: "motivationFeed.entries")
        defaults.set(1.0, forKey: "motivationFeed.receivedAt")

        MotivationGeneratedStore.discardRetiredFeedOnce(in: defaults)
        XCTAssertNil(defaults.object(forKey: "motivationFeed.entries"))
        XCTAssertNil(defaults.object(forKey: "motivationFeed.receivedAt"))

        defaults.set("[]", forKey: "motivationFeed.entries")
        MotivationGeneratedStore.discardRetiredFeedOnce(in: defaults)
        XCTAssertNotNil(defaults.object(forKey: "motivationFeed.entries"),
                        "the cleanup must be a one-time migration, not a loop")
    }

    // MARK: - Reading is free, writing is deliberate

    /// The central promise of this feature: the model runs only because
    /// somebody tapped. Nothing on a launch, a page load, a snapshot, or a
    /// reschedule may reach it.
    func testReadingTheCacheNeverAsksTheModel() async {
        var asked = false
        let line = MotivationDaily.cachedLine(for: day, in: defaults)
        XCTAssertNil(line)
        XCTAssertFalse(asked, "cachedLine is a pure defaults read")
    }

    func testAnAlreadyWrittenLineIsReturnedByACachedRead() {
        MotivationGeneratedStore.record("Bereits da", for: day, in: defaults)
        XCTAssertEqual(MotivationDaily.cachedLine(for: day, in: defaults), "Bereits da")
    }

    func testWritingHappensOnlyWhenAsked() async {
        var asked = false
        let line = await MotivationDaily.writeLine(
            for: day, language: "de", defaults: defaults, available: true
        ) { _, _ in asked = true; return "Ein Satz" }

        XCTAssertTrue(asked)
        XCTAssertEqual(line, "Ein Satz")
        XCTAssertEqual(MotivationGeneratedStore.line(for: day, in: defaults), "Ein Satz")
    }

    /// A second tap without a re-roll must not buy a second model call. That is
    /// the difference between "ask again" and "ask again and pay for it".
    func testASecondWriteWithoutRerollCostsNothing() async {
        MotivationGeneratedStore.record("Bereits da", for: day, in: defaults)
        var asked = false

        let line = await MotivationDaily.writeLine(
            for: day, language: "de", defaults: defaults, available: true
        ) { _, _ in asked = true; return "zweiter Satz" }

        XCTAssertEqual(line, "Bereits da")
        XCTAssertFalse(asked, "a repeat tap must not re-enter the model")
    }

    /// A re-roll IS a second call, and it replaces the line.
    func testARerollSpendsAnotherCallAndReplacesTheLine() async {
        MotivationGeneratedStore.record("Erster Satz", for: day, in: defaults)
        var asked = false

        let line = await MotivationDaily.rerollLine(
            for: day, language: "de", defaults: defaults, available: true
        ) { _, recent in
            asked = true
            XCTAssertTrue(recent.contains("Erster Satz"),
                          "the re-roll must know what it is replacing")
            return "Zweiter Satz"
        }

        XCTAssertTrue(asked)
        XCTAssertEqual(line, "Zweiter Satz")
        XCTAssertEqual(MotivationGeneratedStore.line(for: day, in: defaults), "Zweiter Satz")
    }

    func testAnUnavailableModelWritesNothing() async {
        var asked = false
        let line = await MotivationDaily.writeLine(
            for: day, language: "de", defaults: defaults, available: false
        ) { _, _ in asked = true; return "sollte nicht laufen" }

        XCTAssertNil(line)
        XCTAssertFalse(asked)
        XCTAssertNil(MotivationGeneratedStore.line(for: day, in: defaults))
    }

    func testAWriterThatFailsLeavesNoLine() async {
        let line = await MotivationDaily.writeLine(
            for: day, language: "de", defaults: defaults, available: true
        ) { _, _ in nil }

        XCTAssertNil(line)
        XCTAssertNil(MotivationGeneratedStore.line(for: day, in: defaults))
    }

    func testABlankWriteIsRejected() async {
        let line = await MotivationDaily.writeLine(
            for: day, language: "de", defaults: defaults, available: true
        ) { _, _ in "   " }

        XCTAssertNil(line)
        XCTAssertNil(MotivationGeneratedStore.line(for: day, in: defaults))
    }

    func testTheWriterIsGivenTheHistoryToAvoidRepeating() async {
        MotivationGeneratedStore.record("Gestern", for: "2026-08-13", in: defaults)
        var seen: [String] = []

        _ = await MotivationDaily.writeLine(
            for: day, language: "de", defaults: defaults, available: true
        ) { _, recent in
            seen = recent
            return "Heute etwas anderes"
        }

        XCTAssertTrue(seen.contains("Gestern"), "the model must be told what it already said")
    }

    func testTheRequestedLanguageReachesTheWriter() async {
        var requested: String?
        _ = await MotivationDaily.writeLine(
            for: day, language: "fr", defaults: defaults, available: true
        ) { language, _ in requested = language; return "Bonjour" }

        XCTAssertEqual(requested, "fr")
    }

    func testTheCombinedHelperRespectsTheRerollFlag() async {
        MotivationGeneratedStore.record("Erster", for: day, in: defaults)
        var asked = false
        let writer: MotivationDaily.Writer = { _, _ in asked = true; return "Neu" }

        _ = await MotivationDaily.rerollOrWriteLine(for: day, language: "de", reroll: false,
                                                     defaults: defaults, write: writer)
        XCTAssertFalse(asked)

        _ = await MotivationDaily.rerollOrWriteLine(for: day, language: "de", reroll: true,
                                                     defaults: defaults, write: writer)
        XCTAssertTrue(asked)
    }
}
