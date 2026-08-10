import Foundation

/// Die Farbrampe des Contribution-Graphen. Sechs eingebaute Familien, jede mit
/// fünf Stufen für hell UND dunkel, gebaut nach denselben drei Regeln wie
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
/// ändert, bekommt sofort gesagt, ob die Rampe noch trägt. Eigene Paletten des
/// Nutzers rechnen dieselben Regeln in `PaletteGenerator` aus — geprüft
/// werden beide mit denselben Invarianten.
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

    /// Die eingebaute Palette als fertige Farbtafel — dasselbe Format, das
    /// eine eigene Palette erzeugt. Ab hier weiß der Rest der App nicht mehr,
    /// ob eine Farbe eingebaut oder gerechnet ist.
    var style: PaletteStyle {
        // Die Verneinung ist auch hier GERECHNET und nicht als siebte
        // Konstante von Hand gesetzt: dieselbe Regel für eingebaute und
        // eigene Farben, sonst wäre sie an sechs Stellen prüfbar und an
        // unendlich vielen nicht. Der Farbton-Geber ist die Markenfarbe der
        // Familie — die eingebauten haben keine „Basisfarbe".
        PaletteStyle(lightRamp: ramp(dark: false),
                     darkRamp: ramp(dark: true),
                     accentHex: accentHex,
                     accentFillLight: accentFillHex.light,
                     accentFillDark: accentFillHex.dark,
                     accentTextLight: accentTextHex.light,
                     accentTextDark: accentTextHex.dark,
                     negativeLight: PaletteGenerator.negative(ramp: ramp(dark: false),
                                                              hueSource: accentHex, dark: false),
                     negativeDark: PaletteGenerator.negative(ramp: ramp(dark: true),
                                                             hueSource: accentHex, dark: true))
    }
}

// MARK: – Die aufgelöste Farbtafel

/// Eine FERTIGE Palette: fünf Rasterstufen je Schema plus die drei
/// Akzent-Rollen. Der gemeinsame Nenner von eingebauten und eigenen Farben —
/// alles, was zeichnet, bekommt diesen Typ und nicht mehr die Herkunft.
struct PaletteStyle: Equatable, Hashable, Sendable {
    let lightRamp: [UInt32]
    let darkRamp: [UInt32]
    let accentHex: UInt32
    let accentFillLight: UInt32
    let accentFillDark: UInt32
    let accentTextLight: UInt32
    let accentTextDark: UInt32
    /// Die Farbe eines mit NEIN beantworteten Tages. Gehört in die Tafel und
    /// nicht neben sie: sie hängt an der RAMPE dieser Palette (sie liegt in
    /// deren Mitte) und muss überall dort verfügbar sein, wo die Rampe es
    /// ist — bis in den Widget-Eintrag, der keine Umgebung hat.
    let negativeLight: UInt32
    let negativeDark: UInt32

    func ramp(dark: Bool) -> [UInt32] { dark ? darkRamp : lightRamp }
    func negative(dark: Bool) -> UInt32 { dark ? negativeDark : negativeLight }
    var accentFillHex: (light: UInt32, dark: UInt32) { (accentFillLight, accentFillDark) }
    var accentTextHex: (light: UInt32, dark: UInt32) { (accentTextLight, accentTextDark) }

    static let `default` = GraphPalette.default.style
}

// MARK: – Eigene Palette

/// Eine vom Nutzer angelegte Farbe.
///
/// Gespeichert wird NUR `base` — die Rampe entsteht bei jedem Lesen neu aus
/// `PaletteGenerator`. Das ist Absicht: ein verbesserter Generator hebt damit
/// automatisch alle bestehenden Paletten mit an, statt eingefrorene Hex-Werte
/// aus einer alten App-Version weiterzuschleppen. Die Farbe des Nutzers ist
/// die Wahrheit, die Rampe ist eine Ableitung.
struct CustomPalette: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// Die gewählte Basisfarbe als 0xRRGGBB.
    var base: UInt32

    init(id: UUID = UUID(), name: String, base: UInt32) {
        self.id = id
        self.name = name
        self.base = base & 0xFFFFFF
    }

    var style: PaletteStyle { PaletteGenerator.style(base: base) }

    /// Was im Picker steht, wenn der Nutzer das Namensfeld leer gelassen hat.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Eigene Farbe") : trimmed
    }

    private enum CodingKeys: String, CodingKey { case id, name, base }

    /// Tolerant wie alles andere in dieser Datei: fehlt der Name, ist die
    /// Palette trotzdem brauchbar; fehlt die Farbe, wird sie grün statt
    /// unlesbar.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        base = (try c.decodeIfPresent(UInt32.self, forKey: .base) ?? 0x2EA043) & 0xFFFFFF
    }
}

