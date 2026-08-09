import Foundation
import Observation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Persistenz-Container: JSON im App-Group-Container, damit das Widget
/// dieselbe Datei liest. Fallback auf Application Support (Unit-Tests,
/// fehlendes Entitlement) — niemals stiller Datenverlust.
struct HabitData: Codable {
    /// Geschrieben wird immer die aktuelle Version; gelesen werden 1 und 2.
    static let currentVersion = 2

    var version: Int
    var updatedAt: TimeInterval
    var summaryMinutes: Int?      // Abend-Zusammenfassung; nil = aus
    var habits: [Habit]
    /// Hell/Dunkel/System. Liegt HIER und nicht in UserDefaults, damit die
    /// Einstellung denselben Weg nimmt wie alles andere (Export, Import,
    /// GitHub-Sync) — ein neues Gerät sieht sofort dieselbe App.
    var appearance: AppearanceSetting
    /// Globale Rasterfarbe.
    var palette: GraphPalette
    /// Soll das App-Icon der Palette folgen? Standard an; der Icon-Wechsel
    /// zeigt einen System-Dialog, deshalb ist er abschaltbar.
    var matchAppIcon: Bool
    /// Wischgeste von links nach rechts (Standard: erledigt).
    var leadingSwipe: SwipeAction
    /// Wischgeste von rechts nach links (Standard: archivieren).
    var trailingSwipe: SwipeAction

    /// Die neuen Felder sind bewusst KEIN Versionssprung: sie sind rein
    /// additiv und tolerant dekodiert, ein v2-Build von gestern liest die
    /// Datei unverändert weiter (ein Sprung auf 3 würde ihn aussperren).
    init(version: Int,
         updatedAt: TimeInterval,
         summaryMinutes: Int?,
         habits: [Habit],
         appearance: AppearanceSetting = .default,
         palette: GraphPalette = .default,
         matchAppIcon: Bool = true,
         leadingSwipe: SwipeAction = .defaultLeading,
         trailingSwipe: SwipeAction = .defaultTrailing) {
        self.version = version
        self.updatedAt = updatedAt
        self.summaryMinutes = summaryMinutes
        self.habits = habits
        self.appearance = appearance
        self.palette = palette
        self.matchAppIcon = matchAppIcon
        self.leadingSwipe = leadingSwipe
        self.trailingSwipe = trailingSwipe
    }

    static let empty = HabitData(version: currentVersion, updatedAt: 0, summaryMinutes: nil, habits: [])
}

extension HabitData {
    private enum CodingKeys: String, CodingKey {
        case version, updatedAt, summaryMinutes, habits, appearance, palette, matchAppIcon
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
        summaryMinutes = try c.decodeIfPresent(Int.self, forKey: .summaryMinutes)
        habits = try c.decodeIfPresent([Habit].self, forKey: .habits) ?? []
        // Fehlt / unbekannt -> Standard. Eine Datei aus einer neueren
        // Version mit "palette":"neon" verliert nur die Farbe, nicht die
        // Check-ins.
        appearance = (try c.decodeIfPresent(String.self, forKey: .appearance))
            .flatMap(AppearanceSetting.init(rawValue:)) ?? .default
        palette = (try c.decodeIfPresent(String.self, forKey: .palette))
            .flatMap(GraphPalette.init(rawValue:)) ?? .default
        matchAppIcon = try c.decodeIfPresent(Bool.self, forKey: .matchAppIcon) ?? true
        // Gleiche Regel wie bei Palette und Erscheinungsbild: unbekannt oder
        // fehlend -> Standard, nie ein Fehler.
        leadingSwipe = SwipeAction.tolerant(
            try c.decodeIfPresent(String.self, forKey: .leadingSwipe), fallback: .defaultLeading)
        trailingSwipe = SwipeAction.tolerant(
            try c.decodeIfPresent(String.self, forKey: .trailingSwipe), fallback: .defaultTrailing)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(summaryMinutes, forKey: .summaryMinutes)
        try c.encode(habits, forKey: .habits)
        // Standards bleiben implizit — eine unveränderte Installation
        // schreibt exakt dieselbe Datei wie vor dem Theming.
        if appearance != .default { try c.encode(appearance.rawValue, forKey: .appearance) }
        if palette != .default { try c.encode(palette.rawValue, forKey: .palette) }
        if !matchAppIcon { try c.encode(false, forKey: .matchAppIcon) }
        if leadingSwipe != .defaultLeading { try c.encode(leadingSwipe.rawValue, forKey: .leadingSwipe) }
        if trailingSwipe != .defaultTrailing { try c.encode(trailingSwipe.rawValue, forKey: .trailingSwipe) }
    }
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
    /// mtime der Datei beim letzten eigenen Lesen/Schreiben — erkennt
    /// externe Schreiber (Widget-Intent im Extension-Prozess).
    @ObservationIgnored private var loadedMtime: Date?

    init(url: URL = SharedStorage.dataURL()) {
        self.url = url
        self.data = Self.read(url) ?? .empty
        self.loadedMtime = Self.mtime(url)
    }

    /// ALLE Habits, auch archivierte (Export, Sync, Archiv-Ansicht).
    var habits: [Habit] { data.habits }

    /// Nicht archivierte Habits — Hauptliste, Summary, Widget.
    var activeHabits: [Habit] { data.habits.filter { $0.archivedAt == nil } }

    var summaryMinutes: Int? {
        get { data.summaryMinutes }
        set { data.summaryMinutes = newValue; persist() }
    }

    var appearance: AppearanceSetting {
        get { data.appearance }
        set { data.appearance = newValue; persist() }
    }

    var palette: GraphPalette {
        get { data.palette }
        set { data.palette = newValue; persist() }
    }

