import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Die Live-Aktivität einer Habit-Session. In App UND Widget-Extension
/// kompiliert — beide Seiten müssen exakt denselben Typ sehen, sonst findet
/// die `ActivityConfiguration` die Aktivität der App nicht.
///
/// Fast alles ist ATTRIBUT (fest für die Lebensdauer): eine Session ändert
/// weder Habit noch Plan. Der `ContentState` trägt nur den Startzeitpunkt —
/// die verstrichene Zeit RECHNET das System aus `Text(timerInterval:)`
/// selbst, es gibt keine tickenden Updates (Pflicht, damit die Anzeige die
/// Suspendierung der App übersteht).
struct HabitActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
    }

    var habitID: UUID
    var name: String
    var emoji: String
    /// nil = limitless: nur hochzählen, kein Fortschritt.
    var plannedMinutes: Int?
    /// Akzentfarben der (Habit-)Palette als Hex, hell und dunkel — zum
    /// Startzeitpunkt aufgelöst, damit die Aktivität dieselbe Farbe trägt
    /// wie das Raster des Habits, ohne dass die Extension den Store lesen
    /// muss. Beide Varianten, weil die Aktivität dem Schema des
    /// Sperrbildschirms folgt, nicht dem der App.
    var accentFillLight: UInt32
    var accentFillDark: UInt32
    var accentTextLight: UInt32
    var accentTextDark: UInt32

    func accentFill(dark: Bool) -> UInt32 { dark ? accentFillDark : accentFillLight }
    func accentText(dark: Bool) -> UInt32 { dark ? accentTextDark : accentTextLight }
}
#endif
