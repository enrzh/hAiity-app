import XCTest
@testable import Haiity

final class AutoResolveTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    func testAutoResolveChoiceRoundTripsAndDefaultsToDisabled() throws {
        let original = Habit(name: "Lesen")
        XCTAssertNil(original.autoResolveChoice)

        var configured = original
        configured.autoResolveChoice = .notDone
        let decoded = try JSONDecoder().decode(
            Habit.self,
            from: JSONEncoder().encode(configured))

        XCTAssertEqual(decoded.autoResolveChoice, .notDone)
    }

    func testAutoResolveWaitsUntilEndOfDayDespiteConfiguredTime() {
        var habit = Habit(name: "Lesen", timeMinutes: 18 * 60)
        habit.createdAt = "2026-08-14"

        XCTAssertEqual(
            ReminderOccurrenceEngine.expiredOccurrences(
                for: habit,
                now: date("2026-08-14", minutes: 17 * 60 + 59),
                calendar: calendar),
            [])
        XCTAssertEqual(
            ReminderOccurrenceEngine.expiredOccurrences(
                for: habit,
                now: date("2026-08-14", minutes: 18 * 60),
                calendar: calendar),
            [])
        XCTAssertEqual(
            ReminderOccurrenceEngine.expiredOccurrences(
                for: habit,
                now: date("2026-08-14", minutes: 23 * 60 + 59),
                calendar: calendar),
            [])
        XCTAssertEqual(
            ReminderOccurrenceEngine.expiredOccurrences(
                for: habit,
                now: date("2026-08-15", minutes: 0),
                calendar: calendar),
            ["2026-08-14"])
    }

    func testReminderAutoResolveWaitsUntilEndOfDayDespiteConfiguredTime() {
        var reminder = Habit(name: "Tabletten", itemType: .reminder,
                             timeMinutes: 9 * 60)
        reminder.createdAt = "2026-08-14"

        XCTAssertFalse(ReminderOccurrenceEngine.expiredOccurrences(
            for: reminder,
            now: date("2026-08-14", minutes: 18 * 60),
            calendar: calendar).contains("2026-08-14"))
        XCTAssertTrue(ReminderOccurrenceEngine.expiredOccurrences(
            for: reminder,
            now: date("2026-08-15", minutes: 0),
            calendar: calendar).contains("2026-08-14"))
    }

    func testCheckboxCanBeAutoResolvedAsNotDoneAndRunsOnlyOnce() {
        var habit = Habit(name: "Lesen", timeMinutes: 9 * 60)
        habit.createdAt = "2026-08-14"
        habit.autoResolveChoice = .notDone
        let store = makeStore(habit)
        let now = date("2026-08-15", minutes: 12 * 60)

        XCTAssertTrue(store.resolveExpiredOccurrences(now: now))
        XCTAssertEqual(store.habits[0].missedDays, ["2026-08-14"])
        XCTAssertFalse(store.resolveExpiredOccurrences(now: now))
    }

    func testYesNoCanBeAutoResolvedAsNo() {
        var habit = Habit(name: "Zucker", timeMinutes: 9 * 60, kind: .yesNo)
        habit.createdAt = "2026-08-14"
        habit.autoResolveChoice = .no
        let store = makeStore(habit)

        XCTAssertTrue(store.resolveExpiredOccurrences(
            now: date("2026-08-15", minutes: 12 * 60)))
        XCTAssertEqual(store.habits[0].log["2026-08-14"], Habit.Answer.no)
    }

    func testReminderCanBeAutoResolvedAsDone() {
        var reminder = Habit(name: "Tabletten", itemType: .reminder, timeMinutes: 9 * 60)
        reminder.createdAt = "2026-08-14"
        reminder.autoResolveChoice = .done
        let store = makeStore(reminder)

        XCTAssertTrue(store.resolveExpiredOccurrences(
            now: date("2026-08-15", minutes: 12 * 60)))
        XCTAssertEqual(store.habits[0].log["2026-08-14"], 1)
        XCTAssertNil(store.habits[0].missedDays.first)
    }

    func testReminderAlwaysUsesDoneChoicesEvenWithLegacyYesNoMarker() {
        var reminder = Habit(name: "Tabletten", itemType: .reminder, kind: .yesNo)
        reminder.autoResolveChoice = .yes

        XCTAssertEqual(HabitAutoResolveChoice.choices(for: reminder.kind,
                                                      itemType: reminder.itemType),
                       [.done, .notDone])
        XCTAssertEqual(HabitAutoResolveChoice.defaultChoice(for: reminder.kind,
                                                             itemType: reminder.itemType),
                       .notDone)
    }

    func testQuantityNotDoneDoesNotCreateZero() {
        var habit = Habit(name: "Wasser", recurrence: Recurrence(target: 3))
        habit.createdAt = "2026-08-14"
        habit.autoResolveChoice = .notDone
        let store = makeStore(habit)

        XCTAssertTrue(store.resolveExpiredOccurrences(
            now: date("2026-08-15", minutes: 12 * 60)))
        XCTAssertNil(store.habits[0].log["2026-08-14"])
        XCTAssertEqual(store.habits[0].missedDays, ["2026-08-14"])
    }

    func testAllDayCheckboxStaysOpenUntilTheNextLocalMidnight() {
        var habit = Habit(name: "Lesen")
        habit.createdAt = "2026-08-14"
        habit.autoResolveChoice = .notDone
        let store = makeStore(habit)

        XCTAssertFalse(store.resolveExpiredOccurrences(
            now: date("2026-08-14", minutes: 23 * 60 + 59)))
        XCTAssertTrue(store.habits[0].missedDays.isEmpty)

        XCTAssertTrue(store.resolveExpiredOccurrences(
            now: date("2026-08-15", minutes: 0)))
        XCTAssertEqual(store.habits[0].missedDays, ["2026-08-14"])
    }

    func testAllDayQuantityStaysOpenUntilTheNextLocalMidnight() {
        var habit = Habit(name: "Wasser", recurrence: Recurrence(target: 3))
        habit.createdAt = "2026-08-14"
        habit.autoResolveChoice = .done
        let store = makeStore(habit)

        XCTAssertFalse(store.resolveExpiredOccurrences(
            now: date("2026-08-14", minutes: 12 * 60)))
        XCTAssertNil(store.habits[0].log["2026-08-14"])

        XCTAssertTrue(store.resolveExpiredOccurrences(
            now: date("2026-08-15", minutes: 0)))
        XCTAssertEqual(store.habits[0].log["2026-08-14"], 3)
    }

    func testAllDayYesNoStaysOpenUntilTheNextLocalMidnight() {
        var habit = Habit(name: "Zucker", kind: .yesNo)
        habit.createdAt = "2026-08-14"
        habit.autoResolveChoice = .no
        let store = makeStore(habit)

        XCTAssertFalse(store.resolveExpiredOccurrences(
            now: date("2026-08-14", minutes: 12 * 60)))
        XCTAssertNil(store.habits[0].log["2026-08-14"])

        XCTAssertTrue(store.resolveExpiredOccurrences(
            now: date("2026-08-15", minutes: 0)))
        XCTAssertEqual(store.habits[0].log["2026-08-14"], Habit.Answer.no)
    }

    func testAllDayReminderStaysOpenUntilTheNextLocalMidnight() {
        var reminder = Habit(name: "Tabletten", itemType: .reminder)
        reminder.createdAt = "2026-08-14"
        reminder.autoResolveChoice = .done
        let store = makeStore(reminder)

        XCTAssertFalse(store.resolveExpiredOccurrences(
            now: date("2026-08-14", minutes: 12 * 60)))
        XCTAssertNil(store.habits[0].log["2026-08-14"])

        XCTAssertTrue(store.resolveExpiredOccurrences(
            now: date("2026-08-15", minutes: 0)))
        XCTAssertEqual(store.habits[0].log["2026-08-14"], 1)
    }

    func testOneTimeReminderRemainsCompletableAfterAutoResolveMarksItMissed() {
        var reminder = Habit(name: "Arzt", itemType: .reminder, timeMinutes: 9 * 60,
                             recurrence: Recurrence(frequency: .once, start: "2026-08-14"))
        reminder.createdAt = "2026-08-14"
        reminder.autoResolveChoice = .notDone
        let store = makeStore(reminder)
        let now = date("2026-08-15", minutes: 12 * 60)

        XCTAssertTrue(store.resolveExpiredOccurrences(now: now))
        XCTAssertEqual(store.habits[0].missedDays, ["2026-08-14"])
        XCTAssertNil(store.habits[0].log["2026-08-14"])

        let state = ReminderOccurrenceEngine.state(
            for: store.habits[0], now: now, calendar: calendar)
        XCTAssertEqual(state.actionable?.day, "2026-08-14")

        store.setReminderCompletion(reminder.id, day: "2026-08-14",
                                    completed: true, nextCursor: nil)
        XCTAssertEqual(store.habits[0].log["2026-08-14"], 1)
        XCTAssertTrue(store.habits[0].missedDays.isEmpty)
    }

    private func makeStore(_ habit: Habit) -> HabitStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-auto-resolve-\(UUID().uuidString).json")
        let store = HabitStore(url: url)
        // Match the Berlin calendar used by date helpers so Cloud workers
        // (non-Berlin device TZ) resolve midnight boundaries the same way.
        store.defaultTimeZoneIdentifier = "Europe/Berlin"
        store.add(habit)
        return store
    }

    private func date(_ day: String, minutes: Int) -> Date {
        let start = DayKey.date(from: day, calendar: calendar)!
        return calendar.date(byAdding: .minute, value: minutes, to: start)!
    }
}
