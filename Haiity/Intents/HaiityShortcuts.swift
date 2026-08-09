import AppIntents

/// Siri/Shortcuts-Einstieg ("hAiity Lesen erledigt"). Nur im App-Target:
/// App Shortcuts veröffentlicht das App-Bundle, nicht die Widget-Extension.
/// Jede Phrase MUSS `.applicationName` enthalten (System-Anforderung);
/// `\(\.$habit)` wird über die suggestedEntities der HabitEntityQuery zu
/// konkreten Habit-Namen ausmultipliziert.
struct HaiityShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckOffHabitIntent(),
            phrases: [
                "\(.applicationName) \(\.$habit) erledigt",
                "Hake \(\.$habit) in \(.applicationName) ab",
                "Markiere \(\.$habit) in \(.applicationName) als erledigt",
                "Check off \(\.$habit) in \(.applicationName)",
                "Mark \(\.$habit) as done in \(.applicationName)",
                "Log \(\.$habit) in \(.applicationName)"
            ],
            shortTitle: "Habit abhaken",
            systemImageName: "checkmark.square"
        )
    }
}
