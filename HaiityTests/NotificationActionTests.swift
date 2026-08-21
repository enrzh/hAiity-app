import XCTest
@testable import Haiity

final class NotificationActionTests: XCTestCase {
    func testNotificationDelegateOnlyPersistsAppOpeningActions() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Services/NotificationPresenter.swift"))

        XCTAssertTrue(source.contains("NotificationActionRouter.post"))
        XCTAssertFalse(source.contains("NotificationActionRouter.deliverPending()"),
                       "UIKit notification callbacks must never drive SwiftUI presentation")
        XCTAssertFalse(source.contains("MainActor.run"),
                       "notification actions must not enter the main actor during UIKit state restoration")
        XCTAssertTrue(source.contains("return"),
                      "the delegate should return after persisting an app-opening action")
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
            "Haiity/Views/MoreView.swift"))
        let binding = try XCTUnwrap(source.range(of: "private func notificationActionBinding"))
        let body = source[binding.lowerBound..<source.endIndex]

        XCTAssertTrue(body.contains("NotificationPresenter.configureQuickActions"),
                      "changing a slot must update already scheduled notification menus")
    }

    func testNotificationSettingsShowUniqueChoicesAndTypeAwarePreview() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/MoreView.swift"))

        XCTAssertTrue(source.contains("availableChoices(for: index)"))
        XCTAssertTrue(source.contains("notification-actions-preview"))
        XCTAssertTrue(source.contains("notificationPreviewRow(String(localized: \"Abhaken\"), base: .checkbox)"))
        XCTAssertTrue(source.contains("notificationPreviewRow(String(localized: \"Ja/Nein\"), base: .yesNo)"))
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

        XCTAssertTrue(startup.contains("nativeTab = .more\n                presentMoreSheet(.habitBehavior)"),
                      "the iOS 26 sheet is attached to the More tab")
    }
}
