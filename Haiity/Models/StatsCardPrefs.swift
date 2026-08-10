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
/// Einschaltens (und damit die Reihenfolge über der Liste). Bewusst ein
/// reines Wertmodell OHNE Store-Anbindung: die Einstellung liegt in den
/// App-Group-UserDefaults, nicht in data.json — sie ist eine Geräte-Ansicht,
/// kein Habit-Datum, und soll weder Export noch iCloud-Merge anfassen.
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

/// Die beobachtbare Hülle: hält die Auswahl im Speicher und schreibt jede
/// Änderung sofort in die App-Group-Defaults. Bewusst NICHT im HabitStore —
/// der gehört den Habit-Daten, und diese Einstellung soll seinen
/// Persistenz-Weg (data.json, Widget-Reload, iCloud-Push) nicht auslösen.
@Observable
final class StatsCardStore {
    @ObservationIgnored private let defaults: UserDefaults

    var prefs: StatsCardPrefs {
        didSet { prefs.save(to: defaults) }
    }

    init(defaults: UserDefaults? = nil) {
        let resolved = defaults
            ?? UserDefaults(suiteName: SharedStorage.appGroup)
            ?? .standard
        self.defaults = resolved
        self.prefs = StatsCardPrefs.load(from: resolved)
    }
}
