import XCTest
@testable import Haiity

/// Rückgängig-Toast und Wischgesten: die beiden Dinge, bei denen ein Fehler
/// nicht „sieht komisch aus" heißt, sondern „Check-in weg".
final class UndoExactnessTests: XCTestCase {
    private var url: URL!
    private var store: HabitStore!

    override func setUp() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-undo-\(UUID().uuidString).json")
        store = HabitStore(url: url)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: – setValue: der exakte Gegenspieler

    func testSetValueWritesExactCount() {
        let h = Habit(name: "Wasser", recurrence: Recurrence(target: 5))
        store.add(h)
        store.setValue(h.id, day: "2026-08-09", value: 4)
        XCTAssertEqual(store.habits[0].log["2026-08-09"], 4)
    }

    func testSetValueNilRemovesEntry() {
        let h = Habit(name: "Lesen")
        store.add(h)
        store.toggle(h.id, day: "2026-08-09")
        store.setValue(h.id, day: "2026-08-09", value: nil)
        XCTAssertNil(store.habits[0].log["2026-08-09"])
    }

    func testSetValueZeroRemovesInsteadOfMaterializing() {
        // 0-Werte dürfen NIE in der Datei landen — sie überstehen die
        // Habit-Dekodierung nicht und würden beim nächsten Laden zu einer
        // stillen Änderung.
        let h = Habit(name: "Lesen")
        store.add(h)
        store.toggle(h.id, day: "2026-08-09")
        store.setValue(h.id, day: "2026-08-09", value: 0)
        XCTAssertNil(store.habits[0].log["2026-08-09"])
    }

    func testSetValueUnchangedDoesNotPersist() {
        let h = Habit(name: "Lesen")
        store.add(h)
        store.toggle(h.id, day: "2026-08-09")
        let before = store.data.updatedAt
        store.setValue(h.id, day: "2026-08-09", value: 1)
        XCTAssertEqual(store.data.updatedAt, before)
    }

    func testSetValueUnknownHabitIsNoOp() {
        store.add(Habit(name: "Lesen"))
        let before = store.data.updatedAt
        store.setValue(UUID(), day: "2026-08-09", value: 3)
        XCTAssertEqual(store.data.updatedAt, before)
    }

    // MARK: – Die Rücknahme selbst

    func testUndoRestoresCheckboxToUnchecked() {
        let h = Habit(name: "Lesen")
        store.add(h)
        let before = store.value(h.id, day: "2026-08-09")
        store.toggle(h.id, day: "2026-08-09")
        XCTAssertEqual(store.habits[0].log["2026-08-09"], 1)

        store.setValue(h.id, day: "2026-08-09", value: before)
        XCTAssertNil(store.habits[0].log["2026-08-09"])
    }

    func testUndoRestoresCheckboxToCheckedAfterUnchecking() {
        // Die andere Richtung: ein versehentliches Ent-Haken muss sich
        // genauso zurückholen lassen.
        let h = Habit(name: "Lesen")
        store.add(h)
        store.toggle(h.id, day: "2026-08-09")
        let before = store.value(h.id, day: "2026-08-09")
        store.toggle(h.id, day: "2026-08-09")
        XCTAssertNil(store.habits[0].log["2026-08-09"])

        store.setValue(h.id, day: "2026-08-09", value: before)
        XCTAssertEqual(store.habits[0].log["2026-08-09"], 1)
    }

    func testUndoRestoresQuantityToPreviousCountAboveOne() {
        // DER Fall, an dem ein blindes Umschalten scheitern würde: 3 -> 4
        // muss wieder auf 3 landen, nicht auf 0 und nicht auf 1.
        let h = Habit(name: "Wasser", recurrence: Recurrence(target: 6))
        store.add(h)
        for _ in 0..<3 { store.increment(h.id, day: "2026-08-09") }
        let before = store.value(h.id, day: "2026-08-09")
        XCTAssertEqual(before, 3)

        store.increment(h.id, day: "2026-08-09")
        XCTAssertEqual(store.habits[0].log["2026-08-09"], 4)

        store.setValue(h.id, day: "2026-08-09", value: before)
        XCTAssertEqual(store.habits[0].log["2026-08-09"], 3)
    }

    func testUndoOfFirstIncrementRemovesTheDay() {
        let h = Habit(name: "Wasser", recurrence: Recurrence(target: 3))
        store.add(h)
        let before = store.value(h.id, day: "2026-08-09")
        store.increment(h.id, day: "2026-08-09")
        store.setValue(h.id, day: "2026-08-09", value: before)
        XCTAssertNil(store.habits[0].log["2026-08-09"])
    }

