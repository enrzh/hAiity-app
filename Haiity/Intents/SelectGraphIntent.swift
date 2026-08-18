import AppIntents
import WidgetKit

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
    var habit: HabitEntity?

    init() {
        source = .habit
        palette = nil
        habit = nil
    }

    init(source: GraphWidgetSource,
         habit: HabitEntity? = nil,
         palette: GraphPaletteEntity? = nil) {
        self.source = source
        self.palette = palette
        self.habit = habit
    }

    var resolvedSource: GraphWidgetSource { source ?? .habit }
}
