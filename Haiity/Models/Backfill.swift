import Foundation

/// „Nacharbeiten" — einen Tag NACHTRAGEN, absichtlich und mit Datum vor
/// Augen. Reine Rechnung, ohne SwiftUI und mit explizitem `Calendar`: welche
/// Tage stehen überhaupt zur Wahl, in welchem Zustand ist ein Tag, welche
/// Aktionen gibt es dazu — und welchen Wert schreibt jede davon.
///
/// **Warum das hier steht und nicht in der Karte.** Ein Tippen auf eine
/// Rasterzelle hat früher SOFORT geschrieben (8-pt-Quadrat, ein Fehlgriff und
/// ein vergangener Tag war umgeschaltet). Jetzt öffnet es diese Karte, und
/// die Karte schreibt erst auf eine benannte Aktion. Damit hängt an der
/// Stelle eine Menge Regelwerk — Grenzen, Zustände, Werte —, und Regelwerk
/// gehört in eine Datei, die man prüfen kann, nicht in einen View-Body.
enum Backfill {
    /// So weit reicht das Raster zurück: 53 Spalten × 7 Zeilen. Die
    /// Untergrenze der Karte darf nicht ENGER sein — sonst gäbe es Zellen,
    /// die man antippen kann, die die Karte dann aber nicht anzeigen darf.
    static let windowDays = 53 * GridCalendar.rows

    // MARK: – Maße des Kalenderblatts

    /// Wie hoch das Kalenderblatt (`DatePicker`, grafisch) im Voraus
    /// RESERVIERT bekommt.
    ///
    /// **Warum es diese Rechnung gibt.** Der grafische `DatePicker` ist ein
    /// `UIDatePicker` und meldet seine Höhe in ZWEI Schritten: beim ersten
    /// Layout fehlt genau eine Wochenzeile, die richtige Höhe kommt 6 bis
    /// 100 ms später nach (nachgemessen auf dem Gerät: 324 pt, dann 374,7 pt
    /// bei 328 pt Breite). Die Karte wächst mit ihrem Inhalt — sie stand
    /// damit einen Sekundenbruchteil 50 pt zu niedrig und sprang dann auf ihr
    /// Endmaß. Wer die Höhe vorher weiß, muss nicht darauf warten.
    ///
    /// **Die Rechnung ist eine ENTSCHEIDUNG, keine Vorhersage.** Ein
    /// Monatsblatt ist sechs Wochenzeilen hoch (der Kalender hält die Zahl
    /// fest, damit das Blatt beim Blättern nicht springt), und eine Zeile ist
    /// so hoch wie eine Spalte breit ist — sieben Spalten auf die Breite.
    /// Darüber sitzen Monatszeile und Wochentagskopf; die wachsen mit der
    /// Schrift, das Raster nicht. Angesetzt wird die Reserve als
    /// MINDESTHÖHE: fällt sie einmal zu knapp aus, wächst das Blatt wie
    /// vorher weiter, statt abgeschnitten zu werden.
    ///
    /// Nachgemessen (Breite 328 pt): 370,0 / 374,7 / 384,3 pt bei den
    /// Schriftfaktoren 0,824 / 1,0 / 1,353 — die Rechnung liegt überall ein
    /// bis drei Punkte darüber.
    static func calendarHeight(width: CGFloat, typeScale: CGFloat = 1) -> CGFloat {
        let rows = 6 * max(0, width) / 7
        // Auf einen vernünftigen Bereich geklemmt: eine Schriftskala von 0
        // oder 5 gibt es nicht, und ein Ausreißer soll die Karte nicht
        // zerlegen.
        let scale = min(2, max(0.5, typeScale))
        return (rows + 67 + 27 * scale).rounded(.up)
    }

    // MARK: – Grenzen der Datumswahl

    /// Erster und letzter wählbarer Tag, beide einschließlich.
    struct Bounds: Equatable {
        let earliest: String
        let latest: String

        /// Tagesschlüssel sind nullgepolstert — der lexikografische Vergleich
        /// IST der chronologische.
        func contains(_ key: String) -> Bool { key >= earliest && key <= latest }
    }

