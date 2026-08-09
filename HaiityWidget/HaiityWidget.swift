import WidgetKit
import SwiftUI
import AppIntents

/// Widget liest dieselbe data.json aus dem App-Group-Container.
/// Die Oberfläche liegt in HaiityWidgetView.swift (auch im App-Target,
/// damit sich beide Größen prüfen lassen); hier stehen nur Bundle,
/// Konfiguration und Timeline.
struct HaiityProvider: TimelineProvider {
    func placeholder(in context: Context) -> HaiityEntry {
        HaiityEntry(date: .now, habits: [demoHabit()])
    }

    func getSnapshot(in context: Context, completion: @escaping (HaiityEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HaiityEntry>) -> Void) {
        let entry = entry()
        // Nächster Refresh: Mitternacht (der "heute"-Rahmen wandert).
        let cal = Calendar.current
        let midnight = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: .now) ?? .now)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }

    /// EIN Lesevorgang für Habits UND Paletten — zwei getrennte Lesungen
    /// könnten einen Schreibvorgang dazwischen erwischen und ein Raster in
    /// der alten Farbe zeichnen.
    private func entry() -> HaiityEntry {
        let data = HabitStore.read(SharedStorage.dataURL())
        return HaiityEntry(date: .now,
                           habits: data?.habits.filter { $0.archivedAt == nil } ?? [],
                           palettes: data.map { PaletteBook(global: $0.palette, customs: $0.customPalettes) }
                               ?? PaletteBook())
    }

    private func demoHabit() -> Habit {
        var h = Habit(name: "Lesen", emoji: "📖")
        for i in 0..<40 where i % 3 != 0 {
            if let k = DayKey.shifted(DayKey.today(), by: -i) { h.log[k] = 1 }
        }
        return h
    }
}

@main
struct HaiityWidgetBundle: WidgetBundle {
    var body: some Widget {
        HaiityWidget()
    }
}

struct HaiityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HaiityWidget", provider: HaiityProvider()) { entry in
            HaiityWidgetView(entry: entry)
        }
        .configurationDisplayName("hAiity")
        .description(String(localized: "Dein Habit-Graph auf dem Home-Bildschirm."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
