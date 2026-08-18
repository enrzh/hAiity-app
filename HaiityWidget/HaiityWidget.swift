import WidgetKit
import SwiftUI
import AppIntents

/// Alle Widgets lesen dieselbe data.json aus dem App-Group-Container.
/// Die Oberflächen liegen in eigenen Dateien (auch im App-Target, damit sich
/// jede Größe ohne Widget-Prozess zeichnen und prüfen lässt); hier stehen nur
/// Bundle, Konfigurationen und Timelines.

// MARK: – Lesen

enum WidgetData {
    /// EIN Lesevorgang für Habits UND Paletten — zwei getrennte Lesungen
    /// könnten einen Schreibvorgang dazwischen erwischen und ein Raster in
    /// der alten Farbe zeichnen.
    static func entry(selected: UUID? = nil,
                      source: GraphWidgetSource = .habit,
                      palette: PaletteRef? = nil,
                      date: Date = .now) -> HaiityEntry {
        let data = HabitStore.read(SharedStorage.dataURL())
        return HaiityEntry(date: date,
                           habits: data?.habits.filter { $0.archivedAt == nil && $0.isTrackedHabit } ?? [],
                           palettes: data.map { PaletteBook(global: $0.palette, customs: $0.customPalettes) }
                               ?? PaletteBook(),
                           selected: source == .habit ? selected : nil,
                           graphSource: source,
                           selectedPalette: palette,
                           githubSnapshot: source == .github
                               ? GitHubContributionSnapshot.loadShared()
                               : nil)
    }

    /// Eine Timeline mit genau einem Eintrag, gültig bis Mitternacht — der
    /// „heute"-Rahmen wandert, und „Frei bis Mo" ist am Montag falsch.
    static func timeline(selected: UUID? = nil,
                         source: GraphWidgetSource = .habit,
                         palette: PaletteRef? = nil) -> Timeline<HaiityEntry> {
        Timeline(entries: [entry(selected: selected, source: source, palette: palette)],
                 policy: .after(WidgetLogic.nextMidnight()))
    }

    static func demoGitHubEntry() -> HaiityEntry {
        let today = DayKey.today()
        var days: [GitHubContributionDay] = []
        for offset in 0..<371 {
            guard let date = DayKey.shifted(today, by: -offset) else { continue }
            let level = offset.isMultiple(of: 7) ? 0 : (offset % 4) + 1
            days.append(GitHubContributionDay(date: date,
                                              count: level * 2,
                                              level: level))
        }
        return HaiityEntry(date: .now,
                           habits: [],
                           graphSource: .github,
                           githubSnapshot: GitHubContributionSnapshot(username: "enrzh",
                                                                       days: days,
                                                                       fetchedAt: .now))
    }
}

// MARK: – Timelines

/// Für die Widgets MIT Habit-Auswahl.
struct HaiityHabitProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HaiityEntry { .demo }

    func snapshot(for configuration: SelectHabitIntent, in context: Context) async -> HaiityEntry {
        // In der Galerie steht noch keine echte Auswahl — dort lieber
        // Demodaten als ein leeres Rechteck.
        context.isPreview ? .demo : WidgetData.entry(selected: configuration.habit?.id)
    }

    func timeline(for configuration: SelectHabitIntent, in context: Context) async -> Timeline<HaiityEntry> {
        WidgetData.timeline(selected: configuration.habit?.id)
    }
}

/// Für das reine Habit-Graph-Widget.
struct GraphWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HaiityEntry { .demo }

    func snapshot(for configuration: SelectGraphIntent, in context: Context) async -> HaiityEntry {
        let source = configuration.resolvedSource
        if context.isPreview, source == .github {
            return WidgetData.demoGitHubEntry()
        }
        return WidgetData.entry(selected: configuration.habit?.id,
                                source: source,
                                palette: configuration.palette?.paletteRef)
    }

    func timeline(for configuration: SelectGraphIntent, in context: Context) async -> Timeline<HaiityEntry> {
        let source = configuration.resolvedSource
        return WidgetData.timeline(selected: configuration.habit?.id,
                                   source: source,
                                   palette: configuration.palette?.paletteRef)
    }
}