    /// Obergrenze ist immer heute (die Zukunft trägt man nicht nach).
    ///
    /// Die Untergrenze ist der FRÜHESTE aus drei Kandidaten:
    ///  * heute − `windowDays` — so weit reicht das sichtbare Raster, und
    ///    jede Zelle darin muss die Karte an ihrem Datum öffnen können;
    ///  * `habit.createdAt`, sofern plausibel;
    ///  * der älteste zählende Log-Tag (importierte Historie kann älter sein
    ///    als das Habit selbst).
    ///
    /// **`createdAt` allein wäre der Fehler**, den es hier zu vermeiden gilt:
    /// es steht bei der Anlage auf HEUTE. Ein Habit, das man gerade angelegt
    /// hat, hätte damit eine leere Auswahl — genau der Fall, für den man
    /// nacharbeitet („angelegt, und jetzt die letzte Woche eintragen").
    ///
    /// Zum Schluss auf `DayKey.plausibleFloor` geklemmt. Heute gewinnt kein
    /// Kandidat diesen Vergleich — ein absurd altes `createdAt` scheitert
    /// schon an `isPlausible`, und `validDays` filtert selbst gegen den
    /// Boden. Die Klemme steht trotzdem: sie ist die Stelle, an der die
    /// Zusage „was hier herauskommt, ist schreibbar" hängt, und sie hält
    /// auch dann noch, wenn `windowDays` einmal größer wird als die
    /// Plausibilitätsspanne. Was darunter läge, wäre für Serien und
    /// Statistik unsichtbar (siehe `Habit.validDays`) und stünde trotzdem
    /// für immer in der Datei und in iCloud.
    static func bounds(habit: Habit,
                       today: String = DayKey.today(),
                       calendar: Calendar = .current) -> Bounds {
        var earliest = today
        func consider(_ key: String?) {
            guard let key, key < earliest else { return }
            earliest = key
        }
        consider(DayKey.shifted(today, by: -windowDays, calendar: calendar))
        if DayKey.isPlausible(habit.createdAt, today: today, calendar: calendar) {
            consider(habit.createdAt)
        }
        consider(habit.validDays(today: today, calendar: calendar).min())

        if let floor = DayKey.plausibleFloor(today: today, calendar: calendar) {
            let floorKey = DayKey.key(for: floor, calendar: calendar)
            if earliest < floorKey { earliest = floorKey }
        }
        return Bounds(earliest: earliest, latest: today)
    }

    /// Dieselben Grenzen als Datumsspanne — das ist, was ein `DatePicker`
    /// versteht. Die Spanne ist nie leer: sie enthält mindestens heute.
    static func dateRange(habit: Habit,
                          today: String = DayKey.today(),
                          calendar: Calendar = .current) -> ClosedRange<Date> {
        let b = bounds(habit: habit, today: today, calendar: calendar)
        let upper = DayKey.date(from: b.latest, calendar: calendar)
            ?? calendar.startOfDay(for: Date())
        let lower = DayKey.date(from: b.earliest, calendar: calendar) ?? upper
        return min(lower, upper)...upper
    }

    /// Dieselbe Spanne HALBOFFEN — `MultiDatePicker` nimmt nur die Form.
    ///
    /// **Die Obergrenze ist der Beginn des LETZTEN wählbaren Tages, nicht
    /// der des Folgetages.** `MultiDatePicker` rechnet in Tagen, nicht in
    /// Augenblicken: der Tag, in dem die Obergrenze liegt, ist noch wählbar.
    /// Mit dem Folgetag als Grenze (die naheliegende Lesart einer halboffenen
    /// Spanne) war MORGEN anwählbar — nachgemessen am Bildschirm: der 11.
    /// stand schwarz zwischen dem heutigen 10. und dem ausgegrauten 12. Der
    /// Schreibweg hätte ihn ohnehin abgelehnt (`canWrite`), aber ein Tag, den
    /// man auswählen kann und der dann stillschweigend übersprungen wird, ist
    /// eine Lüge im Kalender.
    static func dateRangeExclusive(habit: Habit,
                                   today: String = DayKey.today(),
                                   calendar: Calendar = .current) -> Range<Date> {
        let closed = dateRange(habit: habit, today: today, calendar: calendar)
        guard closed.lowerBound < closed.upperBound else {
            // Entartet (nur ein Tag wählbar): die Spanne darf nicht leer sein.
            let upper = calendar.date(byAdding: .day, value: 1, to: closed.upperBound)
                ?? closed.upperBound.addingTimeInterval(86_400)
            return closed.lowerBound..<upper
        }
        return closed.lowerBound..<closed.upperBound
    }

