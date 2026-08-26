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

    func testManagerDoesNotStartBeforeConfiguredTime() async {
        let client = RecordedMotivationActivityClient()
        let defaults = testDefaults("before-time")
        let manager = MotivationActivityManager(client: client, defaults: defaults)
        let now = DayKey.date(from: "2026-08-17", calendar: calendar)!
            .addingTimeInterval(7 * 3600)

        await manager.reconcile(motivationMinutes: 8 * 60,
                                name: "Mo",
                                now: now,
                                calendar: calendar)

        let snapshot = await client.snapshot()
        XCTAssertTrue(snapshot.starts.isEmpty)
        XCTAssertNil(MotivationActivityStorage.shownDay(in: defaults))
        cleanupDefaults(defaults, suite: "MotivationActivityTests.before-time")
    }

    func testManagerStartsOneCapturedMessageAfterConfiguredTime() async {
        let client = RecordedMotivationActivityClient()
        let defaults = testDefaults("starts-message")
        let manager = MotivationActivityManager(client: client, defaults: defaults)
        let now = DayKey.date(from: "2026-08-17", calendar: calendar)!
            .addingTimeInterval(9 * 3600)

        await manager.reconcile(motivationMinutes: 8 * 60,
                                name: "Mo",
                                now: now,
                                calendar: calendar)

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.starts.count, 1)
        XCTAssertEqual(snapshot.starts.first?.dayKey, "2026-08-17")
        let expected = Motivation.message(name: "Mo", today: "2026-08-17")
        XCTAssertEqual(snapshot.starts.first?.title, expected.title)
        XCTAssertEqual(snapshot.starts.first?.body, expected.body)
        XCTAssertEqual(MotivationActivityStorage.shownDay(in: defaults), "2026-08-17")
        cleanupDefaults(defaults, suite: "MotivationActivityTests.starts-message")
    }

    func testManagerEndsOldDaysAndPreservesToday() async {
        let client = RecordedMotivationActivityClient(active: ["2026-08-16", "2026-08-17"])
        let defaults = testDefaults("old-day")
        let manager = MotivationActivityManager(client: client, defaults: defaults)
        let now = DayKey.date(from: "2026-08-17", calendar: calendar)!
            .addingTimeInterval(9 * 3600)

        await manager.reconcile(motivationMinutes: 8 * 60,
                                name: nil,
                                now: now,
                                calendar: calendar)

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.ended, ["2026-08-16"])
        XCTAssertTrue(snapshot.starts.isEmpty)
        XCTAssertEqual(snapshot.active, ["2026-08-17"])
        cleanupDefaults(defaults, suite: "MotivationActivityTests.old-day")
    }

    func testManagerDoesNotRestartShownDay() async {
        let client = RecordedMotivationActivityClient()
        let defaults = testDefaults("shown-day")
        MotivationActivityStorage.markShown("2026-08-17", in: defaults)
        let manager = MotivationActivityManager(client: client, defaults: defaults)
        let now = DayKey.date(from: "2026-08-17", calendar: calendar)!
            .addingTimeInterval(9 * 3600)

        await manager.reconcile(motivationMinutes: 8 * 60,
                                name: nil,
                                now: now,
                                calendar: calendar)

        let snapshot = await client.snapshot()
        XCTAssertTrue(snapshot.starts.isEmpty)
        cleanupDefaults(defaults, suite: "MotivationActivityTests.shown-day")
    }

    func testDisablingMotivationEndsActivitiesAndClearsMarker() async {
        let client = RecordedMotivationActivityClient(active: ["2026-08-17"])
        let defaults = testDefaults("disabled")
        MotivationActivityStorage.markShown("2026-08-17", in: defaults)
        let manager = MotivationActivityManager(client: client, defaults: defaults)

        let now = DayKey.date(from: "2026-08-17", calendar: calendar)!
            .addingTimeInterval(9 * 3600)
        await manager.reconcile(motivationMinutes: nil,
                                name: nil,
                                now: now,
                                calendar: calendar)

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.ended, [nil])
        XCTAssertTrue(snapshot.active.isEmpty)
        XCTAssertNil(MotivationActivityStorage.shownDay(in: defaults))
        cleanupDefaults(defaults, suite: "MotivationActivityTests.disabled")
    }

    func testNotificationDeliveryEndsLiveActivityWithoutStartingAnother() async {
        let client = RecordedMotivationActivityClient(active: ["2026-08-17"])
        let defaults = testDefaults("notification-mode")
        let manager = MotivationActivityManager(client: client, defaults: defaults)
        let now = DayKey.date(from: "2026-08-18", calendar: calendar)!
            .addingTimeInterval(12 * 3600)

        await manager.reconcile(motivationMinutes: 8 * 60,
                                name: "Mo",
                                delivery: .notification,
                                now: now,
                                calendar: calendar)

        let snapshot = await client.snapshot()
        XCTAssertTrue(snapshot.starts.isEmpty)
        XCTAssertEqual(snapshot.ended, ["2026-08-17", nil])
        XCTAssertNil(MotivationActivityStorage.shownDay(in: defaults))
        cleanupDefaults(defaults, suite: "MotivationActivityTests.notification-mode")
    }

    func testManagerDoesNotMarkDayWhenActivityRequestFails() async {
        let client = RecordedMotivationActivityClient(shouldThrow: true)
        let defaults = testDefaults("request-fails")
        let manager = MotivationActivityManager(client: client, defaults: defaults)
        let now = DayKey.date(from: "2026-08-17", calendar: calendar)!
            .addingTimeInterval(9 * 3600)

        await manager.reconcile(motivationMinutes: 8 * 60,
                                name: nil,
                                now: now,
                                calendar: calendar)

        XCTAssertNil(MotivationActivityStorage.shownDay(in: defaults))
        cleanupDefaults(defaults, suite: "MotivationActivityTests.request-fails")
    }

    func testLiveActivityStartBoundaryStaysServerlessAndDocumentsItsTerminationLimit() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Services/MotivationActivityManager.swift"))

        XCTAssertTrue(source.contains("pushType: nil"),
                      "Task 6 keeps motivation delivery on the serverless ActivityKit path")
        XCTAssertTrue(source.contains("terminated app cannot start a Live Activity"),
                      "the start boundary must document the terminated-state limit explicitly")
        XCTAssertTrue(source.contains("notification fallback remains the serverless behavior"),
                      "the source should state that the fallback stays with notifications until a backend is approved")
        XCTAssertTrue(source.contains("NotificationDeliveryIssueCenter.note(.reminderScheduleFailed)"),
                      "a failed motivation start must persist the same delivery issue the app consumes on next activation")
    }

    func testConcurrentReconciliationsStartOnlyOnce() async {
        let client = RecordedMotivationActivityClient()
        let defaults = testDefaults("concurrent")
        let manager = MotivationActivityManager(client: client, defaults: defaults)
        let now = DayKey.date(from: "2026-08-17", calendar: calendar)!
            .addingTimeInterval(9 * 3600)

        async let first: Void = manager.reconcile(motivationMinutes: 8 * 60,
                                                   name: nil,
                                                   now: now,
                                                   calendar: calendar)
        async let second: Void = manager.reconcile(motivationMinutes: 8 * 60,
                                                    name: nil,
                                                    now: now,
                                                    calendar: calendar)
        _ = await (first, second)

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.starts.count, 1)
        cleanupDefaults(defaults, suite: "MotivationActivityTests.concurrent")
    }

    private func testDefaults(_ suffix: String) -> UserDefaults {
        let suite = "MotivationActivityTests.\(suffix)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func cleanupDefaults(_ defaults: UserDefaults, suite: String) {
        defaults.removePersistentDomain(forName: suite)
    }
}

actor RecordedMotivationActivityClient: MotivationActivityClient {
    enum TestActivityError: Error { case denied }

    private var active: Set<String>
    private var starts: [MotivationActivityRequest] = []
    private var ended: [String?] = []
    private let shouldThrow: Bool

    init(active: Set<String> = [], shouldThrow: Bool = false) {
        self.active = active
        self.shouldThrow = shouldThrow
    }

    func activeDayKeys() async -> Set<String> { active }

    func start(_ request: MotivationActivityRequest) async throws {
        if shouldThrow { throw TestActivityError.denied }
        starts.append(request)
        active.insert(request.dayKey)
    }

    func end(dayKey: String?) async {
        ended.append(dayKey)
        if let dayKey { active.remove(dayKey) }
        else { active.removeAll() }
    }

    func snapshot() -> (active: Set<String>,
                       starts: [MotivationActivityRequest],
                       ended: [String?]) {
        (active, starts, ended)
    }
}
