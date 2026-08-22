import XCTest
import UIKit
@testable import Haiity

/// Farbrechnung für die Tests. Bewusst hier und nicht im App-Code: die
/// Rampen werden GEGEN eine unabhängige Umsetzung der WCAG-Formel geprüft,
/// nicht gegen sich selbst.
enum Contrast {
    /// Relative Leuchtdichte nach WCAG 2.1 (sRGB).
    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ raw: UInt32) -> Double {
            let c = Double(raw) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF)
            + 0.7152 * channel((hex >> 8) & 0xFF)
            + 0.0722 * channel(hex & 0xFF)
    }

    static func ratio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

// MARK: – Rampen

/// Die drei Regeln aus Theme.swift, nachgerechnet für JEDE Palette in
/// BEIDEN Schemata. Wer eine Stufe verschiebt, bekommt hier sofort gesagt,
/// ob die Rampe noch trägt — dieselbe Prüfung, die den dunklen l0-Wert
/// überhaupt erst erzwungen hat.
final class PaletteRampTests: XCTestCase {
    /// Zwei benachbarte Stufen müssen sich unterscheiden lassen.
    private let minStep = 1.15
    /// l0 gegen die Karte: sichtbar …
    private let minEmpty = 1.10
    /// … aber leise. Eine leere Zelle darf nicht wie eine gefüllte wirken.
    private let maxEmpty = 1.85

    func testEveryPaletteHasFiveLevelsInBothSchemes() {
        for palette in GraphPalette.allCases {
            XCTAssertEqual(palette.ramp(dark: false).count, 5, "\(palette) hell")
            XCTAssertEqual(palette.ramp(dark: true).count, 5, "\(palette) dunkel")
        }
    }

    /// Hell läuft von hell nach dunkel, dunkel von dunkel nach hell —
    /// monoton, ohne Ausreißer in der Mitte.
    func testRampsAreMonotonicInPerceivedLightness() {
        for palette in GraphPalette.allCases {
            for dark in [false, true] {
                let lums = palette.ramp(dark: dark).map(Contrast.luminance)
                for i in 0..<4 {
                    if dark {
                        XCTAssertGreaterThan(lums[i + 1], lums[i],
                            "\(palette) dunkel: l\(i + 1) ist nicht heller als l\(i)")
                    } else {
                        XCTAssertLessThan(lums[i + 1], lums[i],
                            "\(palette) hell: l\(i + 1) ist nicht dunkler als l\(i)")
                    }
                }
            }
        }
    }

    func testConsecutiveLevelsAreDistinguishable() {
        for palette in GraphPalette.allCases {
            for dark in [false, true] {
                let ramp = palette.ramp(dark: dark)
                for i in 0..<4 {
                    let step = Contrast.ratio(ramp[i], ramp[i + 1])
                    XCTAssertGreaterThanOrEqual(step, minStep,
                        "\(palette) \(dark ? "dunkel" : "hell"): l\(i)→l\(i + 1) nur \(step)")
                }
            }
        }
    }

    /// Die leere Zelle muss sich von der Karte abheben — genau der Fehler,
    /// den GitHubs #161b22 im Dark Mode hatte (1,02:1 gegen #1C1C1E).
    func testEmptyCellStandsOffTheCardInBothSchemes() {
        for palette in GraphPalette.allCases {
            for dark in [false, true] {
                let l0 = palette.ramp(dark: dark)[0]
                let ratio = Contrast.ratio(l0, Theme.cardHex(dark: dark))
                XCTAssertGreaterThanOrEqual(ratio, minEmpty,
                    "\(palette) \(dark ? "dunkel" : "hell"): l0 verschwindet in der Karte (\(ratio))")
                XCTAssertLessThanOrEqual(ratio, maxEmpty,
                    "\(palette) \(dark ? "dunkel" : "hell"): l0 überstimmt die Karte (\(ratio))")
            }
        }
    }

