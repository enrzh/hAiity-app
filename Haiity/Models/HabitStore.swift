import Foundation
import Observation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum MotivationDelivery: String, Codable, CaseIterable, Sendable {
    case notification
    case liveActivity

    var displayName: String {
        switch self {
        case .notification: return String(localized: "Mitteilung")
        case .liveActivity: return String(localized: "Live-Aktivität")
        }
    }
}

/// A temporary prompt-suppression state. The mode is retained after a timed
/// window expires so the UI can show the last choice without treating an
/// expired DND window as still active.
struct NotificationDNDState: Codable, Equatable, Sendable {
    enum Mode: String, Codable, CaseIterable, Sendable {
        case off
        case twoHours
        case eightHours
        case twentyFourHours
        case custom
        case untilDisabled
    }

    var mode: Mode
    var until: Date?

    static let off = NotificationDNDState(mode: .off, until: nil)

    static func active(_ mode: Mode, now: Date = .now, customUntil: Date? = nil) -> Self {
        switch mode {
        case .off:
            return .off
        case .twoHours:
            return Self(mode: mode, until: now.addingTimeInterval(2 * 60 * 60))
        case .eightHours:
            return Self(mode: mode, until: now.addingTimeInterval(8 * 60 * 60))
        case .twentyFourHours:
            return Self(mode: mode, until: now.addingTimeInterval(24 * 60 * 60))
        case .custom:
            let fallback = now.addingTimeInterval(2 * 60 * 60)
            return Self(mode: mode, until: max(customUntil ?? fallback, now.addingTimeInterval(60)))
        case .untilDisabled:
            return Self(mode: mode, until: nil)
        }
    }

    func isActive(at date: Date = .now) -> Bool {
        switch mode {
        case .off:
            return false
        case .untilDisabled:
            return true
        case .twoHours, .eightHours, .twentyFourHours, .custom:
            return until.map { $0 > date } ?? false
        }
    }
}

/// User choices that affect system integrations but not the integration
/// objects themselves. Calendar/reminder permissions and native identifiers
/// stay on each device; these switches are the user's synced intent.
struct CloudPreferences: Codable, Equatable {
    var calendarSyncHabits: Bool
    var calendarSyncReminders: Bool
    var nativeReminderSync: Bool
    var notificationDND: NotificationDNDState
    var shakeToReportEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case calendarSyncHabits
        case calendarSyncReminders
        case nativeReminderSync
        case notificationPromptsSuppressed
        case notificationDND
        case shakeToReportEnabled
    }

    /// Compatibility view for older callers and older iCloud payloads. New
    /// code should persist `notificationDND` so timed windows survive sync.
    var notificationPromptsSuppressed: Bool { notificationDND.isActive() }

    init(calendarSyncHabits: Bool = false,
         calendarSyncReminders: Bool = false,
         nativeReminderSync: Bool = false,
         notificationPromptsSuppressed: Bool = false,
         shakeToReportEnabled: Bool = true,
         notificationDND: NotificationDNDState? = nil) {
        self.calendarSyncHabits = calendarSyncHabits
        self.calendarSyncReminders = calendarSyncReminders
        self.nativeReminderSync = nativeReminderSync
        self.notificationDND = notificationDND
            ?? (notificationPromptsSuppressed ? .active(.untilDisabled) : .off)
        self.shakeToReportEnabled = shakeToReportEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        calendarSyncHabits = try container.decodeIfPresent(Bool.self,
                                                           forKey: .calendarSyncHabits) ?? false
        calendarSyncReminders = try container.decodeIfPresent(Bool.self,
                                                              forKey: .calendarSyncReminders) ?? false
        nativeReminderSync = try container.decodeIfPresent(Bool.self,
                                                             forKey: .nativeReminderSync) ?? false
        if let savedDND = try container.decodeIfPresent(NotificationDNDState.self,
                                                        forKey: .notificationDND) {
            notificationDND = savedDND
        } else {
            let legacy = try container.decodeIfPresent(Bool.self,
                                                       forKey: .notificationPromptsSuppressed) ?? false
            notificationDND = legacy ? .active(.untilDisabled) : .off
        }
        shakeToReportEnabled = try container.decodeIfPresent(Bool.self,
                                                             forKey: .shakeToReportEnabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(calendarSyncHabits, forKey: .calendarSyncHabits)
        try container.encode(calendarSyncReminders, forKey: .calendarSyncReminders)
        try container.encode(nativeReminderSync, forKey: .nativeReminderSync)
        try container.encode(notificationDND, forKey: .notificationDND)
        // Keep the old boolean for one migration cycle. Older builds ignore
        // the new state but still respect an active permanent/timed window.
        try container.encode(notificationPromptsSuppressed,
                             forKey: .notificationPromptsSuppressed)
        try container.encode(shakeToReportEnabled, forKey: .shakeToReportEnabled)
    }
}

/// Persistenz-Container: JSON im App-Group-Container, damit das Widget
/// dieselbe Datei liest. Fallback auf Application Support (Unit-Tests,
/// fehlendes Entitlement) — niemals stiller Datenverlust.
struct HabitData: Codable {
    /// Geschrieben wird immer die aktuelle Version; gelesen werden 1 und 2.
    static let currentVersion = 2

    var version: Int
    var updatedAt: TimeInterval
    /// Freshness of the appearance slice, independent from habit/check-in
    /// writes. Nil means the payload predates this timestamp and keeps the
    /// legacy root-timestamp merge rule only when both sides are legacy.
    var appearanceUpdatedAt: TimeInterval?
    /// Global default for habits without a per-item override. Nil means the
    /// current device timezone and keeps older payloads unchanged.
    var defaultTimeZoneIdentifier: String?
    /// Tageszusammenfassung; nil = aus. Hieß bis v4 „Abend-Zusammenfassung"
    /// und behält deshalb ihren Schlüssel — dieselbe Einstellung, nur mit
    /// mehr zu sagen (siehe `SummaryText`).
    var summaryMinutes: Int?
    /// Wochenzusammenfassung; nil = aus.
    var weeklySummaryMinutes: Int?
    /// Tägliche Motivationsnachricht; nil = aus (die Voreinstellung). Ein
    /// eigener Schalter neben `summaryMinutes`: die Zusammenfassung trägt
    /// ZAHLEN, die Motivation trägt einen Satz — wer das eine will, will
    /// nicht zwangsläufig das andere, und beide dürfen zu verschiedenen
    /// Uhrzeiten kommen.
    var motivationMinutes: Int?
    /// Auslieferungsart der täglichen Motivation. Alte Dateien fallen auf
    /// lokale Mitteilungen zurück, damit ihr bisheriges Verhalten bleibt.
    var motivationDelivery: MotivationDelivery
    /// Where the daily motivational line comes from.
    var motivationSource: Motivation.Source
    /// Wochentag der Wochenzusammenfassung (1 = So … 7 = Sa).
    var weeklySummaryWeekday: Int
    var habits: [Habit]
    var sessionHistory: [HabitSessionRecord]
    /// Hell/Dunkel/System. Liegt HIER und nicht in UserDefaults, damit die
    /// Einstellung denselben Weg nimmt wie alles andere (Export, Import,
    /// iCloud-Spiegel) — ein neues Gerät sieht sofort dieselbe App.
    var appearance: AppearanceSetting
    /// Hintergrundbild und Oberflächenmaterial. Das Bild wird vor dem Setzen
    /// auf eine kleine JPEG-Nutzlast begrenzt, damit der iCloud-Asset nicht
    /// unnötig groß wird.
    var appearancePreferences: AppearancePreferences
    /// Globale Rasterfarbe.
    var palette: PaletteRef
    /// Eigene Paletten des Nutzers. Gespeichert wird je Palette NUR die
    /// Basisfarbe — die Rampe rechnet der Generator beim Lesen (siehe
    /// `CustomPalette`).
    var customPalettes: [CustomPalette]
    /// Soll das App-Icon der Palette folgen? Standard an; der Icon-Wechsel
    /// zeigt einen System-Dialog, deshalb ist er abschaltbar.
    var matchAppIcon: Bool
    /// Der zuletzt gewählte manuelle Alternate-Icon-Katalogname. iOS hält die
    /// tatsächliche Icon-Auswahl pro Gerät; dieser Wunsch reist deshalb mit
    /// dem iCloud-Payload und wird auf dem neuen Gerät erneut angewendet.
    var manualAppIconName: String?
    /// Soll der GitHub-Nutzername ueber dem Beitragsraster erscheinen? `nil`
    /// bedeutet eine Datei aus einer Version, die diese Einstellung noch
    /// lokal im App-Group-Defaults hielt.
    var githubShowsUsername: Bool?
    /// Ansichts-Einstellungen (Statistik-Karten und kompakte Darstellung).
    /// Sie reisen als Teil desselben privaten iCloud-Payloads mit.
    var viewPreferences: ViewPreferences
    /// Synced user intent for system integrations. Permissions, native IDs,
    /// and per-device event/reminder mappings deliberately remain local.
    var cloudPreferences: CloudPreferences?

