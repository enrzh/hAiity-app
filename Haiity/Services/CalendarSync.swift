import Foundation
import EventKit

struct CalendarSyncSelection: Equatable {
    var habits: Bool
    var reminders: Bool

    func includes(_ item: Habit) -> Bool {
        item.calendarSyncEnabled && (item.isReminder ? reminders : habits)
    }
}

struct CalendarDestinationOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let sourceTitle: String
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

    static func calendarTitleKey(isReminder: Bool) -> String {
        isReminder ? "calendarSyncRemindersCalendarTitle" : "calendarSyncHabitsCalendarTitle"
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
struct CalendarEventPlan: Equatable, Sendable {
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
    nonisolated static let calendarKey = "calendarSyncCalendar"
    nonisolated static let fallbackCalendarKey = "calendarSyncFallbackCalendar"
    static let mapKey = "calendarSyncEvents"
    static let fingerprintKey = "calendarSyncFingerprints"
    nonisolated static let calendarTitle = "hAiity"
    nonisolated static let habitsCalendarTitle = "hAiity Habits"
    nonisolated static let remindersCalendarTitle = "hAiity Reminders"

    nonisolated static func destinationTitle(isReminder: Bool) -> String {
        isReminder ? remindersCalendarTitle : habitsCalendarTitle
    }

    static func selectedCalendarID(isReminder: Bool) -> String? {
        CalendarSyncPreferences.calendarID(isReminder: isReminder, in: defaults)
    }

    static func setSelectedCalendarID(_ id: String?, isReminder: Bool) {
        CalendarSyncPreferences.setCalendarID(id, isReminder: isReminder, in: defaults)
    }

    static func activeCalendarTitle(isReminder: Bool) -> String? {
        guard hasAccess else { return nil }
        let titleKey = CalendarSyncPreferences.calendarTitleKey(isReminder: isReminder)
        if let title = defaults.string(forKey: titleKey), !title.isEmpty {
            return title
        }
        let calendarKey = isReminder ? remindersCalendarKey : habitsCalendarKey
        if defaults.string(forKey: calendarKey) != nil {
            return destinationTitle(isReminder: isReminder)
        }
        if selectedCalendarID(isReminder: isReminder) != nil {
            return destinationTitle(isReminder: isReminder)
        }
        if defaults.string(forKey: fallbackCalendarKey) != nil {
            return destinationTitle(isReminder: isReminder)
        }
        return nil
    }

    static var writableCalendarOptions: [CalendarDestinationOption] {
        guard hasAccess else { return [] }
        return cachedWritableOptions
    }

    static func refreshDestinationCache() async {
        guard hasAccess else {
            cachedWritableOptions = []
            return
        }
        cachedWritableOptions = await CalendarEventKit.shared.writableOptions()
        await refreshCachedTitles()
    }

    nonisolated static func orderedSourceIDs(preferredID: String?,
                                             fallbackIDs: [String]) -> [String] {
        var result: [String] = []
        for id in ([preferredID].compactMap { $0 } + fallbackIDs)
            where !result.contains(id) {
            result.append(id)
        }
        return result
    }

    private static weak var observedStore: HabitStore?
    private static var isSyncing = false
    private static var nativeRecheckTask: Task<Void, Never>?
    private static var cachedWritableOptions: [CalendarDestinationOption] = []

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
            return await CalendarEventKit.shared.requestFullAccess()
        default: return false
        }
    }

    static var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Re-check mapped native events when the user changes or deletes one in
    /// Apple Calendar. The pass looks up persisted event identifiers only, so
    /// it cannot import unrelated calendar content and never inventories a
    /// 200-year window.
    static func startObserving(store habitStore: HabitStore) {
        observedStore = habitStore
        Task {
            await CalendarEventKit.shared.startObservingNativeChanges {
                Task { @MainActor in
                    handleNativeStoreChange()
                }
            }
        }
    }

    static func handleNativeStoreChange() {
        guard !isSyncing else { return }
        nativeRecheckTask?.cancel()
        nativeRecheckTask = Task { @MainActor in
            try? await Task.sleep(for: CalendarMappedSyncPolicy.nativeRecheckDelay)
            guard !Task.isCancelled, !isSyncing else { return }
            guard let habitStore = observedStore else { return }
            await sync(scope: .allMapped,
                       habits: habitStore.habits,
                       defaultTimeZoneIdentifier: habitStore.defaultTimeZoneIdentifier)
        }
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
    /// Gelesen wird die gemerkte Überschrift, nicht EventKit — damit die
    /// Mehr-Seite und die Diagnose den Main Actor nicht auf den Store
    /// warten.
    static var activeCalendarTitle: String? {
        activeCalendarTitle(isReminder: false) ?? activeCalendarTitle(isReminder: true)
    }

    static var activeCalendarTitles: [String] {
        guard hasAccess else { return [] }
        var titles: [String] = []
        for title in [activeCalendarTitle(isReminder: false),
                      activeCalendarTitle(isReminder: true)].compactMap({ $0 })
            where !titles.contains(title) {
            titles.append(title)
        }
        return titles
    }

    /// Spiegelt geänderte Habits in Calendar. Ein Editor-Save übergibt die
    /// betroffenen Kennungen; Start, Vordergrund und Einstellungen gleichen
    /// die gemerkte Abbildung ab. Die Inventur über alle Kalender bleibt
    /// `removeAllOwnedItems()`.
    static func sync(habitID: UUID,
                     habits: [Habit],
                     defaultTimeZoneIdentifier: String? = nil) async {
        await sync(scope: .items([habitID]),
                   habits: habits,
                   defaultTimeZoneIdentifier: defaultTimeZoneIdentifier)
    }

    static func sync(scope: CalendarSyncScope,
                     habits: [Habit],
                     defaultTimeZoneIdentifier: String? = nil) async {
        guard Pro.isUnlocked else { return }
        guard isEnabled, hasAccess, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let selection = CalendarSyncSelection(habits: syncHabits, reminders: syncReminders)
        let active = habits.filter { $0.archivedAt == nil && selection.includes($0) }
        let plans = active.compactMap { habit in
            CalendarEventPlan(habit: habit,
                              defaultTimeZoneIdentifier: defaultTimeZoneIdentifier)
                .map { (habit.id.uuidString, $0) }
        }
        let next = await CalendarEventKit.shared.syncMapped(
            plans: plans,
            requestedKeys: scope.keys,
            state: currentKitState())
        persist(state: next)
        cachedWritableOptions = await CalendarEventKit.shared.writableOptions()
    }

    /// Voller mapped Abgleich — Start, Vordergrund, Kalenderziel. Niemals
    /// eine 200-Jahre-Inventur.
    static func reconcile(habits: [Habit],
                          defaultTimeZoneIdentifier: String? = nil) async {
        await sync(scope: .allMapped,
                   habits: habits,
                   defaultTimeZoneIdentifier: defaultTimeZoneIdentifier)
    }

    /// Removes every Calendar item carrying hAiity's current or legacy
    /// ownership marker. This is used during reinstall recovery and explicit
    /// cleanup because native event IDs do not survive a fresh app-group
    /// container.
    static func removeAllOwnedItems() async -> Bool {
        guard hasAccess else { return false }
        let (succeeded, next) = await CalendarEventKit.shared.removeAllOwnedItems(
            state: currentKitState())
        persist(state: next)
        if succeeded {
            defaults.removeObject(forKey: calendarKey)
        }
        cachedWritableOptions = []
        return succeeded
    }

    /// Ausschalten: alle eigenen Termine entfernen, Kennungen vergessen.
    /// Der (leere) Kalender bleibt stehen — ihn löschen hieße, bei jedem
    /// Umschalten das Konto umzupflügen.
    static func disable() {
        syncHabits = false
        syncReminders = false
        defaults.removeObject(forKey: fallbackCalendarKey)
        Task { _ = await removeAllOwnedItems() }
    }

    private static func currentKitState() -> CalendarKitState {
        CalendarKitState(
            map: (defaults.dictionary(forKey: mapKey) as? [String: String]) ?? [:],
            prints: (defaults.dictionary(forKey: fingerprintKey) as? [String: String]) ?? [:],
            habitsCalendarID: defaults.string(forKey: habitsCalendarKey),
            remindersCalendarID: defaults.string(forKey: remindersCalendarKey),
            fallbackCalendarID: defaults.string(forKey: fallbackCalendarKey),
            habitsCalendarTitle: defaults.string(
                forKey: CalendarSyncPreferences.calendarTitleKey(isReminder: false)),
            remindersCalendarTitle: defaults.string(
                forKey: CalendarSyncPreferences.calendarTitleKey(isReminder: true)))
    }

    private static func persist(state: CalendarKitState) {
        defaults.set(state.map, forKey: mapKey)
        defaults.set(state.prints, forKey: fingerprintKey)
        CalendarSyncPreferences.setCalendarID(state.habitsCalendarID,
                                              isReminder: false,
                                              in: defaults)
        CalendarSyncPreferences.setCalendarID(state.remindersCalendarID,
                                              isReminder: true,
                                              in: defaults)
        if let fallback = state.fallbackCalendarID {
            defaults.set(fallback, forKey: fallbackCalendarKey)
        } else {
            defaults.removeObject(forKey: fallbackCalendarKey)
        }
        let habitTitleKey = CalendarSyncPreferences.calendarTitleKey(isReminder: false)
        let reminderTitleKey = CalendarSyncPreferences.calendarTitleKey(isReminder: true)
        if let title = state.habitsCalendarTitle {
            defaults.set(title, forKey: habitTitleKey)
        } else {
            defaults.removeObject(forKey: habitTitleKey)
        }
        if let title = state.remindersCalendarTitle {
            defaults.set(title, forKey: reminderTitleKey)
        } else {
            defaults.removeObject(forKey: reminderTitleKey)
        }
    }

    private static func refreshCachedTitles() async {
        if let id = defaults.string(forKey: habitsCalendarKey),
           let title = await CalendarEventKit.shared.calendarTitle(identifier: id) {
            defaults.set(title, forKey: CalendarSyncPreferences.calendarTitleKey(isReminder: false))
        }
        if let id = defaults.string(forKey: remindersCalendarKey),
           let title = await CalendarEventKit.shared.calendarTitle(identifier: id) {
            defaults.set(title, forKey: CalendarSyncPreferences.calendarTitleKey(isReminder: true))
        }
    }

    // MARK: – Abbildung ohne EventKit-Store

    @discardableResult
    nonisolated static func configure(event: EKEvent,
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

    nonisolated static func recurrenceRule(for plan: CalendarEventPlan) -> EKRecurrenceRule? {
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
