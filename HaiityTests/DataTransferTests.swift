import XCTest
@testable import Haiity

@MainActor
final class DataTransferTests: XCTestCase {
    func testSharedImportBoundaryMergesFreeDataAndRejectsOverLimitWithoutChangingIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-transfer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HabitStore(url: directory.appendingPathComponent("data.json"))
        let existing = Habit(name: "Existing")
        store.add(existing)
        let imported = Habit(name: "Imported")
        let payload = HabitData(version: HabitData.currentVersion, updatedAt: 1,
                                summaryMinutes: nil, habits: [imported])
        try DataTransferSection.importJSON(JSONEncoder().encode(payload), into: store, unlocked: false)
        XCTAssertEqual(Set(store.habits.map(\.id)), Set([existing.id, imported.id]))

        let saved = try XCTUnwrap(store.exportJSON())
        let extra = [Habit(name: "Third"), Habit(name: "Fourth")]
        let overLimit = HabitData(version: HabitData.currentVersion, updatedAt: 2,
                                  summaryMinutes: nil, habits: extra)
        XCTAssertThrowsError(try DataTransferSection.importJSON(JSONEncoder().encode(overLimit),
                                                               into: store, unlocked: false))
        XCTAssertEqual(store.exportJSON(), saved)
        try DataTransferSection.importJSON(JSONEncoder().encode(overLimit), into: store, unlocked: true)
        XCTAssertEqual(store.habits.count, 4)
    }

    func testSharedImportBoundaryRejectsMalformedJSONAndKeepsExistingEntries() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-transfer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HabitStore(url: directory.appendingPathComponent("data.json"))
        store.add(Habit(name: "Keep me"))
        let saved = try XCTUnwrap(store.exportJSON())
        XCTAssertThrowsError(try DataTransferSection.importJSON(Data("{invalid".utf8),
                                                               into: store, unlocked: false))
        XCTAssertEqual(store.exportJSON(), saved)
    }
}
