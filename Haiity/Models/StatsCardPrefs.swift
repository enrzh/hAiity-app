import Foundation
import Observation
import SwiftUI

/// Die fünf Statistik-Karten über der Statistikseite. Roh-Wert ist der
/// Speicher-Schlüssel — Umbenennen wäre ein Datenformat-Bruch.
enum StatsCard: String, Codable, CaseIterable, Identifiable, Sendable {
    case yearPulse, streakFlame, todayRing, weekMomentum, totals

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .yearPulse:    return String(localized: "Rhythmus")
        case .streakFlame:  return String(localized: "Aktuelle Serie")
        case .todayRing:    return String(localized: "Heute")
        case .weekMomentum: return String(localized: "Diese Woche")
        case .totals:       return String(localized: "Check-ins")
        }
    }

    /// Ein Satz für die Mehr-Tafel: was die Karte zeigt.
    var detail: String {
        switch self {
        case .yearPulse:
            return String(localized: "Alle Habits als ein Raster über die letzten fünf Monate.")
        case .streakFlame:
            return String(localized: "Deine Gesamt-Serie über alle Habits.")
        case .todayRing:
            return String(localized: "Was heute fällig ist — Segment für Segment.")
        case .weekMomentum:
            return String(localized: "Die Woche im Verlauf, verglichen mit der Vorwoche.")
        case .totals:
            return String(localized: "Alle Check-ins und aktiven Habits zusammen.")
        }
    }

    var symbol: String {
        switch self {
        case .yearPulse:    return "square.grid.3x3.middle.filled"
        case .streakFlame:  return "flame"
        case .todayRing:    return "circle.dashed"
        case .weekMomentum: return "chart.line.uptrend.xyaxis"
        case .totals:       return "number"
        }
    }
}

/// Welche Karten aktiv sind. Die Reihenfolge entspricht der Reihenfolge des
/// Einschaltens und damit der Reihenfolge über der Statistikseite.
struct StatsCardPrefs: Codable, Equatable {
    static let maxActive = StatsCard.allCases.count
    static let storageKey = "statsCards"
    /// Rhythmus plus Check-ins. Heute and the week card are always on the
    /// page, so the other metric tiles are opt-in.
    static let defaultActive: [StatsCard] = [.yearPulse, .totals]

    private(set) var active: [StatsCard]
    /// Old builds stored the default as just `yearPulse`. A missing marker on
    /// that payload, or on the current default, is not a user choice. Any
    /// other stored selection, including an explicit all-five choice, stays.
    private(set) var isCustomized: Bool

    /// Standard: Rhythmus and Check-ins, in page order.
    init(active: [StatsCard] = StatsCardPrefs.defaultActive, customized: Bool? = nil) {
        var seen = Set<StatsCard>()
        let normalized = Array(active.filter { seen.insert($0).inserted }.prefix(Self.maxActive))
        self.active = normalized
        self.isCustomized = customized ?? (normalized != Self.defaultActive)
    }

    var isFull: Bool { active.count >= Self.maxActive }

    func isActive(_ card: StatsCard) -> Bool { active.contains(card) }

    /// Mit vier möglichen Karten gibt es keine künstliche Obergrenze mehr.
    func canToggle(_ card: StatsCard) -> Bool { isActive(card) || !isFull }

    /// Ein-/Ausschalten. Die Obergrenze entspricht der Zahl der verfügbaren
    /// Karten und bleibt als Datenformat-Schutz bestehen.
    mutating func set(_ card: StatsCard, active on: Bool) {
        if on {
            guard !isActive(card), !isFull else { return }
            active.append(card)
        } else {
            active.removeAll { $0 == card }
        }
        isCustomized = true
    }

    // MARK: – Codable (tolerant)

    private enum CodingKeys: String, CodingKey { case active, customized }

