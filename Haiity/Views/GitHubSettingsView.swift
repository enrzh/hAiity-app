import SwiftUI
import UIKit

/// Verbindung, Code, Aktualisieren und Trennen. Kein Passwort, kein Scope.
struct GitHubSettingsView: View {
    let store: GitHubContributionStore
    @Binding var showsUsername: Bool
    @Binding var showsMonthLabels: Bool
    @State private var confirmDisconnect = false
    @State private var codeCopied = false

    var body: some View {
        List {
            Section {
                Text(String(localized: "Dein offizieller GitHub-Beitragskalender erscheint auf der Habits-Seite."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .settingsListRow()
            Section {
                VStack(spacing: 0) {
                    Toggle(isOn: $showsUsername) {
                        Label(String(localized: "GitHub-Namen anzeigen"),
                              systemImage: "person.crop.circle")
                    }
                    .accessibilityIdentifier("github-username-toggle")

                    Divider()
                        .padding(.leading, 32)

                    Toggle(isOn: $showsMonthLabels) {
                        Label(String(localized: "GitHub-Monate anzeigen"),
                              systemImage: "calendar")
                    }
                    .accessibilityIdentifier("github-month-labels-toggle")
                }
                .padding(.vertical, 2)
                .accessibilityIdentifier("github-display-settings")
            } header: {
                Text(String(localized: "Darstellung"))
            }
            .settingsListRow()
            Section {
                content
            }
            .settingsListRow()
        }
        .settingsSurface()
        .navigationTitle(Text(verbatim: "GitHub"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            copyCode(store.deviceCode)
            Task { await store.resumeOrRefresh(forced: true) }
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

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .disconnected:
            if GitHubAppConfig.isConfigured {
                Button(String(localized: "GitHub verbinden")) {
                    Task { await store.connect() }
                }
                .accessibilityIdentifier("github-connect")
            } else {
                Text(String(localized: "GitHub ist nicht eingerichtet."))
                    .foregroundStyle(.secondary)
            }
        case .connecting:
            if let code = store.deviceCode {
                Text(String(localized: "Code auf GitHub eingeben"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(verbatim: code.userCode)
                    .font(.title2.monospaced())
                    .textSelection(.enabled)
                    .accessibilityIdentifier("github-user-code")
                Button {
                    copyCode(code)
                } label: {
                    Label(String(localized: codeCopied ? "Code kopiert." : "Code kopieren"),
                          systemImage: codeCopied ? "checkmark" : "doc.on.doc")
                        .symbolEffect(.bounce, value: codeCopied)
                }
                .accessibilityIdentifier(codeCopied ? "github-copy-confirmation" : "github-copy-code")
                Button(String(localized: "Auf GitHub öffnen")) {
                    GitHubLink.open(code.verificationURLWithCode)
                }
                .accessibilityIdentifier("github-open-verification")
            }
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .leading)
        case .connected:
            if let snapshot = store.snapshot {
                Text(String(localized: "Verbunden als \(snapshot.username)"))
                    .accessibilityIdentifier("github-connected-name")
            }
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
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if case .success = store.refreshFeedback {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: store.refreshAnimationToken)
                        .accessibilityIdentifier("github-refresh-success")
                } else if case .reauthenticationRequired = store.refreshFeedback {
                    Label(String(localized: "Erneut anmelden"), systemImage: "person.crop.circle.badge.arrow.forward")
                } else {
                    Label(String(localized: "Aktualisieren"), systemImage: "arrow.clockwise")
                }
            }
            .accessibilityIdentifier("github-refresh")
            .disabled(store.isRefreshing)
            .animation(.easeInOut(duration: 0.2), value: store.refreshAnimationToken)
            refreshFeedbackView
            Button(String(localized: "Verbindung trennen"), role: .destructive) {
                confirmDisconnect = true
            }
        case .failed(let message):
            Text(message)
                .foregroundStyle(.secondary)
            if store.hasStoredCredentials {
                Button(String(localized: "Aktualisieren")) {
                    Task { await store.refresh(forced: true) }
                }
                .accessibilityIdentifier("github-refresh")
            } else {
                Button(String(localized: "Erneut versuchen")) {
                    Task { await store.connect() }
                }
                .accessibilityIdentifier("github-connect")
            }
            Button(String(localized: "Verbindung trennen"), role: .destructive) {
                store.disconnect()
            }
            .accessibilityIdentifier("github-disconnect")
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
