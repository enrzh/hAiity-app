import WidgetKit
import SwiftUI

/// Ein Zeitpunkt im Widget-Verlauf: der Stand der aktiven Habits.
///
/// Der Eintrag trägt ALLES, was gezeichnet wird — die Extension hat keine
/// Umgebung von der App. Deshalb reisen hier auch die Farben mit (global +
/// eigene Paletten) und die im Widget EINGESTELLTE Habit-Kennung.
struct HaiityEntry: TimelineEntry {
    let date: Date
    let habits: [Habit]
    /// Globale Farbe UND eigene Paletten aus derselben data.json. Das Widget
    /// hat keine Umgebung von der App — die Farbe muss im Eintrag stehen,
    /// sonst bliebe der Homescreen grün, während die App längst blau ist. Die
    /// eigenen Paletten reisen mit, weil ein Habit auf eine davon zeigen kann.
    var palettes: PaletteBook = PaletteBook()
    /// Der in DIESER Widget-Instanz gewählte Habit; nil = „automatisch"
    /// (der empfohlene). Kommt aus dem `WidgetConfigurationIntent`.
    var selected: UUID?
    /// Die Quelle des reinen Graph-Widgets. Andere Widgettypen lassen diesen
    /// Wert auf `.habit` und behalten damit ihr bisheriges Verhalten.
    var graphSource: GraphWidgetSource = .habit
    /// Eine explizite Farbe für dieses Graph-Widget. `nil` behält die
    /// bisherige Habit-/Global-Auflösung.
    var selectedPalette: PaletteRef?
    /// Öffentliche GitHub-Daten, wenn dieses Graph-Widget GitHub gewählt hat.
    /// Nie ein Token und nie ein Credential.
    var githubSnapshot: GitHubContributionSnapshot?

    /// Der Habit, den diese Instanz zeigt — Auswahl schlägt Empfehlung,
    /// Empfehlung ist die längste laufende Serie.
    var habit: Habit? {
        guard graphSource == .habit else { return nil }
        return WidgetLogic.resolve(habits: habits, selected: selected)
    }

    /// Die Farbe des Graph-Widgets: eine explizite Widget-Auswahl schlägt die
    /// Habit-Farbe, danach gilt die bestehende globale Auflösung.
    var resolvedGraphPalette: PaletteStyle {
        selectedPalette?.style(customs: palettes.customs)
            ?? palettes.style(for: habit)
    }

    /// Platzhalter für Galerie und Vorschau: genug Historie, damit das
    /// Raster nicht leer aussieht, und mehrere Habits für die Übersicht.
    static var demo: HaiityEntry {
        var reading = Habit(name: String(localized: "Lesen"), emoji: "📚")
        var water = Habit(name: String(localized: "Wasser"), emoji: "💧",
                          recurrence: Recurrence(target: 3))
        var sport = Habit(name: String(localized: "Sport"), emoji: "🏃",
                          recurrence: .weekdays([2, 4, 6]))
        for i in 0..<370 {
            guard let k = DayKey.shifted(DayKey.today(), by: -i) else { continue }
            if i % 4 != 0 { reading.log[k] = 1 }
            if i % 3 != 0 { water.log[k] = (i % 3) + 2 }
            if i % 7 == 1 || i % 7 == 3 || i % 7 == 5 { sport.log[k] = 1 }
        }
        return HaiityEntry(date: .now, habits: [reading, water, sport])
    }
}

// MARK: – Der heutige Zustand EINES Habits

/// Was die Kopfzeile über heute sagt. Bewusst ein Aufzählungstyp und kein
/// fertiger String: die Auswahl ist die Logik (und wird getestet), der Text
/// ist nur ihre Übersetzung.
enum WidgetStatus: Equatable {
    /// Heute zählt — auch als Bonus an einem terminfreien Tag.
    case done
    /// Heute ist ein Termin und er ist noch offen.
    case open
    /// Heute ausdrücklich mit NEIN beantwortet (nur Ja/Nein-Habits). Ein
    /// eigener Fall und nicht `.open`: der Tag ist entschieden, nur eben
    /// negativ — „Heute noch offen" wäre schlicht falsch.
    case declined
    /// Heute ist KEIN Termin. `next` ist der Calendar-Wochentag des nächsten
    /// (1 = So … 7 = Sa); nil, wenn keiner mehr kommt.
    case free(next: Int?)
}

