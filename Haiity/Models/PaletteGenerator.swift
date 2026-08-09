import Foundation

/// Baut aus EINER vom Nutzer gewählten Farbe eine vollständige Palette:
/// fünf Rasterstufen je Schema plus die drei Akzent-Rollen.
///
/// **Warum nicht in sRGB interpolieren.** Ein linearer Verlauf zwischen zwei
/// sRGB-Werten läuft durch matschige Mitten und ist in der wahrgenommenen
/// Helligkeit nicht monoton — genau die Eigenschaft, an der die Rampe hängt.
/// Gerechnet wird deshalb in **OKLCH** (OKLab in Polarkoordinaten): der
/// Farbton bleibt der des Nutzers, Helligkeit und Buntheit werden getrennt
/// gesteuert. Die Matrizen sind Ottossons Original; es gibt keine
/// Abhängigkeit, die das mitbrächte.
///
/// **Warum nicht auf OKLab-L gezielt wird.** Die Tests (und die Augen) messen
/// WCAG-Leuchtdichte, und die ist bei gleicher OKLab-Helligkeit für Gelb und
/// Blau nicht dieselbe. Also wird direkt auf die LEUCHTDICHTE gezielt: für
/// jede Stufe steht der gewünschte Kontrast gegen die Karte fest, daraus
/// fällt ein Ziel-Y, und eine Intervallhalbierung über L sucht die Farbe des
/// gewählten Farbtons, die dieses Y trifft. Die Buntheit wird dabei am
/// sRGB-Rand abgeschnitten (`maxChroma`) — deshalb entsättigen die hellen
/// Enden von selbst, statt aus dem Farbraum zu fallen.
///
/// **Was das für die Randfälle bedeutet.** Weiß, Schwarz und Grau haben keinen
/// Farbton; sie erzeugen eine monochrome Rampe (wie die eingebaute Palette
/// „Monochrom"). Ein Neon-Ton bekommt so viel Buntheit, wie sRGB bei der
/// nötigen Helligkeit hergibt. In beiden Fällen stimmen die Kontraste, weil
/// die Kontraste das Ziel sind und die Farbe der Weg dorthin.
enum PaletteGenerator {

    // MARK: – Zielkontraste
    //
    // Die Rampe wird nicht „schön geraten", sondern gegen die Karte gerechnet.
    // Jede Zahl ist der Kontrast der Stufe GEGEN DIE KARTE (#FFFFFF hell,
    // #1C1C1E dunkel). Daraus folgen automatisch beide Invarianten:
    //   * l0 liegt in [1,10 … 1,85] — sichtbar, aber leise.
    //   * zwischen zwei Stufen liegen ≥ 1,15 (hier real ≥ 1,36), weil die
    //     Reihe streng wächst.
    // Der Abstand ist bewusst großzügig: nach dem Runden auf 8 Bit bleibt
    // genug Luft, dass keine Stufe an der Grenze kippt.
    static let lightSteps: [Double] = [1.28, 1.75, 2.90, 4.80, 8.00]
    static let darkSteps: [Double] = [1.30, 2.00, 3.20, 5.20, 8.40]

    /// Wie viel der gewünschten Buntheit eine Stufe bekommt. Nicht kosmetisch:
    /// im Light Mode ist l1 ein blasser HAUCH und erst l3/l4 tragen die volle
    /// Farbe (so läuft GitHubs Original), im Dark Mode ist es umgekehrt — dort
    /// ist l1 die dunkelste Stufe und die hellste darf nicht grellen.
    /// Der Wert für l0 steht separat (`hint`), er ist keine Abstufung, sondern
    /// eine Andeutung.
    static let lightChroma: [Double] = [0, 0.55, 0.80, 1.00, 1.00]
    static let darkChroma: [Double] = [0, 1.00, 1.00, 0.95, 0.85]

    /// Die Fläche, gegen die l0 bestehen muss. EINE Quelle für App und
    /// Generator (`Theme.cardHex` reicht hierher durch).
    static func cardHex(dark: Bool) -> UInt32 { dark ? 0x1C1C1E : 0xFFFFFF }

    /// Unterhalb dieser Buntheit gilt eine Farbe als unbunt — Weiß, Schwarz
    /// und jedes Grau landen hier und bekommen eine neutrale Rampe. Ein
    /// Farbton, den es nicht gibt, wird nicht erfunden.
    static let achromatic = 0.020

    // MARK: – Öffentliche Schnittstelle

