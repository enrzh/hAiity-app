import Foundation

/// Der Bearbeitungs-Zustand des Regel-Editors, als reiner Wert.
///
/// Er liegt bewusst NICHT als ein Dutzend `@State`-Variablen in der Ansicht:
/// so ist der Weg Regel -> Formular -> Regel prüfbar, ohne die Oberfläche zu
/// starten. Das Formular hat mehr Knöpfe als das Modell Felder (der Monats-
/// modus ist eine Auswahl aus drei Formen, das Ende eine aus dreien), und
/// genau in dieser Übersetzung stecken die Fehler, die man sonst erst im
/// Simulator sieht.
///
/// Ein Grundsatz: **Umschalten verliert nichts.** Wer von „monatlich" auf
/// „wöchentlich" und zurück geht, findet seinen 3. Dienstag wieder — die
/// Felder aller Häufigkeiten bleiben nebeneinander stehen, gebaut wird nur
/// die gerade gewählte.
struct RecurrenceDraft: Equatable {

    /// Die drei Formen, in denen ein Monatstag benannt werden kann.
    enum MonthlyMode: String, CaseIterable, Equatable { case dayOfMonth, lastDay, nthWeekday }

    /// Die drei Enden.
    enum EndMode: String, CaseIterable, Equatable { case never, onDate, afterCount }

    var frequency: Recurrence.Frequency = .daily
    var interval = 1
    var weekdays: Set<Int> = []
    /// „Feste Anzahl statt fester Tage" — das flexible Ziel.
    var flexible = false
    var times = 3
    var monthlyMode: MonthlyMode = .dayOfMonth
    var dayOfMonth = 1
    /// 1…5 oder `Recurrence.DayRule.last`.
    var nth = 1
    var nthWeekday = 2
    var month = 1
    /// Hat die Regel überhaupt ein Startdatum? Migrierte Alt-Ziele haben
    /// keins („gilt schon immer"), und das darf ihnen beim Bearbeiten nicht
    /// versehentlich verpasst werden: ein nachträglicher Start macht jeden
    /// Tag davor terminfrei und würde Quoten rückwirkend verändern.
    var hasStart = true
    var start = Date()
    var endMode: EndMode = .never
    var endDate = Date()
    var endCount = 10
    var quantity = false
    var target = 3

    // MARK: – Formular -> Regel

    func recurrence(calendar: Calendar = .current) -> Recurrence {
        Recurrence(frequency: frequency,
                   interval: interval,
                   weekdays: frequency == .weekly ? weekdays : [],
                   rule: rule,
                   month: month,
                   start: hasStart ? DayKey.key(for: start, calendar: calendar) : nil,
                   end: end(calendar: calendar),
                   timesPerPeriod: flexible && frequency != .daily ? times : nil,
                   target: quantity ? target : nil)
    }

    private var rule: Recurrence.DayRule? {
        switch monthlyMode {
        case .dayOfMonth: return .dayOfMonth(dayOfMonth)
        case .lastDay: return .lastDayOfMonth
        case .nthWeekday: return .nthWeekday(nth: nth, weekday: nthWeekday)
        }
    }

    private func end(calendar: Calendar) -> Recurrence.End {
        switch endMode {
        case .never: return .never
        case .onDate: return .on(DayKey.key(for: endDate, calendar: calendar))
        case .afterCount: return .after(endCount)
        }
    }

    // MARK: – Regel -> Formular

    /// Neu anlegen: heute als Start, alles andere auf sinnvollen Vorgaben
    /// (der heutige Wochentag, der heutige Monatstag, der heutige Monat) —
    /// so steht beim Umschalten der Häufigkeit nie eine 1. Januar-Regel da.
    init(today: Date = Date(), calendar: Calendar = .current) {
        start = today
        endDate = calendar.date(byAdding: .month, value: 3, to: today) ?? today
        weekdays = [calendar.component(.weekday, from: today)]
        nthWeekday = calendar.component(.weekday, from: today)
        dayOfMonth = calendar.component(.day, from: today)
        month = calendar.component(.month, from: today)
        nth = min(5, (calendar.component(.day, from: today) - 1) / 7 + 1)
    }

    init(_ recurrence: Recurrence, today: Date = Date(), calendar: Calendar = .current) {
        self.init(today: today, calendar: calendar)
        frequency = recurrence.frequency
        interval = recurrence.interval
        // Bewusst auch die LEERE Menge übernehmen: „wöchentlich ohne Tage"
        // ist eine echte (wenn auch stille) Regel und darf beim Laden nicht
        // heimlich einen Tag dazubekommen.
        weekdays = recurrence.weekdays
        flexible = recurrence.isFlexible
        if let times = recurrence.timesPerPeriod { self.times = times }
        if let month = recurrence.month { self.month = month }
        switch recurrence.rule {
        case .dayOfMonth(let day)?:
            monthlyMode = .dayOfMonth
            dayOfMonth = day
        case .lastDayOfMonth?:
            monthlyMode = .lastDay
        case .nthWeekday(let nth, let weekday)?:
            monthlyMode = .nthWeekday
            self.nth = nth
            nthWeekday = weekday
        case nil:
            break
        }
        // Ohne Start („gilt schon immer", so kommen migrierte Alt-Ziele
        // herein) bleibt der Schalter AUS — das Feld zeigt dann heute, ohne
        // dass Sichern daraus einen Start machen würde.
        hasStart = recurrence.start != nil
        if let day = recurrence.start, let date = DayKey.date(from: day, calendar: calendar) {
            start = date
        }
        switch recurrence.end {
        case .never:
            endMode = .never
        case .on(let day):
            endMode = .onDate
            if let date = DayKey.date(from: day, calendar: calendar) { endDate = date }
        case .after(let n):
            endMode = .afterCount
            endCount = n
        }
        if let target = recurrence.target {
            quantity = true
            self.target = target
        }
    }

    // MARK: – Sanft nachziehen

    /// Beim Umschalten der Häufigkeit: was in der neuen Form keinen Sinn
    /// ergibt, wird still korrigiert — eine leere Wochentagsmenge (die
    /// „keine Termine" hieße) bekommt den Tag des Starts, und „täglich"
    /// kennt kein flexibles Ziel.
    ///
    /// Läuft NUR auf Nutzeraktion (Umschalten), nie beim Laden oder Sichern:
    /// wer alle Chips bewusst abwählt, soll seine stille Regel behalten und
    /// nicht beim Sichern einen erfundenen Montag zurückbekommen.
    mutating func normalize(calendar: Calendar = .current) {
        if frequency == .weekly, !flexible, weekdays.isEmpty {
            weekdays = [calendar.component(.weekday, from: start)]
        }
        if frequency == .daily { flexible = false }
        interval = min(Recurrence.maxInterval, max(1, interval))
        times = min(Recurrence.maxTimes(for: frequency), max(1, times))
        endCount = min(Recurrence.maxOccurrences, max(1, endCount))
    }

    /// Der Satz, der im Editor unter den Knöpfen steht.
    func summary(calendar: Calendar = .current) -> String {
        RecurrenceText.summary(recurrence(calendar: calendar), calendar: calendar)
    }
}
