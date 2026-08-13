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
        let h = Habit(name: "Lesen")
        XCTAssertEqual(CheckInUndo.message(habit: h, value: 1, day: "2026-08-09",
                                           today: "2026-08-09"),
                       String(localized: "Lesen erledigt"))
        XCTAssertEqual(CheckInUndo.message(habit: h, value: 0, day: "2026-08-09",
                                           today: "2026-08-09"),
                       String(localized: "Lesen zurückgesetzt"))
    }

    func testMessageForQuantityShowsProgressUntilTargetIsMet() {
        let h = Habit(name: "Wasser", recurrence: Recurrence(target: 3))
        XCTAssertEqual(CheckInUndo.message(habit: h, value: 2, day: "2026-08-09",
                                           today: "2026-08-09"),
                       String(localized: "Wasser: 2/3"))
        XCTAssertEqual(CheckInUndo.message(habit: h, value: 3, day: "2026-08-09",
                                           today: "2026-08-09"),
                       String(localized: "Wasser erledigt"))
        // Über dem Ziel bleibt es „erledigt" — kein 4/3.
        XCTAssertEqual(CheckInUndo.message(habit: h, value: 4, day: "2026-08-09",
                                           today: "2026-08-09"),
                       String(localized: "Wasser erledigt"))
    }

    /// Ein NACHGETRAGENER Tag muss sein Datum mitbringen. Ohne das steht bei
    /// „Lesen erledigt" nicht, WELCHER Tag gerade geschrieben wurde — und
    /// „Rückgängig" nimmt dann etwas zurück, das man nicht gesehen hat.
    func testMessageNamesTheDayWhenItIsNotToday() {
        let h = Habit(name: "Lesen")
        let message = CheckInUndo.message(habit: h, value: 1, day: "2026-08-03",
                                          today: "2026-08-09")
        XCTAssertNotEqual(message, String(localized: "Lesen erledigt"))
        XCTAssertTrue(message.contains(Backfill.dayText("2026-08-03")))
        XCTAssertTrue(message.contains("Lesen"))
    }
}

final class SwipeActionsTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-legacy-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    func testDefaultActionsAreTypeAware() {
        let prefs = ViewPreferences()

        XCTAssertNil(prefs.effectiveSwipeActions(for: Habit(name: "Lesen")).leading)
        XCTAssertNil(prefs.effectiveSwipeActions(for: Habit(name: "Lesen")).trailing)

        let quantity = Habit(name: "Wasser", recurrence: Recurrence(target: 3))
        XCTAssertNil(prefs.effectiveSwipeActions(for: quantity).leading)

        let yesNo = Habit(name: "Kein Zucker", kind: .yesNo)
        XCTAssertNil(prefs.effectiveSwipeActions(for: yesNo).leading)
        XCTAssertNil(prefs.effectiveSwipeActions(for: yesNo).trailing)
    }

    func testContentViewAlwaysEmitsCoreSwipeActionsBeforeOptionalExtras() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("swipeButton(primarySwipe(for: habit), habit: habit)"))
        XCTAssertTrue(source.contains("swipeButton(secondarySwipe(for: habit), habit: habit)"))
        XCTAssertTrue(source.contains(".frame(maxHeight: .infinity)"))
    }

    func testDisabledActionsAreNotExposed() {
        var prefs = ViewPreferences()
        prefs.swipeActions.enabled = false

        XCTAssertEqual(prefs.effectiveSwipeActions(for: Habit(name: "Lesen")), .disabled)
    }

    func testHabitOverrideWinsOverGlobalSides() {
        var habit = Habit(name: "Lesen")
        habit.swipeActions = SwipeActionsOverride(leading: .archive, trailing: .some(.none))

        let effective = ViewPreferences().effectiveSwipeActions(for: habit)
        XCTAssertEqual(effective.leading?.operation, .archive)
        XCTAssertNil(effective.trailing)
    }

    func testArchiveIsNeverEligibleForFullSwipe() {
        let archive = EffectiveSwipeAction(operation: .archive)

        XCTAssertFalse(archive.allowsFullSwipe)
    }

    func testCurrentSwipeConfigurationRoundTrips() throws {
        var habit = Habit(name: "Lesen")
        habit.swipeActions = SwipeActionsOverride(leading: .archive, trailing: .some(.none))
        let data = HabitData(version: 2, updatedAt: 1, summaryMinutes: nil, habits: [habit],
                             viewPreferences: ViewPreferences(
                                swipeActions: SwipeActionsPreferences(enabled: false,
                                                                      leading: .archive,
                                                                      trailing: .primary)))

        let decoded = try JSONDecoder().decode(HabitData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(decoded.viewPreferences.swipeActions,
                       SwipeActionsPreferences(enabled: false, leading: .archive, trailing: .primary))
        XCTAssertEqual(decoded.habits[0].swipeActions, habit.swipeActions)
    }

    func testLegacyFilesWithRootSwipeKeysDecodeToDefaults() throws {
        let raw = Data(#"""
        {"version":2,"updatedAt":1,
         "habits":[{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Lesen",
                    "emoji":"📚","createdAt":"2026-01-05","log":{"2026-08-01":1}}],
         "leadingSwipe":"teleport","trailingSwipe":"revert"}
        """#.utf8)
        let data = try JSONDecoder().decode(HabitData.self, from: raw)
        // Frühe Builds legten die Schlüssel an der Wurzel ab. Auch kaputte
        // Werte dürfen das neue Format nicht beeinflussen.
        XCTAssertEqual(data.habits.count, 1)
        XCTAssertEqual(data.habits.first?.name, "Lesen")
        XCTAssertEqual(data.habits.first?.log["2026-08-01"], 1)
        XCTAssertEqual(data.viewPreferences.swipeActions, SwipeActionsPreferences())
    }

    func testLegacyRootSwipeKeysMigrateRecognizedValues() throws {
        let raw = Data(#"""
        {"version":2,"updatedAt":1,"habits":[],
         "leadingSwipe":"done","trailingSwipe":"archive"}
        """#.utf8)

        let data = try JSONDecoder().decode(HabitData.self, from: raw)

        XCTAssertEqual(data.viewPreferences.swipeActions,
                       SwipeActionsPreferences(leading: .primary, trailing: .archive))
    }

    func testAddingSwipeConfigurationIsNoVersionBump() throws {
        // Konvention des Projekts: der v2-Build von gestern muss die Datei
        // weiter lesen können. Ein Sprung auf 3 würde ihn aussperren.
        let store = HabitStore(url: url)
        store.add(Habit(name: "Lesen"))
        XCTAssertEqual(store.data.version, 2)
        XCTAssertEqual(HabitData.currentVersion, 2)
    }

    func testLegacyFileRoundTripWritesCurrentSwipeConfiguration() throws {
        try Data(#"""
        {"version":2,"updatedAt":1,"habits":[],"palette":"violet",
         "leadingSwipe":"edit","trailingSwipe":"none"}
        """#.utf8).write(to: url)
        let store = HabitStore(url: url)
        store.add(Habit(name: "Sport"))
        let reopened = HabitStore(url: url)
        XCTAssertEqual(reopened.palette, .builtin(.violet))
        XCTAssertEqual(reopened.habits.map(\.name), ["Sport"])
        XCTAssertTrue(reopened.data.viewPreferences.swipeActions.enabled)
        XCTAssertEqual(reopened.data.viewPreferences.swipeActions.leading, .primary)
        XCTAssertEqual(reopened.data.viewPreferences.swipeActions.trailing, .secondary)
    }
}