    /// Zwei Paletten dürfen sich nicht die Rampe teilen — sonst wäre die
    /// Auswahl im Einstellungs-Chip eine Lüge.
    func testPalettesAreDistinctFromEachOther() {
        for dark in [false, true] {
            let ramps = GraphPalette.allCases.map { $0.ramp(dark: dark) }
            XCTAssertEqual(Set(ramps.map { $0.description }).count, ramps.count,
                           "identische Rampen (\(dark ? "dunkel" : "hell"))")
        }
    }

    /// Grün ist und bleibt GitHubs Original (plus der l0-Korrektur im
    /// Dark Mode) — bestehende Nutzer sehen nach dem Update exakt dasselbe.
    func testGreenIsUnchangedGitHub() {
        XCTAssertEqual(GraphPalette.green.ramp(dark: false),
                       [0xEFF2F5, 0x9BE9A8, 0x40C463, 0x30A14E, 0x216E39])
        XCTAssertEqual(GraphPalette.green.ramp(dark: true),
                       [0x262C36, 0x0E4429, 0x006D32, 0x26A641, 0x39D353])
    }

    /// Ein defekter Level-Wert darf nie einen Absturz auslösen — die
    /// Intensität kommt aus gerechneten Daten, nicht aus einer Konstante.
    func testLevelClampsOutOfRange() {
        for palette in GraphPalette.allCases {
            XCTAssertEqual(Theme.level(-3, dark: true, palette: palette),
                           Theme.level(0, dark: true, palette: palette))
            XCTAssertEqual(Theme.level(99, dark: false, palette: palette),
                           Theme.level(4, dark: false, palette: palette))
        }
    }
}

// MARK: – Akzent-Rollen

/// Die Akzentfarben tragen Text. Dieselbe Prüfung wie bei der Rampe, nur mit
/// dem Schwellenwert, der für Schrift gilt.
final class AccentContrastTests: XCTestCase {
    func testAccentFillCarriesWhiteText() {
        for palette in GraphPalette.allCases {
            let hex = palette.accentFillHex
            XCTAssertGreaterThanOrEqual(Contrast.ratio(hex.light, 0xFFFFFF), 4.5,
                                        "\(palette) accentFill hell")
            XCTAssertGreaterThanOrEqual(Contrast.ratio(hex.dark, 0xFFFFFF), 4.5,
                                        "\(palette) accentFill dunkel")
        }
    }

    func testAccentTextIsReadableOnItsBackground() {
        for palette in GraphPalette.allCases {
            let hex = palette.accentTextHex
            XCTAssertGreaterThanOrEqual(
                Contrast.ratio(hex.light, Theme.cardHex(dark: false)), 4.5,
                "\(palette) accentText hell")
            XCTAssertGreaterThanOrEqual(
                Contrast.ratio(hex.dark, Theme.cardHex(dark: true)), 4.5,
                "\(palette) accentText dunkel")
        }
    }
}

// MARK: – Auflösung Habit > global > Standard

final class PaletteResolutionTests: XCTestCase {
    func testHabitOverrideBeatsGlobal() {
        var h = Habit(name: "Lesen")
        h.palette = .violet
        XCTAssertEqual(PaletteStyle.resolve(habit: h, global: .blue), GraphPalette.violet.style)
    }

    func testHabitWithoutOverrideFollowsGlobal() {
        let h = Habit(name: "Lesen")
        XCTAssertNil(h.palette)
        XCTAssertEqual(PaletteStyle.resolve(habit: h, global: .blue), GraphPalette.blue.style)
    }

    func testFallsBackToGreenWithoutAnything() {
        XCTAssertEqual(PaletteStyle.resolve(habit: nil, global: nil), GraphPalette.green.style)
        XCTAssertEqual(PaletteStyle.resolve(habit: Habit(name: "x"), global: nil),
                       GraphPalette.green.style)
        XCTAssertEqual(GraphPalette.default, .green)
        XCTAssertEqual(PaletteRef.default, .builtin(.green))
    }

