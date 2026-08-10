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

    /// Präfix der VORAUS geplanten Tagesmeldungen (ein Wecker je kommendem
    /// Tag mit Terminen). Die einmalige `summaryId`-Meldung trägt den Stand
    /// von HEUTE — aber sie existiert nur, wenn die App am selben Tag vor der
    /// Uhrzeit lief. Wer die App drei Tage nicht öffnet, bekam bis v11 in
    /// diesen drei Tagen GAR NICHTS: genau das gemeldete „Benachrichtigungen
    /// kommen nicht". Deshalb stellt `reschedule` zusätzlich für jeden der
    /// nächsten Tage, an dem laut Regel etwas ansteht, einen Wecker mit dem
    /// prospektiven Satz („Heute fällig: …"). Öffnet die App vorher, werden
    /// sie mit frischem Stand ersetzt; Tage ohne Termin bekommen weiterhin
    /// bewusst keinen.
    static let upcomingPrefix = "summary-day-"
    static let upcomingDays = 7

    /// Kennung der Test-Mitteilung (Mehr → „Test-Mitteilung").
    static let testId = "summary-test"

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

    /// Die vorausgeplanten Tagesmeldungen: für jeden der nächsten
    /// `upcomingDays` Tage, an dem laut Wiederholungsregel mindestens ein
    /// aktiver Habit ansteht, ein einmaliger Wecker zur Tageszeit der
    /// Zusammenfassung. Pur und damit prüfbar; heute selbst deckt weiterhin
    /// `dailySummaryPlan` mit dem ECHTEN Stand ab.
    static func upcomingDailyPlans(minutes: Int?,
                                   habits: [Habit],
                                   now: Date = Date(),
                                   calendar: Calendar = .current) -> [ReminderPlan] {
        guard let minutes, (0..<24 * 60).contains(minutes) else { return [] }
        let active = habits.filter { $0.archivedAt == nil }
        guard !active.isEmpty else { return [] }
        var plans: [ReminderPlan] = []
        var day = DayKey.key(for: now, calendar: calendar)
        for _ in 0..<upcomingDays {
            guard let next = DayKey.shifted(day, by: 1, calendar: calendar) else { break }
            day = next
            let due = active
                .filter { GoalEngine.isScheduled(habit: $0, day: day, calendar: calendar) }
                .map(\.name)
            guard let body = SummaryText.upcoming(due, locale: calendar.locale ?? .current),
                  let date = DayKey.date(from: day, calendar: calendar) else { continue }
            var c = calendar.dateComponents([.year, .month, .day], from: date)
            c.hour = minutes / 60
            c.minute = minutes % 60
            plans.append(ReminderPlan(identifier: upcomingPrefix + day,
                                      title: String(localized: "Heute"),
                                      body: body,
                                      dateMatching: c,
                                      repeats: false))
        }
        return plans
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
            $0 == summaryId || $0 == weeklySummaryId
                || $0.hasPrefix(legacyHabitPrefix) || $0.hasPrefix(upcomingPrefix)
        }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        // Die Voraus-Wecker lesen ihren Stoff selbst von der Platte — die
        // Aufrufer geben nur die beiden Zusammenfassungen mit, und dieselbe
        // data.json ist ohnehin die einzige Wahrheit (auch fürs Widget).
        var plans = [daily, weekly].compactMap { $0 }
        if let data = HabitStore.read(SharedStorage.dataURL()) {
            plans += upcomingDailyPlans(minutes: data.summaryMinutes, habits: data.habits)
        }
        for plan in plans {
            try? await center.add(request(plan))
        }
    }

    /// Eine Probemeldung in `seconds` Sekunden — der sichtbare Beweis, dass
    /// die Kette bis zum Banner reicht. false, wenn die Berechtigung fehlt.
    static func scheduleTest(after seconds: TimeInterval = 10) async -> Bool {
        guard await ensurePermission() else { return false }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Test-Mitteilung")
        content.body = String(localized: "So sieht eine Zusammenfassung von hAiity aus.")
        content.sound = .default
        center.removePendingNotificationRequests(withIdentifiers: [testId])
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: testId,
                                                    content: content,
                                                    trigger: trigger))
        return true
    }

    static func request(_ plan: ReminderPlan) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: plan.dateMatching,
                                                    repeats: plan.repeats)
        return UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
    }
}

/// Ohne Delegat wirft iOS geplante Mitteilungen WEG, solange die App vorne
/// ist — wer die Zusammenfassung einschaltet und zum Testen in der App auf
/// die Uhrzeit wartet, sieht: nichts. Genau so wurde v11 als „Mitteilungen
/// funktionieren nicht" gemeldet. Der Delegat sagt dem System, dass Banner,
/// Ton und Mitteilungsliste auch im Vordergrund gelten.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
