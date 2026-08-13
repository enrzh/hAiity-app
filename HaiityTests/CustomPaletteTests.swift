import XCTest
import UIKit
@testable import Haiity

// MARK: – Der Generator (das eigentliche Stück Arbeit)

/// Eine eigene Palette entsteht aus EINER Farbe, die der Nutzer frei wählt —
/// also auch aus Weiß, aus Schwarz, aus einem Neon-Grün oder aus einem
/// Marineblau, das kaum heller ist als der dunkle Hintergrund. Ein Generator,
/// der für Petrol schöne Rampen baut und bei Weiß eine unbrauchbare, ist nicht
/// fertig.
///
/// Deshalb wird hier nicht ein Beispiel geprüft, sondern ein GITTER: jeder
/// Farbton in 15°-Schritten, mehrere Sättigungen und Helligkeiten, dazu die
/// unbunten Extreme. Für JEDE erzeugte Rampe gelten in BEIDEN Schemata exakt
/// dieselben Invarianten wie für die sechs eingebauten (`PaletteRampTests`) —
/// nachgerechnet mit derselben unabhängigen WCAG-Umsetzung.
final class GeneratedRampInvariantTests: XCTestCase {
    private let minStep = 1.15
    private let minEmpty = 1.10
    private let maxEmpty = 1.85

    /// Farbton × Sättigung × Helligkeit plus die Fälle, an denen ein
    /// Generator typischerweise zerbricht.
    static let bases: [(String, UInt32)] = {
        var out: [(String, UInt32)] = []
        for hue in stride(from: 0, to: 360, by: 15) {
            for saturation in [0.15, 0.45, 0.85, 1.0] {
                for brightness in [0.20, 0.50, 0.80, 1.0] {
                    let color = UIColor(hue: CGFloat(hue) / 360,
                                        saturation: CGFloat(saturation),
                                        brightness: CGFloat(brightness),
                                        alpha: 1)
                    out.append(("h\(hue) s\(saturation) b\(brightness)", hex(color)))
                }
            }
        }
        // Unbunte Extreme: kein Farbton, den man halten könnte.
        for value in stride(from: 0, through: 255, by: 15) {
            let v = UInt32(value)
            out.append(("grau \(value)", (v << 16) | (v << 8) | v))
        }
        out.append(contentsOf: [
            ("reinweiß", 0xFFFFFF), ("reinschwarz", 0x000000), ("mittelgrau", 0x808080),
            ("rot", 0xFF0000), ("grün", 0x00FF00), ("blau", 0x0000FF),
            ("gelb", 0xFFFF00), ("cyan", 0x00FFFF), ("magenta", 0xFF00FF),
            ("neon", 0x39FF14), ("marineblau", 0x001F3F), ("pastell", 0xFFD1DC),
            ("beige", 0xF5F5DC), ("fast schwarz", 0x050505), ("fast weiß", 0xFDFDFD),
        ])
        return out
    }()

