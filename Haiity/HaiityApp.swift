import SwiftUI

@main
struct HaiityApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            // Schema, Palette und Tint setzt ContentView selbst — dort liegt
            // der Store, der sie hält.
            ContentView()
                // Vergessene Sessions aufräumen: eine Live-Aktivität, die
                // seit über acht Stunden läuft, wird still beendet, ohne
                // den Tag abzuhaken (siehe HabitSessionManager).
                .onAppear {
                    HabitSessionManager.shared.recoverIfNeeded()
                    #if DEBUG
                    // Nur für die Simulator-Verifikation: eine Session per
                    // Startumgebung anstoßen (der lange Druck lässt sich
                    // maschinell nicht zuverlässig auslösen). Im Release
                    // existiert der Pfad nicht.
                    if let name = ProcessInfo.processInfo.environment["HAIITY_START_SESSION"] {
                        let habits = HabitStore.read(SharedStorage.dataURL())?.habits ?? []
                        if let habit = habits.first(where: { $0.name == name }) {
                            HabitSessionManager.shared.start(habit: habit)
                        }
                    }
                    #endif
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { HabitSessionManager.shared.recoverIfNeeded() }
        }
    }
}
