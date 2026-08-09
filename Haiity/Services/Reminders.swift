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
    /// Was der `UNCalendarNotificationTrigger` abgleicht. Ohne weitere
    /// Angabe passt es auf JEDEN Tag zur genannten Uhrzeit (täglich); mit
    /// `weekday` auf diesen einen Wochentag (wöchentlich), mit `day` auf
    /// diesen Monatstag (monatlich), mit `month` + `day` auf dieses Datum
    /// (jährlich). Ein vollständiges Datum (`year`) ist der EINMALIGE
    /// Wecker der Rückfallebene.
    var dateMatching: DateComponents
    var repeats: Bool

    var isWeekly: Bool { dateMatching.weekday != nil }
    var isMonthly: Bool { dateMatching.day != nil && dateMatching.year == nil }
    /// Einmalig gestellt, weil sich die Regel nicht als Muster ausdrücken
    /// lässt — wird bei jedem `reschedule` neu gesetzt.
    var isOneShot: Bool { !repeats }
}

enum Reminders {
    static let summaryId = "summary"

    static func habitId(_ id: UUID) -> String { "habit-\(id.uuidString)" }

    /// Ein Wochentag = EIN Trigger: `UNCalendarNotificationTrigger` gleicht
    /// genau EINEN `weekday` ab, „Mo + Mi + Fr" sind also drei Anfragen mit
    /// drei Kennungen. Das gemeinsame Präfix bleibt `habit-`, damit das
    /// Aufräumen in `reschedule` sie alle findet.
    static func habitId(_ id: UUID, weekday: Int) -> String {
        "habit-\(id.uuidString)-w\(weekday)"
    }

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

