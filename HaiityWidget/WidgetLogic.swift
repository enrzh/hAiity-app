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
    /// (der erste aktive). Kommt aus dem `WidgetConfigurationIntent`.
    var selected: UUID?

    /// Der Habit, den diese Instanz zeigt — Auswahl schlägt Automatik,
    /// Automatik ist der erste aktive Habit.
    var habit: Habit? { WidgetLogic.resolve(habits: habits, selected: selected) }

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
    /// Heute ist KEIN Termin. `next` ist der Calendar-Wochentag des nächsten
    /// (1 = So … 7 = Sa); nil, wenn keiner mehr kommt.
    case free(next: Int?)
}

/// Reine Widget-Logik — ohne SwiftUI-Zustand, ohne Store, mit injiziertem
/// Kalender. Alles hier ist im Unit-Test nachrechenbar; die Views daneben
/// treffen keine Entscheidungen mehr, sie zeichnen nur.
enum WidgetLogic {

    // MARK: – Welcher Habit?

    /// Auswahl schlägt Automatik: die eingestellte Kennung, wenn es sie noch
    /// gibt, sonst der erste aktive Habit. Ein gelöschter oder archivierter
    /// Habit lässt das Widget also nicht leer stehen — es fällt auf den
    /// ersten zurück, statt „Noch keine Habits" zu behaupten.
    static func resolve(habits: [Habit], selected: UUID?) -> Habit? {
        let active = habits.filter { $0.archivedAt == nil }
        if let selected, let hit = active.first(where: { $0.id == selected }) { return hit }
        return active.first
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
        for habit in habits where habit.archivedAt == nil {
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
        let active = habits.filter { $0.archivedAt == nil }
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

/// Wie viele Wochen passen in eine Fläche, und wie groß werden die Zellen?
///
/// Reine Rechnung, damit sich beide Fälle prüfen lassen:
///  * `trailing` — die LETZTEN Wochen: so viele, wie bei noch lesbarer Zelle
///    hineinpassen.
///  * `year` — das GANZE Jahr, egal wie klein die Zellen dafür werden.
///
/// Beide dürfen WICKELN, und beide müssen es können: sieben Zeilen mal
/// 53 Wochen sind 7,6-mal so breit wie hoch, es gibt also keine Widget-Fläche,
/// die ein Jahresband ausfüllt. In einer großen Fläche wäre es ein
/// 40-pt-Streifen in 350 pt Leere, in einer kleinen quadratischen zeigt ein
/// Band überhaupt nur sieben Wochen. Gewickelt läuft die Chronologie wie ein
/// Text: links→rechts, Band für Band nach unten, und endet unten rechts heute.
enum GraphLayout {
    static let rows = GridCalendar.rows

    struct Layout: Equatable {
        /// Insgesamt gezeigte Wochen.
        let weeks: Int
        /// Übereinanderliegende Bänder.
        let bands: Int
        /// Spalten je Band.
        let perBand: Int
        let cell: CGFloat
        let gap: CGFloat

        var pitch: CGFloat { cell + gap }
        /// Leere Spalten VOR der ältesten Woche — die Bänder sind rechteckig,
        /// 53 Wochen sind es selten. Die Lücke gehört an den Anfang, damit
        /// „heute" unten rechts sitzt.
        var pad: Int { max(0, bands * perBand - weeks) }
        var contentWidth: CGFloat { CGFloat(perBand) * pitch - gap }
        var contentHeight: CGFloat {
            CGFloat(bands * rows) * pitch - gap + CGFloat(max(0, bands - 1)) * pitch
        }
    }

    private static let gapRatio: CGFloat = 0.17

    private static func gap(for pitch: CGFloat) -> CGFloat {
        max(0.5, (pitch * gapRatio).rounded())
    }

    /// Die LETZTEN Wochen: so viele, wie bei noch lesbarer Zelle in die
    /// Fläche passen.
    ///
    /// `maxBands` ist der Unterschied zwischen einem Streifen und einem
    /// Block. Ein Streifen (`1`, der Standard) ist das, was neben Text steht
    /// — im Haupt-Widget, in einer Übersichtszeile, auf dem Sperrbildschirm.
    /// Der reine Graph darf wickeln: auf einer fast quadratischen kleinen
    /// Fläche zeigt EIN Band nur sieben Wochen mit riesigen Quadraten, zwei
    /// Bänder zeigen dreißig — dieselbe Fläche, viermal so viel Geschichte.
    ///
    /// Ausgewählt wird nach MEHR WOCHEN, aber nie unter `minCell`: ein
    /// halbes Jahr aus 4-pt-Punkten ist keine Information mehr, sondern
    /// Textur. Bei gleicher Wochenzahl gewinnt die größere Zelle.
    static func trailing(width: CGFloat,
                         height: CGFloat,
                         maxWeeks: Int = 53,
                         maxBands: Int = 1,
                         minCell: CGFloat = 6) -> Layout {
        guard width > 0, height > 0 else {
            return Layout(weeks: 1, bands: 1, perBand: 1, cell: max(1, minCell), gap: 1)
        }
        var best: Layout?
        for bands in 1...max(1, maxBands) {
            let slots = CGFloat(rows * bands + (bands - 1))
            let byHeight = height / slots
            guard byHeight > 0 else { continue }
            let fitting = Int((width / byHeight).rounded(.down))
            guard fitting >= 1 else { continue }
            let weeks = min(maxWeeks, bands * fitting)
            let perBand = Int((Double(weeks) / Double(bands)).rounded(.up))
            let pitch = min(byHeight, width / CGFloat(perBand))
            let g = gap(for: pitch)
            let candidate = Layout(weeks: weeks, bands: bands, perBand: perBand,
                                   cell: max(0.5, pitch - g), gap: g)
            guard let current = best else { best = candidate; continue }
            // Eine unlesbare Zelle verdrängt nie eine lesbare.
            guard candidate.cell >= minCell else { continue }
            let richer = candidate.weeks > current.weeks
                || (candidate.weeks == current.weeks && candidate.cell > current.cell)
            if current.cell < minCell || richer { best = candidate }
        }
        return best ?? Layout(weeks: 1, bands: 1, perBand: 1, cell: max(1, minCell), gap: 1)
    }

    /// Das ganze Jahr, gewickelt. Zwischen zwei Bändern bleibt genau eine
    /// Zellhöhe Luft — sonst laufen sie zu einer Fläche zusammen.
    static func year(width: CGFloat,
                     height: CGFloat,
                     weeks: Int = 53,
                     maxBands: Int = 6,
                     minCell: CGFloat = 3) -> Layout {
        guard width > 0, height > 0, weeks > 0 else {
            return Layout(weeks: max(1, weeks), bands: 1, perBand: max(1, weeks), cell: minCell, gap: 1)
        }
        var best = (pitch: CGFloat(0), bands: 1, perBand: weeks)
        for bands in 1...max(1, maxBands) {
            let perBand = Int((Double(weeks) / Double(bands)).rounded(.up))
            // Höhe: bands × 7 Zeilen plus (bands − 1) Leerzeilen dazwischen.
            let slots = CGFloat(rows * bands + (bands - 1))
            let pitch = min(width / CGFloat(perBand), height / slots)
            if pitch > best.pitch { best = (pitch, bands, perBand) }
        }
        let g = gap(for: best.pitch)
        return Layout(weeks: weeks, bands: best.bands, perBand: best.perBand,
                      cell: max(minCell, best.pitch - g), gap: g)
    }
}