    /// Unbekannte Kartennamen (aus einer neueren Version) fallen still weg,
    /// statt die ganze Einstellung zu verwerfen. Eine GESPEICHERTE leere
    /// Auswahl bleibt leer — „alle aus" ist eine Entscheidung, kein Fehler.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent([String].self, forKey: .active) ?? []
        var seen = Set<StatsCard>()
        active = Array(raw.compactMap(StatsCard.init(rawValue:))
            .filter { seen.insert($0).inserted }
            .prefix(Self.maxActive))
        // Builds before the explicit marker stored the default as only the
        // year card. That payload and the current default are not a choice.
        // Any other payload, including an intentional empty, partial, or
        // all-five selection, is therefore already a user choice.
        let storedDefault = active == [.yearPulse] || active == Self.defaultActive
        isCustomized = try c.decodeIfPresent(Bool.self, forKey: .customized)
            ?? !storedDefault
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(active.map(\.rawValue), forKey: .active)
        if isCustomized { try c.encode(true, forKey: .customized) }
    }

    // MARK: – Ablage

    /// Kein gespeicherter Wert -> Standard (Rhythmus und Check-ins). Kaputte
    /// Daten ebenso — lieber der Standard als ein Crash über einer Einstellung.
    static func load(from defaults: UserDefaults) -> StatsCardPrefs {
        guard let raw = defaults.data(forKey: storageKey),
              let prefs = try? JSONDecoder().decode(StatsCardPrefs.self, from: raw)
        else { return StatsCardPrefs() }
        return prefs.isCustomized ? prefs : StatsCardPrefs()
    }

    func save(to defaults: UserDefaults) {
        guard let raw = try? JSONEncoder().encode(self) else { return }
        defaults.set(raw, forKey: Self.storageKey)
    }
}

struct ViewPreferences: Codable, Equatable {
    static let storageKey = "viewPreferences"

    var updatedAt: TimeInterval
    var statsCards: StatsCardPrefs
    var compactMode: Bool
    /// Allows the main widget to expose an explicit reset/revert control.
    var widgetResetEnabled: Bool
    /// Automatically archive an item after its one-time or final scheduled
    /// occurrence is completed.
    var autoArchiveCompletedItems: Bool
    /// Globale Wischgesten. Die Auswahl ist absichtlich semantisch
    /// (Haupt-/Nebenaktion), damit sie bei jeder Habit-Art richtig bleibt.
    var swipeActions: SwipeActionsPreferences
    /// Shows one-tap actions when a scheduled notification is held down.
    var notificationActionsEnabled: Bool
    /// Up to three actions shown on a scheduled habit notification.
    var notificationActions: NotificationActionPreferences

    /// Compatibility view for callers and older tests that still address the
    /// first notification slot as a singular action.
    var notificationAction: SwipeActionChoice {
        get { notificationActions[0] }
        set { notificationActions[0] = newValue }
    }

    init(updatedAt: TimeInterval = 0,
         statsCards: StatsCardPrefs = StatsCardPrefs(),
         compactMode: Bool = false,
         widgetResetEnabled: Bool = true,
         autoArchiveCompletedItems: Bool = true,
         swipeActions: SwipeActionsPreferences = SwipeActionsPreferences(),
         notificationActionsEnabled: Bool = true,
         notificationActions: NotificationActionPreferences = NotificationActionPreferences(),
         notificationAction: SwipeActionChoice? = nil) {
        self.updatedAt = updatedAt
        self.statsCards = statsCards
        self.compactMode = compactMode
        self.widgetResetEnabled = widgetResetEnabled
        self.autoArchiveCompletedItems = autoArchiveCompletedItems
        self.swipeActions = swipeActions
        self.notificationActionsEnabled = notificationActionsEnabled
        self.notificationActions = notificationActions
        if let notificationAction {
            self.notificationActions[0] = notificationAction
        }
    }