    /// Zwei Habits nebeneinander: das eine übersteuert, das andere nicht.
    /// Genau der Fall aus der Liste — und die Stelle, an der eine falsche
    /// Auflösung ALLE Karten einfärben würde.
    func testOverrideIsPerHabitNotGlobal() {
        var special = Habit(name: "Meditation")
        special.palette = .rose
        let normal = Habit(name: "Lesen")
        XCTAssertEqual(PaletteStyle.resolve(habit: special, global: .green), GraphPalette.rose.style)
        XCTAssertEqual(PaletteStyle.resolve(habit: normal, global: .green), GraphPalette.green.style)
    }
}

// MARK: – Erscheinungsbild

final class AppearanceSettingTests: XCTestCase {
    func testBackgroundImageReusesDecodedImageBetweenReads() throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let data = try XCTUnwrap(source.jpegData(compressionQuality: 0.9))
        let preferences = AppearancePreferences(material: .adaptive,
                                                 backgroundImageData: data,
                                                 backgroundMode: .image)

        let first = try XCTUnwrap(preferences.backgroundImage)
        let second = try XCTUnwrap(preferences.backgroundImage)

        XCTAssertTrue(first === second,
                      "the launch handoff should not decode the same background image repeatedly")
    }

    func testBackgroundImageCanBePrewarmedBeforeSwiftUIReadsIt() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let data = try XCTUnwrap(source.jpegData(compressionQuality: 0.9))

        await AppearanceImageCache.prewarm(data: data)
        let cached = try XCTUnwrap(AppearanceImageCache.image(for: data))
        let second = try XCTUnwrap(AppearanceImageCache.image(for: data))

        XCTAssertTrue(cached === second,
                      "startup should finish preparing the same image SwiftUI will render")
    }

    func testSystemMeansNoOverride() {
        XCTAssertNil(AppearanceSetting.system.colorScheme)
        XCTAssertEqual(AppearanceSetting.light.colorScheme, .light)
        XCTAssertEqual(AppearanceSetting.dark.colorScheme, .dark)
    }

    func testDefaultIsSystem() {
        XCTAssertEqual(AppearanceSetting.default, .system)
        XCTAssertEqual(HabitData.empty.appearance, .system)
        XCTAssertEqual(HabitData.empty.palette, .green)
        XCTAssertTrue(HabitData.empty.matchAppIcon)
    }

    func testStatsPageUsesTheSharedSettingsSurface() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Haiity/Views/StatsView.swift"))
        let statsList = try XCTUnwrap(source.range(of: "private var statsList"))
        let statsSettings = source[statsList.upperBound...]
        XCTAssertTrue(statsSettings.contains(".settingsSurface()"),
                      "the statistics page must use the same material surface as settings")
    }

    func testNonListSettingsScreensUseTheSharedMaterialChrome() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let theme = try String(contentsOf: root.appendingPathComponent("Haiity/Theme.swift"))
        let setup = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/ReminderSetupView.swift"))

        XCTAssertTrue(theme.contains("func settingsChrome()"),
                      "settings chrome needs a reusable non-list surface")
        XCTAssertTrue(setup.contains(".settingsChrome()"),
                      "the reminder setup page must follow the selected material too")
    }

    func testSettingsChromeKeepsNativeMaterialVisibleForGlassModes() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let theme = try String(contentsOf: root.appendingPathComponent("Haiity/Theme.swift"))
        let chromeStart = try XCTUnwrap(theme.range(of: "private struct SettingsChromeModifier"))
        let chrome = theme[chromeStart.lowerBound...]
        let liquidStart = try XCTUnwrap(chrome.range(of: "case .liquid:"))
        let adaptiveStart = try XCTUnwrap(chrome.range(of: "case .adaptive:",
                                                       range: liquidStart.upperBound..<chrome.endIndex))
        let liquid = chrome[liquidStart.lowerBound..<adaptiveStart.lowerBound]
        let adaptive = chrome[adaptiveStart.lowerBound...]

        XCTAssertTrue(liquid.contains(".toolbarBackground(.visible, for: .navigationBar)"),
                      "Liquid Glass settings chrome must keep a visible native header")
        XCTAssertTrue(liquid.contains(".toolbarBackground(.ultraThinMaterial, for: .navigationBar)"),
                      "Liquid Glass settings chrome must use a visible blur material")
        XCTAssertTrue(adaptive.contains(".toolbarBackground(.visible, for: .navigationBar)"),
                      "Auto settings chrome must keep a visible native header")
        XCTAssertTrue(adaptive.contains(".toolbarBackground(.regularMaterial, for: .navigationBar)"),
                      "Auto settings chrome must use a native material")
        XCTAssertFalse(liquid.contains(".toolbarBackground(.hidden, for: .navigationBar)"),
                       "the Liquid Glass header must not disappear")
    }

    func testAppearanceControlsUseStyledImageActionAndInlineDynamicIcon() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let more = try String(contentsOf: root.appendingPathComponent("Haiity/Views/MoreView.swift"))

        XCTAssertTrue(more.contains("photo.on.rectangle.angled"),
                      "the image action needs a clear photo affordance")
        XCTAssertTrue(more.contains("Bild auswählen"),
                      "the image action should name the action, not only say select")
        XCTAssertTrue(more.contains("appearance-background-picker"))
        XCTAssertTrue(more.contains("appearance-background-remove"))
        XCTAssertTrue(more.contains(".appSurface(cornerRadius: 12)"),
                      "the image action should follow the selected surface material")
        XCTAssertTrue(more.contains("HStack(alignment: .center, spacing: Theme.Metrics.gap)"),
                      "the dynamic icon control should keep its icon inline")
        XCTAssertTrue(more.contains("Image(systemName: \"app.badge\")"),
                      "the dynamic icon control should render its icon in the inline row")
    }

    func testMoreRouteDestinationsUseTheSharedSettingsSurface() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/ContentView.swift"))
        let destination = try XCTUnwrap(source.range(of: "private func moreDestination"))
        let routeBody = source[destination.upperBound...]

        XCTAssertTrue(routeBody.contains(".settingsSurface()"),
                      "every More route must inherit the selected settings material")
    }

    func testMaterialAndImagePreferencesRoundTrip() throws {
        let preferences = AppearancePreferences(material: .liquid,
                                                backgroundImageData: Data([1, 2, 3]))
        let data = HabitData(version: HabitData.currentVersion,
                             updatedAt: 1,
                             summaryMinutes: nil,
                             habits: [],
                             appearancePreferences: preferences)

        let decoded = try JSONDecoder().decode(HabitData.self,
                                                from: JSONEncoder().encode(data))

        XCTAssertEqual(decoded.appearancePreferences, preferences)
    }

    func testAdaptiveMaterialUsesLegacyCompatibleEncoding() throws {
        let preferences = AppearancePreferences(
            material: .adaptive,
            backgroundMode: .color,
            backgroundColorHex: 0x102030)

        let raw = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(preferences)) as? [String: Any])

        XCTAssertEqual(raw["material"] as? String, "solid")
        XCTAssertEqual(raw["adaptive"] as? Bool, true)
        XCTAssertEqual(try JSONDecoder().decode(AppearancePreferences.self,
                                                 from: JSONEncoder().encode(preferences)),
                       preferences)
    }

    func testUnknownMaterialFallsBackToSolid() throws {
        let raw = #"{"material":"futureMaterial","backgroundMode":"color"}"#
        let decoded = try JSONDecoder().decode(AppearancePreferences.self,
                                                from: Data(raw.utf8))

        XCTAssertEqual(decoded.material, .solid)
    }

    func testAdaptiveReferenceUsesGradientMidpoint() {
        let preferences = AppearancePreferences(
            material: .adaptive,
            backgroundMode: .gradient,
            gradientStartHex: 0xFFFFFF,
            gradientEndHex: 0x102030)

        XCTAssertEqual(Theme.adaptiveReferenceHex(preferences: preferences, dark: false),
                       0x889098)
    }

    func testAdaptivePaletteMaintainsContrastOnLightAndDarkBackgrounds() {
        let lightPreferences = AppearancePreferences(
            material: .adaptive,
            backgroundMode: .color,
            backgroundColorHex: 0xFFFFFF)
        let darkPreferences = AppearancePreferences(
            material: .adaptive,
            backgroundMode: .color,
            backgroundColorHex: 0x101114)

        for (preferences, dark) in [(lightPreferences, false), (darkPreferences, true)] {
            let palette = Theme.adaptivePalette(GraphPalette.green.style,
                                                preferences: preferences,
                                                dark: dark)
            let background = Theme.adaptiveReferenceHex(preferences: preferences, dark: dark)
            for level in palette.ramp(dark: dark) {
                XCTAssertGreaterThanOrEqual(Contrast.ratio(level, background), 1.15,
                                             "adaptive tile (String(level, radix: 16)) lacks contrast")
            }
        }
    }

    func testAppearancePickerIncludesAdaptiveMaterial() {
        XCTAssertTrue(AppearanceMaterial.allCases.contains(.adaptive))
        XCTAssertEqual(AppearanceMaterial.adaptive.displayName,
                       String(localized: "Auto"))
    }

    func testBackgroundModesAndGradientColorsRoundTrip() throws {
        let preferences = AppearancePreferences(
            material: .milky,
            backgroundMode: .gradient,
            backgroundColorHex: 0x102030,
            gradientStartHex: 0xFFFFFF,
            gradientEndHex: 0x102030)

        let data = HabitData(version: HabitData.currentVersion,
                             updatedAt: 1,
                             summaryMinutes: nil,
                             habits: [],
                             appearancePreferences: preferences)

        let decoded = try JSONDecoder().decode(HabitData.self,
                                                from: JSONEncoder().encode(data))

        XCTAssertEqual(decoded.appearancePreferences, preferences)
        XCTAssertEqual(decoded.appearancePreferences.backgroundMode, .gradient)
        XCTAssertEqual(decoded.appearancePreferences.gradientStartHex, 0xFFFFFF)
        XCTAssertEqual(decoded.appearancePreferences.gradientEndHex, 0x102030)
    }

    func testLegacyImagePreferencesInferImageMode() throws {
        let raw = #"{"material":"solid","backgroundImageData":"AQI="}"#
        let preferences = try JSONDecoder().decode(AppearancePreferences.self,
                                                    from: Data(raw.utf8))

        XCTAssertEqual(preferences.backgroundMode, .image)
        XCTAssertEqual(preferences.backgroundImageData, Data([1, 2]))
    }

    func testAppearancePreferencesRejectOversizedImageData() {
        let oversized = Data(repeating: 1, count: AppearancePreferences.maxImageBytes + 1)

        XCTAssertNil(AppearancePreferences(material: .solid,
                                            backgroundImageData: oversized).backgroundImageData)
    }

    func testNewerRemoteAppearancePreferencesReplaceLocalPreferences() {
        let local = HabitData(version: HabitData.currentVersion,
                              updatedAt: 10,
                              summaryMinutes: nil,
                              habits: [],
                              appearancePreferences: .init(material: .solid))
        let remote = HabitData(version: HabitData.currentVersion,
                               updatedAt: 20,
                               summaryMinutes: nil,
                               habits: [],
                               appearancePreferences: .init(material: .milky,
                                                            backgroundImageData: Data([4, 5])))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-appearance-(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try! JSONEncoder().encode(local).write(to: url)
        let store = HabitStore(url: url)

        store.merge(remote: remote)

        XCTAssertEqual(store.data.appearancePreferences, remote.appearancePreferences)
    }
}

