import Foundation

/// Die öffentliche Identität der App gegenüber GitHub.
///
/// `clientId` ist ein **öffentlicher** Bezeichner, kein Geheimnis: der Device
/// Flow ist genau dafür gemacht, dass eine Client-App ohne Client-Secret
/// auskommt (RFC 8628). Die ID darf im App-Binary stehen — sie identifiziert
/// nur, *welche* App fragt; autorisiert wird ausschließlich der Nutzer, im
/// Browser, mit seinem eigenen Code. Ein Angreifer mit dieser ID kann damit
/// nichts tun, was er nicht auch mit einer eigenen App-Registrierung könnte.
///
/// Neu erzeugen / ersetzen:
///  1. github.com → Settings → Developer Settings → **GitHub Apps** → *New GitHub App*
///     (oder OAuth Apps → *New OAuth App*, dann greift `scope=repo`).
///  2. „Enable Device Flow" ankreuzen — ohne das antwortet GitHub mit
///     `device_flow_disabled`.
///  3. Permissions (GitHub App): *Repository permissions* →
///     **Contents: Read and write** und **Administration: Read and write**
///     (Letzteres nur, damit hAiity das Repo `haiity-data` anlegen kann).
///  4. „Where can this GitHub App be installed" → *Any account*.
///  5. Die angezeigte **Client ID** (`Iv23li…` bzw. `Ov23li…`) hier eintragen.
///
/// Solange der Platzhalter steht, meldet `isConfigured` false und die UI
/// bietet nur den Token-Weg an — statt einen Device Flow zu starten, der
/// garantiert scheitert.
enum GitHubAppConfig {
    /// Platzhalter, damit ein unkonfigurierter Build ehrlich bleibt.
    static let placeholder = "REPLACE_ME_CLIENT_ID"

    /// PUBLIC identifier — siehe Doku oben. Kein Secret, kein Token.
    static let clientId = "REPLACE_ME_CLIENT_ID"

    /// Ist eine echte Client-ID hinterlegt?
    static var isConfigured: Bool {
        #if DEBUG
        // Nur Debug: erlaubt Screenshots/Previews der Geräte-UI ohne echte
        // ID. Es wird dabei kein Request abgesetzt — die UI wird lediglich
        // mit einem Beispiel-Code bestückt.
        if ProcessInfo.processInfo.arguments.contains("-demo-device-code") { return true }
        #endif
        let id = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        return !id.isEmpty && id != placeholder
    }
}
