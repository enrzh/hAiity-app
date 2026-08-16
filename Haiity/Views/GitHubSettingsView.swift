import SwiftUI
import UIKit

/// Verbindung, Code, Aktualisieren und Trennen. Kein Passwort, kein Scope.
struct GitHubSettingsView: View {
    let store: GitHubContributionStore
    @State private var confirmDisconnect = false

    var body: some View {
        List {
            Section {
                Text(String(localized: "Dein offizieller GitHub-Beitragskalender erscheint auf der Habits-Seite."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section {
                content
            }
        }
        .navigationTitle(Text(verbatim: "GitHub"))
        .navigationBarTitleDisplayMode(.inline)
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
                Button(String(localized: "Auf GitHub öffnen")) {
                    open(code.verificationURL)
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
            Button(String(localized: "Aktualisieren")) {
                Task { await store.refresh(forced: true) }
            }
            .accessibilityIdentifier("github-refresh")
            Button(String(localized: "Verbindung trennen"), role: .destructive) {
                confirmDisconnect = true
            }
        case .failed(let message):
            Text(message)
                .foregroundStyle(.secondary)
            if store.snapshot == nil {
                Button(String(localized: "Erneut versuchen")) {
                    Task { await store.connect() }
                }
                .accessibilityIdentifier("github-connect")
            } else {
                Button(String(localized: "Verbindung trennen"), role: .destructive) {
                    store.disconnect()
                }
                .accessibilityIdentifier("github-disconnect")
            }
        }
    }

    private func open(_ url: URL) {
        GitHubLink.open(url)
    }
}

enum GitHubLink {
    static func open(_ url: URL?) {
        guard let url, url.scheme?.lowercased() == "https" else { return }
        UIApplication.shared.open(url)
    }
}
