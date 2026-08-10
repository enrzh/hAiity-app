import SwiftUI
import UserNotifications

@main
struct HaiityApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Ohne Delegat unterdrückt iOS jede geplante Mitteilung, solange die
        // App im Vordergrund ist — der häufigste Grund für „Benachrichtigungen
        // funktionieren nicht". Früh gesetzt, damit auch eine Meldung, die
        // GENAU beim Start eintrifft, präsentiert wird.
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

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
                    // Simulator-Verifikation: die Test-Mitteilung ohne
                    // UI-Fahrt anstoßen (löst auch den Berechtigungsdialog
                    // aus — genau wie der Knopf in „Mehr").
                    if ProcessInfo.processInfo.environment["HAIITY_TEST_NOTIFICATION"] != nil {
                        Task { _ = await Reminders.scheduleTest() }
                    }
                    // Verifikation der Weckrufe: die anstehenden Anfragen als
                    // Datei neben data.json — von außen gibt es keinen Weg,
                    // die Pending-Requests eines Simulators zu sehen.
                    if ProcessInfo.processInfo.environment["HAIITY_DUMP_PENDING"] != nil {
                        Task {
                            try? await Task.sleep(nanoseconds: 4_000_000_000)
                            let reqs = await UNUserNotificationCenter.current()
                                .pendingNotificationRequests()
                            let lines = reqs.map { r in
                                "\(r.identifier) | \(r.content.title) | \(r.content.body) | " +
                                ((r.trigger as? UNCalendarNotificationTrigger).map {
                                    "\($0.dateComponents) repeats=\($0.repeats)"
                                } ?? String(describing: r.trigger))
                            }.sorted().joined(separator: "\n")
                            let url = SharedStorage.dataURL().deletingLastPathComponent()
                                .appendingPathComponent("pending.txt")
                            try? lines.write(to: url, atomically: true, encoding: .utf8)
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
