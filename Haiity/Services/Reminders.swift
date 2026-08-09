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
/// `UNUserNotificationCenter`. Als Wert ist die Entscheidung prüfbar, ohne
/// dass ein Test dem Benachrichtigungssystem eine Berechtigung vorspielen
/// müsste (die es im Simulator ohnehin nicht gibt).
struct ReminderPlan: Equatable {
    var identifier: String
    var title: String
    var body: String
    /// Was der `UNCalendarNotificationTrigger` abgleicht. Ein vollständiges
    /// Datum (`year`) ist ein EINMALIGER Wecker, `weekday` + Uhrzeit ein
    /// wöchentlich wiederkehrender.
    var dateMatching: DateComponents
    var repeats: Bool

    var isWeekly: Bool { dateMatching.weekday != nil }
    /// Einmalig gestellt und bei jedem `reschedule` neu gesetzt.
    var isOneShot: Bool { !repeats }
}

/// Die beiden Zusammenfassungen — und sonst nichts.
///
/// **Was hier einmal stand und bewusst weg ist:** die EIGENE Erinnerung je
/// Habit (`plans(for:)`, ein Trigger pro Wochentag, Rückfallebene für
/// „am letzten Freitag"). Zehn Habits waren zehn Weckrufe, und keiner davon
/// wusste, ob der Tag schon erledigt war. Stattdessen fasst EINE Meldung am
/// Tag zusammen, was offen ist, und eine am Ende der Woche, was gehalten
/// wurde. `Habit.reminderMinutes` bleibt in der Datei stehen (siehe dort),
/// wird aber nirgends mehr ausgewertet — und alte, noch anstehende
/// Habit-Weckrufe räumt `reschedule` beim ersten Start weg.
enum Reminders {
    static let summaryId = "summary"
    static let weeklySummaryId = "summary-weekly"

    /// Präfix der bis v4 gestellten Habit-Weckrufe. Es gibt sie nicht mehr,
    /// aber sie liegen auf Geräten mit einem alten Build als anstehende
    /// Anfragen — ohne dieses Aufräumen klingelten sie ewig weiter.
    static let legacyHabitPrefix = "habit-"

    /// Wird beim Einschalten einer Zusammenfassung aufgerufen — der einzige
    /// Ort, der den System-Dialog auslösen darf. Liefert false bei Ablehnung.
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

    /// Die Tageszusammenfassung: EINMALIG mit dem aktuellen Stand, neu
    /// geplant nach jeder Änderung am Store (Abhaken, Anlegen, App-Start).
    /// Genau deshalb ist sie nicht wiederholend — eine wiederholende Meldung
    /// trüge auf ewig den Text von heute.
    ///
    /// Entfällt, wenn heute nichts fällig war oder die Uhrzeit heute schon
    /// vorbei ist.
    static func dailySummaryPlan(minutes: Int?,
                                 status: SummaryStatus,
                                 now: Date = Date(),
                                 calendar: Calendar = .current) -> ReminderPlan? {
        guard let minutes, (0..<24 * 60).contains(minutes),
              let body = SummaryText.daily(status, locale: calendar.locale ?? .current)
        else { return nil }
        var c = calendar.dateComponents([.year, .month, .day], from: now)
        c.hour = minutes / 60
        c.minute = minutes % 60
        guard let fire = calendar.date(from: c), fire > now else { return nil }
        return ReminderPlan(identifier: summaryId,
                            title: String(localized: "Heute"),
                            body: body,
                            dateMatching: calendar.dateComponents(
                                [.year, .month, .day, .hour, .minute], from: fire),
                            repeats: false)
    }

    /// Die Wochenzusammenfassung: Wochentag + Uhrzeit, WIEDERHOLEND. Anders
    /// als die Tagesmeldung soll sie auch dann kommen, wenn die App eine
    /// Woche lang nicht offen war — ein einmaliger Wecker wäre genau dann
    /// nicht gestellt. Der Text stammt vom letzten `reschedule`; er wird bei
    /// jedem Abhaken aufgefrischt.
    ///
    /// Entfällt, wenn in dieser Woche gar kein Termin fällig war.
    static func weeklySummaryPlan(minutes: Int?,
                                  weekday: Int,
                                  status: SummaryStatus,
                                  calendar: Calendar = .current) -> ReminderPlan? {
        guard let minutes, (0..<24 * 60).contains(minutes), (1...7).contains(weekday),
              let body = SummaryText.weekly(status, locale: calendar.locale ?? .current)
        else { return nil }
        return ReminderPlan(identifier: weeklySummaryId,
                            title: String(localized: "Diese Woche"),
                            body: body,
                            dateMatching: DateComponents(hour: minutes / 60,
                                                         minute: minutes % 60,
                                                         weekday: weekday),
                            repeats: true)
    }

    // MARK: – Ausführung

    /// Stellt die beiden Zusammenfassungen neu. Idempotent: erst alle eigenen
    /// Pending-Requests entfernen (die alten Habit-Weckrufe eingeschlossen),
    /// dann setzen.
    static func reschedule(daily: ReminderPlan?, weekly: ReminderPlan?) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard ReminderGate.decision(for: settings.authorizationStatus) == .post else { return }

        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter {
            $0 == summaryId || $0 == weeklySummaryId || $0.hasPrefix(legacyHabitPrefix)
        }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        for plan in [daily, weekly].compactMap({ $0 }) {
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