    /// Die neuen Felder sind bewusst KEIN Versionssprung: sie sind rein
    /// additiv und tolerant dekodiert, ein v2-Build von gestern liest die
    /// Datei unverändert weiter (ein Sprung auf 3 würde ihn aussperren).
    /// Standard-Wochentag der Wochenzusammenfassung: Sonntag — der Tag, an
    /// dem eine Woche zu Ende ist, egal wo sie anfängt.
    static let defaultSummaryWeekday = 1

    init(version: Int,
         updatedAt: TimeInterval,
         summaryMinutes: Int?,
         habits: [Habit],
         appearanceUpdatedAt: TimeInterval? = nil,
         defaultTimeZoneIdentifier: String? = nil,
         appearance: AppearanceSetting = .default,
         appearancePreferences: AppearancePreferences = .default,
         palette: PaletteRef = .default,
         customPalettes: [CustomPalette] = [],
         matchAppIcon: Bool = true,
         manualAppIconName: String? = nil,
         githubShowsUsername: Bool? = nil,
         weeklySummaryMinutes: Int? = nil,
         weeklySummaryWeekday: Int = HabitData.defaultSummaryWeekday,
         viewPreferences: ViewPreferences = ViewPreferences(),
         cloudPreferences: CloudPreferences? = nil,
         sessionHistory: [HabitSessionRecord] = [],
         motivationMinutes: Int? = nil,
         motivationDelivery: MotivationDelivery = .notification,
         motivationSource: Motivation.Source = .builtIn) {
        self.version = version
        self.updatedAt = updatedAt
        self.appearanceUpdatedAt = appearanceUpdatedAt
        self.defaultTimeZoneIdentifier = HabitTimeZone.sanitizedIdentifier(defaultTimeZoneIdentifier)
        self.summaryMinutes = summaryMinutes
        self.weeklySummaryMinutes = weeklySummaryMinutes
        self.motivationMinutes = motivationMinutes
        self.motivationDelivery = motivationDelivery
        self.motivationSource = motivationSource
        self.weeklySummaryWeekday = (1...7).contains(weeklySummaryWeekday)
            ? weeklySummaryWeekday : Self.defaultSummaryWeekday
        self.habits = habits
        self.sessionHistory = sessionHistory
        self.appearance = appearance
        self.appearancePreferences = appearancePreferences.normalizedForStorage()
        self.palette = palette
        self.customPalettes = customPalettes
        self.matchAppIcon = matchAppIcon
        self.manualAppIconName = manualAppIconName
        self.githubShowsUsername = githubShowsUsername
        self.viewPreferences = viewPreferences
        self.cloudPreferences = cloudPreferences
    }

    static let empty = HabitData(version: currentVersion, updatedAt: 0, summaryMinutes: nil, habits: [])
}

extension HabitData {
    /// `leadingSwipe`/`trailingSwipe` stehen hier ABSICHTLICH nicht mehr:
    /// die Wischgesten sind weg (siehe Interaction.swift). Eine Datei aus
    /// einem älteren Build trägt die beiden Schlüssel weiterhin — für
    /// Codable ist ein unbekannter Schlüssel kein Fehler, er wird beim Lesen
    /// schlicht ÜBERGANGEN. Die Datei bleibt also vollständig lesbar; nur
    /// die Einstellung, die es nicht mehr gibt, fällt beim nächsten
    /// Speichern heraus.
    private enum CodingKeys: String, CodingKey {
        case version, updatedAt, appearanceUpdatedAt, defaultTimeZoneIdentifier, summaryMinutes, habits, appearance, appearancePreferences,
             palette, matchAppIcon
        case manualAppIconName
        case githubShowsUsername
        case customPalettes
        // Die Wochenzusammenfassung ist rein ADDITIV: ein Build ohne sie
        // überliest die beiden Schlüssel, also braucht es dafür keinen
        // Versionssprung (der ihn aussperren würde).
        case weeklySummaryMinutes, weeklySummaryWeekday, viewPreferences, sessionHistory
        case cloudPreferences
        // Auch die Motivationsnachricht ist rein ADDITIV — ein Build ohne
        // sie überliest den Schlüssel, kein Versionssprung nötig.
        case motivationMinutes, motivationDelivery, motivationSource
        // Nur zum Einlesen alter Wurzel-Einstellungen; encode schreibt sie
        // nie wieder, weil die neue Konfiguration in viewPreferences liegt.
        case leadingSwipe, trailingSwipe
    }