    /// Darf an diesem Tag geschrieben werden?
    ///
    /// ZWEI Prüfungen, und beide sind Absicht. Die Grenzen sind das, was der
    /// Picker anbietet; `DayKey.isPlausible` ist das, was der Speicher
    /// verträgt. `HabitStore.setValue` prüft den Schlüssel NICHT (es ist der
    /// exakte Setter für „Rückgängig", der bekommt seinen Schlüssel aus
    /// einem Toast). Dies hier ist sein erster Aufrufer mit einem vom Nutzer
    /// GEWÄHLTEN Tag — ein unplausibler Schlüssel wäre für Serien, Statistik
    /// und Raster unsichtbar und stünde trotzdem für immer in der Datei.
    static func canWrite(habit: Habit,
                         day: String,
                         today: String = DayKey.today(),
                         calendar: Calendar = .current) -> Bool {
        guard DayKey.isPlausible(day, today: today, calendar: calendar) else { return false }
        return bounds(habit: habit, today: today, calendar: calendar).contains(day)
    }

    // MARK: – Der Zustand EINES Tages

    /// Wie ein einzelner Tag dasteht.
    ///
    /// **Warum benannt und vierstellig.** Bei der Habit-Art „Ja/Nein" ist
    /// ein Tag *unbeantwortet*, *ja* oder *nein* — drei Zustände, die ein
    /// aus `dayCounts` abgeleiteter Umschalter (an/aus) nicht ausdrücken
    /// kann. Ein einzelner Kippknopf in der Karte hätte dafür weggeworfen
    /// werden müssen; eine Liste aus Aktionen, die aus einem BENANNTEN
    /// Zustand fällt, nicht — `.declined` stand deshalb schon hier, bevor es
    /// die Habit-Art gab, und die Karte hat sich für sie nicht geändert.
    enum DayState: Equatable {
        /// Kein Eintrag — bei Ja/Nein: unbeantwortet.
        case empty
        /// Checkbox-Habit: erledigt. Bei Ja/Nein: mit Ja beantwortet.
        case done
        /// Ausdrücklich verneint (nur bei der Habit-Art „Ja/Nein").
        case declined
        /// Mengen-Habit: Zählstand gegen das Ziel.
        case quantity(value: Int, target: Int)

        /// Zählt der Tag im Sinne des Ziels? Dieselbe Semantik wie
        /// `GoalEngine.dayCounts`, nur aus dem bereits abgeleiteten Zustand.
        var counts: Bool {
            switch self {
            case .empty, .declined: return false
            case .done: return true
            case let .quantity(value, target): return value >= target
            }
        }
    }

    static func state(habit: Habit, day: String) -> DayState {
        let value = habit.log[day] ?? 0
        switch habit.kind {
        case .yesNo:
            if value == Habit.Answer.no { return .declined }
            // Jeder andere positive Wert ist ein Ja — auch die „1", die ein
            // ausgelieferter Build hinterlässt (siehe `Habit.isAffirmed`).
            return value >= 1 ? .done : .empty
        case .quantity:
            return .quantity(value: max(0, value), target: habit.recurrence.target ?? 1)
        case .checkbox:
            return value >= 1 ? .done : .empty
        }
    }

    // MARK: – Die Aktionen zu einem Zustand

    /// EINE Aktion der Karte: was sie heißt und was sie schreibt.
    ///
    /// `value` ist der Wert, der in den Log geht; `nil` entfernt den Eintrag.
    /// Nie ein Delta: „+1" wäre bei einem nachgetragenen Tag eine Rechnung
    /// auf einem Stand, den man gerade gar nicht vor Augen hat.
    struct Action: Identifiable, Equatable {
        enum Kind: String { case done, affirmed, declined, quantity, clear }

        /// Gilt die Aktion für EINEN Tag oder für die ganze Auswahl? Nur die
        /// Beschriftung hängt daran — geschrieben wird in beiden Fällen
        /// derselbe Wert, und zwar für JEDEN betroffenen Tag derselbe. Eine
        /// Mehrfachauswahl mischt nicht: sie setzt alle gleich.
        enum Scope { case day, set }

