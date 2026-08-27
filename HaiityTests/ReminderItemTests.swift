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

    func testReminderPreviewConstrainsItsLayoutBeforeApplyingTheSurface() throws {
        let source = try source("Haiity/Views/ReminderRow.swift")
        let start = try XCTUnwrap(source.range(of: "private var reminderPreview: some View"))
        let end = try XCTUnwrap(source.range(of: "private var menuActions:",
                                             range: start.upperBound..<source.endIndex))
        let preview = source[start.lowerBound..<end.lowerBound]
        let frame = try XCTUnwrap(preview.range(of: ".frame(width: previewWidth"))
        let surface = try XCTUnwrap(preview.range(of: ".appSurface()"))
        XCTAssertLessThan(frame.lowerBound, surface.lowerBound,
                          "the context preview width must be applied before appSurface")
    }

    func testReminderUsesTheCardHeightRevealWithFixedDoneAndRevertActions() throws {
        let row = try source("Haiity/Views/ReminderRow.swift")
        let source = try source("Haiity/Views/ContentView.swift")
        let reminder = try XCTUnwrap(source.range(of: "case .reminderRow:"))
        let habit = try XCTUnwrap(source.range(of: "case .habitCard:"))
        let branch = source[reminder.lowerBound..<habit.lowerBound]

        XCTAssertTrue(row.contains("SwipeRevealPan("),
                      "reminders must use the same card-height reveal bridge as habits")
        XCTAssertTrue(row.contains("leadingSwipe"))
        XCTAssertTrue(row.contains("trailingSwipe"))
        XCTAssertTrue(row.contains("lhs.leadingSwipe == rhs.leadingSwipe"),
                      "changing saved reveal actions must update an equatable row")
        XCTAssertTrue(branch.contains("let reveal = revealActions(for: habit)"))
        XCTAssertTrue(branch.contains("leadingSwipe: reveal.leading"))
        XCTAssertTrue(branch.contains("trailingSwipe: reveal.trailing"))
        XCTAssertFalse(branch.contains(".swipeActions(edge:"),
                       "the system row swipe buttons are shorter than the reminder card")
    }

    func testReminderPreviewAndRevealShareTheStableRowHeight() throws {
        let row = try source("Haiity/Views/ReminderRow.swift")

        XCTAssertTrue(row.contains("static let rowHeight: CGFloat = 64"))
        XCTAssertTrue(row.contains("previewHeight: Self.rowHeight"),
                      "the enlarged reminder preview must use the row's measured contract")
        XCTAssertTrue(row.contains(".frame(maxWidth: .infinity, minHeight: Self.rowHeight)"))
        XCTAssertTrue(row.contains(".frame(minHeight: Self.rowHeight)"),
                      "the preview and source row must not drift apart vertically")
    }

    func testReminderDismissalOverlayDoesNotApplyTheRowOffsetTwice() throws {
        let row = try source("Haiity/Views/ReminderRow.swift")
        let start = try XCTUnwrap(row.range(of: "rowContent\n                .offset"))
        let end = try XCTUnwrap(row.range(of: ".onGeometryChange",
                                          range: start.upperBound..<row.endIndex))
        let revealHost = row[start.lowerBound..<end.lowerBound]

        XCTAssertEqual(String(revealHost)
            .components(separatedBy: ".offset(x: revealOffset * mirror)").count - 1,
                       1,
                       "the transparent dismissal target follows the already-offset row")
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
