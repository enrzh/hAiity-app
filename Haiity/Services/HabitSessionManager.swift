import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Startet und räumt Habit-Sessions auf — die App-Seite der Live-Aktivität.
/// Beendet wird eine Session normalerweise nicht hier, sondern über die
/// Knöpfe AUF der Aktivität (`FinishHabitSessionIntent` /
/// `CancelHabitSessionIntent`), deren `perform()` im App-Prozess läuft.
///
/// **Warum ein Singleton mit eigenem Store-Zugriff:** Der Einstieg sitzt im
/// Kontextmenü der Habit-Karte, und die Karte bekommt ihre Wege als Closures
/// aus `ContentView`. Ein neuer Closure-Weg hieße, `ContentView` anzufassen —
/// die Session braucht aber ohnehin keinen UI-Zustand: sie schreibt nur die
/// Ablage und bittet das System um eine Aktivität.
@MainActor
final class HabitSessionManager {
    static let shared = HabitSessionManager()

    private init() {}

    /// Startet eine Session für dieses Habit. Es läuft höchstens EINE:
    /// eine bestehende wird vorher still verworfen (nicht gutgeschrieben —
    /// wer mitten in einer Session eine neue startet, hat die alte
    /// aufgegeben; „Fertig" ist der Knopf auf der Aktivität).
    func start(habit: Habit) {
        let startedAt = Date()
        let session = HabitSession(habitID: habit.id,
                                   day: DayKey.today(),
                                   startedAt: startedAt,
                                   plannedMinutes: habit.durationMinutes)
        HabitSessionStorage.save(session)
        // ERST die alte Aktivität beenden, DANN die neue anfordern — beides
        // im selben Task. Als getrennter Fire-and-forget-Task lief das
        // Beenden nach dem Anfordern und riss die frische Aktivität mit.
        Task { [weak self] in
            await HabitSessionActivityControl.endAll()
            self?.requestActivity(habit: habit, startedAt: startedAt)
        }
    }

    private func requestActivity(habit: Habit, startedAt: Date) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            NSLog("HabitSession: Live Activities sind deaktiviert — Session läuft ohne Anzeige.")
            return
        }
        // Farben der Habit-Palette zum Startzeitpunkt auflösen — die
        // Extension soll den Store dafür nicht lesen müssen.
        let data = HabitStore.read(SharedStorage.dataURL())
        let palettes = data.map { PaletteBook(global: $0.palette, customs: $0.customPalettes) }
            ?? PaletteBook()
        let style = palettes.style(for: habit)
        let attributes = HabitActivityAttributes(habitID: habit.id,
                                                 name: habit.name,
                                                 emoji: habit.emoji,
                                                 plannedMinutes: habit.durationMinutes,
                                                 accentFillLight: style.accentFillHex.light,
                                                 accentFillDark: style.accentFillHex.dark,
                                                 accentTextLight: style.accentTextHex.light,
                                                 accentTextDark: style.accentTextHex.dark)
        let content = ActivityContent(state: HabitActivityAttributes.ContentState(startedAt: startedAt),
                                      // Nach dem Cutoff ist die Anzeige keine
                                      // Wahrheit mehr — das System darf sie
                                      // dann ausgrauen.
                                      staleDate: startedAt.addingTimeInterval(HabitSessionMath.staleCutoff))
        do {
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            // Kein Recht auf Live-Aktivitäten (vom Nutzer abgeschaltet) ist
            // kein Fehler der Session: sie läuft trotzdem, nur ohne Anzeige.
            NSLog("HabitSession: Live Activity nicht gestartet: %@", String(describing: error))
        }
        #endif
    }

    /// Aufräumen beim App-Start bzw. beim Aktivwerden: eine Session, die
    /// älter ist als der Cutoff, ist vergessen worden — sie wird still
    /// beendet, OHNE den Tag abzuhaken (8 Stunden „Lesen" waren keine 8
    /// Stunden Lesen). Eine frische Session bleibt unangetastet: die
    /// Live-Aktivität überlebt Force-Quit und Relaunch von selbst.
    func recoverIfNeeded(now: Date = Date()) {
        guard let session = HabitSessionStorage.load() else { return }
        if HabitSessionMath.isStale(startedAt: session.startedAt, now: now) {
            HabitSessionStorage.clear()
            Task { await HabitSessionActivityControl.endAll() }
        }
    }
}
