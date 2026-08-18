import AppIntents
import WidgetKit

/// Dedicated GitHub widget configuration. Keeping GitHub out of the generic
/// graph intent avoids an invalid combination of source, habit, and palette.
struct SelectGitHubWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "GitHub-Graph auswählen"
    static var description = IntentDescription("Wähle die Farbe des GitHub-Graphen.")

    static var isDiscoverable: Bool { false }

    @Parameter(title: "Farbe")
    var palette: GraphPaletteEntity?

    init() {
        palette = nil
    }

    init(palette: GraphPaletteEntity? = nil) {
        self.palette = palette
    }
}
