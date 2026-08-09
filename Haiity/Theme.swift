import SwiftUI
import UIKit

/// Erscheinungsbild der App. `system` = dem Gerät folgen (kein Override).
enum AppearanceSetting: String, CaseIterable, Codable, Sendable {
    case system, light, dark

    static let `default` = AppearanceSetting.system

    /// Was `.preferredColorScheme` bekommt — nil heißt "nicht erzwingen".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var displayName: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Hell")
        case .dark: return String(localized: "Dunkel")
        }
    }
}

/// Farb-Quelle für App und Widget.
///
/// Alles hier nimmt eine `PaletteStyle` — die AUFGELÖSTE Farbtafel. Ob sie aus
/// einer der sechs eingebauten Familien kommt oder aus einer eigenen Farbe des
/// Nutzers gerechnet wurde, weiß ab hier niemand mehr; das entscheidet
/// `PaletteStyle.resolve` genau einmal.
enum Theme {
    // MARK: – Contribution-Level

    /// Die Farbe einer Rasterzelle. `palette` kommt aus der Umgebung
    /// (`\.palettes`) bzw. beim Widget aus dem Timeline-Eintrag; die
    /// Habit-Übersteuerung wird VORHER über `PaletteStyle.resolve` aufgelöst.
    static func level(_ n: Int, dark: Bool, palette: PaletteStyle = .default) -> Color {
        color(palette.ramp(dark: dark)[max(0, min(4, n))])
    }

    /// Kartenfarbe (`secondarySystemGroupedBackground`) als Hex — die Fläche,
    /// gegen die l0 bestehen muss. Als Konstante, damit die Kontrast-Tests
    /// nicht von einer Trait-Collection abhängen. EINE Quelle, die auch der
    /// Generator benutzt.
    static func cardHex(dark: Bool) -> UInt32 { PaletteGenerator.cardHex(dark: dark) }

    // MARK: – Akzent
    //
    // Drei Rollen, weil EINE Farbstufe nicht überall lesbar ist:
    //   accent      – Markenfarbe für FLÄCHEN ohne Text (Glas-Tint,
    //                 Monatsbalken, Chip-Hintergründe).
    //   accentFill  – gefüllte Pillen MIT weißer Schrift; dunkel genug für
    //                 ≥ 4,5:1 gegen Weiß.
    //   accentText  – Akzent als SCHRIFT/Symbol auf Systemhintergrund;
    //                 hell im Dark Mode, dunkel im Light Mode.

    static func accent(_ palette: PaletteStyle = .default) -> Color {
        color(palette.accentHex)
    }

    static func accentFill(_ palette: PaletteStyle = .default) -> Color {
        let hex = palette.accentFillHex
        return dynamic(light: hex.light, dark: hex.dark)
    }

    static func accentText(_ palette: PaletteStyle = .default) -> Color {
        let hex = palette.accentTextHex
        return dynamic(light: hex.light, dark: hex.dark)
    }

    // Bequemlichkeits-Überladungen für die eingebauten Familien: Aufrufer, die
    // eine feste Palette meinen (Vorschauen, Tests), müssen nicht erst
    // `.style` schreiben. Ohne Standardwert, damit ein Aufruf ohne Argument
    // eindeutig die `PaletteStyle`-Variante trifft.
    static func level(_ n: Int, dark: Bool, palette: GraphPalette) -> Color {
        level(n, dark: dark, palette: palette.style)
    }
    static func accent(_ palette: GraphPalette) -> Color { accent(palette.style) }
    static func accentFill(_ palette: GraphPalette) -> Color { accentFill(palette.style) }
    static func accentText(_ palette: GraphPalette) -> Color { accentText(palette.style) }

    static func color(_ hex: UInt32) -> Color { Color(uiColor(hex)) }

    /// sRGB-Hex aus einer gewählten `Color`. Der ColorPicker liefert je nach
    /// Gerät Display-P3 oder erweiterte Werte; hier wird EINMAL nach sRGB
    /// gerechnet und geklemmt, damit alles dahinter mit 0xRRGGBB arbeitet.
    static func hex(from color: Color) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let ui = UIColor(color)
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0x2EA043 }
        func channel(_ v: CGFloat) -> UInt32 { UInt32((min(1, max(0, v)) * 255).rounded()) }
        return (channel(r) << 16) | (channel(g) << 8) | channel(b)
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        let l = uiColor(light), d = uiColor(dark)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? d : l })
    }

    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }

    enum Haptics {
        static func check() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    /// EINE Maßskala für die Oberfläche. Alles ist ein Vielfaches von 4, das
    /// meiste von 8; wer hier etwas ändert, verschiebt es überall — genau
    /// dafür stehen die Werte hier und nicht verstreut in den Views.
    ///
    /// `control` ist die wichtigste Zahl: Umschalter-HÖHE, Durchmesser des
    /// zusammengezogenen Blobs und Durchmesser des Anlegen-Knopfes sind
    /// DASSELBE Maß. Geschwisterelemente derselben Ebene dürfen sich in der
    /// Größe nicht unterscheiden, sonst steht das eine optisch höher als das
    /// andere, obwohl beide auf derselben Grundlinie sitzen.
    enum Metrics {
        /// Kantenlänge der schwebenden Bedienelemente unten.
        static let control: CGFloat = 52
        /// Kleinste Trefferfläche (Apple: 44 pt) — auch dort, wo das
        /// Sichtbare kleiner ist.
        static let hit: CGFloat = 44
        /// Grundabstand.
        static let gap: CGFloat = 8
        /// Seitenrand von Liste und Chrom.
        static let gutter: CGFloat = 16
        /// Innenabstand der Rasterfläche.
        static let cardPadding: CGFloat = 12
        /// Eckradius der Rasterfläche.
        static let cardRadius: CGFloat = 16
        /// Kästchen JEDES Chrom-Symbols. Gleich groß, damit die Mittelpunkte
        /// auf einer Linie sitzen; die Punktgrößen darin sind optisch
        /// abgeglichen (siehe ContentView.glyph).
        static let glyph: CGFloat = 32
    }
}

// MARK: – Umgebung

private struct PaletteBookKey: EnvironmentKey {
    static let defaultValue = PaletteBook()
}

extension View {
    /// Farbe und Tint aus dem Store an DIESEN Teilbaum hängen.
    ///
    /// Gebraucht wird das für Blätter: `.sheet` ist eine eigene Präsentation
    /// und erbt die Umgebung des Bildschirms darunter NICHT — die Farbwahl im
    /// Bearbeiten-Blatt zeigte deshalb Grün, während die App in einer eigenen
    /// Farbe lief, und die eigenen Paletten fehlten dort ganz. Eine Zeile je
    /// Blatt, statt in jedem Blatt einzeln daran zu denken.
    func themed(_ store: HabitStore) -> some View {
        environment(\.palettes, store.palettes)
            .tint(Theme.accentText(store.paletteStyle))
    }
}

extension EnvironmentValues {
    /// Die GLOBALE Farbe PLUS die eigenen Paletten. Habit-eigene Farben werden
    /// am Ort des Rasters darübergelegt, nicht hier — sonst würde eine
    /// violette Karte auch die Knöpfe der App violett färben. Die eigenen
    /// Paletten reisen mit, weil eine Habit-Übersteuerung auf eine EIGENE
    /// Farbe zeigen kann und das Raster sie sonst nicht nachschlagen könnte.
    var palettes: PaletteBook {
        get { self[PaletteBookKey.self] }
        set { self[PaletteBookKey.self] = newValue }
    }
}
