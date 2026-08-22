import SwiftUI

/// Anlegen/Bearbeiten. ANLEGEN kommt als eigene SEITE (fullScreenCover, aus
/// dem Toolbar-Plus gezoomt — siehe ContentView), BEARBEITEN
/// bleibt das Half-Sheet an der Karte. Es fragt NICHTS mehr nach
/// Die Uhrzeit im Zeitraum steuert zugleich die konkrete Habit-Erinnerung;
/// Tages- und Wochenzusammenfassungen bleiben zusätzliche globale Hinweise.
///
/// Das Herz ist der Regel-Editor: Häufigkeit × Intervall, dazu die feine
/// Regel (Wochentage, Tag im Monat, n-ter Wochentag), das Startdatum und die
/// Uhrzeit — alles unter EINER Überschrift „Zeitraum". Damit das nicht zu
/// einem Formular wird, das man raten muss, steht ganz oben in der Sektion
/// EIN Satz, der die eingestellte Regel vorliest — „Jeden 2. Montag und
/// Donnerstag um 07:30", „Am letzten Freitag im Monat". Der Satz kommt aus
/// `RecurrenceText` und ist als reine Funktion getestet.
///
/// **Was das Formular NICHT mehr zeigt** (und warum die Werte trotzdem
/// stehen bleiben):
///
///  * **Feste Termine / Anzahl.** Die Regel benennt jetzt immer die TAGE.
///    Das flexible Ziel („3× pro Woche", `Recurrence.timesPerPeriod`) bleibt
///    im Modell und in der Rechnung — migrierte Alt-Ziele und alles, was in
///    einer ausgelieferten Version angelegt wurde, verhält sich unverändert.
///    Es lässt sich nur nicht mehr NEU einstellen.
///  * **Das Ende** (nie / am Datum / nach Terminen, `Recurrence.End`).
///    Es gehört zur Regel und wird deshalb direkt unter dem Startdatum
///    eingestellt.
///
/// Der Zustand liegt in `RecurrenceDraft`, nicht in einem Dutzend
/// `@State`-Variablen: der Weg Regel -> Formular -> Regel ist damit prüfbar,
/// ohne den Simulator zu starten — und genau darüber überleben die beiden
/// nicht mehr angezeigten Felder eine Runde durch den Editor.
struct EditHabitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.palettes) private var palettes
    let store: HabitStore
    var existing: Habit?
    /// Als SEITE präsentiert (Anlegen, fullScreenCover): das Schließen ist
    /// dann ein X oben links — dieselbe Geste wie auf der Mehr-Seite. Als
    /// Blatt (Bearbeiten) bleibt es das Wort „Abbrechen". Beide Wege tun
    /// exakt dasselbe: verwerfen ohne zu sichern.
    var asPage = false

    @State private var name = ""
    @State private var emoji = ""
    @State private var itemType: HabitItemType = .habit
    @State private var calendarSyncEnabled = true
    @State private var notificationsEnabled = true
    @State private var repeatsWhileIncomplete = true
    /// Nil inherits the global default; `device` is an explicit per-item
    /// choice that remains stable when the global setting changes.
    @State private var timeZoneIdentifier: String?
    @State private var showTimeZonePicker = false
    @State private var paywall: PaywallContext?

    /// Die ganze Regel als EIN Wert.
    @State private var draft = RecurrenceDraft()
    /// nil = „Wie App" (kein Override) — der Normalfall.
    @State private var habitPalette: PaletteRef?
    /// Die Art. Steht NEBEN dem Entwurf und nicht darin: `RecurrenceDraft`
    /// bildet die REGEL ab (samt Mengenziel), die Art ist eine Eigenschaft
    /// des Habits. Sie steuert hier trotzdem `draft.quantity` mit — das
    /// Mengenziel ist die Art „Menge".
    @State private var kind: HabitKind = .checkbox
    /// Geplante Session-Dauer. Wie die Uhrzeit hinter einem Schalter — die
    /// meisten Habits haben keine, und ohne Dauer läuft eine Session
    /// „limitless" (sie zählt nur hoch).
    @State private var hasDuration = false
    @State private var durationMinutes = EditHabitSheet.defaultDuration
    /// nil = globale Wischbelegung. Nur beim Bearbeiten sichtbar, denn ein
    /// neues Habit soll mit der globalen, nachvollziehbaren Regel starten.
    @State private var swipeActions: SwipeActionsOverride?
    @State private var notificationDenied = false

    private var calendar: Calendar {
        HabitTimeZone.calendar(identifier: timeZoneIdentifier
                               ?? store.defaultTimeZoneIdentifier)
    }

    private var frequencySelection: Binding<Recurrence.Frequency> {
        Binding(
            get: { draft.frequency },
            set: { newFrequency in
                draft.selectFrequency(newFrequency, calendar: calendar)
                if newFrequency == .once {
                    itemType = .reminder
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(String(localized: "Art"), selection: $itemType) {
                        Text(String(localized: "Habit")).tag(HabitItemType.habit)
                        Text(String(localized: "Erinnerung")).tag(HabitItemType.reminder)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("item-type-picker")

                    TextField(String(localized: "Name (z. B. 20 Minuten lesen)"), text: $name)
                        .accessibilityIdentifier("habit-name")
                    TextField(String(localized: "Emoji (optional)"), text: $emoji)
                        .accessibilityIdentifier("habit-emoji")
                }
                recurrenceSection
                durationSection
                if itemType == .habit { kindSection }
                colorSection
                if let habit = existing {
                    swipeActionsSection
                    Section {
                        if habit.isTrackedHabit {
                            ShareLink(item: HabitShareImage(habit: habit, dark: scheme == .dark, palette: palettes.style(for: habit)),
                                      preview: SharePreview(habit.name)) {
                                Label(String(localized: "Als Bild teilen"), systemImage: "square.and.arrow.up")
                            }
                        }
                        Button {
                            store.archive(habit.id)
                            dismiss()
                        } label: {
                            Label(String(localized: "Archivieren"), systemImage: "archivebox")
                        }
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("archive-habit")
                    }
                }
            }
            .settingsSurface()
            .navigationTitle(existing == nil ? String(localized: "Neuer Habit") : String(localized: "Bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if asPage {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(String(localized: "Schließen"))
                        .accessibilityIdentifier("close-create")
                    } else {
                        Button(String(localized: "Abbrechen")) { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Sichern")) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("save-habit")
                }
            }
        }
        .sheet(item: $paywall) { context in
            PaywallView(context: context, store: store,
                        onUnlocked: { save(skipGate: true) })
                .themed(store)
        }
        .sheet(isPresented: $showTimeZonePicker) {
            HabitTimeZoneSheet(selection: $timeZoneIdentifier,
                               inheritedLabel: String(localized: "Standard"))
                .themed(store)
        }
        .onAppear { load() }
        .onChange(of: draft.flexible) { _, _ in draft.normalize(calendar: calendar) }
        // Die Art IST das Mengenziel-Häkchen: „Menge" schaltet es an, alles
        // andere aus. Ein Ja/Nein-Habit mit stehen gebliebenem Ziel wäre ein
        // Widerspruch, den die Rechnung zwar aushält (die Art gewinnt), der
        // aber beim nächsten Umschalten auf „Menge" aus dem Nichts wieder
        // aufträte.
        .onChange(of: kind) { _, new in draft.quantity = (new == .quantity) }
        .onChange(of: draft.hasTime) { _, enabled in
            guard enabled, notificationsEnabled else { return }
            requestNotificationPermissionIfNeeded()
        }
        .onChange(of: notificationsEnabled) { _, enabled in
            guard enabled, draft.hasTime else { return }
            requestNotificationPermissionIfNeeded()
        }
        .alert(String(localized: "Mitteilungen aktivieren"),
               isPresented: $notificationDenied) {
            Button(String(localized: "iOS-Einstellungen öffnen")) {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(String(localized: "Nicht jetzt"), role: .cancel) {}
        } message: {
            Text(String(localized: "Erlaube Mitteilungen, damit hAiity dich zur gewählten Zeit erinnert."))
        }
    }

    // MARK: – Zeitraum (Regel + Start)

    private var recurrenceSection: some View {
        Section {
            summaryRow
            Picker(String(localized: "Häufigkeit"), selection: frequencySelection) {
                Text(String(localized: "Ein Tag")).tag(Recurrence.Frequency.once)
                Text(String(localized: "Täglich")).tag(Recurrence.Frequency.daily)
                Text(String(localized: "Wöchentlich")).tag(Recurrence.Frequency.weekly)
                Text(String(localized: "Monatlich")).tag(Recurrence.Frequency.monthly)
                Text(String(localized: "Jährlich")).tag(Recurrence.Frequency.yearly)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("cadence-picker")

            if draft.frequency == .once {
                DatePicker(String(localized: "Datum"),
                           selection: $draft.start,
                           displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .accessibilityIdentifier("once-date")
            }

            if draft.frequency != .once {
                Stepper(value: $draft.interval, in: 1...Recurrence.maxInterval) {
                    Text(intervalLabel)
                }
                .accessibilityIdentifier("interval-stepper")

                // Die Wahl „feste Termine oder Anzahl" gibt es nicht mehr: die
                // Regel benennt die TAGE. Ein Habit, das noch aus der Zeit des
                // flexiblen Ziels stammt, behält seine Rechnung (siehe oben) und
                // zeigt hier weiterhin seine Verabredung — nur ohne den Zähler,
                // den man nicht mehr verstellen kann.
                if draft.flexible, draft.frequency != .daily {
                    flexibleControls
                } else {
                    switch draft.frequency {
                    case .once: EmptyView()
                    case .daily: EmptyView()
                    case .weekly: weekdayChips(multiSelect: true)
                    case .monthly: monthlyControls
                    case .yearly: yearlyControls
                    }
                }

                // Der Start gehörte einmal in einen eigenen Abschnitt „Zeitraum"
                // neben dieser Sektion. Zwei Überschriften für dieselbe Frage
                // („wann?") waren eine zu viel — jetzt steht er hier, direkt
                // unter der Regel, für die er gilt.
                Toggle(String(localized: "Startdatum"), isOn: $draft.hasStart)
                    .accessibilityIdentifier("start-toggle")
                if draft.hasStart {
                    DatePicker(String(localized: "Beginn"), selection: $draft.start,
                               displayedComponents: .date)
                        .accessibilityIdentifier("start-date")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Ende"))
                        .accessibilityAddTraits(.isHeader)
                    Picker(String(localized: "Ende"), selection: $draft.endMode) {
                        Text(String(localized: "Nie")).tag(RecurrenceDraft.EndMode.never)
                        Text(String(localized: "Am Datum")).tag(RecurrenceDraft.EndMode.onDate)
                        Text(String(localized: "Nach Anzahl")).tag(RecurrenceDraft.EndMode.afterCount)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("end-mode-picker")
                }
                switch draft.endMode {
                case .never:
                    EmptyView()
                case .onDate:
                    DatePicker(String(localized: "Enddatum"), selection: $draft.endDate,
                               displayedComponents: .date)
                        .accessibilityIdentifier("end-date")
                case .afterCount:
                    Stepper(value: $draft.endCount, in: 1...Recurrence.maxOccurrences) {
                        Text(String(localized: "Nach \(draft.endCount) Terminen"))
                    }
                    .accessibilityIdentifier("end-count")
                }
            }

            Toggle(String(localized: "Uhrzeit"), isOn: $draft.hasTime)
                .accessibilityIdentifier("time-toggle")
            if draft.hasTime {
                DatePicker(String(localized: "Zeit"), selection: $draft.time,
                           displayedComponents: .hourAndMinute)
                    .accessibilityIdentifier("habit-time")
                Toggle(String(localized: "Benachrichtigung"), isOn: $notificationsEnabled)
                    .accessibilityIdentifier("habit-notification-toggle")
            }
            Button {
                showTimeZonePicker = true
            } label: {
                HStack {
                    Label(String(localized: "Zeitzone"), systemImage: "globe")
                    Spacer(minLength: Theme.Metrics.gap)
                    Text(HabitTimeZone.selectionLabel(
                        for: timeZoneIdentifier,
                        defaultIdentifier: store.defaultTimeZoneIdentifier))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("habit-timezone")
            Toggle(String(localized: "Im Kalender"), isOn: $calendarSyncEnabled)
                .accessibilityIdentifier("habit-calendar-toggle")
            if itemType == .reminder {
                Toggle(String(localized: "Trotz offenem Termin wiederholen"),
                       isOn: $repeatsWhileIncomplete)
                    .accessibilityIdentifier("repeats-while-incomplete-toggle")
            }
        } header: {
            Text(String(localized: "Zeitraum"))
        } footer: {
            if draft.frequency == .weekly, !draft.flexible, draft.weekdays.isEmpty {
                Text(String(localized: "Ohne Wochentag gibt es keinen Termin."))
            } else if draft.flexible {
                Text(String(localized: "Check-ins zählen in der gesamten Periode."))
            } else if !draft.hasStart {
                Text(String(localized: "Ohne Startdatum gilt die Regel rückwirkend."))
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
        case .once:
            return String(localized: "Einmal")
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

    // MARK: – Flexibles Ziel („n× pro Periode") — nur noch Bestandsschutz
    //
    // Der Zähler-Stepper stand hier einmal („3× pro Woche"). Er ist weg: die
    // Anzahl pro Periode lässt sich nicht mehr NEU einstellen (das Mengenziel
    // beantwortet die verwandte Frage „wie viel pro Tag"). Was bleibt, ist
    // die Verabredung — der Tag, an dem so ein Habit gedacht ist. Der Satz
    // ganz oben sagt weiterhin, wie oft pro Periode gezählt wird.

    @ViewBuilder
    private var flexibleControls: some View {
        if draft.frequency == .weekly {
            Toggle(String(localized: "Fester Tag"), isOn: fixedWeekdayBinding)
                .accessibilityIdentifier("fixed-weekday-toggle")
            if !draft.weekdays.isEmpty {
                weekdayChips(multiSelect: false)
            }
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

    // MARK: – Dauer (geplante Session-Länge)
    //
    // Wie die Uhrzeit eine EIGENSCHAFT des Habits, keine Pflicht: die Dauer
    // ist der Plan, gegen den eine gestartete Session (Live-Aktivität) ihren
    // Fortschritt zeigt. Ohne Dauer zählt die Session einfach hoch.

    /// Voreinstellung beim Einschalten und die wählbaren Stufen. Feste
    /// Stufen statt eines freien Rads: eine Session-Dauer ist eine
    /// Größenordnung („eine halbe Stunde"), keine Sekundenangabe.
    static let defaultDuration = 30
    static let durationPresets = [5, 10, 15, 20, 30, 45, 60, 90, 120]

    /// Die Stufen, ggf. um einen BESTEHENDEN krummen Wert ergänzt (Import,
    /// andere App-Version) — der eingestellte Wert muss im Rad stehen,
    /// sonst würde das bloße Öffnen des Editors ihn verstellen.
    private var durationChoices: [Int] {
        var choices = Self.durationPresets
        if !choices.contains(durationMinutes) {
            choices.append(durationMinutes)
            choices.sort()
        }
        return choices
    }

    private var durationSection: some View {
        Section {
            Toggle(String(localized: "Dauer"), isOn: $hasDuration)
                .accessibilityIdentifier("duration-toggle")
            if hasDuration {
                Picker(String(localized: "Geplante Dauer"), selection: $durationMinutes) {
                    ForEach(durationChoices, id: \.self) { minutes in
                        Text(HabitSessionMath.durationText(minutes: minutes)).tag(minutes)
                    }
                }
                .accessibilityIdentifier("duration-minutes")
            }
        } footer: {
            Text(String(localized: "Mit Dauer zeigt die Live-Aktivität deinen Fortschritt."))
        }
    }

    // MARK: – Art (Abhaken / Menge / Ja-Nein)
    //
    // Die drei Arten schließen einander aus, also stehen sie in EINEM
    // Umschalter und nicht als zwei Kippschalter nebeneinander. Vorher war
    // hier ein einzelner Schalter „Mengenziel"; mit einer dritten Art wären
    // daraus zwei Schalter geworden, die man gegenseitig ausknipsen muss —
    // und ein Zustand, in dem beide an sind und niemand weiß, was gilt.

    private var kindSection: some View {
        Section {
            Picker(String(localized: "Art"), selection: $kind) {
                ForEach(HabitKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("habit-kind-picker")

            if kind == .quantity {
                Stepper(value: $draft.target, in: 1...99) {
                    Text(String(localized: "Ziel: \(draft.target) pro Tag"))
                }
                .accessibilityIdentifier("quantity-target")
            }
        } header: {
            Text(String(localized: "Art"))
        } footer: {
            switch kind {
            case .checkbox:
                Text(String(localized: "Ein Tag ist erledigt oder nicht."))
            case .quantity:
                Text(String(localized: "Ein Tag zählt, sobald das Ziel erreicht ist."))
            case .yesNo:
                Text(String(localized: "Jeder Tag wird mit Ja oder Nein beantwortet."))
            }
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
    // Die Farbe gilt für das Raster und die Statuskontrollen dieses Habits;
    // Tint und alle anderen App-Akzente folgen weiter der App-Palette.

    private var colorSection: some View {
        Section {
            PalettePicker(selection: $habitPalette,
                          allowsGlobal: true,
                          palettes: palettes)
        } header: {
            Text(String(localized: "Farbe"))
        } footer: {
            Text(String(localized: "Eine eigene Farbe gilt nur für diesen Eintrag."))
        }
    }

    private var swipeActionsSection: some View {
        Section {
            Toggle(String(localized: "Eigene Wischaktionen"), isOn: Binding(
                get: { swipeActions != nil },
                set: { enabled in
                    swipeActions = enabled
                        ? SwipeActionsOverride(leading: SwipeActionChoice.none,
                                               trailing: SwipeActionChoice.none)
                        : nil
                }))
            .accessibilityIdentifier("habit-swipe-override-toggle")

            if swipeActions != nil {
                Picker(String(localized: "Nach rechts wischen"), selection: swipeLeadingBinding) {
                    ForEach(SwipeActionChoice.selectable) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("habit-swipe-leading-picker")

                Picker(String(localized: "Nach links wischen"), selection: swipeTrailingBinding) {
                    ForEach(SwipeActionChoice.selectable) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("habit-swipe-trailing-picker")
            }
        } header: {
            Text(String(localized: "Wischaktionen"))
        } footer: {
            Text(String(localized: "Wähle zusätzliche Wischaktionen."))
        }
    }

    /// Altlasten (`primary`/`secondary`) lesen sich als „keine Extra-Aktion".
    private func normalized(_ choice: SwipeActionChoice?) -> SwipeActionChoice {
        guard let choice, SwipeActionChoice.selectable.contains(choice) else { return .none }
        return choice
    }

    private var swipeLeadingBinding: Binding<SwipeActionChoice> {
        Binding(get: { normalized(swipeActions?.leading) },
                set: { swipeActions?.leading = $0 })
    }

    private var swipeTrailingBinding: Binding<SwipeActionChoice> {
        Binding(get: { normalized(swipeActions?.trailing) },
                set: { swipeActions?.trailing = $0 })
    }

    // MARK: – Laden / Sichern

    private func load() {
        guard let habit = existing else { return }
        name = habit.name
        emoji = habit.emoji
        itemType = habit.itemType
        calendarSyncEnabled = habit.calendarSyncEnabled
        notificationsEnabled = habit.notificationsEnabled
        timeZoneIdentifier = habit.timeZoneIdentifier
        repeatsWhileIncomplete = habit.repeatsWhileIncomplete
        // Die Uhrzeit reist MIT dem Entwurf: sie steht im selben Abschnitt
        // und im selben Satz wie die Regel.
        draft = RecurrenceDraft(habit.recurrence,
                                timeMinutes: habit.timeMinutes ?? habit.reminderMinutes,
                                calendar: calendar)
        if draft.frequency == .once {
            itemType = .reminder
        }
        habitPalette = habit.palette
        swipeActions = habit.swipeActions
        kind = habit.kind
        if let duration = habit.durationMinutes {
            hasDuration = true
            durationMinutes = duration
        }
    }

    /// Sichern bleibt synchron. Die Berechtigung wird beim Einschalten der
    /// Erinnerung angefragt, nicht erst beim Schreiben des Habits.
    private func save(skipGate: Bool = false) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if !skipGate, existing == nil && itemType == .habit,
           !ProGate.mayAddHabit(activeCount: store.activeTrackedHabits.count,
                                unlocked: Pro.isUnlocked) {
            paywall = .habits
            return
        }
        // Bewusst OHNE `normalize`: die Grenzen zieht der Init der Regel
        // ohnehin, und eine bewusst leere Wochentagsmenge soll leer bleiben.
        let recurrence = draft.recurrence(calendar: calendar)

        var habit = existing ?? Habit(name: trimmed, emoji: emoji)
        habit.name = trimmed
        habit.emoji = emoji.trimmingCharacters(in: .whitespaces)
        habit.itemType = itemType
        habit.calendarSyncEnabled = calendarSyncEnabled
        habit.notificationsEnabled = notificationsEnabled
        habit.timeZoneIdentifier = HabitTimeZone.sanitizedIdentifier(timeZoneIdentifier)
        habit.repeatsWhileIncomplete = itemType == .reminder ? repeatsWhileIncomplete : true
        if itemType != .reminder || existing?.recurrence != recurrence {
            habit.reminderCursor = nil
        }
        let notificationTime = draft.timeMinutes(calendar: calendar)
        habit.timeMinutes = notificationTime
        habit.durationMinutes = hasDuration ? Habit.sanitizedDuration(durationMinutes) : nil
        // Keep the legacy key mirrored so older synced builds retain the
        // notification while every current UI exposes only one time.
        habit.reminderMinutes = notificationTime
        habit.recurrence = recurrence
        habit.palette = habitPalette
        habit.swipeActions = swipeActions
        // Reminders share the checkbox log internally; their habit-only kind
        // controls stay out of the editor and cannot survive a mode switch.
        let effectiveKind = itemType == .habit ? kind : .checkbox
        habit.log = Habit.migratedLog(habit.log, to: effectiveKind)
        habit.kind = itemType == .habit ? Habit.resolvedKind(marker: kind.rawValue,
                                                              log: habit.log,
                                                              target: recurrence.target) : .checkbox
        if existing == nil { store.add(habit) } else { store.update(habit) }
        Theme.Haptics.success()
        dismiss()
    }

    private func requestNotificationPermissionIfNeeded() {
        Task {
            let granted = await Reminders.ensurePermission()
            guard !granted, !NotificationPromptPreference.isSuppressed else { return }
            await MainActor.run { notificationDenied = true }
        }
    }
}
