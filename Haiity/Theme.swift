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

enum AppearanceMaterial: String, CaseIterable, Codable, Sendable {
    case solid
    case milky
    case liquid

    var displayName: String {
        switch self {
        case .solid: return String(localized: "Solid")
        case .milky: return String(localized: "Milchglas")
        case .liquid: return String(localized: "Liquid Glass")
        }
    }
}

enum AppearanceBackgroundMode: String, CaseIterable, Codable, Sendable {
    case color
    case gradient
    case image

    var displayName: String {
        switch self {
        case .color: return String(localized: "Farbe")
        case .gradient: return String(localized: "Verlauf")
        case .image: return String(localized: "Bild")
        }
    }
}

/// Persisted appearance choices shared by the app and iCloud payload. Image
/// bytes are intentionally bounded because they travel with the full habit
/// asset even though CloudKit stores that asset outside the record fields.
struct AppearancePreferences: Codable, Equatable, Sendable {
    static let maxImageBytes = 600 * 1024
    static let `default` = AppearancePreferences(material: .solid)

    var material: AppearanceMaterial
    var backgroundMode: AppearanceBackgroundMode
    var backgroundColorHex: UInt32?
    var gradientStartHex: UInt32?
    var gradientEndHex: UInt32?
    var backgroundImageData: Data?

    init(material: AppearanceMaterial = .solid,
         backgroundImageData: Data? = nil,
         backgroundMode: AppearanceBackgroundMode? = nil,
         backgroundColorHex: UInt32? = nil,
         gradientStartHex: UInt32? = nil,
         gradientEndHex: UInt32? = nil) {
        self.material = material
        self.backgroundMode = backgroundMode
            ?? (backgroundImageData == nil ? .color : .image)
        self.backgroundColorHex = backgroundColorHex
        self.gradientStartHex = gradientStartHex
        self.gradientEndHex = gradientEndHex
        self.backgroundImageData = backgroundImageData.flatMap {
            $0.count <= Self.maxImageBytes ? $0 : nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case material, backgroundMode, backgroundColorHex, gradientStartHex,
             gradientEndHex, backgroundImageData
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let image = try c.decodeIfPresent(Data.self, forKey: .backgroundImageData)
        self.init(
            material: try c.decodeIfPresent(AppearanceMaterial.self, forKey: .material) ?? .solid,
            backgroundImageData: image,
            backgroundMode: try c.decodeIfPresent(AppearanceBackgroundMode.self,
                                                    forKey: .backgroundMode)
                ?? (image == nil ? .color : .image),
            backgroundColorHex: try c.decodeIfPresent(UInt32.self, forKey: .backgroundColorHex),
            gradientStartHex: try c.decodeIfPresent(UInt32.self, forKey: .gradientStartHex),
            gradientEndHex: try c.decodeIfPresent(UInt32.self, forKey: .gradientEndHex))
    }

    var backgroundImage: UIImage? {
        guard let backgroundImageData else { return nil }
        return UIImage(data: backgroundImageData)
    }
}

enum AppearanceImage {
    /// Downsample and compress a picked image before it enters `HabitData`.
    /// The final size check is repeated by `AppearancePreferences`.
    static func normalizedData(_ data: Data) -> Data? {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { return nil }
        let maxDimension: CGFloat = 1600
        let scale = min(1, maxDimension / max(CGFloat(cgImage.width), CGFloat(cgImage.height)))
        let size = CGSize(width: CGFloat(cgImage.width) * scale,
                          height: CGFloat(cgImage.height) * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let compressed = renderer.jpegData(withCompressionQuality: 0.78) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return compressed.count <= AppearancePreferences.maxImageBytes ? compressed : nil
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
    ///
    /// `Habit.Answer.declinedLevel` (−1) ist die eine Stufe NEBEN der Rampe:
    /// ein mit Nein beantworteter Tag. Sie steht hier und nicht in jeder
    /// Ansicht einzeln, weil an dieser Funktion ALLES hängt, was Zellen malt
    /// — Liste, Vorschau, Teilen-Karte und jedes Widget erben die Farbe
    /// damit ohne eigenes Zutun. Jeder ANDERE Ausreißer wird weiter geklemmt
    /// (−3 ist keine Verneinung, sondern ein Fehler, und bleibt l0).
    static func level(_ n: Int, dark: Bool, palette: PaletteStyle = .default) -> Color {
        guard n != Habit.Answer.declinedLevel else {
            return color(palette.negative(dark: dark))
        }
        return color(palette.ramp(dark: dark)[max(0, min(4, n))])
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
        /// AUSWAHL, nicht Bestätigung — für Gesten, die nur etwas markieren
        /// und nichts schreiben (Tipp auf eine Rasterzelle). Ein
        /// Bestätigungs-Stups an einer Stelle, die gar nichts festmacht,
        /// behauptet einen Vorgang, den es nicht gab.
        static func select() { UISelectionFeedbackGenerator().selectionChanged() }
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
            .environment(\.appearancePreferences, store.appearancePreferences)
            .tint(Theme.accentText(store.paletteStyle))
    }

    func appSurface(cornerRadius: CGFloat = Theme.Metrics.cardRadius) -> some View {
        modifier(AppSurfaceModifier(cornerRadius: cornerRadius))
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

    var appearancePreferences: AppearancePreferences {
        get { self[AppearancePreferencesKey.self] }
        set { self[AppearancePreferencesKey.self] = newValue }
    }
}

private struct AppearancePreferencesKey: EnvironmentKey {
    static let defaultValue = AppearancePreferences.default
}

/// Background and card surfaces share one switch. Liquid Glass falls back to
/// material on older iOS versions, while every mode keeps a subtle readability
/// tint over a user image.
struct AppearanceBackground: View {
    let preferences: AppearancePreferences
    @Environment(\.colorScheme) private var colorScheme

    private var fallbackColor: Color {
        Color(.systemGroupedBackground)
    }

    private var fallbackGradient: (Color, Color) {
        (fallbackColor, Color(.secondarySystemGroupedBackground))
    }

    var body: some View {
        ZStack {
            switch preferences.backgroundMode {
            case .color:
                preferences.backgroundColorHex.map(Theme.color) ?? fallbackColor
            case .gradient:
                let fallback = fallbackGradient
                LinearGradient(
                    colors: [
                        preferences.gradientStartHex.map(Theme.color) ?? fallback.0,
                        preferences.gradientEndHex.map(Theme.color) ?? fallback.1
                    ],
                    startPoint: .top,
                    endPoint: .bottom)
            case .image:
                if let image = preferences.backgroundImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .overlay(Color(.systemBackground).opacity(0.28))
                        .clipped()
                } else {
                    fallbackColor
                }
            }
            if preferences.backgroundMode != .image {
                Color(.systemBackground).opacity(colorScheme == .dark ? 0.08 : 0.04)
            }
        }
        .ignoresSafeArea()
    }
}

private struct AppSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.appearancePreferences) private var preferences
    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        switch preferences.material {
        case .solid:
            content.background(Color(.secondarySystemGroupedBackground), in: shape)
        case .milky:
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.fill(Color(.systemBackground)
                    .opacity(colorScheme == .dark ? 0.22 : 0.12)))
        case .liquid:
            if #available(iOS 26, *) {
                content.glassEffect(
                    .regular.tint(Color(.systemBackground)
                        .opacity(colorScheme == .dark ? 0.32 : 0.18)),
                    in: shape)
            } else {
                content
                    .background(.ultraThinMaterial, in: shape)
                    .overlay(shape.fill(Color(.systemBackground).opacity(0.16)))
            }
        }
    }
}
