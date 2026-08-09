import SwiftUI

/// Anlegen/Bearbeiten. Die Erinnerung ist der EINZIGE Ort, der die
/// Benachrichtigungs-Berechtigung auslösen darf — beim aktiven Einschalten.
struct EditHabitSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: HabitStore
    var existing: Habit?

    @State private var name = ""
    @State private var emoji = ""
    @State private var reminderOn = false
    @State private var reminderTime = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? .now
    @State private var permissionDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Name (z. B. 20 Minuten lesen)"), text: $name)
                        .accessibilityIdentifier("habit-name")
                    TextField(String(localized: "Emoji (optional)"), text: $emoji)
                        .accessibilityIdentifier("habit-emoji")
                }
                Section {
                    Toggle(String(localized: "Tägliche Erinnerung"), isOn: $reminderOn)
                        .accessibilityIdentifier("reminder-toggle")
                    if reminderOn {
                        DatePicker(String(localized: "Uhrzeit"), selection: $reminderTime, displayedComponents: .hourAndMinute)
                    }
                    if permissionDenied {
                        Text(String(localized: "Benachrichtigungen sind in den iOS-Einstellungen deaktiviert. Dort einschalten, dann klappt die Erinnerung."))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    Text(String(localized: "Gefragt wird nur, wenn du eine Erinnerung einschaltest — nie einfach so."))
                }
                if existing != nil {
                    Section {
                        Button(String(localized: "Habit löschen"), role: .destructive) {
                            if let h = existing { store.remove(h.id) }
                            dismiss()
                        }
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
        .onAppear {
            if let h = existing {
                name = h.name
                emoji = h.emoji
                if let m = h.reminderMinutes {
                    reminderOn = true
                    reminderTime = Calendar.current.date(from: DateComponents(hour: m / 60, minute: m % 60)) ?? .now
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let minutes: Int? = reminderOn
            ? Calendar.current.component(.hour, from: reminderTime) * 60
              + Calendar.current.component(.minute, from: reminderTime)
            : nil

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
                if existing == nil { store.add(h) } else { store.update(h) }
                Theme.Haptics.success()
                dismiss()
            }
        }
    }
}
