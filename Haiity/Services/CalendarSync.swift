import Foundation
import EventKit

// MARK: – Der Plan (pur)

/// Ein Habit als Kalender-Termin — die REGELN pur und ohne EventKit, damit
/// die Abbildung (Wiederholung, Uhrzeit, Ende) im Test steht.
///
/// Nicht jedes Habit gehört in einen Kalender: flexible Ziele OHNE
/// Wochentags-Verabredung („3× pro Woche, irgendwann") haben keinen Termin,
/// den man eintragen könnte — sie liefern keinen Plan. Flexible Ziele MIT
/// Verabredung erscheinen an genau diesen Wochentagen.
struct CalendarEventPlan: Equatable {
    var title: String
    /// Erster Termin (Tagesschlüssel) — heute, wenn heute fällig ist, sonst
    /// der nächste laut Regel.
    var firstDay: String
    /// Uhrzeit in Minuten seit Mitternacht; nil = ganztägig.
    var minutes: Int?
    /// Länge eines Termins mit Uhrzeit (geplante Session-Dauer, sonst 30).
    var durationMinutes: Int
    var frequency: Recurrence.Frequency
    var interval: Int
    /// Wochentage (1 = So … 7 = Sa) — leer heißt: die Frequenz trägt allein.
    var weekdays: [Int]
    /// Monatstag(e); EventKit versteht -1 als „letzter".
    var daysOfMonth: [Int]
    /// „n-ter Wochentag im Monat" (nth, weekday); nth -1 = letzter.
    var nthWeekday: (nth: Int, weekday: Int)?
    /// Monat fürs Jahres-Muster.
    var monthOfYear: Int?
    var end: Recurrence.End

    static func == (a: CalendarEventPlan, b: CalendarEventPlan) -> Bool {
        a.fingerprint == b.fingerprint
    }

    /// Alles Sichtbare in EINEM Schlüssel — ändert er sich, wird der Termin
    /// neu geschrieben; sonst bleibt er unangetastet.
    /// (Schrittweise gebaut: der Typprüfer des Release-Xcode kippt bei dem
    /// einen großen Array-Literal aus Maps und Interpolationen.)
    var fingerprint: String {
        let nth: String = nthWeekday.map { "\($0.nth)@\($0.weekday)" } ?? "-"
        let endKey: String
        switch end {
        case .never: endKey = "never"
        case .on(let day): endKey = "on:\(day)"
        case .after(let n): endKey = "after:\(n)"
        }
        let time: String = minutes.map { String($0) } ?? "allday"
        let weekdayKey: String = weekdays.map { String($0) }.joined(separator: ",")
        let monthDayKey: String = daysOfMonth.map { String($0) }.joined(separator: ",")
        let monthKey: String = monthOfYear.map { String($0) } ?? "-"
        var parts: [String] = [title, firstDay, time]
        parts.append(String(durationMinutes))
        parts.append(frequency.rawValue)
        parts.append(String(interval))
        parts.append(weekdayKey)
        parts.append(monthDayKey)
        parts.append(nth)
        parts.append(monthKey)
        parts.append(endKey)
        return parts.joined(separator: "|")
    }

    /// nil = dieses Habit gehört (so) nicht in den Kalender.
    init?(habit: Habit, today: String = DayKey.today(),
          calendar: Calendar = .current) {
        guard habit.archivedAt == nil else { return nil }
        let recurrence = habit.recurrence

        // Flexible Ziele: nur mit Wochentags-Verabredung — und dann als
        // schlichtes Wochenmuster an genau diesen Tagen.
        if recurrence.isFlexible, recurrence.weekdays.isEmpty { return nil }

        // Erster Termin: heute, wenn fällig — sonst der nächste. Für
        // flexible Regeln zählt die VERABREDUNG (nicht `isScheduled`, das
        // in der Periode überall wahr ist).
        func isAgreedDay(_ day: String) -> Bool {
            if recurrence.isFlexible {
                guard let date = DayKey.date(from: day, calendar: calendar) else { return false }
                return recurrence.weekdays.contains(calendar.component(.weekday, from: date))
            }
            return GoalEngine.isScheduled(habit: habit, day: day, calendar: calendar)
        }
        var first: String? = isAgreedDay(today) ? today : nil
        if first == nil {
            var candidate = today
            // Verabredete Tage liegen höchstens eine Woche voraus; feste
            // Regeln beantwortet `nextOccurrence`.
            if recurrence.isFlexible {
                for _ in 0..<7 {
                    guard let next = DayKey.shifted(candidate, by: 1, calendar: calendar) else { break }
                    candidate = next
                    if isAgreedDay(candidate) { first = candidate; break }
                }
            } else {
                first = recurrence.nextOccurrence(after: today, calendar: calendar)
            }
        }
        guard let firstDay = first else { return nil }

        self.title = habit.emoji.isEmpty ? habit.name : "\(habit.emoji) \(habit.name)"
        self.firstDay = firstDay
        self.minutes = Habit.sanitizedMinutes(habit.timeMinutes ?? habit.reminderMinutes)
        self.durationMinutes = Habit.sanitizedDuration(habit.durationMinutes) ?? 30
        self.frequency = recurrence.isFlexible ? .weekly : recurrence.frequency
        self.interval = recurrence.interval
        self.weekdays = recurrence.weekdays.sorted()
        var days: [Int] = []
        var nth: (Int, Int)?
        if let rule = recurrence.rule {
            switch rule {
            case .dayOfMonth(let day): days = [day]
            case .lastDayOfMonth: days = [-1]
            case .nthWeekday(let n, let weekday): nth = (n, weekday)
            }
        }
        self.daysOfMonth = days
        self.nthWeekday = nth
        self.monthOfYear = recurrence.month
        self.end = recurrence.end
    }
}

