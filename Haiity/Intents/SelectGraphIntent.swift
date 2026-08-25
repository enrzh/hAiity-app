import AppIntents
import WidgetKit

/// Graph configuration only exposes tracked habits. The main hAiity widget
/// uses `HabitEntity` and may also be configured with a reminder.
struct GraphHabitEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Habit")
    static var defaultQuery = GraphHabitEntityQuery()

    var id: UUID
    var name: String
    var emoji: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(emoji.isEmpty ? name : "\(emoji) \(name)")")
    }

    init(habit: Habit) {
        id = habit.id
        name = habit.name
        emoji = habit.emoji
    }
}

struct GraphHabitEntityQuery: EntityQuery {
    private func trackedHabits() -> [Habit] {
        guard let data = HabitStore.read(SharedStorage.dataURL()) else { return [] }
        return HabitVisibility.visibleActiveHabits(
            data.habits,
            unlocked: HabitVisibility.sharedEntitlementIsUnlocked)
            .filter(\.isTrackedHabit)
    }

    func entities(for identifiers: [GraphHabitEntity.ID]) async throws -> [GraphHabitEntity] {
        trackedHabits().filter { identifiers.contains($0.id) }.map(GraphHabitEntity.init)
    }

    func suggestedEntities() async throws -> [GraphHabitEntity] {
        trackedHabits().map(GraphHabitEntity.init)
    }

    func defaultResult() async -> GraphHabitEntity? {
        trackedHabits().first.map(GraphHabitEntity.init)
    }
}

/// Die Einstellung des reinen Graph-Widgets: ein Habit oder der offizielle
/// GitHub-Beitragskalender. Andere Widgets behalten ihre Habit-Auswahl.
struct SelectGraphIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Graph auswählen"
    static var description = IntentDescription("Wähle einen Habit oder GitHub für das Graph-Widget.")

    static var isDiscoverable: Bool { false }

    @Parameter(title: "Quelle")
    var source: GraphWidgetSource?

    @Parameter(title: "Farbe")
    var palette: GraphPaletteEntity?

    @Parameter(title: "Habit")
    var habit: GraphHabitEntity?

    init() {
        source = .habit
        palette = nil
        habit = nil
    }

    init(source: GraphWidgetSource,
         habit: GraphHabitEntity? = nil,
         palette: GraphPaletteEntity? = nil) {
        self.source = source
        self.palette = palette
        self.habit = habit
    }

    var resolvedSource: GraphWidgetSource { source ?? .habit }
}
