import XCTest
@testable import Haiity

/// Abhak-Semantik des Widget-/Siri-Intents — pure Logik, ohne
/// AppIntents-Laufzeit testbar.
final class CheckOffLogicTests: XCTestCase {
    private var url: URL!
    private var store: HabitStore!

    override func setUp() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-checkoff-\(UUID().uuidString).json")
        store = HabitStore(url: url)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    func testCheckboxOpenBecomesDone() {
        let h = Habit(name: "Lesen")
        store.add(h)
        let wrote = CheckOffLogic.apply(to: store, habitId: h.id, day: "2026-08-09")
        XCTAssertTrue(wrote)
        XCTAssertEqual(store.habits[0].log["2026-08-09"], 1)
    }

    func testCheckboxAlreadyDoneStaysDone() {
        // Idempotent: der Button darf NIE ent-haken.
        let h = Habit(name: "Lesen")
        store.add(h)
        store.toggle(h.id, day: "2026-08-09")
        let wrote = CheckOffLogic.apply(to: store, habitId: h.id, day: "2026-08-09")
        XCTAssertFalse(wrote)
        XCTAssertEqual(store.habits[0].log["2026-08-09"], 1)
    }

    func testQuantityIncrementsEvenPastTarget() {
        let h = Habit(name: "Wasser", recurrence: Recurrence(target: 2))
        store.add(h)
        store.increment(h.id, day: "2026-08-09")
        store.increment(h.id, day: "2026-08-09") // Ziel erreicht (2/2)
        let wrote = CheckOffLogic.apply(to: store, habitId: h.id, day: "2026-08-09")
        XCTAssertTrue(wrote)
        XCTAssertEqual(store.habits[0].log["2026-08-09"], 3)
    }

    func testYesNoWidgetActionsSetExplicitAnswers() {
        var h = Habit(name: "Meditation")
        h.kind = .yesNo
        store.add(h)

        XCTAssertTrue(AnswerHabitLogic.apply(to: store, habitId: h.id,
                                              yes: true, day: "2026-08-09"))
        XCTAssertEqual(store.habits[0].log["2026-08-09"], Habit.Answer.yes)

        XCTAssertTrue(AnswerHabitLogic.apply(to: store, habitId: h.id,
                                              yes: false, day: "2026-08-09"))
        XCTAssertEqual(store.habits[0].log["2026-08-09"], Habit.Answer.no)
    }

    func testResetWidgetActionClearsCheckboxQuantityAndYesNo() {
        var checkbox = Habit(name: "Lesen")
        store.add(checkbox)
        store.toggle(checkbox.id, day: "2026-08-09")
        XCTAssertTrue(ResetHabitLogic.apply(to: store, habitId: checkbox.id,
                                             day: "2026-08-09"))
        XCTAssertNil(store.habits[0].log["2026-08-09"])

        let quantity = Habit(name: "Wasser", recurrence: Recurrence(target: 3))
        store.add(quantity)
        store.increment(quantity.id, day: "2026-08-09")
        XCTAssertTrue(ResetHabitLogic.apply(to: store, habitId: quantity.id,
                                             day: "2026-08-09"))
        XCTAssertNil(store.habits.first(where: { $0.id == quantity.id })?.log["2026-08-09"])

        var yesNo = Habit(name: "Meditation")
        yesNo.kind = .yesNo
        store.add(yesNo)
        XCTAssertTrue(AnswerHabitLogic.apply(to: store, habitId: yesNo.id,
                                              yes: true, day: "2026-08-09"))
        XCTAssertTrue(ResetHabitLogic.apply(to: store, habitId: yesNo.id,
                                             day: "2026-08-09"))
        XCTAssertNil(store.habits.first(where: { $0.id == yesNo.id })?.log["2026-08-09"])
    }

    func testArchivedHabitIsNoOp() {
        let h = Habit(name: "Alt")
        store.add(h)
        store.archive(h.id)
        let wrote = CheckOffLogic.apply(to: store, habitId: h.id, day: "2026-08-09")
        XCTAssertFalse(wrote)
        XCTAssertNil(store.habits[0].log["2026-08-09"])
    }

    func testUnknownHabitIsNoOp() {
        store.add(Habit(name: "Lesen"))
        let before = store.data.updatedAt
        let wrote = CheckOffLogic.apply(to: store, habitId: UUID(), day: "2026-08-09")
        XCTAssertFalse(wrote)
        XCTAssertEqual(store.data.updatedAt, before) // nichts persistiert
    }

    func testApplyPersistsToSharedFile() {
        // Der Intent-Schreibpfad: ein ZWEITER Store auf derselben URL
        // (anderer Prozess simuliert) muss den Check-in sehen.
        let h = Habit(name: "Lesen")
        store.add(h)
        CheckOffLogic.apply(to: store, habitId: h.id, day: "2026-08-09")
        let other = HabitStore(url: url)
        XCTAssertTrue(other.habits[0].isDone("2026-08-09"))
    }
}
