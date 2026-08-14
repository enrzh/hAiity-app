import Foundation

/// Der Name für persönliche Mitteilungen — und NUR dafür.
///
/// Zwei Quellen: ein frei eingetragener Alias (geht immer, kein Konto
/// nötig) und der Vorname aus einer optionalen Apple-Anmeldung. Der Alias
/// gewinnt — wer „Mo" heißen will, heißt „Mo", egal was die Apple-ID sagt.
///
/// Der Name wohnt in den App-Group-Defaults, nicht in data.json: er ist
/// Geräte-Kosmetik, kein Habit-Datum — und der Widget-Prozess (Check-in
/// über den Widget-Knopf kann den perfekten Tag auslösen) liest ihn über
/// dieselbe Suite. Er verlässt das Gerät nie. Die Apple-Anmeldung liefert
/// außerdem die verifizierte Adresse, mit der das Besitzerkonto erkannt wird.
enum PersonalName {
    static let aliasKey = "personalAlias"
    static let appleNameKey = "personalAppleName"
    static let appleUserIDKey = "personalAppleUserID"
    static let appleEmailKey = "personalAppleEmail"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard
    }

    static var alias: String? {
        get { defaults.string(forKey: aliasKey) }
        set { store(newValue, forKey: aliasKey) }
    }

    static var appleName: String? {
        get { defaults.string(forKey: appleNameKey) }
        set { store(newValue, forKey: appleNameKey) }
    }

    /// Die undurchsichtige Kennung derselben Apple-Anmeldung
    /// (`ASAuthorizationAppleIDCredential.user`).
    ///
    /// **Warum sie neben dem Vornamen wohnt.** Sie kommt aus DEMSELBEN
    /// Anmeldevorgang und geht mit ihm — wer den Apple-Namen entfernt, meldet
    /// sich ab, und dann darf auch die Kennung nicht zurückbleiben.
    ///
    /// **Warum sie kein Name ist.** Apple vergibt sie stabil je
    /// (Entwicklerteam, Apple-ID) und sonst nirgends: eine Zeichenfolge wie
    /// `001234.abcd…`, aus der niemand einen Menschen ablesen kann. Sie
    /// beantwortet genau EINE Frage — ist das das Gerät des Besitzers
    /// (`DeveloperAccess.isOwnerDevice`)? — und verlässt das Gerät nie.
    ///
    /// **Warum trotzdem hier und nicht im Schlüsselbund.** Sie schützt keinen
    /// Zugang zu fremden Daten; sie entscheidet nur, ob eine Seite mit
    /// technischen Zahlen dieses Geräts erreichbar ist. Für diese Frage ist
    /// die App-Group-Ablage der ehrliche Ort: sie geht mit der App wieder weg.
    static var appleUserID: String? {
        get { defaults.string(forKey: appleUserIDKey) }
        set { store(newValue, forKey: appleUserIDKey) }
    }

    /// The verified address returned by Sign in with Apple. It is kept only
    /// to recognize the built-in owner account on this device.
    static var appleEmail: String? {
        get { defaults.string(forKey: appleEmailKey) }
        set { store(newValue?.lowercased(), forKey: appleEmailKey) }
    }

    /// Was in der Mitteilung steht: Alias vor Apple-Namen, leer = nichts.
    static var effective: String? { resolve(alias: alias, appleName: appleName) }

    /// Rein und prüfbar: Leerraum zählt nicht als Name.
    static func resolve(alias: String?, appleName: String?) -> String? {
        let trimmedAlias = alias?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedAlias, !trimmedAlias.isEmpty { return trimmedAlias }
        let trimmedApple = appleName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedApple, !trimmedApple.isEmpty { return trimmedApple }
        return nil
    }

    private static func store(_ value: String?, forKey key: String) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            defaults.set(trimmed, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
