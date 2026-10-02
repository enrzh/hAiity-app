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
    /// Wann diese Einstellung zuletzt gesetzt wurde.
    ///
    /// Gleiche Lücke wie bei `githubShowsUsername`: ohne Stempel entscheidet der
    /// Wurzel-`updatedAt` über sie, und ein Check-in auf einem anderen Gerät
    /// überschreibt sie mit einem älteren Wert.
    var updatedAt: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case calendarSyncHabits
        case calendarSyncReminders
        case nativeReminderSync
        case notificationPromptsSuppressed
        case notificationDND
        case shakeToReportEnabled
        case updatedAt
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
        updatedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .updatedAt)
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
        if let updatedAt { try container.encode(updatedAt, forKey: .updatedAt) }
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
    /// Wann diese Einstellung zuletzt gesetzt wurde.
    ///
    /// Ohne diesen Stempel entscheidet der Wurzel-`updatedAt` über sie, und das
    /// ist die falsche Frage: ein Check-in auf einem anderen Gerät macht dessen
    /// Wurzel-Zeitstempel neuer, ohne dass sich diese Einstellung geändert hat —
    /// und überschreibt sie dann mit einem älteren Wert. Dieselbe Lücke, die
    /// `appearanceUpdatedAt` für die Darstellung schließt.
    var githubShowsUsernameUpdatedAt: TimeInterval?
    /// Ansichts-Einstellungen (Statistik-Karten und kompakte Darstellung).
    /// Sie reisen als Teil desselben privaten iCloud-Payloads mit.
    var viewPreferences: ViewPreferences
    /// Synced user intent for system integrations. Permissions, native IDs,
    /// and per-device event/reminder mappings deliberately remain local.
    var cloudPreferences: CloudPreferences?

    /// IDs of habits that were deleted on some device, mapped to when.
    ///
    /// The merge is a union by design — a check-in arriving from a device that
    /// still has the data must not be lost — and a union cannot carry a
    /// deletion. Without this, deleting a habit on one device and syncing from
    /// another that still has it brings it back. The map is a timestamp so old
    /// tombstones can be dropped, which is what keeps the set bounded.
    var deletedHabits: [UUID: TimeInterval]

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
         githubShowsUsernameUpdatedAt: TimeInterval? = nil,
         weeklySummaryMinutes: Int? = nil,
         weeklySummaryWeekday: Int = HabitData.defaultSummaryWeekday,
         viewPreferences: ViewPreferences = ViewPreferences(),
         cloudPreferences: CloudPreferences? = nil,
         sessionHistory: [HabitSessionRecord] = [],
         deletedHabits: [UUID: TimeInterval] = [:],
         motivationMinutes: Int? = nil,
         motivationDelivery: MotivationDelivery = .notification,
         motivationSource: Motivation.Source = .builtIn) {
        self.version = version
        self.updatedAt = updatedAt
        self.appearanceUpdatedAt = appearanceUpdatedAt
        self.deletedHabits = deletedHabits
        self.defaultTimeZoneIdentifier = HabitTimeZone.sanitizedIdentifier(defaultTimeZoneIdentifier)
        self.summaryMinutes = summaryMinutes
        self.weeklySummaryMinutes = weeklySummaryMinutes
        self.deletedHabits = deletedHabits
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
        self.githubShowsUsernameUpdatedAt = githubShowsUsernameUpdatedAt
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
        case githubShowsUsernameUpdatedAt
        case customPalettes
        // Die Wochenzusammenfassung ist rein ADDITIV: ein Build ohne sie
        // überliest die beiden Schlüssel, also braucht es dafür keinen
        // Versionssprung (der ihn aussperren würde).
        case weeklySummaryMinutes, weeklySummaryWeekday, viewPreferences, sessionHistory
        case deletedHabits
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
        // Additive and tolerant, like every field since v2: a payload from
        // before tombstones existed simply has none, and that is not an error.
        deletedHabits = (try? c.decodeIfPresent([UUID: TimeInterval].self, forKey: .deletedHabits)) ?? [:]
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
        githubShowsUsernameUpdatedAt = try c.decodeIfPresent(TimeInterval.self,
                                                              forKey: .githubShowsUsernameUpdatedAt)
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
        if !deletedHabits.isEmpty { try c.encode(deletedHabits, forKey: .deletedHabits) }
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
        if let githubShowsUsernameUpdatedAt {
            try c.encode(githubShowsUsernameUpdatedAt, forKey: .githubShowsUsernameUpdatedAt)
        }
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
        if isOwnerDevice(storedAppleUserID: defaults.string(forKey: PersonalName.appleUserIDKey),
                         storedAppleEmail: defaults.string(forKey: PersonalName.appleEmailKey)) {
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
    @ObservationIgnored private var loadedSignature: (modified: Date?, size: Int)?
    @ObservationIgnored private var persistedPayload: Data?

    /// Set when the file on disk exists but will not decode. The store still
    /// starts empty so the app is usable, but the failure is recorded rather than
    /// swallowed, and the unreadable file is preserved before it can be
    /// overwritten.
    @ObservationIgnored private(set) var readFailed = false

    /// Tombstones older than the retention window go, which is what keeps the
    /// set bounded rather than a list of every habit ever deleted.
    static func pruneTombstones(in data: inout HabitData,
                                now: TimeInterval = Date().timeIntervalSince1970) {
        guard !data.deletedHabits.isEmpty else { return }
        let cutoff = now - sessionHistoryRetention
        // Ein Stempel IN DER ZUKUNFT wird nie verworfen. Er kommt von einer
        // nachgehenden Uhr; nach `sessionHistoryRetention` gerechnet wäre eine
        // Löschung auf einem Gerät mit korrekter Uhr wieder da, genau dann wenn
        // sie eigentlich hätte greifen müssen.
        data.deletedHabits = data.deletedHabits.filter { $0.value >= cutoff || $0.value > now }
    }

    /// Keeps session records inside a retention window.
    ///
    /// These used to be appended on every merge with nothing ever removing them,
    /// so the array grew for the life of the install. It is written to data.json,
    /// mirrored to iCloud and loaded on every launch, so the cost is paid each
    /// time rather than once. A year is far longer than any streak or statistic
    /// looks back, and it keeps a long history for anyone who wants it.
    static let sessionHistoryRetention: TimeInterval = 366 * 24 * 60 * 60

    static func trimSessionHistory(in data: inout HabitData,
                                   now: Date = .now,
                                   calendar: Calendar = .current) {
        let cutoff = now.addingTimeInterval(-sessionHistoryRetention)
        data.sessionHistory.removeAll { record in
            guard let day = DayKey.date(from: record.day, calendar: calendar) else {
                return false   // unreadable, not old — never drop on a guess
            }
            return day < cutoff
        }
        // Keep the newest first, which is how the session list reads.
        data.sessionHistory.sort { $0.startedAt > $1.startedAt }
    }

    /// A count of how many times records have been trimmed. Written to the log
    /// rather than shown, so a silent retention policy is at least observable.
    @ObservationIgnored private(set) var trimmings = 0

    /// Why the last write did not land, if it did not. Surfaced to the UI so a
    /// failed save is a message instead of a change that quietly vanishes.
    /// Observable, because the point is that the interface reacts to it.
    private(set) var lastWriteError: String?

    init(url: URL = SharedStorage.dataURL(), loadFromDisk: Bool = true) {
        self.url = url
        if loadFromDisk {
            let outcome = Self.readResult(url)
            self.data = outcome.payload ?? .empty
            self.readFailed = outcome.corrupted
            self.persistedPayload = outcome.raw
            if outcome.corrupted { Self.preserveCorruptPayload(url) }
        } else {
            self.data = .empty
        }
        self.loadedSignature = loadFromDisk ? Self.signature(url) : nil
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
            // The stamp travels with the value, so the merge can tell a real
            // change from a side effect of some other device's timestamp.
            data.githubShowsUsernameUpdatedAt = Date().timeIntervalSince1970
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
        // The stamp is set on a real change, not on every persist, so the merge
        // can tell a preference edit from a check-in on another device.
        next.updatedAt = Date().timeIntervalSince1970
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

    /// Reads the payload. "Nothing there yet" and "there but unreadable" are NOT
    /// the same, and only the second is dangerous: treating an undecodable file
    /// as an empty store means the next write overwrites it, so a half-written or
    /// foreign payload costs everything that was in it.
    ///
    /// `read` keeps its optional shape for the callers that only want the data;
    /// anything deciding whether to overwrite a file uses `readResult`.
    static func read(_ url: URL) -> HabitData? {
        readResult(url).payload
    }

    static func readResult(_ url: URL) -> (payload: HabitData?, corrupted: Bool, raw: Data?) {
        guard let raw = try? Data(contentsOf: url) else {
            return (nil, false, nil)
        }
        guard !raw.isEmpty else { return (nil, false, raw) }
        guard let payload = try? JSONDecoder().decode(HabitData.self, from: raw) else {
            return (nil, true, raw)
        }
        return (payload, false, raw)
    }

    /// Keeps the last trace of a payload that will not decode, so the next write
    /// cannot be the thing that destroys it. Diagnostics rather than deletion.
    static func preserveCorruptPayload(_ url: URL) {
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("haiity.corrupt.json")
        try? FileManager.default.copyItem(at: url, to: backup)
    }

    /// Loads the initial payload away from the first SwiftUI render. The
    /// store is intentionally empty until this finishes so the splash can
    /// cover a mounted content tree without blocking the main thread.
    @MainActor
    func loadFromDisk() async {
        guard loadedSignature == nil else { return }
        let url = self.url
        let snapshot = await Task.detached(priority: .userInitiated) {
            (Self.readResult(url), Self.signature(url))
        }.value
        guard !Task.isCancelled, loadedSignature == nil else { return }
        loadedSignature = snapshot.1
        persistedPayload = snapshot.0.raw
        readFailed = snapshot.0.corrupted
        if readFailed { Self.preserveCorruptPayload(url) }
        guard let fresh = snapshot.0.payload else { return }
        data = fresh
        // A payload written before the retention window existed can already be
        // over it, so trim on the way in rather than only when merging.
        Self.trimSessionHistory(in: &data)
        // Tombstones too: habits deleted elsewhere must not be present just
        // because this payload predates them.
        //
        // The set is copied first on purpose. Reading `data.deletedHabits`
        // inside a `removeAll` that is mutating `data.habits` is a Swift
        // exclusivity conflict and aborts the process on launch — which is
        // exactly how this was found.
        let tombstones = data.deletedHabits
        data.habits.removeAll { tombstones[$0.id] != nil }
        Self.pruneTombstones(in: &data)
    }

    /// mtime PLUS size, as the thing that decides "did this file change".
    ///
    /// mtime alone is a heuristic with a hole in it: on a filesystem with coarse
    /// timestamp granularity an external writer can land within the same tick as
    /// the last read, and a change that did happen is then missed. Size is cheap
    /// and closes the common case of a rewrite to different content.
    private static func signature(_ url: URL) -> (modified: Date?, size: Int)? {
        guard let values = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return (values[.modificationDate] as? Date, (values[.size] as? Int) ?? 0)
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
        guard let current = Self.signature(url) else { return }
        // Tuples are not Equatable in Swift, so the two parts are compared by hand.
        if let known = loadedSignature,
           known.modified == current.modified, known.size == current.size {
            return
        }
        let outcome = Self.readResult(url)
        guard let fresh = outcome.payload else { return }
        persistedPayload = outcome.raw
        loadedSignature = current
        merge(remote: fresh)
    }

    /// Writes the payload, and says whether it landed.
    ///
    /// It used to swallow both the encode and the write. The in-memory state is
    /// already mutated by the time this runs, so a swallowed failure meant the
    /// person saw their change succeed and it was simply not there next launch —
    /// the same shape of silent loss as an unreadable file being overwritten.
    @discardableResult
    func persist(notify: Bool = true,
                 changeKind: HabitStoreChange = .general,
                 touchTimestamp: Bool = true,
                 calendarSync: CalendarSyncScope? = nil) -> Bool {
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
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing,
                                       error: &coordinationError) { destination in
            do {
                let current = Self.readResult(destination)
                guard current.raw == persistedPayload else {
                    // A stale app/widget snapshot cannot replace a newer save.
                    // Restore the durable state so an explicit retry starts fresh.
                    if let fresh = current.payload {
                        data = fresh
                        persistedPayload = current.raw
                        loadedSignature = Self.signature(destination)
                    }
                    throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey:
                        String(localized: "Die Daten wurden inzwischen geändert. Bitte erneut sichern.")])
                }
                let raw = try enc.encode(data)
                try raw.write(to: destination, options: .atomic)
                persistedPayload = raw
            } catch {
                writeError = error
            }
        }
        if let error = coordinationError ?? (writeError as NSError?) {
            lastWriteError = error.localizedDescription
            return false
        }
        lastWriteError = nil
        loadedSignature = Self.signature(url)
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
        return true
    }

    func requireSuccessfulWrite() throws {
        if let lastWriteError {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: lastWriteError])
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
        var habit = habit
        // Ein neu angelegter Habit startet mit Stempel, damit er ab der ersten
        // Sekunde nicht über den Wurzel-Zeitstempel konkurriert.
        if habit.updatedAt == nil { habit.updatedAt = Date().timeIntervalSince1970 }
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
        var habit = habit
        // `update` ist der Sammelweg für die Scalar-Felder, also der eine Ort,
        // an dem der Stempel garantiert weiterläuft.
        habit.updatedAt = Date().timeIntervalSince1970
        data.habits[i] = habit
        persist(calendarSync: .items([habit.id]))
    }

    func remove(_ id: UUID) {
        data.habits.removeAll { $0.id == id }
        data.sessionHistory.removeAll { $0.habitID == id }
        // A deletion is the one thing the union merge cannot carry, so it is
        // recorded as a tombstone for the other devices to apply.
        data.deletedHabits[id] = Date().timeIntervalSince1970
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
            // `reminderCursor` is a merged scalar, so moving it needs the stamp.
            stamp(i)
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
        // Automatisches Archivieren ist eine Scalar-Änderung und muss den
        // Stempel mitnehmen, sonst erreicht sie die andere Seite nicht.
        stamp(index)
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
                        ? (habit.recurrence.effectiveTarget) : 1
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
        stamp(i)
        persist(calendarSync: .items([id]))
    }

    func unarchive(_ id: UUID) {
        guard let i = data.habits.firstIndex(where: { $0.id == id }),
              data.habits[i].archivedAt != nil else { return }
        data.habits[i].archivedAt = nil
        stamp(i)
        persist(calendarSync: .items([id]))
    }

    /// Setzt den habit-eigenen Änderungsstempel.
    ///
    /// Nur für Eingriffe, die ein zusammengeführtes Scalar-Feld ändern. Ein
    /// reiner Log- oder Minuten-Eintrag fasst den Stempel NICHT an: Log und
    /// Minuten sind Vereinigungen und gewinnen ohnehin. Würde ein Abhaken den
    /// Stempel mitziehen, entschiede ein reines Abhaken wieder über Namens- und
    /// Terminänderungen einer anderen Seite — genau der Fehler, den der Stempel
    /// gerade behebt.
    private func stamp(_ index: Int) {
        data.habits[index].updatedAt = Date().timeIntervalSince1970
    }

    /// Verschiebt Habits per Drag — die Offsets beziehen sich auf
    /// `activeHabits` (was die Liste zeigt); archivierte Habits behalten
    /// ihre Positionen im Gesamtarray.
    func move(fromOffsets source: IndexSet, toOffset destination: Int, persist: Bool = true) {
        var active = activeHabits
        guard !source.isEmpty, source.allSatisfy(active.indices.contains),
              (0...active.count).contains(destination) else { return }
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
              !source.isEmpty, source.allSatisfy(visibleIDs.indices.contains),
              (0...visibleIDs.count).contains(destination),
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
            stamp(i)
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
        // Beide Entscheidungen werden EINMAL hier oben getroffen und nach unten
        // gereicht. Kein Schritt muss selbst herleiten, welche Seite neuer ist —
        // genau das hat diese Funktion auf 150 Zeilen wachsen lassen: Jede Sektion
        // hat die Frage für sich beantwortet, jedes Mal anders.
        // Ein unplausibel weit vorausliegender Stempel entscheidet nichts; siehe
        // `reliableStamp`.
        let remoteNewer = Self.reliableStamp(remote.updatedAt)
            .map { $0 > data.updatedAt } ?? false
        let remoteAppearanceNewer = Self.appearanceIsNewer(remote, than: data)
        Self.mergeHabits(remote, newer: remoteNewer, into: &data)
        Self.mergeSessionHistory(remote, into: &data)
        Self.mergeSummary(remote, newer: remoteNewer, into: &data)
        Self.mergeGitHubShowsUsername(remote, newer: remoteNewer, into: &data)
        Self.mergeAppearance(remote, newer: remoteAppearanceNewer, into: &data)
        Self.mergeCloudPreferences(remote, newer: remoteNewer, into: &data)
        Self.mergeViewPreferences(remote, into: &data)
        Self.mergeCustomPalettes(remote, newer: remoteAppearanceNewer, into: &data)
        let mergeChangeKind: HabitStoreChange = remoteAppearanceNewer && !remoteNewer ? .appearance : .general
        persist(changeKind: mergeChangeKind, touchTimestamp: false,
                calendarSync: mergeChangeKind == .general ? .allMapped : nil)
    }

    // MARK: - Merge, je Entität

    /// Jede Entität in einem eigenen Schritt.
    ///
    /// Der ganze Körper war ein einziger 150-Zeiler, der für Habits, Sessions,
    /// Zusammenfassung, Darstellung, Cloud-Einstellungen, Ansicht und Paletten
    /// nacheinander entschied — und dabei für jede Sektion neu ausrechnete,
    /// welche Seite aktueller ist. Getrennt ist jede Entität prüfbar, und die
    /// zwei Zeitstempel, über die alles entscheidet, stehen an genau einer Stelle.

    /// Welche Seite die Darstellung vorgibt.
    ///
    /// `appearanceUpdatedAt` reist MIT, weil Darstellung unabhängig von Habits
    /// und Check-ins editiert wird. Ein Alt-Payload ohne diesen Stempel kann
    /// nicht beweisen, dass sein neuerer Wurzel-Zeitstempel von einer
    /// Darstellungsänderung stammt — deshalb wird dort auf die alte
    /// Wurzel-Zeitstempel-Regel zurückgefallen, damit Upgrades nicht aufhören,
    /// zu synchronisieren.
    private static func appearanceIsNewer(_ remote: HabitData,
                                          than local: HabitData) -> Bool {
        if let localAppearanceUpdatedAt = local.appearanceUpdatedAt {
            if let remoteAppearanceUpdatedAt = remote.appearanceUpdatedAt {
                return remoteAppearanceUpdatedAt > localAppearanceUpdatedAt
            } else {
                // An old build cannot prove that its newer root timestamp
                // came from an appearance edit.
                return false
            }
        } else if let remoteAppearanceUpdatedAt = remote.appearanceUpdatedAt,
                  remoteAppearanceUpdatedAt > 0 {
            return true
        } else {
            return remote.updatedAt > local.updatedAt
        }
    }

    /// Habits: Logs als Union mit MAX pro Tag, Metadaten nach `newer`,
    /// dann Löschungen als Tombstones.
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
    /// Welche Seite die Skalarfelder EINES Habits vorgibt.
    ///
    /// Ein Habit mit eigenem Stempel wird nach diesem Stempel entschieden. Ein
    /// Habit ohne Stempel stammt aus einem Payload, der ihn nicht kannte, und
    /// das einzige verfügbare Indiz ist der Wurzel-Zeitstempel — die alte,
    /// konservative Regel, damit ein Upgrad nicht aufhört zu synchronisieren.
    ///
    /// Wichtig ist die Absicht dahinter: zwei Änderungen an VERSCHIEDENEN
    /// Habits sind kein Konflikt. Vor dieser Entscheidung hing die ganze
    /// Feldzusammenführung an einem einzigen Wurzel-Zeitstempel, wodurch ein
    /// Rename hier den Rename eines anderen Habits dort überschrieb, nur weil
    /// auf dem einen Gerät zur selben Zeit irgendetwas anderes gespeichert
    /// worden war. Der Verlust war still.
    private static func remoteFieldsWin(localStamp: TimeInterval?,
                                        remoteStamp: TimeInterval?,
                                        remoteRootIsNewer: Bool) -> Bool {
        guard let localStamp, let remoteStamp else { return remoteRootIsNewer }
        let now = Date().timeIntervalSince1970
        // Eine kaputte Uhr auf der Gegenseite ist kein Beleg für eine neuere
        // Änderung. Lieber die konservative Seite behalten als zuzusehen, wie
        // alle benachbarten Änderungen verschwinden.
        guard let remote = reliableStamp(remoteStamp, now: now) else { return false }
        return remote > (reliableStamp(localStamp, now: now) ?? localStamp)
    }

    /// Wie weit ein Zeitstempel in der Zukunft liegen darf, um noch als Beleg
    /// für eine neuere Änderung zu gelten.
    ///
    /// Sechs Stunden fangen echte Reise-Zeitzonen und automatische
    /// Zeitumstellungen auf. Alles darüber ist mit hoher Wahrscheinlichkeit eine
    /// kaputte Uhr — und eine kaputte Uhr, die als „neuer" gilt, nimmt einem
    /// Gerät die Arbeit anderer Geräte weg, bis sie wieder stimmt.
    static let maxFutureStampSkew: TimeInterval = 6 * 3600

    /// Der Zeitstempel, wenn er belastbar ist; `nil`, wenn nicht.
    ///
    /// `nil` heißt ausdrücklich „weiß es nicht" — nicht „alt". Die Aufrufer
    /// entscheiden dann conservativ, statt eine kaputte Uhr zu überzeugen.
    static func reliableStamp(_ value: TimeInterval?,
                              now: TimeInterval = Date().timeIntervalSince1970) -> TimeInterval? {
        guard let value, value <= now + maxFutureStampSkew else { return nil }
        return value
    }

    private static func mergeHabits(_ remote: HabitData,
                                   newer: Bool,
                                   into data: inout HabitData) {
        // Grouped by hand rather than with `Dictionary(uniqueKeysWithValues:)`,
        // which crashes outright on a duplicate. Duplicates should not exist, but
        // if one ever arrived from a malformed payload or a bad merge the answer
        // is to keep one entry, not to take the app down.
        var byId: [UUID: Habit] = [:]
        for habit in data.habits where byId[habit.id] == nil {
            byId[habit.id] = habit
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
                if Self.remoteFieldsWin(localStamp: lh.updatedAt,
                                        remoteStamp: rh.updatedAt,
                                        remoteRootIsNewer: newer) {
                    lh.name = rh.name
                    lh.emoji = rh.emoji
                    lh.itemType = rh.itemType
                    lh.reminderMinutes = rh.reminderMinutes
                    lh.timeMinutes = rh.timeMinutes
                    lh.notificationTimes = rh.notificationTimes
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
                    // Der Stempel wandert mit den Feldern. Ohne das wäre der
                    // Merge kein Fixpunkt: die losing Seite behielte ihren
                    // Stempel und zöge beim nächsten Versuch wieder vor.
                    lh.updatedAt = rh.updatedAt ?? lh.updatedAt
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
        // Deletions are the one thing a union cannot carry, so they travel as
        // tombstones and are applied afterwards — from BOTH sides. A habit
        // deleted here and still present on an older device comes back unless
        // its own tombstone is applied to whatever that device sends.
        let tombstones = data.deletedHabits
            .merging(remote.deletedHabits, uniquingKeysWith: max)
        data.habits.removeAll { tombstones[$0.id] != nil }
        data.deletedHabits = tombstones
        pruneTombstones(in: &data)
    }

    /// Sessions: Union ohne Duplikate, dann auf das Beibehaltungs-Fenster kürzen.
    private static func mergeSessionHistory(_ remote: HabitData,
                                            into data: inout HabitData) {
        let localRecordIDs = Set(data.sessionHistory.map(\.id))
        data.sessionHistory += remote.sessionHistory.filter { !localRecordIDs.contains($0.id) }
        trimSessionHistory(in: &data)
    }

    /// Zusammenfassung und Motivation: schlicht die neuere Seite.
    ///
    /// `githubShowsUsername` wird hier mit ausgenomen, weil es einen eigenen
    /// Stempel hat — es gehört nicht zur Zusammenfassung, und der Wurzel-Zeitstempel
    /// ist die falsche Instanz dafür.
    private static func mergeSummary(_ remote: HabitData,
                                     newer: Bool,
                                     into data: inout HabitData) {
        guard newer else { return }
        data.summaryMinutes = remote.summaryMinutes
        data.weeklySummaryMinutes = remote.weeklySummaryMinutes
        data.weeklySummaryWeekday = remote.weeklySummaryWeekday
        data.motivationMinutes = remote.motivationMinutes
        data.motivationDelivery = remote.motivationDelivery
        data.motivationSource = remote.motivationSource
        data.defaultTimeZoneIdentifier = remote.defaultTimeZoneIdentifier
        data.updatedAt = remote.updatedAt
    }

    /// Der GitHub-Namen-Schalter mit seinem eigenen Stempel.
    ///
    /// Er lag bislang in `mergeSummary` und wurde damit vom Wurzel-`updatedAt`
    /// entschieden — ein Check-in auf einem anderen Gerät macht dessen Wurzel
    /// neuer, ohne dass sich dieser Schalter geändert hat, und zieht ihn dann mit
    /// einem älteren Wert wieder auf. Der Stempel ist additiv: ein Payload ohne
    /// ihn fällt auf den Wurzel-Zeitstempel zurück, also auf das alte Verhalten.
    private static func mergeGitHubShowsUsername(_ remote: HabitData,
                                                 newer: Bool,
                                                 into data: inout HabitData) {
        guard let remoteValue = remote.githubShowsUsername else { return }
        // A stamp means the value was set by a build that knows about stamps; no
        // stamp means it predates them. When exactly one side is stamped, the
        // stamped side is the more recent by construction — a pre-feature value
        // is older than any post-feature one, whatever the root timestamp says.
        // With neither stamped there is nothing to go on but the root timestamp,
        // which is the behaviour before this field existed.
        let remoteWins: Bool
        switch (remote.githubShowsUsernameUpdatedAt, data.githubShowsUsernameUpdatedAt) {
        case let (.some(remoteStamp), .some(localStamp)): remoteWins = remoteStamp >= localStamp
        case (.some, .none):                             remoteWins = true
        case (.none, .some):                             remoteWins = false
        case (.none, .none):                             remoteWins = newer
        }
        guard remoteWins else { return }
        data.githubShowsUsername = remoteValue
        data.githubShowsUsernameUpdatedAt = remote.githubShowsUsernameUpdatedAt
        GitHubPreferences.setShowsUsername(remoteValue, in: GitHubPreferences.defaults)
    }

    /// Darstellung: das neuere Gerät gibt das Aussehen vor. Anders als
    /// summaryMinutes gibt es hier kein "nil = nicht gesetzt" — der Standard IST
    /// ein gültiger Wert.
    private static func mergeAppearance(_ remote: HabitData,
                                         newer: Bool,
                                         into data: inout HabitData) {
        guard newer else { return }
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

    /// Cloud-Einstellungen: eigener Stempel, sonst der Wurzel-Zeitstempel.
    ///
    /// Sie sind Absicht, nicht Zähler, und ein Check-in auf einem anderen Gerät
    /// soll sie nicht mit einem älteren Wert überschreiben.
    private static func mergeCloudPreferences(_ remote: HabitData,
                                              newer: Bool,
                                              into data: inout HabitData) {
        guard let remoteValue = remote.cloudPreferences else { return }
        // Same rule as the GitHub switch: a stamped value is post-feature, an
        // unstamped one pre-feature, so a stamp on exactly one side settles it.
        let remoteWins: Bool
        switch (remoteValue.updatedAt, data.cloudPreferences?.updatedAt) {
        case let (.some(remoteStamp), .some(localStamp)): remoteWins = remoteStamp >= localStamp
        case (.some, .none):                             remoteWins = true
        case (.none, .some):                             remoteWins = false
        case (.none, .none):                             remoteWins = newer
        }
        if remoteWins { data.cloudPreferences = remoteValue }
    }

    /// Ansicht: eigener Zeitstempel, unabhängig vom Wurzel-Zeitstempel.
    private static func mergeViewPreferences(_ remote: HabitData,
                                             into data: inout HabitData) {
        if remote.viewPreferences.updatedAt > data.viewPreferences.updatedAt {
            data.viewPreferences = remote.viewPreferences
        }
    }

    /// Eigene Paletten sind additive Daten wie Habits, nicht wie eine
    /// Einstellung: VEREINIGT nach Kennung, damit eine auf dem anderen
    /// Gerät angelegte Farbe nicht verschwindet. Nur bei gleicher Kennung
    /// entscheidet der neuere Stand über Name und Farbe.
    ///
    /// Wie bei den Habits gruppiert von Hand statt mit
    /// `Dictionary(uniqueKeysWithValues:)`, das bei einem Duplikat abstürzt.
    private static func mergeCustomPalettes(_ remote: HabitData,
                                            newer: Bool,
                                            into data: inout HabitData) {
        var paletteById: [UUID: CustomPalette] = [:]
        for palette in data.customPalettes where paletteById[palette.id] == nil {
            paletteById[palette.id] = palette
        }
        for rp in remote.customPalettes {
            if paletteById[rp.id] == nil || newer { paletteById[rp.id] = rp }
        }
        var mergedPalettes = data.customPalettes.compactMap { paletteById[$0.id] }
        let localPaletteIds = Set(data.customPalettes.map(\.id))
        mergedPalettes.append(contentsOf: remote.customPalettes.filter { !localPaletteIds.contains($0.id) })
        data.customPalettes = mergedPalettes
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