struct GitHubWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HaiityEntry { WidgetData.demoGitHubEntry() }

    func snapshot(for configuration: SelectGitHubWidgetIntent,
                  in context: Context) async -> HaiityEntry {
        if context.isPreview { return WidgetData.demoGitHubEntry() }
        return WidgetData.entry(source: .github,
                                palette: configuration.palette?.paletteRef)
    }

    func timeline(for configuration: SelectGitHubWidgetIntent,
                  in context: Context) async -> Timeline<HaiityEntry> {
        WidgetData.timeline(source: .github,
                            palette: configuration.palette?.paletteRef)
    }
}

/// Für die Widgets ÜBER ALLE Habits (Übersicht, Tagesring) — dort gibt es
/// nichts auszuwählen.
struct HaiityRosterProvider: TimelineProvider {
    func placeholder(in context: Context) -> HaiityEntry { .demo }

    func getSnapshot(in context: Context, completion: @escaping (HaiityEntry) -> Void) {
        completion(context.isPreview ? .demo : WidgetData.entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HaiityEntry>) -> Void) {
        completion(WidgetData.timeline())
    }
}

// MARK: – Bundle

@main
struct HaiityWidgetBundle: WidgetBundle {
    var body: some Widget {
        HaiityWidget()
        HaiityGraphWidget()
        HaiityGitHubWidget()
        HaiityRosterWidget()
        HaiityRingWidget()
        HaiityStreakWidget()
        // Die Live-Aktivität einer laufenden Session (Sperrbildschirm +
        // Dynamic Island).
        HabitSessionLiveActivity()
        // Die tägliche Motivation bleibt nach ihrer Uhrzeit bis Mitternacht
        // sichtbar und kann direkt aus der Aktivität ausgeblendet werden.
        MotivationLiveActivity()
        // Steuerungselemente gibt es erst ab iOS 18; das Ziel ist 17. Der
        // `#available`-Zweig ist der einzige unterstützte Weg, ein
        // ControlWidget bedingt in ein Bundle zu hängen — ohne ihn wäre das
        // ganze Bundle iOS 18.
        if #available(iOS 18.0, *) {
            HaiityCheckControl()
        }
    }
}

// MARK: – Homescreen

/// Das ursprüngliche Widget: Name, Serie, heutiger Zustand, Raster und
/// Abhak-Knopf — jetzt mit auswählbarem Habit.
struct HaiityWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HaiityWidget",
                               intent: SelectHabitIntent.self,
                               provider: HaiityHabitProvider()) { entry in
            HaiityWidgetView(entry: entry)
        }
        .configurationDisplayName("hAiity")
        .description(String(localized: "Ein Habit mit Serie, heutigem Stand und Abhak-Knopf."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// Nur der Graph — keine Schrift, kein Knopf.
struct HaiityGraphWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HaiityGraphWidget",
                               intent: SelectGraphIntent.self,
                               provider: GraphWidgetProvider()) { entry in
            GraphWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Habit-Graph"))
        .description(String(localized: "Nur das Habit-Raster — sieben Zeilen, randlos."))
        // Kein systemLarge: Die Zellgröße kommt aus der Höhe, und auf der
        // fast quadratischen großen Fläche ergibt das ein 7x7-Brett aus
        // 40-pt-Quadraten — weniger Historie als die mittlere Größe und
        // optisch ein Schachbrett statt eines Contribution-Graphen. Wer die
        // große Fläche will, nimmt Übersicht oder das Haupt-Widget.
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// Der offizielle GitHub-Beitragsgraph als eigenes Widget. Es hat bewusst
/// keine Habit-Auswahl; nur die Farbe ist konfigurierbar.
struct HaiityGitHubWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HaiityGitHubWidget",
                               intent: SelectGitHubWidgetIntent.self,
                               provider: GitHubWidgetProvider()) { entry in
            GraphWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "GitHub-Graph"))
        .description(String(localized: "Dein GitHub-Beitragsgraph."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// Mehrere Habits auf einmal.
struct HaiityRosterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HaiityRosterWidget", provider: HaiityRosterProvider()) { entry in
            RosterWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Übersicht"))
        .description(String(localized: "Mehrere Habits als Zeilen — was heute ansteht, auf einen Blick."))
        .supportedFamilies([.systemLarge])
    }
}