    /// Akzeptiert Version 1 und 2; alles andere ist keine hAiity-Datei und
    /// wird abgelehnt, statt sie beim nächsten Speichern zu zerschreiben.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let v = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard (1...Self.currentVersion).contains(v) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [CodingKeys.version],
                debugDescription: "Unbekannte Datenversion \(v) — lesbar sind 1…\(Self.currentVersion)."))
        }
        version = v
        updatedAt = try c.decodeIfPresent(TimeInterval.self, forKey: .updatedAt) ?? 0
        appearanceUpdatedAt = try c.decodeIfPresent(TimeInterval.self, forKey: .appearanceUpdatedAt)
        defaultTimeZoneIdentifier = HabitTimeZone.sanitizedIdentifier(
            try c.decodeIfPresent(String.self, forKey: .defaultTimeZoneIdentifier))
        summaryMinutes = try c.decodeIfPresent(Int.self, forKey: .summaryMinutes)
        weeklySummaryMinutes = try c.decodeIfPresent(Int.self, forKey: .weeklySummaryMinutes)
        // Fehlt der Schlüssel (jede Datei vor dieser Fassung): nil = aus.
        motivationMinutes = try c.decodeIfPresent(Int.self, forKey: .motivationMinutes)
        motivationDelivery = try c.decodeIfPresent(MotivationDelivery.self,
                                                    forKey: .motivationDelivery) ?? .notification
        // The retired open-source feed stored a Bool. Its quotes are gone, so a
        // stored `true` is not a choice between the two surviving sources — it
        // becomes the built-in pool, and picking the model stays an explicit
        // opt-in. An unknown string also falls back rather than failing decode.
        // `decodeIfPresent` THROWS on an unknown raw value instead of returning
        // nil, so a source added by a newer build would take the whole file
        // down with it. `try? decode` treats missing and unrecognised alike.
        motivationSource = (try? c.decode(Motivation.Source.self,
                                          forKey: .motivationSource)) ?? .builtIn
        let weekday = try c.decodeIfPresent(Int.self, forKey: .weeklySummaryWeekday)
            ?? Self.defaultSummaryWeekday
        weeklySummaryWeekday = (1...7).contains(weekday) ? weekday : Self.defaultSummaryWeekday
        habits = try c.decodeIfPresent([Habit].self, forKey: .habits) ?? []
        sessionHistory = (try? c.decodeIfPresent([HabitSessionRecord].self, forKey: .sessionHistory)) ?? []
        // Fehlt / unbekannt -> Standard. Eine Datei aus einer neueren
        // Version mit "palette":"neon" verliert nur die Farbe, nicht die
        // Check-ins.
        appearance = (try c.decodeIfPresent(String.self, forKey: .appearance))
            .flatMap(AppearanceSetting.init(rawValue:)) ?? .default
        appearancePreferences = ((try c.decodeIfPresent(AppearancePreferences.self,
                                                         forKey: .appearancePreferences))
            ?? .default).normalizedForStorage()
        palette = (try c.decodeIfPresent(String.self, forKey: .palette))
            .flatMap(PaletteRef.init(rawValue:)) ?? .default
        // Fehlt der Schlüssel (jede Datei vor den eigenen Farben) oder ist ein
        // Eintrag kaputt: leere Liste statt Fehler. Ein Verweis auf eine
        // Palette, die dann fehlt, fällt beim Auflösen sauber zurück.
        customPalettes = ((try? c.decodeIfPresent([CustomPalette].self, forKey: .customPalettes)) ?? nil) ?? []
        matchAppIcon = try c.decodeIfPresent(Bool.self, forKey: .matchAppIcon) ?? true
        manualAppIconName = try c.decodeIfPresent(String.self, forKey: .manualAppIconName)
        githubShowsUsername = try c.decodeIfPresent(Bool.self, forKey: .githubShowsUsername)
        if let savedPreferences = try c.decodeIfPresent(ViewPreferences.self, forKey: .viewPreferences) {
            viewPreferences = savedPreferences
        } else {
            viewPreferences = ViewPreferences(
                swipeActions: SwipeActionsPreferences(
                    leading: Self.migratedSwipeChoice(
                        try c.decodeIfPresent(String.self, forKey: .leadingSwipe), fallback: .primary),
                trailing: Self.migratedSwipeChoice(
                        try c.decodeIfPresent(String.self, forKey: .trailingSwipe), fallback: .secondary)))
        }
        cloudPreferences = try c.decodeIfPresent(CloudPreferences.self, forKey: .cloudPreferences)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(appearanceUpdatedAt, forKey: .appearanceUpdatedAt)
        try c.encodeIfPresent(defaultTimeZoneIdentifier, forKey: .defaultTimeZoneIdentifier)
        try c.encodeIfPresent(summaryMinutes, forKey: .summaryMinutes)
        try c.encodeIfPresent(weeklySummaryMinutes, forKey: .weeklySummaryMinutes)
        try c.encodeIfPresent(motivationMinutes, forKey: .motivationMinutes)
        if motivationMinutes != nil || motivationDelivery != .notification {
            try c.encode(motivationDelivery, forKey: .motivationDelivery)
        }
        if motivationSource != .builtIn {
            try c.encode(motivationSource, forKey: .motivationSource)
        }
        // Der Wochentag steht nur da, wenn die Wochenzusammenfassung
        // überhaupt läuft — sonst wäre er eine Einstellung ohne Wirkung in
        // jeder Datei.
        if weeklySummaryMinutes != nil, weeklySummaryWeekday != Self.defaultSummaryWeekday {
            try c.encode(weeklySummaryWeekday, forKey: .weeklySummaryWeekday)
        }
        try c.encode(habits, forKey: .habits)
        if !sessionHistory.isEmpty { try c.encode(sessionHistory, forKey: .sessionHistory) }
        // Standards bleiben implizit — eine unveränderte Installation
        // schreibt exakt dieselbe Datei wie vor dem Theming.
        if appearance != .default { try c.encode(appearance.rawValue, forKey: .appearance) }
        if appearancePreferences != .default {
            try c.encode(appearancePreferences, forKey: .appearancePreferences)
        }
        if palette != .default { try c.encode(palette.rawValue, forKey: .palette) }
        if !customPalettes.isEmpty { try c.encode(customPalettes, forKey: .customPalettes) }
        if !matchAppIcon { try c.encode(false, forKey: .matchAppIcon) }
        try c.encodeIfPresent(manualAppIconName, forKey: .manualAppIconName)
        if let githubShowsUsername { try c.encode(githubShowsUsername, forKey: .githubShowsUsername) }
        if viewPreferences != ViewPreferences() { try c.encode(viewPreferences, forKey: .viewPreferences) }
        try c.encodeIfPresent(cloudPreferences, forKey: .cloudPreferences)
    }

    /// Die frueheren Wurzel-Schluessel stehen fuer dieselben Nutzerabsichten.
    /// "edit" hat keine sichere Entsprechung als Sofortaktion und faellt wie
    /// unbekannte Werte auf die jeweilige neue Standardseite zurueck.
    private static func migratedSwipeChoice(_ raw: String?, fallback: SwipeActionChoice) -> SwipeActionChoice {
        switch raw {
        case "done": return .primary
        case "revert": return .secondary
        case "archive": return .archive
        case "none": return fallback
        default: return fallback
        }
    }
}

/// Der Stand, den eine Zusammenfassung zusammenfasst: erfüllte von fälligen
/// Terminen und die Namen dessen, was noch aussteht. Bewusst EIN Typ für Tag
/// und Woche — es ist dieselbe Frage über ein anderes Fenster.
struct SummaryStatus: Equatable {
    var done: Int
    var total: Int
    /// Namen der Habits, die im Fenster hinterherhinken (Tag: heute offen;
    /// Woche: weniger erfüllt als fällig).
    var missing: [String]

    var isEmpty: Bool { total == 0 }
}

enum SharedStorage {
    static let appGroup = "group.com.aiity.haiity"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func dataURL(fileManager: FileManager = .default) -> URL {
        if let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return container.appendingPathComponent("data.json")
        }
        let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("haiity", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("data.json")
    }
}

/// Shared app/widget visibility policy. The app's `ProGate` adds the live
/// StoreKit state; extension processes use the App Group snapshot and the
/// same verified owner identity because they cannot observe the app process.
enum HabitVisibility {
    static let freeHabitLimit = 3
    static let proUnlockedKey = "proUnlocked"
    static let proEntitlementExpirationKey = "proEntitlementExpiration"
    static let ownerAppleUserID = "000366.5e70aaf77f174436b9c1ad437015d35a.1026"
    static let ownerAppleEmail = "xianjie.zhan@icloud.com"

    static func visibleActiveHabits(_ habits: [Habit], unlocked: Bool) -> [Habit] {
        let active = habits.filter { $0.archivedAt == nil }
        guard !unlocked else { return active }

        var trackedCount = 0
        return active.filter { habit in
            guard !habit.isTrackedHabit else {
                guard trackedCount < freeHabitLimit else { return false }
                trackedCount += 1
                return true
            }
            return true
        }
    }

    static var sharedEntitlementIsUnlocked: Bool {
        sharedEntitlementIsUnlocked(at: .now)
    }

    static func sharedEntitlementIsUnlocked(
        at now: Date,
        defaults: UserDefaults? = nil
    ) -> Bool {
        let defaults = defaults ?? (UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard)
        if isOwnerDevice(storedAppleUserID: defaults.string(forKey: "personalAppleUserID"),
                         storedAppleEmail: defaults.string(forKey: "personalAppleEmail")) {
            return true
        }
        guard defaults.bool(forKey: proUnlockedKey) else { return false }
        guard let rawExpiration = defaults.object(forKey: proEntitlementExpirationKey)
                as? NSNumber else {
            return true
        }
        return rawExpiration.doubleValue > now.timeIntervalSince1970
    }

    static func isOwnerDevice(storedAppleUserID: String?, storedAppleEmail: String?) -> Bool {
        let userID = storedAppleUserID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if userID == ownerAppleUserID { return true }
        let email = storedAppleEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return email == ownerAppleEmail.lowercased()
    }
}

enum HabitStoreChange: Equatable, Sendable {
    case general
    case appearance
}

/// Which calendar series a local store write should touch. Editor saves pass
/// the changed IDs; foreground, timezone, and iCloud merges use the full set.
enum CalendarSyncScope: Equatable, Sendable {
    case items(Set<UUID>)
    case allMapped

    func merging(_ other: CalendarSyncScope) -> CalendarSyncScope {
        switch (self, other) {
        case (.allMapped, _), (_, .allMapped):
            return .allMapped
        case let (.items(left), .items(right)):
            return .items(left.union(right))
        }
    }

    var keys: Set<String>? {
        switch self {
        case .allMapped: return nil
        case .items(let ids): return Set(ids.map(\.uuidString))
        }
    }
}