// MARK: – Persistenz

/// Alte Dateien müssen unverändert laden, neue Felder tolerant fehlen dürfen
/// — dieselbe Regel wie beim Ziel-Feld aus v2.
final class ThemePersistenceTests: XCTestCase {
    private func decode(_ json: String) throws -> HabitData {
        try JSONDecoder().decode(HabitData.self, from: Data(json.utf8))
    }

    func testV1FileWithoutAnyThemeFieldsLoadsWithDefaults() throws {
        let data = try decode("""
        {"version":1,"updatedAt":1,"habits":[
          {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Lesen",
           "createdAt":"2026-01-01","log":{"2026-01-02":1}}
        ]}
        """)
        XCTAssertEqual(data.appearance, .system)
        XCTAssertEqual(data.palette, .green)
        XCTAssertTrue(data.matchAppIcon)
        XCTAssertEqual(data.habits.count, 1)
        XCTAssertNil(data.habits[0].palette)
        XCTAssertTrue(data.habits[0].isDone("2026-01-02"))
    }

    func testV2FileWithLegacyGoalButNoThemeLoadsUnchanged() throws {
        let data = try decode("""
        {"version":2,"updatedAt":2,"summaryMinutes":1200,"habits":[
          {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Wasser",
           "createdAt":"2026-01-01","log":{},"goal":{"cadence":"weekly","times":3}}
        ]}
        """)
        XCTAssertEqual(data.palette, .green)
        XCTAssertEqual(data.summaryMinutes, 1200)
        XCTAssertEqual(data.habits[0].recurrence, .times(3, per: .weekly))
        XCTAssertNil(data.habits[0].palette)
    }

