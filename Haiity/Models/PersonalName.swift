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
/// dieselbe Suite. Er verlässt das Gerät nie; die Apple-Anmeldung wird
/// ausschließlich benutzt, um den Vornamen EINMAL zu erfahren.
enum PersonalName {
    static let aliasKey = "personalAlias"
    static let appleNameKey = "personalAppleName"

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
