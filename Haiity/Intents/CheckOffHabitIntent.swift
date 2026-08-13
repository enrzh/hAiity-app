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
        self.init(id: habit.id, name: habit.name, emoji: habit.emoji)
    }

    /// Aus rohen Feldern — das Steuerungselement im Kontrollzentrum hält nur
    /// diese drei und hat den Habit nicht zur Hand. Ein eigener Init ist
    /// nötig, weil der bezeichnete oben den memberwise-Init verdeckt.
    init(id: UUID, name: String, emoji: String) {
        self.id = id
        self.name = name
        self.emoji = emoji
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

    /// Für den Widget-Knopf und das Steuerungselement, die nur die Kennung
    /// haben. Eine unbekannte Kennung ist KEIN Fehler — `CheckOffLogic` macht
    /// daraus einen No-op, damit ein Knopf auf einem gelöschten Habit nichts
    /// kaputt macht und nichts erfindet.
    init(entity: HabitEntity) {
        self.habit = entity
    }

    func perform() async throws -> some IntentResult {
        // Immer frisch von der Platte laden — der Store dieses Prozesses
        // ist nicht der Store des App-Prozesses. persist() (in apply)
        // schreibt synchron und stößt den Widget-Reload bereits an
        // (WidgetCenter.reloadAllTimelines unter canImport(WidgetKit)).
        let store = HabitStore(url: SharedStorage.dataURL())
        CheckOffLogic.apply(to: store, habitId: habit.id)
        // Der App-Prozess bekommt von diesem Check-in nichts mit — die
        // heutige Erinnerung und die Tagesmeldung hier selbst nachziehen.
        await Reminders.reconcileAfterExternalCheckIn(store: store, habitID: habit.id)
        return .result()
    }
}

/// Pure, testbare Abhak-Semantik — getrennt vom Intent, damit Unit-Tests
/// sie ohne AppIntents-Laufzeit abdecken.
enum CheckOffLogic {
    /// Checkbox-Habits: nur AN-haken, wenn heute noch offen — idempotent,
    /// ein Widget-Button darf nie ENT-haken. Mengen-Habits: +1, auch über
    /// das Ziel hinaus. Ja/Nein-Habits: JA setzen — auch über ein
    /// bestehendes Nein hinweg (der Knopf heißt „abhaken", und wer ihn
    /// drückt, meint Ja); ein schon bejahter Tag bleibt unberührt, damit
    /// auch hier nichts zurückgenommen wird. Archivierte oder unbekannte
    /// Habits: No-op. Rückgabe: wurde etwas geschrieben?
    @discardableResult
    static func apply(to store: HabitStore, habitId: UUID, day: String = DayKey.today()) -> Bool {
        guard let habit = store.habits.first(where: { $0.id == habitId }),
              habit.archivedAt == nil else { return false }
        switch habit.kind {
        case .quantity:
            store.increment(habitId, day: day)
            return true
        case .yesNo:
            guard !habit.isAffirmed(day) else { return false }
            // NICHT `answer`: das würde ein bestehendes Ja umschalten und
            // damit doch wieder ent-haken.
            store.setValue(habitId, day: day, value: Habit.Answer.yes)
            return true
        case .checkbox:
            guard !habit.isDone(day) else { return false }
            store.toggle(habitId, day: day)
            return true
        }
    }
}