    /// Die Weckrufe eines Habits — MEHRERE, weil ein Kalender-Trigger nur
    /// einen Wochentag abgleichen kann.
    ///
    /// Was `UNCalendarNotificationTrigger` kann, wird als WIEDERHOLENDER
    /// Trigger geplant:
    ///
    ///  * täglich (Intervall 1)                  -> Stunde + Minute
    ///  * flexibles Ziel ohne Tage („3× pro Woche") -> Stunde + Minute; welche
    ///    Tage das werden, entscheidet der Nutzer, die Erinnerung soll ihn an
    ///    allen erwischen (unverändert die alte Regel)
    ///  * feste Wochentage (Intervall 1)         -> ein Trigger JE Wochentag
    ///  * monatlich am festen Tag (Intervall 1)  -> Tag + Stunde + Minute
    ///  * jährlich am festen Tag (Intervall 1)   -> Monat + Tag + Stunde + Minute
    ///
    /// Und was es NICHT kann, ehrlich benannt: „alle 2 Wochen", „alle 3
    /// Monate", „am letzten Freitag", „am 3. Dienstag" lassen sich als
    /// Datumsmuster überhaupt nicht ausdrücken — ein Muster hat keine Phase
    /// und kennt keinen n-ten Wochentag. Für diese Regeln wird der NÄCHSTE
    /// Termin als einmaliger Wecker gestellt und bei jedem `reschedule` neu
    /// gesetzt (App-Start, Aktivwerden, jede Änderung am Store, also auch
    /// jedes Abhaken). Genau dieses Muster fährt die Abend-Zusammenfassung
    /// schon immer.
    ///
    /// Archivierte Habits klingeln nicht — sie sind aus Liste, Widget und
    /// Zusammenfassung verschwunden, eine Erinnerung wäre ein Geist.
    static func plans(for habit: Habit,
                      now: Date = Date(),
                      calendar: Calendar = .current) -> [ReminderPlan] {
        guard let minutes = habit.reminderMinutes, habit.archivedAt == nil,
              (0..<24 * 60).contains(minutes) else { return [] }
        let recurrence = habit.recurrence
        let title = habit.emoji.isEmpty ? habit.name : "\(habit.emoji) \(habit.name)"
        let body = String(localized: "Kleiner Schritt, volle Zelle.")

        func plan(_ identifier: String, _ components: DateComponents, repeats: Bool) -> ReminderPlan {
            var c = components
            c.hour = minutes / 60
            c.minute = minutes % 60
            return ReminderPlan(identifier: identifier, title: title, body: body,
                                dateMatching: c, repeats: repeats)
        }

        // Ein Ende in der Vergangenheit heißt: nichts steht mehr an.
        let today = DayKey.key(for: now, calendar: calendar)
        let schedule = recurrence.schedule(calendar: calendar)
        if let lastDay = schedule.lastDay, lastDay < today { return [] }
        // Eine Regel mit Ende wiederholt sich nicht ewig — dann lieber den
        // nächsten Termin einzeln stellen, als über das Ende hinaus zu
        // klingeln. Dasselbe VOR dem Start: ein Muster kennt keinen Anfang,
        // ein wiederholender Trigger würde also schon vor dem ersten Termin
        // klingeln.
        let endless = recurrence.end == .never
        let started = recurrence.start.map { $0 <= today } ?? true

        if endless, started, recurrence.interval == 1 {
            switch recurrence.frequency {
            case .daily:
                return [plan(habitId(habit.id), DateComponents(), repeats: true)]
            case .weekly:
                if recurrence.isFlexible {
                    // „Einmal pro Woche, gedacht am Dienstag": ein fester Tag
                    // ist eine Verabredung — er steuert genau hier, die
                    // Erinnerung, und sonst nichts.
                    let days = RecurrenceText.ordered(recurrence.weekdays, calendar: calendar)
                    guard let single = days.count == 1 ? days.first : nil else {
                        return [plan(habitId(habit.id), DateComponents(), repeats: true)]
                    }
                    return [plan(habitId(habit.id), DateComponents(weekday: single), repeats: true)]
                }
                let days = RecurrenceText.ordered(recurrence.weekdays, calendar: calendar)
                guard !days.isEmpty else { return [] }
                return days.map {
                    plan(habitId(habit.id, weekday: $0), DateComponents(weekday: $0), repeats: true)
                }
            case .monthly:
                if recurrence.isFlexible {
                    return [plan(habitId(habit.id), DateComponents(), repeats: true)]
                }
                if case .dayOfMonth(let day)? = recurrence.rule {
                    return [plan(habitId(habit.id), DateComponents(day: day), repeats: true)]
                }
            case .yearly:
                if recurrence.isFlexible {
                    return [plan(habitId(habit.id), DateComponents(), repeats: true)]
                }
                if case .dayOfMonth(let day)? = recurrence.rule {
                    return [plan(habitId(habit.id),
                                 DateComponents(month: recurrence.month ?? 1, day: day),
                                 repeats: true)]
                }
            }
        }

        // Rückfallebene: den nächsten Termin einmalig stellen.
        guard let day = nextFireDay(recurrence: recurrence, minutes: minutes,
                                    now: now, calendar: calendar),
              let parts = DayKey.components(day) else { return [] }
        return [plan(habitId(habit.id),
                     DateComponents(year: parts.year, month: parts.month, day: parts.day),
                     repeats: false)]
    }

    /// Der erste Termin, der noch bevorsteht — heute nur, wenn die Uhrzeit
    /// noch kommt.
    static func nextFireDay(recurrence: Recurrence,
                            minutes: Int,
                            now: Date,
                            calendar: Calendar) -> String? {
        let today = DayKey.key(for: now, calendar: calendar)
        let schedule = recurrence.schedule(calendar: calendar)
        if schedule.isScheduled(today) {
            var c = calendar.dateComponents([.year, .month, .day], from: now)
            c.hour = minutes / 60
            c.minute = minutes % 60
            if let fire = calendar.date(from: c), fire > now { return today }
        }
        return schedule.next(after: today)
    }

    /// Der erste Weckruf — für Aufrufer, die nur wissen wollen, OB und in
    /// welcher Form geplant wird. Geplant wird immer `plans(for:)`.
    static func plan(for habit: Habit,
                     now: Date = Date(),
                     calendar: Calendar = .current) -> ReminderPlan? {
        plans(for: habit, now: now, calendar: calendar).first
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

        var plans = habits.flatMap { self.plans(for: $0) }
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
