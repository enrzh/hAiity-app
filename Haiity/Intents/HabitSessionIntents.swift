import AppIntents
import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Die beiden Knöpfe AUF der Live-Aktivität. Als `LiveActivityIntent`
/// laufen ihre `perform()` im APP-Prozess (ohne die App zu öffnen) — sie
/// dürfen also den Store schreiben und die Aktivität beenden. Die Structs
/// selbst sind zusätzlich in die Widget-Extension kompiliert, weil die
/// Button-UI dort den TYP braucht.
///
/// Beide Intents tragen keine Parameter: es gibt höchstens EINE laufende
/// Session (siehe `HabitSessionStorage`), und genau die ist gemeint.
@available(iOS 17.0, *)
struct FinishHabitSessionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Session beenden"
    static var description = IntentDescription("Beendet die laufende Habit-Session und hakt den Tag ab.")
    /// Läuft still im Hintergrund — der Sinn eines Knopfs auf der
    /// Sperrbildschirm-Aktivität ist, die App NICHT öffnen zu müssen.
    static var openAppWhenRun = false

    init() {}

    func perform() async throws -> some IntentResult {
        if let session = HabitSessionStorage.load() {
            // Frisch von der Platte, wie jeder Intent: der Store dieses
            // Prozesses ist nicht zwingend der Store der laufenden UI.
            let store = HabitStore(url: SharedStorage.dataURL())
            HabitSessionCompletion.finish(store: store, session: session)
            HabitSessionStorage.clear()
        }
        await HabitSessionActivityControl.endAll()
        return .result()
    }
}

@available(iOS 17.0, *)
struct CancelHabitSessionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Session abbrechen"
    static var description = IntentDescription("Bricht die laufende Habit-Session ab, ohne etwas abzuhaken.")
    static var openAppWhenRun = false

    init() {}

    func perform() async throws -> some IntentResult {
        HabitSessionStorage.clear()
        await HabitSessionActivityControl.endAll()
        return .result()
    }
}

/// Das Beenden ALLER Session-Aktivitäten, an einer Stelle: die Intents, der
/// Start einer neuen Session und die Stale-Aufräumung beim App-Start rufen
/// alle dasselbe. Mehr als eine sollte es nie geben — beendet wird trotzdem
/// die Liste, damit ein Zähl-Fehler sich nicht als unsterbliche Aktivität
/// auf dem Sperrbildschirm festsetzt.
enum HabitSessionActivityControl {
    static func endAll() async {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            for activity in Activity<HabitActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
    }
}
