import AppIntents
import WidgetKit

/// Die Einstellung EINER Widget-Instanz: welcher Habit steht darin?
///
/// Das Widget war bis v4 fest auf den ersten Habit verdrahtet — wer drei
/// Habits verfolgt, konnte zwei davon nicht auf den Homescreen legen. Jetzt
/// trägt jede Instanz ihre eigene Auswahl (langer Druck → „Widget
/// bearbeiten"), und die Auswahl greift auf DIESELBE Entity und DIESELBE
/// Query zurück, die Siri und Shortcuts schon benutzen — eine Liste, eine
/// Quelle, keine zweite Definition, die auseinanderlaufen kann.
///
/// Der Parameter ist bewusst OPTIONAL: „nicht gesetzt" heißt automatisch der
/// erste aktive Habit (siehe `WidgetLogic.resolve`). Damit zeigt ein frisch
/// abgelegtes Widget sofort etwas, statt leer auf eine Konfiguration zu
/// warten — und ein gelöschter Habit lässt es nicht kaputt zurück.
struct SelectHabitIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Habit auswählen"
    static var description = IntentDescription("Welcher Habit in diesem Widget steht.")

    /// Nicht in Shortcuts und nicht in der Suche: das hier ist die
    /// EINSTELLUNG eines Widgets, keine Aktion. Ohne diese Zeile stünde in
    /// der Kurzbefehle-App ein Eintrag „Habit auswählen", der beim Ausführen
    /// nichts tut — die Auswahl gibt es nur im Kontext einer Widget-Instanz.
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Habit")
    var habit: HabitEntity?

    init() {}

    init(habit: HabitEntity?) {
        self.habit = habit
    }
}

/// Dasselbe für die Steuerungselemente (Kontrollzentrum, iOS 18+).
/// `ControlConfigurationIntent` ist ein eigener Typ als
/// `WidgetConfigurationIntent` — deshalb steht hier ein zweiter, sehr kurzer
/// Intent statt einer Doppelkonformität, die auf iOS 17 nicht existiert.
@available(iOS 18.0, *)
struct SelectHabitControlIntent: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Habit auswählen"
    static var description = IntentDescription("Welcher Habit über das Kontrollzentrum abgehakt wird.")

    static var isDiscoverable: Bool { false }

    @Parameter(title: "Habit")
    var habit: HabitEntity?

    init() {}

    init(habit: HabitEntity?) {
        self.habit = habit
    }
}