    /// Eine Datei aus einer NEUEREN Version darf höchstens die Farbe
    /// verlieren, nie die Check-ins.
    func testUnknownPaletteNamesFallBackInsteadOfThrowing() throws {
        let data = try decode("""
        {"version":2,"updatedAt":3,"palette":"neon","appearance":"sepia","habits":[
          {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Lesen",
           "createdAt":"2026-01-01","log":{"2026-01-02":1},"palette":"chartreuse"}
        ]}
        """)
        XCTAssertEqual(data.palette, .green)
        XCTAssertEqual(data.appearance, .system)
        XCTAssertNil(data.habits[0].palette)
        XCTAssertTrue(data.habits[0].isDone("2026-01-02"))
    }

    func testDefaultsStayImplicitInTheFile() throws {
        var habit = Habit(name: "Lesen")
        habit.log["2026-01-02"] = 1
        let data = HabitData(version: 2, updatedAt: 1, summaryMinutes: nil, habits: [habit])
        let json = String(decoding: try JSONEncoder().encode(data), as: UTF8.self)
        XCTAssertFalse(json.contains("appearance"))
        XCTAssertFalse(json.contains("palette"))
        XCTAssertFalse(json.contains("matchAppIcon"))
    }

    func testRoundTripKeepsEveryThemeField() throws {
        var habit = Habit(name: "Meditation")
        habit.palette = .rose
        let data = HabitData(version: 2, updatedAt: 5, summaryMinutes: 900,
                             habits: [habit, Habit(name: "Lesen")],
                             appearance: .dark, palette: .amber, matchAppIcon: false)
        let raw = try JSONEncoder().encode(data)
        let back = try JSONDecoder().decode(HabitData.self, from: raw)
        XCTAssertEqual(back.appearance, .dark)
        XCTAssertEqual(back.palette, .amber)
        XCTAssertFalse(back.matchAppIcon)
        XCTAssertEqual(back.habits[0].palette, .rose)
        XCTAssertNil(back.habits[1].palette)
    }