    private static func hex(_ color: UIColor) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ v: CGFloat) -> UInt32 { UInt32((min(1, max(0, v)) * 255).rounded()) }
        return (channel(r) << 16) | (channel(g) << 8) | channel(b)
    }

    func testGridIsWideEnoughToMeanSomething() {
        // Ein Gitter, das stillschweigend zusammenschrumpft, prüft nichts.
        XCTAssertGreaterThanOrEqual(Self.bases.count, 400)
        XCTAssertEqual(Set(Self.bases.map(\.1)).count > 300, true, "zu viele doppelte Basen")
    }

    func testEveryGeneratedRampHasFiveLevels() {
        for (label, base) in Self.bases {
            XCTAssertEqual(PaletteGenerator.ramp(base: base, dark: false).count, 5, "\(label) hell")
            XCTAssertEqual(PaletteGenerator.ramp(base: base, dark: true).count, 5, "\(label) dunkel")
        }
    }

    /// Regel 1: hell läuft l0…l4 von hell nach dunkel, dunkel umgekehrt —
    /// monoton in der WCAG-Leuchtdichte, ohne Ausreißer in der Mitte.
    func testEveryGeneratedRampIsMonotonic() {
        for (label, base) in Self.bases {
            for dark in [false, true] {
                let lums = PaletteGenerator.ramp(base: base, dark: dark).map(Contrast.luminance)
                for i in 0..<4 {
                    if dark {
                        XCTAssertGreaterThan(lums[i + 1], lums[i],
                            "\(label) dunkel: l\(i + 1) ist nicht heller als l\(i)")
                    } else {
                        XCTAssertLessThan(lums[i + 1], lums[i],
                            "\(label) hell: l\(i + 1) ist nicht dunkler als l\(i)")
                    }
                }
            }
        }
    }

    /// Regel 1b: zwei benachbarte Stufen müssen sich unterscheiden lassen.
    func testEveryGeneratedRampSeparatesItsSteps() {
        for (label, base) in Self.bases {
            for dark in [false, true] {
                let ramp = PaletteGenerator.ramp(base: base, dark: dark)
                for i in 0..<4 {
                    let step = Contrast.ratio(ramp[i], ramp[i + 1])
                    XCTAssertGreaterThanOrEqual(step, minStep,
                        "\(label) \(dark ? "dunkel" : "hell"): l\(i)→l\(i + 1) nur \(step)")
                }
            }
        }
    }

    /// Regel 2: die leere Zelle hebt sich von der Karte ab, ohne sie zu
    /// überstimmen — genau die Spanne, die auch für die eingebauten gilt.
    func testEveryGeneratedEmptyCellStandsOffTheCard() {
        for (label, base) in Self.bases {
            for dark in [false, true] {
                let l0 = PaletteGenerator.ramp(base: base, dark: dark)[0]
                let ratio = Contrast.ratio(l0, Theme.cardHex(dark: dark))
                XCTAssertGreaterThanOrEqual(ratio, minEmpty,
                    "\(label) \(dark ? "dunkel" : "hell"): l0 verschwindet in der Karte (\(ratio))")
                XCTAssertLessThanOrEqual(ratio, maxEmpty,
                    "\(label) \(dark ? "dunkel" : "hell"): l0 überstimmt die Karte (\(ratio))")
            }
        }
    }

    /// Regel 3: l0 ist NICHT die Nutzerfarbe in voller Stärke, sondern liegt
    /// auf demselben fast neutralen Niveau wie bei den eingebauten. Geprüft
    /// gegen die Spanne, die die sechs eingebauten l0-Werte aufspannen.
    func testGeneratedEmptyCellSitsAtTheBuiltinLevel() {
        for dark in [false, true] {
            let builtin = GraphPalette.allCases.map {
                Contrast.ratio($0.ramp(dark: dark)[0], Theme.cardHex(dark: dark))
            }
            let low = builtin.min()! - 0.1, high = builtin.max()! + 0.35
            for (label, base) in Self.bases {
                let ratio = Contrast.ratio(PaletteGenerator.ramp(base: base, dark: dark)[0],
                                           Theme.cardHex(dark: dark))
                XCTAssertTrue((low...high).contains(ratio),
                    "\(label) \(dark ? "dunkel" : "hell"): l0 bei \(ratio), eingebaut \(low)…\(high)")
            }
        }
    }

    /// Die Akzente tragen Text — dieselben 4,5:1 wie bei den eingebauten.
    func testGeneratedAccentsAreReadable() {
        for (label, base) in Self.bases {
            let style = PaletteGenerator.style(base: base)
            XCTAssertGreaterThanOrEqual(Contrast.ratio(style.accentFillLight, 0xFFFFFF), 4.5,
                                        "\(label) accentFill hell")
            XCTAssertGreaterThanOrEqual(Contrast.ratio(style.accentFillDark, 0xFFFFFF), 4.5,
                                        "\(label) accentFill dunkel")
            XCTAssertGreaterThanOrEqual(
                Contrast.ratio(style.accentTextLight, Theme.cardHex(dark: false)), 4.5,
                "\(label) accentText hell")
            XCTAssertGreaterThanOrEqual(
                Contrast.ratio(style.accentTextDark, Theme.cardHex(dark: true)), 4.5,
                "\(label) accentText dunkel")
        }
    }

    /// Der Farbton des Nutzers bleibt erhalten: eine bunte Basis erzeugt eine
    /// Rampe, deren mittlere Stufen denselben Farbton tragen (±25°). Ohne
    /// diese Prüfung wäre eine Rampe aus fünf Grautönen formal fehlerfrei.
    func testGeneratedRampKeepsTheChosenHue() {
        let chromatic: [UInt32] = [0x0F766E, 0x1F6FEB, 0x8250DF, 0xD1690C, 0xD1245C, 0x39FF14, 0x001F3F]
        for base in chromatic {
            guard let hue = PaletteGenerator.hueDegrees(base) else {
                XCTFail("\(String(format: "#%06X", base)) sollte bunt sein"); continue
            }
            for dark in [false, true] {
                for level in 1...4 {
                    let step = PaletteGenerator.ramp(base: base, dark: dark)[level]
                    guard let stepHue = PaletteGenerator.hueDegrees(step) else {
                        XCTFail("\(String(format: "#%06X", base)) l\(level) ist unbunt geworden"); continue
                    }
                    let raw = abs(stepHue - hue)
                    XCTAssertLessThanOrEqual(min(raw, 360 - raw), 25,
                        "\(String(format: "#%06X", base)) l\(level) \(dark ? "dunkel" : "hell"): "
                        + "Farbton \(stepHue)° statt \(hue)°")
                }
            }
        }
    }

    /// Eine unbunte Basis erfindet keinen Farbton — Weiß, Schwarz und Grau
    /// ergeben dieselbe monochrome Rampe wie die eingebaute „Monochrom".
    func testAchromaticBasesProduceANeutralRamp() {
        for base: UInt32 in [0xFFFFFF, 0x000000, 0x808080, 0x333333] {
            for dark in [false, true] {
                for step in PaletteGenerator.ramp(base: base, dark: dark) {
                    let r = (step >> 16) & 0xFF, g = (step >> 8) & 0xFF, b = step & 0xFF
                    XCTAssertEqual(r, g, "\(String(format: "#%06X", step)) ist nicht neutral")
                    XCTAssertEqual(g, b, "\(String(format: "#%06X", step)) ist nicht neutral")
                }
            }
        }
    }

    /// Dieselbe Basis ergibt dieselbe Rampe — sonst wäre die Palette beim
    /// nächsten Start eine andere, obwohl nur die Basisfarbe gespeichert ist.
    func testGeneratorIsStable() {
        for base: UInt32 in [0x0F766E, 0xFF0000, 0xFFFFFF, 0x123456] {
            XCTAssertEqual(PaletteGenerator.ramp(base: base, dark: false),
                           PaletteGenerator.ramp(base: base, dark: false))
            XCTAssertEqual(PaletteGenerator.style(base: base), PaletteGenerator.style(base: base))
            // Auch über den Umweg Modell -> Stil (der Cache darf nichts ändern).
            let palette = CustomPalette(name: "x", base: base)
            XCTAssertEqual(palette.style, PaletteGenerator.style(base: base))
        }
    }

    /// Zwei verschiedene Farbtöne dürfen nicht dieselbe Rampe ergeben.
    func testDifferentHuesProduceDifferentRamps() {
        let ramps = stride(from: 0, to: 360, by: 30).map { hue -> [UInt32] in
            let color = UIColor(hue: CGFloat(hue) / 360, saturation: 0.8, brightness: 0.8, alpha: 1)
            return PaletteGenerator.ramp(base: Self.hex(color), dark: false)
        }
        XCTAssertEqual(Set(ramps.map(\.description)).count, ramps.count)
    }
}

// MARK: – Modell und Verweise

final class PaletteRefTests: XCTestCase {
    func testBuiltinRefsRoundTripThroughTheOldStrings() {
        for palette in GraphPalette.allCases {
            let ref = PaletteRef.builtin(palette)
            XCTAssertEqual(ref.rawValue, palette.rawValue, "Dateiformat geändert")
            XCTAssertEqual(PaletteRef(rawValue: palette.rawValue), ref)
        }
    }

    func testCustomRefsRoundTrip() {
        let id = UUID()
        let ref = PaletteRef.custom(id)
        XCTAssertEqual(ref.rawValue, "custom:\(id.uuidString)")
        XCTAssertEqual(PaletteRef(rawValue: ref.rawValue), ref)
        XCTAssertEqual(ref.customID, id)
        XCTAssertNil(PaletteRef.blue.customID)
    }

    func testGarbageRefsAreRejectedNotGuessed() {
        XCTAssertNil(PaletteRef(rawValue: "neon"))
        XCTAssertNil(PaletteRef(rawValue: "custom:nicht-uuid"))
        XCTAssertNil(PaletteRef(rawValue: ""))
    }

    func testDanglingCustomRefHasNoStyle() {
        let custom = CustomPalette(name: "Petrol", base: 0x0F766E)
        XCTAssertNotNil(PaletteRef.custom(custom.id).style(customs: [custom]))
        XCTAssertNil(PaletteRef.custom(UUID()).style(customs: [custom]))
    }

    func testCustomPaletteFallsBackToAName() {
        XCTAssertEqual(CustomPalette(name: "  ", base: 0x0F766E).displayName,
                       String(localized: "Eigene Farbe"))
        XCTAssertEqual(CustomPalette(name: " Petrol ", base: 0x0F766E).displayName, "Petrol")
    }
}

// MARK: – Auflösung mit eigenen Farben

/// Die Reihenfolge, in der eine Farbe gewinnt: Habit eigen > Habit eingebaut >
/// global eigen > global eingebaut > Standard.
final class CustomPaletteResolutionTests: XCTestCase {
    private let mine = CustomPalette(name: "Petrol", base: 0x0F766E)
    private let other = CustomPalette(name: "Ziegel", base: 0xB4432A)

    func testHabitCustomBeatsEverything() {
        var habit = Habit(name: "Lesen")
        habit.palette = .custom(mine.id)
        XCTAssertEqual(PaletteStyle.resolve(habit: habit, global: .custom(other.id),
                                            customs: [mine, other]), mine.style)
    }

    func testHabitBuiltinBeatsGlobalCustom() {
        var habit = Habit(name: "Lesen")
        habit.palette = .blue
        XCTAssertEqual(PaletteStyle.resolve(habit: habit, global: .custom(mine.id),
                                            customs: [mine]), GraphPalette.blue.style)
    }

    func testGlobalCustomBeatsDefault() {
        XCTAssertEqual(PaletteStyle.resolve(habit: Habit(name: "x"), global: .custom(mine.id),
                                            customs: [mine]), mine.style)
    }

    func testGlobalBuiltinIsUsedWithoutOverride() {
        XCTAssertEqual(PaletteStyle.resolve(habit: Habit(name: "x"), global: .rose, customs: [mine]),
                       GraphPalette.rose.style)
    }

    func testFallsBackToTheDefaultWithoutAnything() {
        XCTAssertEqual(PaletteStyle.resolve(habit: nil, global: nil), .default)
        XCTAssertEqual(PaletteStyle.default, GraphPalette.green.style)
    }

    /// Verweist die GLOBALE Einstellung auf eine gelöschte Farbe, gilt der
    /// Standard — nicht irgendetwas.
    func testDanglingGlobalRefFallsBackToTheDefault() {
        XCTAssertEqual(PaletteStyle.resolve(habit: nil, global: .custom(UUID()), customs: [mine]),
                       .default)
    }

    /// Verweist die HABIT-Übersteuerung ins Leere, fällt sie durch auf die
    /// globale Farbe: die Liste bleibt einheitlich statt in zwei Farben zu
    /// zerfallen.
    func testDanglingHabitRefFallsThroughToGlobal() {
        var habit = Habit(name: "Lesen")
        habit.palette = .custom(UUID())
        XCTAssertEqual(PaletteStyle.resolve(habit: habit, global: .amber, customs: [mine]),
                       GraphPalette.amber.style)
    }

    func testPaletteBookResolvesTheSameWay() {
        var habit = Habit(name: "Lesen")
        habit.palette = .custom(mine.id)
        let book = PaletteBook(global: .blue, customs: [mine])
        XCTAssertEqual(book.style, GraphPalette.blue.style)
        XCTAssertEqual(book.style(for: habit), mine.style)
        XCTAssertEqual(book.style(for: Habit(name: "y")), GraphPalette.blue.style)
        XCTAssertEqual(book.displayName(.custom(mine.id)), "Petrol")
        XCTAssertEqual(book.displayName(.violet), GraphPalette.violet.displayName)
        XCTAssertNil(book.displayName(.custom(UUID())))
    }
}

// MARK: – Anlegen, Umbenennen, Ändern, Löschen

final class CustomPaletteCRUDTests: XCTestCase {
    private var url: URL!
    private var store: HabitStore!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-custom-\(UUID().uuidString).json")
        store = HabitStore(url: url)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    func testCreateStoresOnlyTheBaseColour() throws {
        let palette = store.addCustomPalette(name: "Petrol", base: 0x0F766E)
        XCTAssertEqual(store.customPalettes.count, 1)
        XCTAssertEqual(store.customPalettes[0].base, 0x0F766E)
        // Die Rampe ist NICHT in der Datei — sie wird gerechnet.
        let raw = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        XCTAssertTrue(raw.contains("customPalettes"))
        XCTAssertTrue(raw.contains(palette.id.uuidString))
        XCTAssertFalse(raw.lowercased().contains("ramp"))
    }

    func testRenameKeepsTheColour() {
        var palette = store.addCustomPalette(name: "Petrol", base: 0x0F766E)
        palette.name = "Tiefsee"
        store.updateCustomPalette(palette)
        XCTAssertEqual(store.customPalettes[0].name, "Tiefsee")
        XCTAssertEqual(store.customPalettes[0].base, 0x0F766E)
        XCTAssertEqual(HabitStore(url: url).customPalettes[0].name, "Tiefsee")
    }

    func testEditChangesTheColourAndTheWholeRamp() {
        var palette = store.addCustomPalette(name: "Petrol", base: 0x0F766E)
        let before = palette.style
        palette.base = 0xB4432A
        store.updateCustomPalette(palette)
        XCTAssertEqual(store.customPalettes[0].base, 0xB4432A)
        XCTAssertNotEqual(store.customPalettes[0].style, before)
    }

    func testUpdatingAnUnknownPaletteDoesNothing() {
        store.addCustomPalette(name: "Petrol", base: 0x0F766E)
        store.updateCustomPalette(CustomPalette(name: "Geist", base: 0x000000))
        XCTAssertEqual(store.customPalettes.count, 1)
        XCTAssertEqual(store.customPalettes[0].name, "Petrol")
    }

    func testDeleteRemovesIt() {
        let palette = store.addCustomPalette(name: "Petrol", base: 0x0F766E)
        store.removeCustomPalette(palette.id)
        XCTAssertTrue(store.customPalettes.isEmpty)
        XCTAssertTrue(HabitStore(url: url).customPalettes.isEmpty)
    }

    func testUsageIsReportedForGlobalAndForHabits() {
        let palette = store.addCustomPalette(name: "Petrol", base: 0x0F766E)
        XCTAssertFalse(store.isCustomPaletteInUse(palette.id))

        var habit = Habit(name: "Lesen")
        habit.palette = .custom(palette.id)
        store.add(habit)
        XCTAssertTrue(store.isCustomPaletteInUse(palette.id))
        XCTAssertEqual(store.paletteUsage(palette.id).habits.count, 1)
        XCTAssertFalse(store.paletteUsage(palette.id).global)

        store.palette = .custom(palette.id)
        XCTAssertTrue(store.paletteUsage(palette.id).global)
    }

    /// Der Fall, um den es beim Löschen wirklich geht: die Farbe ist global
    /// UND an einem Habit gesetzt. Danach darf nirgends ein toter Verweis
    /// übrig bleiben.
    func testDeleteWhileInUseFallsBackEverywhere() {
        let palette = store.addCustomPalette(name: "Petrol", base: 0x0F766E)
        var coloured = Habit(name: "Meditation")
        coloured.palette = .custom(palette.id)
        var untouched = Habit(name: "Lesen")
        untouched.palette = .violet
        store.add(coloured)
        store.add(untouched)
        store.palette = .custom(palette.id)

        store.removeCustomPalette(palette.id)

        XCTAssertEqual(store.palette, .default)
        XCTAssertNil(store.habits[0].palette, "Habit-Übersteuerung zeigt ins Leere")
        XCTAssertEqual(store.habits[1].palette, .violet, "fremde Farbe angefasst")
        XCTAssertEqual(store.palettes.style(for: store.habits[0]), .default)
        // Und nach einem Neustart genauso.
        let reloaded = HabitStore(url: url)
        XCTAssertEqual(reloaded.palette, .default)
        XCTAssertNil(reloaded.habits[0].palette)
    }

    /// Der Verweis kann NACH dem Löschen wieder auftauchen — vom anderen
    /// Gerät, das die Farbe noch kannte. Er darf dann nichts kaputt machen,
    /// sondern fällt still auf die App-Farbe zurück.
    func testRefThatComesBackFromSyncWithoutItsPaletteFallsBack() {
        let palette = store.addCustomPalette(name: "Petrol", base: 0x0F766E)
        let habit = Habit(name: "Lesen")
        store.add(habit)
        store.removeCustomPalette(palette.id)

        var remoteHabit = habit
        remoteHabit.palette = .custom(palette.id)   // Farbe fehlt in remote
        store.merge(remote: HabitData(version: 2,
                                      updatedAt: Date().timeIntervalSince1970 + 60,
                                      summaryMinutes: nil, habits: [remoteHabit]))

        XCTAssertEqual(store.habits[0].palette, .custom(palette.id))
        XCTAssertTrue(store.customPalettes.isEmpty)
        XCTAssertEqual(store.palettes.style(for: store.habits[0]), .default)
    }

    func testSelectingACustomPaletteGlobally() {
        let palette = store.addCustomPalette(name: "Petrol", base: 0x0F766E)
        store.palette = .custom(palette.id)
        XCTAssertEqual(store.paletteStyle, palette.style)
        XCTAssertEqual(HabitStore(url: url).paletteStyle, palette.style)
    }
}

// MARK: – Persistenz

final class CustomPalettePersistenceTests: XCTestCase {
    private func decode(_ json: String) throws -> HabitData {
        try JSONDecoder().decode(HabitData.self, from: Data(json.utf8))
    }

    /// Jede Datei, die es heute gibt, kennt `customPalettes` nicht. Sie muss
    /// unverändert laden — kein Versionssprung, kein Fehler.
    func testFileWithoutCustomPalettesLoads() throws {
        let data = try decode("""
        {"version":2,"updatedAt":1,"palette":"blue","habits":[
          {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Lesen",
           "createdAt":"2026-01-01","log":{"2026-01-02":1}}
        ]}
        """)
        XCTAssertTrue(data.customPalettes.isEmpty)
        XCTAssertEqual(data.palette, .blue)
        XCTAssertEqual(data.version, 2, "kein Versionssprung für ein additives Feld")
        XCTAssertTrue(data.habits[0].isDone("2026-01-02"))
    }

    func testCustomPalettesRoundTrip() throws {
        let mine = CustomPalette(name: "Petrol", base: 0x0F766E)
        var habit = Habit(name: "Lesen")
        habit.palette = .custom(mine.id)
        let data = HabitData(version: 2, updatedAt: 5, summaryMinutes: nil, habits: [habit],
                             palette: .custom(mine.id), customPalettes: [mine])
        let back = try JSONDecoder().decode(HabitData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(back.customPalettes, [mine])
        XCTAssertEqual(back.palette, .custom(mine.id))
        XCTAssertEqual(back.habits[0].palette, .custom(mine.id))
    }

    func testDefaultsStayImplicit() throws {
        let data = HabitData(version: 2, updatedAt: 1, summaryMinutes: nil,
                             habits: [Habit(name: "Lesen")])
        let json = String(decoding: try JSONEncoder().encode(data), as: UTF8.self)
        XCTAssertFalse(json.contains("customPalettes"))
        XCTAssertFalse(json.contains("palette"))
    }

    /// Kaputte Einträge kosten die Farben, nie die Check-ins.
    func testBrokenCustomPalettesDoNotBreakTheFile() throws {
        let data = try decode("""
        {"version":2,"updatedAt":1,"customPalettes":[{"nope":true}],"habits":[
          {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Lesen",
           "createdAt":"2026-01-01","log":{"2026-01-02":1}}
        ]}
        """)
        XCTAssertTrue(data.customPalettes.isEmpty)
        XCTAssertTrue(data.habits[0].isDone("2026-01-02"))
    }

    /// Fehlender Name / fehlende Farbe: brauchbar statt unlesbar.
    func testPartialCustomPaletteEntryIsTolerated() throws {
        let data = try decode("""
        {"version":2,"updatedAt":1,"customPalettes":[
          {"id":"11111111-1111-1111-1111-111111111111"}
        ],"habits":[]}
        """)
        XCTAssertEqual(data.customPalettes.count, 1)
        XCTAssertEqual(data.customPalettes[0].name, "")
        XCTAssertEqual(data.customPalettes[0].displayName, String(localized: "Eigene Farbe"))
    }

    /// Ein Verweis auf eine eigene Farbe aus einer NEUEREN App-Version, die
    /// diese Datei nicht mitliefert: die Farbe fehlt, das Habit bleibt.
    func testUnknownCustomRefKeepsTheHabit() throws {
        let data = try decode("""
        {"version":2,"updatedAt":1,"palette":"custom:22222222-2222-2222-2222-222222222222",
         "habits":[{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Lesen",
           "createdAt":"2026-01-01","log":{"2026-01-02":1},
           "palette":"custom:22222222-2222-2222-2222-222222222222"}]}
        """)
        XCTAssertTrue(data.habits[0].isDone("2026-01-02"))
        XCTAssertEqual(PaletteBook(global: data.palette, customs: data.customPalettes)
            .style(for: data.habits[0]), .default)
    }
}

// MARK: – Sync

final class CustomPaletteMergeTests: XCTestCase {
    private var url: URL!
    private var store: HabitStore!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-cpmerge-\(UUID().uuidString).json")
        store = HabitStore(url: url)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    private func remote(_ palettes: [CustomPalette], newer: Bool, palette: PaletteRef = .default) -> HabitData {
        HabitData(version: 2,
                  updatedAt: newer ? Date().timeIntervalSince1970 + 60 : 1,
                  summaryMinutes: nil, habits: [],
                  palette: palette, customPalettes: palettes)
    }

    /// Eine auf dem anderen Gerät angelegte Farbe kommt an — auch wenn der
    /// dortige Stand ÄLTER ist. Paletten sind Daten, keine Einstellung.
    func testRemotePalettesAreUnionedEvenWhenOlder() {
        let local = store.addCustomPalette(name: "Petrol", base: 0x0F766E)
        let theirs = CustomPalette(name: "Ziegel", base: 0xB4432A)
        store.merge(remote: remote([theirs], newer: false))
        XCTAssertEqual(store.customPalettes.map(\.id), [local.id, theirs.id])
        XCTAssertEqual(store.customPalettes[1].name, "Ziegel")
    }

    func testNewerRemoteWinsOnTheSameId() {
        let local = store.addCustomPalette(name: "Petrol", base: 0x0F766E)
        var theirs = local
        theirs.name = "Tiefsee"
        theirs.base = 0x123456
        store.merge(remote: remote([theirs], newer: true))
        XCTAssertEqual(store.customPalettes.count, 1)
        XCTAssertEqual(store.customPalettes[0].name, "Tiefsee")
        XCTAssertEqual(store.customPalettes[0].base, 0x123456)
    }

    func testOlderRemoteDoesNotOverwriteTheSameId() {
        let local = store.addCustomPalette(name: "Petrol", base: 0x0F766E)
        var theirs = local
        theirs.name = "Alt"
        store.merge(remote: remote([theirs], newer: false))
        XCTAssertEqual(store.customPalettes[0].name, "Petrol")
    }

    /// Die globale Auswahl reist wie bisher mit dem neueren Stand — auch,
    /// wenn sie auf eine eigene Farbe zeigt.
    func testNewerRemoteBringsItsGlobalCustomSelection() {
        let theirs = CustomPalette(name: "Ziegel", base: 0xB4432A)
        store.merge(remote: remote([theirs], newer: true, palette: .custom(theirs.id)))
        XCTAssertEqual(store.palette, .custom(theirs.id))
        XCTAssertEqual(store.paletteStyle, theirs.style)
    }

    /// Habit-Farben sind Metadaten und folgen dem neueren Stand — inklusive
    /// eines Verweises auf eine eigene Farbe.
    func testMergeCarriesCustomHabitPalette() {
        let habit = Habit(name: "Lesen")
        store.add(habit)
        let theirs = CustomPalette(name: "Ziegel", base: 0xB4432A)
        var remoteHabit = habit
        remoteHabit.palette = .custom(theirs.id)
        store.merge(remote: HabitData(version: 2,
                                      updatedAt: Date().timeIntervalSince1970 + 60,
                                      summaryMinutes: nil, habits: [remoteHabit],
                                      customPalettes: [theirs]))
        XCTAssertEqual(store.habits[0].palette, .custom(theirs.id))
        XCTAssertEqual(store.palettes.style(for: store.habits[0]), theirs.style)
    }

    func testImportGoesThroughTheSameMerge() throws {
        let theirs = CustomPalette(name: "Ziegel", base: 0xB4432A)
        let raw = try JSONEncoder().encode(remote([theirs], newer: true))
        try store.importJSON(raw)
        XCTAssertEqual(store.customPalettes, [theirs])
    }
}

// MARK: – App-Icon

/// iOS kann nur MITGELIEFERTE Icons setzen. Eine freie Farbe bekommt deshalb
/// das nächstliegende der 18 eingebauten — fünf Palettenakzente plus zwölf
/// Farbton-Icons alle 30° — siehe die Begründung in AppIcons.
final class CustomPaletteIconTests: XCTestCase {
    func testBuiltinRefsKeepTheirOwnIcon() {
        for palette in GraphPalette.allCases {
            XCTAssertEqual(AppIcons.iconName(for: .builtin(palette), customs: []),
                           AppIcons.name(for: palette))
        }
    }

    /// Der exakte Akzent einer eingebauten Palette landet als freie Farbe
    /// wieder auf GENAU deren Icon — die Anker schlagen sich nicht
    /// gegenseitig tot.
    func testBuiltinAccentsRoundTripThroughTheFreeColorPath() {
        for palette in GraphPalette.allCases where palette != .gray {
            XCTAssertEqual(AppIcons.iconName(forBase: palette.accentHex),
                           AppIcons.name(for: palette), palette.rawValue)
        }
    }

    /// Mit Ankern alle 30° liegt JEDE bunte Farbe höchstens ~15° neben
    /// ihrem Icon — die Eigenschaft, nicht einzelne Zufallsfälle.
    func testEveryHueLandsWithinFifteenDegreesOfItsIcon() {
        for hue in stride(from: 0, to: 360, by: 5) {
            let color = UIColor(hue: CGFloat(hue) / 360, saturation: 0.7, brightness: 0.7, alpha: 1)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            let base = (UInt32(r * 255) << 16) | (UInt32(g * 255) << 8) | UInt32(b * 255)
            guard let baseHue = PaletteGenerator.hueDegrees(base) else { continue }

            let name = AppIcons.iconName(forBase: base)
            if let name {
                XCTAssertTrue(AppIcons.alternateNames.contains(name), "\(name) ist kein echtes Icon")
            }
            let iconHue: Double? = AppIcons.hues.first { $0.name == name }.map { Double($0.degrees) }
                ?? GraphPalette.allCases.first { AppIcons.name(for: $0) == name }
                    .flatMap { PaletteGenerator.hueDegrees($0.accentHex) }
            let dist = iconHue.map { min(abs($0 - baseHue), 360 - abs($0 - baseHue)) }
            XCTAssertNotNil(dist)
            XCTAssertLessThanOrEqual(dist ?? 999, 16, String(format: "#%06X (H%.0f)", base, baseHue))
        }
    }

    func testAchromaticCustomPaletteTakesTheMonochromeIcon() {
        for base: UInt32 in [0xFFFFFF, 0x000000, 0x808080] {
            XCTAssertEqual(AppIcons.iconName(forBase: base), "AppIcon-Gray",
                           String(format: "#%06X", base))
        }
    }

    func testCustomRefResolvesThroughTheBook() {
        let mine = CustomPalette(name: "Petrol", base: 0x0F766E)
        let resolved = AppIcons.iconName(for: .custom(mine.id), customs: [mine])
        XCTAssertEqual(resolved, AppIcons.iconName(forBase: 0x0F766E))
        XCTAssertNotNil(resolved)
        // Gelöschter Verweis: das Primär-Icon, nicht das zuletzt gesetzte.
        XCTAssertNil(AppIcons.iconName(for: .custom(UUID()), customs: [mine]))
    }

    /// Die Miniatur im Auswahlraster malt mit derselben Basis, aus der der
    /// Generator das Icon gerechnet hat — für jeden Farbton-Anker.
    func testEveryHueIconHasAChromaticBaseNearItsNominalHue() {
        for hue in AppIcons.hues {
            let deg = PaletteGenerator.hueDegrees(hue.base)
            XCTAssertNotNil(deg, hue.name)
            let dist = deg.map { min(abs($0 - Double(hue.degrees)), 360 - abs($0 - Double(hue.degrees))) }
            XCTAssertLessThanOrEqual(dist ?? 999, 12, hue.name)
        }
    }
}