    var matchAppIcon: Bool {
        get { data.matchAppIcon }
        set { data.matchAppIcon = newValue; persist() }
    }

    var leadingSwipe: SwipeAction {
        get { data.leadingSwipe }
        set { data.leadingSwipe = newValue; persist() }
    }

    var trailingSwipe: SwipeAction {
        get { data.trailingSwipe }
        set { data.trailingSwipe = newValue; persist() }
    }

    static func read(_ url: URL) -> HabitData? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HabitData.self, from: raw)
    }

    private static func mtime(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Liest die Datei neu ein, wenn sie sich EXTERN geändert hat (der
    /// Widget-Intent schreibt aus dem Extension-Prozess). Merge-frei und
    /// sicher: `persist()` schreibt synchron, der In-Memory-Stand liegt
    /// also immer schon auf der Platte — ein purer Re-Read verliert nichts.
    /// Unveränderte mtime -> No-op (kein Decode, kein onChange).
    func reloadFromDisk() {
        let m = Self.mtime(url)
        guard m != loadedMtime, let fresh = Self.read(url) else { return }
        loadedMtime = m
        data = fresh
        onChange?()
    }

    func persist() {
        data.version = HabitData.currentVersion
        data.updatedAt = Date().timeIntervalSince1970
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let raw = try? enc.encode(data) {
            try? raw.write(to: url, options: .atomic)
        }
        loadedMtime = Self.mtime(url)
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

    /// Checkbox-Habits: 0 <-> 1.
    func toggle(_ id: UUID, day: String = DayKey.today()) {
        guard let i = data.habits.firstIndex(where: { $0.id == id }) else { return }
        if data.habits[i].log[day] != nil { data.habits[i].log[day] = nil }
        else { data.habits[i].log[day] = 1 }
        persist()
    }

    /// Mengen-Habits: +1 auf den Tageszähler (1, 2, 3 …) — kein Wrap.
    /// Löschen läuft explizit über `clear` (Langdruck/Menü in der UI).
    func increment(_ id: UUID, day: String = DayKey.today()) {
        guard let i = data.habits.firstIndex(where: { $0.id == id }) else { return }
        data.habits[i].log[day] = (data.habits[i].log[day] ?? 0) + 1
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
        guard data.habits[i].log[day] != normalized else { return }
        data.habits[i].log[day] = normalized
        persist()
    }

    /// Entfernt den Tageseintrag komplett.
    func clear(_ id: UUID, day: String = DayKey.today()) {
        guard let i = data.habits.firstIndex(where: { $0.id == id }),
              data.habits[i].log[day] != nil else { return }
        data.habits[i].log[day] = nil
        persist()
    }

    /// Archivieren erhält die Historie; das Habit verschwindet nur aus
    /// Liste, Summary und Widget.
    func archive(_ id: UUID, day: String = DayKey.today()) {
        guard let i = data.habits.firstIndex(where: { $0.id == id }),
              data.habits[i].archivedAt == nil else { return }
        data.habits[i].archivedAt = day
        persist()
    }

    func unarchive(_ id: UUID) {
        guard let i = data.habits.firstIndex(where: { $0.id == id }),
              data.habits[i].archivedAt != nil else { return }
        data.habits[i].archivedAt = nil
        persist()
    }

    /// Verschiebt Habits per Drag — die Offsets beziehen sich auf
    /// `activeHabits` (was die Liste zeigt); archivierte Habits behalten
    /// ihre Positionen im Gesamtarray.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var active = activeHabits
        active.move(fromOffsets: source, toOffset: destination)
        var iterator = active.makeIterator()
        data.habits = data.habits.map { $0.archivedAt == nil ? (iterator.next() ?? $0) : $0 }
        persist()
    }

    /// Offene AKTIVE Habits für heute (für die Abend-Zusammenfassung).
    func openToday(_ today: String = DayKey.today()) -> [Habit] {
        activeHabits.filter { !$0.isDone(today) }
    }

    // MARK: – Merge (Union: ein Check-in irgendwo zählt)

    /// Vereinigt Remote-Daten mit lokalen: Habits per id, Logs als Union
    /// mit MAX pro Tag (ein höherer Zähler irgendwo gewinnt) — nie wird
    /// ein Tag gelöscht. Bei Metadaten-Konflikt (Name/Emoji/Erinnerung/
    /// Ziel/Archiv) gewinnt der neuere `updatedAt`-Stand.
    /// Exakter Gleichstand: LOKAL gewinnt — nie beidseitig löschen.
    func merge(remote: HabitData) {
        var byId = Dictionary(uniqueKeysWithValues: data.habits.map { ($0.id, $0) })
        let remoteNewer = remote.updatedAt > data.updatedAt
        for rh in remote.habits {
            if var lh = byId[rh.id] {
                for (k, v) in rh.log {
                    let merged = max(lh.log[k] ?? 0, v)
                    if merged >= 1 { lh.log[k] = merged } // 0-Werte nie materialisieren
                }
                if remoteNewer {
                    lh.name = rh.name
                    lh.emoji = rh.emoji
                    lh.reminderMinutes = rh.reminderMinutes
                    lh.goal = rh.goal
                    lh.archivedAt = rh.archivedAt
                    lh.palette = rh.palette
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
        // Darstellung reist mit: das neuere Gerät gibt das Aussehen vor.
        // Anders als summaryMinutes gibt es hier kein "nil = nicht gesetzt",
        // der Standard IST ein gültiger Wert.
        if remoteNewer {
            data.appearance = remote.appearance
            data.palette = remote.palette
            data.matchAppIcon = remote.matchAppIcon
            data.leadingSwipe = remote.leadingSwipe
            data.trailingSwipe = remote.trailingSwipe
        }
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