// MARK: – Anwendung (EventKit)

/// Spiegelt die Habits in einen EIGENEN Kalender „hAiity" — der erscheint in
/// Apple Kalender und, wenn das Standard-Konto ein Google-Konto ist, auch in
/// Google Kalender (der Kalender entsteht im KONTO des Standardkalenders).
///
/// **Warum Vollzugriff.** Nur-Schreiben reicht zum ANLEGEN, aber nicht zum
/// Pflegen: Aktualisieren und Entfernen brauchen `event(withIdentifier:)` —
/// ein Lesen. Ohne Pflege blieben umbenannte, verschobene und archivierte
/// Habits als Geister-Termine stehen. Gelesen wird trotzdem nur, was die App
/// selbst geschrieben hat (über die gemerkten Kennungen).
///
/// **Gerätelokal.** Der Schalter und die Kennungen wohnen in den
/// App-Group-Defaults, NICHT in data.json: Ereignis-Kennungen gelten je
/// Gerät, und jedes Gerät entscheidet selbst, ob es den Kalender führt.
@MainActor
enum CalendarSync {
    static let enabledKey = "calendarSyncEnabled"
    static let calendarKey = "calendarSyncCalendar"
    static let mapKey = "calendarSyncEvents"
    static let fingerprintKey = "calendarSyncFingerprints"
    static let calendarTitle = "hAiity"

