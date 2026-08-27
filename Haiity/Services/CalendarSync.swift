import Foundation
import EventKit

struct CalendarSyncSelection: Equatable {
    var habits: Bool
    var reminders: Bool

    func includes(_ item: Habit) -> Bool {
        item.calendarSyncEnabled && (item.isReminder ? reminders : habits)
    }
}

enum CalendarFeatureGate {
    static func canEnable(unlocked: Bool) -> Bool { unlocked }
}

enum NativeReminderToggleAction: Equatable {
    case disable
    case showPaywall
    case requestAccess

    static func action(for on: Bool, unlocked: Bool) -> Self {
        guard on else { return .disable }
        guard CalendarFeatureGate.canEnable(unlocked: unlocked) else {
            return .showPaywall
        }
        return .requestAccess
    }
}

enum CalendarSyncPreferences {
    static let legacyEnabledKey = "calendarSyncEnabled"
    static let habitsEnabledKey = "calendarSyncHabitsEnabled"
    static let remindersEnabledKey = "calendarSyncRemindersEnabled"
    static let habitsCalendarKey = "calendarSyncHabitsCalendar"
    static let remindersCalendarKey = "calendarSyncRemindersCalendar"

    static func calendarID(isReminder: Bool, in defaults: UserDefaults) -> String? {
        defaults.string(forKey: isReminder ? remindersCalendarKey : habitsCalendarKey)
    }

    static func setCalendarID(_ id: String?, isReminder: Bool, in defaults: UserDefaults) {
        let key = isReminder ? remindersCalendarKey : habitsCalendarKey
        defaults.set(id, forKey: key)
    }

    static func selection(in defaults: UserDefaults) -> CalendarSyncSelection {
        let habits = defaults.object(forKey: habitsEnabledKey) == nil
            ? defaults.bool(forKey: legacyEnabledKey)
            : defaults.bool(forKey: habitsEnabledKey)
        return CalendarSyncSelection(
            habits: habits,
            reminders: defaults.bool(forKey: remindersEnabledKey))
    }
}

// MARK: – Der Plan (pur)

