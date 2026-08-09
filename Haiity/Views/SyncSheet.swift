import SwiftUI
import UIKit

/// GitHub-Verbindung. Standardweg ist der **Device Flow**: auf „Verbinden"
/// tippen, den angezeigten Code im Browser bestätigen — fertig. Kein Token
/// erzeugen, keine Berechtigungen zusammenklicken, nichts kopieren.
/// Der Token-Weg bleibt unter „Erweitert" erhalten, für alle, die ein fein
/// granuliertes Token lieber selbst auf genau ein Repo zuschneiden.
/// Ehrlich beschriftet: kein hAiity-Server, Token bleibt im Schlüsselbund.
struct SyncSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.palettes) private var palettes
    let store: HabitStore
    let sync: GitHubSync
    @Binding var connectedLogin: String?

    // Token-Weg. Ohne Client-ID ist er der einzige Weg — dann gleich offen.
    @State private var token = ""
    @State private var busy = false
    @State private var showAdvanced = !GitHubAppConfig.isConfigured
    @State private var tokenError: String?
    // Device Flow
    @State private var deviceCode: DeviceCode?
    @State private var deviceBusy = false
    @State private var deviceTask: Task<Void, Never>?
    @State private var copied = false
    @State private var deviceError: String?

    var body: some View {
        NavigationStack {
            Form {
                if let login = connectedLogin {
                    connectedSection(login)
                } else {
                    introSection
                    if GitHubAppConfig.isConfigured {
                        deviceSection
                    } else {
                        unconfiguredSection
                    }
                    advancedSection
                }
            }
            .navigationTitle(String(localized: "GitHub-Sync"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Fertig")) { dismiss() }
                }
            }
            .task {
                #if DEBUG
                seedDemoCodeIfRequested()
                #endif
            }
            .onDisappear { deviceTask?.cancel() }
        }
    }

    // MARK: – Verbunden

    @ViewBuilder
    private func connectedSection(_ login: String) -> some View {
        Section {
            LabeledContent(String(localized: "Verbunden als"), value: login)
            LabeledContent(String(localized: "Repo"), value: "\(login)/\(GitHubSync.repoName)")
            Button(String(localized: "Trennen"), role: .destructive) {
                deviceTask?.cancel()
                Task {
                    await sync.disconnect()
                    connectedLogin = nil
                    deviceCode = nil
                    deviceError = nil
                    tokenError = nil
                }
            }
            .accessibilityIdentifier("sync-disconnect")
        } footer: {
            Text(String(localized: "Jeder Check-in ist ein Commit in deinem Repo — er füllt deinen echten Contribution-Graph."))
        }
    }

    // MARK: – Nicht verbunden

    private var introSection: some View {
        Section {
            Text(String(localized: "Deine Daten landen in einem privaten Repo „haiity-data“ in DEINEM GitHub-Account. hAiity hat keinen Server; der Zugang bleibt im Schlüsselbund dieses Geräts."))
                .font(.footnote)
        }
    }

    /// Der Standardweg: ein Knopf, ein Code, ein Browser-Tap.
    @ViewBuilder
    private var deviceSection: some View {
        Section {
            if let code = deviceCode {
                codeDisplay(code)
                Button {
                    if let url = code.verificationURL { openURL(url) }
                } label: {
                    Label(String(localized: "Im Browser öffnen"), systemImage: "safari")
                        .font(.body.weight(.semibold))
                }
                .accessibilityIdentifier("sync-device-open")
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "Warte auf Bestätigung…"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("sync-device-waiting")
                Button(String(localized: "Abbrechen"), role: .cancel) { cancelDevice() }
                    .accessibilityIdentifier("sync-device-cancel")
            } else {
                Button {
                    startDevice()
                } label: {
                    HStack {
                        if deviceBusy {
                            ProgressView()
                        } else {
                            Text(String(localized: "Verbinden"))
                                .font(.body.weight(.semibold))
                        }
                        Spacer()
                    }
                }
                .disabled(deviceBusy)
                .accessibilityIdentifier("sync-device-start")
            }
            if let deviceError {
                Text(deviceError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("sync-device-error")
            }
        } header: {
            Text(String(localized: "Mit GitHub verbinden"))
        } footer: {
            Text(deviceCode == nil
                 ? String(localized: "hAiity zeigt dir einen kurzen Code. Den bestätigst du einmal im Browser — kein Token, keine Berechtigungen zusammenklicken.")
                 : String(localized: "Code im Browser eingeben und hAiity freigeben. Dieses Fenster kann offen bleiben."))
        }
    }

    private func codeDisplay(_ code: DeviceCode) -> some View {
        Button {
            UIPasteboard.general.string = code.userCode
            copied = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(code.userCode)
                    .font(.system(size: 34, weight: .semibold, design: .monospaced))
                    .kerning(3)
                    .foregroundStyle(Theme.accentText(palettes.style))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .textSelection(.enabled)
                Label(copied ? String(localized: "Kopiert") : String(localized: "Zum Kopieren tippen"),
                      systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sync-device-code")
        .accessibilityLabel(String(localized: "Code \(code.userCode), zum Kopieren tippen"))
    }

    /// Platzhalter-Client-ID: gar nicht erst einen Ablauf starten, der
    /// garantiert scheitert — ehrlich sagen, dass nur der Token-Weg geht.
    private var unconfiguredSection: some View {
        Section {
            Label(String(localized: "Die Anmeldung über GitHub ist in dieser Version noch nicht eingerichtet. Nutze so lange „Erweitert: Token manuell eingeben“."),
                  systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("sync-device-unavailable")
        }
    }

    /// Der alte Weg, bewusst eingeklappt: unverändert, für alle, die ein
    /// fein granuliertes Token auf genau ein Repo zuschneiden wollen.
    private var advancedSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showAdvanced) {
                Link(String(localized: "Fine-grained Token erstellen"),
                     destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                Text(String(localized: "Berechtigungen: Contents (Read/Write) und einmalig Administration (Read/Write) zum Anlegen des Repos — oder das Repo „haiity-data“ vorher selbst anlegen und nur Contents freigeben."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField(String(localized: "github_pat_…"), text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("sync-token")
                if let tokenError {
                    Text(tokenError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("sync-error")
                }
                Button {
                    connectWithToken()
                } label: {
                    if busy { ProgressView() } else { Text(String(localized: "Verbinden")) }
                }
                .disabled(token.isEmpty || busy)
                .accessibilityIdentifier("sync-connect")
            } label: {
                Text(String(localized: "Erweitert: Token manuell eingeben"))
                    .font(.callout)
            }
            .accessibilityIdentifier("sync-advanced")
        }
    }

    // MARK: – Device Flow

    private func startDevice() {
        deviceError = nil
        copied = false
        deviceBusy = true
        let flow = GitHubDeviceFlow(sync: sync)
        deviceTask?.cancel()
        deviceTask = Task {
            do {
                let login = try await flow.authorize { code in
                    Task { @MainActor in
                        deviceCode = code
                        deviceBusy = false
                    }
                }
                await finish(login: login)
            } catch is CancellationError {
                await MainActor.run { resetDevice() }
            } catch {
                await MainActor.run {
                    deviceError = error.localizedDescription
                    resetDevice()
                }
            }
        }
    }

    private func cancelDevice() {
        deviceTask?.cancel()
        deviceTask = nil
        resetDevice()
        deviceError = nil
    }

    private func resetDevice() {
        deviceCode = nil
        deviceBusy = false
        copied = false
    }

    // MARK: – Token-Weg (unverändert)

    private func connectWithToken() {
        busy = true
        tokenError = nil
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let login = try await sync.connect(token: t)
                await finish(login: login)
                await MainActor.run {
                    busy = false
                    token = ""
                }
            } catch {
                await MainActor.run {
                    tokenError = error.localizedDescription
                    busy = false
                }
            }
        }
    }

    /// Nach erfolgreicher Verbindung: Remote-Stand holen und zusammenführen.
    private func finish(login: String) async {
        if let remote = try? await sync.pull() {
            await MainActor.run { store.merge(remote: remote) }
        }
        await MainActor.run {
            connectedLogin = login
            deviceCode = nil
            deviceBusy = false
            deviceError = nil
            tokenError = nil
        }
    }

    #if DEBUG
    /// Nur Debug: `simctl launch … -demo-device-code` zeigt die Code-Ansicht
    /// mit einem Beispielcode — für Screenshots ohne echte Client-ID und
    /// ohne einen einzigen Request.
    private func seedDemoCodeIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-demo-device-code"),
              connectedLogin == nil else { return }
        deviceCode = DeviceCode(deviceCode: "demo-device-code",
                                userCode: "WDJB-MJHT",
                                verificationURI: "https://github.com/login/device",
                                expiresIn: 900,
                                interval: 5)
    }
    #endif
}
