import Foundation
import UserNotifications

/// Benachrichtigungs-Politik (aus aiity übernommen): gefragt wird NUR, wenn
/// der Nutzer gerade aktiv eine Erinnerung einschaltet. Nie beim Start.
enum ReminderGate {
    enum Decision: Equatable { case post, ask, refuse }

    static func decision(for status: UNAuthorizationStatus,
                         promptsSuppressed: Bool = false) -> Decision {
        switch status {
        case .authorized, .provisional, .ephemeral: return .post
        case _ where promptsSuppressed: return .refuse
        case .notDetermined: return .ask
        case .denied: return .refuse
        @unknown default: return .refuse
        }
    }
}

enum NotificationPromptPreference {
    static let suppressedKey = "notificationPromptsSuppressed"
    static let dndStateKey = "notificationDNDState"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard
    }

    static var isSuppressed: Bool {
        get { isSuppressed(in: defaults) }
        set { setSuppressed(newValue, in: defaults) }
    }

    static var state: NotificationDNDState {
        get { state(in: defaults) }
        set { setState(newValue, in: defaults) }
    }

    static func state(in defaults: UserDefaults) -> NotificationDNDState {
        if let data = defaults.data(forKey: dndStateKey),
           let saved = try? JSONDecoder().decode(NotificationDNDState.self, from: data) {
            return saved
        }
        // The boolean was the original permanent opt-out. Preserve it when
        // opening a build that has the richer timed DND model.
        return defaults.bool(forKey: suppressedKey) ? .active(.untilDisabled) : .off
    }

    static func setState(_ state: NotificationDNDState, in defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: dndStateKey)
        }
        // The old key is deliberately a mirror, not a second source of truth.
        defaults.set(state.isActive(), forKey: suppressedKey)
    }

    static func isSuppressed(in defaults: UserDefaults) -> Bool {
        state(in: defaults).isActive()
    }

    static func setSuppressed(_ suppressed: Bool, in defaults: UserDefaults) {
        setState(suppressed ? .active(.untilDisabled) : .off, in: defaults)
    }
}

enum NotificationDNDPresentation {
    static let title = String(localized: "Do not disturb")
    static let symbolName = "moon.zzz.fill"
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
    var quickAction: NotificationQuickAction? = nil
    /// Habit notifications use the habit-kind category, whose action list is
    /// configured once for all three slots. Other plans leave this nil.
    var notificationCategoryIdentifier: String? = nil

    var isWeekly: Bool { dateMatching.weekday != nil }
    /// Einmalig gestellt und bei jedem `reschedule` neu gesetzt.
    var isOneShot: Bool { !repeats }
}

enum NotificationQuickAction: String, CaseIterable, Codable, Sendable {
    case checkbox
    case quantity
    case yesNo
    case reminder
    case reset
    case no
    case archive
    case backfill
    case session
    case edit

    /// Identifier used by builds before multi-action notification menus.
    static let actionIdentifier = "haiity.quick-check"
    private static let actionIdentifierPrefix = "haiity.quick-check."

    static let habitCategoryBases: [Self] = [.checkbox, .quantity, .yesNo, .reminder]

    var categoryIdentifier: String { "haiity.notification.\(rawValue)" }

    var responseIdentifier: String { Self.actionIdentifierPrefix + rawValue }

    var title: String {
        switch self {
        case .checkbox, .reminder: return String(localized: "Erledigt")
        case .quantity: return String(localized: "+1")
        case .yesNo: return String(localized: "Ja")
        case .reset: return String(localized: "Zurücksetzen")
        case .no: return String(localized: "Nein")
        case .archive: return String(localized: "Archivieren")
        case .backfill: return String(localized: "Nacharbeiten")
        case .session: return String(localized: "Session starten")
        case .edit: return String(localized: "Bearbeiten")
        }
    }

    var opensApp: Bool {
        switch self {
        case .backfill, .session, .edit: return true
        default: return false
        }
    }

    static func forHabit(_ habit: Habit) -> Self {
        habit.isReminder ? .reminder : Self(rawValue: habit.kind.rawValue) ?? .checkbox
    }

