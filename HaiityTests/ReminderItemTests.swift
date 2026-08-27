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
        XCTAssertTrue(source.contains(".contextMenu {"),
                      "the native menu must attach to the row surface")
        XCTAssertTrue(source.contains("Label(String(localized: \"Bearbeiten\")"))
        XCTAssertTrue(source.contains("Button(action: onEdit)"),
                      "editing must remain available from the reminder menu")
        XCTAssertFalse(source.contains("GraphContextMenu("),
                       "the transparent overlay must not intercept reminder taps")
    }

    func testReminderContextMenuKeepsTheStableRowSurface() throws {
        let source = try source("Haiity/Views/ReminderRow.swift")
        XCTAssertTrue(source.contains("static let rowHeight: CGFloat = 64"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, minHeight: Self.rowHeight)"))
        XCTAssertTrue(source.contains(".contextMenu {"),
                      "the native preview must be built from the tappable row")
    }

    func testReminderUsesTheCardHeightRevealWithFixedDoneAndRevertActions() throws {
        let row = try source("Haiity/Views/ReminderRow.swift")
        let source = try source("Haiity/Views/ContentView.swift")
        let reminder = try XCTUnwrap(source.range(of: "case .reminderRow:"))
        let habit = try XCTUnwrap(source.range(of: "case .habitCard:"))
        let branch = source[reminder.lowerBound..<habit.lowerBound]

        XCTAssertFalse(row.contains("SwipeRevealPan("),
                       "compact reminders should use the native row swipe interaction")
        XCTAssertTrue(row.contains("leadingSwipe"))
        XCTAssertTrue(row.contains("trailingSwipe"))
        XCTAssertTrue(row.contains(".swipeActions(edge: .leading"))
        XCTAssertTrue(row.contains(".swipeActions(edge: .trailing"))
        XCTAssertTrue(row.contains("lhs.leadingSwipe == rhs.leadingSwipe"),
                      "changing saved reveal actions must update an equatable row")
        XCTAssertTrue(branch.contains("let reveal = revealActions(for: habit)"))
        XCTAssertTrue(branch.contains("leadingSwipe: reveal.leading"))
        XCTAssertTrue(branch.contains("trailingSwipe: reveal.trailing"))
    }

    func testReminderPreviewAndRevealShareTheStableRowHeight() throws {
        let row = try source("Haiity/Views/ReminderRow.swift")

        XCTAssertTrue(row.contains("static let rowHeight: CGFloat = 64"))
        XCTAssertTrue(row.contains(".frame(maxWidth: .infinity, minHeight: Self.rowHeight)"))
        XCTAssertTrue(row.contains(".swipeActions(edge: .leading"),
                      "the native leading actions must stay attached to the row")
        XCTAssertTrue(row.contains(".swipeActions(edge: .trailing"),
                      "the native trailing actions must stay attached to the row")
    }

    func testReminderDoesNotInstallAnInterceptingSwipeOverlay() throws {
        let row = try source("Haiity/Views/ReminderRow.swift")
        XCTAssertFalse(row.contains("SwipeRevealPan("),
                       "reminders should not install a second gesture recognizer")
        XCTAssertFalse(row.contains("revealOffset"),
                       "reminders should not render an offset transparent overlay")
        XCTAssertTrue(row.contains(".contextMenu {"),
                      "the row keeps its native long-press menu")
    }

    func testCombinedListBranchesByItemTypeAfterApplyingTheSharedFilter() throws {
        let source = try source("Haiity/Views/ContentView.swift")
        XCTAssertTrue(source.contains("ItemPresentation.forItem(habit)"))
        XCTAssertTrue(source.contains("ReminderRow("))
        XCTAssertTrue(source.contains("let active = listFilteredHabits"))
    }

    func testEditorOffersAndPersistsItemType() throws {
        let source = try editorSource()

        XCTAssertTrue(source.contains("@State private var itemType: HabitItemType = .reminder"))
        XCTAssertTrue(source.contains("selection: $itemType"))
        XCTAssertTrue(source.contains(".tag(HabitItemType.habit)"))
        XCTAssertTrue(source.contains(".tag(HabitItemType.reminder)"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"item-type-picker\")"))
        XCTAssertTrue(source.contains("itemType = habit.itemType"))
        XCTAssertTrue(source.contains("habit.itemType = itemType"))
    }

    func testEditorOffersAndPersistsCalendarOptOut() throws {
        let source = try editorSource()

        XCTAssertTrue(source.contains("Toggle(isOn: calendarSyncBinding)"),
                      "the calendar switch must use the entitlement-aware binding")
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"habit-calendar-toggle\")"))
        XCTAssertTrue(source.contains("calendarSyncEnabled = habit.calendarSyncEnabled"))
        XCTAssertTrue(source.contains("habit.calendarSyncEnabled = unlocked && calendarSyncEnabled"),
                      "saving must not restore calendar sync after Pro expiry")
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
        XCTAssertTrue(editor.contains("itemType == .reminder && draft.frequency != .once"))
    }

    func testReminderLongPressMenuIncludesRevert() throws {
        let source = try source("Haiity/Views/ReminderRow.swift")
        XCTAssertTrue(source.contains("Rückgängig"))
        XCTAssertTrue(source.contains("onRevert"))
        XCTAssertTrue(source.contains("Löschen"))
        XCTAssertTrue(source.contains("onDelete"))
    }

    func testHabitEditorOffersDeleteForExistingItems() throws {
        let editor = try editorSource()
        let card = try source("Haiity/Views/HabitCard.swift")

        XCTAssertTrue(editor.contains("delete-habit"))
        XCTAssertTrue(editor.contains("store.remove(habit.id)"))
        XCTAssertTrue(card.contains("handler: onDelete"))
    }

    func testEditorKeepsTheSharedHabitSettings() throws {
        let source = try editorSource()

        for section in ["recurrenceSection", "durationSection", "kindSection", "colorSection"] {
            XCTAssertTrue(source.contains(section), "missing shared editor section: \(section)")
        }
    }

    func testHabitAndReminderEditorOfferConfirmedDelete() throws {
        let source = try editorSource()
        XCTAssertTrue(source.contains("showingDeleteConfirmation"))
        XCTAssertTrue(source.contains("delete-habit"))
        XCTAssertTrue(source.contains("store.remove(habit.id)"))
        XCTAssertTrue(source.contains("role: .destructive"))
    }

    func testReminderModeHidesHabitKindControls() throws {
        let source = try editorSource()

        XCTAssertTrue(source.contains("if itemType == .habit { kindSection.settingsListRow() }"),
                      "the habit-only kind controls must be conditionally mounted")
        XCTAssertTrue(source.contains("itemType == .habit ? Habit.resolvedKind"),
                      "saving a reminder must not persist a habit kind")
        XCTAssertTrue(source.contains(": .checkbox"),
                      "reminders must use the internal checkbox representation")
    }

    func testOnlyNewTrackedHabitsUseTheFreeLimit() throws {
        let source = try editorSource()

        XCTAssertTrue(source.contains("ProGate.maySaveTrackedHabit"))
        XCTAssertTrue(source.contains("existingIsTracked: existing?.isTrackedHabit == true"))
        XCTAssertTrue(source.contains("targetIsTracked: itemType == .habit"))
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
