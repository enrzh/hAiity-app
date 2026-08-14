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

enum ReminderSetup {
    static let completedKey = "reminder-setup-completed"

    static func shouldPresent(completed: Bool) -> Bool { !completed }
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

/// Plant tägliche und wöchentliche Zusammenfassungen, tägliche Motivation
/// sowie konkrete Erinnerungen für noch offene Habits. Habit-Erinnerungen
/// werden nur für anstehende Termine vorausgeplant und nach jedem App-Start
/// aktualisiert.
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

    /// Präfix der täglichen Motivationsnachricht — eine Anfrage JE TAG.
    ///
    /// Warum nicht eine wiederholende: ein `UNCalendarNotificationTrigger`
    /// mit `repeats: true` trägt seinen Text für immer. Der Vorrat wechselt
    /// aber täglich (`Motivation.message`), also stünde ein Jahr lang
    /// derselbe Satz auf dem Sperrbildschirm — genau der Fehler, den die
    /// Tageszusammenfassung schon einmal hatte. Deshalb je Tag ein eigener
    /// einmaliger Wecker, `motivationDays` im Voraus, bei jedem
    /// `reschedule` neu gestellt.
    static let motivationPrefix = "motivation-"
    static let motivationDays = 7

    static func motivationId(day: String) -> String { motivationPrefix + day }

    /// Kennung der Test-Mitteilung (Mehr → Über → Entwickler → „Test-Mitteilung").
    /// Sie steht nicht mehr in den Einstellungen: sie ist Diagnose, keine
    /// Einstellung, und wohnt darum hinter der versteckten Tür.
    static let testId = "summary-test"

    /// Präfix der bis v4 gestellten Habit-Weckrufe. Es gibt sie nicht mehr,
    /// aber sie liegen auf Geräten mit einem alten Build als anstehende
    /// Anfragen — ohne dieses Aufräumen klingelten sie ewig weiter.
    static let legacyHabitPrefix = "habit-"
    static let habitReminderPrefix = "habit-reminder-"
    static let sessionMilestonePrefix = "session-milestone-"
    /// Fenster der Habit-Weckrufe in TAGEN (heute + 8): deckt „nächste Woche,
    /// gleicher Wochentag" ab — ein 7-Tage-Fenster verlöre genau den
    /// wöchentlichen Termin, dessen diese Woche schon erledigt ist. Bei
    /// vielen Habits mit Uhrzeit schrumpft das Fenster (`reminderWindow`),
    /// damit das 64er-Budget des Systems nicht stumm überläuft.
    static let habitReminderDays = 9

    static func habitReminderIdentifier(habitID: UUID, day: String) -> String {
        "\(habitReminderPrefix)\(habitID.uuidString)-\(day)"
    }

