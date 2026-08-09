import UIKit

/// Alternative App-Icons — ein Icon je Palette, damit der Homescreen
/// dasselbe zeigt wie das Raster in der App.
///
/// Die Icons kommen (wie ALLE Icons der Familie) aus einem Generator:
/// `aiity-web/scripts/make-icons.swift`, Varianten `haiity`, `haiity-blue`,
/// `haiity-violet`, `haiity-amber`, `haiity-rose`, `haiity-gray`. Sie liegen
/// als eigene .appiconset im Katalog; `ASSETCATALOG_COMPILER_ALTERNATE_
/// APPICON_NAMES` (project.yml) macht sie zu alternativen Icons — der
/// klassische Weg über lose PNGs im Bundle ist seit Xcode 13 nicht mehr
/// nötig und würde die Icons nur an actool vorbeischmuggeln.
///
/// `setAlternateIconName` zeigt einen System-Dialog ("Du hast das Symbol für
/// hAiity geändert"). Deshalb wird hier NUR gewechselt, wenn sich der Name
/// wirklich ändert — und nur, wenn der Nutzer die Kopplung anhat.
enum AppIcons {
    /// Katalogname je Palette; nil = Primär-Icon (Grün).
    static func name(for palette: GraphPalette) -> String? {
        switch palette {
        case .green:  return nil
        case .blue:   return "AppIcon-Blue"
        case .violet: return "AppIcon-Violet"
        case .amber:  return "AppIcon-Amber"
        case .rose:   return "AppIcon-Rose"
        case .gray:   return "AppIcon-Gray"
        }
    }

    /// Alle Katalognamen, die `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`
    /// kennen muss — Quelle für den Test, der project.yml gegen den Code hält.
    static var alternateNames: [String] {
        GraphPalette.allCases.compactMap { name(for: $0) }
    }

    @MainActor
    static func apply(_ palette: GraphPalette) async {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons else { return }
        let wanted = name(for: palette)
        guard app.alternateIconName != wanted else { return }
        // Fehler bewusst geschluckt: ein fehlgeschlagener Icon-Wechsel ist
        // kosmetisch und darf die Farbumstellung nicht zurückrollen.
        try? await app.setAlternateIconName(wanted)
    }
}
