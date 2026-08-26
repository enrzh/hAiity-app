import Foundation
import EventKit
import XCTest
@testable import Haiity

final class ReminderSyncPlanTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = Locale(identifier: "de_DE")
        calendar.firstWeekday = 2
        return calendar
    }()

    func testPlanRejectsTrackedHabitsAndUsesReminderOccurrence() {
        var reminder = Habit(name: "Tabletten", itemType: .reminder)
        reminder.createdAt = "2026-08-17"
        reminder.calendarSyncEnabled = true

        let plan = ReminderSyncPlan(habit: reminder,
                                    today: "2026-08-17",
                                    calendar: calendar)

        XCTAssertEqual(plan?.habitID, reminder.id)
        XCTAssertEqual(plan?.title, "Tabletten")
        XCTAssertEqual(plan?.occurrenceDay, "2026-08-17")
        XCTAssertNil(ReminderSyncPlan(habit: Habit(name: "Laufen"),
                                      today: "2026-08-17",
                                      calendar: calendar))
    }

    func testCompletedReminderPlansItsNextOccurrence() {
        var reminder = Habit(name: "Tabletten", itemType: .reminder)
        reminder.createdAt = "2026-08-01"
        reminder.repeatsWhileIncomplete = false
        reminder.reminderCursor = "2026-08-18"
        reminder.log["2026-08-17"] = 1

        XCTAssertEqual(ReminderSyncPlan(habit: reminder,
                                        today: "2026-08-17",
                                        calendar: calendar)?.occurrenceDay,
                       "2026-08-18")
    }

    func testReminderLinksRoundTrip() {
        let suiteName = "reminder-sync-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let link = ReminderSyncLink(habitID: UUID(),
                                    reminderID: "native-id",
                                    occurrenceDay: "2026-08-17")
        ReminderSyncPreferences.setLinks([link.habitID.uuidString: link], in: defaults)

        XCTAssertEqual(ReminderSyncPreferences.links(in: defaults)[link.habitID.uuidString], link)
    }

    func testSelectionHonorsGlobalAndPerItemOptIn() {
        var reminder = Habit(name: "Tabletten", itemType: .reminder)
        reminder.calendarSyncEnabled = true
        var disabled = reminder
        disabled.calendarSyncEnabled = false

        XCTAssertTrue(ReminderSyncSelection(enabled: true).includes(reminder))
        XCTAssertFalse(ReminderSyncSelection(enabled: true).includes(disabled))
        XCTAssertFalse(ReminderSyncSelection(enabled: false).includes(reminder))
        XCTAssertFalse(ReminderSyncSelection(enabled: true).includes(Habit(name: "Laufen")))
    }

    func testListResolverUsesStoredWritableListBeforeRecoveringExactTitle() {
        let stored = ReminderListCandidate(id: "stored", title: "Renamed", isWritable: true)
        let sameTitle = ReminderListCandidate(id: "same-title", title: "hAiity", isWritable: true)
        let readOnly = ReminderListCandidate(id: "read-only", title: "hAiity", isWritable: false)

        XCTAssertEqual(ReminderListResolver.id(stored: stored,
                                               calendars: [sameTitle, readOnly],
                                               title: "hAiity"),
                       "stored")
        XCTAssertEqual(ReminderListResolver.id(stored: nil,
                                               calendars: [readOnly, sameTitle],
                                               title: "hAiity"),
                       "same-title")
        XCTAssertNil(ReminderListResolver.id(stored: nil,
                                             calendars: [readOnly],
                                             title: "hAiity"))
    }
}

final class ReminderSyncContractTests: XCTestCase {
    func testNativeReminderToggleActionDisablesWithoutPro() {
        XCTAssertEqual(NativeReminderToggleAction.action(for: false, unlocked: false), .disable)
    }

    func testNativeReminderToggleActionShowsPaywallForFreeEnable() {
        XCTAssertEqual(NativeReminderToggleAction.action(for: true, unlocked: false), .showPaywall)
    }

    func testNativeReminderToggleActionRequestsAccessForProEnable() {
        XCTAssertEqual(NativeReminderToggleAction.action(for: true, unlocked: true), .requestAccess)
    }

    func testReminderServiceUsesReminderPermissionAndOwnedList() throws {
        let source = try source("Haiity/Services/ReminderSync.swift")
        XCTAssertTrue(source.contains("requestFullAccessToReminders"))
        XCTAssertTrue(source.contains("authorizationStatus(for: .reminder)"))
        XCTAssertTrue(source.contains("hAiity"))
        XCTAssertTrue(source.contains("EKReminder"))
        XCTAssertFalse(source.contains("event(withIdentifier:"))
    }

    func testReminderCopyHintIsAvailableForTheNativeList() {
        XCTAssertEqual(SyncWatermark.copyText(for: .nativeReminder), "hAiity")
    }

    func testCalendarSyncSharesItsRecurrenceRuleHelper() throws {
        let calendar = try source("Haiity/Services/CalendarSync.swift")
        let reminders = try source("Haiity/Services/ReminderSync.swift")
        XCTAssertTrue(calendar.contains("static func recurrenceRule(for plan: CalendarEventPlan)"))
        XCTAssertTrue(reminders.contains("CalendarSync.recurrenceRule(for: plan.eventPlan)"))
    }