    func testUndoOfClearRestoresFullQuantity() {
        // „Rückgängig" auf ein Zurücksetzen: der ganze Zählstand kommt
        // zurück, nicht nur eine 1.
        let h = Habit(name: "Wasser", recurrence: Recurrence(target: 8))
        store.add(h)
        store.setValue(h.id, day: "2026-08-09", value: 7)
        let before = store.value(h.id, day: "2026-08-09")
        store.clear(h.id, day: "2026-08-09")
        store.setValue(h.id, day: "2026-08-09", value: before)
        XCTAssertEqual(store.habits[0].log["2026-08-09"], 7)
    }

    func testUndoSurvivesReload() {
        // Rückgängig schreibt über persist() — ein zweiter Store auf
        // derselben Datei sieht den zurückgenommenen Stand.
        let h = Habit(name: "Lesen")
        store.add(h)
        store.toggle(h.id, day: "2026-08-09")
        store.setValue(h.id, day: "2026-08-09", value: nil)
        XCTAssertFalse(HabitStore(url: url).habits[0].isDone("2026-08-09"))
    }
}

/// Der Zustandsautomat des Toasts — ohne SwiftUI prüfbar.
final class UndoToastStateTests: XCTestCase {
    func testStartsEmpty() {
        let state = UndoToastState()
        XCTAssertNil(state.current)
    }

    func testPresentShowsToast() {
        var state = UndoToastState()
        let id = UUID()
        state.present(habitId: id, day: "2026-08-09", previousValue: nil, message: "Lesen erledigt")
        XCTAssertEqual(state.current?.habitId, id)
        XCTAssertEqual(state.current?.message, "Lesen erledigt")
        XCTAssertNil(state.current?.previousValue ?? nil)
    }

    func testRapidCheckInsDoNotStackAndLatestWins() {
        var state = UndoToastState()
        let a = UUID(), b = UUID()
        state.present(habitId: a, day: "2026-08-09", previousValue: nil, message: "A")
        let first = state.current
        state.present(habitId: b, day: "2026-08-09", previousValue: 2, message: "B")

        // Es gibt IMMER nur einen — und es ist der neuere.
        XCTAssertEqual(state.current?.habitId, b)
        XCTAssertEqual(state.current?.message, "B")
        XCTAssertNotEqual(state.current?.id, first?.id)

        // Und Rückgängig nimmt die Änderung zurück, auf die er zeigt.
        let taken = state.take()
        XCTAssertEqual(taken?.habitId, b)
        XCTAssertEqual(taken?.previousValue, 2)
        XCTAssertNil(state.current)
    }

    func testStaleTimerDoesNotDismissNewerToast() {
        // Der Zeitgeber des ersetzten Toasts läuft womöglich noch — er darf
        // den neueren nicht wegräumen.
        var state = UndoToastState()
        let first = state.present(habitId: UUID(), day: "2026-08-09",
                                  previousValue: nil, message: "A")
        let second = state.present(habitId: UUID(), day: "2026-08-09",
                                   previousValue: nil, message: "B")
        state.expire(first.id)
        XCTAssertEqual(state.current?.id, second.id)

        state.expire(second.id)
        XCTAssertNil(state.current)
    }

    func testGenerationsAreStrictlyIncreasing() {
        var state = UndoToastState()
        var ids: [Int] = []
        for i in 0..<5 {
            ids.append(state.present(habitId: UUID(), day: "2026-08-09",
                                     previousValue: i, message: "\(i)").id)
        }
        XCTAssertEqual(ids, ids.sorted())
        XCTAssertEqual(Set(ids).count, 5)
    }

    func testTakeOnEmptyIsNil() {
        var state = UndoToastState()
        XCTAssertNil(state.take())
    }

    func testClearRemovesToast() {
        var state = UndoToastState()
        state.present(habitId: UUID(), day: "2026-08-09", previousValue: nil, message: "A")
        state.clear()
        XCTAssertNil(state.current)
    }

    func testMessageForCheckbox() {
        XCTAssertEqual(CheckInUndo.message(habitName: "Lesen", value: 1, target: nil),
                       String(localized: "Lesen erledigt"))
        XCTAssertEqual(CheckInUndo.message(habitName: "Lesen", value: 0, target: nil),
                       String(localized: "Lesen zurückgesetzt"))
    }

    func testMessageForQuantityShowsProgressUntilTargetIsMet() {
        XCTAssertEqual(CheckInUndo.message(habitName: "Wasser", value: 2, target: 3),
                       String(localized: "Wasser: 2/3"))
        XCTAssertEqual(CheckInUndo.message(habitName: "Wasser", value: 3, target: 3),
                       String(localized: "Wasser erledigt"))
        // Über dem Ziel bleibt es „erledigt" — kein 4/3.
        XCTAssertEqual(CheckInUndo.message(habitName: "Wasser", value: 4, target: 3),
                       String(localized: "Wasser erledigt"))
    }
}

