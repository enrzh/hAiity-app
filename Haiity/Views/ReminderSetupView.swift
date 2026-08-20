import SwiftUI

/// Der Einrichtungs-Bildschirm für Mitteilungen — einmal beim ersten Start,
/// später erreichbar über Mehr → „Erinnerungen einrichten".
///
/// Drei Seiten statt einer Wand: das Motiv (gestaffelt aufgebaut, wie im
/// Leerzustand), die Zusammenfassungen mit ihren Schaltern, dann der große
/// Knopf. Wischen und „Weiter" führen durch; „Jetzt nicht" steht auf JEDER
/// Seite — ein Ausstieg, der erst auf der letzten Seite auftaucht, wäre
/// ein dunkles Muster. Die beiden Zusammenfassungen starten EINGESCHALTET —
/// der große Knopf tut damit genau, was er verspricht.
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
    @State private var page = 0

    private static let lastPage = 2

    private var accent: Color { Theme.accentText(store.paletteStyle) }

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                introPage.tag(0)
                summariesPage.tag(1)
                startPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .safeAreaInset(edge: .bottom) { footer }
            .navigationTitle(String(localized: "Erinnerungen"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .settingsChrome()
    }

    // MARK: – Seiten

    /// Jede Seite scrollt für sich — große Schriftgrade brauchen den Platz.
    private func setupPage(@ViewBuilder content: () -> some View) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Metrics.gutter) {
                content()
            }
            .padding(Theme.Metrics.gutter)
        }
    }

    private var introPage: some View {
        setupPage {
            MotifGrid(pattern: MotifGrid.brand,
                      palette: store.paletteStyle, cellSize: 16)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            Text(String(localized: "Dein Rhythmus"))
                .font(.largeTitle.bold())
            Text(String(localized: "Wähle deine Zusammenfassungen."))
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var summariesPage: some View {
        setupPage {
            Text(String(localized: "Zusammenfassungen"))
                .font(.largeTitle.bold())
                .padding(.top, 8)
            summaryCard(symbol: "sun.max.fill",
                        title: String(localized: "Tageszusammenfassung"),
                        text: String(localized: "Erledigt und offen."),
                        isOn: $dailyEnabled,
                        identifier: "setup-daily-toggle")
            summaryCard(symbol: "calendar",
                        title: String(localized: "Wochenzusammenfassung"),
                        text: String(localized: "Deine Woche in Zahlen."),
                        isOn: $weeklyEnabled,
                        identifier: "setup-weekly-toggle")
        }
    }

    private var startPage: some View {
        setupPage {
            Text(String(localized: "Los geht's"))
                .font(.largeTitle.bold())
                .padding(.top, 8)
            Text(String(localized: "Du entscheidest, ob hAiity Mitteilungen senden darf."))
                .font(.body)
                .foregroundStyle(.secondary)
            habitReminderCard
            if denied {
                deniedHint
            }
        }
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
                    Text(String(localized: "Die Uhrzeit stellst du direkt am Eintrag ein."))
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
            .appSurface()
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
            pageDots
            if page < Self.lastPage {
                Button {
                    withAnimation { page += 1 }
                } label: {
                    Text(String(localized: "Weiter"))
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentFill(store.paletteStyle))
                .accessibilityIdentifier("setup-next")
            } else {
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
            }
            Button(String(localized: "Jetzt nicht")) { finish() }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("skip-notification-setup")
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, 12)
        .background(Color.clear.appSurface(cornerRadius: 0))
    }

    /// Eigene Punkte statt der System-Punkte: die stehen sonst UNTER dem
    /// Fuß und färben sich nicht nach der aktiven Palette.
    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(0...Self.lastPage, id: \.self) { i in
                Circle()
                    .fill(i == page ? Theme.accentFill(store.paletteStyle)
                                    : Color(.systemFill))
                    .frame(width: 7, height: 7)
            }
        }
        .animation(.snappy(duration: 0.25), value: page)
        .accessibilityHidden(true)
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
