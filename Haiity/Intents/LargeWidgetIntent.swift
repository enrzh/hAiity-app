import AppIntents

struct LargeWidgetListIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Liste"
    static var description = IntentDescription("Vier Habits oder Erinnerungen auswählen; leer bedeutet Automatisch.")
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Element 1") var slot1: HabitEntity?
    @Parameter(title: "Element 2") var slot2: HabitEntity?
    @Parameter(title: "Element 3") var slot3: HabitEntity?
    @Parameter(title: "Element 4") var slot4: HabitEntity?

    init() {}
}

struct LargeWidgetGridIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Raster"
    static var description = IntentDescription("Sechs Habits oder Erinnerungen auswählen; leer bedeutet Automatisch.")
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Element 1") var slot1: HabitEntity?
    @Parameter(title: "Element 2") var slot2: HabitEntity?
    @Parameter(title: "Element 3") var slot3: HabitEntity?
    @Parameter(title: "Element 4") var slot4: HabitEntity?
    @Parameter(title: "Element 5") var slot5: HabitEntity?
    @Parameter(title: "Element 6") var slot6: HabitEntity?

    init() {}
}

struct LargeWidgetFocusIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Fokus"
    static var description = IntentDescription("Einen Fokus und drei Warteschlangen-Elemente auswählen; leer bedeutet Automatisch.")
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Fokus") var featured: HabitEntity?
    @Parameter(title: "Warteschlange 1") var queue1: HabitEntity?
    @Parameter(title: "Warteschlange 2") var queue2: HabitEntity?
    @Parameter(title: "Warteschlange 3") var queue3: HabitEntity?

    init() {}
}
