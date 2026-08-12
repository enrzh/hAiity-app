import SwiftUI

struct ReminderSetupView: View {
    @Binding var isPresented: Bool
    let store: HabitStore

    @AppStorage(ReminderSetup.completedKey) private var completed = false
    @State private var enabled = false
    @State private var denied = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(Theme.accentText(store.paletteStyle))
                Text(String(localized: "Dein Rhythmus"))
                    .font(.largeTitle.bold())
                Text(String(localized: "hAiity erinnert dich einmal am Tag an offene Habits und fasst deine Woche zusammen. Du bestimmst, ob und wann diese Hinweise kommen."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                Toggle(String(localized: "Tageszusammenfassung aktivieren"), isOn: $enabled)
                if denied {
                    Text(String(localized: "Benachrichtigungen sind in den iOS-Einstellungen deaktiviert."))
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button {
                    Task {
                        let granted = await Reminders.ensurePermission()
                        await MainActor.run {
                            denied = !granted
                            if granted && enabled { store.summaryMinutes = store.summaryMinutes ?? 20 * 60 }
                            finish()
                        }
                    }
                } label: {
                    Label(String(localized: "Benachrichtigungen aktivieren"), systemImage: "bell")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("enable-notifications")
                Button(String(localized: "Jetzt nicht")) { finish() }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("skip-notification-setup")
            }
            .padding(28)
            .navigationTitle(String(localized: "Erinnerungen"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func finish() {
        completed = true
        isPresented = false
    }
}
