import UIKit

/// Alternative App-Icons — ein Icon je eingebauter Palette, damit der
/// Homescreen dasselbe zeigt wie das Raster in der App.
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
///
/// **Eigene Farben und das Icon.** Ein Icon je Nutzerfarbe gibt es nicht: die
/// Bilder liegen vorgerendert im Asset-Katalog, ein zur Laufzeit gemaltes Icon
/// kann iOS nicht setzen. Von den zwei möglichen Antworten — Icon einfach
/// stehen lassen oder das NÄCHSTLIEGENDE eingebaute nehmen — ist die zweite
/// die ehrlichere: „stehen lassen" heißt in der Praxis, dass ein grünes Icon
/// über einer tiefroten App klebt, also genau das Gegenteil dessen, wofür die
/// Kopplung da ist. Gemessen wird der Abstand im OKLCH-FARBTON (derselbe Raum,
/// in dem die Rampe gerechnet wird); eine unbunte Farbe (Weiß, Schwarz, Grau)
/// hat keinen Farbton und bekommt deshalb „Monochrom".
enum AppIcons {
    /// Katalogname je eingebauter Palette; nil = Primär-Icon (Grün).
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

    /// Welche EINGEBAUTE Familie ein Verweis auf dem Homescreen vertritt.
    /// Eingebaute vertreten sich selbst; eine eigene Farbe die mit dem
    /// nächsten Farbton. Rein und ohne UIKit, damit es prüfbar ist.
    static func iconPalette(for ref: PaletteRef, customs: [CustomPalette]) -> GraphPalette {
        switch ref {
        case .builtin(let palette):
            return palette
        case .custom(let id):
            guard let base = customs.first(where: { $0.id == id })?.base else { return .default }
            return nearest(base: base)
        }
    }

    /// Nächstliegende eingebaute Familie zu einer freien Farbe.
    static func nearest(base: UInt32) -> GraphPalette {
        // Kein Farbton -> Monochrom. Ein Grau dem Grün zuzuordnen, nur weil
        // atan2(0, 0) zufällig 0 ergibt, wäre ein Rechenartefakt.
        guard let hue = PaletteGenerator.hueDegrees(base) else { return .gray }
        let candidates = GraphPalette.allCases.compactMap { palette -> (GraphPalette, Double)? in
            guard let h = PaletteGenerator.hueDegrees(palette.accentHex) else { return nil }
            let raw = abs(h - hue)
            return (palette, min(raw, 360 - raw))   // Farbton ist ein Kreis
        }
        return candidates.min { $0.1 < $1.1 }?.0 ?? .default
    }

    @MainActor
    static func apply(_ book: PaletteBook) async {
        await apply(iconPalette(for: book.global, customs: book.customs))
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
