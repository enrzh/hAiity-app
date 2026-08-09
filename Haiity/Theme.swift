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

/// Die Farbrampe des Contribution-Graphen. Sechs Familien, jede mit fünf
/// Stufen für hell UND dunkel, gebaut nach denselben drei Regeln wie
/// GitHubs Original:
///
///  1. **Monoton in der wahrgenommenen Helligkeit.** Hell läuft l0…l4 von
///     hell nach dunkel, dunkel von dunkel nach hell. Zwischen zwei Stufen
///     liegen mindestens 1,15:1 Kontrast — darunter verschmelzen die Stufen
///     im Raster zu einer Fläche.
///  2. **l0 ist sichtbar, aber leise.** Die leere Zelle muss sich von der
///     Karte abheben (mind. 1,10:1), darf sie aber nicht überstimmen
///     (höchstens 1,85:1). Der Wert ist je Palette EIGEN gerechnet, nicht
///     kopiert: die dunkle Karte ist #1C1C1E, und ein Blau-l0 mit derselben
///     Helligkeit wie das Grün-l0 würde gegen sein eigenes l1 verschwinden.
///  3. **Der Farbton trägt bis in die leere Zelle.** l0 ist nicht neutral
///     grau, sondern minimal in Richtung der Palette gekippt — dadurch liest
///     sich das Raster als eine Familie und nicht als bunte Zellen auf grauem
///     Grund. Grau/Monochrom ist die Ausnahme und bleibt neutral.
///
/// Die Zahlen sind in `PaletteRampTests` festgenagelt; wer hier eine Stufe
/// ändert, bekommt sofort gesagt, ob die Rampe noch trägt.
enum GraphPalette: String, CaseIterable, Codable, Identifiable, Sendable {
    case green, blue, violet, amber, rose, gray

    static let `default` = GraphPalette.green

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .green: return String(localized: "Grün")
        case .blue: return String(localized: "Blau")
        case .violet: return String(localized: "Violett")
        case .amber: return String(localized: "Bernstein")
        case .rose: return String(localized: "Rosé")
        case .gray: return String(localized: "Monochrom")
        }
    }

    /// l0…l4 als sRGB-Hex. Roh (nicht als `Color`), damit Tests die
    /// Helligkeiten nachrechnen können, ohne UIColor auseinanderzunehmen.
    func ramp(dark: Bool) -> [UInt32] { dark ? darkRamp : lightRamp }

    private var lightRamp: [UInt32] {
        switch self {
        case .green:  return [0xEFF2F5, 0x9BE9A8, 0x40C463, 0x30A14E, 0x216E39]
        case .blue:   return [0xEDF1F7, 0xBBDDFF, 0x6CB6FF, 0x1F6FEB, 0x0A3069]
        case .violet: return [0xF1F0F7, 0xDCC6FF, 0xB87FFF, 0x8250DF, 0x4C2889]
        case .amber:  return [0xF6F2EC, 0xFFD79C, 0xFCA33C, 0xD1690C, 0x7A3C00]
        case .rose:   return [0xF7F0F2, 0xFFD6E0, 0xFB7699, 0xD1245C, 0x7D0D35]
        case .gray:   return [0xEEF0F2, 0xC9CED6, 0x99A1AD, 0x656C76, 0x32383F]
        }
    }

    private var darkRamp: [UInt32] {
        switch self {
        case .green:  return [0x262C36, 0x0E4429, 0x006D32, 0x26A641, 0x39D353]
        case .blue:   return [0x242B38, 0x0D419D, 0x1F6FEB, 0x58A6FF, 0xA5D6FF]
        case .violet: return [0x2A2739, 0x512A97, 0x7C3AED, 0xA371F7, 0xD2A8FF]
        case .amber:  return [0x312A1F, 0x613A00, 0x9E5F00, 0xD08A1E, 0xF0BE4B]
        case .rose:   return [0x33262C, 0x7A0F38, 0xBF2E63, 0xEF5F8B, 0xFFA8C5]
        case .gray:   return [0x272B31, 0x3D444D, 0x656C76, 0x9198A1, 0xC9D1D9]
        }
    }

    // MARK: – Akzent-Rollen (siehe Theme)

    /// Markenfarbe für FLÄCHEN ohne Text.
    var accentHex: UInt32 {
        switch self {
        case .green:  return 0x2EA043
        case .blue:   return 0x1F6FEB
        case .violet: return 0x8250DF
        case .amber:  return 0xD08A1E
        case .rose:   return 0xD1245C
        case .gray:   return 0x656C76
        }
    }

    /// Gefüllte Pillen MIT weißer Schrift — überall ≥ 4,5:1 gegen Weiß.
    var accentFillHex: (light: UInt32, dark: UInt32) {
        switch self {
        case .green:  return (0x1F883D, 0x238636)
        case .blue:   return (0x0969DA, 0x1F6FEB)
        case .violet: return (0x7C3AED, 0x8250DF)
        case .amber:  return (0xA85C00, 0xA96400)
        case .rose:   return (0xC21E56, 0xCF2E63)
        case .gray:   return (0x4B535D, 0x57606A)
        }
    }

    /// Akzent als SCHRIFT/Symbol — ≥ 4,5:1 gegen Weiß bzw. gegen #1C1C1E.
    var accentTextHex: (light: UInt32, dark: UInt32) {
        switch self {
        case .green:  return (0x1A7F37, 0x3FB950)
        case .blue:   return (0x0757BA, 0x58A6FF)
        case .violet: return (0x6B34D6, 0xB78CFF)
        case .amber:  return (0x8E4C00, 0xF0BE4B)
        case .rose:   return (0xB31E52, 0xFF8FB4)
        case .gray:   return (0x4B535D, 0xC9D1D9)
        }
    }
}

