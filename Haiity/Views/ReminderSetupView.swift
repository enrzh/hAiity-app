import SwiftUI

struct ReminderSetupView: View {
    @Binding var isPresented: Bool
    let store: HabitStore

    @AppStorage(ReminderSetup.completedKey) private var completed = false
    @State private var enabled = false
    @State private var denied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 52, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Theme.accentText(store.paletteStyle))
                            .frame(width: 72, height: 72)
                            .background(Theme.accent(store.paletteStyle).opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                        Text(String(localized: "Dein Rhythmus"))
                            .font(.largeTitle.bold())
                        Text(String(localized: "hAiity erinnert dich einmal am Tag an offene Habits und fasst deine Woche zusammen. Du bestimmst, ob und wann diese Hinweise kommen."))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 0) {
                        setupRow("sun.max.fill", String(localized: "Tageszusammenfassung aktivieren"))
                        Divider().padding(.leading, 44)
                        setupRow("calendar", String(localized: "Erinnerungen"))
                    }
                    .padding(.horizontal, 16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

                    Toggle(String(localized: "Tageszusammenfassung aktivieren"), isOn: $enabled)
                        .tint(Theme.accent(store.paletteStyle))
                    if denied {
                        Label(String(localized: "Benachrichtigungen sind in den iOS-Einstellungen deaktiviert."), systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
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
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "Erinnerungen"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func setupRow(_ symbol: String, _ title: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    }

    private func finish() {
        completed = true
        isPresented = false
    }
}
