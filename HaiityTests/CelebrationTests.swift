import XCTest
@testable import Haiity

/// v23: der Glückwunsch zum perfekten Tag und die Anrede dahinter.
final class CelebrationTests: XCTestCase {

    // MARK: – Perfekter Tag

    func testAnEmptyDayIsNotPerfect() {
        XCTAssertFalse(Celebration.isPerfect(SummaryStatus(done: 0, total: 0, missing: [])))
    }

    func testAnOpenHabitBlocksThePerfectDay() {
        XCTAssertFalse(Celebration.isPerfect(SummaryStatus(done: 2, total: 3, missing: ["Lesen"])))
    }

    /// Ein beantwortetes „Nein" lässt `done` hinter `total` zurück — der Tag
    /// ist abgeschlossen, aber nicht geschafft; kein Glückwunsch.
    func testADeclinedAnswerIsNoReasonToCelebrate() {
        XCTAssertFalse(Celebration.isPerfect(SummaryStatus(done: 2, total: 3, missing: [])))
    }

    func testAllDoneIsPerfect() {
        XCTAssertTrue(Celebration.isPerfect(SummaryStatus(done: 3, total: 3, missing: [])))
    }

    func testCelebrationFiresOncePerDay() {
        let perfect = SummaryStatus(done: 1, total: 1, missing: [])
        XCTAssertTrue(Celebration.shouldCelebrate(status: perfect, today: "2026-08-13",
                                                  lastCelebrated: nil))
        XCTAssertTrue(Celebration.shouldCelebrate(status: perfect, today: "2026-08-13",
                                                  lastCelebrated: "2026-08-12"))
        XCTAssertFalse(Celebration.shouldCelebrate(status: perfect, today: "2026-08-13",
                                                   lastCelebrated: "2026-08-13"))
    }

    // MARK: – Botschaft

    func testPoolIndexIsDeterministicAndInRange() {
        for day in ["2026-08-13", "2026-08-14", "2027-01-01"] {
            let first = Celebration.poolIndex(for: day, poolSize: 6)
            XCTAssertEqual(first, Celebration.poolIndex(for: day, poolSize: 6),
                           "gleicher Tag, gleicher Wurf")
            XCTAssertTrue((0..<6).contains(first), day)
        }
    }

    /// Über einen Monat streut der Wurf wirklich — sonst wäre der Pool Deko.
    func testPoolIndexVariesAcrossDays() {
        var seen = Set<Int>()
        for day in 1...30 {
            seen.insert(Celebration.poolIndex(for: String(format: "2026-09-%02d", day),
                                              poolSize: 6))
        }
        XCTAssertGreaterThanOrEqual(seen.count, 3, "\(seen)")
    }

    func testMessageCarriesTheName() {
        let message = Celebration.message(name: "Mo", today: "2026-08-13")
        XCTAssertTrue(message.title.contains("Mo"), message.title)
        XCTAssertFalse(message.title.contains("%@"), "Platzhalter muss gefüllt sein")
        XCTAssertFalse(message.body.isEmpty)
    }

    func testMessageWithoutNameStaysNeutral() {
        let message = Celebration.message(name: nil, today: "2026-08-13")
        XCTAssertFalse(message.title.contains("%@"), message.title)
        XCTAssertFalse(message.body.isEmpty)
        XCTAssertEqual(message.title, Celebration.message(name: "", today: "2026-08-13").title,
                       "leerer Name zählt wie keiner")
    }

    /// Die drei Pools laufen synchron — gleich lang, damit Index i immer
    /// Titel UND Text trifft.
    func testPoolsShareOneLength() {
        XCTAssertEqual(Celebration.plainTitles.count, Celebration.bodies.count)
        XCTAssertEqual(Celebration.namedTitles.count, Celebration.bodies.count)
        for title in Celebration.namedTitles {
            XCTAssertTrue(title.contains("%@"), title)
        }
        for title in Celebration.plainTitles {
            XCTAssertFalse(title.contains("%@"), title)
        }
    }

    // MARK: – Anrede

    func testAliasBeatsAppleName() {
        XCTAssertEqual(PersonalName.resolve(alias: "Mo", appleName: "Enrico"), "Mo")
    }

    func testAppleNameFillsInWhenAliasIsBlank() {
        XCTAssertEqual(PersonalName.resolve(alias: "   ", appleName: "Enrico"), "Enrico")
        XCTAssertEqual(PersonalName.resolve(alias: nil, appleName: "Enrico"), "Enrico")
    }

    func testNoNameMeansNil() {
        XCTAssertNil(PersonalName.resolve(alias: nil, appleName: nil))
        XCTAssertNil(PersonalName.resolve(alias: " ", appleName: ""))
    }

    // MARK: – Quell-Verträge

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relative))
    }

    /// BEIDE Check-in-Wege prüfen den perfekten Tag: der in der App und der
    /// über den Widget-Knopf.
    func testBothCheckInPathsAskForTheCelebration() throws {
        let content = try source("Haiity/Views/ContentView.swift")
        let reminders = try source("Haiity/Services/Reminders.swift")
        XCTAssertTrue(content.contains("Reminders.celebrateIfPerfectDay(store: store)"))
        XCTAssertTrue(reminders.contains("await celebrateIfPerfectDay(store: store"),
                      "reconcileAfterExternalCheckIn muss mitfeiern")
    }

    /// Das Widget-Target trägt Botschaft und Anrede — sonst bricht der
    /// Extension-Build, sobald Reminders feiert.
    func testWidgetTargetCarriesCelebrationAndPersonalName() throws {
        let yml = try source("project.yml")
        XCTAssertTrue(yml.contains("Haiity/Models/Celebration.swift"))
        XCTAssertTrue(yml.contains("Haiity/Models/PersonalName.swift"))
    }

    /// Die Apple-Anmeldung fragt Name und E-Mail: der Name personalisiert,
    /// die verifizierte E-Mail erkennt ausschließlich das Entwicklerkonto.
    func testSignInAsksForNameAndOwnerEmail() throws {
        let more = try source("Haiity/Views/MorePersonal.swift")
        XCTAssertTrue(more.contains("request.requestedScopes = [.fullName, .email]"))
        XCTAssertTrue(more.contains("if storedAppleUserID != nil"),
                      "the stable Apple ID, not an optional name, defines signed-in state")
        XCTAssertTrue(more.contains("storedAppleEmail = PersonalName.appleEmail"))
        for id in ["\"personal-alias\"", "\"apple-signin\"", "\"apple-signout\""] {
            XCTAssertTrue(more.contains(id), id)
        }
        let entitlements = try source("Haiity/Haiity.entitlements")
        XCTAssertTrue(entitlements.contains("com.apple.developer.applesignin"))
    }

    func testCelebrationStringsAreInTheCatalog() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Localizable.xcstrings"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        for key in ["Alle Habits geschafft!", "%@, alle Habits geschafft!",
                    "Alles von heute ist erledigt — das Raster leuchtet.",
                    "Anrede", "Alias", "Angemeldet als %@", "Entfernen"] {
            XCTAssertNotNil(strings[key], "fehlt im Katalog: \(key)")
        }
    }
}