/// Auflösung der Palette für EIN Habit: die Habit-Einstellung schlägt die
/// globale, die globale schlägt den Standard (Grün). Eine Funktion, damit
/// App, Widget und Teilen-Karte garantiert dieselbe Regel benutzen.
extension GraphPalette {
    static func resolve(habit: Habit?, global: GraphPalette?) -> GraphPalette {
        habit?.palette ?? global ?? .default
    }
}

/// Farb-Quelle für App und Widget.
enum Theme {
    // MARK: – Contribution-Level

    /// Die Farbe einer Rasterzelle. `palette` kommt aus der Umgebung
    /// (`\.graphPalette`) bzw. beim Widget aus dem Timeline-Eintrag; die
    /// Habit-Übersteuerung wird VORHER über `GraphPalette.resolve` aufgelöst.
    static func level(_ n: Int, dark: Bool, palette: GraphPalette = .default) -> Color {
        color(palette.ramp(dark: dark)[max(0, min(4, n))])
    }

    /// Kartenfarbe (`secondarySystemGroupedBackground`) als Hex — die Fläche,
    /// gegen die l0 bestehen muss. Als Konstante, damit die Kontrast-Tests
    /// nicht von einer Trait-Collection abhängen.
    static func cardHex(dark: Bool) -> UInt32 { dark ? 0x1C1C1E : 0xFFFFFF }

    // MARK: – Akzent
    //
    // Drei Rollen, weil EINE Farbstufe nicht überall lesbar ist:
    //   accent      – Markenfarbe für FLÄCHEN ohne Text (Glas-Tint,
    //                 Monatsbalken, Chip-Hintergründe).
    //   accentFill  – gefüllte Pillen MIT weißer Schrift; dunkel genug für
    //                 ≥ 4,5:1 gegen Weiß.
    //   accentText  – Akzent als SCHRIFT/Symbol auf Systemhintergrund;
    //                 hell im Dark Mode, dunkel im Light Mode.

    static func accent(_ palette: GraphPalette = .default) -> Color {
        color(palette.accentHex)
    }

    static func accentFill(_ palette: GraphPalette = .default) -> Color {
        let hex = palette.accentFillHex
        return dynamic(light: hex.light, dark: hex.dark)
    }

    static func accentText(_ palette: GraphPalette = .default) -> Color {
        let hex = palette.accentTextHex
        return dynamic(light: hex.light, dark: hex.dark)
    }

    static func color(_ hex: UInt32) -> Color { Color(uiColor(hex)) }

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

private struct GraphPaletteKey: EnvironmentKey {
    static let defaultValue = GraphPalette.default
}

extension EnvironmentValues {
    /// Die GLOBALE Palette. Habit-eigene Farben werden am Ort des Rasters
    /// darübergelegt, nicht hier — sonst würde eine violette Karte auch die
    /// Knöpfe der App violett färben.
    var graphPalette: GraphPalette {
        get { self[GraphPaletteKey.self] }
        set { self[GraphPaletteKey.self] = newValue }
    }
}
