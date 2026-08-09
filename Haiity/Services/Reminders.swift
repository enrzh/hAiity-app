import Foundation
import UserNotifications

/// Benachrichtigungs-Politik (aus aiity übernommen): gefragt wird NUR, wenn
/// der Nutzer gerade aktiv eine Erinnerung einschaltet. Nie beim Start.
enum ReminderGate {
    enum Decision { case post, ask, refuse }

    static func decision(for status: UNAuthorizationStatus) -> Decision {
        switch status {
        case .authorized, .provisional, .ephemeral: return .post
        case .notDetermined: return .ask
        case .denied: return .refuse
        @unknown default: return .refuse
        }
    }
}

enum Reminders {
    static let summaryId = "summary"

    static func habitId(_ id: UUID) -> String { "habit-\(id.uuidString)" }

    /// Wird beim Einschalten einer Erinnerung aufgerufen — der einzige Ort,
    /// der den System-Dialog auslösen darf. Liefert false bei Ablehnung.
    static func ensurePermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch ReminderGate.decision(for: settings.authorizationStatus) {
        case .post: return true
        case .refuse: return false
        case .ask:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    /// Plant alle Habit-Erinnerungen und die Abend-Zusammenfassung neu.
    /// Idempotent: erst alle eigenen Pending-Requests entfernen, dann setzen.
    static func reschedule(habits: [Habit], summaryMinutes: Int?, openToday: [Habit]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard ReminderGate.decision(for: settings.authorizationStatus) == .post else { return }

        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0 == summaryId || $0.hasPrefix("habit-") }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        for h in habits {
            guard let minutes = h.reminderMinutes else { continue }
            let content = UNMutableNotificationContent()
            content.title = h.emoji.isEmpty ? h.name : "\(h.emoji) \(h.name)"
            content.body = String(localized: "Kleiner Schritt, volle Zelle.")
            content.sound = .default
            var c = DateComponents()
            c.hour = minutes / 60
            c.minute = minutes % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: c, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: habitId(h.id), content: content, trigger: trigger))
        }

        // Abend-Zusammenfassung: nicht-wiederholend mit aktuellem Stand,
        // wird nach jedem Toggle neu geplant; entfällt, wenn alles erledigt.
        if let minutes = summaryMinutes, !openToday.isEmpty {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "hAiity")
            content.body = String(localized: "\(openToday.count) Gewohnheit(en) heute noch offen.")
            content.sound = .default
            let now = Date()
            let cal = Calendar.current
            var c = cal.dateComponents([.year, .month, .day], from: now)
            c.hour = minutes / 60
            c.minute = minutes % 60
            if let fire = cal.date(from: c), fire > now {
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
                    repeats: false)
                try? await center.add(UNNotificationRequest(identifier: summaryId, content: content, trigger: trigger))
            }
        }
    }
}
