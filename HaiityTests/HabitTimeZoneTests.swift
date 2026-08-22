import XCTest
@testable import Haiity

final class HabitTimeZoneTests: XCTestCase {
    private var berlin: Calendar {
        HabitTimeZone.calendar(identifier: "Europe/Berlin")
    }

    func testInvalidIdentifiersAreDroppedAndDeviceIsExplicit() {
        XCTAssertNil(HabitTimeZone.sanitizedIdentifier("Mars/Base"))
        XCTAssertEqual(HabitTimeZone.sanitizedIdentifier(" device "),
                       HabitTimeZone.deviceIdentifier)
        XCTAssertEqual(HabitTimeZone.sanitizedIdentifier("Asia/Shanghai"),
                       "Asia/Shanghai")
    }

    func testHabitOverrideWinsOverGlobalDefault() {
        var habit = Habit(name: "Schicht")
        habit.timeZoneIdentifier = "Asia/Shanghai"

        let resolved = HabitTimeZone.calendar(for: habit,
                                              defaultIdentifier: "Europe/Berlin")

        XCTAssertEqual(resolved.timeZone.identifier, "Asia/Shanghai")
    }

    func testGlobalDefaultResolvesWhenHabitHasNoOverride() {
        let habit = Habit(name: "Schicht")
        let resolved = HabitTimeZone.calendar(for: habit,
                                              defaultIdentifier: "Europe/Berlin")

        XCTAssertEqual(resolved.timeZone.identifier, "Europe/Berlin")
    }

    func testNilResolutionPreservesTheCallerCalendar() {
        var caller = Calendar(identifier: .gregorian)
        caller.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let resolved = HabitTimeZone.calendar(for: Habit(name: "Schicht"),
                                              defaultIdentifier: nil,
                                              base: caller)

        XCTAssertEqual(resolved.timeZone.identifier, "Asia/Tokyo")
    }

    func testHabitTimezoneRoundTripsThroughJSON() throws {
        var habit = Habit(name: "Schicht")
        habit.timeZoneIdentifier = "Asia/Shanghai"

        let decoded = try JSONDecoder().decode(Habit.self,
                                                from: JSONEncoder().encode(habit))

        XCTAssertEqual(decoded.timeZoneIdentifier, "Asia/Shanghai")
    }

    func testDefaultTimezoneRoundTripsThroughHabitData() throws {
        var data = HabitData.empty
        data.defaultTimeZoneIdentifier = "America/New_York"

        let decoded = try JSONDecoder().decode(HabitData.self,
                                                from: JSONEncoder().encode(data))

        XCTAssertEqual(decoded.defaultTimeZoneIdentifier, "America/New_York")
    }

    func testHabitStorePersistsDefaultTimezone() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("timezone-(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = HabitStore(url: url)
        store.defaultTimeZoneIdentifier = "Asia/Tokyo"

        XCTAssertEqual(HabitStore(url: url).defaultTimeZoneIdentifier, "Asia/Tokyo")
    }

    func testHabitPlanUsesHabitTimezone() {
        var habit = Habit(name: "Schicht", timeMinutes: 9 * 60)
        habit.timeZoneIdentifier = "Asia/Shanghai"
        let now = berlin.date(from: DateComponents(year: 2026, month: 8, day: 9))!

        let plan = Reminders.habitPlans(habits: [habit],
                                        defaultTimeZoneIdentifier: "Europe/Berlin",
                                        now: now,
                                        calendar: berlin).first

        XCTAssertEqual(plan?.dateMatching.timeZone?.identifier, "Asia/Shanghai")
    }

    func testCalendarAndReminderPlansCarryResolvedTimezone() throws {
        var habit = Habit(name: "Schicht", itemType: .reminder,
                          timeMinutes: 9 * 60)
        habit.timeZoneIdentifier = "Asia/Shanghai"

        let calendarPlan = try XCTUnwrap(CalendarEventPlan(
            habit: habit,
            today: "2026-08-09",
            defaultTimeZoneIdentifier: "Europe/Berlin"))
        let reminderPlan = try XCTUnwrap(ReminderSyncPlan(
            habit: habit,
            today: "2026-08-09",
            defaultTimeZoneIdentifier: "Europe/Berlin"))

        XCTAssertEqual(calendarPlan.timeZoneIdentifier, "Asia/Shanghai")
        XCTAssertEqual(reminderPlan.eventPlan.timeZoneIdentifier, "Asia/Shanghai")
        XCTAssertEqual(reminderPlan.eventPlan.fingerprint,
                       CalendarEventPlan(habit: habit,
                                         today: "2026-08-09",
                                         defaultTimeZoneIdentifier: "Europe/Berlin")?.fingerprint)
    }

    func testGlobalTimezoneIsUsedWhenHabitHasNoOverride() throws {
        let habit = Habit(name: "Schicht", timeMinutes: 9 * 60)
        let plan = try XCTUnwrap(CalendarEventPlan(
            habit: habit,
            today: "2026-08-09",
            defaultTimeZoneIdentifier: "America/New_York"))

        XCTAssertEqual(plan.timeZoneIdentifier, "America/New_York")
    }

    func testCalendarPlanPreservesCallerTimezoneWithoutAnOverride() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let plan = try XCTUnwrap(CalendarEventPlan(
            habit: Habit(name: "Schicht", timeMinutes: 9 * 60),
            today: "2026-08-09",
            calendar: calendar))

        XCTAssertEqual(plan.timeZoneIdentifier, "Asia/Tokyo")
    }

    func testExternalCheckInPathsResolveTheHabitTimezone() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let paths = [
            "Haiity/Intents/CheckOffHabitIntent.swift",
            "Haiity/Intents/SiriQueryIntents.swift",
            "Haiity/Services/HomeShortcuts.swift",
            "Haiity/Services/NotificationPresenter.swift",
            "Haiity/Services/HabitSessionManager.swift"
        ]

        for path in paths {
            let source = try String(contentsOf: root.appendingPathComponent(path))
            let resolvesHabitTimeZone = source.contains("HabitTimeZone.calendar")
                || source.contains("HabitTimeZone.today")
            XCTAssertTrue(resolvesHabitTimeZone,
                          "\(path) must resolve the habit timezone before choosing a day")
        }
    }

    func testMainGraphAndWidgetCarryTheDefaultTimezoneIntoTheirDayCalculations() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let grid = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/ContributionGrid.swift"))
        XCTAssertTrue(grid.contains("var calendar: Calendar"),
                      "the in-app graph must not silently use Calendar.current")

        let widget = try String(contentsOf: root.appendingPathComponent(
            "HaiityWidget/WidgetLogic.swift"))
        XCTAssertTrue(widget.contains("HabitTimeZone.calendar(for:"),
                      "widget logic must resolve each habit's timezone")
    }
}
