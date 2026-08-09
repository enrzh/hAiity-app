import XCTest
@testable import Haiity

final class DayKeyTests: XCTestCase {
    var berlin: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }

    func testKeyFormatsWithPadding() {
        var c = DateComponents(); c.year = 2026; c.month = 8; c.day = 9
        let d = berlin.date(from: c)!
        XCTAssertEqual(DayKey.key(for: d, calendar: berlin), "2026-08-09")
    }

    func testParseRoundTrip() {
        let key = "2026-01-05"
        let d = DayKey.date(from: key, calendar: berlin)
        XCTAssertNotNil(d)
        XCTAssertEqual(DayKey.key(for: d!, calendar: berlin), key)
    }

    func testShiftAcrossMonthBoundary() {
        XCTAssertEqual(DayKey.shifted("2026-08-01", by: -1, calendar: berlin), "2026-07-31")
        XCTAssertEqual(DayKey.shifted("2026-07-31", by: 1, calendar: berlin), "2026-08-01")
    }

    func testShiftAcrossYearBoundary() {
        XCTAssertEqual(DayKey.shifted("2026-01-01", by: -1, calendar: berlin), "2025-12-31")
        XCTAssertEqual(DayKey.shifted("2025-12-31", by: 1, calendar: berlin), "2026-01-01")
    }

    func testShiftAcrossSpringDSTTransition() {
        // 29.03.2026: Sommerzeit-Umstellung in Berlin (23-Stunden-Tag)
        XCTAssertEqual(DayKey.shifted("2026-03-28", by: 1, calendar: berlin), "2026-03-29")
        XCTAssertEqual(DayKey.shifted("2026-03-29", by: 1, calendar: berlin), "2026-03-30")
        XCTAssertEqual(DayKey.shifted("2026-03-30", by: -2, calendar: berlin), "2026-03-28")
    }

    func testShiftAcrossAutumnDSTTransition() {
        // 25.10.2026: Winterzeit (25-Stunden-Tag)
        XCTAssertEqual(DayKey.shifted("2026-10-24", by: 1, calendar: berlin), "2026-10-25")
        XCTAssertEqual(DayKey.shifted("2026-10-25", by: 1, calendar: berlin), "2026-10-26")
        XCTAssertEqual(DayKey.shifted("2026-10-26", by: -2, calendar: berlin), "2026-10-24")
    }

    func testInvalidKeyParsesToNil() {
        XCTAssertNil(DayKey.date(from: "quatsch"))
        XCTAssertNil(DayKey.date(from: "2026-13"))
    }
}

final class StreakTests: XCTestCase {
    private func habit(_ days: [String]) -> Habit {
        var h = Habit(name: "Test")
        for d in days { h.log[d] = 1 }
        return h
    }

    func testEmptyLogHasZeroStreak() {
        XCTAssertEqual(habit([]).streak(today: "2026-08-09"), 0)
    }

    func testStreakEndingToday() {
        let h = habit(["2026-08-07", "2026-08-08", "2026-08-09"])
        XCTAssertEqual(h.streak(today: "2026-08-09"), 3)
    }

    func testStreakSurvivesUncheckedToday() {
        // Heute noch offen -> Serie bis gestern zählt weiter
        let h = habit(["2026-08-07", "2026-08-08"])
        XCTAssertEqual(h.streak(today: "2026-08-09"), 2)
    }

    func testStreakBrokenByGap() {
        let h = habit(["2026-08-05", "2026-08-06", "2026-08-09"])
        XCTAssertEqual(h.streak(today: "2026-08-09"), 1)
    }

    func testBestStreakFindsMiddleRun() {
        let h = habit(["2026-01-01",
                       "2026-02-01", "2026-02-02", "2026-02-03", "2026-02-04",
                       "2026-03-01", "2026-03-02"])
        XCTAssertEqual(h.bestStreak(), 4)
    }

    func testBestStreakAcrossMonthBoundary() {
        let h = habit(["2026-07-30", "2026-07-31", "2026-08-01", "2026-08-02"])
        XCTAssertEqual(h.bestStreak(), 4)
    }
}

final class IntensityTests: XCTestCase {
    private func habit(_ days: [String]) -> Habit {
        var h = Habit(name: "Test")
        for d in days { h.log[d] = 1 }
        return h
    }

    func testUncheckedIsZero() {
        XCTAssertEqual(habit([]).intensity("2026-08-09"), 0)
    }

    func testSingleDayIsLevelOne() {
        XCTAssertEqual(habit(["2026-08-09"]).intensity("2026-08-09"), 1)
    }

    func testLevelsScaleWithRunLength() {
        let days = (0..<8).compactMap { DayKey.shifted("2026-08-09", by: -$0) }
        let h = habit(days)
        XCTAssertEqual(h.intensity("2026-08-02"), 1) // Lauf-Anfang
        XCTAssertEqual(h.intensity("2026-08-05"), 2)
        XCTAssertEqual(h.intensity("2026-08-09"), 4) // 8. Tag im Lauf
    }

    func testLevelNeverExceedsFour() {
        let days = (0..<30).compactMap { DayKey.shifted("2026-08-09", by: -$0) }
        XCTAssertEqual(habit(days).intensity("2026-08-09"), 4)
    }
}
