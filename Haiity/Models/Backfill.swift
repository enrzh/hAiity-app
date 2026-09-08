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

    /// Die Zahl der Wochenzeilen, die der sichtbare Monat im Kalender belegt.
    /// Die Wochen folgen der Konfiguration des übergebenen Kalenders, damit
    /// Montag- und Sonntag-beginnende Kalender dieselbe Rechnung wie
    /// `UICalendarView` verwenden.
    static func calendarWeekRows(containing date: Date, calendar: Calendar = .current) -> Int {
        guard let month = calendar.dateInterval(of: .month, for: date),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: month.start),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: month.end),
              let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastDay)
        else { return 6 }

        var rows = 0
        var weekStart = firstWeek.start
        while weekStart <= lastWeek.start, rows < 6 {
            rows += 1
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) else {
                return 6
            }
            weekStart = next
        }
        return min(6, max(4, rows))
    }

    /// Höhe für genau die Wochenzeilen des sichtbaren Monats. Monatstitel
    /// und Wochentagskopf behalten die bewährte Dynamic-Type-Hüllkurve; nur
    /// das Raster wächst oder schrumpft beim Blättern zwischen vier und sechs
    /// Reihen.
    ///
    /// Der Skalierungsfaktor stammt aus `@ScaledMetric` relativ zu `.body`.
    /// Er hält den nativen Monats- und Wochentagskopf auch in größeren
    /// Dynamic-Type-Größen innerhalb der Karte; bei noch größeren
    /// Accessibility-Größen übernimmt der bestehende Scroll-Fallback.
    static func calendarHeight(width: CGFloat, weekRows: Int, typeScale: CGFloat = 1) -> CGFloat {
        let rows = CGFloat(min(6, max(4, weekRows))) * max(0, width) / 7
        // Auf einen vernünftigen Bereich geklemmt: eine Schriftskala von 0
        // oder 5 gibt es nicht, und ein Ausreißer soll die Karte nicht
        // zerlegen.
        let scale = min(2, max(0.5, typeScale))
        let header: CGFloat = scale <= 1
            ? 95 + 17 * (scale - 1)
            : min(95 + 46 * (scale - 1), 104.5)
        return (rows + header).rounded(.up)
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

        let kind: Kind
        let value: Int?

        var id: String { kind.rawValue }

        /// Bei Ja/Nein heißen die Knöpfe „Ja" und „Nein" und nicht
        /// „Erledigt"/„Nicht gemacht": das Habit stellt eine FRAGE („Kein
        /// Zucker?"), und man beantwortet eine Frage nicht mit „erledigt".
        /// The clear action is presented as „Rückgängig" because it restores
        /// the empty state directly from the backfill menu.
        var title: String {
            switch kind {
            case .done:     return String(localized: "Erledigt")
            case .affirmed: return String(localized: "Ja")
            case .declined: return String(localized: "Nein")
            case .quantity: return String(localized: "Eintragen")
            case .clear:    return String(localized: "Rückgängig")
            }
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
        /// Mengenziel: EXAKT der gewünschte Stand, nicht „einer mehr" —
        /// geklemmt auf das echte Zählerband (mindestens 1, nie hinein ins
        /// reservierte Antwortband, siehe `Habit.Answer`).
        static func quantity(target: Int) -> Action {
            Action(kind: .quantity, value: min(Habit.Answer.maxCount, max(1, target)))
        }
    }

    /// Welche Aktionen gibt es zu diesem Zustand?
    ///
    /// Bei Ja/Nein stehen die beiden Entscheidungen und das Leeren immer zur
    /// Verfügung. So ist „Rückgängig" schon beim Öffnen sichtbar und nicht
    /// erst nach einer neuen Entscheidung.
    ///
    /// Die Art muss mit hinein, weil `.done` bei einer Checkbox etwas
    /// anderes bedeutet als bei einer Frage — und vor allem einen anderen
    /// WERT schreibt.
    static func actions(for state: DayState, kind: HabitKind = .checkbox) -> [Action] {
        if kind == .yesNo {
            switch state {
            case .empty:    return [.affirm, .decline, .clear]
            case .done:     return [.decline, .clear]
            case .declined: return [.affirm, .clear]
            case .quantity: return [.affirm, .decline, .clear]   // unmöglich
            }
        }
        switch state {
        case .empty:
            return [.done, .clear]
        case .done:
            return [.clear]
        case .declined:
            // Bei Checkbox und Menge nicht erzeugbar — die Liste hätte den
            // Fall trotzdem: auf Ja drehen oder den Tag wieder leeren.
            return [.done, .clear]
        case let .quantity(value, target):
            var out: [Action] = []
            if value < target { out.append(.quantity(target: target)) }
            out.append(.clear)
            return out
        }
    }

    /// Bequemer Weg: Zustand UND Art kommen aus demselben Habit.
    static func actions(habit: Habit, day: String) -> [Action] {
        actions(for: state(habit: habit, day: day), kind: habit.kind)
    }

    // MARK: – Dekoration des Kalenderblatts

    /// Was unter einem Tag im Nacharbeiten-Kalender steht — der Punkt, der
    /// sagt, WAS an diesem Tag schon eingetragen ist. Reines Modell: die
    /// Farbe löst erst die Ansicht auf (Palette + Hell/Dunkel).
    ///
    /// **Warum nicht einfach `GoalEngine.intensity`.** Die Lauflängen-
    /// Schattierung des Rasters (längere Ketten leuchten heller) ist für
    /// einen 6-pt-Punkt unter einer Kalenderzahl zu fein — Stufe 1 wäre dort
    /// kaum vom Papier zu unterscheiden, und ein erledigter Tag sähe je nach
    /// Nachbarschaft anders aus, obwohl an IHM nichts anders ist. Ein
    /// erledigter/bejahter Tag bekommt deshalb IMMER die volle Stufe; nur
    /// die Menge schattiert (ihr Stand gegen das Ziel ist eine Eigenschaft
    /// des Tages selbst — dieselbe Ganzzahl-Rampe wie im Raster).
    enum Decoration: Equatable {
        /// Erledigt (Checkbox) bzw. mit Ja beantwortet: voller Farbpunkt.
        case affirmed
        /// Mit Nein beantwortet: die Verneinungsfarbe des Habits.
        case declined
        /// Menge: Rampenstufe 1…4 aus Stand gegen Ziel.
        case quantity(level: Int)

        /// Die Rampenstufe für `Theme.level` — die EINE Brücke zur Farbe,
        /// an der schon Raster, Widgets und Teilen-Karte hängen.
        var level: Int {
            switch self {
            case .affirmed:            return 4
            case .declined:            return Habit.Answer.declinedLevel
            case let .quantity(level): return max(1, min(4, level))
            }
        }
    }

    /// Die Dekoration EINES Tages — nil heißt: kein Eintrag, kein Punkt.
    ///
    /// Fällt komplett aus `state` (dem einen abgeleiteten Tageszustand der
    /// Karte) plus — für die Mengenstufe — derselben Rechnung, die auch die
    /// Rasterzelle schattiert (`GoalEngine.intensity`).
    static func decoration(habit: Habit, day: String,
                           calendar: Calendar = .current) -> Decoration? {
        switch state(habit: habit, day: day) {
        case .empty:
            return nil
        case .done:
            return habit.kind == .quantity ? .quantity(level: 4) : .affirmed
        case .declined:
            return .declined
        case let .quantity(value, _):
            guard value >= 1 else { return nil }
            return .quantity(level: GoalEngine.intensity(habit: habit, key: day,
                                                         calendar: calendar))
        }
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

    /// Returns only writable days without an entry. Keeping this decision in
    /// the model lets the History editor offer a one-tap shortcut without
    /// duplicating date-boundary rules in the view.
    static func selectableMissingDays(habit: Habit,
                                      days: [String],
                                      today: String = DayKey.today(),
                                      calendar: Calendar = .current) -> [String] {
        days.filter { habit.log[$0] == nil && canWrite(habit: habit,
                                                        day: $0,
                                                        today: today,
                                                        calendar: calendar) }
    }

    /// Die Aktionen der Auswahl-Leiste („Auswählen"-Modus) — VOLLSTÄNDIG je
    /// Habit-Art, und jede gilt für ALLE gewählten Tage gleich.
    ///
    /// Früher gab es hier genau zwei („kein Mischen" hieß auch „kein Nein
    /// für alle"). Das war die Rückmeldung: Massen-Nein und Massen-Menge
    /// gingen schlicht nicht. Jetzt steht jeder Zielzustand der Art zur
    /// Wahl — einheitlich bleibt der Schreibvorgang trotzdem: EIN Wert für
    /// jeden gewählten Tag.
    ///
    /// `amount` ist der Stand des Mengen-Stellers in der Karte; ohne ihn
    /// gilt das Tagesziel. Für Checkbox und Ja/Nein ist er bedeutungslos.
    static func selectActions(habit: Habit, amount: Int? = nil) -> [Action] {
        switch habit.kind {
        case .yesNo:
            return [.affirm, .decline, .clear]
        case .quantity:
            return [.quantity(target: amount ?? habit.recurrence.target ?? 1), .clear]
        case .checkbox:
            return [.done, .clear]
        }
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