        let kind: Kind
        let value: Int?
        var scope: Scope = .day

        var id: String { kind.rawValue }

        /// Bei Ja/Nein heißen die Knöpfe „Ja" und „Nein" und nicht
        /// „Erledigt"/„Nicht gemacht": das Habit stellt eine FRAGE („Kein
        /// Zucker?"), und man beantwortet eine Frage nicht mit „erledigt".
        var title: String {
            switch (kind, scope) {
            case (.done, .day):     return String(localized: "Erledigt")
            case (.done, .set):     return String(localized: "Alle als erledigt")
            case (.affirmed, .day): return String(localized: "Ja")
            case (.affirmed, .set): return String(localized: "Alle als Ja")
            case (.declined, .day): return String(localized: "Nein")
            case (.declined, .set): return String(localized: "Alle als Nein")
            case (.quantity, .day): return String(localized: "Ziel erreicht")
            case (.quantity, .set): return String(localized: "Alle auf das Ziel")
            case (.clear, .day):    return String(localized: "Rückgängig")
            case (.clear, .set):    return String(localized: "Alle zurücksetzen")
            }
        }

        func scoped(_ scope: Scope) -> Action {
            Action(kind: kind, value: value, scope: scope)
        }

        var systemImage: String {
            switch kind {
            case .done, .affirmed: return "checkmark"
            case .declined:        return "xmark"
            case .quantity:        return "target"
            case .clear:           return "arrow.uturn.backward"
            }
        }

        /// Kennung für die Oberfläche — je Aktion genau eine, stabil.
        var accessibilityIdentifier: String { "backfill-action-\(kind.rawValue)" }

        static let done = Action(kind: .done, value: 1)
        static let clear = Action(kind: .clear, value: nil)
        /// Ja/Nein: die beiden reservierten Antwort-Codes, nicht 1 und nicht
        /// 0 (siehe `Habit.Answer`).
        static let affirm = Action(kind: .affirmed, value: Habit.Answer.yes)
        static let decline = Action(kind: .declined, value: Habit.Answer.no)
        /// Mengenziel: EXAKT das Ziel, nicht „einer mehr".
        static func quantity(target: Int) -> Action {
            Action(kind: .quantity, value: max(1, target))
        }
    }

    /// Welche Aktionen gibt es zu diesem Zustand?
    ///
    /// Bei Ja/Nein sind es IMMER genau zwei, und in jedem Zustand die beiden,
    /// die etwas ändern: unbeantwortet -> Ja | Nein, Ja -> Nein |
    /// Rückgängig, Nein -> Ja | Rückgängig. Ein dritter Knopf wäre in jedem
    /// Zustand einer, der nichts tut.
    ///
    /// Die Art muss mit hinein, weil `.done` bei einer Checkbox etwas
    /// anderes bedeutet als bei einer Frage — und vor allem einen anderen
    /// WERT schreibt.
    static func actions(for state: DayState, kind: HabitKind = .checkbox) -> [Action] {
        if kind == .yesNo {
            switch state {
            case .empty:    return [.affirm, .decline]
            case .done:     return [.decline, .clear]
            case .declined: return [.affirm, .clear]
            case .quantity: return [.affirm, .decline]   // unmöglich; nie ohne Ausweg
            }
        }
        switch state {
        case .empty:
            return [.done]
        case .done:
            return [.clear]
        case .declined:
            // Bei Checkbox und Menge nicht erzeugbar — die Liste hätte den
            // Fall trotzdem: auf Ja drehen oder den Tag wieder leeren.
            return [.done, .clear]
        case let .quantity(value, target):
            var out: [Action] = []
            if value < target { out.append(.quantity(target: target)) }
            if value > 0 { out.append(.clear) }
            return out
        }
    }

    /// Bequemer Weg: Zustand UND Art kommen aus demselben Habit.
    static func actions(habit: Habit, day: String) -> [Action] {
        actions(for: state(habit: habit, day: day), kind: habit.kind)
    }

    // MARK: – Mehrere Tage auf einmal

    /// Was in einer Mehrfachauswahl steckt: wie viele Tage, und wie viele
    /// davon schon zählen. Die zweite Zahl ist der Punkt — sie sagt, was
    /// eine EINHEITLICHE Aktion überhaupt noch ändern wird.
    struct Selection: Equatable {
        let count: Int
        let done: Int
    }