    func testReminderSyncOnlyPersistsNativeIDsAfterSuccessfulSaves() throws {
        let source = try source("Haiity/Services/ReminderSync.swift")
        XCTAssertTrue(source.contains("store.calendars(for: .reminder)"))
        XCTAssertTrue(source.contains("allowsContentModifications"))
        XCTAssertTrue(source.contains("try store.save(reminder, commit: true)"))
        XCTAssertTrue(source.contains("lastError"))
        XCTAssertFalse(source.contains("try? store.save(reminder, commit: true)"))
    }

    func testReminderReconciliationRepairsAllOwnedDuplicatesBeforeSaving() throws {
        let source = try source("Haiity/Services/ReminderSync.swift")

        XCTAssertTrue(source.contains("async"),
                      "duplicate-safe reminder reconciliation must await the EventKit fetch")
        XCTAssertTrue(source.contains("selectCanonicalItem"))
        XCTAssertTrue(source.contains("duplicateIDs"))
        XCTAssertTrue(source.contains("fetchReminders(matching:"))
    }

    func testReminderValidationCarriesScannedCanonicalReminderIntoSavePass() throws {
        let source = try source("Haiity/Services/ReminderSync.swift")

        XCTAssertTrue(source.contains("var validatedReminders"),
                      "validation must retain the fetched canonical reminder")
        XCTAssertTrue(source.contains("validatedReminders[key]"),
                      "the save pass must use the scanned reminder before looking up its ID")
        XCTAssertTrue(source.contains("existing: linked"),
                      "changed reminders must remove the fetched canonical object directly")
    }

    func testReminderCleanupCannotOverlapReconciliation() throws {
        let source = try source("Haiity/Services/ReminderSync.swift")

        XCTAssertTrue(source.contains("guard hasAccess, !isReconciling, !isPulling else { return false }"),
                      "cleanup must not race a reconciliation or native pull")
        XCTAssertTrue(source.contains("isReconciling = true"),
                      "cleanup must hold the same native-store guard while it runs")
    }

    func testForegroundNativeReconciliationAwaitsReminderFetch() throws {
        let content = try source("Haiity/Views/ContentView.swift")

        XCTAssertTrue(content.contains("validate: true"),
                      "foreground reconciliation must inspect native duplicates")
        XCTAssertTrue(content.contains("await ReminderSync.reconcile"),
                      "the async EventKit pass must finish before the lifecycle task continues")
    }

    func testMoreViewReminderBindingUsesPureToggleAction() throws {
        let source = try source("Haiity/Views/MoreView.swift")
        XCTAssertTrue(source.contains("switch NativeReminderToggleAction.action(for: on, unlocked: unlocked)"))
        XCTAssertTrue(source.contains("case .disable:"))
        XCTAssertTrue(source.contains("case .showPaywall:"))
        XCTAssertTrue(source.contains("case .requestAccess:"))
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relative))
    }
}

final class ReminderSyncNativeMappingTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = Locale(identifier: "de_DE")
        calendar.firstWeekday = 2
        return calendar
    }()

    @MainActor
    func testOneTimePlanUsesSelectedDayWithoutNativeRecurrenceRule() throws {
        var reminder = Habit(name: "Einmal", itemType: .reminder)
        reminder.reminderMinutes = 7 * 60 + 45
        reminder.recurrence = Recurrence(frequency: .once, start: "2026-08-18")
        let plan = try XCTUnwrap(ReminderSyncPlan(habit: reminder,
                                                  today: "2026-08-10",
                                                  calendar: calendar))
        let nativeReminder = EKReminder(eventStore: EKEventStore())

        ReminderSync.configure(reminder: nativeReminder,
                               for: plan,
                               completed: false,
                               calendar: calendar)

        XCTAssertEqual(plan.occurrenceDay, "2026-08-18")
        XCTAssertEqual(nativeReminder.dueDateComponents?.year, 2026)
        XCTAssertEqual(nativeReminder.dueDateComponents?.month, 8)
        XCTAssertEqual(nativeReminder.dueDateComponents?.day, 18)
        XCTAssertEqual(nativeReminder.dueDateComponents?.hour, 7)
        XCTAssertEqual(nativeReminder.dueDateComponents?.minute, 45)
        XCTAssertTrue(nativeReminder.recurrenceRules?.isEmpty ?? true)
    }

    @MainActor
    func testRecurringPlanKeepsNativeReminderRecurrenceRule() throws {
        let reminder = Habit(name: "Taeglich",
                             itemType: .reminder,
                             reminderMinutes: 8 * 60,
                             recurrence: .daily)
        let plan = try XCTUnwrap(ReminderSyncPlan(habit: reminder,
                                                  today: "2026-08-18",
                                                  calendar: calendar))
        let nativeReminder = EKReminder(eventStore: EKEventStore())

        ReminderSync.configure(reminder: nativeReminder,
                               for: plan,
                               completed: false,
                               calendar: calendar)

        XCTAssertEqual(nativeReminder.recurrenceRules?.count, 1)
        XCTAssertEqual(nativeReminder.recurrenceRules?.first?.frequency, .daily)
    }
}