    /// l0…l4 für ein Schema. Rein, deterministisch, ohne UIKit — damit die
    /// Tests dieselbe Funktion prüfen können, die die App zeichnet.
    static func ramp(base: UInt32, dark: Bool) -> [UInt32] {
        let (_, chroma0, hue) = oklch(base)
        let mono = chroma0 < achromatic
        // Buntheit der Rampe: der Wunsch des Nutzers, mit Boden und Deckel.
        // Der Boden sorgt dafür, dass ein blasses Pastell trotzdem als Farbe
        // liest; der Deckel verhindert, dass ein Neon-Ton in den Mitten
        // gegen die sRGB-Wand läuft.
        let chroma = mono ? 0 : min(0.26, max(0.075, chroma0 * 1.10))
        // l0 trägt den Farbton nur als ANDEUTUNG (Regel 3 der Rampen): das
        // Raster liest sich als Familie, die leere Zelle bleibt fast neutral.
        let hint = mono ? 0 : (dark ? 0.014 : 0.012)
        let card = luminance(cardHex(dark: dark))
        let steps = dark ? darkSteps : lightSteps
        let factors = dark ? darkChroma : lightChroma
        return steps.enumerated().map { index, ratio in
            // Hell: die Stufe ist DUNKLER als die weiße Karte, dunkel heller
            // als die schwarze — dieselbe Kontrastformel, andere Richtung.
            let target = dark
                ? (card + 0.05) * ratio - 0.05
                : (card + 0.05) / ratio - 0.05
            return solve(hue: hue,
                         chroma: index == 0 ? hint : chroma * factors[index],
                         targetLuminance: max(0, min(1, target)))
        }
    }

    /// Die drei Akzent-Rollen. Eigene Ziel-Leuchtdichten, weil eine Farbstufe
    /// nicht gleichzeitig weiße Schrift tragen und selbst als Schrift auf
    /// hellem Grund lesbar sein kann:
    ///   * `fill` trägt WEISSE Schrift -> ≥ 4,5:1 gegen Weiß, also dunkel.
    ///   * `text` ist selbst Schrift -> hell im Dark Mode, dunkel im Light.
    ///   * `accent` ist reine Fläche und darf dazwischen liegen.
    static func accents(base: UInt32) -> (accent: UInt32,
                                          fillLight: UInt32, fillDark: UInt32,
                                          textLight: UInt32, textDark: UInt32) {
        let (_, chroma0, hue) = oklch(base)
        let mono = chroma0 < achromatic
        // Akzente dürfen bunter sein als die Rampe: sie stehen einzeln, nicht
        // als Reihe, und sollen die Marke tragen.
        let chroma = mono ? 0 : min(0.30, max(0.09, chroma0 * 1.25))
        func at(_ y: Double) -> UInt32 { solve(hue: hue, chroma: chroma, targetLuminance: y) }
        return (accent: at(0.200),
                fillLight: at(0.140), fillDark: at(0.168),
                textLight: at(0.148), textDark: at(0.300))
    }

    /// Die fertige Palette. Gecacht, weil `CustomPalette.style` bei jedem
    /// Zeichnen gelesen wird und eine Rampe rund 2 500 Farbraum-Umrechnungen
    /// kostet — einmal pro Basisfarbe reicht.
    static func style(base: UInt32) -> PaletteStyle {
        let key = base & 0xFFFFFF
        if let hit = cache.withLock({ $0[key] }) { return hit }
        let a = accents(base: key)
        let style = PaletteStyle(lightRamp: ramp(base: key, dark: false),
                                 darkRamp: ramp(base: key, dark: true),
                                 accentHex: a.accent,
                                 accentFillLight: a.fillLight,
                                 accentFillDark: a.fillDark,
                                 accentTextLight: a.textLight,
                                 accentTextDark: a.textDark)
        cache.withLock { store in
            // Kein LRU nötig: so viele eigene Farben legt niemand an. Der
            // Deckel ist nur die Bremse gegen einen ColorPicker, der beim
            // Ziehen hunderte Zwischenwerte durchreicht.
            if store.count > 128 { store.removeAll() }
            store[key] = style
        }
        return style
    }

    private static let cache = PaletteCache()

    // MARK: – Farbton der Basis (für die Icon-Zuordnung)

    /// Farbton in Grad (0…360) und Buntheit der Basisfarbe. `nil`, wenn die
    /// Farbe unbunt ist — dann gibt es keinen Farbton, den man vergleichen
    /// könnte.
    static func hueDegrees(_ hex: UInt32) -> Double? {
        let (_, chroma, hue) = oklch(hex)
        guard chroma >= achromatic else { return nil }
        let deg = hue * 180 / .pi
        return deg < 0 ? deg + 360 : deg
    }

    // MARK: – Die Suche

