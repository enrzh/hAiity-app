import XCTest
@testable import Haiity

final class MotivationTests: XCTestCase {
    func testPoolHas288CombinationsAndMatchingOpeners() {
        XCTAssertEqual(Motivation.openersNamed.count, 12)
        XCTAssertEqual(Motivation.openersPlain.count, 12)
        XCTAssertEqual(Motivation.lines.count, 24)
        XCTAssertEqual(Motivation.openersNamed.count * Motivation.lines.count, 288)
        XCTAssertTrue(Motivation.openersNamed.allSatisfy { $0.contains("%@") })
        XCTAssertTrue(Motivation.openersPlain.allSatisfy { !$0.contains("%@") })
        XCTAssertTrue(Motivation.lines.allSatisfy { !$0.contains("%@") })
    }

    func testMessageIsStableForTheDayAndHandlesAnOptionalName() {
        let named = Motivation.message(name: "Mo", today: "2026-08-14")
        XCTAssertEqual(named.title, Motivation.message(name: "Mo", today: "2026-08-14").title)
        XCTAssertEqual(named.body, Motivation.message(name: "Mo", today: "2026-08-14").body)
        XCTAssertTrue(named.title.contains("Mo"))
        XCTAssertFalse(named.title.contains("%@"))

        let plain = Motivation.message(name: nil, today: "2026-08-14")
        XCTAssertEqual(plain.title, Motivation.message(name: "", today: "2026-08-14").title)
        XCTAssertEqual(named.body, plain.body)
        XCTAssertFalse(plain.title.contains("%@"))
    }

    func testSaltedIndicesCoverMostCombinationsAcrossThreeYears() {
        var pairs = Set<String>()
        var day = "2026-01-01"
        for _ in 0..<1095 {
            let opener = Motivation.index(for: day, salt: Motivation.openerSalt, count: 12)
            let line = Motivation.index(for: day, salt: Motivation.lineSalt, count: 24)
            pairs.insert("\(opener)-\(line)")
            day = DayKey.shifted(day, by: 1) ?? day
        }
        XCTAssertGreaterThanOrEqual(pairs.count, 250,
                                    "hash salts have become correlated again")
    }

    func testMoreCarriesTheOptInSettingAndTimePicker() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        XCTAssertTrue(more.contains("motivationSection"))
        XCTAssertTrue(more.contains("store.motivationMinutes"))
        XCTAssertTrue(more.contains("\"motivation-toggle\""))
        XCTAssertTrue(more.contains("\"motivation-time\""))
        XCTAssertTrue(more.contains("\"motivation-delivery\""))
        XCTAssertTrue(more.contains("Live-Aktivitäten starten"))
        XCTAssertTrue(more.contains("Reminders.ensurePermission()"))
        XCTAssertTrue(more.contains("Do not disturb"))
        XCTAssertFalse(more.contains("DND (Do not disturb)"))
        XCTAssertTrue(more.contains("copy-sync-watermark"))
        XCTAssertFalse(more.contains("ForEach(SyncWatermark.Kind.allCases"))
        XCTAssertTrue(more.contains("notification-actions-toggle"))
    }

    func testMotivationLinesStayShortEnoughForNotifications() {
        XCTAssertTrue(Motivation.lines.allSatisfy { $0.count <= 84 })
    }

    func testTargetAndCatalogCarryMotivation() throws {
        let yml = try source("project.yml")
        XCTAssertTrue(yml.contains("Haiity/Models/Motivation.swift"))

        let data = try Data(contentsOf: root.appendingPathComponent("Haiity/Localizable.xcstrings"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        for key in ["Tägliche Motivation",
                    "Jeden Tag ein anderer kurzer Gedanke aus deinem Raster — ruhig, ohne Druck."] {
            XCTAssertNotNil(strings[key], "fehlt im Katalog: \(key)")
        }
    }

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relative))
    }
}
