import Foundation
import Observation
import SwiftUI

/// Die vier Statistik-Karten über der Habit-Liste. Roh-Wert ist der
/// Speicher-Schlüssel — Umbenennen wäre ein Datenformat-Bruch.
enum StatsCard: String, Codable, CaseIterable, Identifiable, Sendable {
    case yearPulse, streakFlame, todayRing, weekMomentum

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .yearPulse:    return String(localized: "Jahres-Puls")
        case .streakFlame:  return String(localized: "Streak-Flamme")
        case .todayRing:    return String(localized: "Heute-Ring")
        case .weekMomentum: return String(localized: "Wochen-Momentum")
        }
    }

    /// Ein Satz für die Mehr-Tafel: was die Karte zeigt.
    var detail: String {
        switch self {
        case .yearPulse:
            return String(localized: "Alle Habits als ein Raster, dazu der Heute-Ring.")
        case .streakFlame:
            return String(localized: "Deine Gesamt-Serie über alle Habits.")
        case .todayRing:
            return String(localized: "Was heute fällig ist — Segment für Segment.")
        case .weekMomentum:
            return String(localized: "Die Woche im Verlauf, verglichen mit der Vorwoche.")
        }
    }

    var symbol: String {
        switch self {
        case .yearPulse:    return "square.grid.3x3.middle.filled"
        case .streakFlame:  return "flame"
        case .todayRing:    return "circle.dashed"
        case .weekMomentum: return "chart.line.uptrend.xyaxis"
        }
    }
}

/// Welche Karten aktiv sind — höchstens zwei, Reihenfolge = Reihenfolge des
/// Einschaltens (und damit die Reihenfolge über der Liste).
struct StatsCardPrefs: Codable, Equatable {
    static let maxActive = 2
    static let storageKey = "statsCards"

    private(set) var active: [StatsCard]

    /// Standard: der Jahres-Puls, sonst nichts.
    init(active: [StatsCard] = [.yearPulse]) {
        var seen = Set<StatsCard>()
        self.active = Array(active.filter { seen.insert($0).inserted }.prefix(Self.maxActive))
    }

    var isFull: Bool { active.count >= Self.maxActive }

    func isActive(_ card: StatsCard) -> Bool { active.contains(card) }

    /// Darf der Schalter dieser Karte gerade bedient werden? Aktive dürfen
    /// immer aus; neue nur, solange noch Platz ist — das ist die
    /// „deaktivieren + Fußnote"-Mechanik der Mehr-Tafel.
    func canToggle(_ card: StatsCard) -> Bool { isActive(card) || !isFull }

    /// Ein-/Ausschalten mit Obergrenze. Einschalten über die Grenze hinweg
    /// ist ein No-op (die Oberfläche sperrt den Schalter ohnehin).
    mutating func set(_ card: StatsCard, active on: Bool) {
        if on {
            guard !isActive(card), !isFull else { return }
            active.append(card)
        } else {
            active.removeAll { $0 == card }
        }
    }

    // MARK: – Codable (tolerant)

    private enum CodingKeys: String, CodingKey { case active }

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
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(active.map(\.rawValue), forKey: .active)
    }

    // MARK: – Ablage

    /// Kein gespeicherter Wert -> Standard (Jahres-Puls). Kaputte Daten
    /// ebenso — lieber der Standard als ein Crash über einer Einstellung.
    static func load(from defaults: UserDefaults) -> StatsCardPrefs {
        guard let raw = defaults.data(forKey: storageKey),
              let prefs = try? JSONDecoder().decode(StatsCardPrefs.self, from: raw)
        else { return StatsCardPrefs() }
        return prefs
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

    init(updatedAt: TimeInterval = 0,
         statsCards: StatsCardPrefs = StatsCardPrefs(),
         compactMode: Bool = false) {
        self.updatedAt = updatedAt
        self.statsCards = statsCards
        self.compactMode = compactMode
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

    func update(_ body: (inout ViewPreferences) -> Void) {
        var next = preferences
        body(&next)
        guard next.statsCards != preferences.statsCards || next.compactMode != preferences.compactMode else { return }
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