    /// Der Weg, den die App wirklich geht: setzen -> auf Platte -> neu lesen.
    func testStorePersistsThemeAcrossLaunches() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-theme-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = HabitStore(url: url)
        var habit = Habit(name: "Meditation")
        habit.palette = .violet
        store.add(habit)
        store.appearance = .dark
        store.palette = .blue
        store.matchAppIcon = false

        let reloaded = HabitStore(url: url)
        XCTAssertEqual(reloaded.appearance, .dark)
        XCTAssertEqual(reloaded.palette, .blue)
        XCTAssertFalse(reloaded.matchAppIcon)
        XCTAssertEqual(reloaded.habits[0].palette, .violet)
        XCTAssertEqual(reloaded.palettes.style(for: reloaded.habits[0]),
                       GraphPalette.violet.style)
    }

    /// Sync: das neuere Gerät gibt die Darstellung vor, das ältere nicht.
    func testMergeAdoptsThemeOnlyFromNewerRemote() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-merge-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url)
        store.palette = .blue

        let older = HabitData(version: 2, updatedAt: 1, summaryMinutes: nil, habits: [],
                              appearance: .light, palette: .rose)
        store.merge(remote: older)
        XCTAssertEqual(store.palette, .blue, "älterer Stand darf nicht überschreiben")

        let newer = HabitData(version: 2, updatedAt: Date().timeIntervalSince1970 + 60,
                              summaryMinutes: nil, habits: [],
                              appearance: .light, palette: .rose)
        store.merge(remote: newer)
        XCTAssertEqual(store.palette, .rose)
        XCTAssertEqual(store.appearance, .light)
    }

    /// Eine Habit-Farbe vom anderen Gerät ist Metadaten — sie folgt derselben
    /// „neuerer Stand gewinnt"-Regel wie Name und Ziel.
    func testMergeCarriesHabitPalette() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-merge2-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url)
        let habit = Habit(name: "Lesen")
        store.add(habit)

        var remoteHabit = habit
        remoteHabit.palette = .amber
        store.merge(remote: HabitData(version: 2,
                                      updatedAt: Date().timeIntervalSince1970 + 60,
                                      summaryMinutes: nil, habits: [remoteHabit]))
        XCTAssertEqual(store.habits[0].palette, .amber)
    }
}

