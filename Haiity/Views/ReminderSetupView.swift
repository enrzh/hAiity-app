import SwiftUI

/// Der Einrichtungs-Bildschirm für Mitteilungen — erreichbar über Mehr →
/// „Erinnerungen einrichten", aber bewusst nicht Teil des ersten Starts.
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

    @State private var dailyEnabled = true
    @State private var weeklyEnabled = true
    @State private var denied = false
    @State private var page = 0
    @State private var proStatus = ProStatus.shared
    @State private var calendarPermissionGranted = false
    @State private var remindersPermissionGranted = false
    @State private var requestingPermission: NativePermission?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum NativePermission: Equatable {
        case calendar
        case reminders
    }

    private static let lastPage = 2

    private var unlocked: Bool {
        _ = proStatus.unlocked
        return Pro.isUnlocked
    }

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
        .pageHeaderChrome()
        .onAppear { refreshPermissions() }
    }

    // MARK: – Seiten

    /// Jede Seite scrollt für sich — große Schriftgrade brauchen den Platz.
    private func setupPage<Content: View>(
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Metrics.gutter) {
                    content()
                }
                .frame(maxWidth: .infinity,
                       minHeight: max(0, proxy.size.height - Theme.Metrics.gutter * 2),
                       alignment: .top)
                .padding(.horizontal, Theme.Metrics.gutter)
                .padding(.top, Theme.Metrics.gutter * 2)
                .padding(.bottom, Theme.Metrics.gutter)
            }
        }
        .softScrollEdges()
    }

    private var introPage: some View {
        setupPage {
            MotifGrid(pattern: MotifGrid.brand,
                      palette: store.paletteStyle, cellSize: 16)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            Text(String(localized: "Dein Rhythmus"))
                .font(store.appearancePreferences.designStyle.pageTitleFont)
            Text(String(localized: "Wähle deine Zusammenfassungen."))
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var summariesPage: some View {
        setupPage {
            Text(String(localized: "Zusammenfassungen"))
                .font(store.appearancePreferences.designStyle.pageTitleFont)
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
                .font(store.appearancePreferences.designStyle.pageTitleFont)
                .padding(.top, 8)
            Text(String(localized: "Du entscheidest, ob hAiity Mitteilungen senden darf."))
                .font(.body)
                .foregroundStyle(.secondary)
            habitReminderCard
            calendarPermissionCard
            if denied {
                deniedHint
            }
        }
    }

    // MARK: – Karten

    private func summaryCard(symbol: String, title: String, text: String,
                             isOn: Binding<Bool>, identifier: String) -> some View {
        card {
            Toggle(isOn: isOn) {
                AppSettingsRow(title: title, detail: text, symbol: symbol) {
                    EmptyView()
                }
            }
            .tint(Theme.accentFill(store.paletteStyle))
            .accessibilityIdentifier(identifier)
        }
    }

    /// Habit-Erinnerungen haben hier bewusst KEINEN Schalter: sie hängen an
    /// der Uhrzeit des einzelnen Habits. Die Karte sagt nur, wo sie wohnen.
    private var habitReminderCard: some View {
        card {
            AppSettingsRow(title: String(localized: "Habit-Erinnerungen"),
                           detail: String(localized: "Die Uhrzeit stellst du direkt am Eintrag ein."),
                           symbol: "bell.badge.fill") {
                EmptyView()
            }
        }
    }

    /// Native integrations are optional, but their permission request belongs
    /// visibly in setup rather than being hidden behind the final notification
    /// button. The rows remain available for Pro users and explain the gate
    /// for everyone else without requesting anything on mere page appearance.
    private var calendarPermissionCard: some View {
        card {
            VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
                Label(String(localized: "Apple-Apps verbinden"),
                      systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                Text(String(localized: "Eigene Einträge können mit Kalender und Erinnerungen synchronisiert werden."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                permissionRow(title: String(localized: "Kalender"),
                              symbol: "calendar",
                              granted: calendarPermissionGranted,
                              permission: .calendar,
                              action: requestCalendarPermission)
                    .accessibilityIdentifier("setup-calendar-permission")
                Divider()
                permissionRow(title: String(localized: "Erinnerungen"),
                              symbol: "checklist",
                              granted: remindersPermissionGranted,
                              permission: .reminders,
                              action: requestRemindersPermission)
                    .accessibilityIdentifier("setup-reminders-permission")
            }
        }
        .accessibilityIdentifier("setup-native-permissions")
    }

    private func permissionRow(title: String,
                               symbol: String,
                               granted: Bool,
                               permission: NativePermission,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            AppSettingsRow(title: title, symbol: symbol) {
                if requestingPermission == permission {
                    ProgressView()
                        .controlSize(.small)
                } else if granted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if unlocked {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                } else {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .disabled(!unlocked || requestingPermission != nil)
        .accessibilityLabel(title)
        .accessibilityValue(
            requestingPermission == permission
                ? String(localized: "Wird geladen")
                : granted
                    ? String(localized: "Erlaubt")
                    : unlocked
                        ? String(localized: "Nicht aktiviert")
                        : String(localized: "Nur mit hAiity Pro"))
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        content().appCard()
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
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                        page += 1
                    }
                } label: {
                    Text(String(localized: "Weiter"))
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.hit)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentFill(store.paletteStyle))
                .accessibilityIdentifier("setup-next")
            } else {
                Button {
                    enable()
                } label: {
                    Label(String(localized: "Berechtigungen aktivieren"), systemImage: "lock.open")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.hit)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentFill(store.paletteStyle))
                .accessibilityIdentifier("enable-notifications")
            }
            Button(String(localized: "Jetzt nicht")) { finish() }
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.hit)
                .accessibilityIdentifier("skip-notification-setup")
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, 12)
        .background(.clear)
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
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Einrichtungsseite"))
        .accessibilityValue(String.localizedStringWithFormat(
            String(localized: "Seite %d von %d"), page + 1, Self.lastPage + 1))
    }

    private func enable() {
        Task {
            let notificationsGranted = await Reminders.ensurePermission()
            var calendarGranted = calendarPermissionGranted
            var remindersGranted = remindersPermissionGranted
            if unlocked {
                calendarGranted = await CalendarSync.requestAccess()
                remindersGranted = await ReminderSync.requestAccess()
            }
            await MainActor.run {
                calendarPermissionGranted = calendarGranted
                remindersPermissionGranted = remindersGranted
                denied = !notificationsGranted
                guard notificationsGranted else { return }
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

    private func refreshPermissions() {
        calendarPermissionGranted = CalendarSync.hasAccess
        remindersPermissionGranted = ReminderSync.hasAccess
    }

    private func requestCalendarPermission() {
        guard unlocked else { return }
        requestingPermission = .calendar
        Task {
            let granted = await CalendarSync.requestAccess()
            await MainActor.run {
                calendarPermissionGranted = granted
                requestingPermission = nil
            }
        }
    }

    private func requestRemindersPermission() {
        guard unlocked else { return }
        requestingPermission = .reminders
        Task {
            let granted = await ReminderSync.requestAccess()
            await MainActor.run {
                remindersPermissionGranted = granted
                requestingPermission = nil
            }
        }
    }

    private func finish() {
        isPresented = false
    }
}
