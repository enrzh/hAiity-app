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
    private func validImageData() throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }

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
        let prepared = try XCTUnwrap(AppearanceImageCache.cachedImage(for: data))
        let second = try XCTUnwrap(AppearanceImageCache.image(for: data))

        XCTAssertTrue(cached === prepared,
                      "the background view must be able to read a prepared image without decoding")
        XCTAssertTrue(cached === second,
                      "startup should finish preparing the same image SwiftUI will render")
    }

    func testLaunchPrewarmDoesNotSpinDetachedDecodeWork() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let theme = try String(contentsOf: root.appendingPathComponent("Haiity/Theme.swift"))
        let start = try XCTUnwrap(theme.range(of: "private actor InFlightStore"))
        let end = try XCTUnwrap(theme.range(of: "private static func decodedImage",
                                            range: start.upperBound..<theme.endIndex))
        let cache = theme[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(cache.contains("guard !Task.isCancelled else { return nil }"),
                      "canceling shared work must stop the actual decode worker before rendering")
        XCTAssertTrue(cache.contains("withTaskCancellationHandler"),
                      "prewarm waiters should release shared work when launch is canceled")
    }

    func testSelectingNonImageModeRemovesTheStoredImage() throws {
        let imageData = try validImageData()
        var preferences = AppearancePreferences(backgroundImageData: imageData,
                                                 backgroundMode: .image)

        preferences.selectBackgroundMode(.gradient)

        XCTAssertEqual(preferences.backgroundMode, .gradient)
        XCTAssertNil(preferences.backgroundImageData)
    }

    func testRemovingTheBackgroundImageIsAnExplicitDestructiveAction() throws {
        var preferences = AppearancePreferences(backgroundImageData: try validImageData(),
                                                 backgroundMode: .image)

        preferences.removeBackgroundImage()

        XCTAssertEqual(preferences.backgroundMode, .color)
        XCTAssertNil(preferences.backgroundImageData)
    }

    func testSelectingImageModeWithoutAnImageKeepsThePickerMode() {
        var preferences = AppearancePreferences(backgroundMode: .color)

        preferences.selectBackgroundMode(.image)

        XCTAssertEqual(preferences.backgroundMode, .image)
        XCTAssertNil(preferences.backgroundImageData)
    }

    func testInstallingAnImageChangesModeAndPayloadAtomically() throws {
        var preferences = AppearancePreferences(backgroundMode: .color)

        XCTAssertTrue(preferences.setBackgroundImage(try validImageData()))

        XCTAssertEqual(preferences.backgroundMode, .image)
        XCTAssertNotNil(preferences.backgroundImageData)
    }

    func testInstallingInvalidImageLeavesTheExistingBackgroundUntouched() {
        var preferences = AppearancePreferences(backgroundMode: .gradient,
                                                 gradientStartHex: 0x112233,
                                                 gradientEndHex: 0x445566)

        XCTAssertFalse(preferences.setBackgroundImage(Data([1, 2, 3])))

        XCTAssertEqual(preferences.backgroundMode, .gradient)
        XCTAssertEqual(preferences.gradientStartHex, 0x112233)
        XCTAssertEqual(preferences.gradientEndHex, 0x445566)
        XCTAssertNil(preferences.backgroundImageData)
    }

    func testDecodedColorModeDropsStaleImageData() throws {
        let raw = Data(#"{"material":"solid","backgroundMode":"color","backgroundImageData":"AQID"}"#.utf8)

        let preferences = try JSONDecoder().decode(AppearancePreferences.self, from: raw)

        XCTAssertEqual(preferences.backgroundMode, .color)
        XCTAssertNil(preferences.backgroundImageData)
    }

    func testDecodedColorModeDropsAValidStaleImage() throws {
        let imageData = try validImageData()
        let raw = try JSONSerialization.data(withJSONObject: [
            "material": "solid",
            "backgroundMode": "color",
            "backgroundImageData": imageData.base64EncodedString()
        ])

        let preferences = try JSONDecoder().decode(AppearancePreferences.self, from: raw)

        XCTAssertEqual(preferences.backgroundMode, .color)
        XCTAssertNil(preferences.backgroundImageData)
    }

    func testDecodedImageModeWithoutImageKeepsThePickerMode() throws {
        let raw = Data(#"{"material":"solid","backgroundMode":"image"}"#.utf8)

        let preferences = try JSONDecoder().decode(AppearancePreferences.self, from: raw)

        XCTAssertEqual(preferences.backgroundMode, .image)
        XCTAssertNil(preferences.backgroundImageData)
    }

    func testInvalidImagePayloadNormalizesToAnEmptyImageModeBeforeStorage() {
        let preferences = AppearancePreferences(
            material: .liquid,
            backgroundImageData: Data([1, 2, 3]),
            backgroundMode: .image,
            backgroundColorHex: 0x112233)

        let normalized = preferences.normalizedForStorage()

        XCTAssertEqual(normalized.material, .liquid)
        XCTAssertEqual(normalized.backgroundMode, .image)
        XCTAssertEqual(normalized.backgroundColorHex, 0x112233)
        XCTAssertNil(normalized.backgroundImageData)
    }

    func testStoreSetterNormalizesStaleImageMode() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-background-normalize-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = HabitStore(url: url)
        store.appearancePreferences = AppearancePreferences(
            backgroundImageData: Data([1, 2, 3]),
            backgroundMode: .image)

        XCTAssertEqual(store.appearancePreferences.backgroundMode, .image)
        XCTAssertNil(store.appearancePreferences.backgroundImageData)
        XCTAssertEqual(HabitStore(url: url).appearancePreferences.backgroundMode, .image)
    }

    func testMergeNormalizesRemoteImageModeBeforeApplyingIt() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-background-merge-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = HabitStore(url: url)
        let remote = HabitData(version: HabitData.currentVersion,
                               updatedAt: 20,
                               summaryMinutes: nil,
                               habits: [],
                               appearanceUpdatedAt: 20,
                               appearancePreferences: AppearancePreferences(
                                   backgroundImageData: Data([1, 2, 3]),
                                   backgroundMode: .image))

        store.merge(remote: remote)

        XCTAssertEqual(store.appearancePreferences.backgroundMode, .image)
        XCTAssertNil(store.appearancePreferences.backgroundImageData)
    }

    func testStoreResetBackgroundClearsEveryBackgroundValueAndPersists() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-background-reset-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url)
        store.appearancePreferences = AppearancePreferences(
            material: .adaptive,
            backgroundImageData: try validImageData(),
            backgroundMode: .image,
            backgroundColorHex: 0x112233,
            gradientStartHex: 0x445566,
            gradientEndHex: 0x778899)

        store.resetBackground()

        let saved = HabitStore(url: url).appearancePreferences
        XCTAssertEqual(saved.material, .adaptive)
        XCTAssertEqual(saved.backgroundMode, .color)
        XCTAssertNil(saved.backgroundImageData)
        XCTAssertNil(saved.backgroundColorHex)
        XCTAssertNil(saved.gradientStartHex)
        XCTAssertNil(saved.gradientEndHex)
    }

    func testImagePickerIsMountedOnlyForImageMode() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Views/MoreView.swift"))
        let control = try XCTUnwrap(source.range(of: "private var backgroundControl"))
        let end = try XCTUnwrap(source.range(of: "private var backgroundModeSelector",
                                             range: control.upperBound..<source.endIndex))
        let body = source[control.lowerBound..<end.lowerBound]

        XCTAssertEqual(body.components(separatedBy: "backgroundImagePicker").count - 1, 1)
        XCTAssertFalse(body.contains("backgroundMode != .image"))
    }

    func testPaletteRowsExposeAnExplicitRoundSelectionControl() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Views/PalettePicker.swift"))

        XCTAssertTrue(source.contains("checkmark.circle.fill"))
        XCTAssertTrue(source.contains("selected ? \"checkmark.circle.fill\" : \"circle\""))
    }

    func testStoreRemoveBackgroundImagePersistsAnExplicitRemoval() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-background-remove-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = HabitStore(url: url)
        store.appearancePreferences = AppearancePreferences(
            backgroundImageData: try validImageData(),
            backgroundMode: .image)

        store.removeBackgroundImage()

        let saved = HabitStore(url: url).appearancePreferences
        XCTAssertEqual(saved.backgroundMode, .color)
        XCTAssertNil(saved.backgroundImageData)
        XCTAssertNotNil(saved.backgroundResetAt)
    }

    func testModeSelectorTreatsOnlyValidatedImageDataAsExisting() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let more = try String(contentsOf: root.appendingPathComponent("Haiity/Views/MoreView.swift"))

        XCTAssertTrue(more.contains("hasPersistedBackgroundImage"),
                      "image mode must show the picker and removal action only for persisted image data")
        XCTAssertTrue(more.contains("store.removeBackgroundImage()"),
                      "the visible delete action must use the explicit removal path")
    }

    func testDeveloperPageOffersTheForceBackgroundReset() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Haiity/Views/DeveloperView.swift"))

        XCTAssertTrue(source.contains("store.resetBackground()"))
        XCTAssertTrue(source.contains("\"reset-background\""))
        XCTAssertTrue(source.contains("store.removeBackgroundImage()"))
        XCTAssertTrue(source.contains("\"force-remove-background-image\""))
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

    func testStatsPageUsesClearSectionsAndIndividualCardSurfaces() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Haiity/Views/StatsView.swift"))
        let statsList = try XCTUnwrap(source.range(of: "private var statsList"))
        let statsSettings = source[statsList.upperBound...]
        let statsListEnd = try XCTUnwrap(statsSettings.range(of: "private var statsSelectionEmpty"))
        let list = statsSettings[..<statsListEnd.lowerBound]
        XCTAssertTrue(list.contains(".listRowBackground(Color.clear)"),
                      "the stats list must keep its sections clear behind individual cards")
        XCTAssertTrue(list.contains(".appSurface()"),
                      "each stats card must own its selected appearance surface")
        XCTAssertFalse(list.contains(".settingsListRow()"),
                       "a section-wide surface creates a second background behind held cards")
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
        XCTAssertTrue(theme.contains("listRowSpacing(Theme.Metrics.settingsRowGap)"),
                      "settings rows need a shared gap instead of a squished glass stack")
        XCTAssertTrue(theme.contains("listSectionSpacing(Theme.Metrics.settingsSectionGap)"),
                      "settings groups need shared breathing room")
        XCTAssertTrue(setup.contains(".settingsChrome()"),
                      "the reminder setup page must follow the selected material too")
    }

    func testSettingsMaterialUsesAStableDynamicTypeSafeRowMinimum() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let theme = try String(contentsOf: root.appendingPathComponent("Haiity/Theme.swift"))

        XCTAssertTrue(theme.contains("settingsRowMinHeight"),
                      "settings need one shared minimum row height")
        XCTAssertTrue(theme.contains("environment(\\.defaultMinListRowHeight, Theme.Metrics.settingsRowMinHeight)"),
                      "native lists must keep rows readable without fixing their height")
    }

    func testAppearanceAndSetupLabelsHaveEnglishCatalogEntries() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Localizable.xcstrings"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        let keys = [
            "Solid", "Milchglas", "Liquid Glass", "Bild auswählen", "Verlauf", "Bild",
            "Farbton", "Deckende Flächen in einer ruhigen Farbe.",
            "Milchig getönte Flächen, die den Hintergrund erahnen.",
            "Echtes Liquid Glass mit Tiefenwirkung (ab iOS 26, sonst Milchglas).",
            "Passt Fläche und Kontrast automatisch an deinen Hintergrund an.",
            "Wähle deine Zusammenfassungen.", "Erledigt und offen.",
            "Deine Woche in Zahlen.", "Berechtigungen aktivieren"
        ]

        for key in keys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
            let english = try XCTUnwrap(localizations["en"] as? [String: Any], key)
            let unit = try XCTUnwrap(english["stringUnit"] as? [String: Any], key)
            XCTAssertEqual(unit["state"] as? String, "translated", key)
            XCTAssertFalse((unit["value"] as? String ?? "").isEmpty, key)
        }
    }

    func testSettingsChromeLeavesNavigationBarMaterialToTheSystem() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let theme = try String(contentsOf: root.appendingPathComponent("Haiity/Theme.swift"))
        let chromeStart = try XCTUnwrap(theme.range(of: "private struct SettingsChromeModifier"))
        let chrome = theme[chromeStart.lowerBound...]

        XCTAssertTrue(chrome.contains("AppearanceBackground(preferences: preferences)"))
        XCTAssertFalse(chrome.contains("toolbarBackground(.visible"),
                       "settings chrome must not force a separate header band")
        XCTAssertFalse(chrome.contains("toolbarBackground(Color("),
                       "settings chrome must not replace the native header material")
        XCTAssertFalse(chrome.contains("toolbarBackground(.regularMaterial"),
                       "settings chrome must not own the blur material")
        XCTAssertFalse(chrome.contains("toolbarBackground(.ultraThinMaterial"),
                       "settings chrome must not own the blur material")
    }

    func testNavigationRootsUseOneAppearanceAwareMaterialChrome() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let theme = try String(contentsOf: root.appendingPathComponent("Haiity/Theme.swift"))
        let content = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/ContentView.swift"))

        XCTAssertTrue(theme.contains("func navigationChrome()"))
        XCTAssertTrue(theme.contains("private struct NavigationChromeModifier"))
        XCTAssertTrue(theme.contains("toolbarBackground(.ultraThinMaterial"),
                      "liquid navigation chrome must remain blurred")
        XCTAssertTrue(content.contains(".navigationChrome()"),
                      "all root navigation stacks must use the shared chrome")
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
        let imagePickerStart = try XCTUnwrap(more.range(of: "private var backgroundImagePicker: some View"))
        let imagePickerEnd = try XCTUnwrap(more.range(of: "private func importBackgroundImage",
                                                       range: imagePickerStart.upperBound..<more.endIndex))
        let picker = more[imagePickerStart.lowerBound..<imagePickerEnd.lowerBound]
        XCTAssertFalse(picker.contains(".appSurface("),
                       "PhotosPicker must not own a hit-sensitive material modifier")
        XCTAssertTrue(more.contains("PhotosPicker(selection: $pickedBackgroundItem"),
                      "image selection must use the native PhotosUI control")
        XCTAssertTrue(picker.contains("PhotosPicker("),
                      "the image action should be a direct native picker control")
        let removeStart = try XCTUnwrap(more.range(of: "Button(role: .destructive)"))
        let removeEnd = try XCTUnwrap(more.range(of: ".accessibilityIdentifier(\"appearance-background-remove\")",
                                                  range: removeStart.upperBound..<more.endIndex))
        let remove = more[removeStart.lowerBound..<removeEnd.upperBound]
        XCTAssertTrue(remove.contains(".buttonStyle(.plain)"),
                      "the image removal action must use a native hit-testable plain button")
        XCTAssertFalse(remove.contains(".buttonStyle(.bordered)"),
                       "a bordered button is not reliable inside this iOS 27 list row")
        XCTAssertTrue(more.contains("HStack(alignment: .center, spacing: Theme.Metrics.gap)"),
                      "the dynamic icon control should keep its icon inline")
        XCTAssertTrue(more.contains("Image(systemName: \"app.badge\")"),
                      "the dynamic icon control should render its icon in the inline row")
    }

    func testAppearanceEditorUsesAHitTestableScrollContainer() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let more = try String(contentsOf: root.appendingPathComponent("Haiity/Views/MoreView.swift"))
        let start = try XCTUnwrap(more.range(of: "private var appearanceSettings: some View"))
        let end = try XCTUnwrap(more.range(of: "private var habitBehaviorSettings: some View",
                                           range: start.upperBound..<more.endIndex))
        let appearance = more[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(appearance.contains("ScrollView"),
                      "appearance controls must live in a native scroll container")
        XCTAssertFalse(appearance.contains("List {"),
                       "iOS 27 List presentation currently drops taps for this editor")
    }

    func testAppearanceBackgroundEditorUsesNativeControls() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let more = try String(contentsOf: root.appendingPathComponent("Haiity/Views/MoreView.swift"))

        let backgroundStart = try XCTUnwrap(more.range(of: "private var backgroundControl: some View"))
        let backgroundEnd = try XCTUnwrap(more.range(of: "private func backgroundSymbol",
                                                     range: backgroundStart.upperBound..<more.endIndex))
        let background = more[backgroundStart.lowerBound..<backgroundEnd.lowerBound]
        XCTAssertTrue(background.contains("backgroundModeSelector"),
                      "background modes need a dedicated selector on iOS 27")
        XCTAssertTrue(background.contains("Picker(selection: backgroundModeBinding"),
                      "background modes must use a native picker hit target")
        XCTAssertFalse(more.contains("showingBackgroundPhotoPicker"),
                       "the fragile custom sheet state must not remain")
        XCTAssertFalse(more.contains("private func backgroundModeButton"),
                       "the custom mode buttons must not remain")
        XCTAssertTrue(more.contains("\"appearance-background-mode-picker\""),
                      "the native picker needs one stable test target")

        let imageStart = try XCTUnwrap(more.range(of: "private var backgroundImagePicker: some View"))
        let imageEnd = try XCTUnwrap(more.range(of: "private func importBackgroundImage",
                                                range: imageStart.upperBound..<more.endIndex))
        let imagePicker = more[imageStart.lowerBound..<imageEnd.lowerBound]
        XCTAssertTrue(imagePicker.contains("PhotosPicker(selection: $pickedBackgroundItem"),
                      "the image action must have a direct native picker hit target")
        XCTAssertFalse(more.contains("PHPickerViewController"),
                       "the custom UIKit picker path must not remain")
    }

    func testBackgroundPickerUsesOneAsyncImportPath() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let more = try String(contentsOf: root.appendingPathComponent("Haiity/Views/MoreView.swift"))

        XCTAssertTrue(more.contains("loadTransferable(type: Data.self)"),
                      "the native picker must load one transferable payload")
        XCTAssertTrue(more.contains("importBackgroundImage(data)"),
                      "the native picker must share the existing normalization path")
        XCTAssertTrue(more.contains("backgroundImageImportToken"),
                      "a canceled or replaced selection must invalidate stale work")
    }

    func testBackgroundImageActionsUsePersistedImageData() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let more = try String(contentsOf: root.appendingPathComponent("Haiity/Views/MoreView.swift"))

        XCTAssertTrue(more.contains("backgroundImageData != nil"),
                      "a corrupt but persisted image must remain removable")
        XCTAssertTrue(more.contains("removeBackgroundImage()"),
                      "only the explicit remove action may clear image state")
    }

    func testBackgroundPickerDoesNotRetainASecondUIKitCoordinator() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let more = try String(contentsOf: root.appendingPathComponent("Haiity/Views/MoreView.swift"))

        XCTAssertFalse(more.contains("final class Coordinator: NSObject, PHPickerViewControllerDelegate"),
                       "the native SwiftUI picker owns its lifecycle")
        XCTAssertTrue(more.contains("pickedBackgroundItem"),
                      "the selection must be retained by the view state")
    }

    func testBackgroundPickerFallsBackForCloudAndNonCurrentRepresentations() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let more = try String(contentsOf: root.appendingPathComponent("Haiity/Views/MoreView.swift"))

        XCTAssertTrue(more.contains("PhotosPicker(selection: $pickedBackgroundItem"),
                      "PhotosPicker handles iCloud-backed asset representations")
        XCTAssertTrue(more.contains("loadTransferable(type: Data.self)"),
                      "the picker must load the selected asset asynchronously")
    }

    func testMoreViewDoesNotUseStaleEquatableIdentityForAppearanceChanges() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let more = try String(contentsOf: root.appendingPathComponent("Haiity/Views/MoreView.swift"))

        XCTAssertFalse(more.contains("struct MoreView: View, Equatable"),
                       "appearance changes must invalidate the settings editor")
    }

    func testMoreAndBehaviorPagesUseSharedMaterialSurface() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let more = try String(contentsOf: root.appendingPathComponent("Haiity/Views/MoreView.swift"))
        let mainStart = try XCTUnwrap(more.range(of: "private var mainSettings: some View"))
        let behaviorStart = try XCTUnwrap(more.range(of: "private var habitBehaviorSettings: some View"))
        let timezoneStart = try XCTUnwrap(more.range(of: "private var timeZoneSettings: some View"))

        XCTAssertTrue(more[mainStart.lowerBound..<behaviorStart.lowerBound].contains(".settingsSurface()"))
        XCTAssertTrue(more[behaviorStart.lowerBound..<timezoneStart.lowerBound].contains(".settingsSurface()"))
    }

    func testTaskOneSharedSettingsSurfaceContractIsAppliedToMoreAndPicker() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let theme = try String(contentsOf: root.appendingPathComponent("Haiity/Theme.swift"))
        let more = try String(contentsOf: root.appendingPathComponent("Haiity/Views/MoreView.swift"))
        let picker = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/MaterialPreviewPicker.swift"))

        XCTAssertTrue(theme.contains("AppearanceBackground(preferences: appearancePreferences)"),
                      "the shared settings chrome must render the environment appearance background")
        XCTAssertTrue(theme.contains("func settingsRowSurface()"),
                      "settings rows need one reusable material-aware surface entry point")
        XCTAssertTrue(more.contains(".settingsRowSurface()"),
                      "More subpages must apply the shared row surface")
        XCTAssertTrue(picker.contains(".settingsRowSurface()"),
                      "material previews must use the same row surface treatment")
    }

    func testAppearanceEditorsNeverDecodeBackgroundImagesDuringBodyEvaluation() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let more = try String(contentsOf: root.appendingPathComponent("Haiity/Views/MoreView.swift"))
        let picker = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/MaterialPreviewPicker.swift"))

        XCTAssertFalse(more.contains("store.appearancePreferences.backgroundImage"),
                       "the settings editor must use the prepared image cache")
        XCTAssertFalse(picker.contains("preferences.backgroundImage"),
                       "material previews must not decode image data in body")
        XCTAssertTrue(more.contains("AppearanceCachedImage"),
                      "the appearance editor needs an asynchronous cached image view")
        XCTAssertTrue(picker.contains("AppearanceCachedImage"),
                      "material previews need the same asynchronous cached image view")
    }

    func testSettingsSurfaceKeepsListRowBackgroundNonInteractive() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let theme = try String(contentsOf: root.appendingPathComponent("Haiity/Theme.swift"))

        XCTAssertTrue(theme.contains("SettingsRowSurface"),
                      "settings lists need one shared appearance-aware row surface")
        XCTAssertTrue(theme.contains("SettingsRowSurface()"),
                      "the row surface must be installed through the shared modifier")
        XCTAssertTrue(theme.contains(".allowsHitTesting(false)"),
                      "the row surface must stay behind native controls")
    }

    func testSettingsSurfaceAppliesTheSelectedMaterialWithoutBlockingRows() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let theme = try String(contentsOf: root.appendingPathComponent("Haiity/Theme.swift"))

        XCTAssertTrue(theme.contains("settingsRowBackground"),
                      "native settings rows need an appearance-aware background")
        XCTAssertTrue(theme.contains("listRowBackground(settingsRowBackground)"),
                      "the row surface must be applied through List's native background hook")
        XCTAssertTrue(theme.contains("allowsHitTesting(false)"),
                      "material backgrounds must never steal taps from controls")
        XCTAssertTrue(theme.contains("case .liquid"),
                      "Liquid Glass needs a settings-row treatment, not only a page background")
    }

    func testAppearanceBackgroundDoesNotCaptureControlTouches() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let theme = try String(contentsOf: root.appendingPathComponent("Haiity/Theme.swift"))
        let background = try XCTUnwrap(theme.range(of: "struct AppearanceBackground: View"))
        let end = try XCTUnwrap(theme.range(of: "private struct AppSurfaceModifier"))
        let body = theme[background.upperBound..<end.lowerBound]

        XCTAssertTrue(body.contains(".allowsHitTesting(false)"),
                      "the full-screen appearance background must stay behind settings controls")
    }

    func testAppSurfaceDecorationsDoNotCaptureControlTouches() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let theme = try String(contentsOf: root.appendingPathComponent("Haiity/Theme.swift"))
        let surface = try XCTUnwrap(theme.range(of: "private struct AppSurfaceModifier: ViewModifier"))
        let end = try XCTUnwrap(theme.range(of: "private struct SettingsSurfaceModifier",
                                             range: surface.upperBound..<theme.endIndex))
        let body = theme[surface.upperBound..<end.lowerBound]

        XCTAssertTrue(body.contains("allowsHitTesting(false)"),
                      "material fills and overlays must never sit above interactive content")
    }

    func testIOS26GlassSurfaceIsRenderedBehindInteractiveContent() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let theme = try String(contentsOf: root.appendingPathComponent("Haiity/Theme.swift"))
        let surface = try XCTUnwrap(theme.range(of: "private struct AppSurfaceModifier: ViewModifier"))
        let end = try XCTUnwrap(theme.range(of: "private struct SettingsSurfaceModifier",
                                             range: surface.upperBound..<theme.endIndex))
        let body = theme[surface.upperBound..<end.lowerBound]

        XCTAssertFalse(body.contains("content.glassEffect("),
                       "iOS 26 glass must not wrap interactive control content directly")
        XCTAssertTrue(body.contains(".background {"),
                      "iOS 26 glass should be a non-interactive background decoration")
    }

    func testSettingsSurfaceDoesNotInstallAHitCapturingListRowBackground() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let theme = try String(contentsOf: root.appendingPathComponent("Haiity/Theme.swift"))
        let settings = try XCTUnwrap(theme.range(of: "private struct SettingsSurfaceModifier"))
        let end = try XCTUnwrap(theme.range(of: "private struct SettingsChromeModifier",
                                             range: settings.upperBound..<theme.endIndex))
        let body = theme[settings.upperBound..<end.lowerBound]

        XCTAssertFalse(body.contains("listRowBackground(SettingsRowSurface"),
                       "custom list row backgrounds can intercept native control taps on iOS 27")
    }

    func testLargeValidBackgroundImageIsCompressedInsteadOfRejected() throws {
        let width = 1600
        let height = 1600
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        var state: UInt32 = 0x12345678
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            state = state &* 1664525 &+ 1013904223
            bytes[offset] = UInt8(truncatingIfNeeded: state >> 24)
            state = state &* 1664525 &+ 1013904223
            bytes[offset + 1] = UInt8(truncatingIfNeeded: state >> 24)
            state = state &* 1664525 &+ 1013904223
            bytes[offset + 2] = UInt8(truncatingIfNeeded: state >> 24)
            bytes[offset + 3] = 255
        }

        let source: UIImage = try bytes.withUnsafeMutableBytes { raw in
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let context = try XCTUnwrap(CGContext(data: raw.baseAddress,
                                                   width: width,
                                                   height: height,
                                                   bitsPerComponent: 8,
                                                   bytesPerRow: width * 4,
                                                   space: colorSpace,
                                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let cgImage = try XCTUnwrap(context.makeImage())
            return UIImage(cgImage: cgImage)
        }
        let sourceData = try XCTUnwrap(source.jpegData(compressionQuality: 1))
        let normalized = AppearanceImage.normalizedData(sourceData)

        XCTAssertNotNil(normalized, "a valid photo should be retried at a smaller size or quality")
        XCTAssertLessThanOrEqual(normalized?.count ?? .max, AppearancePreferences.maxImageBytes)
    }

    func testMoreRouteDestinationsDoNotWrapTheirOwnSettingsSurface() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/ContentView.swift"))
        let destination = try XCTUnwrap(source.range(of: "private func moreDestination"))
        let end = try XCTUnwrap(source.range(of: "// MARK: – Schütteln meldet einen Fehler",
                                             range: destination.upperBound..<source.endIndex))
        let routeBody = source[destination.upperBound..<end.lowerBound]

        XCTAssertFalse(routeBody.contains(".settingsSurface()"),
                       "More destinations own their settings surface; an outer list wrapper can capture native control touches")
    }

    func testMaterialAndImagePreferencesRoundTrip() throws {
        let imageData = try validImageData()
        let preferences = AppearancePreferences(material: .liquid,
                                                backgroundImageData: imageData)
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

    func testBottomChromeResolvesTheSelectedSurfaceMaterial() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Views/ContentView.swift"))
        let start = try XCTUnwrap(content.range(of: "private struct ChromeGlass"))
        let end = try XCTUnwrap(content.range(of: "/// Schwebende Pillen",
                                              range: start.upperBound..<content.endIndex))
        let chrome = content[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(chrome.contains("case .solid:"),
                      "the bottom chrome must have an opaque material path")
        XCTAssertTrue(chrome.contains("case .milky:"),
                      "the bottom chrome must have a milky material path")
        XCTAssertTrue(chrome.contains("case .liquid:"),
                      "the bottom chrome must have a Liquid Glass path")
        XCTAssertTrue(chrome.contains("case .adaptive:"),
                      "the bottom chrome must have an adaptive material path")
        XCTAssertTrue(chrome.contains("@Environment(\\.appearancePreferences)"),
                      "the bottom chrome must read the shared appearance setting")
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
        let imageData = try validImageData()
        let raw = try JSONSerialization.data(withJSONObject: [
            "material": "solid",
            "backgroundImageData": imageData.base64EncodedString()
        ])
        let preferences = try JSONDecoder().decode(AppearancePreferences.self,
                                                    from: raw)

        XCTAssertEqual(preferences.backgroundMode, .image)
        XCTAssertEqual(preferences.backgroundImageData, imageData)
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
                                                            backgroundImageData: try! validImageData()))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-appearance-(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try! JSONEncoder().encode(local).write(to: url)
        let store = HabitStore(url: url)

        store.merge(remote: remote)

        XCTAssertEqual(store.data.appearancePreferences, remote.appearancePreferences)
    }

    func testBackgroundResetTombstoneBlocksAnOlderRemoteImage() throws {
        let local = HabitData(version: HabitData.currentVersion,
                              updatedAt: 10,
                              summaryMinutes: nil,
                              habits: [],
                              appearanceUpdatedAt: 10,
                              appearancePreferences: .init(material: .milky,
                                                            backgroundMode: .color))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(local)) as? [String: Any])
        var appearance = try XCTUnwrap(object["appearancePreferences"] as? [String: Any])
        appearance["backgroundResetAt"] = 15.0
        object["appearancePreferences"] = appearance

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-background-reset-merge-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        let store = HabitStore(url: url)
        let remote = HabitData(version: HabitData.currentVersion,
                               updatedAt: 100,
                               summaryMinutes: nil,
                               habits: [],
                               appearanceUpdatedAt: 14,
                               appearancePreferences: .init(
                                   material: .milky,
                                   backgroundImageData: try validImageData(),
                                   backgroundMode: .image))

        store.merge(remote: remote)

        XCTAssertEqual(store.appearancePreferences.backgroundMode, .color)
        XCTAssertNil(store.appearancePreferences.backgroundImageData)
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
                              appearanceUpdatedAt: Date().timeIntervalSince1970 + 60,
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
