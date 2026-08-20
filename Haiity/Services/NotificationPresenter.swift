import UIKit
import UserNotifications

/// Keeps notification UI delivery outside UIKit's notification callback.
/// Persisting first means a scene that is still restoring can consume the
/// action safely when it becomes active.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    static func configureQuickActions(enabled: Bool) {
        let categories: Set<UNNotificationCategory>
        if enabled {
            categories = Set(NotificationQuickAction.allCases.map { action in
                let button = UNNotificationAction(identifier: NotificationQuickAction.actionIdentifier,
                                                   title: action.title,
                                                   options: action.opensApp ? [.foreground] : [])
                return UNNotificationCategory(identifier: action.categoryIdentifier,
                                              actions: [button],
                                              intentIdentifiers: [],
                                              options: [])
            })
        } else {
            categories = []
        }
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == NotificationQuickAction.actionIdentifier,
              let target = Reminders.habitTarget(
                for: response.notification.request.identifier) else { return }

        guard let category = NotificationQuickAction(rawValue: response.notification
            .request.content.categoryIdentifier.replacingOccurrences(
                of: "haiity.notification.", with: "")) else { return }

        if category.opensApp {
            NotificationActionRouter.post(NotificationActionRequest(action: category,
                                                                     target: target))
            return
        }

        // Keep non-opening actions off the main actor as well. The delegate
        // can run while UIKit is restoring a scene; even a store mutation
        // that does not present a sheet can trigger SwiftUI observation and
        // the iOS 27 state-restoration assertion seen in build 75.
        let store = HabitStore(url: SharedStorage.dataURL())
        guard let habit = store.habits.first(where: { $0.id == target.habitID }) else { return }
        guard Reminders.applyQuickAction(category, to: habit, target: target, store: store) else {
            return
        }
        Task {
            await Reminders.reschedule(store: store)
            await Reminders.celebrateIfPerfectDay(store: store)
        }
    }
}
