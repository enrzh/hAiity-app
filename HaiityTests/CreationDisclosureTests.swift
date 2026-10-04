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
}
