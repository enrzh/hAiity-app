import EventKit
import XCTest
@testable import Haiity

final class CalendarSyncSelectionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "CalendarSyncSelectionTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testLegacyEnabledMigratesToHabitsOnly() {
        defaults.set(true, forKey: CalendarSyncPreferences.legacyEnabledKey)
        XCTAssertEqual(CalendarSyncPreferences.selection(in: defaults),
                       CalendarSyncSelection(habits: true, reminders: false))
    }

    func testLegacyDisabledMigratesToBothOff() {
        defaults.set(false, forKey: CalendarSyncPreferences.legacyEnabledKey)
        XCTAssertEqual(CalendarSyncPreferences.selection(in: defaults),
                       CalendarSyncSelection(habits: false, reminders: false))
    }

    func testAllSelectionCombinationsIncludeTheExpectedItemTypes() {
        let habit = Habit(name: "Lesen")
        let reminder = Habit(name: "Tabletten", itemType: .reminder)

        for habits in [false, true] {
            for reminders in [false, true] {
                let selection = CalendarSyncSelection(habits: habits, reminders: reminders)
                XCTAssertEqual(selection.includes(habit), habits)
                XCTAssertEqual(selection.includes(reminder), reminders)
            }
        }
    }

    func testIndividualOptOutOverridesEnabledType() {
        var habit = Habit(name: "Lesen")
        var reminder = Habit(name: "Tabletten", itemType: .reminder)
        habit.calendarSyncEnabled = false
        reminder.calendarSyncEnabled = false

        let selection = CalendarSyncSelection(habits: true, reminders: true)
        XCTAssertFalse(selection.includes(habit))
        XCTAssertFalse(selection.includes(reminder))
    }

    func testNewKeysOverrideLegacyPreference() {
        defaults.set(true, forKey: CalendarSyncPreferences.legacyEnabledKey)
        defaults.set(false, forKey: CalendarSyncPreferences.habitsEnabledKey)
        defaults.set(true, forKey: CalendarSyncPreferences.remindersEnabledKey)

        XCTAssertEqual(CalendarSyncPreferences.selection(in: defaults),
                       CalendarSyncSelection(habits: false, reminders: true))
    }

    func testMoreScreenExposesIndependentCalendarToggles() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Views/MoreView.swift"))
        XCTAssertTrue(source.contains("calendar-sync-habits-toggle"))
        XCTAssertTrue(source.contains("calendar-sync-reminders-toggle"))
        XCTAssertTrue(source.contains("CalendarSync.syncHabits"))
        XCTAssertTrue(source.contains("CalendarSync.syncReminders"))
    }

    func testEveryCalendarEnablePathRequiresPro() throws {
        XCTAssertFalse(CalendarFeatureGate.canEnable(unlocked: false))
        XCTAssertTrue(CalendarFeatureGate.canEnable(unlocked: true))

        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Views/MoreView.swift"))
        XCTAssertTrue(source.contains("guard CalendarFeatureGate.canEnable(unlocked: unlocked)"))
        XCTAssertTrue(source.contains("paywall = .calendar"))
    }

    func testMoreViewReminderToggleUsesItsBinding() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Views/MoreView.swift"))
        XCTAssertTrue(source.contains("Toggle(isOn: reminderSyncBinding)"))
    }
}

final class SyncWatermarkTests: XCTestCase {
    func testWatermarkKeepsReadableProductNameAndInvisibleItemMarker() {
        let id = UUID()
        let note = SyncWatermark.note(for: id, kind: .habitCalendar)

        XCTAssertTrue(note.hasPrefix("hAiity"))
        XCTAssertFalse(note.contains(id.uuidString))
        XCTAssertTrue(note.unicodeScalars.contains { $0.value == 0x2063 })
        XCTAssertTrue(note.unicodeScalars.contains { (0xE0000...0xE007F).contains($0.value) })
    }

    func testCopyTextIsStableForAllNativeIntegrations() {
        XCTAssertEqual(SyncWatermark.copyText(for: .habitCalendar), "hAiity")
        XCTAssertEqual(SyncWatermark.copyText(for: .reminderCalendar), "hAiity")
        XCTAssertEqual(SyncWatermark.copyText(for: .nativeReminder), "hAiity")
    }

    func testNativeServicesUseTheSharedWatermark() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let calendar = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Services/CalendarSync.swift"))
        let reminders = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Services/ReminderSync.swift"))

        XCTAssertTrue(calendar.contains("SyncWatermark.note(for:"))
        XCTAssertTrue(reminders.contains("SyncWatermark.note(for:"))
    }
}

/// Die Abbildung Habit -> Kalender-Termin (`CalendarEventPlan`) — pur, ohne
/// EventKit: welche Habits einen Termin bekommen, wann er beginnt, wie er
/// sich wiederholt und wann er endet.
final class CalendarEventPlanTests: XCTestCase {
    /// So, 09.08.2026 als „heute" — dieselbe Fixture-Wochenlage wie überall.
    private let today = "2026-08-09"

