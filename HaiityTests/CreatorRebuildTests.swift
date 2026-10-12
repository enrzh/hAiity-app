import XCTest
@testable import Haiity

@MainActor
final class CreatorRebuildTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "de_DE")
        value.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return value
    }

    private var today: Date {
        DayKey.date(from: "2026-10-10", calendar: calendar)!
    }

    func testCreationEntryPointsUseDailyHabitAndOnceReminderDefaults() {
        let habit = EditHabitSheet.initialDraft(calendar: calendar, today: today)
        let reminder = EditHabitSheet.initialDraft(initialItemType: .reminder,
                                                   calendar: calendar, today: today)
        XCTAssertEqual(habit.frequency, .daily)
        XCTAssertEqual(reminder.frequency, .once)
        XCTAssertEqual(reminder.recurrence(calendar: calendar).start, "2026-10-10")
        XCTAssertFalse(habit.hasTime)
        XCTAssertFalse(reminder.hasTime)
        XCTAssertEqual(RecurrenceDraft(today: today, calendar: calendar).frequency, .once)
    }

    func testInitialTypeCannotReplaceAnExistingLegacySchedule() {
        let rules: [Recurrence] = [
            .weekdays([], end: .on("2026-12-31")),
            .times(3, per: .weekly, weekdays: [3]),
            .monthly(.lastDayOfMonth, interval: 2, end: .on("2026-12-31")),
            Recurrence(frequency: .once, start: "2026-10-15", target: 7)
        ]
        for type in HabitItemType.allCases {
            for rule in rules {
                let existing = Habit(name: "Existing", itemType: type,
                                     reminderMinutes: 8 * 60, recurrence: rule)
                let loaded = EditHabitSheet.initialDraft(existing: existing,
                    initialItemType: type == .habit ? .reminder : .habit,
                    calendar: calendar, today: today)
                XCTAssertEqual(loaded.recurrence(calendar: calendar), existing.recurrence)
                XCTAssertEqual(loaded.timeMinutes(calendar: calendar), 8 * 60)
            }
        }
    }

    func testPreviewSeparatesAppointmentFromNormalizedAlertClocks() {
        let draft = RecurrenceDraft(.weekdays([2]), timeMinutes: 8 * 60,
                                    today: today, calendar: calendar)
        let preview = EditHabitSheet.previewSummary(name: "Read", itemType: .habit,
            draft: draft, notificationMode: .timeSensitive,
            notificationTimes: [17 * 60, 9 * 60, 9 * 60], calendar: calendar)
        XCTAssertTrue(preview.contains("Read"), preview)
        XCTAssertTrue(preview.contains("08:00"), preview)
        XCTAssertEqual(preview.components(separatedBy: "09:00").count - 1, 1)
        XCTAssertTrue(preview.contains("17:00"), preview)
        XCTAssertEqual(draft.timeMinutes(calendar: calendar), 8 * 60)
    }

    func testPreviewDoesNotAdvertiseDisabledOrExplicitlyEmptyTimes() {
        let draft = RecurrenceDraft(itemType: .reminder, today: today, calendar: calendar)
        let off = EditHabitSheet.previewSummary(name: "Dentist", itemType: .reminder,
            draft: draft, notificationMode: .off, notificationTimes: [17 * 60], calendar: calendar)
        let empty = EditHabitSheet.previewSummary(name: "Dentist", itemType: .reminder,
            draft: draft, notificationMode: .standard, notificationTimes: [], calendar: calendar)
        let inherited = EditHabitSheet.previewSummary(name: "Dentist", itemType: .reminder,
            draft: draft, notificationMode: .standard, notificationTimes: nil, calendar: calendar)
        XCTAssertEqual(off, empty)
        XCTAssertFalse(off.contains("17:00"), off)
        XCTAssertFalse(empty.contains("09:00"), empty)
        XCTAssertTrue(inherited.contains("09:00"), inherited)
        XCTAssertFalse(draft.hasTime, "previewing an inherited alert must not invent an appointment clock")
    }

    func testPreviewShowsFutureStartAndRetainsTheAbsenceOfALegacyStart() {
        let future = DayKey.date(from: "2099-10-15", calendar: calendar)!
        let dated = RecurrenceDraft(itemType: .habit, today: future, calendar: calendar)
        let legacy = RecurrenceDraft(.daily, today: future, calendar: calendar)
        let datedPreview = EditHabitSheet.previewSummary(name: "Read", itemType: .habit,
            draft: dated, notificationMode: .off, notificationTimes: nil, calendar: calendar)
        let legacyPreview = EditHabitSheet.previewSummary(name: "Read", itemType: .habit,
            draft: legacy, notificationMode: .off, notificationTimes: nil, calendar: calendar)
        XCTAssertTrue(datedPreview.contains("2099"), datedPreview)
        XCTAssertTrue(datedPreview.contains("15"), datedPreview)
        XCTAssertFalse(legacyPreview.contains("2099"), legacyPreview)
        XCTAssertFalse(legacy.hasStart)
    }
}