/// Reine Widget-Logik — ohne SwiftUI-Zustand, ohne Store, mit injiziertem
/// Kalender. Alles hier ist im Unit-Test nachrechenbar; die Views daneben
/// treffen keine Entscheidungen mehr, sie zeichnen nur.
enum WidgetLogic {

    // MARK: – Welcher Habit?

    /// Auswahl schlägt Empfehlung: die eingestellte Kennung, wenn es sie noch
    /// gibt, sonst der empfohlene Habit. Ein gelöschter oder archivierter
    /// Habit lässt das Widget also nicht leer stehen — es fällt zurück,
    /// statt „Noch keine Habits" zu behaupten.
    static func resolve(habits: [Habit],
                        selected: UUID?,
                        today: String = DayKey.today(),
                        calendar: Calendar = .current) -> Habit? {
        let active = habits.filter { $0.archivedAt == nil && $0.isTrackedHabit }
        if let selected, let hit = active.first(where: { $0.id == selected }) { return hit }
        return recommended(habits: active, today: today, calendar: calendar)
    }

    /// Der Habit, den ein NICHT eingestelltes Widget zeigt: der mit der
    /// LÄNGSTEN laufenden Serie.
    ///
    /// Vorher war es blind der erste der Liste. Das ist die falsche Antwort
    /// auf „zeig mir was" — die Liste ist nach Anlagedatum sortiert, und der
    /// zuerst angelegte Habit ist oft genau der, der längst eingeschlafen
    /// ist. Ein Graph ohne Zellen ist kein Graph. Die laufende Serie ist die
    /// einzige Zahl, die ohne weitere Annahmen sagt „hier passiert gerade
    /// etwas", und sie ist genau die Zahl, die der Nutzer nicht abreißen
    /// lassen will.
    ///
    /// Bei Gleichstand — und der ist der Normalfall, etwa in einem frischen
    /// Store, in dem jede Serie 0 ist — gewinnt der ERSTE: die Empfehlung
    /// darf nicht bei jedem Zeitstrahl-Aufbau eine andere sein.
    static func recommended(habits: [Habit],
                            today: String = DayKey.today(),
                            calendar: Calendar = .current) -> Habit? {
        var best: (habit: Habit, streak: Int)?
        for habit in habits where habit.archivedAt == nil && habit.isTrackedHabit {
            let streak = habit.streak(today: today, calendar: calendar)
            if best == nil || streak > best!.streak { best = (habit, streak) }
        }
        return best?.habit
    }

    // MARK: – Heute

    /// Genau die Unterscheidung, die auch die Karte in der App trifft: ein
    /// Habit, der heute gar nicht dran ist, darf nicht „Heute noch offen"
    /// sagen. Erledigt gewinnt trotzdem — ein Bonus-Check-in an einem freien
    /// Tag zählt (siehe GoalEngine) und soll auch so aussehen.
    static func status(habit: Habit,
                       today: String = DayKey.today(),
                       calendar: Calendar = .current) -> WidgetStatus {
        if GoalEngine.dayCounts(habit: habit, day: today, calendar: calendar) { return .done }
        // VOR der Termin-Frage: eine Verneinung gilt auch an einem Tag, an
        // dem gar nichts fällig war (dieselbe Regel wie in der GoalEngine).
        if habit.isDeclined(today) { return .declined }
        if GoalEngine.isScheduled(habit: habit, day: today, calendar: calendar) { return .open }
        guard let next = habit.recurrence.nextOccurrence(after: today, calendar: calendar),
              let date = DayKey.date(from: next, calendar: calendar) else { return .free(next: nil) }
        return .free(next: calendar.component(.weekday, from: date))
    }

