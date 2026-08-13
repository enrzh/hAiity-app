import SwiftUI

/// Der Einrichtungs-Bildschirm für Mitteilungen — einmal beim ersten Start,
/// später erreichbar über Mehr → „Erinnerungen einrichten".
///
/// Er spricht die Sprache der App: oben ein kleines Contribution-Muster in
/// der aktiven Farbfamilie (dasselbe Motiv wie Raster und App-Icon), darunter
/// je eine Karte pro Mitteilungsart mit ehrlichem Ein-Satz-Text. Die beiden
/// Zusammenfassungen starten EINGESCHALTET — der große Knopf tut damit
/// genau, was er verspricht. (Vorher stand der einzige Schalter versteckt
/// auf AUS, und „Benachrichtigungen aktivieren" aktivierte: nichts.)
///
/// Die System-Berechtigung wird weiterhin erst beim Tipp auf den großen
/// Knopf angefragt — nie beim Start, nie beim bloßen Anschauen.
struct ReminderSetupView: View {
    @Binding var isPresented: Bool
    let store: HabitStore

    @AppStorage(ReminderSetup.completedKey) private var completed = false
    @State private var dailyEnabled = true
    @State private var weeklyEnabled = true
    @State private var denied = false
    @Environment(\.colorScheme) private var scheme

    private var accent: Color { Theme.accentText(store.paletteStyle) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Metrics.gutter) {
                    hero
                    summaryCard(symbol: "sun.max.fill",
                                title: String(localized: "Tageszusammenfassung"),
                                text: String(localized: "Abends in einem Satz: was erledigt ist und was noch offen steht."),
                                isOn: $dailyEnabled,
                                identifier: "setup-daily-toggle")
                    summaryCard(symbol: "calendar",
                                title: String(localized: "Wochenzusammenfassung"),
                                text: String(localized: "Am Ende der Woche: wie viele Termine du gehalten hast."),
                                isOn: $weeklyEnabled,
                                identifier: "setup-weekly-toggle")
                    habitReminderCard
                    if denied {
                        deniedHint
                    }
                }
                .padding(Theme.Metrics.gutter)
            }
            .safeAreaInset(edge: .bottom) { footer }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "Erinnerungen"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: – Held

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            motifGrid
                .frame(maxWidth: .infinity)
            Text(String(localized: "Dein Rhythmus"))
                .font(.largeTitle.bold())
            Text(String(localized: "hAiity erinnert dich einmal am Tag an offene Habits und fasst deine Woche zusammen. Du bestimmst, ob und wann diese Hinweise kommen."))
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    /// Das Markenmotiv: ein kleines Raster in der Rampe der aktiven Farbe.
    /// FEST gewürfelt (kein `random()`): ein Muster, das bei jedem Aufbau
    /// anders aussieht, wirkt wie ein Ladefehler, nicht wie ein Motiv.
    private var motifGrid: some View {
        let pattern: [Int] = [0, 2, 1, 0, 3, 4, 2, 0, 1, 3, 0, 2,
                              1, 0, 3, 2, 0, 1, 4, 3, 0, 2, 1, 0,
                              2, 3, 0, 1, 4, 0, 2, 1, 3, 0, 4, 2]
        let cols = Array(repeating: GridItem(.fixed(16), spacing: 3), count: 12)
        return LazyVGrid(columns: cols, spacing: 3) {
            ForEach(Array(pattern.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(Theme.level(level, dark: scheme == .dark,
                                      palette: store.paletteStyle))
                    .frame(height: 16)
            }
        }
        .frame(width: 12 * 19)
        .accessibilityHidden(true)
    }

    // MARK: – Karten

    private func summaryCard(symbol: String, title: String, text: String,
                             isOn: Binding<Bool>, identifier: String) -> some View {
        card {
            HStack(alignment: .top, spacing: Theme.Metrics.gap) {
                iconTile(symbol)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Metrics.gap)
                Toggle(title, isOn: isOn)
                    .labelsHidden()
                    .tint(Theme.accentFill(store.paletteStyle))
                    .accessibilityIdentifier(identifier)
            }
        }
    }

    /// Habit-Erinnerungen haben hier bewusst KEINEN Schalter: sie hängen an
    /// der Uhrzeit des einzelnen Habits. Die Karte sagt nur, wo sie wohnen.
    private var habitReminderCard: some View {
        card {
            HStack(alignment: .top, spacing: Theme.Metrics.gap) {
                iconTile("bell.badge.fill")
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Habit-Erinnerungen"))
                        .font(.subheadline.weight(.semibold))
                    Text(String(localized: "Eine feste Uhrzeit je Habit — stellst du beim Anlegen oder Bearbeiten ein."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(Theme.Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                             style: .continuous))
    }

    private func iconTile(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(accent)
            .frame(width: 36, height: 36)
            .background(Theme.accent(store.paletteStyle).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var deniedHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(String(localized: "Benachrichtigungen sind in den iOS-Einstellungen deaktiviert."),
                  systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
            Button(String(localized: "iOS-Einstellungen öffnen")) {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.footnote.weight(.semibold))
            .accessibilityIdentifier("open-notification-settings")
        }
    }

    // MARK: – Fuß

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                enable()
            } label: {
                Label(String(localized: "Benachrichtigungen aktivieren"), systemImage: "bell")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accentFill(store.paletteStyle))
            .accessibilityIdentifier("enable-notifications")
            Button(String(localized: "Jetzt nicht")) { finish() }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("skip-notification-setup")
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func enable() {
        Task {
            let granted = await Reminders.ensurePermission()
            await MainActor.run {
                denied = !granted
                guard granted else { return }
                if dailyEnabled {
                    store.summaryMinutes = store.summaryMinutes ?? 20 * 60
                }
                if weeklyEnabled {
                    store.weeklySummaryMinutes = store.weeklySummaryMinutes ?? 18 * 60
                }
                finish()
            }
        }
    }

    private func finish() {
        completed = true
        isPresented = false
    }
}