/// Wischgesten: Belegung, Persistenz, tolerantes Lesen.
final class SwipeActionTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-swipe-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    func testDefaultsAreDoneAndArchive() {
        let store = HabitStore(url: url)
        XCTAssertEqual(store.leadingSwipe, .done)
        XCTAssertEqual(store.trailingSwipe, .archive)
    }

    func testOnlyReversibleActionsAllowFullSwipe() {
        XCTAssertTrue(SwipeAction.done.allowsFullSwipe)
        XCTAssertTrue(SwipeAction.revert.allowsFullSwipe)
        // Archivieren ausdrücklich nicht — ein zu beherzter Wisch soll kein
        // Habit aus der Liste räumen.
        XCTAssertFalse(SwipeAction.archive.allowsFullSwipe)
        XCTAssertFalse(SwipeAction.edit.allowsFullSwipe)
        XCTAssertFalse(SwipeAction.none.allowsFullSwipe)
    }

    func testNoneHasNoSymbolEveryOtherActionDoes() {
        XCTAssertNil(SwipeAction.none.symbol)
        for action in SwipeAction.allCases where action != .none {
            XCTAssertNotNil(action.symbol, "\(action) braucht ein Symbol")
            XCTAssertFalse(action.title.isEmpty)
        }
    }

    func testPersistsAcrossStores() {
        let store = HabitStore(url: url)
        store.leadingSwipe = .edit
        store.trailingSwipe = .revert
        let reopened = HabitStore(url: url)
        XCTAssertEqual(reopened.leadingSwipe, .edit)
        XCTAssertEqual(reopened.trailingSwipe, .revert)
    }

    func testDefaultsStayImplicitInTheFile() throws {
        // Eine unveränderte Installation schreibt exakt dieselbe Datei wie
        // vor den Wischgesten.
        let store = HabitStore(url: url)
        store.add(Habit(name: "Lesen"))
        let json = String(data: try XCTUnwrap(store.exportJSON()), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("leadingSwipe"))
        XCTAssertFalse(json.contains("trailingSwipe"))
    }

    func testNonDefaultsAreWritten() throws {
        let store = HabitStore(url: url)
        store.leadingSwipe = .none
        let json = String(data: try XCTUnwrap(store.exportJSON()), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"leadingSwipe\" : \"none\""))
    }

    func testTolerantDecodeOfUnknownValues() throws {
        // Datei aus einer neueren Version: unbekannte Geste -> Standard,
        // NIE ein Fehler (der ganze Datensatz stünde sonst auf dem Spiel).
        let raw = Data(#"""
        {"version":2,"updatedAt":1,"habits":[],
         "leadingSwipe":"teleport","trailingSwipe":"revert"}
        """#.utf8)
        let data = try JSONDecoder().decode(HabitData.self, from: raw)
        XCTAssertEqual(data.leadingSwipe, .done)
        XCTAssertEqual(data.trailingSwipe, .revert)
    }

    func testMissingKeysFallBackToDefaults() throws {
        let raw = Data(#"{"version":2,"updatedAt":1,"habits":[]}"#.utf8)
        let data = try JSONDecoder().decode(HabitData.self, from: raw)
        XCTAssertEqual(data.leadingSwipe, .defaultLeading)
        XCTAssertEqual(data.trailingSwipe, .defaultTrailing)
    }

    func testSwipeConfigIsNoVersionBump() {
        // Die Konvention des Projekts: additive Felder, KEIN Sprung auf 3 —
        // sonst sperrt die Datei den v2-Build von gestern aus.
        let store = HabitStore(url: url)
        store.trailingSwipe = .edit
        XCTAssertEqual(store.data.version, 2)
        XCTAssertEqual(HabitData.currentVersion, 2)
    }

    func testMergeTakesSwipeConfigFromNewerRemote() {
        let store = HabitStore(url: url)
        var remote = HabitData.empty
        remote.updatedAt = Date().timeIntervalSince1970 + 1000
        remote.leadingSwipe = .archive
        remote.trailingSwipe = .none
        store.merge(remote: remote)
        XCTAssertEqual(store.leadingSwipe, .archive)
        XCTAssertEqual(store.trailingSwipe, .none)
    }

    func testMergeKeepsLocalSwipeConfigWhenRemoteIsOlder() {
        let store = HabitStore(url: url)
        store.leadingSwipe = .edit
        var remote = HabitData.empty
        remote.updatedAt = 1
        remote.leadingSwipe = .archive
        store.merge(remote: remote)
        XCTAssertEqual(store.leadingSwipe, .edit)
    }
}
