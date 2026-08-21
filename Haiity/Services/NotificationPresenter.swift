import UIKit
import UserNotifications

/// Keeps notification UI delivery outside UIKit's notification callback.
/// Persisting first means a scene that is still restoring can consume the
/// action safely when it becomes active.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    static func configureQuickActions(
        enabled: Bool,
        choices: [SwipeActionChoice] = NotificationActionPreferences().slots
    ) {
        UNUserNotificationCenter.current().setNotificationCategories(
            notificationCategories(enabled: enabled, choices: choices))
    }

    static func notificationCategories(
        enabled: Bool,
        choices: [SwipeActionChoice]
    ) -> Set<UNNotificationCategory> {
        guard enabled else { return [] }

        return Set(NotificationQuickAction.habitCategoryBases.map { base in
            let buttons = NotificationQuickAction.actions(for: base, choices: choices)
                .map { action in
                    UNNotificationAction(identifier: action.responseIdentifier,
                                         title: action.title,
                                         options: action.opensApp ? [.foreground] : [])
                }
            return UNNotificationCategory(identifier: base.categoryIdentifier,
                                          actions: buttons,
                                          intentIdentifiers: [],
                                          options: [])
        })
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let action = NotificationQuickAction.responseAction(
                  identifier: response.actionIdentifier,
                  categoryIdentifier: response.notification.request.content.categoryIdentifier),
              let target = Reminders.habitTarget(
                for: response.notification.request.identifier) else { return }

        if action.opensApp {
            NotificationActionRouter.post(NotificationActionRequest(action: action,
                                                                     target: target))
            return
        }

        // Keep non-opening actions off the main actor as well. The delegate
        // can run while UIKit is restoring a scene; even a store mutation
        // that does not present a sheet can trigger SwiftUI observation and
        // the iOS 27 state-restoration assertion seen in build 75.
        let store = HabitStore(url: SharedStorage.dataURL())
        guard let habit = store.habits.first(where: { $0.id == target.habitID }) else { return }
        guard Reminders.applyQuickAction(action, to: habit, target: target, store: store) else {
            return
        }
        Task {
            await Reminders.reschedule(store: store)
            await Reminders.celebrateIfPerfectDay(store: store)
        }
    }
}