// MARK: – Verweis auf eine Palette

/// Was eine Einstellung speichert: entweder eine der sechs eingebauten
/// Familien oder die Kennung einer eigenen Palette.
///
/// Auf der Platte ist das EIN String — `"blue"` wie bisher, `"custom:<UUID>"`
/// für eigene. Bestehende Dateien lesen deshalb unverändert weiter, und ein
/// älterer Build, der `custom:…` nicht kennt, verliert nur die Farbe
/// (tolerantes Dekodieren), nie die Check-ins.
enum PaletteRef: Hashable, Sendable, RawRepresentable {
    case builtin(GraphPalette)
    case custom(UUID)

    static let `default` = PaletteRef.builtin(.default)

    // Bequemlichkeit für Code und Tests: `.blue` bleibt `.blue`.
    static let green = PaletteRef.builtin(.green)
    static let blue = PaletteRef.builtin(.blue)
    static let violet = PaletteRef.builtin(.violet)
    static let amber = PaletteRef.builtin(.amber)
    static let rose = PaletteRef.builtin(.rose)
    static let gray = PaletteRef.builtin(.gray)

    private static let customPrefix = "custom:"

    init?(rawValue: String) {
        if let builtin = GraphPalette(rawValue: rawValue) {
            self = .builtin(builtin)
            return
        }
        guard rawValue.hasPrefix(Self.customPrefix),
              let id = UUID(uuidString: String(rawValue.dropFirst(Self.customPrefix.count)))
        else { return nil }
        self = .custom(id)
    }

    var rawValue: String {
        switch self {
        case .builtin(let palette): return palette.rawValue
        case .custom(let id): return Self.customPrefix + id.uuidString
        }
    }

    var customID: UUID? {
        if case .custom(let id) = self { return id }
        return nil
    }

    /// Die Farbtafel dazu — `nil`, wenn der Verweis ins Leere zeigt (eine
    /// gelöschte eigene Palette). Das `nil` ist der Grund, warum die
    /// Auflösung eine Kette ist und kein Nachschlagen.
    func style(customs: [CustomPalette]) -> PaletteStyle? {
        switch self {
        case .builtin(let palette): return palette.style
        case .custom(let id): return customs.first { $0.id == id }?.style
        }
    }
}

extension PaletteRef: Codable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PaletteRef(rawValue: raw) ?? .default
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

// MARK: – Auflösung

extension PaletteStyle {
    /// **Die eine Auflösungsregel** für die ganze App (Liste, Blätter,
    /// Teilen-Karte, Widget): die Habit-Einstellung schlägt die globale, die
    /// globale schlägt den Standard.
    ///
    /// Ein Verweis auf eine GELÖSCHTE eigene Palette gilt als „nicht
    /// gesetzt" und fällt durch die Kette weiter — beim Habit also auf die
    /// globale Farbe, global auf den Standard (Grün). So bleibt eine Liste
    /// nach dem Löschen einer Farbe einheitlich, statt in zwei Farben zu
    /// zerfallen; kaputt wird nichts.
    static func resolve(habit: Habit?,
                        global: PaletteRef?,
                        customs: [CustomPalette] = []) -> PaletteStyle {
        habit?.palette?.style(customs: customs)
            ?? global?.style(customs: customs)
            ?? .default
    }
}

/// Global eingestellte Farbe PLUS die eigenen Paletten — das Paar, das man
/// zum Auflösen braucht. Reist als EIN Umgebungswert durch die App und als
/// EIN Feld durch den Widget-Eintrag; zwei getrennte Werte wären zwei
/// Gelegenheiten, sie auseinanderlaufen zu lassen.
struct PaletteBook: Equatable, Hashable, Sendable {
    var global: PaletteRef = .default
    var customs: [CustomPalette] = []

    /// Die globale Farbtafel — für Akzente, Tint und Chrom.
    var style: PaletteStyle { PaletteStyle.resolve(habit: nil, global: global, customs: customs) }

    /// Die Farbtafel EINES Habits — für sein Raster.
    func style(for habit: Habit?) -> PaletteStyle {
        PaletteStyle.resolve(habit: habit, global: global, customs: customs)
    }

    /// Name eines Verweises für die Oberfläche; leer, wenn er ins Leere zeigt.
    func displayName(_ ref: PaletteRef) -> String? {
        switch ref {
        case .builtin(let palette): return palette.displayName
        case .custom(let id): return customs.first { $0.id == id }?.displayName
        }
    }
}