    func testNewItemsAreIncludedInCalendarByDefault() {
        XCTAssertTrue(Habit(name: "Lesen").calendarSyncEnabled)
        XCTAssertTrue(Habit(name: "Tabletten", itemType: .reminder).calendarSyncEnabled)
    }

    func testDailyHabitWithTimeBecomesTimedDailyEvent() {
        let habit = Habit(name: "Lesen", emoji: "📚", timeMinutes: 19 * 60,
                          recurrence: .daily)
        let plan = CalendarEventPlan(habit: habit, today: today)
        XCTAssertEqual(plan?.title, "📚 Lesen")
        XCTAssertEqual(plan?.firstDay, today)
        XCTAssertEqual(plan?.minutes, 19 * 60)
        XCTAssertEqual(plan?.frequency, .daily)
        XCTAssertEqual(plan?.interval, 1)
        XCTAssertFalse(plan?.isReminder ?? true)
    }

    func testReminderPlanCarriesReminderWatermarkKind() {
        let plan = CalendarEventPlan(habit: Habit(name: "Tabletten", itemType: .reminder,
                                                   recurrence: .daily), today: today)

        XCTAssertTrue(plan?.isReminder ?? false)
    }

    func testHabitWithoutTimeIsAllDay() {
        let plan = CalendarEventPlan(habit: Habit(name: "Lesen", recurrence: .daily),
                                     today: today)
        XCTAssertNil(plan?.minutes)
    }

    func testPlannedSessionDurationSetsEventLength() {
        var habit = Habit(name: "Sport", timeMinutes: 7 * 60, recurrence: .daily)
        habit.durationMinutes = 45
        XCTAssertEqual(CalendarEventPlan(habit: habit, today: today)?.durationMinutes, 45)
        XCTAssertEqual(CalendarEventPlan(habit: Habit(name: "X", timeMinutes: 60,
                                                      recurrence: .daily),
                                         today: today)?.durationMinutes, 30)
    }

    func testWeekdayHabitStartsOnItsNextAgreedDay() {
        // Dienstage (3); heute ist Sonntag -> erster Termin Di, 11.08.
        let habit = Habit(name: "Yoga", recurrence: .weekdays([3]))
        let plan = CalendarEventPlan(habit: habit, today: today)
        XCTAssertEqual(plan?.firstDay, "2026-08-11")
        XCTAssertEqual(plan?.frequency, .weekly)
        XCTAssertEqual(plan?.weekdays, [3])
    }

    /// Flexible Ziele MIT Verabredung: Wochenmuster an genau diesen Tagen.
    func testFlexibleWithAgreedWeekdaysBecomesWeeklyPattern() {
        let habit = Habit(name: "Schwimmen",
                          recurrence: .times(2, per: .weekly, weekdays: [2, 5]))
        let plan = CalendarEventPlan(habit: habit, today: today)
        XCTAssertEqual(plan?.frequency, .weekly)
        XCTAssertEqual(plan?.weekdays, [2, 5])
        XCTAssertEqual(plan?.firstDay, "2026-08-10")
    }

    /// Flexible Ziele OHNE Verabredung haben keinen Termin, den man
    /// eintragen könnte.
    func testFlexibleWithoutWeekdaysHasNoPlan() {
        let habit = Habit(name: "Irgendwann",
                          recurrence: .times(3, per: .weekly))
        XCTAssertNil(CalendarEventPlan(habit: habit, today: today))
    }

    func testArchivedHabitsHaveNoPlan() {
        var habit = Habit(name: "Alt", recurrence: .daily)
        habit.archivedAt = "2026-08-01"
        XCTAssertNil(CalendarEventPlan(habit: habit, today: today))
    }

    func testMonthlyDayRuleCarriesDayOfMonth() {
        let habit = Habit(name: "Miete",
                          recurrence: .monthly(.dayOfMonth(1)))
        let plan = CalendarEventPlan(habit: habit, today: today)
        XCTAssertEqual(plan?.frequency, .monthly)
        XCTAssertEqual(plan?.daysOfMonth, [1])
        XCTAssertEqual(plan?.firstDay, "2026-09-01")
    }

    func testLastDayOfMonthMapsToMinusOne() {
        let habit = Habit(name: "Rückblick",
                          recurrence: .monthly(.lastDayOfMonth))
        XCTAssertEqual(CalendarEventPlan(habit: habit, today: today)?.daysOfMonth, [-1])
    }

    func testEndDatePassesThrough() {
        let habit = Habit(name: "Kur",
                          recurrence: Recurrence(frequency: .daily,
                                                 end: .on("2026-09-01")))
        XCTAssertEqual(CalendarEventPlan(habit: habit, today: today)?.end, .on("2026-09-01"))
    }

    func testEndTitleIsVisibleInNativeEventTitle() {
        let habit = Habit(name: "Kur",
                          recurrence: Recurrence(frequency: .daily,
                                                 end: .on("2026-09-01"),
                                                 endTitle: "Sommer"))
        XCTAssertEqual(CalendarEventPlan(habit: habit, today: today)?.title, "Kur · Sommer")
    }

