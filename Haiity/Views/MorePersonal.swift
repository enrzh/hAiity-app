import AuthenticationServices
import SwiftUI

extension MoreView {
    // MARK: – Anrede
    //
    // Der Name macht Mitteilungen persönlich („Stark, Mo!") — mehr nicht.
    // Zwei Quellen: der Alias (geht IMMER, kein Konto nötig) und optional
    // der Vorname aus der Apple-Anmeldung; der Alias gewinnt. Apple liefert
    // den Namen nur bei der ERSTEN Anmeldung — schlägt das fehl oder kommt
    // leer zurück, sagt die Zeile das ehrlich, statt still nichts zu tun.

    var personalDisplayName: String? {
        PersonalName.resolve(alias: aliasDraft, appleName: storedAppleName)
    }

    var personalHeader: some View {
        VStack(alignment: .leading, spacing: currentAppearance.designStyle.rowGap * 2 + 4) {
            HStack {
                Group {
                    if let name = personalDisplayName, let initial = name.first {
                        Text(String(initial).uppercased())
                    } else {
                        Image(systemName: "person.fill")
                    }
                }
                .font(.title.weight(.semibold))
                .foregroundStyle(accentColor)
                .frame(width: 64, height: 64)
                .background(accentColor.opacity(0.1), in: Circle())
                .accessibilityHidden(true)
                Spacer()
            }
            Text(personalDisplayName.map { String(format: String(localized: "Hallo, %@"), $0) }
                 ?? String(localized: "Dein Alltag, persönlich."))
                .font(currentAppearance.designStyle.sectionTitleFont)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(String(localized: "Ein Name, der deine Motivationen persönlicher macht."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(currentAppearance.designStyle.cardPadding + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .morePanel()
        .accessibilityIdentifier("account-header")
    }

    var personalSection: some View {
        VStack(spacing: store.appearancePreferences.designStyle.sectionGap) {
            AppSettingsGroup(title: String(localized: "Anrede"),
                             footer: String(localized: "Dein Alias bleibt auf diesem Gerät. Du brauchst dafür kein Konto.")) {
                HStack(spacing: Theme.Metrics.gap + 4) {
                    personalLeadingIcon("person.crop.circle")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Alias"))
                            .font(currentAppearance.designStyle.rowTitleFont)
                        TextField(String(localized: "Alias"),
                                  text: aliasBinding,
                                  prompt: Text(String(localized: "Wie dürfen wir dich nennen?")))
                            .textInputAutocapitalization(.words)
                            .textContentType(.nickname)
                            .submitLabel(.done)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("personal-alias")
                            .frame(minHeight: Theme.Metrics.hit)
                    }
                }
                .padding(.vertical, Theme.Metrics.gap / 2)
                Divider().padding(.leading, Theme.Metrics.rowTitleInset)
                personalMotivationPreview
            }

            DisclosureGroup {
            AppSettingsGroup(title: String(localized: "Apple-ID"),
                             footer: String(localized: "Die Apple-Anmeldung ist optional. Dein iCloud-Abgleich läuft unabhängig davon.")) {
            VStack(alignment: .leading, spacing: 0) {
                if storedAppleUserID != nil {
                    let displayName = PersonalName.resolve(alias: nil,
                                                            appleName: storedAppleName)
                        ?? String(localized: "Apple-ID")
                    VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
                        HStack(spacing: Theme.Metrics.gap + 4) {
                            personalLeadingIcon("person.crop.circle.badge.checkmark")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(format: String(localized: "Angemeldet als %@"), displayName))
                                    .font(currentAppearance.designStyle.rowTitleFont)
                                if let storedAppleEmail {
                                    Text(storedAppleEmail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button(String(localized: "Abmelden"), role: .destructive) {
                            signOutFromApple()
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .frame(minHeight: Theme.Metrics.hit)
                        .padding(.leading, Theme.Metrics.rowTitleInset)
                        .accessibilityIdentifier("apple-signout")
                    }
                    .frame(minHeight: Theme.Metrics.hit)
                    if appleSignInCameBackEmpty && PersonalName.effective == nil {
                        Text(String(localized: "Apple hat keinen Namen geliefert. Nutze einen Alias."))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } else {
                    appleSignInButton
                        .padding(.vertical, Theme.Metrics.gap)
                    if appleSignInCameBackEmpty {
                        Text(String(localized: "Apple hat keinen Namen geliefert. Nutze einen Alias."))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.vertical, Theme.Metrics.gap / 2)
            }
            } label: {
                AppSettingsRow(title: String(localized: "Apple-Verbindung (optional)"),
                               detail: storedAppleUserID == nil
                                ? String(localized: "Nicht angemeldet")
                                : String(localized: "Mit Apple verbunden"),
                               symbol: "person.crop.circle.badge.checkmark") {
                    EmptyView()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("personal-apple-connection")
        }
        .onAppear { refreshPersonalIdentity() }
    }

    private var personalMotivationPreview: some View {
        let message = Celebration.message(name: personalDisplayName, today: DayKey.today())
        return HStack(alignment: .top, spacing: Theme.Metrics.gap + 4) {
            personalLeadingIcon("quote.bubble")
            VStack(alignment: .leading, spacing: currentAppearance.designStyle.rowGap) {
                Text(String(localized: "Vorschau"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(message.title)
                    .font(currentAppearance.designStyle.rowTitleFont)
                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, currentAppearance.designStyle.cardPadding)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("account-motivation-preview")
    }

    func refreshPersonalIdentity() {
        aliasDraft = PersonalName.alias ?? ""
        storedAppleName = PersonalName.appleName
        storedAppleUserID = PersonalName.appleUserID
        storedAppleEmail = PersonalName.appleEmail
    }

    private var appleSignInButton: some View {
        appleSignInControl
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Metrics.hit)
            .accessibilityIdentifier("apple-signin")
    }

    var appleSignInControl: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            handleAppleSignIn(result)
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.control, style: .continuous))
    }

    private var aliasBinding: Binding<String> {
        Binding(get: { aliasDraft },
                set: { value in
                    aliasDraft = value
                    PersonalName.alias = value
                })
    }

    func signOutFromApple() {
        PersonalName.appleName = nil
        PersonalName.appleUserID = nil
        PersonalName.appleEmail = nil
        Pro.accountDidChange()
        storedAppleName = nil
        storedAppleUserID = nil
        storedAppleEmail = nil
        appleSignInCameBackEmpty = false
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let auth) = result,
              let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
            // Abbruch/Fehler: kein Banner, keine Strafe — der Alias bleibt
            // der immer offene Weg.
            return
        }
        let formatter = PersonNameComponentsFormatter()
        let credentialName = credential.fullName?.givenName
            ?? credential.fullName.map { formatter.string(from: $0) }
        // Die undurchsichtige Kennung IMMER mitnehmen — auch wenn Apple
        // keinen Vornamen liefert (das tut es nur bei der allerersten
        // Anmeldung). Sie ist der einzige Weg, dieses Gerät später als das
        // des Besitzers zu erkennen (siehe `DeveloperAccess.isOwnerDevice`),
        // und sie hängt nicht daran, ob ein Name dabei war.
        let existingUserID = PersonalName.appleUserID
        let resolvedName = AppleSignInIdentity.resolvedName(
            credentialName: credentialName,
            existingName: PersonalName.appleName,
            existingUserID: existingUserID,
            userID: credential.user)
        let resolvedEmail = AppleSignInIdentity.resolvedEmail(
            credentialEmail: credential.email,
            identityToken: credential.identityToken,
            existingEmail: PersonalName.appleEmail,
            existingUserID: existingUserID,
            userID: credential.user,
            audience: Bundle.main.bundleIdentifier ?? "com.aiity.haiity")
        PersonalName.appleUserID = credential.user
        PersonalName.appleEmail = resolvedEmail
        if existingUserID != credential.user {
            Pro.accountDidChange()
        }
        storedAppleUserID = PersonalName.appleUserID
        storedAppleEmail = PersonalName.appleEmail
        let aliasEmail = resolvedEmail ?? (DeveloperAccess.isOwnerDevice(
            storedAppleUserID: credential.user,
            storedAppleEmail: nil) ? DeveloperAccess.ownerAppleEmail : nil)
        let suggestedAlias = AppleSignInIdentity.suggestedAlias(
            resolvedName: resolvedName,
            email: aliasEmail)
        PersonalName.appleName = resolvedName
        storedAppleName = PersonalName.appleName
        if PersonalName.alias == nil, let suggestedAlias {
            PersonalName.alias = suggestedAlias
            aliasDraft = suggestedAlias
        }
        appleSignInCameBackEmpty = PersonalName.effective == nil
        // Personalization does not change the App Store purchase account.
        // Only StoreKit transactions or an explicit restore may revoke access.
        Task { await Pro.refresh() }
        Theme.Haptics.success()
    }

    private func personalLeadingIcon(_ symbol: String) -> some View {
        AppIconBadge(symbol: symbol)
    }
}
