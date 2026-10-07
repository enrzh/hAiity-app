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

    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    // Absichtlich die COMPLETION-Variante statt einer `async`-Methode:
    // beim `async`-Delegat läuft der compilererzeugte Abschlussaufruf auf
    // einem Nebenläufigkeitsthread, und UIKit wirft dort während der
    // State-Restoration eine Assertion (SIGABRT in Build 75 und 82,
    // `_performBlockAfterCATransactionCommitSynchronizes`). Die Arbeit
    // bleibt bewusst außerhalb des Haupt-Actors — nur der Abschluss wird
    // auf dem Haupt-Actor gefeuert.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // A check-off from the notification panel wakes this process without
        // showing the app. That wake must not take the "app opened" path,
        // which clears every delivered habit and reminder notification.
        if Self.keepsAppClosed(actionIdentifier: response.actionIdentifier,
                               categoryIdentifier: response.notification.request.content.categoryIdentifier) {
            DeliveredNotificationCleanup.noteBackgroundNotificationAction()
        }
        Task { [response] in
            await NotificationPresenter.process(response)
            await MainActor.run {
                completionHandler()
            }
        }
    }

    /// Tapping the notification itself opens the app. Action buttons that
    /// only record a state, and dismissing one banner, do not.
    static func keepsAppClosed(actionIdentifier: String, categoryIdentifier: String) -> Bool {
        if actionIdentifier == UNNotificationDefaultActionIdentifier { return false }
        guard let action = NotificationQuickAction.responseAction(
            identifier: actionIdentifier,
            categoryIdentifier: categoryIdentifier) else { return true }
        return !action.opensApp
    }

    private static func process(_ response: UNNotificationResponse) async {
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
        guard let habit = HabitVisibility.visibleActiveHabits(
            store.habits,
            unlocked: HabitVisibility.sharedEntitlementIsUnlocked)
            .first(where: { $0.id == target.habitID }) else { return }
        let calendar = HabitTimeZone.calendar(
            for: habit,
            defaultIdentifier: store.defaultTimeZoneIdentifier)
        guard Reminders.applyQuickAction(
            action,
            to: habit,
            target: target,
            store: store,
            defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier,
            calendar: calendar) else {
            return
        }
        Task {
            await Reminders.reschedule(store: store)
            await Reminders.celebrateIfPerfectDay(store: store)
        }
    }
}

/// Delivered notifications are cleared only after a person is actually in
/// the app. Scene creation and a notification-action wake both construct
/// the SwiftUI scene without that person opening hAiity.
enum DeliveredNotificationCleanup {
    private static let lock = NSLock()
    private static var suppressUntil = Date.distantPast

    /// Long enough for the notification delegate to mark a background action
    /// before a scene-phase `.active` callback decides to clear.
    static let settleDelay: Duration = .milliseconds(600)
    private static let suppressionWindow: TimeInterval = 1.5

    static func noteBackgroundNotificationAction(now: Date = .now) {
        lock.lock()
        suppressUntil = now.addingTimeInterval(suppressionWindow)
        lock.unlock()
    }

    static func shouldClear(applicationIsActive: Bool, now: Date = .now) -> Bool {
        guard applicationIsActive else { return false }
        lock.lock()
        let until = suppressUntil
        lock.unlock()
        return now >= until
    }

    @MainActor
    static func clearDeliveredIfUserIsInTheApp() {
        guard shouldClear(applicationIsActive: UIApplication.shared.applicationState == .active) else { return }
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    static func resetForTests() {
        lock.lock()
        suppressUntil = .distantPast
        lock.unlock()
    }
}
