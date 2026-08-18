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

    /// Ein frei wählbarer Icon-Farbton: alle 30° einer, damit jede im
    /// Farbrad gewählte Farbe höchstens ~15° neben einem echten Icon liegt.
    /// `base` ist die Farbe, aus der der Generator die Rampe des Icons
    /// gerechnet hat — die Miniatur im Auswahlraster rechnet mit DERSELBEN
    /// Basis, deshalb können Vorschau und Homescreen nicht auseinanderlaufen.
    struct IconHue: Identifiable, Equatable, Sendable {
        let degrees: Int
        let base: UInt32
        var name: String { String(format: "AppIcon-H%03d", degrees) }
        var id: Int { degrees }
        var style: PaletteStyle { PaletteGenerator.style(base: base) }
    }

    /// Die zwölf Farbton-Icons (Basen: OKLCH-nächste sRGB-Farbe zur
    /// mittleren Helligkeit/Chromatik der eingebauten Akzente — dieselben
    /// Werte stehen als Rampen in aiity-web/scripts/make-icons.swift).
    static let hues: [IconHue] = [
        IconHue(degrees: 0,   base: 0xD2427B),
        IconHue(degrees: 30,  base: 0xD84836),
        IconHue(degrees: 60,  base: 0xC06900),
        IconHue(degrees: 90,  base: 0x9F7E00),
        IconHue(degrees: 120, base: 0x789000),
        IconHue(degrees: 150, base: 0x009C42),
        IconHue(degrees: 180, base: 0x009984),
        IconHue(degrees: 210, base: 0x0096A8),
        IconHue(degrees: 240, base: 0x008ACF),
        IconHue(degrees: 270, base: 0x5775ED),
        IconHue(degrees: 300, base: 0x9360DB),
        IconHue(degrees: 330, base: 0xBA4EB4),
    ]

    /// Alle Katalognamen, die `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`
    /// kennen muss — Quelle für den Test, der project.yml gegen den Code hält.
    static var alternateNames: [String] {
        GraphPalette.allCases.compactMap { name(for: $0) } + hues.map(\.name)
    }

    static func validManualName(_ name: String?) -> String? {
        guard let name, alternateNames.contains(name) else { return nil }
        return name
    }

    /// Freie Farbe → Katalogname des nächstliegenden eingebauten Icons
    /// (nil = Primär-Grün). Unbunt bekommt Monochrom; sonst entscheidet der
    /// kürzeste Weg auf dem Farbtonkreis über ALLE 18 Anker — die fünf
    /// Palettenakzente und die zwölf Farbton-Icons.
    static func iconName(forBase base: UInt32) -> String? {
        guard let hue = PaletteGenerator.hueDegrees(base) else { return name(for: .gray) }
        func dist(_ h: Double) -> Double { let raw = abs(h - hue); return min(raw, 360 - raw) }
        var candidates: [(name: String?, dist: Double)] = GraphPalette.allCases.compactMap {
            guard let h = PaletteGenerator.hueDegrees($0.accentHex) else { return nil }
            return (name(for: $0), dist(h))
        }
        candidates += hues.map { ($0.name, dist(Double($0.degrees))) }
        return candidates.min { $0.dist < $1.dist }?.name ?? nil
    }

    /// Die Farbtafel, mit der die Miniatur eines Icons zu malen ist.
    static func style(forIconName name: String?) -> PaletteStyle {
        if let palette = GraphPalette.allCases.first(where: { self.name(for: $0) == name }) {
            return palette.style
        }
        return hues.first { $0.name == name }?.style ?? GraphPalette.green.style
    }

    /// Welches Icon die Kopplung „Icon folgt der Graph-Farbe" setzt:
    /// eingebaute Paletten ihr eigenes, eine eigene Farbe das nächste der 18.
    static func iconName(for ref: PaletteRef, customs: [CustomPalette]) -> String? {
        switch ref {
        case .builtin(let palette): return name(for: palette)
        case .custom(let id):
            guard let base = customs.first(where: { $0.id == id })?.base else { return nil }
            return iconName(forBase: base)
        }
    }

    @MainActor
    static func apply(_ book: PaletteBook) async {
        // Fehler bewusst geschluckt: ein fehlgeschlagener Icon-Wechsel ist
        // kosmetisch und darf die Farbumstellung nicht zurückrollen.
        _ = await set(iconName(for: book.global, customs: book.customs))
    }

    /// Wie `apply`, aber mit Antwort — das Auswahlraster in „Mehr" sagt dem
    /// Nutzer, wenn der Wechsel nicht ging, statt still nichts zu tun (genau
    /// dieses Schweigen las sich auf dem Gerät als „ist deaktiviert").
    @MainActor
    @discardableResult
    static func set(_ wanted: String?) async -> Bool {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons else { return false }
        guard app.alternateIconName != wanted else { return true }
        do { try await app.setAlternateIconName(wanted); return true }
        catch { return false }
    }
}