@Observable
final class HabitStore {
    private(set) var data: HabitData
    let url: URL
    var onChange: (() -> Void)?
    var onChangeKind: ((HabitStoreChange) -> Void)?
    var onCalendarSyncNeeded: ((CalendarSyncScope) -> Void)?
    /// mtime der Datei beim letzten eigenen Lesen/Schreiben — erkennt
    /// externe Schreiber (Widget-Intent im Extension-Prozess).
    @ObservationIgnored private var loadedMtime: Date?

    init(url: URL = SharedStorage.dataURL(), loadFromDisk: Bool = true) {
        self.url = url
        self.data = loadFromDisk ? (Self.read(url) ?? .empty) : .empty
        self.loadedMtime = loadFromDisk ? Self.mtime(url) : nil
    }

    /// ALLE Habits, auch archivierte (Export, Sync, Archiv-Ansicht).
    var habits: [Habit] { data.habits }
    var sessionHistory: [HabitSessionRecord] { data.sessionHistory }

    /// Nicht archivierte Habits — Hauptliste, Summary, Widget.
    var activeHabits: [Habit] { data.habits.filter { $0.archivedAt == nil } }
    var activeTrackedHabits: [Habit] { activeHabits.filter(\.isTrackedHabit) }
    var activeReminders: [Habit] { activeHabits.filter(\.isReminder) }

    var summaryMinutes: Int? {
        get { data.summaryMinutes }
        set { data.summaryMinutes = newValue; persist() }
    }

    var weeklySummaryMinutes: Int? {
        get { data.weeklySummaryMinutes }
        set { data.weeklySummaryMinutes = newValue; persist() }
    }

    /// Uhrzeit der Motivationsnachricht; nil = aus. `persist()` schreibt und
    /// meldet über `onChange` — daran hängt die Neuplanung, also stellt schon
    /// das Setzen der Uhrzeit die Wecker um (siehe `Reminders.reschedule`).
    var motivationMinutes: Int? {
        get { data.motivationMinutes }
        set { data.motivationMinutes = newValue; persist() }
    }

    var motivationDelivery: MotivationDelivery {
        get { data.motivationDelivery }
        set { data.motivationDelivery = newValue; persist() }
    }

    var motivationSource: Motivation.Source {
        get { data.motivationSource }
        set {
            guard data.motivationSource != newValue else { return }
            data.motivationSource = newValue
            persist()
        }
    }

    var defaultTimeZoneIdentifier: String? {
        get { data.defaultTimeZoneIdentifier }
        set {
            let normalized = HabitTimeZone.sanitizedIdentifier(newValue)
            guard normalized != data.defaultTimeZoneIdentifier else { return }
            data.defaultTimeZoneIdentifier = normalized
            persist(calendarSync: .allMapped)
        }
    }

    var weeklySummaryWeekday: Int {
        get { data.weeklySummaryWeekday }
        set {
            data.weeklySummaryWeekday = (1...7).contains(newValue)
                ? newValue : HabitData.defaultSummaryWeekday
            persist()
        }
    }

    var appearance: AppearanceSetting {
        get { data.appearance }
        set { data.appearance = newValue; persist(changeKind: .appearance) }
    }

    var appearancePreferences: AppearancePreferences {
        get { data.appearancePreferences }
        set {
            let old = data.appearancePreferences
            var next = newValue.normalizedForStorage()
            // A mode switch is reversible and must not become a deletion
            // tombstone. Only an actual payload mutation changes the marker.
            if old.backgroundImageData != next.backgroundImageData {
                next.backgroundResetAt = Date().timeIntervalSince1970
            }
            data.appearancePreferences = next
            persist(changeKind: .appearance)
        }
    }

    func resetBackground() {
        var preferences = data.appearancePreferences
        preferences.resetBackground()
        guard preferences != data.appearancePreferences else { return }
        data.appearancePreferences = preferences
        persist(changeKind: .appearance)
    }

    func removeBackgroundImage() {
        var preferences = data.appearancePreferences
        preferences.removeBackgroundImage()
        data.appearancePreferences = preferences
        persist(changeKind: .appearance)
    }

    /// Die GLOBALE Einstellung (was gespeichert wird).
    var palette: PaletteRef {
        get { data.palette }
        set { data.palette = newValue; persist(changeKind: .appearance) }
    }

    var customPalettes: [CustomPalette] { data.customPalettes }

    /// Globale Farbe + eigene Paletten als EIN Paket — das, was die Umgebung
    /// und der Widget-Eintrag tragen.
    var palettes: PaletteBook {
        PaletteBook(global: data.palette, customs: data.customPalettes)
    }

    /// Die aufgelöste globale Farbtafel — für Akzente, Tint und Chrom.
    var paletteStyle: PaletteStyle { palettes.style }

    var matchAppIcon: Bool {
        get { data.matchAppIcon }
        set { data.matchAppIcon = newValue; persist(changeKind: .appearance) }
    }

    var manualAppIconName: String? {
        get { data.manualAppIconName }
        set { data.manualAppIconName = newValue; persist(changeKind: .appearance) }
    }

    var cloudPreferences: CloudPreferences? { data.cloudPreferences }

    /// The synced preference is authoritative once it exists. Older installs
    /// keep their local value until `materializeGitHubShowsUsername()` runs
    /// after the first iCloud pull.
    var githubShowsUsername: Bool {
        get { data.githubShowsUsername ?? GitHubPreferences.showsUsername }
        set {
            data.githubShowsUsername = newValue
            GitHubPreferences.setShowsUsername(newValue, in: GitHubPreferences.defaults)
            persist()
        }
    }

    /// Promote the legacy App Group preference only after any remote payload
    /// has had a chance to provide the newer synced value.
    func materializeGitHubShowsUsername() {
        guard data.githubShowsUsername == nil else { return }
        data.githubShowsUsername = GitHubPreferences.showsUsername
        persist(notify: false)
    }

    func setViewPreferences(_ preferences: ViewPreferences) {
        guard preferences != data.viewPreferences else { return }
        data.viewPreferences = preferences
        persist(notify: false)
    }

    /// The integration objects themselves are device-local, but the user's
    /// choice to use them is part of the iCloud payload.
    func updateCloudPreferences(fallback: CloudPreferences,
                                _ body: (inout CloudPreferences) -> Void) {
        var next = data.cloudPreferences ?? fallback
        body(&next)
        guard next != data.cloudPreferences else { return }
        data.cloudPreferences = next
        persist()
    }

    /// Older payloads have no cloud preference object. Materialize the local
    /// defaults only after an iCloud pull has had a chance to win.
    func materializeCloudPreferences(fallback: CloudPreferences) {
        guard data.cloudPreferences == nil else { return }
        data.cloudPreferences = fallback
        persist(notify: false)
    }