    private enum CodingKeys: String, CodingKey {
        case updatedAt, statsCards, compactMode, widgetResetEnabled, autoArchiveCompletedItems, swipeActions, notificationActionsEnabled,
             notificationActions, notificationAction
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try c.decodeIfPresent(TimeInterval.self, forKey: .updatedAt) ?? 0
        let decodedCards = try c.decodeIfPresent(StatsCardPrefs.self, forKey: .statsCards)
            ?? StatsCardPrefs()
        statsCards = decodedCards.isCustomized ? decodedCards : StatsCardPrefs()
        compactMode = try c.decodeIfPresent(Bool.self, forKey: .compactMode) ?? false
        widgetResetEnabled = try c.decodeIfPresent(Bool.self, forKey: .widgetResetEnabled) ?? true
        autoArchiveCompletedItems = try c.decodeIfPresent(Bool.self,
                                                          forKey: .autoArchiveCompletedItems) ?? true
        swipeActions = try c.decodeIfPresent(SwipeActionsPreferences.self, forKey: .swipeActions)
            ?? SwipeActionsPreferences()
        notificationActionsEnabled = try c.decodeIfPresent(Bool.self,
                                                           forKey: .notificationActionsEnabled)
            ?? true
        if let saved = try c.decodeIfPresent(NotificationActionPreferences.self,
                                             forKey: .notificationActions) {
            notificationActions = saved
        } else if let legacy = (try c.decodeIfPresent(String.self,
                                                       forKey: .notificationAction))
            .flatMap(SwipeActionChoice.init(rawValue:)) {
            notificationActions = NotificationActionPreferences(
                slots: [legacy, .none, .none])
        } else {
            notificationActions = NotificationActionPreferences()
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(statsCards, forKey: .statsCards)
        try c.encode(compactMode, forKey: .compactMode)
        if !widgetResetEnabled {
            try c.encode(false, forKey: .widgetResetEnabled)
        }
        if !autoArchiveCompletedItems {
            try c.encode(false, forKey: .autoArchiveCompletedItems)
        }
        if swipeActions != SwipeActionsPreferences() {
            try c.encode(swipeActions, forKey: .swipeActions)
        }
        if !notificationActionsEnabled {
            try c.encode(false, forKey: .notificationActionsEnabled)
        }
        if notificationActions != NotificationActionPreferences() {
            try c.encode(notificationActions, forKey: .notificationActions)
        }
    }

    static func load(from defaults: UserDefaults) -> ViewPreferences {
        if let raw = defaults.data(forKey: storageKey),
           let prefs = try? JSONDecoder().decode(ViewPreferences.self, from: raw) {
            return prefs
        }
        // Build 20 and earlier wrote just this key. Give a real legacy value
        // a timestamp so it joins the first iCloud upload, but leave a fresh
        // install at zero so an existing remote preference wins.
        let cards = StatsCardPrefs.load(from: defaults)
        let migratedAt = defaults.data(forKey: StatsCardPrefs.storageKey) == nil
            ? 0
            : Date().timeIntervalSince1970
        return ViewPreferences(updatedAt: migratedAt, statsCards: cards)
    }

    func save(to defaults: UserDefaults) {
        guard let raw = try? JSONEncoder().encode(self) else { return }
        defaults.set(raw, forKey: Self.storageKey)
    }
}

/// Local cache for the syncable view preferences. Changes notify ContentView,
/// which folds the value into HabitData and schedules its normal iCloud push.
@Observable
final class ViewPreferencesStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var adoptingRemote = false

    var preferences: ViewPreferences {
        didSet {
            preferences.save(to: defaults)
            // Keep the Build 20 cache current for a clean local migration
            // path and for extensions that have not yet adopted the wrapper.
            preferences.statsCards.save(to: defaults)
            if !adoptingRemote { onChange?() }
        }
    }

    init(defaults: UserDefaults? = nil) {
        let resolved = defaults
            ?? UserDefaults(suiteName: SharedStorage.appGroup)
            ?? .standard
        self.defaults = resolved
        self.preferences = ViewPreferences.load(from: resolved)
    }

    var statsCards: StatsCardPrefs {
        preferences.statsCards
    }

    /// Read-only compatibility surface for existing consumers.
    var prefs: StatsCardPrefs {
        get { statsCards }
    }

    var compactMode: Bool {
        get { preferences.compactMode }
        set { update { $0.compactMode = newValue } }
    }

