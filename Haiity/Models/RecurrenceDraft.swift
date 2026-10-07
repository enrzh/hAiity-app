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

    /// Legacy values remain for decoding old rules; the editor uses the
    /// start date and an editable list of additional dates.
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
    /// Monthly entries store only the day. Yearly entries keep the month and
    /// day together so editing one never changes another entry implicitly.
    var multipleDays: Set<Int> = []
    var multipleMonthDays: Set<Recurrence.MonthDay> = []
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
            if frequency == .yearly {
                let dates = Set(multipleMonthDays.compactMap { $0.sanitized })
                if !dates.isEmpty { return .multipleMonthDays(dates) }
                let datesFromLegacyDays = Set(multipleDays.compactMap {
                    Recurrence.MonthDay(month: month, day: $0).sanitized
                })
                if !datesFromLegacyDays.isEmpty { return .multipleMonthDays(datesFromLegacyDays) }
            } else {
                let days = Set(multipleDays.filter { (1...31).contains($0) })
                if !days.isEmpty { return .multipleDays(days) }
            }
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

    /// Product defaults apply only to a new item, never to loaded rules.
    init(itemType: HabitItemType, today: Date = Date(), calendar: Calendar = .current) {
        self.init(today: today, calendar: calendar)
        frequency = itemType == .habit ? .daily : .once
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
            if recurrence.frequency == .yearly {
                multipleMonthDays = Set(multipleDays.compactMap {
                    Recurrence.MonthDay(month: recurrence.month ?? month, day: $0).sanitized
                })
            }
        case .multipleMonthDays(let dates)?:
            monthlyMode = .dayOfMonth
            multipleDaysEnabled = true
            multipleMonthDays = Set(dates.compactMap { $0.sanitized })
            if let first = multipleMonthDays.sorted().first {
                month = first.month
                dayOfMonth = first.day
            }
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
            if frequency == .yearly {
                multipleMonthDays.insert(Recurrence.MonthDay(month: month, day: dayOfMonth))
            } else if frequency == .monthly {
                multipleDays.insert(dayOfMonth)
            }
        }
    }

    mutating func setMultipleDaysEnabled(_ enabled: Bool,
                                         calendar: Calendar = .current) {
        multipleDaysEnabled = enabled
        preservedLegacyMonthlyRule = nil
        guard enabled else { return }
        if frequency == .yearly {
            if multipleMonthDays.isEmpty {
                multipleMonthDays = [Recurrence.MonthDay(
                    month: calendar.component(.month, from: start),
                    day: calendar.component(.day, from: start))]
            }
        } else if multipleDays.isEmpty {
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

    /// Adds a new entry or replaces an existing one in the list editor.
    mutating func setMultipleDate(_ date: Date,
                                  replacing original: Recurrence.MonthDay? = nil,
                                  calendar: Calendar = .current) {
        let value = Recurrence.MonthDay(
            month: calendar.component(.month, from: date),
            day: calendar.component(.day, from: date))
        preservedLegacyMonthlyRule = nil
        multipleDaysEnabled = true

        if frequency == .yearly {
            if let original { multipleMonthDays.remove(original) }
            multipleMonthDays.insert(value)
        } else {
            if let original { multipleDays.remove(original.day) }
            multipleDays.insert(value.day)
        }
    }

    /// Removes an entry. Removing the final entry turns the optional list off
    /// and returns to the primary date instead of creating an empty rule.
    mutating func removeMultipleDate(_ value: Recurrence.MonthDay) {
        preservedLegacyMonthlyRule = nil
        if frequency == .yearly {
            multipleMonthDays.remove(value)
            if multipleMonthDays.isEmpty {
                multipleDaysEnabled = false
            }
        } else {
            multipleDays.remove(value.day)
            if multipleDays.isEmpty {
                multipleDaysEnabled = false
            }
        }
    }

    var sortedMultipleDates: [Recurrence.MonthDay] {
        if frequency == .yearly {
            return multipleMonthDays.sorted()
        }
        return multipleDays.sorted().map { Recurrence.MonthDay(month: 1, day: $0) }
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
        multipleMonthDays = Set(multipleMonthDays.compactMap { $0.sanitized })
        if multipleDaysEnabled {
            if frequency == .yearly, multipleMonthDays.isEmpty {
                multipleMonthDays = [Recurrence.MonthDay(
                    month: calendar.component(.month, from: start),
                    day: calendar.component(.day, from: start))]
            } else if frequency == .monthly, multipleDays.isEmpty {
                multipleDays = [calendar.component(.day, from: start)]
            }
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
        if newFrequency == .yearly, multipleDaysEnabled, multipleMonthDays.isEmpty {
            multipleMonthDays = Set(multipleDays.compactMap {
                Recurrence.MonthDay(month: month, day: $0).sanitized
            })
        } else if newFrequency == .monthly, multipleDaysEnabled, multipleDays.isEmpty {
            multipleDays = Set(multipleMonthDays.map(\.day))
        }
        frequency = newFrequency
        if newFrequency == .monthly || newFrequency == .yearly {
            interval = 1
        }
        normalize(calendar: calendar)
    }

    mutating func setRepeats(_ enabled: Bool, calendar: Calendar = .current) {
        hasStart = true
        selectFrequency(enabled ? (frequency == .once ? .daily : frequency) : .once,
                        calendar: calendar)
    }

    /// Any-day weeks reuse the existing quota. Clear an agreement only when
    /// explicitly enabling this option; loading a legacy rule keeps it intact.
    mutating func setFlexibleWeek(_ enabled: Bool, calendar: Calendar = .current) {
        guard frequency == .weekly else { return }
        flexible = enabled
        if enabled { weekdays = [] }
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
    static let defaultHour = Habit.defaultNotificationMinutes / 60
}
