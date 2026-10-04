import SwiftUI

/// Kurz und ehrlich: das Kein-Server-Prinzip — und ganz unten die
/// Versionszeile, hinter der die versteckte Tür zum Entwicklerbereich sitzt.
struct AboutView: View {
    let store: HabitStore
    /// Bereits getätigte Tipps auf die Versionszeile. Bewusst NICHT
    /// gespeichert: eine halb geöffnete Tür soll den Bildschirm nicht
    /// überleben (siehe `DeveloperAccess`).
    @State private var taps = 0
    /// Refreshed on appearance because Sign in with Apple may establish the
    /// owner identity while More is already alive below this page.
    @State private var developerAvailable = false
    @State private var shakeToReport = ShakeToReport.isEnabled
    @Environment(\.palettes) private var palettes
    @Environment(\.appearancePreferences) private var preferences

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: preferences.designStyle.sectionGap - 4) {
                aboutHero
                privacyCard
                reportCard
                releaseCard
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, ChromeLayout.nativeTabBarClearance + 20)
        }
        .scrollIndicators(.hidden)
        .settingsChrome()
        .appPageHeader(String(localized: "Über"))
        .onAppear {
            shakeToReport = store.cloudPreferences?.shakeToReportEnabled ?? ShakeToReport.isEnabled
            developerAvailable = DeveloperAccess.isAvailable(
                storedAppleUserID: PersonalName.appleUserID,
                storedAppleEmail: PersonalName.appleEmail)
        }
        .onReceive(NotificationCenter.default.publisher(for: ShakeToReport.didChange)) { _ in
            shakeToReport = ShakeToReport.isEnabled
        }
    }

    private var aboutHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Theme.accentFill(palettes.style),
                                in: RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
                Spacer(minLength: 0)
                Image(systemName: "checkmark.seal")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: "hAiity")
                    .font(preferences.designStyle.pageTitleFont)
                Text(String(localized: "Dein Alltag als Contribution-Graph."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .morePanel()
        .accessibilityElement(children: .combine)
    }

    private var privacyCard: some View {
        aboutCard(title: String(localized: "Datenschutz"), symbol: "lock.shield") {
            Text(String(localized: "Kein Tracking, kein hAiity-Server. Deine Daten bleiben auf deinen Geräten und in deiner privaten iCloud."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reportCard: some View {
        Toggle(isOn: Binding(
            get: { shakeToReport },
            set: { enabled in
                shakeToReport = enabled
                ShakeToReport.isEnabled = enabled
                store.updateCloudPreferences(
                    fallback: CloudPreferences(
                        calendarSyncHabits: CalendarSync.syncHabits,
                        calendarSyncReminders: CalendarSync.syncReminders,
                        nativeReminderSync: ReminderSync.isEnabled,
                        shakeToReportEnabled: ShakeToReport.isEnabled,
                        notificationDND: NotificationPromptPreference.state)) {
                    $0.shakeToReportEnabled = enabled
                }
            })) {
                Label(String(localized: "Schütteln zum Melden"),
                      systemImage: "iphone.radiowaves.left.and.right")
            }
            .accessibilityIdentifier("shake-to-report-toggle")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .morePanel()
    }

    private var releaseCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            versionRow
            if developerAvailable { developerRow }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .morePanel()
    }

    private func aboutCard<Content: View>(title: String,
                                          symbol: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline.weight(.semibold))
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .morePanel()
    }

    /// Die Tür. Sie sieht aus wie eine Fußzeile und ist eine: die Version
    /// gehört ohnehin in jede Meldung. Erst ab dem vierten Tipp verrät der
    /// Countdown, dass da etwas ist — vorher wäre sie keine versteckte Tür.
    private var versionRow: some View {
        Button {
            tapVersion()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: AppBuildInfo.versionLine)
                if let hint = DeveloperAccess.hint(for: taps) {
                    Text(hint)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("app-version")
    }

    private var developerRow: some View {
        NavigationLink(value: MoreRoute.developer) {
            Label(String(localized: "Entwickler"), systemImage: "hammer")
        }
        .accessibilityIdentifier("open-developer")
    }

    /// Ein Tipp weiter. Gerechnet wird in `DeveloperAccess`; hier steht nur,
    /// was die ANSICHT damit tut — den einen Schreibvorgang und den Stups,
    /// der das Aufgehen der Tür spürbar macht.
    ///
    /// **Auf fremden Geräten passiert NICHTS.** Kein Countdown, keine
    /// Zählung, kein Stups — die Zeile bleibt eine Versionszeile. Eine Tür,
    /// die sich einen Spalt bewegt, verrät, dass sie eine ist; und der
    /// Countdown „Noch 3 Tipps …" wäre die Anleitung gleich dazu. Wem die Tür
    /// gehört, entscheidet `DeveloperAccess.isOwnerDevice`.
    private func tapVersion() {
        guard DeveloperAccess.isOwnerDevice(storedAppleUserID: PersonalName.appleUserID,
                                                  storedAppleEmail: PersonalName.appleEmail) else {
            return
        }
        let step = DeveloperAccess.next(taps: taps)
        taps = step.taps
        guard step.unlocked else { return }
        DeveloperAccess.isUnlocked = true
        // Ohne Nachfrage: Der Riegel oben hat gerade bestätigt, dass dieses
        // Gerät dem Besitzer gehört — ein zweiter Aufruf derselben Regel im
        // selben Atemzug wäre nur eine Wiederholung.
        developerAvailable = true
        Theme.Haptics.success()
    }
}