    static func forHabit(_ habit: Habit, choice: SwipeActionChoice) -> Self? {
        resolved(for: forHabit(habit), choice: choice)
    }

    static func resolved(for base: Self, choice: SwipeActionChoice) -> Self? {
        switch choice {
        case .primary: return base
        case .secondary: return base == .yesNo ? .no : .reset
        case .archive: return .archive
        case .backfill: return .backfill
        case .session: return .session
        case .edit: return .edit
        case .none: return nil
        }
    }

    static func actions(for habit: Habit,
                        choices: [SwipeActionChoice]) -> [Self] {
        actions(for: forHabit(habit), choices: choices)
    }

    static func actions(for base: Self,
                        choices: [SwipeActionChoice]) -> [Self] {
        var result: [Self] = []
        for choice in choices.prefix(NotificationActionPreferences.slotCount) {
            guard let action = resolved(for: base, choice: choice),
                  !result.contains(action) else { continue }
            result.append(action)
        }
        return result
    }

    static func responseAction(identifier: String,
                               categoryIdentifier: String) -> Self? {
        if identifier.hasPrefix(actionIdentifierPrefix) {
            let raw = String(identifier.dropFirst(actionIdentifierPrefix.count))
            return Self(rawValue: raw)
        }

        // Existing pending notifications used one shared action identifier
        // and encoded the selected action in the category name.
        guard identifier == actionIdentifier,
              categoryIdentifier.hasPrefix("haiity.notification.") else { return nil }
        let raw = String(categoryIdentifier.dropFirst("haiity.notification.".count))
        return Self(rawValue: raw)
    }
}

struct NotificationHabitTarget: Equatable, Sendable {
    let habitID: UUID
    let day: String
}

struct NotificationActionRequest: Equatable, Sendable {
    let action: NotificationQuickAction
    let target: NotificationHabitTarget
}

struct NotificationDeliveryIssue: Codable, Equatable, Sendable {
    let message: String

    static let reminderScheduleFailed = NotificationDeliveryIssue(
        message: String(localized:
            "Mitteilungen konnten nicht aktualisiert werden. Öffne hAiity erneut, um es noch einmal zu versuchen."))
}

enum NotificationDeliveryIssueCenter {
    static let pendingDidChange = Notification.Name("haiity.notification-delivery-issue")

    private static let pendingKey = "pendingNotificationDeliveryIssue"

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard
    }

    static func note(_ issue: NotificationDeliveryIssue,
                     defaults: UserDefaults = sharedDefaults,
                     center: NotificationCenter = .default) {
        if let data = try? JSONEncoder().encode(issue) {
            defaults.set(data, forKey: pendingKey)
        }
        center.post(name: pendingDidChange, object: nil)
    }

    static func takePending(defaults: UserDefaults = sharedDefaults) -> NotificationDeliveryIssue? {
        guard let data = defaults.data(forKey: pendingKey),
              let issue = try? JSONDecoder().decode(NotificationDeliveryIssue.self, from: data) else {
            return nil
        }
        defaults.removeObject(forKey: pendingKey)
        return issue
    }

    @discardableResult
    static func deliverPendingMessage(defaults: UserDefaults = sharedDefaults,
                                      deliver: (String) -> Void) -> Bool {
        guard let issue = takePending(defaults: defaults) else { return false }
        deliver(issue.message)
        return true
    }
}

enum NotificationActionRouter {
    /// A wake-up only. The observer must read the persisted request with
    /// `takePending()`; it must never receive a request that can be presented
    /// synchronously from UIKit's notification callback.
    static let pendingDidChange = Notification.Name("haiity.notification-action-pending")

