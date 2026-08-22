import XCTest
@testable import Haiity

/// v25: die Siri/Shortcuts-Erweiterung — Nein-Semantik, Serien-Sätze und
/// der Vertrag des AppShortcuts-Katalogs.
final class SiriIntentTests: XCTestCase {
    private var url: URL!
    private var store: HabitStore!

    override func setUp() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-siri-\(UUID().uuidString).json")
        store = HabitStore(url: url)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: – Nein-Semantik

    func testDeclineWritesTheNoSentinel() {
        let h = Habit(name: "Kein Zucker", kind: .yesNo)
        store.add(h)
        XCTAssertEqual(DeclineLogic.apply(to: store, habitId: h.id, day: "2026-08-09"), .declined)
        XCTAssertTrue(store.habits[0].isDeclined("2026-08-09"))
    }

    /// Wer Siri „nicht geschafft" sagt, meint das so — auch über ein
    /// bestehendes Ja hinweg.
    func testDeclineOverridesAnExistingYes() {
        let h = Habit(name: "Kein Zucker", kind: .yesNo)
        store.add(h)
        store.setValue(h.id, day: "2026-08-09", value: Habit.Answer.yes)
        XCTAssertEqual(DeclineLogic.apply(to: store, habitId: h.id, day: "2026-08-09"), .declined)
        XCTAssertTrue(store.habits[0].isDeclined("2026-08-09"))
        XCTAssertFalse(store.habits[0].isAffirmed("2026-08-09"))
    }

    func testDeclineIsIdempotentOnAnAlreadyDeclinedDay() {
        let h = Habit(name: "Kein Zucker", kind: .yesNo)
        store.add(h)
        store.setValue(h.id, day: "2026-08-09", value: Habit.Answer.no)
        XCTAssertEqual(DeclineLogic.apply(to: store, habitId: h.id, day: "2026-08-09"), .alreadyDeclined)
        XCTAssertTrue(store.habits[0].isDeclined("2026-08-09"))
    }

    func testDeclineRefusesNonYesNoHabits() {
        let checkbox = Habit(name: "Lesen")
        let counter = Habit(name: "Wasser", recurrence: Recurrence(target: 3))
        store.add(checkbox)
        store.add(counter)
        XCTAssertEqual(DeclineLogic.apply(to: store, habitId: checkbox.id, day: "2026-08-09"), .notYesNo)
        XCTAssertEqual(DeclineLogic.apply(to: store, habitId: counter.id, day: "2026-08-09"), .notYesNo)
        XCTAssertNil(store.habits[0].log["2026-08-09"])
        XCTAssertNil(store.habits[1].log["2026-08-09"])
    }

    func testDeclineIgnoresArchivedAndUnknownHabits() {
        var archived = Habit(name: "Alt", kind: .yesNo)
        archived.archivedAt = "2026-08-01"
        store.add(archived)
        XCTAssertEqual(DeclineLogic.apply(to: store, habitId: archived.id, day: "2026-08-09"), .missing)
        XCTAssertEqual(DeclineLogic.apply(to: store, habitId: UUID(), day: "2026-08-09"), .missing)
    }

    func testDeclineSpeechNamesTheHabit() {
        for outcome: DeclineLogic.Outcome in [.declined, .alreadyDeclined, .notYesNo] {
            let speech = DeclineLogic.speech(for: outcome, name: "Kein Zucker")
            XCTAssertTrue(speech.contains("Kein Zucker"), "\(outcome): \(speech)")
        }
        XCTAssertFalse(DeclineLogic.speech(for: .missing, name: "X").isEmpty)
    }

    // MARK: – Serien-Sätze

    func testStreakSpeechCoversZeroOneAndMany() {
        XCTAssertTrue(StreakSpeech.text(name: "Lesen", streak: 0).contains("keine Serie"))
        XCTAssertTrue(StreakSpeech.text(name: "Lesen", streak: 1).contains("1 Tag"))
        let many = StreakSpeech.text(name: "Lesen", streak: 12)
        XCTAssertTrue(many.contains("12"), many)
        XCTAssertTrue(many.contains("Lesen"), many)
    }

    // MARK: – Katalog-Verträge

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relative))
    }

    /// Vier App Shortcuts, jeder Satz trägt `.applicationName`
    /// (System-Anforderung — ohne sie versteht Siri die Phrase nicht).
    func testShortcutsProviderListsAllFourIntents() throws {
        let shortcuts = try source("Haiity/Intents/HaiityShortcuts.swift")
        for intent in ["CheckOffHabitIntent()", "DeclineHabitIntent()",
                       "HabitStatusIntent()", "HabitStreakIntent()"] {
            XCTAssertTrue(shortcuts.contains("intent: \(intent)"), intent)
        }
        // Jede Phrasen-Zeile (beginnt mit ") nennt die App.
        let phraseLines = shortcuts.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("\"") }
        XCTAssertGreaterThanOrEqual(phraseLines.count, 20)
        for line in phraseLines {
            XCTAssertTrue(line.contains(".applicationName"), line)
        }
    }

    /// Die Antworten sprechen NICHT die App auf — Dialog statt App-Start —
    /// und der Tages-Wert (offene Habits) steht Kurzbefehlen zur Verfügung.
    func testQueryIntentsAnswerInPlace() throws {
        let intents = try source("Haiity/Intents/SiriQueryIntents.swift")
        XCTAssertFalse(intents.contains("openAppWhenRun"))
        XCTAssertTrue(intents.contains("ReturnsValue<Int> & ProvidesDialog"))
        XCTAssertTrue(intents.contains("SummaryText.daily(status)"),
                      "der Tagesstand spricht denselben Satz wie die Tagesmeldung")
        XCTAssertTrue(intents.contains("GoalEngine.streak(")
                      && intents.contains("today: DayKey.today(calendar:"),
                      "die Serie ist DIE Zahl aus der Statistik")
        // Nach einem Nein muss die heutige Erinnerung verstummen.
        XCTAssertTrue(intents.contains("Reminders.reconcileAfterExternalCheckIn"))
    }

    func testSiriStringsAreInTheCatalog() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Localizable.xcstrings"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        for key in ["Nein notieren", "Tagesstand", "Serie abfragen",
                    "%@ ist für heute als Nein notiert.",
                    "Heute steht kein Habit an.",
                    "%@: %lld Tage am Stück.",
                    "Diesen Habit gibt es nicht mehr."] {
            XCTAssertNotNil(strings[key], "fehlt im Katalog: \(key)")
        }
    }
}
