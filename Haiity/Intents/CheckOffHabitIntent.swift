import AppIntents
import Foundation

/// App Intent zum Abhaken eines Habits. Läuft in ZWEI Prozessen: als
/// interaktiver Widget-Button im Widget-Extension-Prozess und über
/// Siri/Shortcuts im App-Prozess — die Datei ist deshalb in BEIDE Targets
/// kompiliert. Beide Seiten schreiben über `HabitStore` in dieselbe
/// data.json (App-Group-Container via `SharedStorage.dataURL()`), sodass
/// jeder Check-in überall ankommt.
struct HabitEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Habit")
    static var defaultQuery = HabitEntityQuery()

    var id: UUID
    var name: String
    var emoji: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(emoji.isEmpty ? name : "\(emoji) \(name)")")
    }

    init(habit: Habit) {
        self.init(id: habit.id, name: habit.name, emoji: habit.emoji)
    }

    /// Aus rohen Feldern — das Steuerungselement im Kontrollzentrum hält nur
    /// diese drei und hat den Habit nicht zur Hand. Ein eigener Init ist
    /// nötig, weil der bezeichnete oben den memberwise-Init verdeckt.
    init(id: UUID, name: String, emoji: String) {
        self.id = id
        self.name = name
        self.emoji = emoji
    }
}

/// Query über die AKTIVEN Habits des geteilten Stores — archivierte
/// tauchen weder in Siri-Vorschlägen noch in der Shortcuts-Auswahl auf.
struct HabitEntityQuery: EntityQuery {
    private func activeHabits() -> [Habit] {
        guard let data = HabitStore.read(SharedStorage.dataURL()) else { return [] }
        return HabitVisibility.visibleActiveHabits(
            data.habits,
            unlocked: HabitVisibility.sharedEntitlementIsUnlocked)
    }

    func entities(for identifiers: [HabitEntity.ID]) async throws -> [HabitEntity] {
        activeHabits().filter { identifiers.contains($0.id) }.map(HabitEntity.init)
    }

    func suggestedEntities() async throws -> [HabitEntity] {
        activeHabits().map(HabitEntity.init)
    }

    func defaultResult() async -> HabitEntity? {
        activeHabits().first.map(HabitEntity.init)
    }
}

struct CheckOffHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Habit abhaken"
    static var description = IntentDescription("Hakt einen Habit für heute ab bzw. zählt ihn eins hoch.")

    @Parameter(title: "Habit")
    var habit: HabitEntity

    init() {}

    init(habit: Habit) {
        self.habit = HabitEntity(habit: habit)
    }

    /// Für den Widget-Knopf und das Steuerungselement, die nur die Kennung
    /// haben. Eine unbekannte Kennung ist KEIN Fehler — `CheckOffLogic` macht
    /// daraus einen No-op, damit ein Knopf auf einem gelöschten Habit nichts
    /// kaputt macht und nichts erfindet.
    init(entity: HabitEntity) {
        self.habit = entity
    }

    func perform() async throws -> some IntentResult {
        // Immer frisch von der Platte laden — der Store dieses Prozesses
        // ist nicht der Store des App-Prozesses. persist() (in apply)
        // schreibt synchron; im Widget-Extension-Prozess folgt der
        // Timeline-Reload sofort, in der App entprellt nach dem Schreiben.
        let store = HabitStore(url: SharedStorage.dataURL())
        let storedHabit = HabitVisibility.visibleActiveHabits(
            store.habits,
            unlocked: HabitVisibility.sharedEntitlementIsUnlocked)
            .first { $0.id == habit.id }
        guard let storedHabit else { return .result() }
        let day = HabitTimeZone.today(for: storedHabit,
                                      defaultIdentifier: store.defaultTimeZoneIdentifier)
        CheckOffLogic.apply(to: store, habitId: habit.id, day: day)
        // Der App-Prozess bekommt von diesem Check-in nichts mit — die
        // heutige Erinnerung und die Tagesmeldung hier selbst nachziehen.
        await Reminders.reconcileAfterExternalCheckIn(
            store: store,
            habitID: habit.id,
            defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
        return .result()
    }
}

/// Explicitly removes today's widget value. It is separate from
/// `CheckOffHabitIntent` so the main widget can offer a real revert action
/// without making the primary check-in toggle unexpectedly.
struct ResetHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Habit zurücksetzen"
    static var description = IntentDescription("Entfernt den heutigen Eintrag.")

    @Parameter(title: "Habit")
    var habit: HabitEntity

    init() {}

    init(habit: Habit) {
        self.habit = HabitEntity(habit: habit)
    }

    init(entity: HabitEntity) {
        self.habit = entity
    }

    func perform() async throws -> some IntentResult {
        let store = HabitStore(url: SharedStorage.dataURL())
        guard let storedHabit = HabitVisibility.visibleActiveHabits(
            store.habits,
            unlocked: HabitVisibility.sharedEntitlementIsUnlocked)
            .first(where: { $0.id == habit.id }) else { return .result() }
        let calendar = HabitTimeZone.calendar(
            for: storedHabit,
            defaultIdentifier: store.defaultTimeZoneIdentifier)
        if storedHabit.isReminder {
            let state = ReminderOccurrenceEngine.state(for: storedHabit, calendar: calendar)
            if let completed = state.mostRecentCompleted {
                store.setReminderCompletion(storedHabit.id, day: completed.day,
                                            completed: false, nextCursor: nil)
            }
        } else {
            let day = HabitTimeZone.today(for: storedHabit,
                                          defaultIdentifier: store.defaultTimeZoneIdentifier)
            store.clear(storedHabit.id, day: day)
        }
        await Reminders.reconcileAfterExternalCheckIn(
            store: store,
            habitID: storedHabit.id,
            defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
        return .result()
    }
}

