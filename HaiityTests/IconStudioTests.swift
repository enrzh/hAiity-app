import XCTest
@testable import Haiity

/// v22: das Icon-Studio (18 eingebaute Icons + freie Farbe) und der
/// pixelige Farbwähler.
final class IconStudioTests: XCTestCase {

    // MARK: – Kachel-Kuratierung

    func testTileRowsAreThreeTimesTwelveAndChromatic() {
        XCTAssertEqual(HueTileGrid.rows.count, 3)
        for row in HueTileGrid.rows {
            XCTAssertEqual(row.count, 12)
            XCTAssertEqual(Set(row).count, 12, "doppelte Kacheln")
            for hex in row {
                XCTAssertNotNil(PaletteGenerator.hueDegrees(hex),
                                String(format: "unbunt: #%06X", hex))
            }
        }
    }

    /// Die mittlere Reihe IST die Basis der zwölf Farbton-Icons — wer eine
    /// Kachel als Graph-Farbe wählt und die Icon-Kopplung anhat, bekommt
    /// pixelgenau das passende Icon.
    func testMiddleTileRowMatchesTheHueIconBases() {
        XCTAssertEqual(HueTileGrid.rows[1], AppIcons.hues.map(\.base))
    }

    /// Jede Kachel ergibt über die Icon-Kopplung ein echtes Icon.
    func testEveryTileResolvesToABundledIcon() {
        for hex in HueTileGrid.rows.flatMap({ $0 }) {
            let name = AppIcons.iconName(forBase: hex)
            if let name {
                XCTAssertTrue(AppIcons.alternateNames.contains(name),
                              String(format: "#%06X → %@", hex, name))
            }
        }
    }

    /// Die Helligkeits-Reihen sind wirklich hell → mittel → tief.
    func testTileRowsDescendInLuminance() {
        for col in 0..<12 {
            let l = HueTileGrid.rows.map { PaletteGenerator.luminance($0[col]) }
            XCTAssertGreaterThan(l[0], l[1], "Spalte \(col): hell ≤ mittel")
            XCTAssertGreaterThan(l[1], l[2], "Spalte \(col): mittel ≤ tief")
        }
    }

    // MARK: – Quell-Verträge

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relative))
    }

    /// Das Auswahlraster zeigt ALLE 18 Icons plus die freie Farbe mit
    /// ehrlicher Vorschau des gerundeten Ziels.
    func testMoreViewOffersEveryIconAndTheFreeColorRow() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        XCTAssertTrue(more.contains("ForEach(AppIcons.hues)"))
        for id in ["\"icon-color-picker\"", "\"icon-color-apply\""] {
            XCTAssertTrue(more.contains(id), id)
        }
        XCTAssertTrue(more.contains("AppIcons.style(forIconName: snappedFreeIconName)"),
                      "die Mini-Vorschau muss das GERUNDETE Ziel zeigen")
        XCTAssertFalse(more.contains("AppIcons.set(palette)"),
                       "Icon-Wechsel läuft seit v22 über Katalognamen")
    }

    /// Der Farbwähler ist pixelig: Kachel-Raster zuerst, das Farbrad nur
    /// noch als Feinabstimmung, die Vorschau ein echtes Mini-Raster.
    func testCustomPaletteSheetIsPixelly() throws {
        let sheet = try source("Haiity/Views/CustomPaletteSheet.swift")
        XCTAssertTrue(sheet.contains("HueTileGrid(selected:"))
        XCTAssertTrue(sheet.contains("\"custom-palette-tiles\""))
        XCTAssertTrue(sheet.contains("MotifGrid(pattern: MotifGrid.brand"))
        // Die Kennungen, an denen Automatisierung und Doku hängen.
        for id in ["\"custom-palette-color\"", "\"custom-palette-name\"",
                   "\"custom-palette-preview-light\"", "\"custom-palette-preview-dark\""] {
            XCTAssertTrue(sheet.contains(id), id)
        }
    }

    func testStudioStringsAreInTheCatalog() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Localizable.xcstrings"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        for key in ["Feinabstimmung", "Eigene Icon-Farbe", "Anwenden",
                    "hell", "mittel", "tief", "Farbton %lld°"] {
            XCTAssertNotNil(strings[key], "fehlt im Katalog: \(key)")
        }
    }

    /// Alle 17 Alternates liegen als .appiconset im Katalog — ein Name in
    /// project.yml ohne Bilddaten fiele sonst erst beim Archivieren auf.
    func testEveryAlternateNameHasAnAppiconset() throws {
        let assets = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Assets.xcassets")
        for name in AppIcons.alternateNames {
            let set = assets.appendingPathComponent("\(name).appiconset/icon_1024.png")
            XCTAssertTrue(FileManager.default.fileExists(atPath: set.path),
                          "\(name).appiconset fehlt oder ist leer")
        }
    }

    /// project.yml kennt exakt die Namen aus dem Code — in beide Richtungen.
    func testProjectYamlDeclaresExactlyTheAlternateNames() throws {
        let yml = try source("project.yml")
        let line = try XCTUnwrap(yml.split(separator: "\n")
            .first { $0.contains("ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES") })
        let quoted = try XCTUnwrap(line.split(separator: "\"").dropFirst().first)
        XCTAssertEqual(Set(quoted.split(separator: " ").map(String.init)),
                       Set(AppIcons.alternateNames))
    }
}
