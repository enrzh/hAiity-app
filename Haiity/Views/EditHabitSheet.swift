import SwiftUI

/// Creation and editing share essential fields and explicit disclosure of
/// schedule details and additional settings. Collapsing only changes visibility;
/// RecurrenceDraft retains existing rules, including legacy flexible goals.
/// Notification times can follow the scheduled time or be customized separately.
/// Daily and weekly summaries remain additional global notifications.
struct EditHabitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.palettes) private var palettes
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.appearancePreferences) private var appearancePreferences
    let store: HabitStore
    var existing: Habit?
    var initialItemType: HabitItemType = .habit
    /// Als SEITE präsentiert (Anlegen, fullScreenCover): das Schließen ist
    /// dann ein X oben links — dieselbe Geste wie auf der Mehr-Seite. Als
    /// Blatt (Bearbeiten) bleibt es das Wort „Abbrechen". Beide Wege tun
    /// exakt dasselbe: verwerfen ohne zu sichern.
    var asPage = false
    var offersSentenceCreation: Bool = false

    @State private var name = ""
    @State private var emoji = ""
    @State private var itemType: HabitItemType = .habit
    @State private var calendarSyncEnabled = true
    @State private var notificationMode: HabitNotificationMode = .standard
    @State private var notificationTimes: [Int]?
    @State private var notificationTimeIDs = [UUID()]
    @State private var repeatsWhileIncomplete = true
    @State private var autoResolveChoice: HabitAutoResolveChoice?
    /// Nil inherits the global default; `device` is an explicit per-item
    /// choice that remains stable when the global setting changes.
    @State private var timeZoneIdentifier: String?
    @State private var showTimeZonePicker = false
    @State private var showStartDatePicker = false
    @State private var paywall: PaywallContext?
    @State private var pendingCalendarEnable = false
    @State private var proStatus = ProStatus.shared

    /// Die ganze Regel als EIN Wert.
    @State private var draft = RecurrenceDraft(itemType: .habit)
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
    @State private var showingDeleteConfirmation = false
    @State private var editingMultipleDate: MultipleDateEdit?
    @State private var showingCreationAdvanced = false
    @State private var showingScheduleDetails = false
    @State private var sentenceText: String?
    @State private var didLoad = false
    @State private var isVisible = false
    @State private var permissionTask: Task<Void, Never>?
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var savedWhileAwaitingPermission = false
    private enum IdentityField: Hashable { case name, emoji }
    @FocusState private var focusedIdentity: IdentityField?

    init(store: HabitStore, existing: Habit? = nil,
         initialItemType: HabitItemType = .habit, asPage: Bool = false,
         offersSentenceCreation: Bool = false) {
        self.store = store
        self.existing = existing
        self.initialItemType = initialItemType
        self.asPage = asPage
        self.offersSentenceCreation = offersSentenceCreation
        _itemType = State(initialValue: existing?.itemType ?? initialItemType)
        let calendar = HabitTimeZone.calendar(identifier:
            existing?.timeZoneIdentifier ?? store.defaultTimeZoneIdentifier)
        _draft = State(initialValue: Self.initialDraft(existing: existing,
            initialItemType: initialItemType, calendar: calendar))
    }

    static func initialDraft(existing: Habit? = nil, initialItemType: HabitItemType = .habit,
                             calendar: Calendar, today: Date = .now) -> RecurrenceDraft {
        if let existing {
            return RecurrenceDraft(existing.recurrence,
                timeMinutes: existing.timeMinutes ?? existing.reminderMinutes,
                today: today, calendar: calendar)
        }
        return RecurrenceDraft(itemType: initialItemType, today: today, calendar: calendar)
    }

    private var isCreating: Bool { existing == nil }
    private var designStyle: AppDesignStyle { appearancePreferences.designStyle }

    private var creationTitle: String {
        itemType == .habit
            ? String(localized: "Neuer Habit")
            : String(localized: "Neue Erinnerung")
    }

    private var creationNamePrompt: String {
        itemType == .habit
            ? String(localized: "Name (z. B. 20 Minuten lesen)")
            : String(localized: "Name (z. B. Tabletten nehmen)")
    }

    private struct MultipleDateEdit: Identifiable {
        let id = UUID()
        let original: Recurrence.MonthDay?
        let initialDate: Date
        let isYearly: Bool
    }

    private var calendar: Calendar {
        HabitTimeZone.calendar(identifier: timeZoneIdentifier
                               ?? store.defaultTimeZoneIdentifier)
    }

    private var unlocked: Bool {
        _ = proStatus.unlocked
        return Pro.isUnlocked
    }

    private var calendarSyncBinding: Binding<Bool> {
        Binding(
            get: { unlocked && calendarSyncEnabled },
            set: { enabled in
                guard enabled else {
                    calendarSyncEnabled = false
                    return
                }
                guard unlocked else {
                    pendingCalendarEnable = true
                    paywall = .calendar
                    return
                }
                calendarSyncEnabled = true
            })
    }

    private var frequencySelection: Binding<Recurrence.Frequency> {
        Binding(
            get: { draft.frequency == .once ? .daily : draft.frequency },
            set: { newFrequency in
                draft.hasStart = true
                draft.selectFrequency(newFrequency, calendar: calendar)
                showingScheduleDetails = false
            }
        )
    }

    private var repeatsBinding: Binding<Bool> {
        Binding(
            get: { draft.frequency != .once },
            set: { enabled in
                draft.setRepeats(enabled, calendar: calendar)
            })
    }

    private var itemTypeSelection: Binding<HabitItemType> {
        Binding(get: { itemType }, set: { selected in
            guard itemType != selected else { return }
            itemType = selected
            if isCreating {
                draft.selectFrequency(selected == .habit ? .daily : .once, calendar: calendar)
            }
        })
    }

    private var flexibleWeekBinding: Binding<Bool> {
        Binding(get: { draft.flexible }, set: { enabled in
            draft.setFlexibleWeek(enabled, calendar: calendar)
        })
    }

    private var autoResolveEnabledBinding: Binding<Bool> {
        Binding(
            get: { autoResolveChoice != nil },
            set: { enabled in
                autoResolveChoice = enabled
                    ? (validAutoResolveChoice ?? HabitAutoResolveChoice.defaultChoice(
                        for: kind, itemType: itemType))
                    : nil
            })
    }

    private var validAutoResolveChoice: HabitAutoResolveChoice? {
        guard let autoResolveChoice,
              HabitAutoResolveChoice.choices(for: kind, itemType: itemType)
                .contains(autoResolveChoice) else {
            return nil
        }
        return autoResolveChoice
    }

    private var autoResolveChoiceBinding: Binding<HabitAutoResolveChoice> {
        Binding(
            get: {
                validAutoResolveChoice ?? HabitAutoResolveChoice.defaultChoice(
                    for: kind, itemType: itemType)
            },
            set: { autoResolveChoice = $0 })
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { draft.start },
            set: { draft.selectDate($0, calendar: calendar) })
    }

    private var multipleDaysBinding: Binding<Bool> {
        Binding(get: { draft.multipleDaysEnabled },
                set: { draft.setMultipleDaysEnabled($0, calendar: calendar) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if dynamicTypeSize.isAccessibilitySize {
                        itemTypePicker.pickerStyle(.menu)
                    } else {
                        itemTypePicker.pickerStyle(.segmented)
                    }

                    TextField(creationNamePrompt, text: $name)
                        .focused($focusedIdentity, equals: .name)
                        .submitLabel(.done)
                        .onSubmit { focusedIdentity = nil }
                        .accessibilityIdentifier("habit-name")
                } footer: {
                    if isCreating, offersSentenceCreation {
                        Button {
                            focusedIdentity = nil
                            sentenceText = name
                        } label: {
                            Label(String(localized: "Aus einem Satz anlegen"), systemImage: "text.bubble")
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(minHeight: Theme.Metrics.hit)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("speak-to-create")
                    }
                }
                .settingsListRow()
                recurrenceSection.settingsListRow()
                if itemType == .habit {
                    Section {
                        kindControls
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("creation-kind")
                    .settingsListRow()
                }
                Section { creationPreview }
                    .settingsListRow()
                Section {
                    Button {
                        showingCreationAdvanced.toggle()
                    } label: {
                        AppSettingsRow(title: String(localized: "Weitere Einstellungen"),
                                       detail: additionalSettingsSummary.isEmpty
                                           ? String(localized: "Mitteilungen, Kalender und Verhalten")
                                           : additionalSettingsSummary,
                                       symbol: "slider.horizontal.3") {
                            Image(systemName: showingCreationAdvanced ? "chevron.down" : "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .flipsForRightToLeftLayoutDirection(true)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("creation-advanced")
                    .accessibilityValue(showingCreationAdvanced
                        ? String(localized: "Ausgeklappt") : String(localized: "Eingeklappt"))
                }
                .settingsListRow()
                if showingCreationAdvanced {
                    if itemType == .habit {
                        Section { appointmentTimeControls }
                            .settingsListRow()
                    }
                    notificationSection.settingsListRow()
                    Section {
                        TextField(String(localized: "Emoji (optional)"), text: $emoji)
                            .focused($focusedIdentity, equals: .emoji)
                            .submitLabel(.done)
                            .onSubmit { focusedIdentity = nil }
                            .accessibilityIdentifier("habit-emoji")
                    }
                    .settingsListRow()
                    durationSection.settingsListRow()
                    colorSection.settingsListRow()
                    creationAdvancedNotificationSection.settingsListRow()
                    if existing != nil { swipeActionsSection.settingsListRow() }
                }
                if let habit = existing {
                    Section {
                        if habit.isTrackedHabit {
                            ShareLink(item: HabitShareImage(habit: habit, dark: scheme == .dark, palette: palettes.style(for: habit)),
                                      preview: SharePreview(habit.name)) {
                                Label(String(localized: "Als Bild teilen"), systemImage: "square.and.arrow.up")
                            }
                        }
                        Button {
                            store.archive(habit.id)
                            guard store.lastWriteError == nil else {
                                saveError = store.lastWriteError
                                return
                            }
                            dismiss()
                        } label: {
                            Label(String(localized: "Archivieren"), systemImage: "archivebox")
                        }
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("archive-habit")
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label(String(localized: "Löschen"), systemImage: "trash")
                        }
                        .accessibilityIdentifier("delete-habit")
                    }
                    .settingsListRow()
                }
            }
            .disabled(isSaving || savedWhileAwaitingPermission)
            .settingsSurface()
            .environment(\.calendar, calendar)
            .environment(\.timeZone, calendar.timeZone)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(existing == nil ? creationTitle : String(localized: "Bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .pageHeaderChrome()
            .navigationDestination(item: $sentenceText) { initialText in
                SpeakToCreateSheet(store: store, initialText: initialText, embedded: true,
                                   onClose: { sentenceText = nil },
                                   onCreated: { close() })
            }
            .toolbar {
                if sentenceText == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        if asPage {
                            Button {
                                close()
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .accessibilityLabel(String(localized: "Schließen"))
                            .accessibilityIdentifier("close-create")
                            .disabled(isSaving || savedWhileAwaitingPermission)
                        } else {
                            Button(String(localized: "Abbrechen")) { close() }
                                .accessibilityIdentifier("close-create")
                                .disabled(isSaving || savedWhileAwaitingPermission)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Sichern")) { save() }
                            .fontWeight(.semibold)
                            .disabled(isSaving || savedWhileAwaitingPermission || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("save-habit")
                    }
                }
            }
        }
        .alert(String(localized: "Fehler"), isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button(String(localized: "OK"), role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .sheet(item: $paywall) { context in
            PaywallView(context: context, store: store,
                        onUnlocked: {
                            guard isVisible else { return }
                            if pendingCalendarEnable {
                                pendingCalendarEnable = false
                                calendarSyncEnabled = true
                            } else {
                                save(skipGate: true)
                            }
                        })
                .themed(store, palettes: palettes)
        }
        .sheet(isPresented: $showTimeZonePicker) {
            HabitTimeZoneSheet(selection: $timeZoneIdentifier,
                               inheritedLabel: String(localized: "Standard"))
                .themed(store, palettes: palettes)
        }
        .sheet(isPresented: $showStartDatePicker) {
            NavigationStack {
                DatePicker(String(localized: "Datum"), selection: dateBinding,
                           displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding()
                    .environment(\.calendar, calendar)
                    .environment(\.timeZone, calendar.timeZone)
                    .navigationTitle(String(localized: "Datum"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "Fertig")) { showStartDatePicker = false }
                                .accessibilityIdentifier("start-date-done")
                        }
                    }
            }
            .themed(store, palettes: palettes)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingMultipleDate) { edit in
            MultipleDatePickerSheet(
                initialDate: edit.initialDate,
                isYearly: edit.isYearly,
                calendar: calendar,
                onSave: { date in
                    draft.setMultipleDate(date,
                                           replacing: edit.original,
                                           calendar: calendar)
                    editingMultipleDate = nil
                },
                onDelete: edit.original.map { original in
                    {
                        draft.removeMultipleDate(original)
                        editingMultipleDate = nil
                    }
                })
            .themed(store, palettes: palettes)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            isVisible = true
            guard !didLoad else { return }
            didLoad = true
            load()
            if isCreating {
                focusedIdentity = .name
            }
        }
        .onDisappear {
            isVisible = false
            permissionTask?.cancel()
        }
        .confirmationDialog(String(localized: "Eintrag löschen?"),
                            isPresented: $showingDeleteConfirmation,
                            presenting: existing) { habit in
            Button(String(localized: "Löschen"), role: .destructive) {
                store.remove(habit.id)
                guard store.lastWriteError == nil else {
                    saveError = store.lastWriteError
                    return
                }
                dismiss()
            }
            Button(String(localized: "Abbrechen"), role: .cancel) {}
        } message: { habit in
            Text(String(localized: "„\(habit.name)“ und die komplette Historie werden gelöscht. Das lässt sich nicht rückgängig machen."))
        }
        .onChange(of: draft.flexible) { _, _ in draft.normalize(calendar: calendar) }
        // Die Art IST das Mengenziel-Häkchen: „Menge" schaltet es an, alles
        // andere aus. Ein Ja/Nein-Habit mit stehen gebliebenem Ziel wäre ein
        // Widerspruch, den die Rechnung zwar aushält (die Art gewinnt), der
        // aber beim nächsten Umschalten auf „Menge" aus dem Nichts wieder
        // aufträte.
        .onChange(of: kind) { _, new in
            draft.quantity = (new == .quantity)
            if let choice = autoResolveChoice,
               !HabitAutoResolveChoice.choices(for: new, itemType: itemType).contains(choice) {
                autoResolveChoice = HabitAutoResolveChoice.defaultChoice(
                    for: new, itemType: itemType)
            }
        }
        .onChange(of: itemType) { _, new in
            guard new == .reminder,
                  let choice = autoResolveChoice,
                  !HabitAutoResolveChoice.choices(for: .checkbox).contains(choice) else {
                return
            }
            autoResolveChoice = .notDone
        }
        .onChange(of: notificationMode) { _, mode in
            if mode == .timeSensitive && !draft.hasTime {
                draft.hasTime = true
            }
        }
        .alert(String(localized: "Mitteilungen aktivieren"),
               isPresented: $notificationDenied) {
            Button(String(localized: "iOS-Einstellungen öffnen")) {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                dismiss()
            }
            Button(String(localized: "Nicht jetzt"), role: .cancel) { dismiss() }
        } message: {
            Text(String(localized: "Erlaube Mitteilungen, damit hAiity dich zur gewählten Zeit erinnert."))
        }
        .interactiveDismissDisabled(isSaving || savedWhileAwaitingPermission)
    }

    private var itemTypePicker: some View {
        Picker(String(localized: "Art"), selection: itemTypeSelection) {
            Text(String(localized: "Habit")).tag(HabitItemType.habit)
            Text(String(localized: "Erinnerung")).tag(HabitItemType.reminder)
        }
        .accessibilityIdentifier("item-type-picker")
    }

    private var additionalSettingsSummary: String {
        var values: [String] = []
        if draft.hasTime || notificationTimes != nil || notificationMode == .off {
            values.append(Self.notificationPreview(mode: notificationMode,
                                                   times: notificationTimeValues,
                                                   calendar: calendar))
        }
        if !emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            values.append(String(localized: "Emoji: \(emoji)"))
        }
        if let habitPalette, let paletteName = palettes.displayName(habitPalette) {
            values.append(String(localized: "Farbe: \(paletteName)"))
        }
        if hasDuration {
            let duration = HabitSessionMath.durationText(minutes: durationMinutes)
            values.append(String(localized: "Dauer: \(duration)"))
        }
        if timeZoneIdentifier != nil {
            let zone = HabitTimeZone.selectionLabel(
                for: timeZoneIdentifier, defaultIdentifier: store.defaultTimeZoneIdentifier)
            values.append(String(localized: "Zeitzone: \(zone)"))
        }
        let calendarIntegrationEnabled = itemType == .habit
            ? store.cloudPreferences?.calendarSyncHabits ?? CalendarSync.syncHabits
            : store.cloudPreferences?.calendarSyncReminders ?? CalendarSync.syncReminders
        if unlocked && calendarSyncEnabled && calendarIntegrationEnabled {
            values.append(String(localized: "Im Kalender"))
        }
        if itemType == .reminder && draft.frequency != .once && !repeatsWhileIncomplete {
            values.append(String(localized: "Neue Termine warten auf Abschluss"))
        }
        if let choice = validAutoResolveChoice {
            values.append(String(localized: "Automatisch abschließen: \(choice.displayName)"))
        }
        if let swipeActions {
            let leading = normalized(swipeActions.leading).displayName
            let trailing = normalized(swipeActions.trailing).displayName
            values.append(String(localized: "Wischaktionen: \(leading), \(trailing)"))
        }
        return values.joined(separator: " · ")
    }

    private var creationPreview: some View {
        Text(Self.previewSummary(name: name, itemType: itemType, draft: draft,
                                 notificationMode: notificationMode,
                                 notificationTimes: notificationTimes, calendar: calendar))
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, designStyle.rowGap)
            .accessibilityIdentifier("creation-preview")
    }

    static func previewSummary(name: String, itemType: HabitItemType, draft: RecurrenceDraft,
                               notificationMode: HabitNotificationMode,
                               notificationTimes: [Int]?, calendar: Calendar) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = itemType == .habit ? String(localized: "Habit") : String(localized: "Erinnerung")
        let identity = trimmed.isEmpty ? type : "\(type): \(trimmed)"
        var schedule = draft.summary(calendar: calendar)
        if draft.frequency != .once, draft.hasStart {
            let start = draft.start.formatted(Date.FormatStyle(date: .long, time: .omitted,
                locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone))
            schedule += ", " + String(format: String(localized: "Ab %@"), start)
        }
        let times = notificationTimes
            ?? [draft.timeMinutes(calendar: calendar) ?? Habit.defaultNotificationMinutes]
        return String(localized: "Vorschau: \(identity), \(schedule)") + "\n"
            + notificationPreview(mode: notificationMode, times: times, calendar: calendar)
    }

    private var creationAdvancedNotificationSection: some View {
        Section {
            Button {
                showTimeZonePicker = true
            } label: {
                VStack(alignment: .leading, spacing: designStyle.rowGap) {
                    Label(String(localized: "Zeitzone"), systemImage: "globe")
                        .font(designStyle.rowTitleFont)
                    Text(HabitTimeZone.selectionLabel(
                        for: timeZoneIdentifier,
                        defaultIdentifier: store.defaultTimeZoneIdentifier))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.hit, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("habit-timezone")
            Toggle(isOn: calendarSyncBinding) {
                HStack {
                    Text(String(localized: "Im Kalender"))
                    if !unlocked {
                        Spacer(minLength: Theme.Metrics.gap)
                        Image(systemName: "lock")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(String(localized: "Nur mit hAiity Pro"))
                    }
                }
            }
            .accessibilityIdentifier("habit-calendar-toggle")
            if itemType == .reminder && draft.frequency != .once {
                Toggle(String(localized: "Trotz offenem Termin wiederholen"),
                       isOn: $repeatsWhileIncomplete)
                    .accessibilityIdentifier("repeats-while-incomplete-toggle")
            }
            Toggle(String(localized: "Offene Termine automatisch abschließen"),
                   isOn: autoResolveEnabledBinding)
                .accessibilityIdentifier("auto-resolve-toggle")
            if autoResolveChoice != nil {
                Picker(String(localized: "Beim Ablauf als"), selection: autoResolveChoiceBinding) {
                    ForEach(HabitAutoResolveChoice.choices(for: kind, itemType: itemType),
                            id: \.rawValue) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                .accessibilityIdentifier("auto-resolve-choice")
            }
        } header: {
            Text(String(localized: "Benachrichtigung und Verhalten"))
        }
    }

    // MARK: – Zeitraum (Regel + Start)

    private var recurrenceSection: some View {
        Section {
            if itemType == .reminder || draft.frequency == .once
                || draft.frequency == .monthly || draft.frequency == .yearly {
                appointmentDateControls
            }

            Toggle(String(localized: "Wiederholen"), isOn: repeatsBinding)
                .accessibilityIdentifier("repeat-toggle")

            if draft.frequency != .once {
                Picker(String(localized: "Häufigkeit"), selection: frequencySelection) {
                    Text(String(localized: "Täglich")).tag(Recurrence.Frequency.daily)
                    Text(String(localized: "Wöchentlich")).tag(Recurrence.Frequency.weekly)
                    Text(String(localized: "Monatlich")).tag(Recurrence.Frequency.monthly)
                    Text(String(localized: "Jährlich")).tag(Recurrence.Frequency.yearly)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("cadence-picker")

                if itemType == .habit, draft.frequency == .weekly {
                    Toggle(String(localized: "Flexible Woche"), isOn: flexibleWeekBinding)
                        .accessibilityIdentifier("flexible-week-toggle")
                    if draft.flexible {
                        Stepper(value: $draft.times, in: 1...Recurrence.maxTimes(for: .weekly)) {
                            Text(draft.interval == 1 && draft.weekdays.isEmpty
                                 ? String(localized: "\(draft.times)× pro Woche, an beliebigen Tagen")
                                 : draft.summary(calendar: calendar))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(minHeight: Theme.Metrics.hit)
                        .accessibilityIdentifier("weekly-times-stepper")
                    }
                }

                DisclosureGroup(isExpanded: $showingScheduleDetails) {
                    recurrenceDetails
                } label: {
                    AppSettingsRow(title: String(localized: "Wiederholung anpassen")) {
                        EmptyView()
                    }
                    .foregroundStyle(.primary)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("recurrence-details")
            }

            if itemType == .reminder { appointmentTimeControls }
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

    @ViewBuilder
    private var appointmentDateControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Button { showStartDatePicker = true } label: {
                VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
                    Text(String(localized: "Datum"))
                        .foregroundStyle(.primary)
                    Text(draft.start.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted,
                        locale: calendar.locale ?? .current, calendar: calendar,
                        timeZone: calendar.timeZone)))
                        .foregroundStyle(.tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.hit, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("once-date")
        } else {
            startDatePicker.datePickerStyle(.compact)
        }
    }

    @ViewBuilder
    private var appointmentTimeControls: some View {
        Toggle(String(localized: "Uhrzeit"), isOn: $draft.hasTime)
            .accessibilityIdentifier("time-toggle")
        if draft.hasTime {
            DatePicker(String(localized: "Zeit"), selection: $draft.time,
                       displayedComponents: .hourAndMinute)
                .accessibilityIdentifier("habit-time")
        }
    }

    private var startDatePicker: some View {
        DatePicker(String(localized: "Datum"), selection: dateBinding,
                   displayedComponents: .date)
            .accessibilityIdentifier("once-date")
    }

    @ViewBuilder
    private var recurrenceDetails: some View {
        if itemType == .habit && (draft.frequency == .daily || draft.frequency == .weekly) {
            appointmentDateControls
        }
        if draft.showsIntervalStepper {
            Stepper(value: $draft.interval, in: 1...Recurrence.maxInterval) {
                Text(intervalLabel)
            }
            .accessibilityIdentifier("interval-stepper")
        }

        if draft.flexible, draft.frequency != .daily {
            flexibleControls
        } else {
            switch draft.frequency {
            case .once, .daily: EmptyView()
            case .weekly: weekdayChips(multiSelect: true)
            case .monthly: monthlyControls
            case .yearly: yearlyControls
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Ende"))
                .accessibilityAddTraits(.isHeader)
            Picker(String(localized: "Ende"), selection: $draft.endMode) {
                Text(String(localized: "Nie")).tag(RecurrenceDraft.EndMode.never)
                Text(String(localized: "Am Datum")).tag(RecurrenceDraft.EndMode.onDate)
                Text(String(localized: "Nach Anzahl")).tag(RecurrenceDraft.EndMode.afterCount)
            }
            .pickerStyle(.menu)
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

    private var notificationTimeValues: [Int] {
        notificationTimes ?? [draft.timeMinutes(calendar: calendar) ?? Habit.defaultNotificationMinutes]
    }

    /// Presentation only: an off mode must never turn retained times into alerts.
    static func notificationPreview(mode: HabitNotificationMode, times: [Int],
                                    calendar: Calendar) -> String {
        guard mode != .off, !times.isEmpty else {
            return String(localized: "Keine Mitteilungen geplant")
        }
        let format = Date.FormatStyle(date: .omitted, time: .shortened,
                                     locale: calendar.locale ?? .current,
                                     calendar: calendar, timeZone: calendar.timeZone)
            .hour(.twoDigits(amPM: .abbreviated))
        let clocks = Habit.normalizedNotificationTimes(times).compactMap { minutes in
            calendar.date(from: DateComponents(year: 2001, month: 1, day: 15,
                                               hour: minutes / 60, minute: minutes % 60))?
                .formatted(format)
        }
        guard !clocks.isEmpty else { return String(localized: "Keine Mitteilungen geplant") }
        let list = clocks.formatted(.list(type: .and).locale(calendar.locale ?? .current))
        return mode == .timeSensitive
            ? String(localized: "Zeitkritische Mitteilungen: \(list)")
            : String(localized: "Mitteilungen: \(list)")
    }

    private var notificationSection: some View {
        Section {
            if dynamicTypeSize.isAccessibilitySize {
                notificationModePicker.pickerStyle(.menu)
            } else {
                notificationModePicker.pickerStyle(.segmented)
            }
            if notificationMode != .off {
                notificationTimeControls
            }
        } header: {
            Text(String(localized: "Mitteilungen"))
        } footer: {
            if notificationMode == .off {
                Text(String(localized: "Mitteilungen sind aus. Gespeicherte Zeiten bleiben erhalten."))
            } else {
                Text(String(localized: "Diese Zeiten gelten an den geplanten Tagen. Sie ändern den Termin nicht. Bei Aus werden keine Mitteilungen gesendet. Mehr Zeiten verkürzen den Vorausplanungszeitraum."))
            }
        }
    }

    private var notificationModePicker: some View {
        Picker(String(localized: "Benachrichtigung"), selection: $notificationMode) {
            Text(String(localized: "Aus")).tag(HabitNotificationMode.off)
            Text(String(localized: "Standard")).tag(HabitNotificationMode.standard)
            Text(String(localized: "Zeitkritisch")).tag(HabitNotificationMode.timeSensitive)
        }
        .accessibilityIdentifier("habit-notification-mode")
    }

    @ViewBuilder
    private var notificationTimeControls: some View {
        if notificationTimeValues.isEmpty {
            Text(String(localized: "Keine Mitteilungen geplant"))
                .foregroundStyle(.secondary)
        }
        ForEach(Array(notificationTimeIDs.enumerated()), id: \.element) { index, _ in
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Metrics.gap))
                : AnyLayout(HStackLayout(spacing: Theme.Metrics.gap))
            layout {
                DatePicker(String(localized: "Mitteilung \(index + 1)"),
                           selection: notificationTimeBinding(index),
                           displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .accessibilityIdentifier("notification-time-\(index)")
                Button(role: .destructive) {
                    var times = notificationTimeValues
                    guard times.indices.contains(index) else { return }
                    times.remove(at: index)
                    notificationTimes = times
                    notificationTimeIDs.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .frame(width: Theme.Metrics.hit, height: Theme.Metrics.hit)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: "Mitteilung \(index + 1) entfernen"))
                .accessibilityIdentifier("remove-notification-time-\(index)")
            }
        }
        Button {
            let times = notificationTimeValues
            let start = times.last.map { ($0 + 60) % (24 * 60) }
                ?? draft.timeMinutes(calendar: calendar) ?? Habit.defaultNotificationMinutes
            guard let next = (0..<24 * 60).lazy.map({ (start + $0) % (24 * 60) })
                .first(where: { !times.contains($0) }) else { return }
            notificationTimes = times + [next]
            notificationTimeIDs.append(UUID())
        } label: {
            Label(String(localized: "Mitteilung hinzufügen"), systemImage: "plus.circle")
                .frame(minHeight: Theme.Metrics.hit)
        }
        .buttonStyle(.borderless)
        .disabled(notificationTimeValues.count >= 24 * 60)
        .accessibilityIdentifier("add-notification-time")
    }

    private func notificationTimeBinding(_ index: Int) -> Binding<Date> {
        Binding(get: {
            let values = notificationTimeValues
            let minutes = values.indices.contains(index) ? values[index] : Habit.defaultNotificationMinutes
            // A fixed winter date keeps time-only controls away from DST gaps.
            return calendar.date(from: DateComponents(year: 2001, month: 1, day: 15,
                                                       hour: minutes / 60, minute: minutes % 60)) ?? .now
        }, set: { date in
            var values = notificationTimeValues
            guard values.indices.contains(index) else { return }
            values[index] = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
            notificationTimes = values
        })
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

    // MARK: – Flexible Ziele und bestehende Wochentags-Verabredungen

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
        multipleDayControls
    }

    @ViewBuilder
    private var yearlyControls: some View {
        multipleDayControls
    }

    private var multipleDayControls: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
            Toggle(String(localized: "Mehrere Tage"), isOn: multipleDaysBinding)
                .accessibilityIdentifier("multiple-days-toggle")
            if draft.multipleDaysEnabled {
                VStack(spacing: 0) {
                    ForEach(draft.sortedMultipleDates, id: \.self) { value in
                        HStack(spacing: Theme.Metrics.gap) {
                            Button {
                                editingMultipleDate = MultipleDateEdit(
                                    original: value,
                                    initialDate: multipleDatePickerDate(for: value),
                                    isYearly: draft.frequency == .yearly)
                            } label: {
                                HStack {
                                    Text(multipleDateLabel(value))
                                        .font(.body.monospacedDigit().weight(.medium))
                                    Spacer(minLength: Theme.Metrics.gap)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                        .flipsForRightToLeftLayoutDirection(true)
                                }
                                .frame(minHeight: Theme.Metrics.hit)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "\(multipleDateLabel(value)) bearbeiten"))
                            .accessibilityIdentifier("multiple-date-\(value.month)-\(value.day)")

                            Button(role: .destructive) {
                                draft.removeMultipleDate(value)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.body.weight(.medium))
                                    .frame(width: Theme.Metrics.hit, height: Theme.Metrics.hit)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "\(multipleDateLabel(value)) löschen"))
                            .accessibilityIdentifier("multiple-date-delete-\(value.month)-\(value.day)")
                        }
                        .padding(.vertical, 7)
                        if value != draft.sortedMultipleDates.last {
                            Divider()
                        }
                    }
                }
                .accessibilityIdentifier("multiple-date-list")

                Button {
                    editingMultipleDate = MultipleDateEdit(
                        original: nil,
                        initialDate: multipleDatePickerDate(for: nil),
                        isYearly: draft.frequency == .yearly)
                } label: {
                    Label(String(localized: "Datum hinzufügen"), systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .frame(minHeight: Theme.Metrics.hit)
                .accessibilityIdentifier("multiple-date-add")
            }
        }
    }

    private func multipleDateLabel(_ value: Recurrence.MonthDay) -> String {
        if draft.frequency == .yearly {
            return String(format: "%02d.%02d.", value.day, value.month)
        }
        return "\(value.day)."
    }

    private func multipleDatePickerDate(for value: Recurrence.MonthDay?) -> Date {
        let month = value?.month ?? (draft.frequency == .yearly ? draft.month : 1)
        let day = value?.day ?? draft.dayOfMonth
        return calendar.date(from: DateComponents(year: 2000,
                                                  month: month,
                                                  day: min(day, 31))) ?? draft.start
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

    @ViewBuilder
    private var kindControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            kindPicker.pickerStyle(.menu)
        } else {
            kindPicker.pickerStyle(.segmented)
        }

        if kind == .quantity {
            Stepper(value: $draft.target, in: 1...99) {
                Text(String(localized: "Ziel: \(draft.target) pro Tag"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("quantity-target")
        }
        Group {
            switch kind {
            case .checkbox:
                Text(String(localized: "Ein Tag ist erledigt oder nicht."))
            case .quantity:
                Text(String(localized: "Ein Tag zählt, sobald das Ziel erreicht ist."))
            case .yesNo:
                Text(String(localized: "Jeder Tag wird mit Ja oder Nein beantwortet."))
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var kindPicker: some View {
        Picker(String(localized: "Art"), selection: $kind) {
            ForEach(HabitKind.allCases, id: \.self) { kind in
                Text(kind.displayName).tag(kind)
            }
        }
        .accessibilityIdentifier("habit-kind-picker")
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
            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                      ? [GridItem(.flexible())]
                      : [GridItem(.adaptive(minimum: Theme.Metrics.hit))], spacing: 6) {
                ForEach(orderedWeekdays, id: \.self) { day in
                    let on = draft.weekdays.contains(day)
                    Button {
                        if multiSelect {
                            if on { draft.weekdays.remove(day) } else { draft.weekdays.insert(day) }
                        } else {
                            draft.weekdays = [day]
                        }
                    } label: {
                        Text(dynamicTypeSize.isAccessibilitySize
                             ? RecurrenceText.weekdayName(day, calendar: calendar)
                             : RecurrenceText.shortWeekdayName(day, calendar: calendar))
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.hit)
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
                          palettes: unlocked ? palettes : palettes.withoutCustoms)
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
        notificationMode = habit.notificationMode
        notificationTimes = habit.notificationTimes
        notificationTimeIDs = notificationTimeValues.map { _ in UUID() }
        timeZoneIdentifier = habit.timeZoneIdentifier
        repeatsWhileIncomplete = habit.repeatsWhileIncomplete
        autoResolveChoice = habit.autoResolveChoice
        // Die Uhrzeit reist MIT dem Entwurf: sie steht im selben Abschnitt
        // und im selben Satz wie die Regel.
        draft = RecurrenceDraft(habit.recurrence,
                                timeMinutes: habit.timeMinutes ?? habit.reminderMinutes,
                                calendar: calendar)
        // A persisted custom palette is a Pro-only choice. Keep the editor
        // usable after expiry and avoid writing that choice back invisibly.
        habitPalette = unlocked || habit.palette?.customID == nil ? habit.palette : nil
        swipeActions = habit.swipeActions
        kind = habit.kind
        if let duration = habit.durationMinutes {
            hasDuration = true
            durationMinutes = duration
        }
    }

    /// Sichern bleibt synchron. Die Berechtigung gehört zum bestätigten
    /// Eintrag, nicht zu einem möglicherweise verworfenen Entwurf.
    private func save(skipGate: Bool = false) {
        guard isVisible, !isSaving, !savedWhileAwaitingPermission else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !skipGate,
           !ProGate.maySaveTrackedHabit(
               existingIsTracked: existing?.isTrackedHabit == true,
               targetIsTracked: itemType == .habit,
               activeCount: store.activeTrackedHabits.count,
               unlocked: unlocked) {
            paywall = .habits
            return
        }
        // Bewusst OHNE `normalize`: die Grenzen zieht der Init der Regel
        // ohnehin, und eine bewusst leere Wochentagsmenge soll leer bleiben.
        let recurrence = draft.recurrence(calendar: calendar)

        var habit = existing.flatMap { original in store.habits.first { $0.id == original.id } }
            ?? existing ?? Habit(name: trimmed, emoji: emoji)
        habit.name = trimmed
        habit.emoji = emoji.trimmingCharacters(in: .whitespaces)
        habit.itemType = itemType
        habit.calendarSyncEnabled = unlocked && calendarSyncEnabled
        habit.notificationMode = notificationMode
        habit.notificationTimes = notificationTimes.map(Habit.normalizedNotificationTimes)
        habit.timeZoneIdentifier = HabitTimeZone.sanitizedIdentifier(timeZoneIdentifier)
        habit.repeatsWhileIncomplete = itemType == .reminder ? repeatsWhileIncomplete : true
        habit.autoResolveChoice = validAutoResolveChoice
        if itemType != .reminder || existing?.recurrence != recurrence {
            habit.reminderCursor = nil
        }
        let notificationTime = draft.timeMinutes(calendar: calendar)
        habit.timeMinutes = notificationTime
        habit.durationMinutes = hasDuration ? Habit.sanitizedDuration(durationMinutes) : nil
        // The legacy key retains the scheduled time for older synced builds.
        habit.reminderMinutes = notificationTime
        habit.recurrence = recurrence
        habit.palette = unlocked || habitPalette?.customID == nil ? habitPalette : nil
        habit.swipeActions = swipeActions
        // Reminders share the checkbox log internally; their habit-only kind
        // controls stay out of the editor and cannot survive a mode switch.
        let effectiveKind = itemType == .habit ? kind : .checkbox
        habit.log = Habit.migratedLog(habit.log, to: effectiveKind)
        habit.kind = itemType == .habit ? Habit.resolvedKind(marker: kind.rawValue,
                                                              log: habit.log,
                                                              target: recurrence.target) : .checkbox
        if existing == nil { store.add(habit) } else { store.update(habit) }
        guard store.lastWriteError == nil else {
            saveError = store.lastWriteError
            return
        }
        Theme.Haptics.success()
        guard (draft.hasTime || notificationTimes != nil), notificationMode != .off,
              !habit.effectiveNotificationTimes.isEmpty else {
            dismiss()
            return
        }
        savedWhileAwaitingPermission = true
        isSaving = true
        permissionTask = Task {
            let granted = await Reminders.ensurePermission()
            if granted {
                // Store persistence schedules the normal change path; this
                // explicit pass closes the permission-grant race as well.
                await Reminders.reschedule(store: store)
            }
            let suppressed = NotificationPromptPreference.isSuppressed
            await MainActor.run {
                guard !Task.isCancelled, isVisible else { return }
                isSaving = false
                if granted || suppressed {
                    dismiss()
                } else {
                    notificationDenied = true
                }
            }
        }
    }

    private func close() {
        guard isVisible else { return }
        isVisible = false
        permissionTask?.cancel()
        dismiss()
    }
}

/// Native iOS wheel selection for additional recurrence entries. The sheet
/// exposes only the components that can be stored: a day for monthly rules,
/// and a day plus month for yearly rules.
private struct MultipleDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initialDate: Date
    let isYearly: Bool
    let calendar: Calendar
    let onSave: (Date) -> Void
    let onDelete: (() -> Void)?

    @State private var selectedDay: Int
    @State private var selectedMonth: Int
    @State private var showingDeleteConfirmation = false

    init(initialDate: Date,
         isYearly: Bool,
         calendar: Calendar,
         onSave: @escaping (Date) -> Void,
         onDelete: (() -> Void)?) {
        self.initialDate = initialDate
        self.isYearly = isYearly
        self.calendar = calendar
        self.onSave = onSave
        self.onDelete = onDelete
        _selectedDay = State(initialValue: calendar.component(.day, from: initialDate))
        _selectedMonth = State(initialValue: calendar.component(.month, from: initialDate))
    }

    private var validDays: Range<Int> {
        guard isYearly else { return 1..<32 }
        let components = DateComponents(year: 2000, month: selectedMonth, day: 1)
        let date = calendar.date(from: components)
        let count = date.flatMap { calendar.range(of: .day, in: .month, for: $0)?.count } ?? 31
        return 1..<(count + 1)
    }

    private var selection: Date {
        calendar.date(from: DateComponents(year: 2000,
                                            month: isYearly ? selectedMonth : 1,
                                            day: selectedDay)) ?? initialDate
    }

    var body: some View {
        NavigationStack {
            Form {
                if isYearly {
                    HStack(alignment: .top, spacing: Theme.Metrics.gap) {
                        pickerColumn(String(localized: "Tag"), selection: $selectedDay,
                                     values: validDays,
                                     suffix: ".")
                        pickerColumn(String(localized: "Monat"), selection: $selectedMonth,
                                     values: 1..<13,
                                     suffix: nil)
                    }
                } else {
                    pickerColumn(String(localized: "Tag"), selection: $selectedDay,
                                 values: validDays,
                                 suffix: ".")
                }
                Text(String(localized: isYearly
                            ? "Jahr wird nicht gespeichert"
                            : "Gilt an diesem Tag in jedem Monat"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("multiple-date-picker")
            }
            .settingsSurface()
            .onChange(of: selectedMonth) { _, _ in
                selectedDay = min(selectedDay, validDays.last ?? selectedDay)
            }
            .navigationTitle(String(localized: isYearly ? "Datum bearbeiten" : "Tag bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Abbrechen")) { dismiss() }
                }
                if onDelete != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button(String(localized: "Löschen"), role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Sichern")) {
                        onSave(selection)
                        dismiss()
                    }
                }
            }
        }
        .pageHeaderChrome()
        .confirmationDialog(String(localized: "Datum löschen?"),
                            isPresented: $showingDeleteConfirmation) {
            Button(String(localized: "Löschen"), role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button(String(localized: "Abbrechen"), role: .cancel) {}
        }
    }

    @ViewBuilder
    private func pickerColumn(_ title: String,
                              selection: Binding<Int>,
                              values: Range<Int>,
                              suffix: String?) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text(suffix.map { "\(value)\($0)" } ?? calendar.monthSymbols[value - 1])
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
    }
}
