import Foundation
import EventKit

struct ReminderSyncLink: Codable, Equatable, Sendable {
    let habitID: UUID
    let reminderID: String
    let occurrenceDay: String
}

struct ReminderSyncPlan: Equatable {
    let habitID: UUID
    let title: String
    let eventPlan: CalendarEventPlan
    let occurrenceDay: String
    let fingerprint: String

    init?(habit: Habit,
          today: String = DayKey.today(),
          calendar: Calendar = .current) {
        guard habit.isReminder, habit.archivedAt == nil,
              let eventPlan = CalendarEventPlan(habit: habit,
                                                today: today,
                                                calendar: calendar),
              let day = DayKey.date(from: today, calendar: calendar) else {
            return nil
        }

        let occurrence = ReminderOccurrenceEngine.state(for: habit,
                                                        now: day,
                                                        calendar: calendar)
            .actionable?.day ?? eventPlan.firstDay
        self.habitID = habit.id
        self.title = eventPlan.title
        self.eventPlan = eventPlan
        self.occurrenceDay = occurrence
        self.fingerprint = [habit.id.uuidString,
                            occurrence,
                            eventPlan.fingerprint].joined(separator: "|")
    }
}

struct ReminderSyncSelection: Equatable {
    let enabled: Bool

    func includes(_ item: Habit) -> Bool {
        enabled && item.isReminder && item.archivedAt == nil && item.calendarSyncEnabled
    }
}

struct ReminderListCandidate: Equatable {
    let id: String
    let title: String
    let isWritable: Bool
}

enum ReminderListResolver {
    static func id(stored: ReminderListCandidate?,
                   calendars: [ReminderListCandidate],
                   title: String) -> String? {
        if let stored, stored.isWritable { return stored.id }
        return calendars.first { $0.title == title && $0.isWritable }?.id
    }
}

enum ReminderSyncPreferences {
    static let enabledKey = "nativeReminderSyncEnabled"
    static let linksKey = "nativeReminderSyncLinks"
    static let fingerprintsKey = "nativeReminderSyncFingerprints"

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    static func setEnabled(_ enabled: Bool, in defaults: UserDefaults) {
        defaults.set(enabled, forKey: enabledKey)
    }

    static func links(in defaults: UserDefaults) -> [String: ReminderSyncLink] {
        guard let data = defaults.data(forKey: linksKey),
              let links = try? JSONDecoder().decode([String: ReminderSyncLink].self,
                                                     from: data) else {
            return [:]
        }
        return links
    }

    static func setLinks(_ links: [String: ReminderSyncLink], in defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(links) else { return }
        defaults.set(data, forKey: linksKey)
    }

    static func fingerprints(in defaults: UserDefaults) -> [String: String] {
        guard let data = defaults.data(forKey: fingerprintsKey),
              let fingerprints = try? JSONDecoder().decode([String: String].self,
                                                             from: data) else {
            return [:]
        }
        return fingerprints
    }

    static func setFingerprints(_ fingerprints: [String: String], in defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(fingerprints) else { return }
        defaults.set(data, forKey: fingerprintsKey)
    }

    static func clearLinks(in defaults: UserDefaults) {
        defaults.removeObject(forKey: linksKey)
        defaults.removeObject(forKey: fingerprintsKey)
    }
}

/// Owns one dedicated Apple Reminders list. Stored identifiers are the
/// ownership boundary: unrelated lists and reminders are never searched or
/// modified.
@MainActor
enum ReminderSync {
    static let listTitle = "hAiity"
    static let listKey = "nativeReminderSyncList"

