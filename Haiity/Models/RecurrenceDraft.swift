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

    /// Legacy values remain for decoding old rules; the editor now uses the
    /// start date and an optional set of day numbers.
    enum MonthlyMode: String, CaseIterable, Equatable { case dayOfMonth, lastDay, nthWeekday }

    /// Die drei Enden.
    enum EndMode: String, CaseIterable, Equatable { case never, onDate, afterCount }

    var frequency: Recurrence.Frequency = .once
    var interval = 1
    var weekdays: Set<Int> = []
    /// „Feste Anzahl statt fester Tage" — das flexible Ziel.
    var flexible = false
    var times = 3
    var monthlyMode: MonthlyMode = .dayOfMonth
    var dayOfMonth = 1
    var multipleDaysEnabled = false
    var multipleDays: Set<Int> = []
    /// Keep old last-day/nth-weekday rules stable until the user edits the
    /// date or the new multi-day option.
    private var preservedLegacyMonthlyRule: Recurrence.DayRule?
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
    var endTitle = ""
    var quantity = false
    var target = 3
    /// Hat der Habit eine Uhrzeit? Sie gehört NICHT zur Regel (die Regel
    /// benennt Tage) und wird deshalb auch nicht in `recurrence()`
    /// eingebaut — sie liegt am Habit (`Habit.timeMinutes`). Hier steht sie
    /// trotzdem, weil sie im selben Abschnitt eingestellt wird und im selben
    /// Satz vorgelesen wird: „Jeden Montag um 07:30".
    var hasTime = false
    var time = Date()

    /// Monthly and yearly recurrence use the date at the top of the editor as
    /// their single cadence anchor. Only daily and weekly rules expose an
    /// adjustable interval in the form.
    var showsIntervalStepper: Bool {
        frequency == .daily || frequency == .weekly
    }

    // MARK: – Formular -> Regel

    func recurrence(calendar: Calendar = .current) -> Recurrence {
        let startDay: String?
        if frequency == .once {
            startDay = DayKey.key(for: start, calendar: calendar)
        } else {
            startDay = hasStart ? DayKey.key(for: start, calendar: calendar) : nil
        }

        return Recurrence(frequency: frequency,
                          interval: interval,
                          weekdays: frequency == .weekly ? weekdays : [],
                          rule: rule,
                          month: month,
                          start: startDay,
                          end: frequency == .once ? .never : end(calendar: calendar),
                          endTitle: nil,
                          timesPerPeriod: flexible && frequency != .daily ? times : nil,
                          target: quantity ? target : nil)
    }

    private var rule: Recurrence.DayRule? {
        guard frequency == .monthly || frequency == .yearly else { return nil }
        if multipleDaysEnabled {
            let days = Set(multipleDays.filter { (1...31).contains($0) })
            if !days.isEmpty { return .multipleDays(days) }
        }
        if let preservedLegacyMonthlyRule { return preservedLegacyMonthlyRule }
        return .dayOfMonth(dayOfMonth)
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
        var clock = calendar.dateComponents([.year, .month, .day], from: today)
        clock.hour = Self.defaultHour
        clock.minute = 0
        time = calendar.date(from: clock) ?? today
        weekdays = [calendar.component(.weekday, from: today)]
        nthWeekday = calendar.component(.weekday, from: today)
        dayOfMonth = calendar.component(.day, from: today)
        month = calendar.component(.month, from: today)
        nth = min(5, (calendar.component(.day, from: today) - 1) / 7 + 1)
    }

    init(_ recurrence: Recurrence,
         timeMinutes: Int? = nil,
         today: Date = Date(),
         calendar: Calendar = .current) {
        self.init(today: today, calendar: calendar)
        if let minutes = Habit.sanitizedMinutes(timeMinutes) {
            hasTime = true
            var clock = calendar.dateComponents([.year, .month, .day], from: today)
            clock.hour = minutes / 60
            clock.minute = minutes % 60
            if let date = calendar.date(from: clock) { time = date }
        }
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
            preservedLegacyMonthlyRule = .lastDayOfMonth
        case .nthWeekday(let nth, let weekday)?:
            monthlyMode = .nthWeekday
            self.nth = nth
            nthWeekday = weekday
            preservedLegacyMonthlyRule = .nthWeekday(nth: nth, weekday: weekday)
        case .multipleDays(let days)?:
            monthlyMode = .dayOfMonth
            multipleDaysEnabled = true
            multipleDays = Set(days.filter { (1...31).contains($0) })
            dayOfMonth = multipleDays.sorted().first ?? dayOfMonth
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
        endTitle = recurrence.endTitle ?? ""
        if let target = recurrence.target {
            quantity = true
            self.target = target
        }
    }

    /// Select the single date shown at the top of the editor. It also updates
    /// the day/month components used by monthly and yearly rules.
    mutating func selectDate(_ date: Date, calendar: Calendar = .current) {
        start = date
        hasStart = true
        dayOfMonth = calendar.component(.day, from: date)
        month = calendar.component(.month, from: date)
        preservedLegacyMonthlyRule = nil
        if multipleDaysEnabled {
            multipleDays.insert(dayOfMonth)
        }
    }

    mutating func setMultipleDaysEnabled(_ enabled: Bool,
                                         calendar: Calendar = .current) {
        multipleDaysEnabled = enabled
        preservedLegacyMonthlyRule = nil
        guard enabled else { return }
        if multipleDays.isEmpty {
            multipleDays = [calendar.component(.day, from: start)]
        }
    }

    mutating func toggleMultipleDay(_ day: Int) {
        guard (1...31).contains(day) else { return }
        preservedLegacyMonthlyRule = nil
        if multipleDays.contains(day) {
            // Keep one selected day so the enabled mode never creates an
            // invalid empty monthly/yearly rule.
            guard multipleDays.count > 1 else { return }
            multipleDays.remove(day)
        } else {
            multipleDays.insert(day)
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
        if frequency == .daily || frequency == .once { flexible = false }
        multipleDays = Set(multipleDays.filter { (1...31).contains($0) })
        if multipleDaysEnabled, multipleDays.isEmpty {
            multipleDays = [calendar.component(.day, from: start)]
        }
        interval = min(Recurrence.maxInterval, max(1, interval))
        times = min(Recurrence.maxTimes(for: frequency), max(1, times))
        endCount = min(Recurrence.maxOccurrences, max(1, endCount))
    }

    /// Nutzerwechsel der Häufigkeit: dieselbe sanfte Korrektur wie bisher,
    /// aber ohne versteckte Nebenwirkung auf einen migrierten Start-losen
    /// Bestand. `.once` liest immer `start`, braucht dafür aber kein
    /// dauerhaft umgelegtes `hasStart`.
    mutating func selectFrequency(_ newFrequency: Recurrence.Frequency,
                                  calendar: Calendar = .current) {
        frequency = newFrequency
        if newFrequency == .monthly || newFrequency == .yearly {
            interval = 1
        }
        normalize(calendar: calendar)
    }

    /// Die eingestellte Uhrzeit als Minuten seit Mitternacht; nil = ohne.
    func timeMinutes(calendar: Calendar = .current) -> Int? {
        guard hasTime else { return nil }
        return calendar.component(.hour, from: time) * 60
            + calendar.component(.minute, from: time)
    }

    /// Der Satz, der im Editor unter den Knöpfen steht — samt Uhrzeit.
    func summary(calendar: Calendar = .current) -> String {
        RecurrenceText.summary(recurrence(calendar: calendar),
                               timeMinutes: timeMinutes(calendar: calendar),
                               calendar: calendar)
    }

    /// Vorgabe-Uhrzeit, wenn der Schalter eingeschaltet wird.
    static let defaultHour = 9
}