// MARK: – Alternative App-Icons

final class AppIconTests: XCTestCase {
    func testGreenUsesThePrimaryIcon() {
        XCTAssertNil(AppIcons.name(for: .green))
    }

    func testEveryOtherPaletteHasItsOwnIcon() {
        let names = GraphPalette.allCases.compactMap { AppIcons.name(for: $0) }
        XCTAssertEqual(names.count, GraphPalette.allCases.count - 1)
        XCTAssertEqual(Set(names).count, names.count, "doppelte Icon-Namen")
        // Die Alternates sind Paletten-Icons PLUS die zwölf Farbton-Icons.
        XCTAssertEqual(Set(AppIcons.alternateNames),
                       Set(names).union(AppIcons.hues.map(\.name)))
        XCTAssertEqual(AppIcons.alternateNames.count, 17, "5 Paletten + 12 Farbtöne")
    }

    /// Der eigentliche Nachweis: actool hat die Icons wirklich ins Bundle
    /// geschrieben. Ein Tippfehler im Katalognamen oder eine fehlende
    /// Eintragung in project.yml fällt hier auf — nicht erst als
    /// stillschweigend fehlgeschlagener Icon-Wechsel auf dem Gerät.
    func testAlternateIconsAreDeclaredInTheBundle() throws {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any] else {
            throw XCTSkip("Test läuft ohne Host-App — kein Bundle zum Prüfen.")
        }
        let alternates = icons["CFBundleAlternateIcons"] as? [String: Any]
        for name in AppIcons.alternateNames {
            XCTAssertNotNil(alternates?[name], "\(name) fehlt in CFBundleAlternateIcons")
        }
    }
}