    static func selection(habit: Habit, days: Set<String>) -> Selection {
        Selection(count: days.count,
                  done: days.filter { state(habit: habit, day: $0).counts }.count)
    }

    /// Die Aktionen für eine Mehrfachauswahl. Immer genau ZWEI, und beide
    /// gelten für ALLE gewählten Tage gleich: nachtragen oder leeren. Es gibt
    /// bewusst kein „umschalten" — bei gemischten Tagen wüsste niemand
    /// vorher, was passiert.
    ///
    /// Auch bei Ja/Nein bleiben es zwei: „Alle als Ja" und „Alle
    /// zurücksetzen". Ein drittes „Alle als Nein" ist bewusst NICHT dabei —
    /// die Zeile trägt drei Beschriftungen dieser Länge nicht, und
    /// nachgetragen wird, was man geschafft hat. Ein einzelnes Nein
    /// nachzutragen geht weiterhin über den Einzel-Modus.
    static func setActions(habit: Habit) -> [Action] {
        let write: Action
        switch habit.kind {
        case .yesNo:    write = .affirm
        case .quantity: write = .quantity(target: habit.recurrence.target ?? 1)
        case .checkbox: write = .done
        }
        return [write.scoped(.set), Action.clear.scoped(.set)]
    }

    /// Die Statuszeile im Mehrfach-Modus.
    ///
    /// Bei GENAU einem Tag steht sein Datum dabei. Das ist kein Schmuck:
    /// `MultiDatePicker` öffnet immer im laufenden Monat, auch wenn der
    /// gewählte Tag im Mai liegt — ohne diese Zeile sähe es aus, als wäre
    /// beim Umschalten die Auswahl verloren gegangen.
    static func selectionLine(habit: Habit,
                              days: Set<String>,
                              calendar: Calendar = .current) -> String {
        let summary = selection(habit: habit, days: days)
        guard summary.count == 1, let only = days.first else { return selectionText(summary) }
        return String(localized: "\(selectionText(summary)) · \(dayText(only, calendar: calendar))")
    }

    static func selectionText(_ selection: Selection) -> String {
        guard selection.count > 0 else { return String(localized: "Keine Tage ausgewählt") }
        let chosen = selection.count == 1
            ? String(localized: "1 Tag ausgewählt")
            : String(localized: "\(selection.count) Tage ausgewählt")
        guard selection.done > 0 else { return chosen }
        return String(localized: "\(chosen) · \(selection.done) bereits erledigt")
    }

    // MARK: – Text

    /// Der Zustand als Satzstück. Bei Ja/Nein spricht die Zeile die Sprache
    /// der Frage: „Unbeantwortet", „Ja", „Nein".
    static func statusText(for state: DayState, kind: HabitKind = .checkbox) -> String {
        switch state {
        case .empty:
            return kind == .yesNo
                ? String(localized: "Unbeantwortet")
                : String(localized: "Kein Eintrag")
        case .done:
            return kind == .yesNo
                ? String(localized: "Ja")
                : String(localized: "Erledigt")
        case .declined:
            return String(localized: "Nein")
        case let .quantity(value, target):
            return value >= target
                ? String(localized: "Erledigt (\(value)/\(target))")
                : String(localized: "\(value)/\(target)")
        }
    }

    /// Der gewählte Tag als Datum — mit Wochentag, weil „nachtragen" fast
    /// immer über einen Wochentag gedacht wird („der Dienstag fehlt noch").
    static func dayText(_ key: String, calendar: Calendar = .current) -> String {
        guard let date = DayKey.date(from: key, calendar: calendar) else { return key }
        return date.formatted(.dateTime.weekday(.abbreviated)
            .day().month(.abbreviated).year())
    }

    /// Die Statuszeile der Karte: WELCHER Tag und WIE er gerade steht. Sie
    /// steht unter dem Picker und ändert sich mit jeder Wahl und jedem
    /// Schreibvorgang — deshalb hier und nicht als zwei Texte in der Ansicht.
    static func statusLine(habit: Habit, day: String, calendar: Calendar = .current) -> String {
        let text = statusText(for: state(habit: habit, day: day), kind: habit.kind)
        return String(localized: "\(dayText(day, calendar: calendar)) · \(text)")
    }
}