    /// Der Fingerabdruck ändert sich mit dem Sichtbaren — und nur damit.
    func testFingerprintTracksVisibleChanges() {
        let a = CalendarEventPlan(habit: Habit(name: "Lesen", timeMinutes: 19 * 60,
                                               recurrence: .daily), today: today)
        let b = CalendarEventPlan(habit: Habit(name: "Lesen", timeMinutes: 19 * 60,
                                               recurrence: .daily), today: today)
        let c = CalendarEventPlan(habit: Habit(name: "Lesen", timeMinutes: 20 * 60,
                                               recurrence: .daily), today: today)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    /// Kalendereinträge sind NUR Bild: erinnern tut hAiity selbst — ein
    /// Termin mit eigenem Wecker wäre der zweite Alarm für denselben Habit.
    func testCalendarEventsCarryNoAlarms() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Services/CalendarSync.swift"))
        XCTAssertTrue(source.contains("event.alarms = nil"))
        XCTAssertFalse(source.contains("EKAlarm"), "kein Wecker am Termin")
        XCTAssertFalse(source.contains("addAlarm"), "kein Wecker am Termin")
    }
}

final class CalendarSyncRecurrenceRuleTests: XCTestCase {
    @MainActor
    func testOncePlanProducesNoEventKitRecurrenceRule() throws {
        let habit = Habit(name: "Einmal",
                          recurrence: Recurrence(frequency: .once,
                                                 start: "2026-08-18"))
        let plan = try XCTUnwrap(CalendarEventPlan(habit: habit, today: "2026-08-18"))

        XCTAssertNil(CalendarSync.recurrenceRule(for: plan))
    }

    @MainActor
    func testDailyPlanStillProducesDailyEventKitRecurrenceRule() throws {
        let habit = Habit(name: "Taeglich", recurrence: .daily)
        let plan = try XCTUnwrap(CalendarEventPlan(habit: habit, today: "2026-08-18"))

        let rule = try XCTUnwrap(CalendarSync.recurrenceRule(for: plan))

        XCTAssertEqual(rule.frequency, .daily)
    }

    @MainActor
    func testYearlyMultipleDatesUseExactNativeDayOfYearValues() throws {
        let recurrence = Recurrence(frequency: .yearly,
                                    rule: .multipleMonthDays([
                                        Recurrence.MonthDay(month: 3, day: 12),
                                        Recurrence.MonthDay(month: 10, day: 5)
                                    ]),
                                    start: "2026-03-12")
        let habit = Habit(name: "Mehrere Jahrestage", recurrence: recurrence)
        let plan = try XCTUnwrap(CalendarEventPlan(habit: habit,
                                                   today: "2026-01-01",
                                                   calendar: .current))

        let rule = try XCTUnwrap(CalendarSync.recurrenceRule(for: plan))

        XCTAssertEqual(rule.frequency, EKRecurrenceFrequency.yearly)
        XCTAssertEqual(rule.daysOfTheYear?.map { $0.intValue }, [72, 279])
        XCTAssertNil(rule.daysOfTheMonth)
        XCTAssertNil(rule.monthsOfTheYear)
    }
}

final class CalendarSyncNativeMappingTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = Locale(identifier: "de_DE")
        calendar.firstWeekday = 2
        return calendar
    }()

    @MainActor
    func testOneTimePlanConfiguresSingleNativeEventWithoutRecurrence() throws {
        let habit = Habit(name: "Einmal",
                          timeMinutes: 9 * 60 + 15,
                          recurrence: Recurrence(frequency: .once,
                                                 start: "2026-08-18"))
        let plan = try XCTUnwrap(CalendarEventPlan(habit: habit,
                                                   today: "2026-08-10",
                                                   calendar: calendar))
        let event = EKEvent(eventStore: EKEventStore())

        CalendarSync.configure(event: event, for: plan, calendar: calendar)

        XCTAssertEqual(DayKey.key(for: event.startDate, calendar: calendar), "2026-08-18")
        XCTAssertEqual(calendar.component(.hour, from: event.startDate), 9)
        XCTAssertEqual(calendar.component(.minute, from: event.startDate), 15)
        XCTAssertTrue(event.recurrenceRules?.isEmpty ?? true)
    }

    @MainActor
    func testRecurringPlanKeepsNativeRecurrenceRule() throws {
        let habit = Habit(name: "Taeglich",
                          timeMinutes: 8 * 60,
                          recurrence: .daily)
        let plan = try XCTUnwrap(CalendarEventPlan(habit: habit,
                                                   today: "2026-08-18",
                                                   calendar: calendar))
        let event = EKEvent(eventStore: EKEventStore())

        CalendarSync.configure(event: event, for: plan, calendar: calendar)

        XCTAssertEqual(event.recurrenceRules?.count, 1)
        XCTAssertEqual(event.recurrenceRules?.first?.frequency, .daily)
    }
}