    var widgetResetEnabled: Bool {
        get { preferences.widgetResetEnabled }
        set { update { $0.widgetResetEnabled = newValue } }
    }

    func update(_ body: (inout ViewPreferences) -> Void) {
        var next = preferences
        body(&next)
        guard next.statsCards != preferences.statsCards
                || next.compactMode != preferences.compactMode
                || next.widgetResetEnabled != preferences.widgetResetEnabled
                || next.autoArchiveCompletedItems != preferences.autoArchiveCompletedItems
                || next.swipeActions != preferences.swipeActions
                || next.notificationActionsEnabled != preferences.notificationActionsEnabled
                || next.notificationActions != preferences.notificationActions
        else { return }
        next.updatedAt = Date().timeIntervalSince1970
        preferences = next
    }

    func setStatsCard(_ card: StatsCard, active: Bool) {
        update { $0.statsCards.set(card, active: active) }
    }

    func adoptRemote(_ remote: ViewPreferences) {
        guard remote.updatedAt > preferences.updatedAt else { return }
        adoptingRemote = true
        preferences = remote
        adoptingRemote = false
    }
}

typealias StatsCardStore = ViewPreferencesStore

// MARK: - Wischaktionen

/// Die Wahl in den Einstellungen — eine ZUSÄTZLICHE Aktion hinter der
/// festen Erst-Aktion jeder Seite (Erledigt/+1/Ja vorwärts, Zurücksetzen/
/// Nein rückwärts, siehe ContentView). `primary`/`secondary` sind Altlasten
/// früherer Dateien und lösen zu „keine Extra-Aktion" auf.
enum SwipeActionChoice: String, CaseIterable, Codable, Identifiable, Sendable {
    case primary, secondary, archive, backfill, session, edit, none

    var id: String { rawValue }

    /// Die Auswahl, die die Einstellungen anbieten — ohne die Altlasten.
    static var selectable: [SwipeActionChoice] { [.archive, .backfill, .session, .edit, .none] }

    /// Notifications use the same semantic choices as swipe actions. The
    /// permanent primary/secondary actions remain available alongside the
    /// optional extra actions.
    static var notificationSelectable: [SwipeActionChoice] {
        [.primary, .secondary] + selectable
    }

    var displayName: String {
        switch self {
        case .primary: return String(localized: "Standardaktion")
        case .secondary: return String(localized: "Zurücksetzen")
        case .archive: return String(localized: "Archivieren")
        case .backfill: return String(localized: "Nacharbeiten")
        case .session: return String(localized: "Session starten")
        case .edit: return String(localized: "Bearbeiten")
        case .none: return String(localized: "Keine Aktion")
        }
    }

    var notificationDisplayName: String {
        switch self {
        case .primary: return String(localized: "Hauptaktion")
        case .secondary: return String(localized: "Zurücksetzen / Nein")
        case .archive: return String(localized: "Archivieren")
        case .backfill: return String(localized: "Nacharbeiten")
        case .session: return String(localized: "Session starten")
        case .edit: return String(localized: "Bearbeiten")
        case .none: return String(localized: "Keine Aktion")
        }
    }
}

/// The three configurable notification slots. `none` is a real choice so the
/// user can keep one or two visible actions without a second source of truth.
struct NotificationActionPreferences: Codable, Equatable, Sendable {
    static let slotCount = 3

    var slots: [SwipeActionChoice]

    init(slots: [SwipeActionChoice] = [.primary, .secondary, .none]) {
        var normalized = Array(slots.prefix(Self.slotCount))
        while normalized.count < Self.slotCount {
            normalized.append(.none)
        }
        self.slots = normalized
    }

    subscript(index: Int) -> SwipeActionChoice {
        get {
            guard slots.indices.contains(index) else { return .none }
            return slots[index]
        }
        set {
            guard (0..<Self.slotCount).contains(index) else { return }
            var next = slots
            while next.count < Self.slotCount { next.append(.none) }
            next[index] = newValue
            slots = next
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode([String].self)) ?? []
        self.init(slots: raw.compactMap(SwipeActionChoice.init(rawValue:)))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(slots.map(\.rawValue))
    }

