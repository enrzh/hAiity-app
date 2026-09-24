import AppIntents

/// Siri/Shortcuts-Einstieg ("hAiity Lesen erledigt"). Nur im App-Target:
/// App Shortcuts veröffentlicht das App-Bundle, nicht die Widget-Extension.
/// Jede Phrase MUSS `.applicationName` enthalten (System-Anforderung);
/// `\(\.$habit)` wird über die suggestedEntities der HabitEntityQuery zu
/// konkreten Habit-Namen ausmultipliziert.
/// **Why the two create intents carry no `phrases` here.** An `AppShortcut`
/// phrase may only interpolate an `AppEntity`: Siri builds its training corpus
/// from the list of entities it can offer, and a free-text `String` parameter has
/// no such list. A phrase naming one does not become a phrase: the build emits an
/// "unresolved variable" warning for every utterance and the phrase never works.
/// It cost 187 warnings before this was understood. The create intents are still fully usable, because the
/// Shortcuts editor is where free text belongs: they appear there with a field
/// to type or dictate into. The phrases below all interpolate `HabitEntity`, so
/// they are the ones that resolve.
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
        AppShortcut(
            intent: DeclineHabitIntent(),
            phrases: [
                "\(.applicationName) \(\.$habit) heute nicht",
                "\(\.$habit) in \(.applicationName) nicht geschafft",
                "Notiere Nein für \(\.$habit) in \(.applicationName)",
                "Decline \(\.$habit) in \(.applicationName)",
                "Mark \(\.$habit) as missed in \(.applicationName)"
            ],
            shortTitle: "Nein notieren",
            systemImageName: "xmark.square"
        )
        AppShortcut(
            intent: HabitStatusIntent(),
            phrases: [
                "Wie steht es heute in \(.applicationName)",
                "\(.applicationName) Tagesstand",
                "Was ist in \(.applicationName) noch offen",
                "What's left in \(.applicationName) today",
                "How am I doing in \(.applicationName)"
            ],
            shortTitle: "Tagesstand",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: HabitStreakIntent(),
            phrases: [
                "Wie lang ist meine Serie für \(\.$habit) in \(.applicationName)",
                "\(.applicationName) Serie von \(\.$habit)",
                "What's my \(\.$habit) streak in \(.applicationName)",
                "Streak for \(\.$habit) in \(.applicationName)"
            ],
            shortTitle: "Serie abfragen",
            systemImageName: "flame"
        )
    }
}
