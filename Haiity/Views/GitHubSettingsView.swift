import SwiftUI
import UIKit

/// Verbindung, Code, Aktualisieren und Trennen. Kein Passwort, kein Scope.
struct GitHubSettingsView: View {
    let store: GitHubContributionStore
    @Binding var showsUsername: Bool
    @Binding var showsMonthLabels: Bool
    @State private var confirmDisconnect = false
    @State private var codeCopied = false
    @Environment(\.palettes) private var palettes

    var body: some View {
        List {
            connectionSection
            displaySection
        }
        .moreSettingsSurface()
        .appPageHeader("GitHub")
        .onAppear {
            copyCode(store.deviceCode)
            // Hydrate from the cache first. A stale graph may refresh in the
            // background, but opening this page must not show a blank action
            // row or force a network request every time it appears.
            Task { await store.resumeOrRefresh() }
        }
        .onChange(of: store.deviceCode) { _, code in
            copyCode(code)
        }
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

    private var connectionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                connectionStatusRow
                contributionPreview
                Divider()
                    .padding(.leading, 44)
                    .padding(.vertical, 4)
                connectionControls
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("github-connection")
        }
        .moreSettingsSection()
    }

    private var displaySection: some View {
        Section {
            VStack(spacing: 0) {
                Toggle(isOn: $showsUsername) {
                    Label(String(localized: "GitHub-Namen anzeigen"),
                          systemImage: "person.crop.circle")
                }
                .accessibilityIdentifier("github-username-toggle")
                .frame(minHeight: Theme.Metrics.hit)

                Divider()
                    .padding(.leading, 32)

                Toggle(isOn: $showsMonthLabels) {
                    Label(String(localized: "GitHub-Monate anzeigen"),
                          systemImage: "calendar")
                }
                .accessibilityIdentifier("github-month-labels-toggle")
                .frame(minHeight: Theme.Metrics.hit)
            }
            .padding(.vertical, 2)
            .accessibilityIdentifier("github-display-settings")
        } header: {
            Text(String(localized: "Darstellung"))
        }
        .moreSettingsSection()
    }

    @ViewBuilder
    private var connectionControls: some View {
        switch store.phase {
        case .disconnected:
            if GitHubAppConfig.isConfigured {
                Button {
                    Task { await store.connect() }
                } label: {
                    Label(String(localized: "GitHub verbinden"), systemImage: "link")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("github-connect")
            } else {
                Text(String(localized: "GitHub ist nicht eingerichtet."))
                    .foregroundStyle(.secondary)
            }
        case .connecting:
            if let code = store.deviceCode {
                VStack(alignment: .leading, spacing: Theme.Metrics.gap + 2) {
                    Text(String(localized: "Code auf GitHub eingeben"))
                        .font(.subheadline)
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
                        Label(String(localized: "Auf GitHub öffnen"),
                              systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("github-open-verification")
                    HStack(spacing: Theme.Metrics.gap) {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(String(localized: "Code auf GitHub eingeben"))
                    }
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
                    HStack(spacing: Theme.Metrics.gap) {
                        if store.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else if case .success = store.refreshFeedback {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .symbolEffect(.bounce, value: store.refreshAnimationToken)
                                .accessibilityIdentifier("github-refresh-success")
                        } else if case .reauthenticationRequired = store.refreshFeedback {
                            Image(systemName: "person.crop.circle.badge.arrow.forward")
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(refreshActionTitle)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.Metrics.hit,
                           alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("github-refresh")
                .disabled(store.isRefreshing)
                .animation(.easeInOut(duration: 0.2), value: store.refreshAnimationToken)
                refreshFeedbackView
                Divider()
                    .padding(.vertical, 4)
                disconnectButton
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("github-refresh-failure")
                if store.hasStoredCredentials {
                    Button(String(localized: "Aktualisieren")) {
                        Task { await store.refresh(forced: true) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("github-refresh")
                } else {
                    Button(String(localized: "Erneut versuchen")) {
                        Task { await store.connect() }
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
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accentText(palettes.style))
                    .frame(width: 36, height: 36)
                    .background(Theme.accentFill(palettes.style).opacity(0.14),
                                in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }
                Circle()
                    .fill(statusTint)
                    .frame(width: 10, height: 10)
                    .overlay {
                        Circle()
                            .stroke(Color(.systemBackground), lineWidth: 2)
                    }
                    .offset(x: 1, y: 1)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                if let username = store.snapshot?.username,
                   case .connected = store.phase {
                    Text(String(localized: "Verbunden als \(username)"))
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .accessibilityIdentifier("github-connected-name")
                } else {
                    Text(statusTitle)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                }
                if case .connected = store.phase,
                   let snapshot = store.snapshot {
                    Text(snapshot.fetchedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else {
                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }

    @ViewBuilder
    private var contributionPreview: some View {
        if case .connected = store.phase,
           let snapshot = store.snapshot {
            GitHubContributionGraph(days: snapshot.days,
                                    weeks: 24,
                                    showsMonthLabels: false,
                                    interactive: false,
                                    palette: palettes.style)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 44)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .accessibilityIdentifier("github-settings-preview")
        }
    }

    private var disconnectButton: some View {
        Button(String(localized: "Verbindung trennen"), role: .destructive) {
            confirmDisconnect = true
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.hit,
               alignment: .leading)
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

    private var statusTitle: String {
        switch store.phase {
        case .connected: return String(localized: "GitHub-Beitragskalender")
        case .connecting: return String(localized: "Code auf GitHub eingeben")
        case .failed: return String(localized: "Die Verbindung zu GitHub ist fehlgeschlagen.")
        case .disconnected: return String(localized: "GitHub verbinden")
        }
    }

    private var statusSubtitle: String {
        switch store.phase {
        case .connected:
            return String(localized: "Dein offizieller GitHub-Beitragskalender erscheint auf der Habits-Seite.")
        case .connecting:
            return String(localized: "Code auf GitHub eingeben")
        case .failed:
            return String(localized: "Erneut versuchen")
        case .disconnected:
            return String(localized: "Dein offizieller GitHub-Beitragskalender erscheint auf der Habits-Seite.")
        }
    }

    @ViewBuilder
    private var refreshFeedbackView: some View {
        if case .failure(let message) = store.refreshFeedback {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
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
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
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
