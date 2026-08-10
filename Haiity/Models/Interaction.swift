import Foundation

// MARK: – Aktionen an einer Habit-Zeile
//
// FRÜHER standen hier belegbare Wischgesten (`SwipeAction`, plus zwei Picker
// in „Mehr"). Beides ist ersatzlos weg: eine Zeile hat jetzt EINEN Weg zu
// ihren Aktionen — langes Drücken öffnet die Karte als Vorschau mit dem
// vergrößerten Raster und den Aktionen darunter (HabitCard). Das ist
// sichtbar statt versteckt, zeigt VORHER, welches Habit gemeint ist, und
// braucht keine Einstellung, die erklärt, was ein Wisch tut.
//
// Alte data.json-Dateien tragen weiterhin `leadingSwipe`/`trailingSwipe`.
// Die Schlüssel werden beim Lesen IGNORIERT (siehe HabitData.CodingKeys) —
// unbekannte Schlüssel sind für Codable kein Fehler, die Datei bleibt also
// lesbar und verliert nichts ausser einer Einstellung, die es nicht mehr
// gibt.

// MARK: – Rückgängig-Toast

/// EINE rückgängig machbare Änderung an EINEM Habit — an einem Tag oder an
/// vielen auf einmal.
///
/// `previousValue` ist der Wert VOR der Änderung (nil = es gab keinen
/// Eintrag). Damit ist die Rücknahme EXAKT und nicht bloß ein zweites
/// Umschalten: ein Mengen-Habit, das von 3 auf 4 hochgezählt wurde, landet
/// wieder auf 3 — nicht auf 0 und nicht auf „irgendwas ≥ 1".
///
/// **Warum eine LISTE von Tagen und nicht einer.** Seit der
/// Mehrfachauswahl im Nacharbeiten (siehe `Backfill`) trägt EIN Griff
/// mehrere Tage nach. Das ist EIN Vorgang, also braucht es EIN Zurück:
/// sieben Toasts übereinander wären keine Rücknahme, sondern eine
/// Warteschlange, und ein Zurück, das nur den letzten Tag trifft, ließe
/// sechs stille Änderungen stehen.
struct CheckInUndo: Equatable, Identifiable {
    /// EIN betroffener Tag mit seinem Wert VOR der Änderung.
    struct Entry: Equatable {
        let day: String
        let previousValue: Int?
    }

    /// Laufende Nummer. Sie IST die Identität des Toasts: der Zeitgeber
    /// hängt daran, und ein Nachzügler erkennt daran, dass inzwischen ein
    /// neuerer Toast steht.
    let id: Int
    let habitId: UUID
    /// Alle Tage dieser einen Änderung, in der Reihenfolge, in der sie
    /// geschrieben wurden.
    let entries: [Entry]
    let message: String

    /// Bequemer Zugriff für den Normalfall „ein Tag" (Abhaken, Hochzählen).
    var day: String { entries.first?.day ?? "" }
    var previousValue: Int? { entries.first?.previousValue }

    /// Toast-Text nach der Änderung. Checkbox: erledigt oder zurückgesetzt.
    /// Mengenziel: der Zählstand, bis das Ziel steht. Ein NACHGETRAGENER Tag
    /// (siehe `Backfill`) trägt sein Datum mit — sonst steht dieselbe Meldung
    /// da wie beim Abhaken von heute, und „Rückgängig" zeigt ins Ungewisse.
    ///
    /// **Warum das ganze Habit und nicht Name plus Ziel.** Die Meldung hängt
    /// an EIGENSCHAFTEN des Habits, und davon kommen welche dazu: als
    /// Nächstes die Art „Ja/Nein", bei der ein Tag auch verneint sein kann.
    /// Mit dem Habit als Argument ist das ein Fall mehr in dieser Funktion —
    /// mit `name` und `target` einzeln wäre es wieder eine neue Signatur und
    /// wieder jeder Aufrufer.
    static func message(habit: Habit,
                        value: Int,
                        day: String,
                        today: String = DayKey.today(),
                        calendar: Calendar = .current) -> String {
        let base: String
        if let target = habit.recurrence.target {
            base = value >= target
                ? String(localized: "\(habit.name) erledigt")
                : String(localized: "\(habit.name): \(value)/\(target)")
        } else {
            base = value >= 1
                ? String(localized: "\(habit.name) erledigt")
                : String(localized: "\(habit.name) zurückgesetzt")
        }
        guard day != today else { return base }
        return String(localized: "\(base) · \(Backfill.dayText(day, calendar: calendar))")
    }

    /// Toast-Text für eine Änderung an MEHREREN Tagen. Hier zählt die ZAHL:
    /// was geschrieben wurde, steht in der Karte — wie viele Tage der Griff
    /// daneben zurückholt, steht nirgendwo sonst.
    static func message(habit: Habit, days: Int, cleared: Bool) -> String {
        cleared
            ? String(localized: "\(habit.name): \(days) Tage zurückgesetzt")
            : String(localized: "\(habit.name): \(days) Tage nachgetragen")
    }
}

/// Zustandsautomat des Rückgängig-Toasts — pure Logik, ohne SwiftUI, damit
/// „der Letzte gewinnt" prüfbar ist statt geglaubt.
///
/// Drei Regeln:
///  * **Kein Stapel.** Es gibt immer höchstens EINEN Toast; ein neuer
///    Check-in ersetzt den alten, statt sich darunter zu legen.
///  * **Der Letzte gewinnt.** Rückgängig nimmt genau die Änderung zurück,
///    auf die der SICHTBARE Toast zeigt — nie eine ältere.
///  * **Nachzügler räumen nichts ab.** Der Zeitgeber des ersetzten Toasts
///    läuft womöglich noch; er darf den neueren nicht wegblenden. Deshalb
///    trägt `expire` die Nummer, zu der er gehört.
struct UndoToastState {
    private(set) var current: CheckInUndo?
    private var generation = 0

    /// Neue Änderung anmelden — ersetzt einen eventuell stehenden Toast.
    @discardableResult
    mutating func present(habitId: UUID,
                          entries: [CheckInUndo.Entry],
                          message: String) -> CheckInUndo {
        generation += 1
        let toast = CheckInUndo(id: generation,
                                habitId: habitId,
                                entries: entries,
                                message: message)
        current = toast
        return toast
    }

    /// Der Normalfall: EIN Tag.
    @discardableResult
    mutating func present(habitId: UUID,
                          day: String,
                          previousValue: Int?,
                          message: String) -> CheckInUndo {
        present(habitId: habitId,
                entries: [CheckInUndo.Entry(day: day, previousValue: previousValue)],
                message: message)
    }

    /// Zeit abgelaufen. No-op, wenn inzwischen ein neuerer Toast steht.
    mutating func expire(_ id: Int) {
        if current?.id == id { current = nil }
    }

    /// Rückgängig: nimmt die Änderung heraus, auf die der sichtbare Toast
    /// zeigt (und blendet ihn damit aus).
    mutating func take() -> CheckInUndo? {
        defer { current = nil }
        return current
    }

    mutating func clear() { current = nil }
}
