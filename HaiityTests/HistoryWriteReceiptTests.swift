import XCTest
@testable import Haiity

@MainActor
final class HistoryWriteReceiptTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testRejectedHistoryWriteDoesNotOfferUndoOrOverwriteExternalValue() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("history-receipt-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let day = DayKey.today(calendar: calendar)
        var habit = Habit(name: "Water", recurrence: Recurrence(target: 20), notificationMode: .off)
        habit.createdAt = day
        habit.timeZoneIdentifier = "UTC"
        habit.log[day] = 2
        let store = HabitStore(url: url, loadFromDisk: false)
        store.add(habit)
        let external = HabitStore(url: url)
        external.setValue(habit.id, day: day, value: 11)
        XCTAssertNil(store.setValues(habit.id, values: [(day, 3)]),
                     "A rejected write must not return an Undo receipt")
        XCTAssertNotNil(store.lastWriteError)
        XCTAssertEqual(store.value(habit.id, day: day), 11)
        XCTAssertEqual(HabitStore(url: url).value(habit.id, day: day), 11)
    }

    func testRejectedHistoryUndoUsesDurableReceiptAndPreservesExternalValue() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("history-restore-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let day = DayKey.today(calendar: calendar)
        var displayed = Habit(name: "Water", recurrence: Recurrence(target: 20), notificationMode: .off)
        displayed.createdAt = day
        displayed.timeZoneIdentifier = "UTC"
        displayed.log[day] = 2
        let store = HabitStore(url: url, loadFromDisk: false)
        store.add(displayed)
        store.setValue(displayed.id, day: day, value: 7)
        let receipt = try XCTUnwrap(store.setValues(displayed.id, values: [(day, 3)]))
        XCTAssertEqual(receipt.count, 1)
        XCTAssertEqual(receipt.first?.day, day)
        XCTAssertEqual(receipt.first?.previousValue, 7,
                       "Undo must use the writer's receipt, not the displayed value of 2")
        XCTAssertEqual(HabitStore(url: url).value(displayed.id, day: day), 3)
        let external = HabitStore(url: url)
        external.setValue(displayed.id, day: day, value: 11)
        XCTAssertNil(store.setValues(displayed.id, values: receipt.map { ($0.day, $0.previousValue) }))
        XCTAssertNotNil(store.lastWriteError)
        XCTAssertEqual(store.value(displayed.id, day: day), 11)
        XCTAssertEqual(HabitStore(url: url).value(displayed.id, day: day), 11)
    }
}
