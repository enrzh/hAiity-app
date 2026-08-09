import SwiftUI

/// GitHub-Verbindung: Token rein, Repo wird angelegt, fertig.
/// Ehrlich beschriftet: kein hAiity-Server, Token bleibt im Schlüsselbund.
struct SyncSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: HabitStore
    let sync: GitHubSync
    @Binding var connectedLogin: String?

    @State private var token = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let login = connectedLogin {
                    Section {
                        LabeledContent(String(localized: "Verbunden als"), value: login)
                        LabeledContent(String(localized: "Repo"), value: "\(login)/\(GitHubSync.repoName)")
                        Button(String(localized: "Trennen"), role: .destructive) {
                            Task {
                                await sync.disconnect()
                                connectedLogin = nil
                            }
                        }
                    } footer: {
                        Text(String(localized: "Jeder Check-in ist ein Commit in deinem Repo — er füllt deinen echten Contribution-Graph."))
                    }
                } else {
                    Section {
                        Text(String(localized: "Deine Daten landen in einem privaten Repo „haiity-data“ in DEINEM GitHub-Account. hAiity hat keinen Server; das Token bleibt im Schlüsselbund dieses Geräts."))
                            .font(.footnote)
                    }
                    Section {
                        Link(String(localized: "Fine-grained Token erstellen"),
                             destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                        Text(String(localized: "Berechtigungen: Contents (Read/Write) und einmalig Administration (Read/Write) zum Anlegen des Repos — oder das Repo „haiity-data“ vorher selbst anlegen und nur Contents freigeben."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SecureField(String(localized: "github_pat_…"), text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("sync-token")
                        if let error {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                        Button {
                            connect()
                        } label: {
                            if busy { ProgressView() } else { Text(String(localized: "Verbinden")) }
                        }
                        .disabled(token.isEmpty || busy)
                        .accessibilityIdentifier("sync-connect")
                    }
                }
            }
            .navigationTitle(String(localized: "GitHub-Sync"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Fertig")) { dismiss() }
                }
            }
        }
    }

    private func connect() {
        busy = true
        error = nil
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let login = try await sync.connect(token: t)
                if let remote = try await sync.pull() {
                    await MainActor.run { store.merge(remote: remote) }
                }
                await MainActor.run {
                    connectedLogin = login
                    busy = false
                    token = ""
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    busy = false
                }
            }
        }
    }
}
