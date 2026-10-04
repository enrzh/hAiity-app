import XCTest
@testable import Haiity

final class DesignStyleTests: XCTestCase {
    func testLegacyAndUnknownStylesDecodeAsOriginalWithoutResettingAppearance() throws {
        for style in [nil, "a-future-style"] as [String?] {
            var object: [String: Any] = ["material": "milky", "backgroundMode": "gradient",
                                        "gradientStartHex": 0x123456, "gradientEndHex": 0x654321,
                                        "performanceMode": true]
            if let style { object["designStyle"] = style }
            let preferences = try JSONDecoder().decode(AppearancePreferences.self,
                                                        from: JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(preferences.designStyle, .native)
            XCTAssertEqual(preferences.material, .milky)
            XCTAssertEqual(preferences.backgroundMode, .gradient)
            XCTAssertEqual(preferences.gradientStartHex, 0x123456)
            XCTAssertEqual(preferences.gradientEndHex, 0x654321)
            XCTAssertTrue(preferences.performanceMode)
        }
    }

    func testEveryStyleRoundTripsWithoutChangingCustomization() throws {
        var preferences = AppearancePreferences(material: .adaptive, backgroundMode: .gradient,
                                                gradientStartHex: 0x123456, gradientEndHex: 0x654321,
                                                performanceMode: true)
        for style in AppDesignStyle.allCases {
            preferences.designStyle = style
            let decoded = try JSONDecoder().decode(AppearancePreferences.self,
                                                     from: JSONEncoder().encode(preferences))
            XCTAssertEqual(decoded, preferences)
            XCTAssertEqual(decoded.normalizedForStorage().designStyle, style)
            var changedMaterial = decoded
            changedMaterial.material = .liquid
            XCTAssertEqual(changedMaterial.designStyle, style)
            XCTAssertEqual(changedMaterial.gradientStartHex, preferences.gradientStartHex)
        }
    }

    func testSavingAndReloadingAStyleKeepsHabitDataAndColors() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("design-style-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url)
        var habit = Habit(name: "Read")
        habit.log["2026-10-04"] = 1
        store.add(habit)
        store.palette = .rose
        let habits = store.habits
        for style in AppDesignStyle.allCases {
            var preferences = store.appearancePreferences
            preferences.designStyle = style
            store.appearancePreferences = preferences
            try store.requireSuccessfulWrite()
            let reloaded = HabitStore(url: url)
            XCTAssertEqual(reloaded.appearancePreferences.designStyle, style)
            XCTAssertEqual(reloaded.habits, habits)
            XCTAssertEqual(reloaded.palette, .rose)
        }
    }

    func testStylesPreserveMinimumControlTargetsAndSpecialShapes() {
        XCTAssertEqual(AppDesignStyle.native.settingsRowHeight, Theme.Metrics.settingsRowMinHeight)
        XCTAssertEqual(AppDesignStyle.native.rowGap, Theme.Metrics.settingsRowGap)
        XCTAssertEqual(AppDesignStyle.native.sectionGap, Theme.Metrics.settingsSectionGap)
        for style in AppDesignStyle.allCases {
            XCTAssertGreaterThanOrEqual(style.settingsRowHeight, 44)
            XCTAssertGreaterThanOrEqual(style.graphPadding, 4)
            XCTAssertEqual(style.radius(for: 999), 999, "floating capsules keep their shape")
            XCTAssertEqual(style.radius(for: 2), 2, "graph pixels keep their shape")
        }
        XCTAssertLessThan(AppDesignStyle.focus.sectionGap, AppDesignStyle.native.sectionGap)
        XCTAssertLessThan(AppDesignStyle.focus.cardPadding, AppDesignStyle.native.cardPadding)
        XCTAssertGreaterThan(AppDesignStyle.studio.sectionGap, AppDesignStyle.native.sectionGap)
    }

    func testNewerAppearanceMergeAndImportCarryStyleWithoutLosingHabits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("style-merge-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HabitStore(url: directory.appendingPathComponent("local.json"))
        let habit = Habit(name: "Keep me")
        store.add(habit)
        let savedHabits = store.habits
        let future = Date().timeIntervalSince1970 + 1000
        let preferences = AppearancePreferences(material: .milky, backgroundMode: .gradient,
                                                gradientStartHex: 0x123456, gradientEndHex: 0x654321,
                                                performanceMode: true, designStyle: .studio)
        let remote = HabitData(version: HabitData.currentVersion, updatedAt: future,
                               summaryMinutes: nil, habits: [], appearanceUpdatedAt: future,
                               appearancePreferences: preferences)
        store.merge(remote: remote)
        XCTAssertEqual(store.appearancePreferences, preferences)
        XCTAssertEqual(store.habits, savedHabits)
        let imported = HabitStore(url: directory.appendingPathComponent("imported.json"))
        try imported.importJSON(XCTUnwrap(store.exportJSON()))
        XCTAssertEqual(imported.appearancePreferences, preferences)
        XCTAssertEqual(imported.habits, savedHabits)
    }

    func testDesignAndMaterialSelectorsHaveAllSupportedLanguages() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Haiity/Localizable.xcstrings")
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let languages = Set(["ar", "bn", "de", "en", "es", "fr", "hi", "id", "it", "ja",
                             "ko", "pt", "ru", "tr", "ur", "vi", "zh-Hans"])
        let keys = ["Designstil", "Anpassen", "Wähle das Layout für die ganze App.",
                    "Original", "Ruhig", "Fokus", "Studio",
                    "Das vertraute hAiity-Design mit klaren Gruppen und nativen Bedienelementen.",
                    "Weniger Flächen, dezente Symbole und ein ruhiger Lesefluss.",
                    "Kompakte Inhalte, klare Aktionen und mehr Überblick.",
                    "Markante Überschriften und großzügige Flächen für deinen Fortschritt.",
                    "Dein Fortschritt", "12 Tage Serie", "Oberfläche",
                    "Vorschau des ausgewählten Erscheinungsbilds"]
        for key in keys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localized = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
            XCTAssertEqual(Set(localized.keys), languages, key)
            for language in languages {
                let translation = try XCTUnwrap(localized[language] as? [String: Any], "\(key) / \(language)")
                let unit = try XCTUnwrap(translation["stringUnit"] as? [String: Any], key)
                XCTAssertEqual(unit["state"] as? String, "translated", key)
                XCTAssertFalse((unit["value"] as? String ?? "").isEmpty, key)
            }
        }
    }
}
