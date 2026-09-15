import Foundation
import EventKit

/// Device-local EventKit snapshot. Calendar identifiers are per-device, so
/// this lives next to the event map rather than in `data.json`.
struct CalendarKitState: Equatable, Sendable {
    var map: [String: String]
    var prints: [String: String]
    var habitsCalendarID: String?
    var remindersCalendarID: String?
    var fallbackCalendarID: String?
    var habitsCalendarTitle: String?
    var remindersCalendarTitle: String?
}

/// Native Calendar notifications re-check persisted event IDs only. The
/// 200-year inventory is reserved for explicit cleanup.
enum CalendarMappedSyncPolicy {
    static let nativeRecheckDelay: Duration = .milliseconds(400)

    static func keysToSync(requested: Set<String>?,
                           wanted: Set<String>,
                           mapped: Set<String>) -> (targets: Set<String>,
                                                    removeOrphans: Bool) {
        guard let requested else {
            return (wanted.union(mapped), true)
        }
        return (requested, false)
    }

    static func needsRewrite(storedFingerprint: String?,
                             planFingerprint: String,
                             mappedEventExists: Bool) -> Bool {
        storedFingerprint != planFingerprint || !mappedEventExists
    }
}

/// Serial EventKit owner. Apple does not allow using one `EKEventStore` on
/// several threads at once; the UI hops here for every native read or write.
actor CalendarEventKit {
    static let shared = CalendarEventKit()

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var isMutating = false

    func requestFullAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func startObservingNativeChanges(_ onChange: @escaping @Sendable () -> Void) {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: nil) { _ in
                onChange()
            }
    }

    func writableOptions() -> [CalendarDestinationOption] {
        store.calendars(for: .event)
            .filter {
                $0.allowsContentModifications
                    && $0.source?.sourceType != .subscribed
                    && $0.source?.sourceType != .birthdays
            }
            .map {
                CalendarDestinationOption(id: $0.calendarIdentifier,
                                           title: $0.title,
                                           sourceTitle: $0.source?.title ?? "")
            }
            .sorted {
                let titleOrder = $0.title.localizedStandardCompare($1.title)
                return titleOrder == .orderedSame ? $0.id < $1.id : titleOrder == .orderedAscending
            }
    }

    func calendarTitle(identifier: String) -> String? {
        store.calendar(withIdentifier: identifier)?.title
    }

    func mappedEventExists(identifier: String) -> Bool {
        store.event(withIdentifier: identifier) != nil
    }

    /// Rewrites only the requested series, looking up EventKit objects by the
    /// persisted identifiers. Removes and creates with `commit: false`, then
    /// commits once.
    func syncMapped(plans: [(String, CalendarEventPlan)],
                    requestedKeys: Set<String>?,
                    state: CalendarKitState) -> CalendarKitState {
        guard !isMutating else { return state }
        isMutating = true
        defer { isMutating = false }

        let original = state
        var state = state
        let wanted = Set(plans.map(\.0))
        let selection = CalendarMappedSyncPolicy.keysToSync(
            requested: requestedKeys,
            wanted: wanted,
            mapped: Set(state.map.keys))
        let plansByKey = Dictionary(uniqueKeysWithValues: plans)
        var calendars: [Bool: EKCalendar] = [:]
        var pendingCommit = false
        var created: [(key: String, event: EKEvent, fingerprint: String)] = []

        if selection.removeOrphans {
            for key in Array(state.map.keys) where !wanted.contains(key) {
                if removeMappedEvent(for: key, state: &state, commit: false) {
                    pendingCommit = true
                }
            }
        }

        for key in selection.targets {
            guard let plan = plansByKey[key] else {
                if removeMappedEvent(for: key, state: &state, commit: false) {
                    pendingCommit = true
                }
                continue
            }
            let exists = state.map[key].flatMap { store.event(withIdentifier: $0) } != nil
            if !CalendarMappedSyncPolicy.needsRewrite(
                storedFingerprint: state.prints[key],
                planFingerprint: plan.fingerprint,
                mappedEventExists: exists) {
                continue
            }
            guard let calendar = resolvedCalendar(isReminder: plan.isReminder,
                                                  state: &state,
                                                  cache: &calendars) else {
                continue
            }
            if !removeMappedEvent(for: key, state: &state, commit: false) {
                continue
            }
            pendingCommit = true
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            guard CalendarSync.configure(event: event, for: plan) else { continue }
            do {
                try store.save(event, span: .futureEvents, commit: false)
                created.append((key, event, plan.fingerprint))
            } catch {
                continue
            }
        }

        if pendingCommit || !created.isEmpty {
            do { try store.commit() }
            catch { return original }
        }
        for item in created {
            if let id = item.event.eventIdentifier {
                state.map[item.key] = id
                state.prints[item.key] = item.fingerprint
            }
        }
        return state
    }

    /// 200-year inventory used only by reinstall recovery and the explicit
    /// native cleanup action.
    func removeAllOwnedItems(state: CalendarKitState) -> (Bool, CalendarKitState) {
        guard !isMutating else { return (false, state) }
        isMutating = true
        defer { isMutating = false }

        let mappedNativeIDs = Set(state.map.values)
        let events = eventsIncludingStoredMappings(state.map).sorted {
            ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast)
        }
        var removedIDs = Set<String>()
        var succeeded = true
        for event in events {
            if let notes = event.notes,
               SyncWatermark.ownership(in: notes)?.kind == .nativeReminder {
                continue
            }
            let isMappedCalendarEvent = event.eventIdentifier.map {
                mappedNativeIDs.contains($0)
            } ?? false
            guard isMappedCalendarEvent || SyncWatermark.isCalendarOwned(
                notes: event.notes,
                urlString: event.url?.absoluteString) else {
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
        if !removeLegacyOwnedItems() {
            succeeded = false
        }
        if !removedIDs.isEmpty {
            do { try store.commit() }
            catch { succeeded = false }
        }
        guard succeeded else { return (false, state) }
        var cleared = state
        cleared.map = [:]
        cleared.prints = [:]
        cleared.habitsCalendarID = nil
        cleared.remindersCalendarID = nil
        cleared.fallbackCalendarID = nil
        cleared.habitsCalendarTitle = nil
        cleared.remindersCalendarTitle = nil
        return (true, cleared)
    }

    // MARK: – Private

    private func resolvedCalendar(isReminder: Bool,
                                  state: inout CalendarKitState,
                                  cache: inout [Bool: EKCalendar]) -> EKCalendar? {
        if let cached = cache[isReminder] { return cached }
        guard let calendar = ensureCalendar(isReminder: isReminder, state: &state) else {
            return nil
        }
        cache[isReminder] = calendar
        return calendar
    }

    private func removeMappedEvent(for key: String,
                                   state: inout CalendarKitState,
                                   commit: Bool) -> Bool {
        if let event = state.map[key].flatMap({ store.event(withIdentifier: $0) }) {
            do {
                try store.remove(event, span: .futureEvents, commit: commit)
            } catch {
                return false
            }
        }
        state.map[key] = nil
        state.prints[key] = nil
        return true
    }

    private func ensureCalendar(isReminder: Bool,
                                state: inout CalendarKitState) -> EKCalendar? {
        let storedID = isReminder ? state.remindersCalendarID : state.habitsCalendarID
        if let storedID,
           let existing = store.calendar(withIdentifier: storedID),
           existing.allowsContentModifications {
            remember(calendar: existing, isReminder: isReminder, state: &state)
            return existing
        }
        if storedID != nil {
            if isReminder { state.remindersCalendarID = nil }
            else { state.habitsCalendarID = nil }
        }
        let title = CalendarSync.destinationTitle(isReminder: isReminder)
        if let existing = store.calendars(for: .event)
            .first(where: { $0.title == title && $0.allowsContentModifications }) {
            remember(calendar: existing, isReminder: isReminder, state: &state)
            return existing
        }
        if let fallbackID = state.fallbackCalendarID,
           let existing = store.calendar(withIdentifier: fallbackID),
           existing.allowsContentModifications {
            return existing
        }
        let sourceCandidates = store.sources.filter {
            $0.sourceType != .subscribed && $0.sourceType != .birthdays
        }
        let sourcesByID = Dictionary(uniqueKeysWithValues: sourceCandidates.map {
            ($0.sourceIdentifier, $0)
        })
        let preferredID = store.defaultCalendarForNewEvents?.source?.sourceIdentifier
        for sourceID in CalendarSync.orderedSourceIDs(
            preferredID: preferredID,
            fallbackIDs: sourceCandidates.map(\.sourceIdentifier)) {
            guard let source = sourcesByID[sourceID] else { continue }
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = title
            calendar.source = source
            do {
                try store.saveCalendar(calendar, commit: true)
                remember(calendar: calendar, isReminder: isReminder, state: &state)
                return calendar
            } catch {
                continue
            }
        }
        let fallback = store.defaultCalendarForNewEvents
            .flatMap { $0.allowsContentModifications ? $0 : nil }
            ?? store.calendars(for: .event).first(where: { $0.allowsContentModifications })
        guard let fallback, fallback.allowsContentModifications else {
            return nil
        }
        state.fallbackCalendarID = fallback.calendarIdentifier
        return fallback
    }

    private func remember(calendar: EKCalendar,
                          isReminder: Bool,
                          state: inout CalendarKitState) {
        if isReminder {
            state.remindersCalendarID = calendar.calendarIdentifier
            state.remindersCalendarTitle = calendar.title
        } else {
            state.habitsCalendarID = calendar.calendarIdentifier
            state.habitsCalendarTitle = calendar.title
        }
    }

    private func allEvents() -> [EKEvent] {
        let calendars = store.calendars(for: .event)
        guard !calendars.isEmpty else { return [] }
        var seenSeries = Set<String>()
        var events: [EKEvent] = []
        let now = Date.now
        var startYear = -100
        while startYear < 100 {
            guard let start = Calendar.current.date(byAdding: .year,
                                                    value: startYear,
                                                    to: now),
                  let end = Calendar.current.date(byAdding: .year,
                                                  value: startYear + 10,
                                                  to: now) else {
                startYear += 10
                continue
            }
            let predicate = store.predicateForEvents(withStart: start,
                                                      end: end,
                                                      calendars: calendars)
            for event in store.events(matching: predicate)
                where seenSeries.insert(event.calendarItemIdentifier).inserted {
                events.append(event)
            }
            startYear += 10
        }
        return events.sorted { eventSortKey($0) < eventSortKey($1) }
    }

    private func eventsIncludingStoredMappings(_ map: [String: String]) -> [EKEvent] {
        var events = allEvents()
        var seenSeries = Set(events.map(\.calendarItemIdentifier))
        for event in map.values.compactMap({ store.event(withIdentifier: $0) })
            where seenSeries.insert(event.calendarItemIdentifier).inserted {
            events.append(event)
        }
        return events.sorted { eventSortKey($0) < eventSortKey($1) }
    }

    private func ownedEvents() -> [EKEvent] {
        allEvents().filter { event in
            guard let notes = event.notes,
                  let owner = SyncWatermark.ownership(in: notes) else { return false }
            return owner.kind == .habitCalendar || owner.kind == .reminderCalendar
        }
    }

    private func removeLegacyOwnedItems() -> Bool {
        var removedSeries = Set<String>()
        var succeeded = true
        for event in allEvents() {
            guard SyncWatermark.isCalendarOwned(
                notes: event.notes,
                urlString: event.url?.absoluteString),
                  SyncWatermark.ownership(in: event.notes ?? "") == nil else { continue }
            guard removedSeries.insert(event.calendarItemIdentifier).inserted else { continue }
            do {
                try store.remove(event, span: .futureEvents, commit: false)
            } catch {
                succeeded = false
            }
        }
        return succeeded
    }

    private func nativeID(for event: EKEvent) -> String? {
        event.eventIdentifier ?? event.calendarItemIdentifier
    }

    private func eventSortKey(_ event: EKEvent) -> String {
        let start = event.startDate?.timeIntervalSinceReferenceDate ?? .greatestFiniteMagnitude
        return "\(start)|\(nativeID(for: event) ?? event.calendarItemIdentifier)"
    }
}