    static func sessionMilestoneIdentifier(_ session: HabitSession) -> String {
        "\(sessionMilestonePrefix)\(session.id.uuidString)"
    }

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
        let active = habits.filter { $0.archivedAt == nil && $0.isTrackedHabit }
        guard !active.isEmpty else { return [] }
        var plans: [ReminderPlan] = []
        let today = DayKey.key(for: now, calendar: calendar)
        var day = today
        for _ in 0..<upcomingDays {
            guard let next = DayKey.shifted(day, by: 1, calendar: calendar) else { break }
            day = next
            let due = active
                .filter { reminderWorthy(habit: $0, day: day, today: today, calendar: calendar) }
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

    /// Die Motivationsnachricht: für heute und die nächsten Tage je ein
    /// einmaliger Wecker zur eingestellten Uhrzeit mit dem Satz DIESES
    /// Tages. Pur — der Name kommt als Argument herein, damit ein Test die
    /// Anrede prüfen kann, ohne die Defaults des Geräts anzufassen.
    ///
    /// Heute ist mit dabei, anders als bei `upcomingDailyPlans`: dort deckt
    /// `dailySummaryPlan` den heutigen Tag mit dem ECHTEN Stand ab, hier
    /// gibt es keinen Stand — nur den Satz. Ist die Uhrzeit für heute
    /// vorbei, fällt der Tag über `fire > now` von selbst heraus.
    static func motivationPlans(minutes: Int?,
                                name: String?,
                                days: Int = motivationDays,
                                now: Date = Date(),
                                calendar: Calendar = .current) -> [ReminderPlan] {
        guard let minutes, (0..<24 * 60).contains(minutes), days > 0 else { return [] }
        var plans: [ReminderPlan] = []
        var day = DayKey.key(for: now, calendar: calendar)
        for offset in 0 ..< days {
            if offset > 0 {
                guard let next = DayKey.shifted(day, by: 1, calendar: calendar) else { break }
                day = next
            }
            guard let date = DayKey.date(from: day, calendar: calendar) else { continue }
            var c = calendar.dateComponents([.year, .month, .day], from: date)
            c.hour = minutes / 60
            c.minute = minutes % 60
            // `fire > now` wirft den heutigen Tag heraus, wenn die Uhrzeit
            // schon vorbei ist. `date(from:)` kann bei einer übersprungenen
            // Stunde (Zeitumstellung) nil liefern — dann fällt genau dieser
            // Tag aus, statt dass die ganze Reihe abbricht.
            guard let fire = calendar.date(from: c), fire > now else { continue }
            let message = Motivation.message(name: name, today: day)
            plans.append(ReminderPlan(identifier: motivationId(day: day),
                                      title: message.title,
                                      body: message.body,
                                      dateMatching: c,
                                      repeats: false))
        }
        return plans
    }

    /// Verdient dieser Tag eine Erinnerung an dieses Habit?
    ///
    /// Feste Regeln: der Terminplan entscheidet. Flexible Regeln („n× pro
    /// Woche") sind laut `isScheduled` an JEDEM Tag der Periode „dran" —
    /// als Erinnerung wäre das ein täglicher Weckruf für ein Wochenziel
    /// (gemeldeter Fehler). Deshalb gilt zusätzlich:
    ///  * Ist eine Wochentags-Verabredung hinterlegt, wird nur an diesen
    ///    Tagen erinnert — genau wofür sie dokumentiert ist („steuert nur
    ///    die Erinnerung").
    ///  * Ist die Periode bereits erfüllt (3 von 3 geschafft), schweigt der
    ///    Rest der Periode.
    static func reminderWorthy(habit: Habit, day: String, today: String,
                               calendar: Calendar = .current) -> Bool {
        guard GoalEngine.isScheduled(habit: habit, day: day, calendar: calendar) else { return false }
        let recurrence = habit.recurrence
        guard recurrence.isFlexible else { return true }
        if !recurrence.weekdays.isEmpty {
            guard let date = DayKey.date(from: day, calendar: calendar),
                  recurrence.weekdays.contains(calendar.component(.weekday, from: date))
            else { return false }
        }
        return !GoalEngine.periodSatisfied(habit: habit, day: day, today: today,
                                           calendar: calendar)
    }

    /// Feste Anfragen neben den Habit-Weckrufen: Tages-Zusammenfassung (1),
    /// Wochen-Zusammenfassung (1), bis zu `upcomingDays` Voraus-Wecker (7),
    /// ein Session-Meilenstein (1), eine Test-Mitteilung (1), der Glückwunsch
    /// zum perfekten Tag (1) und zwei Anfragen Luft — macht 14. Nur wenn die
    /// Motivation eingeschaltet ist, kommen bis zu `motivationDays` weitere
    /// Anfragen dazu. iOS deckelt bei 64 ANSTEHENDEN Anfragen und wirft den
    /// Überhang stumm weg.
    static let pendingBudget = 64
    private static let baseFixedRequestEstimate = upcomingDays + 7

    static func fixedRequestEstimate(reservingMotivation: Bool) -> Int {
        baseFixedRequestEstimate + (reservingMotivation ? motivationDays : 0)
    }

    static func habitRequestBudget(reservingMotivation: Bool) -> Int {
        pendingBudget - fixedRequestEstimate(reservingMotivation: reservingMotivation)
    }

    /// Wie viele Tage je Habit vorausgeplant werden dürfen, ohne das
    /// 64er-Budget zu sprengen. Mit Motivation passen bei 1–4 Habits mit
    /// Uhrzeit die vollen `habitReminderDays`, ohne sie bei 1–5; darüber
    /// entsprechend weniger — lieber ein kürzeres Fenster für alle als ein
    /// stummes für die letzten.
    static func reminderWindow(timedHabitCount: Int,
                               reservingMotivation: Bool = false) -> Int {
        guard timedHabitCount > 0 else { return habitReminderDays }
        let available = max(1, habitRequestBudget(reservingMotivation: reservingMotivation)
                            / timedHabitCount)
        return min(habitReminderDays, available)
    }

    static func habitPlans(habits: [Habit], reservingMotivation: Bool = false,
                           now: Date = Date(),
                           calendar: Calendar = .current) -> [ReminderPlan] {
        var plans: [ReminderPlan] = []
        let today = DayKey.key(for: now, calendar: calendar)
        let timed = habits.filter {
            $0.archivedAt == nil
                && Habit.sanitizedMinutes($0.timeMinutes ?? $0.reminderMinutes) != nil
        }
        let budget = habitRequestBudget(reservingMotivation: reservingMotivation)
        let window = reminderWindow(timedHabitCount: timed.count,
                                    reservingMotivation: reservingMotivation)
        // Das Fenster allein reicht als Deckel NICHT: es kann nicht unter
        // einen Tag fallen, also ergäben 50 Habits mit Uhrzeit 50 Anfragen —
        // mehr, als den Habits zusteht. Ab hier zählt zusätzlich die
        // GESAMTZAHL. Abgeschnitten wird am Ende der Liste; ohne diese Zeile
        // schnitte iOS selbst ab, nur stumm und ohne zu sagen, wo.
        outer: for habit in timed {
            guard plans.count < budget else { break outer }
            guard let minutes = Habit.sanitizedMinutes(habit.timeMinutes ?? habit.reminderMinutes) else { continue }
            var day = today
            for offset in 0..<window {
                guard plans.count < budget else { break outer }
                if offset > 0 {
                    guard let next = DayKey.shifted(day, by: 1, calendar: calendar) else { break }
                    day = next
                }
                guard reminderWorthy(habit: habit, day: day, today: today, calendar: calendar),
                      !habit.isDone(day), !habit.isAnswered(day),
                      let date = DayKey.date(from: day, calendar: calendar)
                else { continue }
                var components = calendar.dateComponents([.year, .month, .day], from: date)
                components.hour = minutes / 60
                components.minute = minutes % 60
                guard let fire = calendar.date(from: components), fire > now else { continue }
                let label = habit.emoji.isEmpty ? habit.name : "\(habit.emoji) \(habit.name)"
                plans.append(ReminderPlan(identifier: habitReminderIdentifier(habitID: habit.id, day: day),
                                          title: label,
                                          body: String(localized: "Zeit für \(habit.name)"),
                                          dateMatching: components, repeats: false))
            }
        }
        return plans
    }

    static func sessionMilestonePlan(_ session: HabitSession,
                                     calendar: Calendar = .current) -> ReminderPlan? {
        guard let end = HabitSessionMath.plannedEnd(startedAt: session.startedAt,
                                                     plannedMinutes: session.plannedMinutes) else { return nil }
        // MIT Sekunden: ohne sie feuerte der Meilenstein zur vollen Minute —
        // bei einem Start um hh:mm:45 also bis zu 45 Sekunden zu früh.
        return ReminderPlan(identifier: sessionMilestoneIdentifier(session),
                            title: String(localized: "Session-Ziel erreicht"),
                            body: String(localized: "Deine geplante Dauer ist erreicht."),
                            dateMatching: calendar.dateComponents(
                                [.year, .month, .day, .hour, .minute, .second], from: end),
                            repeats: false)
    }

    // MARK: – Ausführung

    /// Stellt Zusammenfassungen, Motivation und Habit-Weckrufe neu.
    /// Idempotent: erst alle eigenen Pending-Requests entfernen (die alten
    /// Habit-Weckrufe eingeschlossen), dann setzen.
    static func reschedule(daily: ReminderPlan?, weekly: ReminderPlan?) async {
        let center = UNUserNotificationCenter.current()

        // Aufräumen VOR dem Berechtigungs-Gate: auch wer Mitteilungen in den
        // iOS-Einstellungen abgeschaltet hat, darf keine veralteten Anfragen
        // liegen lassen — sonst klingelt nach dem Wieder-Einschalten ein
        // längst archiviertes Habit weiter.
        let pending = await center.pendingNotificationRequests()
        // Die Motivations-Kennungen gehören zu „unseren": nur weil sie hier
        // stehen, verschwinden sie beim AUSSCHALTEN wieder (dann plant der
        // Durchlauf unten keine neuen) und beim UMSTELLEN der Uhrzeit werden
        // sie auf die neue Zeit gesetzt, statt doppelt zu klingeln.
        let ours = pending.map(\.identifier).filter {
            $0 == summaryId || $0 == weeklySummaryId
                || $0.hasPrefix(legacyHabitPrefix) || $0.hasPrefix(upcomingPrefix)
                || $0.hasPrefix(habitReminderPrefix) || $0.hasPrefix(motivationPrefix)
        }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        let settings = await center.notificationSettings()
        guard ReminderGate.decision(for: settings.authorizationStatus) == .post else { return }

        // Die Voraus-Wecker lesen ihren Stoff selbst von der Platte — die
        // Aufrufer geben nur die beiden Zusammenfassungen mit, und dieselbe
        // data.json ist ohnehin die einzige Wahrheit (auch fürs Widget).
        var plans = [daily, weekly].compactMap { $0 }
        if let data = HabitStore.read(SharedStorage.dataURL()) {
            plans += upcomingDailyPlans(minutes: data.summaryMinutes, habits: data.habits)
            // VOR den Habit-Weckrufen: bleibt am Ende doch etwas liegen,
            // soll es ein einzelner Habit-Wecker in ferner Zukunft sein und
            // nicht die Nachricht von morgen früh.
            plans += motivationPlans(minutes: data.motivationMinutes,
                                     name: PersonalName.effective)
            plans += habitPlans(habits: data.habits,
                                reservingMotivation: data.motivationMinutes != nil)
        }
        for plan in plans {
            try? await center.add(request(plan))
        }
    }

    /// Nach einem Check-in AUSSERHALB der App (Widget-Knopf, Steuerungs-
    /// element, Siri): die App-eigene Neuplanung (`store.onChange` →
    /// `reschedule`) läuft in DIESEM Prozess nie. Ohne diesen Abgleich
    /// klingelte am Abend die Erinnerung für ein längst abgehaktes Habit,
    /// und die Tages-Zusammenfassung nannte es weiter „offen" (gemeldeter
    /// Fehlerklasse). Bewusst schmal: nur der heutige Habit-Weckruf und die
    /// einmalige Tagesmeldung — alles andere holt der nächste App-Start nach.
    static func reconcileAfterExternalCheckIn(store: HabitStore,
                                              habitID: UUID,
                                              now: Date = Date(),
                                              calendar: Calendar = .current) async {
        let center = UNUserNotificationCenter.current()
        let today = DayKey.key(for: now, calendar: calendar)
        center.removePendingNotificationRequests(
            withIdentifiers: [habitReminderIdentifier(habitID: habitID, day: today)])

        let settings = await center.notificationSettings()
        guard ReminderGate.decision(for: settings.authorizationStatus) == .post else { return }
        center.removePendingNotificationRequests(withIdentifiers: [summaryId])
        if let daily = dailySummaryPlan(minutes: store.summaryMinutes,
                                        status: store.dailyStatus(today, calendar: calendar),
                                        now: now,
                                        calendar: calendar) {
            try? await center.add(request(daily))
        }
        // Auch der Widget-Check-in kann den Tag vollmachen.
        await celebrateIfPerfectDay(store: store, now: now, calendar: calendar)
    }

    /// Der Glückwunsch zum perfekten Tag — nach JEDEM Check-in geprüft
    /// (App wie Widget), gefeuert höchstens einmal je Tag. Der Merker wird
    /// VOR dem Planen gesetzt: zwei schnelle Check-ins hintereinander
    /// dürfen nicht beide feuern.
    static func celebrateIfPerfectDay(store: HabitStore,
                                      now: Date = Date(),
                                      calendar: Calendar = .current) async {
        let today = DayKey.key(for: now, calendar: calendar)
        let defaults = UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard
        guard Celebration.shouldCelebrate(status: store.dailyStatus(today, calendar: calendar),
                                          today: today,
                                          lastCelebrated: defaults.string(forKey: Celebration.celebratedKey))
        else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard ReminderGate.decision(for: settings.authorizationStatus) == .post else { return }
        defaults.set(today, forKey: Celebration.celebratedKey)

        let message = Celebration.message(name: PersonalName.effective, today: today)
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "celebration-\(today)",
                                                    content: content,
                                                    trigger: trigger))
    }

    static func scheduleSessionMilestone(_ session: HabitSession) async {
        guard let plan = sessionMilestonePlan(session) else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard ReminderGate.decision(for: settings.authorizationStatus) == .post else { return }
        center.removePendingNotificationRequests(withIdentifiers: [plan.identifier])
        try? await center.add(request(plan))
    }

    static func cancelSessionMilestone(_ session: HabitSession) {
        HabitSessionMilestoneControl.cancel(session)
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