    private static let store = EKEventStore()

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard
    }

    static var isEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    /// Der eine Ort, der den System-Dialog auslösen darf — beim aktiven
    /// Einschalten in „Mehr", nie beim Start.
    static func requestAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return true
        case .notDetermined:
            return (try? await store.requestFullAccessToEvents()) ?? false
        default: return false
        }
    }

    static var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Alles abgleichen: fehlende Termine anlegen, veränderte neu schreiben,
    /// verwaiste entfernen. Idempotent; ohne Schalter oder Zugriff ein No-op
    /// (beim AUSschalten räumt `disable()` auf).
    ///
    /// `validate` prüft zusätzlich, ob die gemerkten Termine noch existieren
    /// (heilt vom Nutzer gelöschte Serien) — das kostet je Habit einen
    /// EventKit-Zugriff. Der Start übergibt `true`; der Check-in-Pfad `false`,
    /// damit ein unveränderter Bestand KEINEN EventKit-Aufruf auslöst.
    static func reconcile(habits: [Habit], validate: Bool = true) {
        guard isEnabled, hasAccess else { return }

        var map = (defaults.dictionary(forKey: mapKey) as? [String: String]) ?? [:]
        var prints = (defaults.dictionary(forKey: fingerprintKey) as? [String: String]) ?? [:]

        let active = habits.filter { $0.archivedAt == nil }
        let plans = active.compactMap { habit in
            CalendarEventPlan(habit: habit).map { (habit.id.uuidString, $0) }
        }
        if !validate {
            let wanted = Set(plans.map(\.0))
            let unchanged = Set(map.keys) == wanted && plans.allSatisfy {
                prints[$0.0] == $0.1.fingerprint
            }
            if unchanged { return }
        }

        guard let calendar = ensureCalendar() else {
            trace("calsync: no calendar (sources: \(store.sources.map(\.title)))")
            return
        }
        trace("calsync: reconcile into '\(calendar.title)' source=\(calendar.source?.title ?? "nil")")

        var seen: Set<String> = []
        for habit in active {
            let key = habit.id.uuidString
            guard let plan = CalendarEventPlan(habit: habit) else {
                removeEvent(for: key, map: &map, prints: &prints)
                continue
            }
            seen.insert(key)
            if prints[key] == plan.fingerprint, map[key] != nil,
               !validate || store.event(withIdentifier: map[key]!) != nil {
                continue
            }
            // Neu schreiben statt umbiegen: eine geänderte Wiederholungs-
            // regel sauber auf einer bestehenden Serie zu ändern ist ein
            // Minenfeld — Entfernen + Anlegen ist idempotent und eindeutig.
            removeEvent(for: key, map: &map, prints: &prints)
            if let id = createEvent(plan: plan, in: calendar) {
                map[key] = id
                prints[key] = plan.fingerprint
            }
        }

        // Verwaiste (gelöschte/archivierte Habits) räumen.
        for key in map.keys where !seen.contains(key) {
            removeEvent(for: key, map: &map, prints: &prints)
        }

        defaults.set(map, forKey: mapKey)
        defaults.set(prints, forKey: fingerprintKey)
    }

    /// Ausschalten: alle eigenen Termine entfernen, Kennungen vergessen.
    /// Der (leere) Kalender bleibt stehen — ihn löschen hieße, bei jedem
    /// Umschalten das Konto umzupflügen.
    static func disable() {
        isEnabled = false
        guard hasAccess else { return }
        var map = (defaults.dictionary(forKey: mapKey) as? [String: String]) ?? [:]
        var prints = (defaults.dictionary(forKey: fingerprintKey) as? [String: String]) ?? [:]
        for key in Array(map.keys) {
            removeEvent(for: key, map: &map, prints: &prints)
        }
        defaults.removeObject(forKey: mapKey)
        defaults.removeObject(forKey: fingerprintKey)
    }

    // MARK: – Bausteine

    private static func removeEvent(for key: String,
                                    map: inout [String: String],
                                    prints: inout [String: String]) {
        if let id = map[key], let event = store.event(withIdentifier: id) {
            try? store.remove(event, span: .futureEvents, commit: true)
        }
        map[key] = nil
        prints[key] = nil
    }

    /// Der eigene Kalender — angelegt im Konto des Standardkalenders, damit
    /// er dort erscheint, wo die Termine des Nutzers ohnehin wohnen (bei
    /// einem Google-Standardkonto also in Google Kalender).
    private static func ensureCalendar() -> EKCalendar? {
        if let id = defaults.string(forKey: calendarKey),
           let existing = store.calendar(withIdentifier: id) {
            return existing
        }
        if let existing = store.calendars(for: .event)
            .first(where: { $0.title == calendarTitle }) {
            defaults.set(existing.calendarIdentifier, forKey: calendarKey)
            return existing
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = calendarTitle
        calendar.source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .calDAV }
            ?? store.sources.first { $0.sourceType == .local }
        guard calendar.source != nil else { return nil }
        do {
            try store.saveCalendar(calendar, commit: true)
            defaults.set(calendar.calendarIdentifier, forKey: calendarKey)
            return calendar
        } catch {
            // Manche Konten verbieten neue Kalender — dann eben der
            // Standardkalender: lieber Termine im Hauptkalender als keine.
            return store.defaultCalendarForNewEvents
        }
    }

    private static func createEvent(plan: CalendarEventPlan,
                                    in calendar: EKCalendar) -> String? {
        guard let day = DayKey.date(from: plan.firstDay) else { return nil }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = plan.title
        event.notes = "hAiity"
        event.url = URL(string: "haiity://habits")
        if let minutes = plan.minutes {
            let start = Calendar.current.date(byAdding: .minute, value: minutes, to: day) ?? day
            event.startDate = start
            event.endDate = start.addingTimeInterval(TimeInterval(plan.durationMinutes * 60))
        } else {
            event.isAllDay = true
            event.startDate = day
            event.endDate = day
        }
        event.recurrenceRules = [recurrenceRule(for: plan)]
        // BEWUSST ohne Hinweiston: erinnern tut hAiity selbst (Reminders);
        // der Kalendereintrag ist nur das Bild des Tages. Zwei Wecker für
        // denselben Habit wären Lärm.
        event.alarms = nil
        do {
            try store.save(event, span: .futureEvents, commit: true)
            trace("calsync: saved '\(plan.title)' id=\(event.eventIdentifier ?? "nil")")
            return event.eventIdentifier
        } catch {
            trace("calsync: save FAILED '\(plan.title)': \(error)")
            return nil
        }
    }

    private static func recurrenceRule(for plan: CalendarEventPlan) -> EKRecurrenceRule {
        let frequency: EKRecurrenceFrequency
        switch plan.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        }
        var days: [EKRecurrenceDayOfWeek]?
        var setPositions: [NSNumber]?
        if !plan.weekdays.isEmpty {
            days = plan.weekdays.compactMap { EKWeekday(rawValue: $0) }
                .map { EKRecurrenceDayOfWeek($0) }
        }
        if let nth = plan.nthWeekday, let weekday = EKWeekday(rawValue: nth.weekday) {
            days = [EKRecurrenceDayOfWeek(weekday)]
            setPositions = [NSNumber(value: nth.nth)]
        }
        var end: EKRecurrenceEnd?
        switch plan.end {
        case .never: end = nil
        case .on(let dayKey):
            if let date = DayKey.date(from: dayKey) {
                end = EKRecurrenceEnd(end: date.addingTimeInterval(24 * 3600 - 1))
            }
        case .after(let count):
            end = EKRecurrenceEnd(occurrenceCount: max(1, count))
        }
        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: max(1, plan.interval),
            daysOfTheWeek: days,
            daysOfTheMonth: plan.daysOfMonth.isEmpty ? nil : plan.daysOfMonth.map(NSNumber.init),
            monthsOfTheYear: plan.monthOfYear.map { [NSNumber(value: $0)] },
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: setPositions,
            end: end)
    }
}