/// Explicit Ja/Nein actions for the interactive widget. They deliberately set
/// a value instead of toggling so pressing Ja twice cannot erase the answer.
struct AnswerYesHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Mit Ja beantworten"
    static var description = IntentDescription("Beantwortet den heutigen Ja/Nein-Habit mit Ja.")

    @Parameter(title: "Habit")
    var habit: HabitEntity

    init() {}

    init(habit: Habit) {
        self.habit = HabitEntity(habit: habit)
    }

    func perform() async throws -> some IntentResult {
        await AnswerHabitIntentSupport.setAnswer(habit.id, yes: true)
        return .result()
    }
}

struct AnswerNoHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Mit Nein beantworten"
    static var description = IntentDescription("Beantwortet den heutigen Ja/Nein-Habit mit Nein.")

    @Parameter(title: "Habit")
    var habit: HabitEntity

    init() {}

    init(habit: Habit) {
        self.habit = HabitEntity(habit: habit)
    }

    func perform() async throws -> some IntentResult {
        await AnswerHabitIntentSupport.setAnswer(habit.id, yes: false)
        return .result()
    }
}

private enum AnswerHabitIntentSupport {
    static func setAnswer(_ id: UUID, yes: Bool) async {
        let store = HabitStore(url: SharedStorage.dataURL())
        guard let storedHabit = HabitVisibility.visibleActiveHabits(
            store.habits,
            unlocked: HabitVisibility.sharedEntitlementIsUnlocked)
            .first(where: { $0.id == id }) else { return }
        let day = HabitTimeZone.today(for: storedHabit,
                                      defaultIdentifier: store.defaultTimeZoneIdentifier)
        AnswerHabitLogic.apply(to: store, habitId: id, yes: yes, day: day)
        await Reminders.reconcileAfterExternalCheckIn(
            store: store,
            habitID: id,
            defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
    }
}

/// Explicit Ja/Nein writes shared by the widget intent and unit tests. This
/// must set the requested answer, never toggle it, so repeated widget taps
/// remain predictable.
enum AnswerHabitLogic {
    @discardableResult
    static func apply(to store: HabitStore,
                      habitId: UUID,
                      yes: Bool,
                      day: String = DayKey.today()) -> Bool {
        guard let habit = store.habits.first(where: { $0.id == habitId }),
              habit.archivedAt == nil,
              habit.isTrackedHabit,
              habit.kind == .yesNo else { return false }

        let answer = yes ? Habit.Answer.yes : Habit.Answer.no
        guard habit.log[day] != answer else { return false }
        store.setValue(habitId, day: day, value: answer)
        return true
    }
}

enum ResetHabitLogic {
    @discardableResult
    static func apply(to store: HabitStore,
                      habitId: UUID,
                      day: String = DayKey.today()) -> Bool {
        guard let habit = store.habits.first(where: { $0.id == habitId }),
              habit.archivedAt == nil,
              habit.log[day] != nil else { return false }
        if habit.isReminder {
            store.setReminderCompletion(habitId, day: day,
                                        completed: false, nextCursor: nil)
        } else {
            store.clear(habitId, day: day)
        }
        return true
    }
}

/// Pure, testbare Abhak-Semantik — getrennt vom Intent, damit Unit-Tests
/// sie ohne AppIntents-Laufzeit abdecken.
enum CheckOffLogic {
    /// Checkbox-Habits: nur AN-haken, wenn heute noch offen — idempotent,
    /// ein Widget-Button darf nie ENT-haken. Mengen-Habits: +1, auch über
    /// das Ziel hinaus. Ja/Nein-Habits: JA setzen — auch über ein
    /// bestehendes Nein hinweg (der Knopf heißt „abhaken", und wer ihn
    /// drückt, meint Ja); ein schon bejahter Tag bleibt unberührt, damit
    /// auch hier nichts zurückgenommen wird. Archivierte oder unbekannte
    /// Habits: No-op. Rückgabe: wurde etwas geschrieben?
    @discardableResult
    static func apply(to store: HabitStore, habitId: UUID, day: String = DayKey.today()) -> Bool {
        guard let habit = store.habits.first(where: { $0.id == habitId }),
              habit.archivedAt == nil else { return false }
        if habit.isReminder {
            let calendar = HabitTimeZone.calendar(
                for: habit,
                defaultIdentifier: store.defaultTimeZoneIdentifier)
            let state = ReminderOccurrenceEngine.state(for: habit, calendar: calendar)
            guard let occurrence = state.actionable,
                  habit.log[occurrence.day] == nil else { return false }
            let nextCursor = habit.repeatsWhileIncomplete ? nil
                : ReminderOccurrenceEngine.cursorAfterCompleting(occurrence,
                                                                  reminder: habit,
                                                                  calendar: calendar)
            store.setReminderCompletion(habitId,
                                        day: occurrence.day,
                                        completed: true,
                                        nextCursor: nextCursor)
            return true
        }
        switch habit.kind {
        case .quantity:
            store.increment(habitId, day: day)
            return true
        case .yesNo:
            guard !habit.isAffirmed(day) else { return false }
            // NICHT `answer`: das würde ein bestehendes Ja umschalten und
            // damit doch wieder ent-haken.
            store.setValue(habitId, day: day, value: Habit.Answer.yes)
            return true
        case .checkbox:
            guard !habit.isDone(day) else { return false }
            store.toggle(habitId, day: day)
            return true
        }
    }
}
