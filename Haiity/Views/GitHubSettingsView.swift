import SwiftUI
import UIKit

/// Verbindung, Code, Aktualisieren und Trennen. Kein Passwort, kein Scope.
struct GitHubSettingsView: View {
    let store: GitHubContributionStore
    @Binding var showsUsername: Bool
    @Binding var showsMonthLabels: Bool
    @State private var confirmDisconnect = false
    @State private var codeCopied = false
    /// Owns the "copied" tick. Held so leaving the page cancels it instead of
    /// leaving a timer running against a view that is gone.
    @State private var copyReset: Task<Void, Never>?
    @Environment(\.palettes) private var palettes
    @Environment(\.appearancePreferences) private var appearancePreferences

    private var designStyle: AppDesignStyle { appearancePreferences.designStyle }

    var body: some View {
        // Not a `List`: iOS 27 drops taps on grouped list rows. The hub already
        // uses the continuous group surface, and this page now matches it.
        SettingsPage {
            VStack(alignment: .leading, spacing: designStyle.sectionGap) {
                connectionGroup
                displayGroup
            }
            .frame(maxWidth: Theme.Metrics.readableContentWidth)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("GitHub")
        .navigationBarTitleDisplayMode(.inline)
        .pageHeaderChrome()
        .onAppear {
            // No copying here. The code used to be put on the pasteboard the
            // moment this page appeared, which overwrote whatever the person was
            // holding without them asking for it. The button is right next to the
            // code and says what it does.
            //
            // Hydrate from the cache first. A stale graph may refresh in the
            // background, but opening this page must not show a blank action
            // row or force a network request every time it appears.
            Task { await store.resumeOrRefresh() }
        }
        .onDisappear { copyReset?.cancel() }
        .confirmationDialog(String(localized: "GitHub-Konto trennen?"),
                            isPresented: $confirmDisconnect,
                            titleVisibility: .visible) {
            Button(String(localized: "Verbindung trennen"), role: .destructive) {
                store.disconnect()
            }
            .accessibilityIdentifier("github-disconnect")
        } message: {
            Text(String(localized: "Der Beitragskalender verschwindet von der Habits-Seite."))
        }
    }

    private var connectionGroup: some View {
        AppSettingsGroup(title: String(localized: "Verbindung"),
                         footer: connectionFooter) {
            VStack(alignment: .leading, spacing: 0) {
                connectionStatusRow
                contributionPreview
                Divider()
                    .padding(.leading, Theme.Metrics.rowTitleInset)
                    .padding(.vertical, designStyle.rowGap)
                connectionControls
            }
            .padding(.vertical, designStyle.rowGap)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("github-connection")
        }
    }

    /// What the group is for, in the group's own terms. The "not configured"
    /// state used to be one grey sentence with no action and no explanation —
    /// a dead end that read like an error the person had caused.
    private var connectionFooter: String? {
        switch store.phase {
        case .disconnected where !GitHubAppConfig.isConfigured:
            return String(localized: "In dieser Fassung ist die GitHub-Verbindung nicht enthalten. Der Beitragskalender lässt sich deshalb nicht verbinden.")
        case .connected:
            return String(localized: "hAiity liest nur den Beitragskalender. Es wird nichts auf deinem GitHub-Konto verändert.")
        default:
            return nil
        }
    }

    private var displayGroup: some View {
        AppSettingsGroup(title: String(localized: "Darstellung")) {
            VStack(spacing: 0) {
                Toggle(isOn: $showsUsername) {
                    AppSettingsRow(title: String(localized: "GitHub-Namen anzeigen"),
                                   symbol: "person.crop.circle") {
                        EmptyView()
                    }
                }
                .tint(Theme.accentFill(palettes.style))
                .accessibilityIdentifier("github-username-toggle")

                Divider()
                    .padding(.leading, Theme.Metrics.rowTitleInset)

                Toggle(isOn: $showsMonthLabels) {
                    AppSettingsRow(title: String(localized: "GitHub-Monate anzeigen"),
                                   symbol: "calendar") {
                        EmptyView()
                    }
                }
                .tint(Theme.accentFill(palettes.style))
                .accessibilityIdentifier("github-month-labels-toggle")
            }
            .padding(.vertical, designStyle.rowGap / 2)
            // Contain, don't merge: outside a `List` a plain container
            // identifier bleeds onto its children and both toggles answer as
            // "github-display-settings". This keeps each toggle addressable.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("github-display-settings")
        }
    }

    @ViewBuilder
    private var connectionControls: some View {
        switch store.phase {
        case .disconnected:
            if GitHubAppConfig.isConfigured {
                Button {
                    Task { await store.connect() }
                } label: {
                    AppSettingsRow(title: String(localized: "GitHub verbinden"), symbol: "link") {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("github-connect")
            } else {
                // The sentence stays as it was — it is translated into every
                // shipped language and a contract test holds it there. The
                // missing "why" is the footer's job, not a reworded error.
                Text(String(localized: "GitHub ist nicht eingerichtet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .connecting:
            if let code = store.deviceCode {
                VStack(alignment: .leading, spacing: designStyle.rowGap * 2 + 2) {
                    Text(String(localized: "Dein Code"))
                        .font(designStyle.sectionTitleFont)
                        .foregroundStyle(.secondary)
                    HStack(spacing: Theme.Metrics.gap) {
                        Text(verbatim: code.userCode)
                            .font(.title2.monospaced().weight(.semibold))
                            .textSelection(.enabled)
                            .accessibilityIdentifier("github-user-code")
                        Spacer(minLength: 0)
                        Button {
                            copyCode(code)
                        } label: {
                            Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                                .font(.body.weight(.semibold))
                                .frame(width: Theme.Metrics.hit, height: Theme.Metrics.hit)
                                .contentShape(Rectangle())
                                .symbolEffect(.bounce, value: codeCopied)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: codeCopied ? "Code kopiert." : "Code kopieren"))
                        .accessibilityIdentifier(codeCopied ? "github-copy-confirmation" : "github-copy-code")
                    }
                    Button {
                        GitHubLink.open(code.verificationURLWithCode)
                    } label: {
                        AppSettingsRow(title: String(localized: "Auf GitHub öffnen"),
                                       symbol: "arrow.up.right.square") {
                            EmptyView()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("github-open-verification")
                    // A spinner with nothing beside it tells the person their app
                    // is busy and nothing about what it is waiting for. GitHub's
                    // device flow is a round trip through a website and can sit
                    // idle for a while, so it says what is pending and offers a
                    // way out — a pending code is not a connection, so leaving
                    // costs nothing.
                    HStack(spacing: Theme.Metrics.gap) {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "Warte auf die Bestätigung in GitHub. Das kann einen Moment dauern."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(localized: "Warte auf die Bestätigung in GitHub."))
                    Button {
                        store.cancelConnect()
                    } label: {
                        AppSettingsRow(title: String(localized: "Abbrechen"), symbol: "xmark") {
                            EmptyView()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("github-cancel-connect")
                }
            }
        case .connected:
            VStack(spacing: 0) {
                Button {
                    Task {
                        if case .reauthenticationRequired = store.refreshFeedback {
                            store.prepareForReauthentication()
                            await store.connect()
                        } else {
                            await store.refresh(forced: true)
                        }
                    }
                } label: {
                    AppSettingsRow(title: refreshActionTitle,
                                   symbol: store.refreshFeedback == .reauthenticationRequired
                                    ? "person.crop.circle.badge.arrow.forward" : "arrow.clockwise") {
                        if store.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else if case .success = store.refreshFeedback {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .symbolEffect(.bounce, value: store.refreshAnimationToken)
                                .accessibilityIdentifier("github-refresh-success")
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("github-refresh")
                .disabled(store.isRefreshing)
                .animation(.easeInOut(duration: 0.2), value: store.refreshAnimationToken)
                refreshFeedbackView
                Divider()
                    .padding(.vertical, designStyle.rowGap)
                disconnectButton
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: designStyle.rowGap * 2) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("github-refresh-failure")
                if store.hasStoredCredentials {
                    Button {
                        Task { await store.refresh(forced: true) }
                    } label: {
                        AppSettingsRow(title: String(localized: "Aktualisieren"), symbol: "arrow.clockwise") {
                            EmptyView()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("github-refresh")
                } else {
                    Button {
                        Task { await store.connect() }
                    } label: {
                        AppSettingsRow(title: String(localized: "Erneut versuchen"), symbol: "arrow.clockwise") {
                            EmptyView()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("github-connect")
                }
                disconnectButton
            }
        }
    }

    private var connectionStatusRow: some View {
        HStack(spacing: Theme.Metrics.gap + 4) {
            ZStack(alignment: .bottomTrailing) {
                AppIconBadge(symbol: "chevron.left.forwardslash.chevron.right")
                Circle()
                    .fill(statusTint)
                    .frame(width: 10, height: 10)
                    .overlay {
                        Circle()
                            .stroke(Color(.systemBackground), lineWidth: 2)
                    }
                    .offset(x: 1, y: 1)
            }
            .frame(width: Theme.Metrics.glyph, height: Theme.Metrics.glyph)
            VStack(alignment: .leading, spacing: 2) {
                if let username = store.snapshot?.username,
                   case .connected = store.phase {
                    Text(String(localized: "Verbunden als \(username)"))
                        .font(designStyle.rowTitleFont)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("github-connected-name")
                } else {
                    Text(statusTitle)
                        .font(designStyle.rowTitleFont)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if case .connected = store.phase,
                   let snapshot = store.snapshot {
                    Text(snapshot.fetchedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(statusSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: designStyle.settingsRowHeight, alignment: .leading)
    }

    @ViewBuilder
    private var contributionPreview: some View {
        if case .connected = store.phase,
           let snapshot = store.snapshot {
            // One source of truth for the grid. The cell size used to subtract a
            // hard-coded column-count times a hard-coded gap while also passing a
            // different `gap` to the graph, so the maths and the grid could
            // disagree the moment either number changed — and the last column
            // would quietly overflow.
            let weeks = 24
            let gap: CGFloat = 3
            GeometryReader { geometry in
                let columns = CGFloat(weeks - 1)
                GitHubContributionGraph(days: snapshot.days,
                                        weeks: weeks,
                                        cellSize: max(1, (geometry.size.width - columns * gap) / CGFloat(weeks)),
                                        gap: gap,
                                        showsMonthLabels: false,
                                        interactive: false,
                                        palette: palettes.style)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
                .aspectRatio(CGFloat(weeks) / CGFloat(GridCalendar.rows), contentMode: .fit)
                .padding(.top, 8)
                .padding(.bottom, 6)
                // The graph labels itself "GitHub-Beitragskalender", which is true
                // but not useful here: this is the proof of what connecting gets
                // you, sitting above the controls that do the connecting.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Vorschau deines Beitragskalenders"))
                .accessibilityIdentifier("github-settings-preview")
        }
    }

    /// The only control here that can lose something, so it has to look like it.
    ///
    /// It declared `role: .destructive` and then used `.buttonStyle(.plain)`,
    /// which discards exactly the red that role is supposed to add — the one
    /// action that unlinks an account looked identical to "Aktualisieren". The
    /// colour is set here rather than left to the style, and there is a symbol as
    /// well, so the difference does not rest on colour alone.
    private var disconnectButton: some View {
        Button(role: .destructive) {
            confirmDisconnect = true
        } label: {
            HStack(spacing: Theme.Metrics.gap + 4) {
                AppIconBadge(symbol: "link.badge.minus", tint: .red)
                AppSettingsRow(title: String(localized: "Verbindung trennen")) {
                    EmptyView()
                }
            }
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("github-disconnect")
    }

    private var refreshActionTitle: String {
        if case .reauthenticationRequired = store.refreshFeedback {
            return String(localized: "Erneut anmelden")
        }
        return String(localized: "Aktualisieren")
    }

    private var statusTint: Color {
        switch store.phase {
        case .connected: return .green
        case .connecting: return .orange
        case .failed: return .red
        case .disconnected: return .secondary
        }
    }

    /// The title is the thing, not the state. It used to hold a whole sentence
    /// in the failure case — "Die Verbindung zu GitHub ist fehlgeschlagen." —
    /// which made the most important row the least scannable one and repeated
    /// what the red message underneath already said.
    private var statusTitle: String {
        switch store.phase {
        case .connecting: return String(localized: "Anmeldung läuft")
        case .connected, .disconnected, .failed: return String(localized: "GitHub-Beitragskalender")
        }
    }

    /// The state, in a few words. The specific reason for a failure stays in the
    /// message below the controls, where it can be read in full instead of being
    /// clipped to two lines, and the action stays on the button.
    private var statusSubtitle: String {
        switch store.phase {
        case .connected:
            return String(localized: "Dein offizieller GitHub-Beitragskalender erscheint auf der Habits-Seite.")
        case .disconnected:
            return String(localized: "Zeigt die Beiträge der letzten Monate auf der Habits-Seite.")
        case .connecting:
            return String(localized: "Der Code muss bei GitHub bestätigt werden.")
        case .failed:
            return String(localized: "Nicht verbunden")
        }
    }

    @ViewBuilder
    private var refreshFeedbackView: some View {
        if case .failure(let message) = store.refreshFeedback {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.red)
                .accessibilityIdentifier("github-refresh-failure")
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func copyCode(_ code: GitHubDeviceCode?) {
        guard let code else { return }
        UIPasteboard.general.string = code.userCode
        codeCopied = true
        Theme.Haptics.success()
        // Replaces any tick still running, so a second tap cannot be undone by
        // the first one's timer firing.
        copyReset?.cancel()
        copyReset = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            codeCopied = false
        }
    }
}

enum GitHubLink {
    static func open(_ url: URL?) {
        guard let url, url.scheme?.lowercased() == "https" else { return }
        UIApplication.shared.open(url)
    }
}
