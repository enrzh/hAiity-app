import XCTest
@testable import Haiity

final class NotificationActionTests: XCTestCase {
    private let berlinCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = Locale(identifier: "de_DE")
        return calendar
    }()

    func testNotificationDelegateOnlyPersistsAppOpeningActions() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Services/NotificationPresenter.swift"))

        XCTAssertTrue(source.contains("NotificationActionRouter.post"))
        XCTAssertFalse(source.contains("NotificationActionRouter.deliverPending()"),
                       "UIKit notification callbacks must never drive SwiftUI presentation")
        XCTAssertTrue(source.contains("withCompletionHandler"),
                      "the bare async delegate variant lets UIKit's completion "
                    + "machinery run off-main — the Build 75/82 SIGABRT")
        XCTAssertFalse(source.contains("didReceive response: UNNotificationResponse) async"),
                       "the async delegate signature IS the crash; keep the completion variant")
        XCTAssertTrue(source.contains("return"),
                      "the delegate should return after persisting an app-opening action")
        XCTAssertTrue(source.contains("noteBackgroundNotificationAction()"),
                      "a panel action that does not open the app must suppress the delivered-notification wipe")
    }

    func testPanelActionKeepsTheAppClosedAndLeavesOtherNotifications() {
        DeliveredNotificationCleanup.resetForTests()
        defer { DeliveredNotificationCleanup.resetForTests() }

        XCTAssertTrue(NotificationPresenter.keepsAppClosed(
            actionIdentifier: NotificationQuickAction.checkbox.responseIdentifier,
            categoryIdentifier: NotificationQuickAction.checkbox.categoryIdentifier))
        XCTAssertTrue(NotificationPresenter.keepsAppClosed(
            actionIdentifier: UNNotificationDismissActionIdentifier,
            categoryIdentifier: NotificationQuickAction.reminder.categoryIdentifier))
        XCTAssertFalse(NotificationPresenter.keepsAppClosed(
            actionIdentifier: NotificationQuickAction.edit.responseIdentifier,
            categoryIdentifier: NotificationQuickAction.checkbox.categoryIdentifier))
        XCTAssertFalse(NotificationPresenter.keepsAppClosed(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            categoryIdentifier: NotificationQuickAction.checkbox.categoryIdentifier))

        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        DeliveredNotificationCleanup.noteBackgroundNotificationAction(now: now)
        XCTAssertFalse(DeliveredNotificationCleanup.shouldClear(
            applicationIsActive: true,
            now: now.addingTimeInterval(0.2)),
                       "acting on one notification must not clear the rest while the app stays closed")
        XCTAssertFalse(DeliveredNotificationCleanup.shouldClear(
            applicationIsActive: false,
            now: now.addingTimeInterval(5)),
                       "a background wake is not an app open")
        XCTAssertTrue(DeliveredNotificationCleanup.shouldClear(
            applicationIsActive: true,
            now: now.addingTimeInterval(2)),
                       "a later real foreground open still clears delivered notifications")
    }

    func testSceneCreationDoesNotClearDeliveredNotifications() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(contentsOf: root.appendingPathComponent("Haiity/HaiityApp.swift"))
        let appear = try XCTUnwrap(app.range(of: ".onAppear {"))
        let afterAppear = try XCTUnwrap(app.range(of: ".onChange(of: scenePhase)",
                                                  range: appear.upperBound..<app.endIndex))
        let appearBody = app[appear.lowerBound..<afterAppear.lowerBound]
        XCTAssertFalse(appearBody.contains("removeAllDeliveredNotifications"),
                       "building the scene on a notification wake must not clear every delivered notification")
        XCTAssertTrue(app.contains("clearDeliveredIfUserIsInTheApp()"))
        XCTAssertTrue(app.contains("DeliveredNotificationCleanup.settleDelay"))
    }

    /// Der EINE erlaubte Haupt-Actor-Sprung: UIKit seine Completion
    /// zurückgeben (das MUSS auf dem Hauptthread geschehen, sonst wirft
    /// `_performBlockAfterCATransactionCommitSynchronizes`). Alles andere —
    /// Store-Mutationen, Neuplanung — bleibt außerhalb.
    func testMainActorHopWrapsOnlyTheCompletionCall() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Services/NotificationPresenter.swift"))

        let hop = try XCTUnwrap(source.range(of: "MainActor.run"),
                                "the delegate must complete on the main actor")
        XCTAssertNil(source.range(of: "MainActor.run",
                                  range: hop.upperBound..<source.endIndex),
                     "processing must stay off the main actor during restoration")

        let tail = source[hop.lowerBound...]
        let closingBrace = try XCTUnwrap(tail.firstIndex(of: "}"))
        XCTAssertTrue(tail[..<closingBrace].contains("completionHandler()"),
                      "the main-actor hop exists solely to call the completion handler")
    }

    func testAppOpeningActionIsNotDeliveredSynchronously() {
        let request = NotificationActionRequest(
            action: .edit,
            target: NotificationHabitTarget(
                habitID: UUID(),
                day: "2026-08-20"))
        _ = NotificationActionRouter.takePending()

        var received = false
        let observer = NotificationCenter.default.addObserver(
            forName: NotificationActionRouter.pendingDidChange,
            object: nil,
            queue: nil) { _ in
                received = true
            }
        defer {
            NotificationCenter.default.removeObserver(observer)
            _ = NotificationActionRouter.takePending()
        }

        NotificationActionRouter.post(request)

        XCTAssertFalse(received,
                       "notification actions must not synchronously interrupt UIKit state restoration")
    }

    func testConfiguredSlotsResolveToThreeUniqueActionsPerHabitKind() {
        let habit = Habit(name: "Lesen", timeMinutes: 18 * 60,
                          recurrence: .daily)

        XCTAssertEqual(NotificationQuickAction.actions(
            for: habit,
            choices: [.primary, .secondary, .archive]),
                       [.checkbox, .reset, .archive])
    }

    func testNoneSlotsAreNotRegisteredAndResponseIdentifiersAreDistinct() {
        let habit = Habit(name: "Lesen", timeMinutes: 18 * 60,
                          recurrence: .daily)
        let actions = NotificationQuickAction.actions(
            for: habit,
            choices: [.primary, .none, .none])

        XCTAssertEqual(actions, [.checkbox])
        XCTAssertNotEqual(NotificationQuickAction.checkbox.responseIdentifier,
                           NotificationQuickAction.reset.responseIdentifier)
    }

    func testNotificationSlotChoicesExcludeActionsAlreadyAssignedElsewhere() {
        let preferences = NotificationActionPreferences(
            slots: [.primary, .secondary, .none])

        XCTAssertEqual(Set<SwipeActionChoice>(preferences.availableChoices(for: 0)),
                       Set<SwipeActionChoice>([.primary, .archive, .backfill, .session, .edit, .none]))
        XCTAssertEqual(Set<SwipeActionChoice>(preferences.availableChoices(for: 1)),
                       Set<SwipeActionChoice>([.secondary, .archive, .backfill, .session, .edit, .none]))
        XCTAssertTrue(preferences.availableChoices(for: 2).contains(.none),
                      "multiple disabled slots must remain possible")
        XCTAssertFalse(preferences.availableChoices(for: 2).contains(.primary))
        XCTAssertFalse(preferences.availableChoices(for: 2).contains(.secondary))
    }

    func testAssigningAnActionClearsItsPreviousSlot() {
        var preferences = NotificationActionPreferences(
            slots: [.archive, .secondary, .none])

        preferences.assign(.archive, to: 1)

        XCTAssertEqual(preferences.slots, [.none, .archive, .none])
    }

    func testCategoryDefinitionsContainTheConfiguredActionsForEachHabitKind() {
        let categories = NotificationPresenter.notificationCategories(
            enabled: true,
            choices: [.primary, .secondary, .archive])
        let checkbox = categories.first {
            $0.identifier == NotificationQuickAction.checkbox.categoryIdentifier
        }

        XCTAssertEqual(checkbox?.actions.map(\.identifier), [
            NotificationQuickAction.checkbox.responseIdentifier,
            NotificationQuickAction.reset.responseIdentifier,
            NotificationQuickAction.archive.responseIdentifier
        ])
    }

    func testRescheduleReportsFailedPlanAddsInsteadOfDroppingThem() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Services/Reminders.swift"))
        let start = try XCTUnwrap(source.range(of: "static func reschedule(daily:"))
        let end = try XCTUnwrap(source.range(of: "static func reschedule(store:",
                                             range: start.upperBound..<source.endIndex))
        let body = source[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(body.contains("schedulePlans"),
                      "reschedule should use the shared reporting path for plan adds")
        XCTAssertTrue(body.contains("logScheduleFailure"),
                      "a failed notification add must remain visible to the app")
        XCTAssertFalse(body.contains("try? await center.add(request(plan))"),
                       "a silently dropped plan leaves the user without a reminder")
    }

    func testSchedulePlansReportsEveryFailedAddAndContinues() async {
        enum StubFailure: Error { case failed }

        let plans = [
            ReminderPlan(identifier: "first", title: "A", body: "A",
                         dateMatching: DateComponents(day: 1), repeats: false),
            ReminderPlan(identifier: "second", title: "B", body: "B",
                         dateMatching: DateComponents(day: 2), repeats: false)
        ]
        var added: [String] = []
        var failures: [String] = []

        await Reminders.schedulePlans(
            plans,
            addPlan: { plan in
                added.append(plan.identifier)
                if plan.identifier == "first" { throw StubFailure.failed }
            },
            logFailure: { _, identifier, context in
                XCTAssertEqual(context, "reschedule")
                failures.append(identifier)
            })

        XCTAssertEqual(added, ["first", "second"])
        XCTAssertEqual(failures, ["first"])
    }

    func testLegacyResponseIdentifierStillResolvesFromItsOldCategory() {
        XCTAssertEqual(NotificationQuickAction.responseAction(
            identifier: NotificationQuickAction.actionIdentifier,
            categoryIdentifier: NotificationQuickAction.archive.categoryIdentifier),
                       .archive)
    }

    func testChangingNotificationSlotReRegistersCategoriesImmediately() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/MoreNotifications.swift"), encoding: .utf8)
        let binding = try XCTUnwrap(source.range(of: "func notificationActionBinding"))
        let body = source[binding.lowerBound..<source.endIndex]

        XCTAssertTrue(body.contains("NotificationPresenter.configureQuickActions"),
                      "changing a slot must update already scheduled notification menus")
    }

    func testCloudNotificationPreferencesReRegisterCategoriesAfterAdoption() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/ContentView.swift"))
        let adoption = "viewPreferences.adoptRemote(store.data.viewPreferences)"
        let segments = source.components(separatedBy: adoption).dropFirst()
        XCTAssertFalse(segments.isEmpty)
        XCTAssertTrue(segments.allSatisfy { $0.prefix(240).contains(
            "NotificationPresenter.configureQuickActions") },
                      "remote notification slots must reach the system category registry")
    }

    func testNotificationSettingsShowUniqueChoicesAndTypeAwarePreview() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/MoreNotifications.swift"), encoding: .utf8)
        let host = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/MoreBehavior.swift"), encoding: .utf8)
        let behaviorStart = try XCTUnwrap(host.range(of: "var habitBehaviorSettings: some View"))
        let behaviorEnd = try XCTUnwrap(host.range(of: "var cloudSyncSection: some View",
                                                  range: behaviorStart.upperBound..<host.endIndex))
        XCTAssertTrue(host[behaviorStart.lowerBound..<behaviorEnd.lowerBound].contains("notificationActionsSection"))

        XCTAssertTrue(source.contains("availableChoices(for: index)"))
        XCTAssertTrue(source.contains("notification-actions-preview"))
        XCTAssertTrue(source.contains("notificationPreviewRow(String(localized: \"Abhaken\"), base: .checkbox)"))
        XCTAssertTrue(source.contains("notificationPreviewRow(String(localized: \"Ja/Nein\"), base: .yesNo)"))
    }

    func testExternalCheckInReconciliationRefreshesUpcomingSummaryPlans() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notification-upcoming-refresh-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url)
        store.summaryMinutes = 20 * 60

        let daily = Habit(name: "Water plants", recurrence: .daily)
        let monday = Habit(name: "Stretch", recurrence: .weekdays([2]))
        store.add(daily)
        store.add(monday)

        let now = try XCTUnwrap(berlinCalendar.date(from: DateComponents(
            year: 2026, month: 8, day: 17, hour: 7, minute: 30)))
        let update = try XCTUnwrap(Reminders.externalCheckInReconciliation(
            store: store,
            habitID: daily.id,
            pendingIdentifiers: [
                Reminders.summaryId,
                Reminders.habitReminderIdentifier(habitID: daily.id, day: "2026-08-17"),
                Reminders.upcomingPrefix + "2026-08-18",
                Reminders.upcomingPrefix + "2026-08-19",
                Reminders.upcomingPrefix + "2026-08-24"
            ],
            now: now,
            calendar: berlinCalendar))

        XCTAssertEqual(Set(update.pendingUpcomingIdentifiers), Set([
            Reminders.upcomingPrefix + "2026-08-18",
            Reminders.upcomingPrefix + "2026-08-19",
            Reminders.upcomingPrefix + "2026-08-24"
        ]))
        XCTAssertEqual(Set(update.upcomingPlans.map(\.identifier)), Set([
            Reminders.upcomingPrefix + "2026-08-18",
            Reminders.upcomingPrefix + "2026-08-19",
            Reminders.upcomingPrefix + "2026-08-20",
            Reminders.upcomingPrefix + "2026-08-21",
            Reminders.upcomingPrefix + "2026-08-22",
            Reminders.upcomingPrefix + "2026-08-23",
            Reminders.upcomingPrefix + "2026-08-24"
        ]))
    }

    func testUpcomingSummaryRefreshRemovesObsoleteIdsOnlyAfterAllAddsSucceed() async {
        let desired = [
            ReminderPlan(identifier: Reminders.upcomingPrefix + "2026-08-18",
                         title: "Heute",
                         body: "Heute fällig: Water plants",
                         dateMatching: DateComponents(year: 2026, month: 8, day: 18, hour: 20),
                         repeats: false),
            ReminderPlan(identifier: Reminders.upcomingPrefix + "2026-08-19",
                         title: "Heute",
                         body: "Heute fällig: Water plants",
                         dateMatching: DateComponents(year: 2026, month: 8, day: 19, hour: 20),
                         repeats: false)
        ]
        var added: [String] = []
        var removed: [String] = []
        var failures: [String] = []

        await Reminders.refreshUpcomingSummaryPlans(
            pendingIdentifiers: [
                Reminders.upcomingPrefix + "2026-08-18",
                Reminders.upcomingPrefix + "2026-08-17"
            ],
            desiredPlans: desired,
            addPlan: { plan in
                added.append(plan.identifier)
            },
            removePending: { identifiers in
                removed = identifiers
            },
            logFailure: { _, identifier, _ in
                failures.append(identifier)
            })

        XCTAssertEqual(added, desired.map(\.identifier))
        XCTAssertEqual(removed, [Reminders.upcomingPrefix + "2026-08-17"])
        XCTAssertTrue(failures.isEmpty)
    }

    func testUpcomingSummaryRefreshKeepsOldIdsAndReportsFailureWhenAnyAddFails() async {
        enum StubFailure: Error { case failed }

        let desired = [
            ReminderPlan(identifier: Reminders.upcomingPrefix + "2026-08-18",
                         title: "Heute",
                         body: "Heute fällig: Water plants",
                         dateMatching: DateComponents(year: 2026, month: 8, day: 18, hour: 20),
                         repeats: false),
            ReminderPlan(identifier: Reminders.upcomingPrefix + "2026-08-19",
                         title: "Heute",
                         body: "Heute fällig: Water plants",
                         dateMatching: DateComponents(year: 2026, month: 8, day: 19, hour: 20),
                         repeats: false)
        ]
        var added: [String] = []
        var removed: [String] = []
        var failures: [String] = []

        await Reminders.refreshUpcomingSummaryPlans(
            pendingIdentifiers: [
                Reminders.upcomingPrefix + "2026-08-18",
                Reminders.upcomingPrefix + "2026-08-17"
            ],
            desiredPlans: desired,
            addPlan: { plan in
                added.append(plan.identifier)
                if plan.identifier == Reminders.upcomingPrefix + "2026-08-19" {
                    throw StubFailure.failed
                }
            },
            removePending: { identifiers in
                removed = identifiers
            },
            logFailure: { _, identifier, _ in
                failures.append(identifier)
            })

        XCTAssertEqual(added, desired.map(\.identifier))
        XCTAssertTrue(removed.isEmpty)
        XCTAssertEqual(failures, [Reminders.upcomingPrefix + "2026-08-19"])
    }

    func testNotificationDeliveryIssuePersistsUntilTheUiConsumesIt() {
        let suite = "NotificationActionTests.delivery-issue"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let center = NotificationCenter()
        let issue = NotificationDeliveryIssue(message: "retry me")
        var notifications = 0
        let observer = center.addObserver(
            forName: NotificationDeliveryIssueCenter.pendingDidChange,
            object: nil,
            queue: nil
        ) { _ in
            notifications += 1
        }
        defer { center.removeObserver(observer) }

        NotificationDeliveryIssueCenter.note(issue, defaults: defaults, center: center)

        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(NotificationDeliveryIssueCenter.takePending(defaults: defaults), issue)
        XCTAssertNil(NotificationDeliveryIssueCenter.takePending(defaults: defaults))
    }

    func testDeliveryIssueConsumerForwardsPersistedMessageAndClearsIt() {
        let suite = "NotificationActionTests.delivery-issue-consumer"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        NotificationDeliveryIssueCenter.note(
            NotificationDeliveryIssue(message: "retry me"),
            defaults: defaults,
            center: NotificationCenter())

        var messages: [String] = []
        XCTAssertTrue(NotificationDeliveryIssueCenter.deliverPendingMessage(defaults: defaults) {
            messages.append($0)
        })

        XCTAssertEqual(messages, ["retry me"])
        XCTAssertNil(NotificationDeliveryIssueCenter.takePending(defaults: defaults))
        XCTAssertFalse(NotificationDeliveryIssueCenter.deliverPendingMessage(defaults: defaults) { _ in
            XCTFail("no second message should be delivered after the first consumer clears it")
        })
    }

    func testDebugNotificationSettingsRouteIsScheduledBeforeBoot() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/ContentView.swift"))
        let task = try XCTUnwrap(source.range(of: ".task {"))
        let startup = source[task.lowerBound..<source.endIndex]
        let route = try XCTUnwrap(startup.range(of: "handleLaunchScreenArgument()"))
        let boot = try XCTUnwrap(startup.range(of: "await boot()"))

        XCTAssertLessThan(route.lowerBound, boot.lowerBound,
                          "the debug screen route must not wait for startup sync")

        let settingsStart = try XCTUnwrap(source.range(of: "if args[i + 1] == \"notification-actions\""))
        let settingsEnd = try XCTUnwrap(source.range(of: "if args[i + 1] == \"appearance\"",
                                                   range: settingsStart.upperBound..<source.endIndex))
        let settings = source[settingsStart.lowerBound..<settingsEnd.lowerBound]
        XCTAssertTrue(settings.contains("presentMoreSheet(.habitBehavior)"))
        XCTAssertTrue(settings.contains("guard routeToken == launchRouteToken else { return }"),
                      "a newer route must cancel delayed debug settings presentation")
        XCTAssertFalse(settings.contains("nativeTab ="), "settings must open on the current content tab")
        for write in ["store.", "updateCloudPreferences", "Reminders.ensurePermission", "CalendarSync.requestAccess"] {
            XCTAssertFalse(settings.contains(write), "debug navigation must not write preferences or request permission")
        }

        for tab in [AppTab.today, .habits, .stats, .search] {
            var work = RouteWork()
            let item = work.begin(AppRouteEffect(tab: tab, morePage: .habitBehavior,
                                                opensSearch: false, opensCreate: false))
            XCTAssertEqual(item.effect.tab, tab)
            var presentation = RoutePresentation()
            presentation.more = .presented
            presentation.morePage = .settings
            XCTAssertEqual(work.nextStep(for: item, presentation: presentation), .dismissMore)
            presentation.more = .dismissing
            XCTAssertEqual(work.nextStep(for: item, presentation: presentation), .waitForMoreDismissal)
            presentation.more = .absent
            XCTAssertEqual(work.nextStep(for: item, presentation: presentation), .apply)
            _ = work.begin(AppDestination.stats.effect)
            XCTAssertNil(work.nextStep(for: item, presentation: presentation),
                         "the superseded startup route must never reopen settings")
        }
    }
}