    /// Sucht die Farbe mit DIESEM Farbton, die DIESE Leuchtdichte trifft.
    ///
    /// Intervallhalbierung über die OKLab-Helligkeit: Y wächst mit L monoton
    /// (bei L = 0 ist die Farbe Schwarz, bei L = 1 Weiß), das Intervall
    /// umschließt die Lösung also immer. Gemessen wird am GERUNDETEN
    /// 8-Bit-Wert — genau der Farbe, die später gezeichnet wird; deshalb wird
    /// der beste gesehene Kandidat mitgeführt statt am Ende neu gerechnet.
    private static func solve(hue: Double, chroma: Double, targetLuminance: Double) -> UInt32 {
        var lo = 0.0, hi = 1.0
        var best: UInt32 = 0
        var bestError = Double.infinity
        for _ in 0..<18 {
            let mid = (lo + hi) / 2
            let hex = quantized(lightness: mid, chroma: chroma, hue: hue)
            let y = luminance(hex)
            let error = abs(y - targetLuminance)
            if error < bestError { bestError = error; best = hex }
            if y < targetLuminance { lo = mid } else { hi = mid }
        }
        return best
    }

    /// OKLCH -> 8-Bit-sRGB, mit Buntheit am Farbraumrand abgeschnitten.
    private static func quantized(lightness: Double, chroma: Double, hue: Double) -> UInt32 {
        let c = min(chroma, maxChroma(lightness: lightness, hue: hue))
        let (r, g, b) = linearRGB(lightness: lightness, a: c * cos(hue), b: c * sin(hue))
        return hex(encode(r), encode(g), encode(b))
    }

    /// Größte Buntheit, die bei dieser Helligkeit und diesem Farbton noch in
    /// sRGB passt. Ohne diesen Schnitt würde ein Neon-Wunsch beim Umrechnen
    /// beschnitten und dabei den Farbton verziehen.
    private static func maxChroma(lightness: Double, hue: Double) -> Double {
        var lo = 0.0, hi = 0.40
        let cosH = cos(hue), sinH = sin(hue)
        for _ in 0..<14 {
            let mid = (lo + hi) / 2
            let (r, g, b) = linearRGB(lightness: lightness, a: mid * cosH, b: mid * sinH)
            let inGamut = r >= -1e-6 && r <= 1 + 1e-6
                && g >= -1e-6 && g <= 1 + 1e-6
                && b >= -1e-6 && b <= 1 + 1e-6
            if inGamut { lo = mid } else { hi = mid }
        }
        return lo
    }

    // MARK: – Farbraum (Ottosson, OKLab)

    /// sRGB-Hex -> OKLCH (Helligkeit, Buntheit, Farbton im Bogenmaß).
    static func oklch(_ hex: UInt32) -> (l: Double, c: Double, h: Double) {
        let r = decode(Double((hex >> 16) & 0xFF) / 255)
        let g = decode(Double((hex >> 8) & 0xFF) / 255)
        let b = decode(Double(hex & 0xFF) / 255)

        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)

        let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        return (lightness, sqrt(a * a + bb * bb), atan2(bb, a))
    }

    /// OKLab -> lineares sRGB (noch ungeklemmt, damit `maxChroma` sehen kann,
    /// dass es aus dem Farbraum läuft).
    private static func linearRGB(lightness: Double, a: Double, b: Double)
        -> (Double, Double, Double) {
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    /// sRGB-Übertragungsfunktion (dieselbe wie WCAG benutzt).
    private static func decode(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// Linear -> 8 Bit, geklemmt. Der Klemmschritt ist nach `maxChroma` nur
    /// noch Rundungs-Hygiene.
    private static func encode(_ c: Double) -> UInt32 {
        let clamped = min(1, max(0, c))
        let v = clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
        return UInt32((min(1, max(0, v)) * 255).rounded())
    }

    private static func hex(_ r: UInt32, _ g: UInt32, _ b: UInt32) -> UInt32 {
        (r << 16) | (g << 8) | b
    }

    /// Relative Leuchtdichte nach WCAG 2.1 — die Größe, gegen die alle
    /// Rampen-Regeln formuliert sind.
    static func luminance(_ hex: UInt32) -> Double {
        0.2126 * decode(Double((hex >> 16) & 0xFF) / 255)
            + 0.7152 * decode(Double((hex >> 8) & 0xFF) / 255)
            + 0.0722 * decode(Double(hex & 0xFF) / 255)
    }
}

/// Winziger Mutex um den Rampen-Cache. Paletten werden auch außerhalb des
/// Main-Threads gelesen (Widget-Timeline, ImageRenderer).
private final class PaletteCache: @unchecked Sendable {
    private let lock = NSLock()
    private var store: [UInt32: PaletteStyle] = [:]

    func withLock<R>(_ body: (inout [UInt32: PaletteStyle]) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&store)
    }
}