    /// Der Satz dazu. Kurz genug für ein kleines Widget.
    static func statusText(_ status: WidgetStatus, calendar: Calendar = .current) -> String {
        switch status {
        case .done:
            return String(localized: "✓ Heute erledigt")
        case .open:
            return String(localized: "Heute noch offen")
        case .declined:
            return String(localized: "✗ Heute Nein")
        case .free(nil):
            return String(localized: "Keine Termine mehr")
        case .free(let weekday?):
            return String(localized: "Frei bis \(RecurrenceText.shortWeekdayName(weekday, calendar: calendar))")
        }
    }

    // MARK: – Der Tagesring

    /// Wie viel von heute steht? Gemessen an den HEUTE FÄLLIGEN Habits —
    /// ein Habit, der heute gar keinen Termin hat, steht in keinem der beiden
    /// Werte (dieselbe Regel wie in der Abend-Zusammenfassung).
    struct DayProgress: Equatable {
        /// Heute fällige aktive Habits.
        let due: Int
        /// Davon erfüllte.
        let met: Int

        /// 0…1. Ohne fälligen Habit ist der Tag VOLL — ein leerer Ring an
        /// einem Ruhetag läse sich wie ein Versäumnis.
        var fraction: Double {
            guard due > 0 else { return 1 }
            return min(1, max(0, Double(met) / Double(due)))
        }

        /// Heute ist gar nichts fällig.
        var isFree: Bool { due == 0 }
        /// Alles Fällige steht.
        var isComplete: Bool { due > 0 && met >= due }
    }

    static func progress(habits: [Habit],
                         today: String = DayKey.today(),
                         calendar: Calendar = .current) -> DayProgress {
        var due = 0, met = 0
        for habit in habits where habit.archivedAt == nil && habit.isTrackedHabit {
            guard GoalEngine.isScheduled(habit: habit, day: today, calendar: calendar) else { continue }
            due += 1
            if GoalEngine.dayCounts(habit: habit, day: today, calendar: calendar) { met += 1 }
        }
        return DayProgress(due: due, met: met)
    }

    // MARK: – Die Übersicht

    /// Was in eine Übersicht passt, und wie viel darunter noch liegt. Die
    /// Reihenfolge bleibt die der Liste — eine Übersicht, die ihre Zeilen
    /// selbst umsortiert, ist beim nächsten Blick eine andere Übersicht.
    static func roster(_ habits: [Habit], limit: Int) -> (visible: [Habit], overflow: Int) {
        let active = habits.filter { $0.archivedAt == nil && $0.isTrackedHabit }
        guard limit > 0 else { return ([], active.count) }
        return (Array(active.prefix(limit)), max(0, active.count - limit))
    }

    /// Zeilen je Größe. Konstanten statt Magie in der View, damit der Test
    /// dieselbe Zahl sieht wie das Layout.
    static let rosterRowsMedium = 3
    static let rosterRowsLarge = 7

    static func rosterLimit(for family: WidgetFamily) -> Int {
        family == .systemLarge ? rosterRowsLarge : rosterRowsMedium
    }

    // MARK: – Zeitplan der Timeline

    /// Nächster Refresh: Mitternacht — der „heute"-Rahmen wandert, und ein
    /// „Frei bis Mo" ist am Montag falsch.
    static func nextMidnight(after date: Date = .now, calendar: Calendar = .current) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        return calendar.startOfDay(for: tomorrow)
    }
}

// MARK: – Rastergeometrie

