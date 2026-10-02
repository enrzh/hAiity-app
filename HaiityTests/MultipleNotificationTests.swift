import XCTest
@testable import Haiity

final class MultipleNotificationTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Berlin")!
        value.locale = Locale(identifier: "de_DE")
        return value
    }

    private func date(_ day: String = "2026-08-09", hour: Int = 8) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0,
                      of: DayKey.date(from: day, calendar: calendar)!)!
    }

    private func habit(_ type: HabitItemType = .habit, times: [Int]? = [9 * 60, 17 * 60]) -> Habit {
        var value = Habit(name: "Read", itemType: type, timeMinutes: 8 * 60,
                          notificationTimes: times)
        value.createdAt = "2026-08-01"
        return value
    }

    func testLegacyTimesAndFallbackKeepTheirExistingIdentifiers() throws {
        var value = habit(times: nil)
        let legacy = try JSONDecoder().decode(Habit.self, from: JSONEncoder().encode(value))
        XCTAssertNil(legacy.notificationTimes)
        XCTAssertEqual(legacy.effectiveNotificationTimes, [8 * 60])
        let plan = try XCTUnwrap(Reminders.habitPlans(habits: [legacy], now: date(hour: 7), calendar: calendar).first)
        XCTAssertEqual(plan.identifier, Reminders.habitReminderIdentifier(habitID: value.id, day: "2026-08-09"))
        value.timeMinutes = nil
        value.reminderMinutes = 10 * 60
        XCTAssertEqual(value.effectiveNotificationTimes, [10 * 60])
        value.reminderMinutes = nil
        XCTAssertEqual(value.effectiveNotificationTimes, [Habit.defaultNotificationMinutes])
    }

    func testCustomTimesRoundTripWithoutChangingTheScheduledTime() throws {
        let value = habit(times: [17 * 60, 9 * 60, 9 * 60, -1, 1440])
        let decoded = try JSONDecoder().decode(Habit.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded.notificationTimes, [9 * 60, 17 * 60])
        XCTAssertEqual(decoded.timeMinutes, 8 * 60)
        XCTAssertEqual(decoded.effectiveNotificationTimes, [9 * 60, 17 * 60])
    }

    func testRemovingEveryTimeStaysSilentAfterReload() throws {
        let value = habit(times: [])
        let decoded = try JSONDecoder().decode(Habit.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded.notificationTimes, [])
        XCTAssertTrue(Reminders.habitPlans(habits: [decoded], now: date(), calendar: calendar).isEmpty)
    }

    func testMalformedExplicitTimesAreSilentInsteadOfRestoringAnUnexpectedDefault() throws {
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(habit())) as? [String: Any])
        payload["notificationTimes"] = ["bad", 600]
        let decoded = try JSONDecoder().decode(Habit.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(decoded.effectiveNotificationTimes, [])
        payload["notificationTimes"] = NSNull()
        let inherited = try JSONDecoder().decode(Habit.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(inherited.effectiveNotificationTimes, [8 * 60])
    }

    func testBothItemTypesGetDistinctSameDayRequestsAndPreserveTheTarget() {
        for type in [HabitItemType.habit, .reminder] {
            let value = habit(type)
            let plans = Reminders.habitPlans(habits: [value], now: date(), calendar: calendar)
            let today = plans.filter { Reminders.habitTarget(for: $0.identifier)?.day == "2026-08-09" }
            XCTAssertEqual(today.map { $0.dateMatching.hour }, [9, 17])
            XCTAssertEqual(Set(plans.map(\.identifier)).count, plans.count)
            XCTAssertTrue(today.allSatisfy { Reminders.habitTarget(for: $0.identifier)?.habitID == value.id })
        }
        let id = UUID()
        XCTAssertNil(Reminders.habitTarget(for: Reminders.habitReminderIdentifier(habitID: id, day: "2026-08-09") + "-t1440"))
        XCTAssertNil(Reminders.habitTarget(for: Reminders.habitReminderIdentifier(habitID: id, day: "2026-08-09") + "-garbage"))
    }

    func testPastAlertsAreSkippedButLaterAlertsForANonContinuingReminderSurvive() {
        var value = habit(.reminder)
        value.recurrence = Recurrence(frequency: .once, start: "2026-08-09")
        value.repeatsWhileIncomplete = false
        let plans = Reminders.habitPlans(habits: [value], now: date(hour: 12), calendar: calendar)
        XCTAssertEqual(plans.map { $0.dateMatching.hour }, [17])
        XCTAssertEqual(ReminderOccurrenceEngine.state(for: value, now: date(hour: 12), calendar: calendar).actionable?.dueDate,
                       date(hour: 8))
    }

    func testCompletionAndDeclineCancelAllAlertsForTheHandledDay() {
        for kind in [HabitKind.checkbox, .quantity, .yesNo] {
            var value = habit()
            value.kind = kind
            if kind == .quantity { value.recurrence = Recurrence(target: 3) }
            value.log["2026-08-09"] = kind == .yesNo ? Habit.Answer.no : kind == .quantity ? 3 : 1
            let plans = Reminders.habitPlans(habits: [value], now: date(), calendar: calendar)
            XCTAssertFalse(plans.contains { Reminders.habitTarget(for: $0.identifier)?.day == "2026-08-09" })
            XCTAssertTrue(plans.contains { Reminders.habitTarget(for: $0.identifier)?.day == "2026-08-10" })
        }
        var quantity = habit()
        quantity.recurrence = Recurrence(target: 3)
        quantity.log["2026-08-09"] = 1
        XCTAssertEqual(Reminders.habitPlans(habits: [quantity], now: date(), calendar: calendar)
            .filter { Reminders.habitTarget(for: $0.identifier)?.day == "2026-08-09" }.count, 2)
    }

    func testDisabledAndArchivedItemsDoNotScheduleTheirStoredTimes() {
        var disabled = habit(), archived = habit()
        disabled.notificationMode = .off
        archived.archivedAt = "2026-08-09"
        XCTAssertTrue(Reminders.habitPlans(habits: [disabled, archived], now: date(), calendar: calendar).isEmpty)
    }

    func testQuantityNotificationActionsWorkUntilTheTargetIsReached() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notification-quantity-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url)
        var value = habit()
        value.recurrence = Recurrence(target: 3)
        store.add(value)
        store.setValue(value.id, day: "2026-08-09", value: 1)
        let target = NotificationHabitTarget(habitID: value.id, day: "2026-08-09")
        XCTAssertTrue(Reminders.applyQuickAction(.quantity, to: store.habits[0], target: target,
                                                 store: store, now: date(), calendar: calendar))
        XCTAssertEqual(store.value(value.id, day: target.day), 2)
        XCTAssertTrue(Reminders.applyQuickAction(.quantity, to: store.habits[0], target: target,
                                                 store: store, now: date(), calendar: calendar))
        XCTAssertEqual(store.value(value.id, day: target.day), 3)
        XCTAssertFalse(Reminders.applyQuickAction(.quantity, to: store.habits[0], target: target,
                                                  store: store, now: date(), calendar: calendar))
    }

    func testBudgetCountsTimesAndKeepsTheNearestAlertsAcrossItems() {
        let values = (0..<20).map { index -> Habit in
            var value = habit(times: [9 * 60, 10 * 60, 11 * 60])
            value.name = "Item \(index)"
            return value
        }
        for reserve in [false, true] {
            let plans = Reminders.habitPlans(habits: values, reservingMotivation: reserve, now: date(), calendar: calendar)
            XCTAssertLessThanOrEqual(plans.count + Reminders.fixedRequestEstimate(reservingMotivation: reserve), 64)
            XCTAssertEqual(Set(plans.compactMap { Reminders.habitTarget(for: $0.identifier)?.habitID }), Set(values.map(\.id)))
            XCTAssertEqual(plans.prefix(20).map { $0.dateMatching.hour }, Array(repeating: 9, count: 20))
        }
    }

    func testRecurrenceTimezoneAndTimeSensitiveModeApplyToEveryAlert() {
        var value = habit()
        value.recurrence = Recurrence(frequency: .weekly, weekdays: [1])
        value.timeZoneIdentifier = "Asia/Tokyo"
        value.notificationMode = .timeSensitive
        let plans = Reminders.habitPlans(habits: [value], now: date(hour: 0), calendar: calendar)
        var local = calendar
        local.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertFalse(plans.isEmpty)
        for plan in plans {
            XCTAssertEqual(plan.dateMatching.timeZone, local.timeZone)
            XCTAssertTrue([9, 17].contains(plan.dateMatching.hour!))
            XCTAssertTrue(plan.timeSensitive)
            XCTAssertEqual(local.component(.weekday, from: local.date(from: plan.dateMatching)!), 1)
        }
    }

    func testNewerMetadataCanRemoveTimesDuringSyncAndExport() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notification-times-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url)
        store.add(habit())
        var remote = store.habits[0]
        remote.notificationTimes = []
        remote.updatedAt = (remote.updatedAt ?? 0) + 10
        store.merge(remote: HabitData(version: HabitData.currentVersion, updatedAt: store.data.updatedAt + 10,
                                     summaryMinutes: nil, habits: [remote]))
        XCTAssertEqual(HabitStore(url: url).habits[0].notificationTimes, [])
        let exported = try JSONDecoder().decode(HabitData.self, from: XCTUnwrap(store.exportJSON()))
        XCTAssertEqual(exported.habits[0].notificationTimes, [])
    }

    func testExternalCheckInRemovesEveryOldTimeAndReplansOnlyFutureDays() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notification-reconcile-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url)
        let value = habit()
        store.add(value)
        let before = Reminders.habitPlans(habits: [value], now: date(), calendar: calendar).map(\.identifier)
        store.setValue(value.id, day: "2026-08-09", value: 1)
        let update = try XCTUnwrap(Reminders.externalCheckInReconciliation(store: store, habitID: value.id,
                                                                          pendingIdentifiers: before,
                                                                          now: date(), calendar: calendar))
        XCTAssertEqual(Set(update.removeIdentifiers), Set(before))
        XCTAssertFalse(update.addPlans.contains { Reminders.habitTarget(for: $0.identifier)?.day == "2026-08-09" })
        XCTAssertTrue(update.addPlans.contains { Reminders.habitTarget(for: $0.identifier)?.day == "2026-08-10" })
    }
}