/// Ein Habit als Kalender-Termin — die REGELN pur und ohne EventKit, damit
/// die Abbildung (Wiederholung, Uhrzeit, Ende) im Test steht.
///
/// Nicht jedes Habit gehört in einen Kalender: flexible Ziele OHNE
/// Wochentags-Verabredung („3× pro Woche, irgendwann") haben keinen Termin,
/// den man eintragen könnte — sie liefern keinen Plan. Flexible Ziele MIT
/// Verabredung erscheinen an genau diesen Wochentagen.
struct CalendarEventPlan: Equatable {
    let habitID: UUID
    let isReminder: Bool
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
    /// Exact month/day pairs for a yearly multi-date rule.
    var monthDays: [Recurrence.MonthDay]
    /// „n-ter Wochentag im Monat" (nth, weekday); nth -1 = letzter.
    var nthWeekday: (nth: Int, weekday: Int)?
    /// Monat fürs Jahres-Muster.
    var monthOfYear: Int?
    var end: Recurrence.End
    /// The timezone used to interpret the first day and event time. It is
    /// part of the fingerprint so changing a habit's timezone moves the
    /// native event instead of leaving the old entry in place.
    let timeZoneIdentifier: String

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
        let monthDaysKey: String = monthDays.map { "\($0.month).\($0.day)" }.joined(separator: ",")
        let monthKey: String = monthOfYear.map { String($0) } ?? "-"
        var parts: [String] = [isReminder ? "reminder" : "habit", title, firstDay, time,
                               timeZoneIdentifier]
        parts.append(String(durationMinutes))
        parts.append(frequency.rawValue)
        parts.append(String(interval))
        parts.append(weekdayKey)
        parts.append(monthDayKey)
        parts.append(monthDaysKey)
        parts.append(nth)
        parts.append(monthKey)
        parts.append(endKey)
        return parts.joined(separator: "|")
    }

    /// nil = dieses Habit gehört (so) nicht in den Kalender.
    init?(habit: Habit, today: String? = nil,
          calendar: Calendar = .current,
          defaultTimeZoneIdentifier: String? = nil) {
        guard habit.archivedAt == nil else { return nil }
        let itemCalendar = HabitTimeZone.calendar(
            for: habit,
            defaultIdentifier: defaultTimeZoneIdentifier,
            base: calendar)
        let effectiveToday = today ?? DayKey.today(calendar: itemCalendar)
        let recurrence = habit.recurrence

        // Flexible Ziele: nur mit Wochentags-Verabredung — und dann als
        // schlichtes Wochenmuster an genau diesen Tagen.
        if recurrence.isFlexible, recurrence.weekdays.isEmpty { return nil }

        // Erster Termin: heute, wenn fällig — sonst der nächste. Für
        // flexible Regeln zählt die VERABREDUNG (nicht `isScheduled`, das
        // in der Periode überall wahr ist).
        func isAgreedDay(_ day: String) -> Bool {
            if recurrence.isFlexible {
                guard let date = DayKey.date(from: day, calendar: itemCalendar) else { return false }
                return recurrence.weekdays.contains(itemCalendar.component(.weekday, from: date))
            }
            return GoalEngine.isScheduled(habit: habit, day: day, calendar: itemCalendar)
        }
        var first: String? = isAgreedDay(effectiveToday) ? effectiveToday : nil
        if first == nil {
            var candidate = effectiveToday
            // Verabredete Tage liegen höchstens eine Woche voraus; feste
            // Regeln beantwortet `nextOccurrence`.
            if recurrence.isFlexible {
                for _ in 0..<7 {
                    guard let next = DayKey.shifted(candidate, by: 1, calendar: itemCalendar) else { break }
                    candidate = next
                    if isAgreedDay(candidate) { first = candidate; break }
                }
            } else {
                first = recurrence.nextOccurrence(after: effectiveToday, calendar: itemCalendar)
            }
        }
        guard let firstDay = first else { return nil }

        self.habitID = habit.id
        self.isReminder = habit.isReminder
        let baseTitle = habit.emoji.isEmpty ? habit.name : "\(habit.emoji) \(habit.name)"
        self.title = recurrence.endTitle.map { "\(baseTitle) · \($0)" } ?? baseTitle
        self.firstDay = firstDay
        self.minutes = Habit.sanitizedMinutes(habit.timeMinutes ?? habit.reminderMinutes)
        self.durationMinutes = Habit.sanitizedDuration(habit.durationMinutes) ?? 30
        self.frequency = recurrence.isFlexible ? .weekly : recurrence.frequency
        self.interval = recurrence.interval
        self.weekdays = recurrence.weekdays.sorted()
        var days: [Int] = []
        var monthDays: [Recurrence.MonthDay] = []
        var nth: (Int, Int)?
        if let rule = recurrence.rule {
            switch rule {
            case .dayOfMonth(let day): days = [day]
            case .lastDayOfMonth: days = [-1]
            case .nthWeekday(let n, let weekday): nth = (n, weekday)
            case .multipleDays(let values): days = values.sorted()
            case .multipleMonthDays(let values): monthDays = values.sorted()
            }
        }
        self.daysOfMonth = days
        self.monthDays = monthDays
        self.nthWeekday = nth
        self.monthOfYear = monthDays.isEmpty ? recurrence.month : nil
        self.end = recurrence.end
        self.timeZoneIdentifier = itemCalendar.timeZone.identifier
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
    static let enabledKey = CalendarSyncPreferences.legacyEnabledKey
    static let habitsEnabledKey = CalendarSyncPreferences.habitsEnabledKey
    static let remindersEnabledKey = CalendarSyncPreferences.remindersEnabledKey
    nonisolated static let habitsCalendarKey = CalendarSyncPreferences.habitsCalendarKey
    nonisolated static let remindersCalendarKey = CalendarSyncPreferences.remindersCalendarKey
    static let calendarKey = "calendarSyncCalendar"
    static let mapKey = "calendarSyncEvents"
    static let fingerprintKey = "calendarSyncFingerprints"
    static let calendarTitle = "hAiity"
    nonisolated static let habitsCalendarTitle = "hAiity Habits"
    nonisolated static let remindersCalendarTitle = "hAiity Reminders"

    nonisolated static func destinationTitle(isReminder: Bool) -> String {
        isReminder ? remindersCalendarTitle : habitsCalendarTitle
    }

    private static let store = EKEventStore()

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard
    }

    static var syncHabits: Bool {
        get { CalendarSyncPreferences.selection(in: defaults).habits }
        set { defaults.set(newValue, forKey: habitsEnabledKey) }
    }

    static var syncReminders: Bool {
        get { CalendarSyncPreferences.selection(in: defaults).reminders }
        set { defaults.set(newValue, forKey: remindersEnabledKey) }
    }

    static var isEnabled: Bool {
        get { syncHabits || syncReminders }
        set {
            syncHabits = newValue
            if !newValue { syncReminders = false }
        }
    }

    /// Der eine Ort, der den System-Dialog auslösen darf — beim aktiven
    /// Einschalten in „Mehr", nie beim Start.
    static func requestAccess() async -> Bool {
        guard Pro.isUnlocked else { return false }
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

    /// Der Titel des Kalenders, den hAiity WIRKLICH führt — oder `nil`.
    ///
    /// **Warum nicht `calendarTitle`.** Das ist die Konstante, MIT der ein
    /// Kalender angelegt wird: Sie stünde auch dann da, wenn `ensureCalendar()`
    /// mangels Quelle gar keinen anlegen konnte, wenn der Zugriff fehlt oder
    /// wenn der Nutzer ihn in der Kalender-App umbenannt hat. Für die
    /// Diagnose („meine Habits stehen nicht im Kalender") wäre genau das der
    /// unfälschbare Wert — die Frage bliebe unbeantwortet.
    ///
    /// Gelesen wird ausschließlich über die gemerkte Kennung, also nur der
    /// eigene Kalender; angelegt, gesucht und geschrieben wird nichts.
    static var activeCalendarTitle: String? {
        guard hasAccess, let id = defaults.string(forKey: calendarKey) else { return nil }
        return store.calendar(withIdentifier: id)?.title
    }

    /// Alles abgleichen: fehlende Termine anlegen, veränderte neu schreiben,
    /// verwaiste entfernen. Idempotent; ohne Schalter oder Zugriff ein No-op
    /// (beim AUSschalten räumt `disable()` auf).
    ///
    /// `validate` prüft zusätzlich, ob die gemerkten Termine noch existieren
    /// (heilt vom Nutzer gelöschte Serien) — das kostet je Habit einen
    /// EventKit-Zugriff. Der Start übergibt `true`; der Check-in-Pfad `false`,
    /// damit ein unveränderter Bestand KEINEN EventKit-Aufruf auslöst.
    static func reconcile(habits: [Habit],
                          defaultTimeZoneIdentifier: String? = nil,
                          validate: Bool = true) {
        guard Pro.isUnlocked else { return }
        guard isEnabled, hasAccess else { return }

        var map = (defaults.dictionary(forKey: mapKey) as? [String: String]) ?? [:]
        var prints = (defaults.dictionary(forKey: fingerprintKey) as? [String: String]) ?? [:]

        let selection = CalendarSyncSelection(habits: syncHabits, reminders: syncReminders)
        let active = habits.filter { $0.archivedAt == nil && selection.includes($0) }
        let plans = active.compactMap { habit in
            CalendarEventPlan(habit: habit,
                              defaultTimeZoneIdentifier: defaultTimeZoneIdentifier)
                .map { (habit.id.uuidString, $0) }
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

        // A stored event ID is only a fast path. Older builds and interrupted
        // writes can leave several owned series behind, so inventory the
        // watermark before deciding which ID to reuse.
        removeLegacyOwnedItems()
        let plansByOwner = Dictionary(uniqueKeysWithValues: plans.compactMap { entry
            -> (SyncWatermark.Ownership, CalendarEventPlan)? in
            guard let id = UUID(uuidString: entry.0) else { return nil }
            let kind: SyncWatermark.Kind = entry.1.isReminder
                ? .reminderCalendar : .habitCalendar
            return (SyncWatermark.Ownership(kind: kind, id: id), entry.1)
        })
        let ownedByOwner = ownedEvents().reduce(into: [SyncWatermark.Ownership: [EKEvent]]()) {
            result, event in
            guard let notes = event.notes,
                  let owner = SyncWatermark.ownership(in: notes) else { return }
            result[owner, default: []].append(event)
        }
        var validatedKeys = Set<String>()
        var validatedEvents: [String: EKEvent] = [:]
        var removedSeries = Set<String>()
        for (owner, events) in ownedByOwner {
            guard plansByOwner[owner] != nil else {
                for event in events {
                    removeOwnedEvent(event, removedSeries: &removedSeries)
                }
                continue
            }

            let targetEvents = events.filter {
                $0.calendar?.calendarIdentifier == calendar.calendarIdentifier
            }
            let candidates = targetEvents.compactMap { event
                -> (id: String, sortKey: String)? in
                guard let id = nativeID(for: event) else { return nil }
                return (id: id, sortKey: eventSortKey(event))
            }
            let selection = SyncWatermark.selectCanonicalItem(
                candidates: candidates,
                preferredID: map[owner.id.uuidString])
            let retainedID = selection.retainedID
            let targetIDs = Set(candidates.map { $0.id })
            for event in events {
                guard let id = nativeID(for: event) else { continue }
                let keep = id == retainedID
                    && targetIDs.contains(id)
                    && !selection.duplicateIDs.contains(id)
                if !keep {
                    removeOwnedEvent(event, removedSeries: &removedSeries)
                }
            }
            if let retainedID,
               let retainedEvent = targetEvents.first(where: {
                   nativeID(for: $0) == retainedID
               }) {
                let key = owner.id.uuidString
                map[key] = retainedID
                validatedKeys.insert(key)
                validatedEvents[key] = retainedEvent
            } else {
                map[owner.id.uuidString] = nil
            }
        }

        var seen: Set<String> = []
        for habit in active {
            let key = habit.id.uuidString
            guard let plan = CalendarEventPlan(
                habit: habit,
                defaultTimeZoneIdentifier: defaultTimeZoneIdentifier) else {
                removeEvent(for: key, map: &map, prints: &prints)
                continue
            }
            seen.insert(key)
            if prints[key] == plan.fingerprint, map[key] != nil,
               !validate || validatedKeys.contains(key) {
                continue
            }
            // Neu schreiben statt umbiegen: eine geänderte Wiederholungs-
            // regel sauber auf einer bestehenden Serie zu ändern ist ein
            // Minenfeld — Entfernen + Anlegen ist idempotent und eindeutig.
            if !removeEvent(for: key,
                            map: &map,
                            prints: &prints,
                            existing: validatedEvents[key]) {
                continue
            }
            if let id = createEvent(plan: plan, in: calendar) {
                map[key] = id
                prints[key] = plan.fingerprint
            }
        }

        // Verwaiste (gelöschte/archivierte Habits) räumen.
        for key in Array(map.keys) where !seen.contains(key) {
            removeEvent(for: key, map: &map, prints: &prints)
        }

        defaults.set(map, forKey: mapKey)
        defaults.set(prints, forKey: fingerprintKey)
    }

    /// Removes every Calendar item carrying hAiity's current or legacy
    /// ownership marker. This is used during reinstall recovery and explicit
    /// cleanup because native event IDs do not survive a fresh app-group
    /// container.
    static func removeAllOwnedItems() -> Bool {
        guard hasAccess else { return false }

        let calendars = store.calendars(for: .event)
        let start = Calendar.current.date(byAdding: .year, value: -100, to: .now) ?? .distantPast
        let end = Calendar.current.date(byAdding: .year, value: 100, to: .now) ?? .distantFuture
        let predicate = store.predicateForEvents(withStart: start,
                                                  end: end,
                                                  calendars: calendars)
        // EventKit can return recurring occurrences in an unspecified order.
        // Removing the earliest occurrence with `.futureEvents` removes the
        // whole series, including all entries the app may have created before
        // the reinstall.
        let events = store.events(matching: predicate).sorted {
            ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast)
        }
        var removedIDs = Set<String>()
        var succeeded = true
        for event in events {
            guard let notes = event.notes,
                  SyncWatermark.containsMarker(notes) else {
                continue
            }
            let isCurrentOwnedItem = SyncWatermark.ownership(in: notes).map { ownership in
                ownership.kind == .habitCalendar || ownership.kind == .reminderCalendar
            } ?? false
            let isLegacyOwnedItem = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                == SyncWatermark.readablePrefix
            guard isCurrentOwnedItem || isLegacyOwnedItem else {
                continue
            }
            let identity = event.calendarItemIdentifier
            guard !removedIDs.contains(identity) else { continue }
            do {
                try store.remove(event, span: .futureEvents, commit: false)
                removedIDs.insert(identity)
            } catch {
                succeeded = false
            }
        }
        if !removedIDs.isEmpty {
            do { try store.commit() }
            catch { succeeded = false }
        }
        guard succeeded else { return false }
        defaults.removeObject(forKey: mapKey)
        defaults.removeObject(forKey: fingerprintKey)
        defaults.removeObject(forKey: calendarKey)
        return true
    }

    /// Ausschalten: alle eigenen Termine entfernen, Kennungen vergessen.
    /// Der (leere) Kalender bleibt stehen — ihn löschen hieße, bei jedem
    /// Umschalten das Konto umzupflügen.
    static func disable() {
        syncHabits = false
        syncReminders = false
        guard hasAccess else { return }
        var map = (defaults.dictionary(forKey: mapKey) as? [String: String]) ?? [:]
        var prints = (defaults.dictionary(forKey: fingerprintKey) as? [String: String]) ?? [:]
        for key in Array(map.keys) {
            _ = removeEvent(for: key, map: &map, prints: &prints)
        }
        if map.isEmpty {
            defaults.removeObject(forKey: mapKey)
        } else {
            defaults.set(map, forKey: mapKey)
        }
        if prints.isEmpty {
            defaults.removeObject(forKey: fingerprintKey)
        } else {
            defaults.set(prints, forKey: fingerprintKey)
        }
    }

    // MARK: – Bausteine

    private static func allEvents() -> [EKEvent] {
        let calendars = store.calendars(for: .event)
        guard !calendars.isEmpty else { return [] }
        let start = Calendar.current.date(byAdding: .year, value: -100, to: .now) ?? .distantPast
        let end = Calendar.current.date(byAdding: .year, value: 100, to: .now) ?? .distantFuture
        let predicate = store.predicateForEvents(withStart: start,
                                                  end: end,
                                                  calendars: calendars)
        var seenSeries = Set<String>()
        return store.events(matching: predicate)
            .sorted { eventSortKey($0) < eventSortKey($1) }
            .filter { seenSeries.insert($0.calendarItemIdentifier).inserted }
    }

    private static func ownedEvents() -> [EKEvent] {
        allEvents().filter { event in
            guard let notes = event.notes,
                  let owner = SyncWatermark.ownership(in: notes) else { return false }
            return owner.kind == .habitCalendar || owner.kind == .reminderCalendar
        }
    }

    private static func removeLegacyOwnedItems() {
        var removedSeries = Set<String>()
        for event in allEvents() {
            guard event.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
                    == SyncWatermark.readablePrefix else { continue }
            removeOwnedEvent(event, removedSeries: &removedSeries)
        }
    }

    private static func nativeID(for event: EKEvent) -> String? {
        event.eventIdentifier ?? event.calendarItemIdentifier
    }

    private static func eventSortKey(_ event: EKEvent) -> String {
        let start = event.startDate?.timeIntervalSinceReferenceDate ?? .greatestFiniteMagnitude
        return "\(start)|\(nativeID(for: event) ?? event.calendarItemIdentifier)"
    }

    private static func removeOwnedEvent(_ event: EKEvent,
                                         removedSeries: inout Set<String>) {
        guard removedSeries.insert(event.calendarItemIdentifier).inserted else { return }
        do {
            try store.remove(event, span: .futureEvents, commit: true)
        } catch {
            trace("calsync: remove FAILED '\(event.title ?? "")': \(error)")
        }
    }

    private static func removeEvent(for key: String,
                                    map: inout [String: String],
                                    prints: inout [String: String],
                                    existing: EKEvent? = nil) -> Bool {
        if let event = existing ?? map[key].flatMap({ store.event(withIdentifier: $0) }) {
            do {
                try store.remove(event, span: .futureEvents, commit: true)
            } catch {
                trace("calsync: remove FAILED '\(event.title ?? "")': \(error)")
                return false
            }
        }
        map[key] = nil
        prints[key] = nil
        return true
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
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        guard configure(event: event, for: plan) else { return nil }
        do {
            try store.save(event, span: .futureEvents, commit: true)
            trace("calsync: saved '\(plan.title)' id=\(event.eventIdentifier ?? "nil")")
            return event.eventIdentifier
        } catch {
            trace("calsync: save FAILED '\(plan.title)': \(error)")
            return nil
        }
    }

    @discardableResult
    static func configure(event: EKEvent,
                          for plan: CalendarEventPlan,
                          calendar: Calendar = .current) -> Bool {
        var itemCalendar = calendar
        itemCalendar.timeZone = TimeZone(identifier: plan.timeZoneIdentifier)
            ?? calendar.timeZone
        guard let day = DayKey.date(from: plan.firstDay, calendar: itemCalendar) else { return false }
        event.title = plan.title
        let watermarkKind: SyncWatermark.Kind = plan.isReminder
            ? .reminderCalendar : .habitCalendar
        event.notes = SyncWatermark.note(for: plan.habitID, kind: watermarkKind)
        event.url = URL(string: "haiity://habits")
        if let minutes = plan.minutes {
            let start = itemCalendar.date(byAdding: .minute, value: minutes, to: day) ?? day
            event.startDate = start
            event.endDate = start.addingTimeInterval(TimeInterval(plan.durationMinutes * 60))
            event.isAllDay = false
        } else {
            event.isAllDay = true
            event.startDate = day
            event.endDate = day
        }
        event.recurrenceRules = recurrenceRule(for: plan).map { [$0] }
        // BEWUSST ohne Hinweiston: erinnern tut hAiity selbst (Reminders);
        // der Kalendereintrag ist nur das Bild des Tages. Zwei Wecker für
        // denselben Habit wären Lärm.
        event.alarms = nil
        return true
    }

    static func recurrenceRule(for plan: CalendarEventPlan) -> EKRecurrenceRule? {
        let frequency: EKRecurrenceFrequency
        switch plan.frequency {
        case .once: return nil
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        }
        var days: [EKRecurrenceDayOfWeek]?
        var setPositions: [NSNumber]?
        var daysOfTheYear: [NSNumber]?
        if !plan.weekdays.isEmpty {
            days = plan.weekdays.compactMap { EKWeekday(rawValue: $0) }
                .map { EKRecurrenceDayOfWeek($0) }
        }
        if let nth = plan.nthWeekday, let weekday = EKWeekday(rawValue: nth.weekday) {
            days = [EKRecurrenceDayOfWeek(weekday)]
            setPositions = [NSNumber(value: nth.nth)]
        }
        if !plan.monthDays.isEmpty {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
            daysOfTheYear = plan.monthDays.compactMap { value in
                guard let date = calendar.date(from: DateComponents(year: 2000,
                                                                     month: value.month,
                                                                     day: value.day)) else { return nil }
                return calendar.ordinality(of: .day, in: .year, for: date).map(NSNumber.init)
            }
            days = nil
            setPositions = nil
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
            daysOfTheMonth: plan.monthDays.isEmpty && !plan.daysOfMonth.isEmpty
                ? plan.daysOfMonth.map(NSNumber.init) : nil,
            monthsOfTheYear: plan.monthDays.isEmpty
                ? plan.monthOfYear.map { [NSNumber(value: $0)] } : nil,
            weeksOfTheYear: nil,
            daysOfTheYear: daysOfTheYear,
            setPositions: setPositions,
            end: end)
    }
}