    private static let pendingKey = "pendingNotificationAction"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard
    }

    static func post(_ request: NotificationActionRequest) {
        guard request.action.opensApp else { return }
        let values: [String: String] = [
            "action": request.action.rawValue,
            "habitID": request.target.habitID.uuidString,
            "day": request.target.day
        ]
        defaults.set(values, forKey: pendingKey)

        // Keep this outside the delegate's call stack. The app may still be
        // restoring UIKit state when `didReceive` returns, so the wake-up is
        // intentionally delayed and carries no UI payload.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
            NotificationCenter.default.post(name: pendingDidChange, object: nil)
        }
    }

    static func takePending() -> NotificationActionRequest? {
        guard let values = defaults.dictionary(forKey: pendingKey) as? [String: String] else {
            return nil
        }
        defaults.removeObject(forKey: pendingKey)
        return makeRequest(action: values["action"], habitID: values["habitID"], day: values["day"])
    }

    private static func makeRequest(action rawAction: String?,
                                    habitID rawHabitID: String?,
                                    day: String?) -> NotificationActionRequest? {
        guard let rawAction,
              let action = NotificationQuickAction(rawValue: rawAction),
              action.opensApp,
              let rawHabitID,
              let habitID = UUID(uuidString: rawHabitID),
              let day,
              DayKey.isValid(day)
        else { return nil }
        return NotificationActionRequest(action: action,
                                         target: NotificationHabitTarget(habitID: habitID, day: day))
    }
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
        switch ReminderGate.decision(for: settings.authorizationStatus,
                                     promptsSuppressed: NotificationPromptPreference.isSuppressed) {
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

    struct ExternalCheckInReconciliation: Equatable, Sendable {
        let removeIdentifiers: [String]
        let addPlans: [ReminderPlan]
        let pendingUpcomingIdentifiers: [String]
        let upcomingPlans: [ReminderPlan]
    }

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
                           notificationActions: [SwipeActionChoice] =
                               NotificationActionPreferences().slots,
                           defaultTimeZoneIdentifier: String? = nil,
                           now: Date = Date(),
                           calendar: Calendar = .current) -> [ReminderPlan] {
        var plans: [ReminderPlan] = []
        let timed = habits.filter {
            $0.archivedAt == nil
                && $0.notificationsEnabled
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
            let habitCalendar = HabitTimeZone.calendar(for: habit,
                                                       defaultIdentifier: defaultTimeZoneIdentifier,
                                                       base: calendar)
            let today = DayKey.key(for: now, calendar: habitCalendar)
            guard let minutes = Habit.sanitizedMinutes(habit.timeMinutes ?? habit.reminderMinutes) else { continue }
            if habit.isReminder, !habit.repeatsWhileIncomplete {
                let state = ReminderOccurrenceEngine.state(for: habit, now: now,
                                                           calendar: habitCalendar)
                guard let occurrence = state.actionable, occurrence.dueDate > now,
                      let plan = habitPlan(habit: habit, day: occurrence.day,
                                           minutes: minutes,
                                           notificationActions: notificationActions,
                                           calendar: habitCalendar)
                else { continue }
                plans.append(plan)
                continue
            }
            var day = today
            for offset in 0..<window {
                guard plans.count < budget else { break outer }
                if offset > 0 {
                    guard let next = DayKey.shifted(day, by: 1, calendar: habitCalendar) else { break }
                    day = next
                }
                guard reminderWorthy(habit: habit, day: day, today: today, calendar: habitCalendar),
                      !habit.isDone(day), !habit.isAnswered(day)
                else { continue }
                guard let plan = habitPlan(habit: habit, day: day,
                                           minutes: minutes,
                                           notificationActions: notificationActions,
                                           calendar: habitCalendar),
                      let fire = habitCalendar.date(from: plan.dateMatching), fire > now
                else { continue }
                plans.append(plan)
            }
        }
        return plans
    }

    /// Compatibility overload for callers from the one-action build.
    static func habitPlans(habits: [Habit], reservingMotivation: Bool = false,
                           notificationAction: SwipeActionChoice,
                           defaultTimeZoneIdentifier: String? = nil,
                           now: Date = Date(),
                           calendar: Calendar = .current) -> [ReminderPlan] {
        habitPlans(habits: habits,
                   reservingMotivation: reservingMotivation,
                   notificationActions: [notificationAction, .none, .none],
                   defaultTimeZoneIdentifier: defaultTimeZoneIdentifier,
                   now: now,
                   calendar: calendar)
    }

    private static func habitPlan(habit: Habit, day: String, minutes: Int,
                                  notificationActions: [SwipeActionChoice],
                                  calendar: Calendar) -> ReminderPlan? {
        guard let date = DayKey.date(from: day, calendar: calendar) else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = minutes / 60
        components.minute = minutes % 60
        components.timeZone = calendar.timeZone
        let label = habit.emoji.isEmpty ? habit.name : "\(habit.emoji) \(habit.name)"
        return ReminderPlan(identifier: habitReminderIdentifier(habitID: habit.id, day: day),
                            title: label,
                            body: String(localized: "Zeit für \(habit.name)"),
                            dateMatching: components,
                            repeats: false,
                            quickAction: NotificationQuickAction.actions(
                                for: habit,
                                choices: notificationActions).first,
                            notificationCategoryIdentifier: NotificationQuickAction
                                .forHabit(habit).categoryIdentifier)
    }

    static func habitTarget(for identifier: String) -> NotificationHabitTarget? {
        guard identifier.hasPrefix(habitReminderPrefix) else { return nil }
        let payload = String(identifier.dropFirst(habitReminderPrefix.count))
        let parts = payload.split(separator: "-")
        guard parts.count == 8 else { return nil }
        let uuidText = parts.prefix(5).joined(separator: "-")
        let day = parts.suffix(3).joined(separator: "-")
        guard let habitID = UUID(uuidString: uuidText), DayKey.isValid(day) else { return nil }
        return NotificationHabitTarget(habitID: habitID, day: day)
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
            let visibleHabits = HabitVisibility.visibleActiveHabits(
                data.habits,
                unlocked: HabitVisibility.sharedEntitlementIsUnlocked)
            plans += upcomingDailyPlans(minutes: data.summaryMinutes, habits: visibleHabits)
            // VOR den Habit-Weckrufen: bleibt am Ende doch etwas liegen,
            // soll es ein einzelner Habit-Wecker in ferner Zukunft sein und
            // nicht die Nachricht von morgen früh.
            if data.motivationDelivery == .notification {
                plans += motivationPlans(minutes: data.motivationMinutes,
                                         name: PersonalName.effective)
            }
            let reservingMotivation = data.motivationMinutes != nil
                && data.motivationDelivery == .notification
            plans += habitPlans(habits: visibleHabits,
                                reservingMotivation: reservingMotivation,
                                notificationActions: data.viewPreferences.notificationActions.slots,
                                defaultTimeZoneIdentifier: data.defaultTimeZoneIdentifier)
        }
        for plan in plans {
            try? await center.add(request(plan))
        }
    }

    static func reschedule(store: HabitStore,
                           now: Date = Date(),
                           calendar: Calendar = .current) async {
        let today = DayKey.key(for: now, calendar: calendar)
        let visibleHabits = HabitVisibility.visibleActiveHabits(
            store.habits,
            unlocked: HabitVisibility.sharedEntitlementIsUnlocked)
        let daily = dailySummaryPlan(minutes: store.summaryMinutes,
                                     status: store.dailyStatus(today,
                                                               calendar: calendar,
                                                               habits: visibleHabits),
                                     now: now,
                                     calendar: calendar)
        let weekly = weeklySummaryPlan(minutes: store.weeklySummaryMinutes,
                                       weekday: store.weeklySummaryWeekday,
                                       status: store.weeklyStatus(today,
                                                                   calendar: calendar,
                                                                   fullWeek: true,
                                                                   habits: visibleHabits),
                                       calendar: calendar)
        await reschedule(daily: daily, weekly: weekly)
    }

    private static func logScheduleFailure(_ error: Error,
                                           identifier: String,
                                           context: String) {
        NSLog("Reminders: failed to schedule %@ during %@: %@",
              identifier,
              context,
              String(describing: error))
        Task { @MainActor in
            NotificationDeliveryIssueCenter.note(.reminderScheduleFailed)
        }
    }

    static func applyQuickAction(_ action: NotificationQuickAction,
                                 to habit: Habit,
                                 target: NotificationHabitTarget,
                                 store: HabitStore,
                                 defaultTimeZoneIdentifier: String? = nil,
                                 now: Date = Date(),
                                 calendar: Calendar = .current) -> Bool {
        guard habit.id == target.habitID, habit.archivedAt == nil else { return false }
        let habitCalendar = HabitTimeZone.calendar(
            for: habit,
            defaultIdentifier: defaultTimeZoneIdentifier ?? store.defaultTimeZoneIdentifier,
            base: calendar)

        if action == .archive {
            store.archive(habit.id)
            return true
        }

        if action == .reset {
            guard store.value(habit.id, day: target.day) != nil else { return false }
            if habit.isReminder {
                store.setReminderCompletion(habit.id, day: target.day,
                                            completed: false, nextCursor: target.day)
            } else {
                store.clear(habit.id, day: target.day)
            }
            return true
        }

        if action == .no {
            guard !habit.isReminder, habit.kind == .yesNo,
                  !habit.isAnswered(target.day) else { return false }
            store.setValue(habit.id, day: target.day, value: Habit.Answer.no)
            return true
        }

        guard NotificationQuickAction.forHabit(habit) == action else { return false }

        if habit.isReminder {
            guard habit.log[target.day] == nil,
                  let dueDate = ReminderOccurrenceEngine.dueDate(day: target.day,
                                                                   reminder: habit,
                                                                   calendar: habitCalendar)
            else { return false }
            let occurrence = ReminderOccurrence(day: target.day, dueDate: dueDate)
            let cursor = habit.repeatsWhileIncomplete
                ? nil
                : ReminderOccurrenceEngine.cursorAfterCompleting(occurrence,
                                                                  reminder: habit,
                                                                  now: now,
                                                                  calendar: habitCalendar)
            store.setReminderCompletion(habit.id, day: target.day,
                                        completed: true, nextCursor: cursor)
            return true
        }

        guard !habit.isDone(target.day) else { return false }
        switch habit.kind {
        case .quantity:
            store.increment(habit.id, day: target.day)
        case .yesNo:
            store.setValue(habit.id, day: target.day, value: Habit.Answer.yes)
        case .checkbox:
            store.toggle(habit.id, day: target.day)
        }
        return true
    }

    /// Nach einem Check-in AUSSERHALB der App (Widget-Knopf, Steuerungs-
    /// element, Siri): die App-eigene Neuplanung (`store.onChange` →
    /// `reschedule`) läuft in DIESEM Prozess nie. Ohne diesen Abgleich
    /// klingelte am Abend die Erinnerung für ein längst abgehaktes Habit,
    /// und die Tages-Zusammenfassung nannte es weiter „offen" (gemeldeter
    /// Fehlerklasse). Bewusst gezielt statt „alles neu": der betroffene
    /// Habit-Weckruf, die heutige Einmal-Zusammenfassung und die voraus
    /// geplanten `summary-day-*`-Meldungen werden abgeglichen; anderes darf
    /// bis zum nächsten App-Start warten.
    static func externalCheckInReconciliation(store: HabitStore,
                                              habitID: UUID,
                                              pendingIdentifiers: [String],
                                              defaultTimeZoneIdentifier: String? = nil,
                                              now: Date = Date(),
                                              calendar: Calendar = .current)
        -> ExternalCheckInReconciliation? {
        let visibleHabits = HabitVisibility.visibleActiveHabits(
            store.habits,
            unlocked: HabitVisibility.sharedEntitlementIsUnlocked)
        guard visibleHabits.contains(where: { $0.id == habitID }) else { return nil }

        let today = DayKey.key(for: now, calendar: calendar)
        let daily = dailySummaryPlan(minutes: store.summaryMinutes,
                                     status: store.dailyStatus(today,
                                                               calendar: calendar,
                                                               habits: visibleHabits),
                                     now: now,
                                     calendar: calendar)
        let reservingMotivation = store.motivationMinutes != nil
            && store.motivationDelivery == .notification
        let habitPlans = habitPlans(
            habits: visibleHabits,
            reservingMotivation: reservingMotivation,
            notificationActions: store.data.viewPreferences.notificationActions.slots,
            defaultTimeZoneIdentifier: defaultTimeZoneIdentifier ?? store.defaultTimeZoneIdentifier,
            now: now,
            calendar: calendar
        ).filter { habitTarget(for: $0.identifier)?.habitID == habitID }
        let reminderPrefix = habitReminderPrefix + habitID.uuidString
        return ExternalCheckInReconciliation(
            removeIdentifiers: pendingIdentifiers.filter {
                $0 == summaryId || $0.hasPrefix(reminderPrefix)
            },
            addPlans: [daily].compactMap { $0 } + habitPlans,
            pendingUpcomingIdentifiers: pendingIdentifiers.filter {
                $0.hasPrefix(upcomingPrefix)
            },
            upcomingPlans: upcomingDailyPlans(minutes: store.summaryMinutes,
                                              habits: visibleHabits,
                                              now: now,
                                              calendar: calendar)
        )
    }

    static func refreshUpcomingSummaryPlans(
        pendingIdentifiers: [String],
        desiredPlans: [ReminderPlan],
        addPlan: (ReminderPlan) async throws -> Void,
        removePending: ([String]) -> Void,
        logFailure: (Error, String, String) -> Void
    ) async {
        for plan in desiredPlans {
            do {
                try await addPlan(plan)
            } catch {
                logFailure(error, plan.identifier, "external check-in upcoming summaries")
                return
            }
        }

        let desiredIdentifiers = Set(desiredPlans.map(\.identifier))
        let obsolete = pendingIdentifiers.filter { !desiredIdentifiers.contains($0) }
        guard !obsolete.isEmpty else { return }
        removePending(obsolete)
    }

    static func reconcileAfterExternalCheckIn(store: HabitStore,
                                              habitID: UUID,
                                              defaultTimeZoneIdentifier: String? = nil,
                                              now: Date = Date(),
                                              calendar: Calendar = .current) async {
        let center = UNUserNotificationCenter.current()
        let pendingIdentifiers = await center.pendingNotificationRequests().map(\.identifier)
        guard let update = externalCheckInReconciliation(store: store,
                                                         habitID: habitID,
                                                         pendingIdentifiers: pendingIdentifiers,
                                                         defaultTimeZoneIdentifier: defaultTimeZoneIdentifier,
                                                         now: now,
                                                         calendar: calendar)
        else { return }
        if !update.removeIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: update.removeIdentifiers)
        }

        let settings = await center.notificationSettings()
        guard ReminderGate.decision(for: settings.authorizationStatus) == .post else { return }
        for plan in update.addPlans {
            do {
                try await center.add(request(plan))
            } catch {
                logScheduleFailure(error, identifier: plan.identifier, context: "external check-in")
            }
        }
        await refreshUpcomingSummaryPlans(
            pendingIdentifiers: update.pendingUpcomingIdentifiers,
            desiredPlans: update.upcomingPlans,
            addPlan: { plan in
                try await center.add(request(plan))
            },
            removePending: { identifiers in
                center.removePendingNotificationRequests(withIdentifiers: identifiers)
            },
            logFailure: { error, identifier, context in
                logScheduleFailure(error, identifier: identifier, context: context)
            })
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
        let visibleHabits = HabitVisibility.visibleActiveHabits(
            store.habits,
            unlocked: HabitVisibility.sharedEntitlementIsUnlocked)
        let defaults = UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard
        guard Celebration.shouldCelebrate(status: store.dailyStatus(today,
                                                                     calendar: calendar,
                                                                     habits: visibleHabits),
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
        if let category = plan.notificationCategoryIdentifier {
            content.categoryIdentifier = category
        } else if let quickAction = plan.quickAction {
            content.categoryIdentifier = quickAction.categoryIdentifier
        }
        let trigger = UNCalendarNotificationTrigger(dateMatching: plan.dateMatching,
                                                    repeats: plan.repeats)
        return UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
    }
}