    private static let store = EKEventStore()
    private static var observer: NSObjectProtocol?
    private static weak var observedStore: HabitStore?
    private static var isReconciling = false
    private static var isPulling = false
    private(set) static var lastError: String?

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard
    }

    static var isEnabled: Bool {
        get { ReminderSyncPreferences.isEnabled(in: defaults) }
        set { ReminderSyncPreferences.setEnabled(newValue, in: defaults) }
    }

    static var hasAccess: Bool {
        isAuthorized(EKEventStore.authorizationStatus(for: .reminder))
    }

    static func requestAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized:
            return true
        case .notDetermined:
            return (try? await store.requestFullAccessToReminders()) ?? false
        default:
            return false
        }
    }

    static func reconcile(habits: [Habit],
                          validate: Bool = true,
                          now: Date = .now,
                          calendar: Calendar = .current) {
        guard isEnabled, hasAccess, !isReconciling, !isPulling else { return }
        isReconciling = true
        lastError = nil
        defer { isReconciling = false }

        var links = ReminderSyncPreferences.links(in: defaults)
        var fingerprints = ReminderSyncPreferences.fingerprints(in: defaults)
        let selection = ReminderSyncSelection(enabled: true)
        let today = DayKey.key(for: now, calendar: calendar)
        let active = habits.filter(selection.includes)
        let plans = active.compactMap {
            ReminderSyncPlan(habit: $0, today: today, calendar: calendar)
        }
        let activeKeys = Set(plans.map { $0.habitID.uuidString })

        guard let list = ensureList() else { return }

        for key in Array(links.keys) where !activeKeys.contains(key) {
            removeReminder(for: key, links: &links, fingerprints: &fingerprints, in: list)
        }

        for plan in plans {
            let key = plan.habitID.uuidString
            let habit = active.first { $0.id == plan.habitID }
            let linked = links[key].flatMap { ownedReminder(id: $0.reminderID, in: list) }
            let fingerprintChanged = fingerprints[key] != plan.fingerprint

            if fingerprintChanged || linked == nil {
                removeReminder(for: key, links: &links, fingerprints: &fingerprints, in: list)
                if let created = createReminder(plan: plan,
                                                completed: habit?.log[plan.occurrenceDay] != nil,
                                                in: list) {
                    links[key] = ReminderSyncLink(habitID: plan.habitID,
                                                  reminderID: created,
                                                  occurrenceDay: plan.occurrenceDay)
                    fingerprints[key] = plan.fingerprint
                }
                continue
            }

            guard let reminder = linked else { continue }
            let completed = habit?.log[plan.occurrenceDay] != nil
            if reminder.isCompleted != completed {
                reminder.isCompleted = completed
                guard save(reminder) else {
                    fingerprints[key] = nil
                    continue
                }
            }
            links[key] = ReminderSyncLink(habitID: plan.habitID,
                                          reminderID: reminder.calendarItemIdentifier,
                                          occurrenceDay: plan.occurrenceDay)
            fingerprints[key] = plan.fingerprint
        }

        ReminderSyncPreferences.setLinks(links, in: defaults)
        ReminderSyncPreferences.setFingerprints(fingerprints, in: defaults)

        // `validate` is intentionally consumed at the boundary. A validating
        // pass repairs deleted native items; normal store changes still push
        // completion and title changes through the same owned links.
        _ = validate
    }

    static func pullCompletions(into habitStore: HabitStore,
                                now: Date = .now,
                                calendar: Calendar = .current) {
        guard isEnabled, hasAccess, !isReconciling, !isPulling else { return }
        isPulling = true
        defer { isPulling = false }

        guard let list = storedList() else { return }
        let links = ReminderSyncPreferences.links(in: defaults)
        for link in links.values {
            guard let habit = habitStore.habits.first(where: { $0.id == link.habitID }),
                  habit.isReminder,
                  let reminder = ownedReminder(id: link.reminderID, in: list) else {
                continue
            }

            let appCompleted = habit.log[link.occurrenceDay] != nil
            guard appCompleted != reminder.isCompleted else { continue }
            let occurrence = ReminderOccurrence(
                day: link.occurrenceDay,
                dueDate: ReminderOccurrenceEngine.dueDate(day: link.occurrenceDay,
                                                          reminder: habit,
                                                          calendar: calendar) ?? now)
            let next = ReminderOccurrenceEngine.cursorAfterCompleting(occurrence,
                                                                        reminder: habit,
                                                                        now: now,
                                                                        calendar: calendar)
            habitStore.setReminderCompletion(habit.id,
                                             day: link.occurrenceDay,
                                             completed: reminder.isCompleted,
                                             nextCursor: next)
        }
    }

    static func pushCompletion(for habit: Habit,
                               habits: [Habit]) {
        guard isEnabled, hasAccess, !isReconciling, !isPulling,
              let link = ReminderSyncPreferences.links(in: defaults)[habit.id.uuidString],
              let list = storedList(),
              let reminder = ownedReminder(id: link.reminderID, in: list),
              let current = habits.first(where: { $0.id == habit.id }) else {
            return
        }
        let completed = current.log[link.occurrenceDay] != nil
        guard reminder.isCompleted != completed else { return }
        reminder.isCompleted = completed
        _ = save(reminder)
    }

    static func startObserving(store habitStore: HabitStore) {
        observedStore = habitStore
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main) { _ in
                Task { @MainActor in
                    guard let habitStore = observedStore else { return }
                    pullCompletions(into: habitStore)
                    reconcile(habits: habitStore.habits, validate: false)
                }
            }
    }

    static func disable() {
        isEnabled = false
        guard hasAccess, let list = storedList() else { return }
        var links = ReminderSyncPreferences.links(in: defaults)
        var fingerprints = ReminderSyncPreferences.fingerprints(in: defaults)
        for key in Array(links.keys) {
            removeReminder(for: key, links: &links, fingerprints: &fingerprints, in: list)
        }
        ReminderSyncPreferences.clearLinks(in: defaults)
    }

    private static func storedList() -> EKCalendar? {
        guard let id = defaults.string(forKey: listKey) else { return nil }
        guard let list = store.calendar(withIdentifier: id),
              store.calendars(for: .reminder).contains(where: { $0.calendarIdentifier == id }) else {
            return nil
        }
        return list
    }

    private static func ensureList() -> EKCalendar? {
        let stored = storedList().map {
            ReminderListCandidate(id: $0.calendarIdentifier,
                                  title: $0.title,
                                  isWritable: $0.allowsContentModifications)
        }
        let candidates = store.calendars(for: .reminder).map {
            ReminderListCandidate(id: $0.calendarIdentifier,
                                  title: $0.title,
                                  isWritable: $0.allowsContentModifications)
        }
        if let id = ReminderListResolver.id(stored: stored,
                                             calendars: candidates,
                                             title: listTitle),
           let list = store.calendar(withIdentifier: id) {
            defaults.set(id, forKey: listKey)
            return list
        }

        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = listTitle
        list.source = writableSource()
        guard list.source != nil else { return nil }
        do {
            try store.saveCalendar(list, commit: true)
            defaults.set(list.calendarIdentifier, forKey: listKey)
            return list
        } catch {
            note(error)
            return nil
        }
    }

    private static func writableSource() -> EKSource? {
        if let source = store.defaultCalendarForNewReminders()?.source {
            return source
        }
        if let source = store.calendars(for: .reminder)
            .first(where: { $0.allowsContentModifications })?.source {
            return source
        }
        return store.sources.first {
            $0.sourceType != .subscribed && $0.sourceType != .birthdays
        }
    }

    private static func ownedReminder(id: String, in list: EKCalendar) -> EKReminder? {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder,
              reminder.calendar?.calendarIdentifier == list.calendarIdentifier else {
            return nil
        }
        return reminder
    }

    private static func removeReminder(for key: String,
                                       links: inout [String: ReminderSyncLink],
                                       fingerprints: inout [String: String],
                                       in list: EKCalendar) {
        if let link = links[key], let reminder = ownedReminder(id: link.reminderID, in: list) {
            try? store.remove(reminder, commit: true)
        }
        links[key] = nil
        fingerprints[key] = nil
    }

    private static func createReminder(plan: ReminderSyncPlan,
                                       completed: Bool,
                                       in list: EKCalendar) -> String? {
        let reminder = EKReminder(eventStore: store)
        guard updateReminder(reminder,
                             plan: plan,
                             completed: completed,
                             in: list) else {
            return nil
        }
        return reminder.calendarItemIdentifier
    }

    @discardableResult
    private static func updateReminder(_ reminder: EKReminder,
                                       plan: ReminderSyncPlan,
                                       completed: Bool,
                                       in list: EKCalendar) -> Bool {
        reminder.calendar = list
        configure(reminder: reminder,
                  for: plan,
                  completed: completed)
        return save(reminder)
    }

    static func configure(reminder: EKReminder,
                          for plan: ReminderSyncPlan,
                          completed: Bool,
                          calendar: Calendar = .current) {
        reminder.title = plan.title
        reminder.notes = "hAiity"
        reminder.dueDateComponents = dueDateComponents(for: plan, calendar: calendar)
        reminder.recurrenceRules = CalendarSync.recurrenceRule(for: plan.eventPlan).map { [$0] }
        reminder.isCompleted = completed
    }

    private static func save(_ reminder: EKReminder) -> Bool {
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            note(error)
            return false
        }
    }

    private static func isAuthorized(_ status: EKAuthorizationStatus) -> Bool {
        status == .fullAccess || status == .authorized
    }

    private static func note(_ error: Error) {
        lastError = error.localizedDescription
        trace("reminders: sync failed: \(error.localizedDescription)")
    }

    private static func dueDateComponents(for plan: ReminderSyncPlan,
                                          calendar: Calendar = .current) -> DateComponents? {
        guard let date = DayKey.date(from: plan.occurrenceDay, calendar: calendar) else { return nil }
        let minutes = Habit.sanitizedMinutes(plan.eventPlan.minutes)
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        if let minutes {
            components.hour = minutes / 60
            components.minute = minutes % 60
        }
        return components
    }
}