    /// Keep the menu honest: an action can be assigned to only one visible
    /// slot. `none` is intentionally reusable so every slot can be disabled.
    func availableChoices(for index: Int) -> [SwipeActionChoice] {
        guard (0..<Self.slotCount).contains(index) else { return [.none] }
        let current = self[index]
        let usedElsewhere = Set(slots.enumerated().compactMap { offset, choice in
            offset == index ? nil : choice
        })
        return SwipeActionChoice.notificationSelectable.filter { choice in
            choice == .none || choice == current || !usedElsewhere.contains(choice)
        }
    }

    mutating func assign(_ choice: SwipeActionChoice, to index: Int) {
        guard (0..<Self.slotCount).contains(index) else { return }
        if choice != .none {
            for otherIndex in slots.indices where otherIndex != index {
                if slots[otherIndex] == choice { slots[otherIndex] = .none }
            }
        }
        self[index] = choice
    }
}

struct SwipeActionsPreferences: Codable, Equatable, Sendable {
    var enabled: Bool
    var leading: SwipeActionChoice
    var trailing: SwipeActionChoice

    init(enabled: Bool = true,
         leading: SwipeActionChoice = .primary,
         trailing: SwipeActionChoice = .secondary) {
        self.enabled = enabled
        self.leading = leading
        self.trailing = trailing
    }

    private enum CodingKeys: String, CodingKey { case enabled, leading, trailing }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        leading = (try c.decodeIfPresent(String.self, forKey: .leading))
            .flatMap(SwipeActionChoice.init(rawValue:)) ?? .primary
        trailing = (try c.decodeIfPresent(String.self, forKey: .trailing))
            .flatMap(SwipeActionChoice.init(rawValue:)) ?? .secondary
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(leading.rawValue, forKey: .leading)
        try c.encode(trailing.rawValue, forKey: .trailing)
    }
}

/// Eine konkrete Aktion, die `ContentView` direkt in ein `swipeActions`-
/// Element uebersetzen kann. Archivieren bleibt immer ein gezielter Tap.
enum SwipeOperation: String, Equatable, Sendable {
    case done, reset, increment, yes, no, archive, backfill, session, edit
}

struct EffectiveSwipeAction: Equatable, Sendable {
    let operation: SwipeOperation

    /// Voll durchwischen löst nur die FESTE Erst-Aktion aus (die zuerst
    /// deklarierte). Für die Extra-Aktionen ist die Eigenschaft trotzdem
    /// ehrlich gepflegt: nichts Zerstörendes oder Navigierendes per
    /// Voll-Wisch.
    var allowsFullSwipe: Bool {
        switch operation {
        case .done, .reset, .increment, .yes, .no: return true
        case .archive, .backfill, .session, .edit: return false
        }
    }
}

struct EffectiveSwipeActions: Equatable, Sendable {
    var leading: EffectiveSwipeAction?
    var trailing: EffectiveSwipeAction?

    static let disabled = EffectiveSwipeActions(leading: nil, trailing: nil)
}

extension ViewPreferences {
    /// Settings contribute optional EXTRA actions. The type-aware primary
    /// and reverse actions are always supplied by ContentView.
    func effectiveSwipeActions(for habit: Habit) -> EffectiveSwipeActions {
        guard swipeActions.enabled else { return .disabled }
        let override = habit.swipeActions
        return EffectiveSwipeActions(
            leading: extraAction(override?.leading ?? swipeActions.leading),
            trailing: extraAction(override?.trailing ?? swipeActions.trailing))
    }

    private func extraAction(_ choice: SwipeActionChoice) -> EffectiveSwipeAction? {
        switch choice {
        case .archive: return EffectiveSwipeAction(operation: .archive)
        case .backfill: return EffectiveSwipeAction(operation: .backfill)
        case .session: return EffectiveSwipeAction(operation: .session)
        case .edit: return EffectiveSwipeAction(operation: .edit)
        case .none, .primary, .secondary: return nil
        }
    }
}
