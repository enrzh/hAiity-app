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

/// Ein geplanter Weckruf als reine DATEN — ohne
/// `UNUserNotificationCenter`. Genau hier sitzt die Entscheidung, ob ein
/// Habit täglich oder wöchentlich klingelt; als Wert ist sie prüfbar, ohne
/// dass ein Test dem Benachrichtigungssystem eine Berechtigung vorspielen
/// müsste (die es im Simulator ohnehin nicht gibt).
struct ReminderPlan: Equatable {
    var identifier: String
    var title: String
    var body: String
    /// Was der `UNCalendarNotificationTrigger` abgleicht. Ohne `weekday`
    /// passt es auf JEDEN Tag zur genannten Uhrzeit (täglich), mit
    /// `weekday` nur auf diesen einen Wochentag (wöchentlich).
    var dateMatching: DateComponents
    var repeats: Bool

    var isWeekly: Bool { dateMatching.weekday != nil }
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

    // MARK: – Planung (pur)

    /// Der Weckruf eines Habits, oder nil, wenn keiner ansteht.
    ///
    /// Zwei Trigger-Formen aus EINER Regel: hat das Habit eine Wochen-Kadenz
    /// MIT festem Tag, wird `weekday` mit abgeglichen — der Trigger feuert
    /// dann wöchentlich an genau diesem Tag. Ohne festen Tag bleibt es beim
    /// täglichen Abgleich auf Stunde und Minute. („3× pro Woche" bleibt
    /// bewusst täglich: welche drei Tage das sind, entscheidet der Nutzer,
    /// die Erinnerung soll ihn an allen erwischen.)
    ///
    /// Archivierte Habits klingeln nicht — sie sind aus Liste, Widget und
    /// Zusammenfassung verschwunden, eine Erinnerung wäre ein Geist.
    static func plan(for habit: Habit) -> ReminderPlan? {
        guard let minutes = habit.reminderMinutes, habit.archivedAt == nil,
              (0..<24 * 60).contains(minutes) else { return nil }
        var c = DateComponents()
        c.hour = minutes / 60
        c.minute = minutes % 60
        if case .weekly = habit.goal.cadence, let weekday = habit.goal.weekday {
            c.weekday = weekday
        }
        return ReminderPlan(identifier: habitId(habit.id),
                            title: habit.emoji.isEmpty ? habit.name : "\(habit.emoji) \(habit.name)",
                            body: String(localized: "Kleiner Schritt, volle Zelle."),
                            dateMatching: c,
                            repeats: true)
    }

    /// Die Abend-Zusammenfassung: nicht-wiederholend mit dem aktuellen
    /// Stand, wird nach jedem Toggle neu geplant. Entfällt, wenn nichts mehr
    /// offen ist oder die Uhrzeit heute schon vorbei ist.
    static func summaryPlan(minutes: Int?,
                            openCount: Int,
                            now: Date = Date(),
                            calendar: Calendar = .current) -> ReminderPlan? {
        guard let minutes, openCount > 0, (0..<24 * 60).contains(minutes) else { return nil }
        var c = calendar.dateComponents([.year, .month, .day], from: now)
        c.hour = minutes / 60
        c.minute = minutes % 60
        guard let fire = calendar.date(from: c), fire > now else { return nil }
        return ReminderPlan(identifier: summaryId,
                            title: String(localized: "hAiity"),
                            body: String(localized: "\(openCount) Gewohnheit(en) heute noch offen."),
                            dateMatching: calendar.dateComponents(
                                [.year, .month, .day, .hour, .minute], from: fire),
                            repeats: false)
    }

    // MARK: – Ausführung

    /// Plant alle Habit-Erinnerungen und die Abend-Zusammenfassung neu.
    /// Idempotent: erst alle eigenen Pending-Requests entfernen, dann setzen.
    static func reschedule(habits: [Habit], summaryMinutes: Int?, openToday: [Habit]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard ReminderGate.decision(for: settings.authorizationStatus) == .post else { return }

        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0 == summaryId || $0.hasPrefix("habit-") }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        var plans = habits.compactMap(plan(for:))
        if let summary = summaryPlan(minutes: summaryMinutes, openCount: openToday.count) {
            plans.append(summary)
        }
        for plan in plans {
            try? await center.add(request(plan))
        }
    }

    private static func request(_ plan: ReminderPlan) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: plan.dateMatching,
                                                    repeats: plan.repeats)
        return UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
    }
}
