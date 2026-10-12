import XCTest
@testable import Haiity

@MainActor
final class CreationDisclosureTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "de_DE")
        value.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return value
    }

    func testDisabledNotificationsNeverAdvertiseRetainedTimesAsActive() {
        let retained = [9 * 60, 17 * 60]
        let disabled = EditHabitSheet.notificationPreview(mode: .off, times: retained,
                                                          calendar: calendar)
        let silent = EditHabitSheet.notificationPreview(mode: .standard, times: [],
                                                        calendar: calendar)
        XCTAssertEqual(disabled, silent)
        XCTAssertFalse(disabled.contains("09:00"))
        XCTAssertFalse(disabled.contains("17:00"))

        let enabled = EditHabitSheet.notificationPreview(mode: .standard, times: retained,
                                                         calendar: calendar)
        XCTAssertTrue(enabled.contains("09:00"), enabled)
        XCTAssertTrue(enabled.contains("17:00"), enabled)
    }

    func testPreviewShowsEveryDistinctCustomTimeInChronologicalOrder() throws {
        let summary = EditHabitSheet.notificationPreview(mode: .standard,
                                                         times: [17 * 60, 9 * 60, 9 * 60],
                                                         calendar: calendar)
        let morning = try XCTUnwrap(summary.range(of: "09:00"), summary)
        let evening = try XCTUnwrap(summary.range(of: "17:00"), summary)
        XCTAssertLessThan(morning.lowerBound, evening.lowerBound)
        XCTAssertEqual(summary.components(separatedBy: "09:00").count - 1, 1)
    }

    func testInvalidOrEmptyCustomTimesNeverInventAFallback() {
        let empty = EditHabitSheet.notificationPreview(mode: .standard, times: [],
                                                       calendar: calendar)
        XCTAssertEqual(EditHabitSheet.notificationPreview(mode: .standard,
                                                          times: [-1, 1440],
                                                          calendar: calendar), empty)
        XCTAssertEqual(EditHabitSheet.notificationPreview(mode: .timeSensitive, times: [],
                                                          calendar: calendar), empty)
    }

    func testAppointmentAndTimeSensitiveNotificationPreviewStayDistinct() {
        let draft = RecurrenceDraft(.weekdays([2]), timeMinutes: 8 * 60, calendar: calendar)
        let standard = EditHabitSheet.notificationPreview(mode: .standard, times: [9 * 60],
                                                          calendar: calendar)
        let sensitive = EditHabitSheet.notificationPreview(mode: .timeSensitive,
                                                           times: [9 * 60], calendar: calendar)
        XCTAssertTrue(draft.summary(calendar: calendar).contains("08:00"))
        XCTAssertTrue(sensitive.contains("09:00"), sensitive)
        XCTAssertFalse(sensitive.contains("08:00"))
        XCTAssertNotEqual(standard, sensitive)
    }

    func testNotificationClockUsesTheItemCalendarAndLocale() {
        var selected = calendar
        selected.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        selected.locale = Locale(identifier: "en_US")
        let summary = EditHabitSheet.notificationPreview(mode: .standard, times: [9 * 60],
                                                         calendar: selected)
        XCTAssertTrue(summary.contains("9:00"))
        XCTAssertTrue(summary.contains("AM"))
    }

    private func editorSource() throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Views/EditHabitSheet.swift"))
    }

    func testEditorKeepsTypeChoiceSeparateFromRepeatingAndLoading() throws {
        let source = try editorSource()
        let repeatStart = try XCTUnwrap(source.range(of: "private var repeatsBinding:"))
        let repeatEnd = try XCTUnwrap(source.range(of: "private var itemTypeSelection:",
                                                  range: repeatStart.upperBound..<source.endIndex))
        let repeatBody = source[repeatStart.lowerBound..<repeatEnd.lowerBound]
        XCTAssertTrue(repeatBody.contains("draft.setRepeats(enabled, calendar: calendar)"))
        XCTAssertFalse(repeatBody.contains("itemType ="))
        let loadStart = try XCTUnwrap(source.range(of: "private func load()"))
        let saveStart = try XCTUnwrap(source.range(of: "private func save(",
                                                  range: loadStart.upperBound..<source.endIndex))
        let loadBody = source[loadStart.lowerBound..<saveStart.lowerBound]
        XCTAssertTrue(loadBody.contains("itemType = habit.itemType"))
        XCTAssertFalse(loadBody.contains("itemType = .reminder"))
        XCTAssertFalse(loadBody.contains("selectFrequency"))
        XCTAssertEqual(EditHabitSheet.initialDraft(calendar: calendar).frequency, .daily)
        XCTAssertTrue(source.contains("selection: itemTypeSelection"))
    }

    func testCollapsedAdditionalSettingsRetainSaveAndPermissionContract() throws {
        let source = try editorSource()
        let advanced = try XCTUnwrap(source.range(of: "if showingCreationAdvanced {"))
        let end = try XCTUnwrap(source.range(of: "if let habit = existing {",
                                            range: advanced.upperBound..<source.endIndex))
        let body = source[advanced.upperBound..<end.lowerBound]
        XCTAssertTrue(body.contains("notificationSection.settingsListRow()"))
        XCTAssertTrue(body.contains("creationAdvancedNotificationSection.settingsListRow()"))
        XCTAssertTrue(body.contains("durationSection.settingsListRow()"))
        XCTAssertTrue(body.contains("if itemType == .habit"))
        XCTAssertTrue(body.contains("appointmentTimeControls"))
        XCTAssertFalse(source.contains(".onChange(of: showingCreationAdvanced)"))
        XCTAssertFalse(source.contains(".onChange(of: showingKind)"))

        let save = try XCTUnwrap(source.range(of: "private func save("))
        let saveBody = source[save.lowerBound...]
        XCTAssertTrue(saveBody.contains("habit.notificationTimes = notificationTimes.map(Habit.normalizedNotificationTimes)"))
        XCTAssertTrue(saveBody.contains("habit.reminderMinutes = notificationTime"))
        XCTAssertTrue(saveBody.contains("habit.timeMinutes = notificationTime"))
        XCTAssertFalse(saveBody.contains("showingCreationAdvanced"))
        XCTAssertFalse(saveBody.contains("showingKind"))
        XCTAssertTrue(saveBody.contains("ProGate.maySaveTrackedHabit"))
        let write = try XCTUnwrap(saveBody.range(of: "if existing == nil { store.add(habit) } else { store.update(habit) }"))
        let permission = try XCTUnwrap(saveBody.range(of: "await Reminders.ensurePermission()"))
        XCTAssertLessThan(write.lowerBound, permission.lowerBound)
        XCTAssertTrue(saveBody.contains("guard store.lastWriteError == nil else"))
    }

    func testSentenceCreationAvailabilityDoesNotChangeTheInitialItemType() {
        let store = HabitStore(loadFromDisk: false)
        let editor = EditHabitSheet(store: store, initialItemType: .reminder, offersSentenceCreation: true)
        XCTAssertTrue(editor.offersSentenceCreation)
        XCTAssertEqual(editor.initialItemType, .reminder)
        XCTAssertEqual(EditHabitSheet.initialDraft(initialItemType: editor.initialItemType, calendar: calendar).frequency, .once)
        XCTAssertTrue(store.habits.isEmpty)
    }
}
