import XCTest
@testable import Haiity

final class MotivationActivityTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        return c
    }()

    func testBeforeConfiguredTimeWaits() {
        let now = DayKey.date(from: "2026-08-17", calendar: calendar)!
            .addingTimeInterval(7 * 3600 + 59 * 60)

        XCTAssertEqual(
            MotivationActivityPolicy.decision(minutes: 8 * 60,
                                              now: now,
                                              shownDay: nil,
                                              calendar: calendar),
            .waiting)
    }

    func testAtConfiguredTimeStartsUntilNextMidnight() {
        let now = DayKey.date(from: "2026-08-17", calendar: calendar)!
            .addingTimeInterval(8 * 3600)

        let decision = MotivationActivityPolicy.decision(minutes: 8 * 60,
                                                         now: now,
                                                         shownDay: nil,
                                                         calendar: calendar)

        XCTAssertEqual(decision,
                       .start(dayKey: "2026-08-17",
                              staleDate: DayKey.date(from: "2026-08-18", calendar: calendar)!))
    }

    func testNilOrInvalidTimeIsDisabled() {
        let now = DayKey.date(from: "2026-08-17", calendar: calendar)!

        XCTAssertEqual(MotivationActivityPolicy.decision(minutes: nil,
                                                          now: now,
                                                          shownDay: nil,
                                                          calendar: calendar),
                       .disabled)
        XCTAssertEqual(MotivationActivityPolicy.decision(minutes: 24 * 60,
                                                          now: now,
                                                          shownDay: nil,
                                                          calendar: calendar),
                       .disabled)
    }

    func testShownDayPreventsSameDayRestartButAllowsNextDay() {
        let today = DayKey.date(from: "2026-08-17", calendar: calendar)!
            .addingTimeInterval(9 * 3600)
        XCTAssertEqual(MotivationActivityPolicy.decision(minutes: 8 * 60,
                                                          now: today,
                                                          shownDay: "2026-08-17",
                                                          calendar: calendar),
                       .alreadyShown)

        let tomorrow = DayKey.date(from: "2026-08-18", calendar: calendar)!
            .addingTimeInterval(9 * 3600)
        XCTAssertEqual(MotivationActivityPolicy.decision(minutes: 8 * 60,
                                                          now: tomorrow,
                                                          shownDay: "2026-08-17",
                                                          calendar: calendar),
                       .start(dayKey: "2026-08-18",
                              staleDate: DayKey.date(from: "2026-08-19", calendar: calendar)!))
    }

    func testAppGroupMarkerRoundTripsThroughInjectedDefaults() {
        let suite = "MotivationActivityTests.marker"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(MotivationActivityStorage.shownDay(in: defaults))
        MotivationActivityStorage.markShown("2026-08-17", in: defaults)
        XCTAssertEqual(MotivationActivityStorage.shownDay(in: defaults), "2026-08-17")
        MotivationActivityStorage.clearShown(in: defaults)
        XCTAssertNil(MotivationActivityStorage.shownDay(in: defaults))
    }

    func testActivityRequestPreservesCapturedMessageAndExpiry() {
        let staleDate = Date(timeIntervalSince1970: 1234)
        let request = MotivationActivityRequest(dayKey: "2026-08-17",
                                                 title: "Heute",
                                                 body: "Ein kleiner Schritt.",
                                                 staleDate: staleDate)

        XCTAssertEqual(request.dayKey, "2026-08-17")
        XCTAssertEqual(request.title, "Heute")
        XCTAssertEqual(request.body, "Ein kleiner Schritt.")
        XCTAssertEqual(request.staleDate, staleDate)
    }
}
