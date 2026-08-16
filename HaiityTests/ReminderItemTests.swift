import XCTest
@testable import Haiity

final class ReminderItemTests: XCTestCase {
    func testPresentationPolicyUsesCompactRowsOnlyForReminders() {
        XCTAssertEqual(ItemPresentation.forItem(Habit(name: "Lesen")), .habitCard)
        XCTAssertEqual(ItemPresentation.forItem(Habit(name: "Tabletten", itemType: .reminder)),
                       .reminderRow)
    }

    func testReminderRowHasNoGraphOrSessionFeatures() throws {
        let source = try source("Haiity/Views/ReminderRow.swift")
        for forbidden in ["ContributionGrid", "Backfill", "HabitSessionManager", "ShareLink"] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
        XCTAssertTrue(source.contains("reminder-check-"))
    }

    func testReminderUsesFullWidthTappableContextPreview() throws {
        let source = try source("Haiity/Views/ReminderRow.swift")
        XCTAssertTrue(source.contains("GraphContextMenu("))
        XCTAssertTrue(source.contains("previewWidth:"))
        XCTAssertTrue(source.contains("commit: onEdit"))
        XCTAssertFalse(source.contains(".contextMenu {"))
    }

    func testReminderHasFixedDoneAndRevertSwipeActions() throws {
        let source = try source("Haiity/Views/ContentView.swift")
        let reminder = try XCTUnwrap(source.range(of: "case .reminderRow:"))
        let habit = try XCTUnwrap(source.range(of: "case .habitCard:"))
        let branch = source[reminder.lowerBound..<habit.lowerBound]
        XCTAssertTrue(branch.contains(".swipeActions(edge: .leading, allowsFullSwipe: true)"))
        XCTAssertTrue(branch.contains("requestReminderCompletion(habit)"))
        XCTAssertTrue(branch.contains(".swipeActions(edge: .trailing, allowsFullSwipe: true)"))
        XCTAssertTrue(branch.contains("revertReminder(habit)"))
    }

    func testCombinedListBranchesByItemTypeWithoutFilteringReminders() throws {
        let source = try source("Haiity/Views/ContentView.swift")
        XCTAssertTrue(source.contains("ItemPresentation.forItem(habit)"))
        XCTAssertTrue(source.contains("ReminderRow("))
        XCTAssertTrue(source.contains("let active = store.activeHabits"))
    }

    func testEditorOffersAndPersistsItemType() throws {
        let source = try editorSource()

        XCTAssertTrue(source.contains("@State private var itemType: HabitItemType = .habit"))
        XCTAssertTrue(source.contains("selection: $itemType"))
        XCTAssertTrue(source.contains(".tag(HabitItemType.habit)"))
        XCTAssertTrue(source.contains(".tag(HabitItemType.reminder)"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"item-type-picker\")"))
        XCTAssertTrue(source.contains("itemType = habit.itemType"))
        XCTAssertTrue(source.contains("habit.itemType = itemType"))
    }

    func testEditorOffersAndPersistsCalendarOptOut() throws {
        let source = try editorSource()

        XCTAssertTrue(source.contains("Toggle(String(localized: \"Im Kalender\"), isOn: $calendarSyncEnabled)"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"habit-calendar-toggle\")"))
        XCTAssertTrue(source.contains("calendarSyncEnabled = habit.calendarSyncEnabled"))
        XCTAssertTrue(source.contains("habit.calendarSyncEnabled = calendarSyncEnabled"))
    }

    func testReminderOccurrenceControlsArePresentAndRecurrenceCopyIsRemoved() throws {
        let editor = try editorSource()
        let row = try source("Haiity/Views/ReminderRow.swift")
        let content = try source("Haiity/Views/ContentView.swift")

        XCTAssertTrue(editor.contains("repeats-while-incomplete-toggle"))
        XCTAssertTrue(editor.contains("repeatsWhileIncomplete = habit.repeatsWhileIncomplete"))
        XCTAssertTrue(editor.contains(
            "habit.repeatsWhileIncomplete = itemType == .reminder ? repeatsWhileIncomplete : true"
        ))
        XCTAssertTrue(content.contains("reminder-early-completion-confirm"))
        XCTAssertFalse(row.contains("RecurrenceText.summary"))
    }

    func testEditorKeepsTheSharedHabitSettings() throws {
        let source = try editorSource()

        for section in ["recurrenceSection", "durationSection", "kindSection", "colorSection"] {
            XCTAssertTrue(source.contains(section), "missing shared editor section: \(section)")
        }
    }

    func testOnlyNewTrackedHabitsUseTheFreeLimit() throws {
        let source = try editorSource()

        XCTAssertTrue(source.contains("existing == nil && itemType == .habit"))
        XCTAssertTrue(source.contains("store.activeTrackedHabits.count"))
        XCTAssertTrue(source.contains("paywall = .habits"))
    }

    private func editorSource() throws -> String {
        try source("Haiity/Views/EditHabitSheet.swift")
    }

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative))
    }
}