// MARK: – Sperrbildschirm

/// Der Tagesring über ALLE Habits.
struct HaiityRingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HaiityRingWidget", provider: HaiityRosterProvider()) { entry in
            RingAccessoryView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Tagesring"))
        .description(String(localized: "Wie viel von heute schon steht."))
        .supportedFamilies([.accessoryCircular])
    }
}

/// EIN Habit auf dem Sperrbildschirm — als Rechteck mit Raster oder als
/// Zeile neben der Uhr.
struct HaiityStreakWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HaiityStreakWidget",
                               intent: SelectHabitIntent.self,
                               provider: HaiityHabitProvider()) { entry in
            StreakAccessoryContainer(entry: entry)
        }
        .configurationDisplayName(String(localized: "Habit & Serie"))
        .description(String(localized: "Ein Habit auf dem Sperrbildschirm."))
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

/// Wählt die richtige Oberfläche für die Familie. Eigener kleiner Typ, damit
/// beide Sperrbildschirm-Formen unter EINER Konfiguration liegen (so bietet
/// die Galerie sie als ein Widget an, das man in beiden Formen ablegen kann).
struct StreakAccessoryContainer: View {
    @Environment(\.widgetFamily) private var family
    let entry: HaiityEntry

    var body: some View {
        if family == .accessoryInline {
            InlineAccessoryView(entry: entry)
        } else {
            StreakAccessoryView(entry: entry)
        }
    }
}

// MARK: – Kontrollzentrum (iOS 18+)

/// Was das Steuerungselement zeichnen muss. Bewusst ein flacher Wert und
/// nicht der Habit: der Provider läuft außerhalb jedes Zeichenkontexts.
@available(iOS 18.0, *)
struct HabitControlValue {
    var id: UUID?
    var name: String
    var emoji: String
    var done: Bool

    static let placeholder = HabitControlValue(id: nil,
                                               name: String(localized: "Habit"),
                                               emoji: "",
                                               done: false)
}

@available(iOS 18.0, *)
struct HabitControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: SelectHabitControlIntent) -> HabitControlValue {
        value(for: configuration.habit?.id) ?? .placeholder
    }

    func currentValue(configuration: SelectHabitControlIntent) async throws -> HabitControlValue {
        value(for: configuration.habit?.id) ?? .placeholder
    }

    /// Immer frisch von der Platte — der Store dieses Prozesses ist nicht der
    /// Store des App-Prozesses.
    private func value(for selected: UUID?) -> HabitControlValue? {
        let habits = HabitStore.read(SharedStorage.dataURL())?.habits ?? []
        guard let habit = WidgetLogic.resolve(habits: habits, selected: selected) else { return nil }
        return HabitControlValue(id: habit.id,
                                 name: habit.name,
                                 emoji: habit.emoji,
                                 done: GoalEngine.dayCounts(habit: habit, day: DayKey.today()))
    }
}

/// Abhaken aus dem Kontrollzentrum.
///
/// Bewusst ein KNOPF und kein Schalter: `ControlWidgetToggle` verlangt einen
/// `SetValueIntent<Bool>` und verspricht damit, dass man ihn auch wieder
/// ausschalten kann. Genau das darf hier nicht passieren — der Check-in ist
/// idempotent und hakt nie ab (siehe `CheckOffLogic`); ein Schalter, der
/// zurückspringt, wäre eine Lüge. Der Knopf feuert denselben
/// `CheckOffHabitIntent` wie der Widget-Knopf und Siri.
@available(iOS 18.0, *)
struct HaiityCheckControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "HaiityCheckControl",
                                      provider: HabitControlProvider()) { value in
            ControlWidgetButton(action: CheckOffHabitIntent(
                entity: HabitEntity(id: value.id ?? UUID(),
                                    name: value.name,
                                    emoji: value.emoji))) {
                HabitControlLabel(name: value.name, emoji: value.emoji, done: value.done)
            }
        }
        .displayName("hAiity")
        .description("Einen Habit für heute abhaken.")
        .promptsForUserConfiguration()
    }
}
