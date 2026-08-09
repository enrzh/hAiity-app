import Foundation

// MARK: – Wischgesten

/// Was eine Wischgeste an einer Habit-Zeile auslöst. Belegbar, weil „von
/// links nach rechts = erledigt" für die einen selbstverständlich und für
/// die anderen genau falsch herum ist — und weil Archivieren an der Kante,
/// an der jemand sonst abhakt, teuer ist.
///
/// Bewusst OHNE SwiftUI: Titel und Symbol gehören zur Bedeutung der Aktion
/// (Einstellungsliste UND Wisch-Knopf zeigen dieselben), die Farbe gehört
/// in die Ansicht.
enum SwipeAction: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Abhaken bzw. hochzählen — hakt nur AN, nie ab.
    case done
    /// Den heutigen Eintrag zurücknehmen.
    case revert
    case archive
    case edit
    /// Diese Kante macht nichts.
    case none

    var id: String { rawValue }

    static let defaultLeading = SwipeAction.done
    static let defaultTrailing = SwipeAction.archive

    /// Unbekannte Werte (Datei aus einer neueren Version) lesen als der
    /// jeweilige Standard — nie als Fehler, sonst verliert ein älterer
    /// Build beim nächsten Speichern die ganze Datei.
    static func tolerant(_ raw: String?, fallback: SwipeAction) -> SwipeAction {
        raw.flatMap(SwipeAction.init(rawValue:)) ?? fallback
    }

    var title: String {
        switch self {
        case .done:    return String(localized: "Erledigt")
        case .revert:  return String(localized: "Rückgängig")
        case .archive: return String(localized: "Archivieren")
        case .edit:    return String(localized: "Bearbeiten")
        case .none:    return String(localized: "Nichts")
        }
    }

    /// nil = kein Knopf (bei `.none`).
    var symbol: String? {
        switch self {
        case .done:    return "checkmark"
        case .revert:  return "arrow.uturn.backward"
        case .archive: return "archivebox"
        case .edit:    return "pencil"
        case .none:    return nil
        }
    }

    /// Darf ein VOLLER Wisch (durchziehen ohne Loslassen) das auslösen?
    /// Nur für umkehrbare Aktionen. Archivieren ausdrücklich nicht: ein zu
    /// beherzter Wisch räumt sonst ein Habit aus der Liste, und die
    /// Rücknahme liegt zwei Bildschirme weiter im Archiv.
    var allowsFullSwipe: Bool { self == .done || self == .revert }
}

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
