import AppIntents
import Foundation

/// Die Siri/Shortcuts-Erweiterung über das Abhaken hinaus: Nein sagen,
/// Tagesstand hören, Serie abfragen. Alle drei antworten DIREKT in Siri
/// (ProvidesDialog) — die App muss nicht aufgehen. Nur im App-Target: die
/// Widget-Extension braucht keinen dieser Wege.
///
/// Wie beim Abhaken gilt: der Store wird je Aufruf FRISCH von der Platte
/// geladen (der Intent-Prozess ist nicht der App-Prozess), und die pure
/// Semantik steht getrennt vom Intent, damit Unit-Tests sie ohne
/// AppIntents-Laufzeit abdecken.

/// „Nein" per Siri — das Gegenstück zum Abhaken, nur für Ja/Nein-Habits.
struct DeclineHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Nein notieren"
    static var description = IntentDescription("Beantwortet einen Ja/Nein-Habit für heute mit Nein.")

    @Parameter(title: "Habit")
    var habit: HabitEntity

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = HabitStore(url: SharedStorage.dataURL())
        let storedHabit = HabitVisibility.visibleActiveHabits(
            store.habits,
            unlocked: HabitVisibility.sharedEntitlementIsUnlocked)
            .first { $0.id == habit.id }
        guard let storedHabit else {
            return .result(dialog: IntentDialog(stringLiteral:
                String(localized: "Diesen Habit gibt es nicht mehr.")))
        }
        let day = HabitTimeZone.today(for: storedHabit,
                                      defaultIdentifier: store.defaultTimeZoneIdentifier)
        let outcome = DeclineLogic.apply(to: store, habitId: habit.id, day: day)
        if outcome == .declined {
            // Der Tag ist beantwortet — die heutige Erinnerung darf nicht
            // mehr klingeln (und ein perfekter Tag wird es damit nie).
            await Reminders.reconcileAfterExternalCheckIn(
                store: store,
                habitID: habit.id,
                defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
        }
        return .result(dialog: IntentDialog(stringLiteral: DeclineLogic.speech(for: outcome, name: habit.name)))
    }
}

/// Pure, testbare Nein-Semantik.
enum DeclineLogic {
    enum Outcome: Equatable { case declined, alreadyDeclined, notYesNo, missing }

    /// Nein setzen — auch über ein bestehendes Ja hinweg: wer Siri „nicht
    /// geschafft" sagt, meint das so. Ein schon verneinter Tag bleibt
    /// unberührt; kein Ja/Nein-Habit, Archivierte, Unbekannte: No-op.
    static func apply(to store: HabitStore, habitId: UUID, day: String = DayKey.today()) -> Outcome {
        guard let habit = store.habits.first(where: { $0.id == habitId }),
              habit.archivedAt == nil else { return .missing }
        guard habit.kind == .yesNo else { return .notYesNo }
        guard !habit.isDeclined(day) else { return .alreadyDeclined }
        store.setValue(habitId, day: day, value: Habit.Answer.no)
        return .declined
    }

    static func speech(for outcome: Outcome, name: String) -> String {
        switch outcome {
        case .declined:
            return String(localized: "\(name) ist für heute als Nein notiert.")
        case .alreadyDeclined:
            return String(localized: "\(name) steht heute schon auf Nein.")
        case .notYesNo:
            return String(localized: "\(name) ist kein Ja/Nein-Habit — dort gibt es nur das Abhaken.")
        case .missing:
            return String(localized: "Diesen Habit gibt es nicht mehr.")
        }
    }
}

/// „Wie steht's heute?" — der Tagesstand als Satz, derselbe Text wie in
/// der Tageszusammenfassung. Liefert zusätzlich die Zahl der OFFENEN
/// Habits als Wert, damit Kurzbefehle darauf verzweigen können.
struct HabitStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Tagesstand"
    static var description = IntentDescription("Sagt, was heute erledigt ist und was noch offen steht.")

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let store = HabitStore(url: SharedStorage.dataURL())
        let visibleHabits = HabitVisibility.visibleActiveHabits(
            store.habits,
            unlocked: HabitVisibility.sharedEntitlementIsUnlocked)
        let status = store.dailyStatus(habits: visibleHabits)
        let text = SummaryText.daily(status)
            ?? String(localized: "Heute steht kein Habit an.")
        return .result(value: status.total - status.done,
                       dialog: IntentDialog(stringLiteral: text))
    }
}

/// „Wie lang ist meine Serie?" — dieselbe Zahl wie in der Statistik
/// (GoalEngine.streak), als Satz und als Wert für Kurzbefehle.
struct HabitStreakIntent: AppIntent {
    static var title: LocalizedStringResource = "Serie abfragen"
    static var description = IntentDescription("Nennt die laufende Serie eines Habits.")

    @Parameter(title: "Habit")
    var habit: HabitEntity

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let store = HabitStore(url: SharedStorage.dataURL())
        guard let stored = HabitVisibility.visibleActiveHabits(
            store.habits,
            unlocked: HabitVisibility.sharedEntitlementIsUnlocked)
            .first(where: { $0.id == habit.id }) else {
            return .result(value: 0,
                           dialog: IntentDialog(stringLiteral: String(localized: "Diesen Habit gibt es nicht mehr.")))
        }
        let calendar = HabitTimeZone.calendar(
            for: stored,
            defaultIdentifier: store.defaultTimeZoneIdentifier)
        let streak = GoalEngine.streak(
            habit: stored,
            today: DayKey.today(calendar: calendar),
            calendar: calendar)
        return .result(value: streak,
                       dialog: IntentDialog(stringLiteral: StreakSpeech.text(name: stored.name, streak: streak)))
    }
}

/// Pure, testbare Serien-Sätze (Ein-Tag-Fall ohne Plural-Holperer).
enum StreakSpeech {
    static func text(name: String, streak: Int) -> String {
        switch streak {
        case 0:
            return String(localized: "Für \(name) läuft gerade keine Serie.")
        case 1:
            return String(localized: "\(name): 1 Tag am Stück.")
        default:
            return String(localized: "\(name): \(streak) Tage am Stück.")
        }
    }
}
