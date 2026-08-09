import SwiftUI

/// Anlegen/Bearbeiten — als Half-Sheet präsentiert. Die Erinnerung ist der
/// EINZIGE Ort, der die Benachrichtigungs-Berechtigung auslösen darf — beim
/// aktiven Einschalten. Neu in v2: Ziel-UI (Rhythmus, Ruhetage, Mengenziel)
/// und Archivieren statt Löschen (endgültig löschen geht nur im Archiv).
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

    // Ziel-Zustand
    @State private var cadenceWeekly = false
    @State private var weeklyTimes = 3
    /// „Einmal pro Woche, und zwar am …" — optional; aus bedeutet: der Tag
    /// ist frei wählbar.
    @State private var fixedWeekdayOn = false
    /// Calendar-Wochentagsnummer (1 = So … 7 = Sa). 2 = Montag als
    /// Vorbelegung.
    @State private var weekday = 2
    @State private var restDays: Set<Int> = []
    @State private var quantityOn = false
    @State private var target = 3
    /// nil = „Wie App" (kein Override) — der Normalfall.
    @State private var habitPalette: PaletteRef?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Name (z. B. 20 Minuten lesen)"), text: $name)
                        .accessibilityIdentifier("habit-name")
                    TextField(String(localized: "Emoji (optional)"), text: $emoji)
                        .accessibilityIdentifier("habit-emoji")
                }
                goalSection
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
    }

    // MARK: – Ziel

    private var goalSection: some View {
        Section {
            Picker(String(localized: "Rhythmus"), selection: $cadenceWeekly) {
                Text(String(localized: "Täglich")).tag(false)
                Text(String(localized: "Pro Woche")).tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("cadence-picker")
            if cadenceWeekly {
                // Fester Tag und „n× pro Woche" schließen sich aus: ein
                // fester Tag IST einmal pro Woche.
                Toggle(String(localized: "Fester Tag"), isOn: $fixedWeekdayOn)
                    .accessibilityIdentifier("fixed-weekday-toggle")
                if fixedWeekdayOn {
                    weekdayPicker
                } else {
                    Stepper(value: $weeklyTimes, in: 1...7) {
                        Text(String(localized: "\(weeklyTimes)× pro Woche"))
                    }
                    .accessibilityIdentifier("weekly-times")
                }
            } else {
                restDayPicker
            }
            Toggle(String(localized: "Mengenziel"), isOn: $quantityOn)
                .accessibilityIdentifier("quantity-toggle")
            if quantityOn {
                Stepper(value: $target, in: 1...99) {
                    Text(String(localized: "Ziel: \(target) pro Tag"))
                }
                .accessibilityIdentifier("quantity-target")
            }
        } header: {
            Text(String(localized: "Ziel"))
        } footer: {
            if cadenceWeekly && fixedWeekdayOn {
                Text(String(localized: "Einmal pro Woche, gedacht am \(weekdayName(weekday)). Die Erinnerung kommt dann wöchentlich an diesem Tag — ein Check-in an einem anderen Tag zählt für die Woche trotzdem."))
            }
        }
    }

    /// Ein Tag, einer davon. Dieselben Chips wie die Ruhetage, nur
    /// Einfachauswahl — dieselbe Geste, dieselbe Optik, andere Bedeutung.
    private var weekdayPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Wochentag"))
                .font(.subheadline)
            HStack(spacing: 6) {
                ForEach(orderedWeekdays, id: \.self) { day in
                    let on = weekday == day
                    Button {
                        weekday = day
                    } label: {
                        Text(shortSymbol(day))
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(on ? Theme.accentFill(palettes.style) : Color(.tertiarySystemFill), in: Capsule())
                            .foregroundStyle(on ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(weekdayName(day))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weekly-weekday")
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

    /// Wochentags-Chips in der Reihenfolge des Nutzerkalenders; Auswahl =
    /// Ruhetag (bricht keine Serie, zählt nicht mit).
    private var restDayPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Ruhetage"))
                .font(.subheadline)
            HStack(spacing: 6) {
                ForEach(orderedWeekdays, id: \.self) { weekday in
                    let on = restDays.contains(weekday)
                    Button {
                        if on { restDays.remove(weekday) } else { restDays.insert(weekday) }
                    } label: {
                        Text(shortSymbol(weekday))
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(on ? Theme.accentFill(palettes.style) : Color(.tertiarySystemFill), in: Capsule())
                            .foregroundStyle(on ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Calendar-Wochentagsnummern (1 = So … 7 = Sa) ab `firstWeekday`.
    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    private func shortSymbol(_ weekday: Int) -> String {
        let symbol = Calendar.current.shortWeekdaySymbols[weekday - 1]
        return symbol.hasSuffix(".") ? String(symbol.dropLast()) : symbol
    }

    /// Voller Wochentagsname — für Fußzeile und Vorlesen, wo „Mo" zu wenig
    /// ist.
    private func weekdayName(_ weekday: Int) -> String {
        Calendar.current.weekdaySymbols[max(0, min(6, weekday - 1))]
    }

    // MARK: – Erinnerung (Berechtigungs-Gate unverändert aus v1)

    /// Bei festem Wochentag klingelt es WÖCHENTLICH — die Beschriftung sagt
    /// das auch, sonst verspricht ein „Tägliche Erinnerung" etwas, was die
    /// App gar nicht plant (siehe Reminders.plan).
    private var weeklyReminder: Bool { cadenceWeekly && fixedWeekdayOn }

    private var reminderSection: some View {
        Section {
            Toggle(weeklyReminder
                   ? String(localized: "Wöchentliche Erinnerung")
                   : String(localized: "Tägliche Erinnerung"),
                   isOn: $reminderOn)
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
            Text(reminderOn && weeklyReminder
                 ? String(localized: "Klingelt jeden \(weekdayName(weekday)) zur gewählten Zeit. Gefragt wird nur, wenn du eine Erinnerung einschaltest — nie einfach so.")
                 : String(localized: "Gefragt wird nur, wenn du eine Erinnerung einschaltest — nie einfach so."))
        }
    }

    // MARK: – Laden / Sichern

    private func load() {
        guard let h = existing else { return }
        name = h.name
        emoji = h.emoji
        if let m = h.reminderMinutes {
            reminderOn = true
            reminderTime = Calendar.current.date(from: DateComponents(hour: m / 60, minute: m % 60)) ?? .now
        }
        switch h.goal.cadence {
        case .daily:
            cadenceWeekly = false
        case .weekly(let times):
            cadenceWeekly = true
            // Bei festem Tag ist times normalisiert 1 — der Stepper würde
            // beim Abschalten des festen Tages sonst auf „1× pro Woche"
            // stehen. 3 ist die Vorbelegung, die auch ein neues Habit hat.
            if let day = h.goal.weekday {
                fixedWeekdayOn = true
                weekday = day
            } else {
                weeklyTimes = times
            }
        }
        restDays = h.goal.restDays
        habitPalette = h.palette
        if let t = h.goal.target {
            quantityOn = true
            target = t
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let minutes: Int? = reminderOn
            ? Calendar.current.component(.hour, from: reminderTime) * 60
              + Calendar.current.component(.minute, from: reminderTime)
            : nil
        // Der Init normalisiert: ein fester Tag zieht times auf 1, ein Tag
        // ohne Wochen-Kadenz fällt weg.
        let goal = Goal(
            cadence: cadenceWeekly ? .weekly(times: Goal.clampTimes(weeklyTimes)) : .daily,
            restDays: cadenceWeekly ? [] : restDays,
            target: quantityOn ? target : nil,
            weekday: cadenceWeekly && fixedWeekdayOn ? weekday : nil)

        Task {
            var granted = true
            if minutes != nil { granted = await Reminders.ensurePermission() }
            await MainActor.run {
                if minutes != nil && !granted {
                    permissionDenied = true
                    return
                }
                var h = existing ?? Habit(name: trimmed, emoji: emoji)
                h.name = trimmed
                h.emoji = emoji.trimmingCharacters(in: .whitespaces)
                h.reminderMinutes = minutes
                h.goal = goal
                h.palette = habitPalette
                if existing == nil { store.add(h) } else { store.update(h) }
                Theme.Haptics.success()
                dismiss()
            }
        }
    }
}