    static func read(_ url: URL) -> HabitData? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HabitData.self, from: raw)
    }

    /// Loads the initial payload away from the first SwiftUI render. The
    /// store is intentionally empty until this finishes so the splash can
    /// cover a mounted content tree without blocking the main thread.
    @MainActor
    func loadFromDisk() async {
        guard loadedMtime == nil else { return }
        let url = self.url
        let snapshot = await Task.detached(priority: .userInitiated) {
            (Self.read(url), Self.mtime(url))
        }.value
        guard !Task.isCancelled, loadedMtime == nil else { return }
        loadedMtime = snapshot.1
        guard let fresh = snapshot.0 else { return }
        data = fresh
    }

    private static func mtime(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Liest die Datei neu ein, wenn sie sich EXTERN geändert hat (der
    /// Widget-Intent schreibt aus dem Extension-Prozess). Merge-frei und
    /// sicher: `persist()` schreibt synchron, der In-Memory-Stand liegt
    /// also immer schon auf der Platte. Ein externer Widget-Schreiber kann
    /// aber mit einem älteren Snapshot arbeiten; deshalb wird der frische
    /// Payload über dieselbe Union/LWW-Logik wie iCloud eingespielt, statt
    /// den gesamten lokalen Stand blind zu ersetzen. So kann ein Widget-
    /// Check-in ankommen, ohne eine danach gewählte Darstellung zurückzuholen.
    /// Unveränderte mtime -> No-op (kein Decode, kein onChange).
    func reloadFromDisk() {
        let m = Self.mtime(url)
        guard m != loadedMtime, let fresh = Self.read(url) else { return }
        loadedMtime = m
        merge(remote: fresh)
    }

    func persist(notify: Bool = true,
                 changeKind: HabitStoreChange = .general,
                 touchTimestamp: Bool = true,
                 calendarSync: CalendarSyncScope? = nil) {
        data.appearancePreferences = data.appearancePreferences.normalizedForStorage()
        data.version = HabitData.currentVersion
        if touchTimestamp {
            let now = Date().timeIntervalSince1970
            if changeKind == .appearance {
                data.appearanceUpdatedAt = now
            } else {
                data.updatedAt = now
            }
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let raw = try? enc.encode(data) {
            try? raw.write(to: url, options: .atomic)
        }
        loadedMtime = Self.mtime(url)
        #if canImport(WidgetKit)
        reloadWidgetsAfterPersist()
        #endif
        if notify {
            onChange?()
            onChangeKind?(changeKind)
            if let calendarSync {
                onCalendarSyncNeeded?(calendarSync)
            }
        }
    }

    #if canImport(WidgetKit)
    /// WidgetKit timeline reloads can stall the current run loop for hundreds
    /// of milliseconds. The local write stays synchronous; the app coalesces
    /// the reload after the current transaction so Save/Done can return to
    /// Habits without freezing the list. Widget-extension check-ins reload
    /// immediately because that process is the surface being updated.
    private static var widgetReloadTask: Task<Void, Never>?

    private func reloadWidgetsAfterPersist() {
        if Bundle.main.bundlePath.hasSuffix(".appex") {
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        Self.widgetReloadTask?.cancel()
        Self.widgetReloadTask = Task(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    #endif

    // MARK: – Mutationen

    func add(_ habit: Habit, after sourceID: UUID? = nil) {
        if let sourceID,
           let index = data.habits.firstIndex(where: { $0.id == sourceID }) {
            data.habits.insert(habit, at: index + 1)
        } else {
            data.habits.append(habit)
        }
        persist(calendarSync: .items([habit.id]))
    }

    func update(_ habit: Habit) {
        guard let i = data.habits.firstIndex(where: { $0.id == habit.id }) else { return }
        data.habits[i] = habit
        persist(calendarSync: .items([habit.id]))
    }

    func remove(_ id: UUID) {
        data.habits.removeAll { $0.id == id }
        data.sessionHistory.removeAll { $0.habitID == id }
        persist(calendarSync: .items([id]))
    }

    /// Checkbox-Habits: 0 <-> 1.
    func toggle(_ id: UUID, day: String = DayKey.today()) {
        guard let i = data.habits.firstIndex(where: { $0.id == id }) else { return }
        if data.habits[i].log[day] != nil { data.habits[i].log[day] = nil }
        else {
            data.habits[i].log[day] = 1
            data.habits[i].missedDays.removeAll { $0 == day }
            autoArchiveIfNeeded(at: i, day: day)
        }
        persist()
    }

    /// Mengen-Habits: +1 auf den Tageszähler (1, 2, 3 …) — kein Wrap.
    /// Löschen läuft explizit über `clear` (Langdruck/Menü in der UI).
    ///
    /// Gedeckelt bei `Habit.Answer.maxCount`. Das ist keine Schikane gegen
    /// den fleißigsten Nutzer der Welt, sondern die Zusage, auf der die
    /// Ja/Nein-Codierung steht: kein Zähler darf je ins reservierte Band
    /// laufen, sonst läse sich ein Habit eines Tages selbst als Ja/Nein.
    func increment(_ id: UUID, day: String = DayKey.today()) {
        guard let i = data.habits.firstIndex(where: { $0.id == id }) else { return }
        let next = (data.habits[i].log[day] ?? 0) + 1
        data.habits[i].log[day] = min(next, Habit.Answer.maxCount)
        data.habits[i].missedDays.removeAll { $0 == day }
        autoArchiveIfNeeded(at: i, day: day)
        persist()
    }

    /// Ja/Nein-Habits: den Tag BEANTWORTEN.
    ///
    /// Dieselbe Antwort ein zweites Mal nimmt sie zurück — der Tag ist dann
    /// wieder unbeantwortet. Das ist derselbe Umschalt-Reflex wie bei der
    /// Checkbox und der einzige Weg, ein versehentliches Ja oder Nein ohne
    /// Umweg über ein Menü loszuwerden.
    func answer(_ id: UUID, day: String = DayKey.today(), yes: Bool) {
        guard let i = data.habits.firstIndex(where: { $0.id == id }) else { return }
        let value = yes ? Habit.Answer.yes : Habit.Answer.no
        data.habits[i].log[day] = data.habits[i].log[day] == value ? nil : value
        data.habits[i].missedDays.removeAll { $0 == day }
        if yes { autoArchiveIfNeeded(at: i, day: day) }
        persist()
    }

    /// Der aktuelle Tageswert; nil = kein Eintrag. Das ist der Wert, den
    /// „Rückgängig" sich VOR einer Änderung merkt.
    func value(_ id: UUID, day: String = DayKey.today()) -> Int? {
        data.habits.first { $0.id == id }?.log[day]
    }

    /// Setzt den Tageswert EXAKT. Der Gegenspieler zu `value` und damit die
    /// Grundlage für ein ehrliches Rückgängig: `toggle` und `increment`
    /// würden nur „irgendwie zurück" kommen — ein Mengen-Habit, das von 3
    /// auf 4 gezählt wurde, muss wieder auf 3 landen, nicht auf 0.
    /// nil (oder ≤ 0) entfernt den Eintrag; 0-Werte werden nie
    /// materialisiert (siehe Habit-Dekodierung).
    func setValue(_ id: UUID, day: String, value: Int?) {
        guard let i = data.habits.firstIndex(where: { $0.id == id }) else { return }
        let normalized = value.flatMap { $0 >= 1 ? $0 : nil }
        let wasMissed = data.habits[i].missedDays.contains(day)
        guard data.habits[i].log[day] != normalized || wasMissed else { return }
        data.habits[i].log[day] = normalized
        data.habits[i].missedDays.removeAll { $0 == day }
        if normalized != nil { autoArchiveIfNeeded(at: i, day: day) }
        persist()
    }

    func setReminderCompletion(_ id: UUID, day: String, completed: Bool,
                               nextCursor: String?) {
        guard let i = data.habits.firstIndex(where: { $0.id == id && $0.isReminder }) else {
            return
        }
        data.habits[i].log[day] = completed ? 1 : nil
        data.habits[i].missedDays.removeAll { $0 == day }
        if !data.habits[i].repeatsWhileIncomplete {
            data.habits[i].reminderCursor = completed ? nextCursor : day
        }
        if completed { autoArchiveIfNeeded(at: i, day: day) }
        persist()
    }

    private func autoArchiveIfNeeded(at index: Int, day: String) {
        guard data.viewPreferences.autoArchiveCompletedItems,
              data.habits.indices.contains(index),
              data.habits[index].archivedAt == nil else { return }
        let habit = data.habits[index]
        let calendar = HabitTimeZone.calendar(for: habit,
                                              defaultIdentifier: data.defaultTimeZoneIdentifier)
        guard GoalEngine.dayCounts(habit: habit, day: day, calendar: calendar),
              habit.recurrence.isFinalOccurrence(on: day, calendar: calendar) else { return }
        data.habits[index].archivedAt = day
    }

    /// Converts stale open reminder occurrences into explicit negative days.
    /// One persistence pass covers all reminders so launch/rescheduling cannot
    /// create a write storm.
    @discardableResult
    func materializeMissedReminderDays(now: Date = .now) -> Bool {
        var changed = false
        for index in data.habits.indices where data.habits[index].isReminder {
            let habit = data.habits[index]
            let calendar = HabitTimeZone.calendar(
                for: habit,
                defaultIdentifier: data.defaultTimeZoneIdentifier)
            let additions = ReminderOccurrenceEngine.missedDays(
                for: habit, now: now, calendar: calendar)
            guard !additions.isEmpty else { continue }
            let merged = Array(Set(habit.missedDays).union(additions)).sorted()
            guard merged != habit.missedDays else { continue }
            data.habits[index].missedDays = merged
            changed = true
        }
        if changed { persist() }
        return changed
    }

    /// Applies each item's selected result after its local scheduled day has
    /// ended. The method is idempotent, so activation and repeated
    /// notification rescheduling are safe.
    @discardableResult
    func resolveExpiredOccurrences(now: Date = .now) -> Bool {
        var changed = false
        for index in data.habits.indices {
            let habit = data.habits[index]
            guard let configuredChoice = habit.autoResolveChoice else { continue }
            let choices = HabitAutoResolveChoice.choices(for: habit.kind,
                                                         itemType: habit.itemType)
            let choice = choices.contains(configuredChoice)
                ? configuredChoice
                : HabitAutoResolveChoice.defaultChoice(for: habit.kind,
                                                       itemType: habit.itemType)
            let calendar = HabitTimeZone.calendar(
                for: habit,
                defaultIdentifier: data.defaultTimeZoneIdentifier)
            let days = ReminderOccurrenceEngine.expiredOccurrences(
                for: habit, now: now, calendar: calendar)
            for day in days {
                switch choice {
                case .done:
                    let value = habit.kind == .quantity
                        ? (habit.recurrence.target ?? 1) : 1
                    data.habits[index].log[day] = value
                    data.habits[index].missedDays.removeAll { $0 == day }
                    autoArchiveIfNeeded(at: index, day: day)
                case .notDone:
                    data.habits[index].missedDays.append(day)
                case .yes:
                    data.habits[index].log[day] = Habit.Answer.yes
                    data.habits[index].missedDays.removeAll { $0 == day }
                    autoArchiveIfNeeded(at: index, day: day)
                case .no:
                    data.habits[index].log[day] = Habit.Answer.no
                    data.habits[index].missedDays.removeAll { $0 == day }
                }
                changed = true
            }
            if !days.isEmpty {
                data.habits[index].missedDays = Array(Set(data.habits[index].missedDays)).sorted()
            }
        }
        if changed { persist() }
        return changed
    }

    /// Schreibt tatsächliche Session-Minuten an einen Tag. MAX statt
    /// Überschreiben — dieselbe Regel wie im Merge: eine zweite, kürzere
    /// Session am selben Tag darf die längere nicht kleinrechnen, und ein
    /// Gerät mit weniger Minuten kann ein anderes nie herunterziehen.
    /// Ungültige Tage oder Minuten < 1: No-op.
    func recordSessionMinutes(_ id: UUID, day: String, minutes: Int) {
        guard let i = data.habits.firstIndex(where: { $0.id == id }),
              minutes >= 1, DayKey.isValid(day) else { return }
        let merged = max(data.habits[i].minutes[day] ?? 0, minutes)
        guard data.habits[i].minutes[day] != merged else { return }
        data.habits[i].minutes[day] = merged
        persist()
    }

    func addSessionRecord(_ record: HabitSessionRecord, persist shouldPersist: Bool = true) {
        guard !data.sessionHistory.contains(where: { $0.id == record.id }) else { return }
        data.sessionHistory.append(record)
        if shouldPersist { persist() }
    }

    /// Entfernt den Tageseintrag komplett.
    func clear(_ id: UUID, day: String = DayKey.today()) {
        guard let i = data.habits.firstIndex(where: { $0.id == id }),
              data.habits[i].log[day] != nil else { return }
        data.habits[i].log[day] = nil
        data.habits[i].missedDays.removeAll { $0 == day }
        persist()
    }

    /// Archivieren erhält die Historie; das Habit verschwindet nur aus
    /// Liste, Summary und Widget.
    func archive(_ id: UUID, day: String = DayKey.today()) {
        guard let i = data.habits.firstIndex(where: { $0.id == id }),
              data.habits[i].archivedAt == nil else { return }
        data.habits[i].archivedAt = day
        persist(calendarSync: .items([id]))
    }

    func unarchive(_ id: UUID) {
        guard let i = data.habits.firstIndex(where: { $0.id == id }),
              data.habits[i].archivedAt != nil else { return }
        data.habits[i].archivedAt = nil
        persist(calendarSync: .items([id]))
    }

    /// Verschiebt Habits per Drag — die Offsets beziehen sich auf
    /// `activeHabits` (was die Liste zeigt); archivierte Habits behalten
    /// ihre Positionen im Gesamtarray.
    func move(fromOffsets source: IndexSet, toOffset destination: Int, persist: Bool = true) {
        var active = activeHabits
        active.move(fromOffsets: source, toOffset: destination)
        var iterator = active.makeIterator()
        data.habits = data.habits.map { $0.archivedAt == nil ? (iterator.next() ?? $0) : $0 }
        if persist {
            self.persist()
        }
    }

    /// Reorders only the visible active items while leaving filtered-out
    /// active items in their existing slots. The Heute view passes its visible
    /// IDs here because its drag offsets are not offsets into `activeHabits`.
    func moveVisible(_ visibleIDs: [UUID],
                     fromOffsets source: IndexSet,
                     toOffset destination: Int,
                     persist: Bool = true) {
        guard !visibleIDs.isEmpty,
              Set(visibleIDs).count == visibleIDs.count,
              visibleIDs.allSatisfy({ id in
                  data.habits.contains { $0.id == id && $0.archivedAt == nil }
              }) else { return }

        var reorderedIDs = visibleIDs
        reorderedIDs.move(fromOffsets: source, toOffset: destination)
        let visibleSet = Set(visibleIDs)
        let originalByID = Dictionary(uniqueKeysWithValues: data.habits.map { ($0.id, $0) })
        var iterator = reorderedIDs.makeIterator()

        data.habits = data.habits.map { habit in
            guard habit.archivedAt == nil,
                  visibleSet.contains(habit.id),
                  let replacementID = iterator.next(),
                  let replacement = originalByID[replacementID] else {
                return habit
            }
            return replacement
        }
        if persist {
            self.persist()
        }
    }

    /// Offene AKTIVE Habits für heute (für die Abend-Zusammenfassung).
    /// „Offen" heißt HEUTE FÄLLIG und noch nicht abgehakt: ein Habit, das
    /// nach seiner Regel heute gar keinen Termin hat, ist nicht offen — es
    /// wäre die unangenehmste Sorte Erinnerung, an etwas gemahnt zu werden,
    /// das gar nicht dran ist. (Flexible Ziele wie „3× pro Woche" sind an
    /// jedem Tag ihrer Periode fällig, für sie ändert sich nichts.)
    ///
    /// **Ein verneinter Tag ist NICHT offen.** Er ist erledigt im Sinne von
    /// „entschieden": um 20 Uhr an etwas zu erinnern, das man um 14 Uhr
    /// ausdrücklich mit Nein beantwortet hat, wäre keine Erinnerung, sondern
    /// eine Nachfrage.
    func openToday(_ today: String = DayKey.today(),
                   calendar: Calendar = .current,
                   habits: [Habit]? = nil) -> [Habit] {
        let tracked = (habits ?? activeHabits).filter(\.isTrackedHabit)
        return tracked.filter {
            GoalEngine.isScheduled(habit: $0, day: today, calendar: calendar)
                && !$0.isDone(today) && !$0.isAnswered(today)
        }
    }

    // MARK: – Stand für die Zusammenfassungen
    //
    // Reine Zahlen, kein Text und keine Benachrichtigung: die Sätze baut
    // `SummaryText`, gestellt wird in `Reminders`. Beides hängt an DIESER
    // Rechnung, damit „3 von 5 erledigt" und die Liste darunter nicht aus
    // zwei verschiedenen Quellen stammen.

    /// Heute: fällige Termine, davon erfüllte, und die Namen der offenen.
    /// „Fällig" ist exakt dasselbe wie in `openToday` — ein Habit ohne Termin
    /// steht in keiner der drei Zahlen.
    ///
    /// Ein mit NEIN beantworteter Tag zählt in `total` (er war fällig), aber
    /// weder in `done` noch in `missing`: er ist nicht erfüllt und trotzdem
    /// nicht offen. Deshalb ist `done + missing.count` hier nicht zwingend
    /// `total` — die Summe war nie die Aussage, „x von y" und „das steht noch
    /// aus" sind zwei verschiedene Sätze (siehe `SummaryText`).
    func dailyStatus(_ today: String = DayKey.today(),
                     calendar: Calendar = .current,
                     habits: [Habit]? = nil) -> SummaryStatus {
        var done = 0, total = 0
        var missing: [String] = []
        let tracked = (habits ?? activeHabits).filter(\.isTrackedHabit)
        for habit in tracked
        where GoalEngine.isScheduled(habit: habit, day: today, calendar: calendar) {
            total += 1
            if GoalEngine.dayCounts(habit: habit, day: today, calendar: calendar) {
                done += 1
            } else if !habit.isAnswered(today) {
                missing.append(habit.name)
            }
        }
        return SummaryStatus(done: done, total: total, missing: missing)
    }

    /// Die laufende Woche bis einschließlich heute: erfüllte gegen fällige
    /// TERMINE über alle aktiven Habits, plus die Namen derer, die
    /// hinterherhinken.
    ///
    /// Flexible Ziele („3× pro Woche") zählen mit ihrer ANZAHL, nicht mit
    /// sieben fälligen Tagen — für sie ist jeder Tag der Periode ein
    /// möglicher Termin, aber geschuldet sind drei. Flexible Ziele mit
    /// größerer Periode (monatlich, jährlich) stehen bewusst gar nicht in der
    /// Wochenbilanz: „5× pro Monat" ist keine Wochenschuld.
    /// `fullWeek` zählt die GESCHULDETEN Termine über die ganze Woche statt
    /// nur bis heute — erfüllt wird weiterhin nur, was schon im Log steht.
    /// Das ist der Stoff für die WOCHEN-Mitteilung: sie feuert am
    /// Wochenende, geplant wird sie aber oft am Montag — mit „bis heute"
    /// wäre eine Woche, deren einziger Termin noch vor ihr liegt, scheinbar
    /// leer, und der Plan fiele ersatzlos aus (gemeldeter Fehler).
    func weeklyStatus(_ today: String = DayKey.today(),
                      calendar: Calendar = .current,
                      fullWeek: Bool = false,
                      habits: [Habit]? = nil) -> SummaryStatus {
        guard let todayDate = DayKey.date(from: today, calendar: calendar),
              let week = calendar.dateInterval(of: .weekOfYear, for: todayDate)?.start
        else { return SummaryStatus(done: 0, total: 0, missing: []) }
        let firstDay = DayKey.key(for: week, calendar: calendar)
        let lastDay = DayKey.shifted(firstDay, by: 6, calendar: calendar) ?? today
        let dueThrough = fullWeek ? max(lastDay, today) : today
        var done = 0, total = 0
        var missing: [String] = []
        let tracked = (habits ?? activeHabits).filter(\.isTrackedHabit)
        for habit in tracked {
            let schedule = habit.recurrence.schedule(calendar: calendar)
            var due = 0, met = 0
            if let times = habit.recurrence.timesPerPeriod {
                guard habit.recurrence.frequency == .weekly,
                      schedule.isActivePeriod(week),
                      schedule.isScheduled(firstDay) || schedule.isScheduled(today)
                else { continue }
                due = times
                met = min(times, countingDays(habit, from: firstDay, to: today, calendar: calendar))
            } else {
                var day = firstDay
                while day <= dueThrough {
                    if schedule.isScheduled(day) {
                        due += 1
                        if day <= today,
                           GoalEngine.dayCounts(habit: habit, day: day, calendar: calendar) { met += 1 }
                    }
                    guard let next = DayKey.shifted(day, by: 1, calendar: calendar) else { break }
                    day = next
                }
            }
            guard due > 0 else { continue }
            total += due
            done += met
            if met < due { missing.append(habit.name) }
        }
        return SummaryStatus(done: done, total: total, missing: missing)
    }

    /// Zählende Tage im Fenster — die Grundlage der flexiblen Wochenbilanz.
    private func countingDays(_ habit: Habit, from: String, to: String,
                              calendar: Calendar) -> Int {
        var day = from, n = 0
        while day <= to {
            if GoalEngine.dayCounts(habit: habit, day: day, calendar: calendar) { n += 1 }
            guard let next = DayKey.shifted(day, by: 1, calendar: calendar) else { break }
            day = next
        }
        return n
    }

    // MARK: – Eigene Paletten
    //
    // Anlegen, Umbenennen, Ändern, Löschen. Gespeichert wird immer nur die
    // Basisfarbe; die Rampe entsteht beim Lesen neu.

    @discardableResult
    func addCustomPalette(name: String, base: UInt32) -> CustomPalette {
        let palette = CustomPalette(name: name, base: base)
        data.customPalettes.append(palette)
        persist(changeKind: .appearance)
        return palette
    }

    /// Umbenennen UND Umfärben in einem — die Oberfläche hat für beides
    /// dasselbe Blatt, und beides ist derselbe Schreibvorgang.
    func updateCustomPalette(_ palette: CustomPalette) {
        guard let i = data.customPalettes.firstIndex(where: { $0.id == palette.id }) else { return }
        data.customPalettes[i] = palette
        persist(changeKind: .appearance)
    }

    /// Wer benutzt diese Palette gerade? Grundlage für die Rückfrage vor dem
    /// Löschen — ohne sie würde eine Farbe klaglos unter mehreren Habits
    /// weggezogen.
    func paletteUsage(_ id: UUID) -> (global: Bool, habits: [Habit]) {
        (data.palette == .custom(id), data.habits.filter { $0.palette == .custom(id) })
    }

    func isCustomPaletteInUse(_ id: UUID) -> Bool {
        let usage = paletteUsage(id)
        return usage.global || !usage.habits.isEmpty
    }

    /// Löschen räumt AUF: die globale Einstellung fällt auf den Standard
    /// zurück, Habit-Übersteuerungen auf „Wie App". Der Verweis überlebt das
    /// Löschen also nirgends — die Auflösung fängt eine verwaiste Kennung zwar
    /// ohnehin ab, aber ein aufgeräumter Zustand ist kein Zufallsergebnis.
    func removeCustomPalette(_ id: UUID) {
        data.customPalettes.removeAll { $0.id == id }
        if data.palette == .custom(id) { data.palette = .default }
        for i in data.habits.indices where data.habits[i].palette == .custom(id) {
            data.habits[i].palette = nil
        }
        persist(changeKind: .appearance)
    }

    // MARK: – Merge (Union: ein Check-in irgendwo zählt)

    /// Vereinigt Remote-Daten mit lokalen: Habits per id, Logs als Union
    /// mit MAX pro Tag (ein höherer Zähler irgendwo gewinnt) — nie wird
    /// ein Tag gelöscht. Bei Metadaten-Konflikt (Name/Emoji/Erinnerung/
    /// Regel/Archiv) gewinnt der neuere `updatedAt`-Stand.
    /// Exakter Gleichstand: LOKAL gewinnt — nie beidseitig löschen.
    ///
    /// **Was MAX mit den Ja/Nein-Codes macht** — die Reihenfolge im Band ist
    /// genau deshalb so gewählt (`yes` = 902 000 > `no` = 901 000 >
    /// `maxCount` = 900 000):
    ///
    ///  * Antwort gegen nichts -> die Antwort. Eine Antwort kann also nie
    ///    verschwinden, so wenig wie ein Check-in verschwinden kann.
    ///  * Ja gegen Nein -> Ja. Dieselbe Regel wie überall in diesem Merge:
    ///    das Positivere gewinnt, nie das Löschende. Sie ist damit
    ///    ASYMMETRISCH — eine Korrektur von Ja auf Nein kann ein Gerät, das
    ///    noch das alte Ja trägt, wieder aufziehen. Das ist keine neue
    ///    Eigenheit dieser Habit-Art, sondern dieselbe, die ein von 5 auf 3
    ///    korrigierter Zähler seit jeher hat; ein Zurücknehmen über Geräte
    ///    hinweg gibt es in diesem Merge nicht.
    ///  * Antwort gegen Zähler -> die Antwort (das Band liegt über jedem
    ///    Zähler, `increment` deckelt bei `maxCount`). Genau das braucht der
    ///    Rückweg von einem ausgelieferten Build: dessen „1" verliert gegen
    ///    das „Nein", das dieser Build geschrieben hat.
    ///
    /// Eine Antwort kann durch den Merge also NIE zu „unbeantwortet" werden
    /// und nie von Ja auf Nein kippen.
    func merge(remote: HabitData) {
        var byId = Dictionary(uniqueKeysWithValues: data.habits.map { ($0.id, $0) })
        let remoteNewer = remote.updatedAt > data.updatedAt
        // Appearance is edited independently from habits and check-ins. New
        // payloads carry their own timestamp; two legacy payloads retain the
        // old root-timestamp rule so upgrades do not silently stop syncing.
        let remoteAppearanceNewer: Bool
        if let localAppearanceUpdatedAt = data.appearanceUpdatedAt {
            if let remoteAppearanceUpdatedAt = remote.appearanceUpdatedAt {
                remoteAppearanceNewer = remoteAppearanceUpdatedAt > localAppearanceUpdatedAt
            } else {
                // An old build cannot prove that its newer root timestamp
                // came from an appearance edit.
                remoteAppearanceNewer = false
            }
        } else if let remoteAppearanceUpdatedAt = remote.appearanceUpdatedAt,
                  remoteAppearanceUpdatedAt > 0 {
            remoteAppearanceNewer = true
        } else {
            remoteAppearanceNewer = remoteNewer
        }
        for rh in remote.habits {
            if var lh = byId[rh.id] {
                for (k, v) in rh.log {
                    let merged = max(lh.log[k] ?? 0, v)
                    if merged >= 1 { lh.log[k] = merged } // 0-Werte nie materialisieren
                }
                // Session-Minuten wie der Log: Union mit MAX pro Tag — mehr
                // gemessene Zeit irgendwo gewinnt, gelöscht wird nie.
                for (k, v) in rh.minutes {
                    let merged = max(lh.minutes[k] ?? 0, v)
                    if merged >= 1 { lh.minutes[k] = merged }
                }
                lh.missedDays = Array(Set(lh.missedDays).union(rh.missedDays)).sorted()
                if remoteNewer {
                    lh.name = rh.name
                    lh.emoji = rh.emoji
                    lh.itemType = rh.itemType
                    lh.reminderMinutes = rh.reminderMinutes
                    lh.timeMinutes = rh.timeMinutes
                    lh.notificationMode = rh.notificationMode
                    lh.calendarSyncEnabled = rh.calendarSyncEnabled
                    lh.timeZoneIdentifier = rh.timeZoneIdentifier
                    lh.repeatsWhileIncomplete = rh.repeatsWhileIncomplete
                    lh.reminderCursor = rh.reminderCursor
                    lh.autoResolveChoice = rh.autoResolveChoice
                    lh.recurrence = rh.recurrence
                    lh.durationMinutes = rh.durationMinutes
                    lh.archivedAt = rh.archivedAt
                    lh.palette = rh.palette
                    lh.swipeActions = rh.swipeActions
                    lh.kind = rh.kind
                }
                // Die Art zum Schluss noch einmal am VEREINIGTEN Log
                // nachziehen: bringt die Gegenseite die erste Antwort mit
                // (oder hat ein ausgelieferter Build den Marker unterwegs
                // abgestreift), steht sie danach trotzdem richtig da.
                lh.kind = Habit.resolvedKind(marker: lh.kind.rawValue,
                                             log: lh.log,
                                             target: lh.recurrence.target)
                byId[rh.id] = lh
            } else {
                byId[rh.id] = rh
            }
        }
        // Reihenfolge: lokale zuerst (bestehende Ordnung), dann neue Remote-Habits
        var merged = data.habits.compactMap { byId[$0.id] }
        let localIds = Set(data.habits.map(\.id))
        merged.append(contentsOf: remote.habits.filter { !localIds.contains($0.id) }.compactMap { byId[$0.id] })
        data.habits = merged
        let localRecordIDs = Set(data.sessionHistory.map(\.id))
        data.sessionHistory += remote.sessionHistory.filter { !localRecordIDs.contains($0.id) }
        if remoteNewer {
            data.summaryMinutes = remote.summaryMinutes
            data.weeklySummaryMinutes = remote.weeklySummaryMinutes
            data.weeklySummaryWeekday = remote.weeklySummaryWeekday
            data.motivationMinutes = remote.motivationMinutes
            data.motivationDelivery = remote.motivationDelivery
            data.motivationSource = remote.motivationSource
            data.defaultTimeZoneIdentifier = remote.defaultTimeZoneIdentifier
            data.updatedAt = remote.updatedAt
            if let remoteShowsUsername = remote.githubShowsUsername {
                data.githubShowsUsername = remoteShowsUsername
                GitHubPreferences.setShowsUsername(remoteShowsUsername,
                                                    in: GitHubPreferences.defaults)
            }
        }
        // Darstellung reist mit: das neuere Gerät gibt das Aussehen vor.
        // Anders als summaryMinutes gibt es hier kein "nil = nicht gesetzt",
        // der Standard IST ein gültiger Wert.
        if remoteAppearanceNewer {
            data.appearance = remote.appearance
            let localPreferences = data.appearancePreferences
            let remotePreferences = remote.appearancePreferences.normalizedForStorage()
            var nextPreferences = remotePreferences
            let localMarker = localPreferences.backgroundResetAt ?? 0
            let remoteMarker = remotePreferences.backgroundResetAt ?? 0
            if localMarker > remoteMarker {
                // Preserve the local background whenever the incoming image
                // predates a local reset, including a color-mode payload that
                // still carries old image bytes.
                nextPreferences.backgroundMode = localPreferences.backgroundMode
                nextPreferences.backgroundColorHex = localPreferences.backgroundColorHex
                nextPreferences.gradientStartHex = localPreferences.gradientStartHex
                nextPreferences.gradientEndHex = localPreferences.gradientEndHex
                nextPreferences.backgroundImageData = localPreferences.backgroundImageData
                nextPreferences.backgroundResetAt = localPreferences.backgroundResetAt
            }
            data.appearancePreferences = nextPreferences.normalizedForStorage()
            data.palette = remote.palette
            data.matchAppIcon = remote.matchAppIcon
            data.manualAppIconName = remote.manualAppIconName
            data.appearanceUpdatedAt = remote.appearanceUpdatedAt
        }
        if remoteNewer, let remoteCloudPreferences = remote.cloudPreferences {
            data.cloudPreferences = remoteCloudPreferences
        }
        if remote.viewPreferences.updatedAt > data.viewPreferences.updatedAt {
            data.viewPreferences = remote.viewPreferences
        }
        // Eigene Paletten sind additive Daten wie Habits, nicht wie eine
        // Einstellung: VEREINIGT nach Kennung, damit eine auf dem anderen
        // Gerät angelegte Farbe nicht verschwindet. Nur bei gleicher Kennung
        // entscheidet der neuere Stand über Name und Farbe.
        var paletteById = Dictionary(uniqueKeysWithValues: data.customPalettes.map { ($0.id, $0) })
        for rp in remote.customPalettes {
            if paletteById[rp.id] == nil || remoteAppearanceNewer { paletteById[rp.id] = rp }
        }
        var mergedPalettes = data.customPalettes.compactMap { paletteById[$0.id] }
        let localPaletteIds = Set(data.customPalettes.map(\.id))
        mergedPalettes.append(contentsOf: remote.customPalettes.filter { !localPaletteIds.contains($0.id) })
        data.customPalettes = mergedPalettes
        let mergeChangeKind: HabitStoreChange = remoteAppearanceNewer && !remoteNewer ? .appearance : .general
        persist(changeKind: mergeChangeKind, touchTimestamp: false,
                calendarSync: mergeChangeKind == .general ? .allMapped : nil)
    }

    // MARK: – Export / Import

    func exportJSON() -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(data)
    }

    func importJSON(_ raw: Data) throws {
        let incoming = try JSONDecoder().decode(HabitData.self, from: raw)
        merge(remote: incoming)
    }
}