/// Wie groß werden die Zellen, und wie viele Wochen passen dann nebeneinander?
///
/// EIN Band, immer: sieben Zeilen (So…Sa) von links nach rechts, heute in der
/// letzten Spalte. Genau so sieht GitHubs eigenes Widget aus — und das ist
/// nicht bloß Geschmack, sondern das, was ein Contribution-Graph IST. Ein
/// gewickeltes Jahr sieht aus wie ein QR-Code: die Zeilen bedeuten dann nicht
/// mehr „Montag", die Spalten nicht mehr „eine Woche", und der Sprung von
/// Bandende zu Bandanfang ist ein Zeitsprung, den niemand liest.
///
/// Die Rechnung hat deshalb nur EINE Richtung:
///
///  1. **Die Höhe bestimmt die Zelle.** Sieben Zeilen plus sechs Lücken füllen
///     die Fläche vollständig — daraus fällt die Kantenlänge.
///  2. **Die Breite bestimmt die Wochenzahl.** So viele Spalten, wie bei
///     DIESER Kantenlänge nebeneinander stehen; danach wird die Teilung noch
///     einmal minimal gestaucht, damit die letzte Spalte genau an der rechten
///     Kante endet statt einen leeren Streifen zu lassen.
///
/// Nie umgekehrt: die Zelle wird nicht kleiner gerechnet, um eine Wunsch-
/// Wochenzahl unterzubringen. Ein halbes Jahr aus 4-pt-Punkten ist keine
/// Information mehr, sondern Textur.
enum GraphLayout {
    static let rows = GridCalendar.rows

    struct Layout: Equatable {
        /// Gezeigte Wochen — Spalten im Band.
        let weeks: Int
        let cell: CGFloat
        let gap: CGFloat

        var pitch: CGFloat { cell + gap }
        var contentWidth: CGFloat { CGFloat(weeks) * pitch - gap }
        var contentHeight: CGFloat { CGFloat(rows) * pitch - gap }
        /// Eckradius im Verhältnis zur Zelle — GitHubs 2 px auf 10 px.
        var radius: CGFloat { max(0.5, cell * 0.2) }
    }

    private static let gapRatio: CGFloat = 0.17

    private static func gap(for pitch: CGFloat) -> CGFloat {
        max(0.5, (pitch * gapRatio).rounded())
    }

    /// Die LETZTEN `weeks` Wochen als EIN Band, das die Fläche ausfüllt.
    ///
    /// `minCell` ist kein Auswahlkriterium mehr (es gibt nichts auszuwählen),
    /// sondern der Boden für entartete Flächen: eine Zelle unter einem halben
    /// Punkt zeichnet nichts, und ein Layout mit 0 pt Kantenlänge würde
    /// SwiftUI eine Division durch null unterschieben.
    static func trailing(width: CGFloat,
                         height: CGFloat,
                         maxWeeks: Int = 53,
                         minCell: CGFloat = 1) -> Layout {
        guard width > 0, height > 0, maxWeeks > 0 else {
            return Layout(weeks: 1, cell: max(minCell, 1), gap: 1)
        }
        // 1. Aus der HÖHE: sieben Zeilen und sechs Lücken füllen sie ganz.
        //    Die Lücke hängt an der Teilung, die Teilung an der Lücke —
        //    deshalb erst schätzen, dann exakt nachziehen.
        let g = gap(for: height / CGFloat(rows))
        let byHeight = (height + g) / CGFloat(rows)
        // 2. Aus der BREITE: so viele Spalten wie bei diesem Maß hineinpassen.
        //    Gerundet, nicht abgeschnitten — bei 16,6 Spalten ist ein um 2 %
        //    gestauchtes 17er-Band randlos, ein 16er ließe eine ganze Zelle
        //    Rand stehen.
        let fitting = Int(((width + g) / byHeight).rounded())
        let weeks = max(1, min(maxWeeks, fitting))
        // 3. Genau in die Breite legen — aber nie über das Höhenmaß hinaus,
        //    sonst liefe das Band unten aus der Fläche.
        let pitch = min(byHeight, (width + g) / CGFloat(weeks))
        return Layout(weeks: weeks, cell: max(minCell, pitch - g), gap: g)
    }
}
