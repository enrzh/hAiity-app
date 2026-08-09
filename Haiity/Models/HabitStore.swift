import Foundation
import Observation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Persistenz-Container: JSON im App-Group-Container, damit das Widget
/// dieselbe Datei liest. Fallback auf Application Support (Unit-Tests,
/// fehlendes Entitlement) — niemals stiller Datenverlust.
struct HabitData: Codable {
    var version: Int
    var updatedAt: TimeInterval
    var summaryMinutes: Int?      // Abend-Zusammenfassung; nil = aus
    var habits: [Habit]

    static let empty = HabitData(version: 1, updatedAt: 0, summaryMinutes: nil, habits: [])
}

enum SharedStorage {
    static let appGroup = "group.com.aiity.haiity"

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

@Observable
final class HabitStore {
    private(set) var data: HabitData
    let url: URL
    var onChange: (() -> Void)?

    init(url: URL = SharedStorage.dataURL()) {
        self.url = url
        self.data = Self.read(url) ?? .empty
    }

    var habits: [Habit] { data.habits }
    var summaryMinutes: Int? {
        get { data.summaryMinutes }
        set { data.summaryMinutes = newValue; persist() }
    }

    static func read(_ url: URL) -> HabitData? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HabitData.self, from: raw)
    }

    func persist() {
        data.updatedAt = Date().timeIntervalSince1970
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let raw = try? enc.encode(data) {
            try? raw.write(to: url, options: .atomic)
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        onChange?()
    }

    // MARK: – Mutationen

    func add(_ habit: Habit) { data.habits.append(habit); persist() }

    func update(_ habit: Habit) {
        guard let i = data.habits.firstIndex(where: { $0.id == habit.id }) else { return }
        data.habits[i] = habit
        persist()
    }

    func remove(_ id: UUID) {
        data.habits.removeAll { $0.id == id }
        persist()
    }

    func toggle(_ id: UUID, day: String = DayKey.today()) {
        guard let i = data.habits.firstIndex(where: { $0.id == id }) else { return }
        if data.habits[i].log[day] != nil { data.habits[i].log[day] = nil }
        else { data.habits[i].log[day] = 1 }
        persist()
    }

    /// Offene Habits für heute (für die Abend-Zusammenfassung).
    func openToday(_ today: String = DayKey.today()) -> [Habit] {
        data.habits.filter { !$0.isDone(today) }
    }

    // MARK: – Merge (Union: ein Check-in irgendwo zählt)

    /// Vereinigt Remote-Daten mit lokalen: Habits per id, Logs als Key-Union.
    /// Bei Namens-/Emoji-Konflikt gewinnt der neuere `updatedAt`-Stand.
    /// Exakter Gleichstand: LOKAL gewinnt — nie beidseitig löschen.
    func merge(remote: HabitData) {
        var byId = Dictionary(uniqueKeysWithValues: data.habits.map { ($0.id, $0) })
        let remoteNewer = remote.updatedAt > data.updatedAt
        for rh in remote.habits {
            if var lh = byId[rh.id] {
                for k in rh.log.keys { lh.log[k] = 1 }
                if remoteNewer {
                    lh.name = rh.name
                    lh.emoji = rh.emoji
                    lh.reminderMinutes = rh.reminderMinutes
                }
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
        if remoteNewer, remote.summaryMinutes != nil { data.summaryMinutes = remote.summaryMinutes }
        persist()
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
