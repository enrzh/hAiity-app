import AppIntents
import Foundation

/// App Intent zum Abhaken eines Habits. Läuft in ZWEI Prozessen: als
/// interaktiver Widget-Button im Widget-Extension-Prozess und über
/// Siri/Shortcuts im App-Prozess — die Datei ist deshalb in BEIDE Targets
/// kompiliert. Beide Seiten schreiben über `HabitStore` in dieselbe
/// data.json (App-Group-Container via `SharedStorage.dataURL()`), sodass
/// jeder Check-in überall ankommt.
struct HabitEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Habit")
    static var defaultQuery = HabitEntityQuery()

    var id: UUID
    var name: String
    var emoji: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(emoji.isEmpty ? name : "\(emoji) \(name)")")
    }

    init(habit: Habit) {
        self.id = habit.id
        self.name = habit.name
        self.emoji = habit.emoji
    }
}

/// Query über die AKTIVEN Habits des geteilten Stores — archivierte
/// tauchen weder in Siri-Vorschlägen noch in der Shortcuts-Auswahl auf.
struct HabitEntityQuery: EntityQuery {
    private func activeHabits() -> [Habit] {
        HabitStore.read(SharedStorage.dataURL())?.habits.filter { $0.archivedAt == nil } ?? []
    }

    func entities(for identifiers: [HabitEntity.ID]) async throws -> [HabitEntity] {
        activeHabits().filter { identifiers.contains($0.id) }.map(HabitEntity.init)
    }

    func suggestedEntities() async throws -> [HabitEntity] {
        activeHabits().map(HabitEntity.init)
    }

    func defaultResult() async -> HabitEntity? {
        activeHabits().first.map(HabitEntity.init)
    }
}

struct CheckOffHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Habit abhaken"
    static var description = IntentDescription("Hakt einen Habit für heute ab bzw. zählt ihn eins hoch.")

    @Parameter(title: "Habit")
    var habit: HabitEntity

    init() {}

    init(habit: Habit) {
        self.habit = HabitEntity(habit: habit)
    }

    func perform() async throws -> some IntentResult {
        // Immer frisch von der Platte laden — der Store dieses Prozesses
        // ist nicht der Store des App-Prozesses. persist() (in apply)
        // schreibt synchron und stößt den Widget-Reload bereits an
        // (WidgetCenter.reloadAllTimelines unter canImport(WidgetKit)).
        let store = HabitStore(url: SharedStorage.dataURL())
        CheckOffLogic.apply(to: store, habitId: habit.id)
        return .result()
    }
}

/// Pure, testbare Abhak-Semantik — getrennt vom Intent, damit Unit-Tests
/// sie ohne AppIntents-Laufzeit abdecken.
enum CheckOffLogic {
    /// Checkbox-Habits: nur AN-haken, wenn heute noch offen — idempotent,
    /// ein Widget-Button darf nie ENT-haken. Mengen-Habits: +1, auch über
    /// das Ziel hinaus. Archivierte oder unbekannte Habits: No-op.
    /// Rückgabe: wurde etwas geschrieben?
    @discardableResult
    static func apply(to store: HabitStore, habitId: UUID, day: String = DayKey.today()) -> Bool {
        guard let habit = store.habits.first(where: { $0.id == habitId }),
              habit.archivedAt == nil else { return false }
        if habit.goal.target != nil {
            store.increment(habitId, day: day)
            return true
        }
        guard !habit.isDone(day) else { return false }
        store.toggle(habitId, day: day)
        return true
    }
}
