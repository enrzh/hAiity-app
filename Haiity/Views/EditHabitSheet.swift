import SwiftUI

/// Anlegen/Bearbeiten — als Half-Sheet präsentiert. Die Erinnerung ist der
/// EINZIGE Ort, der die Benachrichtigungs-Berechtigung auslösen darf — beim
/// aktiven Einschalten (unverändert).
///
/// Das Herz ist der Regel-Editor: Häufigkeit × Intervall, dazu die feine
/// Regel (Wochentage, Tag im Monat, n-ter Wochentag), Zeitraum und das
/// Mengenziel. Damit das nicht zu einem Formular wird, das man raten muss,
/// steht ganz oben in der Sektion EIN Satz, der die eingestellte Regel
/// vorliest — „Jeden 2. Montag und Donnerstag", „Am letzten Freitag im
/// Monat". Der Satz kommt aus `RecurrenceText` und ist als reine Funktion
/// getestet.
///
/// Der Zustand liegt in `RecurrenceDraft`, nicht in einem Dutzend
/// `@State`-Variablen: der Weg Regel -> Formular -> Regel ist damit prüfbar,
/// ohne den Simulator zu starten.
struct EditHabitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.palettes) private var palettes
    let store: HabitStore
    var existing: Habit?

    @State private var name = ""
    @State private var emoji = ""
    @State private var reminderOn = false
    @State private var reminderTime = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? .now
    @State private var permissionDenied = false

    /// Die ganze Regel als EIN Wert.
    @State private var draft = RecurrenceDraft()
    /// nil = „Wie App" (kein Override) — der Normalfall.
    @State private var habitPalette: PaletteRef?

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Name (z. B. 20 Minuten lesen)"), text: $name)
                        .accessibilityIdentifier("habit-name")
                    TextField(String(localized: "Emoji (optional)"), text: $emoji)
                        .accessibilityIdentifier("habit-emoji")
                }
                recurrenceSection
                periodSection
                quantitySection
                colorSection
                reminderSection
                if let habit = existing {
                    Section {
                        ShareLink(item: HabitShareImage(habit: habit, dark: scheme == .dark, palette: palettes.style(for: habit)),
                                  preview: SharePreview(habit.name)) {
                            Label(String(localized: "Als Bild teilen"), systemImage: "square.and.arrow.up")
                        }
                        Button {
                            store.archive(habit.id)
                            dismiss()
                        } label: {
                            Label(String(localized: "Archivieren"), systemImage: "archivebox")
                        }
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("archive-habit")
                    } footer: {
                        Text(String(localized: "Archivieren erhält die Historie. Endgültig löschen kannst du im Archiv (Mehr → Archiv)."))
                    }
                }
            }
            .navigationTitle(existing == nil ? String(localized: "Neuer Habit") : String(localized: "Bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Sichern")) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("save-habit")
                }
            }
        }
        .onAppear { load() }
        .onChange(of: draft.frequency) { _, _ in draft.normalize(calendar: calendar) }
        .onChange(of: draft.flexible) { _, _ in draft.normalize(calendar: calendar) }
    }

    // MARK: – Wiederholung

    private var recurrenceSection: some View {
        Section {
            summaryRow
            Picker(String(localized: "Häufigkeit"), selection: $draft.frequency) {
                Text(String(localized: "Täglich")).tag(Recurrence.Frequency.daily)
                Text(String(localized: "Wöchentlich")).tag(Recurrence.Frequency.weekly)
                Text(String(localized: "Monatlich")).tag(Recurrence.Frequency.monthly)
                Text(String(localized: "Jährlich")).tag(Recurrence.Frequency.yearly)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("cadence-picker")

            Stepper(value: $draft.interval, in: 1...Recurrence.maxInterval) {
                Text(intervalLabel)
            }
            .accessibilityIdentifier("interval-stepper")

            if draft.frequency != .daily {
                Picker(String(localized: "Art"), selection: $draft.flexible) {
                    Text(String(localized: "Feste Termine")).tag(false)
                    Text(String(localized: "Anzahl")).tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("flexible-picker")
            }

            if draft.flexible, draft.frequency != .daily {
                flexibleControls
            } else {
                switch draft.frequency {
                case .daily: EmptyView()
                case .weekly: weekdayChips(multiSelect: true)
                case .monthly: monthlyControls
                case .yearly: yearlyControls
                }
            }
        } header: {
            Text(String(localized: "Wiederholung"))
        } footer: {
            if draft.frequency == .weekly, !draft.flexible, draft.weekdays.isEmpty {
                Text(String(localized: "Ohne gewählten Wochentag steht nie ein Termin an. Check-ins zählen trotzdem."))
            } else if draft.flexible {
                Text(String(localized: "Die Anzahl zählt pro Periode — welche Tage es werden, entscheidest du. Ein fester Tag ist dann nur eine Verabredung für die Erinnerung; ein Check-in an einem anderen Tag zählt genauso."))
            }
        }
    }

    /// Die eingestellte Regel als ein Satz — das Erste in der Sektion, damit
    /// niemand aus Steppern zusammenreimen muss, was er gerade gebaut hat.
    private var summaryRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "calendar")
                .foregroundStyle(Theme.accentText(palettes.style))
            Text(draft.summary(calendar: calendar))
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recurrence-summary")
    }

    private var intervalLabel: String {
        let n = draft.interval
        switch draft.frequency {
        case .daily:
            return n == 1 ? String(localized: "Jeden Tag") : String(localized: "Alle \(n) Tage")
        case .weekly:
            return n == 1 ? String(localized: "Jede Woche") : String(localized: "Alle \(n) Wochen")
        case .monthly:
            return n == 1 ? String(localized: "Jeden Monat") : String(localized: "Alle \(n) Monate")
        case .yearly:
            return n == 1 ? String(localized: "Jedes Jahr") : String(localized: "Alle \(n) Jahre")
        }
    }

    // MARK: – Flexibles Ziel („n× pro Periode")

    @ViewBuilder
    private var flexibleControls: some View {
        Stepper(value: $draft.times, in: 1...Recurrence.maxTimes(for: draft.frequency)) {
            Text(flexibleLabel)
        }
        .accessibilityIdentifier("weekly-times")
        if draft.frequency == .weekly {
            Toggle(String(localized: "Fester Tag"), isOn: fixedWeekdayBinding)
                .accessibilityIdentifier("fixed-weekday-toggle")
            if !draft.weekdays.isEmpty {
                weekdayChips(multiSelect: false)
            }
        }
    }

    private var flexibleLabel: String {
        let n = draft.times
        switch draft.frequency {
        case .monthly: return String(localized: "\(n)× pro Monat")
        case .yearly: return String(localized: "\(n)× pro Jahr")
        default: return String(localized: "\(n)× pro Woche")
        }
    }

    /// Der Schalter „Fester Tag" IST die Frage, ob eine Verabredung
    /// existiert — aus ist die leere Menge, an der Tag des Starts.
    private var fixedWeekdayBinding: Binding<Bool> {
        Binding(get: { !draft.weekdays.isEmpty },
                set: { on in
                    draft.weekdays = on ? [calendar.component(.weekday, from: draft.start)] : []
                })
    }

    // MARK: – Monat / Jahr

    @ViewBuilder
    private var monthlyControls: some View {
        Picker(String(localized: "Regel"), selection: $draft.monthlyMode) {
            Text(String(localized: "Tag im Monat")).tag(RecurrenceDraft.MonthlyMode.dayOfMonth)
            Text(String(localized: "Letzter Tag")).tag(RecurrenceDraft.MonthlyMode.lastDay)
            Text(String(localized: "Wochentag")).tag(RecurrenceDraft.MonthlyMode.nthWeekday)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("monthly-rule-picker")
        monthRuleDetail
    }

    @ViewBuilder
    private var yearlyControls: some View {
        Picker(String(localized: "Monat"), selection: $draft.month) {
            ForEach(1...12, id: \.self) { month in
                Text(RecurrenceText.monthName(month, calendar: calendar)).tag(month)
            }
        }
        .accessibilityIdentifier("year-month")
        Picker(String(localized: "Regel"), selection: $draft.monthlyMode) {
            Text(String(localized: "Tag im Monat")).tag(RecurrenceDraft.MonthlyMode.dayOfMonth)
            Text(String(localized: "Letzter Tag")).tag(RecurrenceDraft.MonthlyMode.lastDay)
            Text(String(localized: "Wochentag")).tag(RecurrenceDraft.MonthlyMode.nthWeekday)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("monthly-rule-picker")
        monthRuleDetail
    }

    @ViewBuilder
    private var monthRuleDetail: some View {
        switch draft.monthlyMode {
        case .dayOfMonth:
            Stepper(value: $draft.dayOfMonth, in: 1...31) {
                Text(String(localized: "Am \(draft.dayOfMonth)."))
            }
            .accessibilityIdentifier("month-day")
            if draft.dayOfMonth > 28 {
                // Nicht jeder Monat hat diesen Tag. Was dann passiert, ist
                // eine ENTSCHEIDUNG (der Termin fällt aus, er rutscht nicht
                // auf den 28.) — also steht sie da, wo man sie trifft.
                Text(String(localized: "Monate ohne diesen Tag werden übersprungen."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .lastDay:
            EmptyView()
        case .nthWeekday:
            Picker(String(localized: "Der wievielte"), selection: $draft.nth) {
                Text(String(localized: "Erster")).tag(1)
                Text(String(localized: "Zweiter")).tag(2)
                Text(String(localized: "Dritter")).tag(3)
                Text(String(localized: "Vierter")).tag(4)
                Text(String(localized: "Fünfter")).tag(5)
                Text(String(localized: "Letzter")).tag(Recurrence.DayRule.last)
            }
            .accessibilityIdentifier("month-nth")
            Picker(String(localized: "Wochentag"), selection: $draft.nthWeekday) {
                ForEach(orderedWeekdays, id: \.self) { day in
                    Text(RecurrenceText.weekdayName(day, calendar: calendar)).tag(day)
                }
            }
            .accessibilityIdentifier("month-weekday")
        }
    }

    // MARK: – Zeitraum

    private var periodSection: some View {
        Section {
            Toggle(String(localized: "Startdatum"), isOn: $draft.hasStart)
                .accessibilityIdentifier("start-toggle")
            if draft.hasStart {
                DatePicker(String(localized: "Beginn"), selection: $draft.start,
                           displayedComponents: .date)
                    .accessibilityIdentifier("start-date")
            }
            Picker(String(localized: "Ende"), selection: $draft.endMode) {
                Text(String(localized: "Nie")).tag(RecurrenceDraft.EndMode.never)
                Text(String(localized: "Am Datum")).tag(RecurrenceDraft.EndMode.onDate)
                Text(String(localized: "Nach Terminen")).tag(RecurrenceDraft.EndMode.afterCount)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("end-picker")
            switch draft.endMode {
            case .never:
                EmptyView()
            case .onDate:
                DatePicker(String(localized: "Endet am"), selection: $draft.endDate,
                           displayedComponents: .date)
                    .accessibilityIdentifier("end-date")
            case .afterCount:
                Stepper(value: $draft.endCount, in: 1...Recurrence.maxOccurrences) {
                    Text(String(localized: "Nach \(draft.endCount) Terminen"))
                }
                .accessibilityIdentifier("end-count")
            }
        } header: {
            Text(String(localized: "Zeitraum"))
        } footer: {
            if !draft.hasStart {
                Text(String(localized: "Ohne Startdatum gilt die Regel für die ganze Historie — so bleiben Quoten und Serien älterer Habits unverändert."))
            } else if draft.endMode == .afterCount {
                Text(String(localized: "Gezählt werden TERMINE, nicht Tage."))
            }
        }
    }

    // MARK: – Mengenziel

    private var quantitySection: some View {
        Section {
            Toggle(String(localized: "Mengenziel"), isOn: $draft.quantity)
                .accessibilityIdentifier("quantity-toggle")
            if draft.quantity {
                Stepper(value: $draft.target, in: 1...99) {
                    Text(String(localized: "Ziel: \(draft.target) pro Tag"))
                }
                .accessibilityIdentifier("quantity-target")
            }
        } header: {
            Text(String(localized: "Ziel"))
        }
    }

    // MARK: – Wochentags-Chips

    /// Dieselben Chips für beide Bedeutungen: Mehrfachauswahl sind die
    /// TERMINE, Einfachauswahl ist die Verabredung eines flexiblen Ziels.
    /// Gleiche Geste, gleiche Optik — nur die Regel darunter ist eine andere.
    private func weekdayChips(multiSelect: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(multiSelect
                 ? String(localized: "Wochentage")
                 : String(localized: "Wochentag"))
                .font(.subheadline)
            HStack(spacing: 6) {
                ForEach(orderedWeekdays, id: \.self) { day in
                    let on = draft.weekdays.contains(day)
                    Button {
                        if multiSelect {
                            if on { draft.weekdays.remove(day) } else { draft.weekdays.insert(day) }
                        } else {
                            draft.weekdays = [day]
                        }
                    } label: {
                        Text(RecurrenceText.shortWeekdayName(day, calendar: calendar))
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(on ? Theme.accentFill(palettes.style) : Color(.tertiarySystemFill), in: Capsule())
                            .foregroundStyle(on ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(RecurrenceText.weekdayName(day, calendar: calendar))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weekly-weekday")
    }

    /// Calendar-Wochentagsnummern (1 = So … 7 = Sa) ab `firstWeekday`.
    private var orderedWeekdays: [Int] {
        let first = calendar.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    // MARK: – Farbe
    //
    // Bewusst NUR das Raster dieses Habits: die Knöpfe, der Tint und alles
    // andere folgen weiter der App-Palette. Eine Habit-Farbe soll EIN Habit
    // hervorheben, nicht die halbe App umlackieren.

    private var colorSection: some View {
        Section {
            PalettePicker(selection: $habitPalette,
                          allowsGlobal: true,
                          palettes: palettes)
        } header: {
            Text(String(localized: "Farbe"))
        } footer: {
            Text(String(localized: "„Wie App“ nimmt die Farbe aus den Einstellungen. Eine eigene Farbe gilt nur für das Raster dieses Habits."))
        }
    }

    // MARK: – Erinnerung (Berechtigungs-Gate unverändert aus v1)

    /// Wie oft es klingelt, sagt die Regel — die Beschriftung sagt dasselbe,
    /// sonst verspricht ein „Tägliche Erinnerung" etwas, was die App gar
    /// nicht plant (siehe `Reminders.plans`).
    private var reminderTitle: String {
        let recurrence = draft.recurrence(calendar: calendar)
        guard let plan = Reminders.plan(for: previewHabit(recurrence),
                                        calendar: calendar) else {
            return String(localized: "Erinnerung")
        }
        if plan.isOneShot { return String(localized: "Erinnerung zum nächsten Termin") }
        if plan.isWeekly { return String(localized: "Wöchentliche Erinnerung") }
        if plan.dateMatching.month != nil { return String(localized: "Jährliche Erinnerung") }
        if plan.isMonthly { return String(localized: "Monatliche Erinnerung") }
        return String(localized: "Tägliche Erinnerung")
    }

    /// Ein Wegwerf-Habit nur für die Frage „wie würde geplant?" — dieselbe
    /// Rechnung wie später beim echten Planen, kein zweites Regelwerk.
    private func previewHabit(_ recurrence: Recurrence) -> Habit {
        Habit(name: name, reminderMinutes: 12 * 60, recurrence: recurrence)
    }

    private var reminderSection: some View {
        Section {
            Toggle(reminderTitle, isOn: $reminderOn)
                .accessibilityIdentifier("reminder-toggle")
            if reminderOn {
                DatePicker(String(localized: "Uhrzeit"), selection: $reminderTime, displayedComponents: .hourAndMinute)
                    .accessibilityIdentifier("reminder-time")
            }
            if permissionDenied {
                Text(String(localized: "Benachrichtigungen sind in den iOS-Einstellungen deaktiviert. Dort einschalten, dann klappt die Erinnerung."))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } footer: {
            Text(reminderOn
                 ? String(localized: "\(draft.summary(calendar: calendar)) — zur gewählten Zeit. Gefragt wird nur, wenn du eine Erinnerung einschaltest — nie einfach so.")
                 : String(localized: "Gefragt wird nur, wenn du eine Erinnerung einschaltest — nie einfach so."))
        }
    }

    // MARK: – Laden / Sichern

    private func load() {
        guard let habit = existing else { return }
        name = habit.name
        emoji = habit.emoji
        if let minutes = habit.reminderMinutes {
            reminderOn = true
            reminderTime = calendar.date(from: DateComponents(hour: minutes / 60,
                                                              minute: minutes % 60)) ?? .now
        }
        draft = RecurrenceDraft(habit.recurrence, calendar: calendar)
        habitPalette = habit.palette
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let minutes: Int? = reminderOn
            ? calendar.component(.hour, from: reminderTime) * 60
              + calendar.component(.minute, from: reminderTime)
            : nil
        // Bewusst OHNE `normalize`: die Grenzen zieht der Init der Regel
        // ohnehin, und eine bewusst leere Wochentagsmenge soll leer bleiben.
        let recurrence = draft.recurrence(calendar: calendar)

        Task {
            var granted = true
            if minutes != nil { granted = await Reminders.ensurePermission() }
            await MainActor.run {
                if minutes != nil && !granted {
                    permissionDenied = true
                    return
                }
                var habit = existing ?? Habit(name: trimmed, emoji: emoji)
                habit.name = trimmed
                habit.emoji = emoji.trimmingCharacters(in: .whitespaces)
                habit.reminderMinutes = minutes
                habit.recurrence = recurrence
                habit.palette = habitPalette
                if existing == nil { store.add(habit) } else { store.update(habit) }
                Theme.Haptics.success()
                dismiss()
            }
        }
    }
}
