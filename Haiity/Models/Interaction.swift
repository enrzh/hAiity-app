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

/// EINE rückgängig machbare Änderung an EINEM Tag EINES Habits.
///
/// `previousValue` ist der Wert VOR der Änderung (nil = es gab keinen
/// Eintrag). Damit ist die Rücknahme EXAKT und nicht bloß ein zweites
/// Umschalten: ein Mengen-Habit, das von 3 auf 4 hochgezählt wurde, landet
/// wieder auf 3 — nicht auf 0 und nicht auf „irgendwas ≥ 1".
struct CheckInUndo: Equatable, Identifiable {
    /// Laufende Nummer. Sie IST die Identität des Toasts: der Zeitgeber
    /// hängt daran, und ein Nachzügler erkennt daran, dass inzwischen ein
    /// neuerer Toast steht.
    let id: Int
    let habitId: UUID
    let day: String
    let previousValue: Int?
    let message: String

    /// Toast-Text nach der Änderung. Checkbox: erledigt oder zurückgesetzt.
    /// Mengenziel: der Zählstand, bis das Ziel steht.
    static func message(habitName: String, value: Int, target: Int?) -> String {
        if let target {
            return value >= target
                ? String(localized: "\(habitName) erledigt")
                : String(localized: "\(habitName): \(value)/\(target)")
        }
        return value >= 1
            ? String(localized: "\(habitName) erledigt")
            : String(localized: "\(habitName) zurückgesetzt")
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
                          day: String,
                          previousValue: Int?,
                          message: String) -> CheckInUndo {
        generation += 1
        let toast = CheckInUndo(id: generation,
                                habitId: habitId,
                                day: day,
                                previousValue: previousValue,
                                message: message)
        current = toast
        return toast
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
