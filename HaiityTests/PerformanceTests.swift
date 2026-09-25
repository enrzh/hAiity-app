import XCTest
@testable import Haiity

/// Benchmarks for the work that runs on every list render.
///
/// The app had no timing harness at all, which meant "it feels fast" was the only
/// performance claim anyone could make and nobody could check it. These exist so
/// the next person sees a number move instead of guessing.
///
/// **Why not `measure {}`.** It reports a floor of roughly a quarter of a second
/// per test on this machine, which is the harness calibrating, not the code being
/// measured — formatting a single day key came out the same cost as a pass over
/// fifty habits. So each one times a fixed number of iterations itself and prints
/// milliseconds per iteration. Same methodology before and after, so the
/// difference is real.
///
/// The ceilings are deliberately loose. A tight time assertion is a flaky test
/// that gets deleted after it fails once on a busy machine; these only catch a
/// catastrophic regression, and the printed numbers are for the humans.
final class PerformanceTests: XCTestCase {

    /// A paying person who tracks a lot. The free allowance is three, so this is
    /// deliberately far past it rather than a typical free-tier count.
    private static let heavyHabitCount = 50

    private static let zones: [String?] = [
        "Europe/Berlin", "America/New_York", "Asia/Tokyo", "Australia/Sydney",
        "America/Sao_Paulo", nil, nil, nil,
    ]

    private func makeHabits(_ count: Int, zones: [String?]) -> [Habit] {
        (0..<count).map { index in
            var habit = Habit(name: "Habit \(index)",
                              emoji: "💧",
                              itemType: .habit,
                              timeMinutes: 7 * 60,
                              recurrence: index % 3 == 0
                                  ? Recurrence(frequency: .weekly, weekdays: [2, 4, 6])
                                  : .daily)
            habit.timeZoneIdentifier = zones[index % zones.count]
            return habit
        }
    }

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        c.firstWeekday = 2
        return c
    }()

    /// Milliseconds per call, warmed up so the first-call cost is not charged to
    /// the loop. Returns the figure so a caller can assert on it if it wants to.
    @discardableResult
    private func timing(_ label: String,
                        iterations: Int = 500,
                        _ work: () -> Void) -> Double {
        for _ in 0..<20 { work() }
        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<iterations { work() }
        let elapsed = start.duration(to: clock.now)
        let milliseconds = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
        let perCall = milliseconds / Double(iterations)
        print(String(format: "PERF  %-48@ %.5f ms", label as NSString, perCall))
        return perCall
    }

    // MARK: - The view-body path

    /// The one that matters most: a body-evaluated pass over every habit, with a
    /// mix of explicit timezones and inherited ones, which is the realistic shape
    /// of a real list. This re-runs for every habit on every re-evaluation of the
    /// body, on the main actor, while someone is scrolling.
    func testTodayProgressAcrossManyHabits() {
        let habits = makeHabits(Self.heavyHabitCount, zones: Self.zones)
        let now = Date(timeIntervalSince1970: 1_787_000_000)
        let perCall = timing("todayProgress/50 habits, mixed zones") {
            _ = ScheduledProgress.today(habits: habits,
                                        defaultTimeZoneIdentifier: nil,
                                        now: now, calendar: self.calendar)
        }
        XCTAssertLessThan(perCall, 50, "a body-evaluated pass should not cost milliseconds")
    }

    /// The same pass when every habit inherits the device zone, which is the
    /// common case and the one where repeating identical work per habit is most
    /// wasteful.
    func testTodayProgressWhenEveryHabitSharesTheDeviceZone() {
        let habits = makeHabits(Self.heavyHabitCount, zones: [nil])
        let now = Date(timeIntervalSince1970: 1_787_000_000)
        let perCall = timing("todayProgress/50 habits, one zone") {
            _ = ScheduledProgress.today(habits: habits,
                                        defaultTimeZoneIdentifier: nil,
                                        now: now, calendar: self.calendar)
        }
        XCTAssertLessThan(perCall, 50)
    }

    /// Isolates the timezone lookup, because it is the suspected cost: an
    /// explicit identifier is resolved twice per call.
    func testResolvingAnExplicitTimeZoneCalendar() {
        let perCall = timing("calendar(identifier: Europe/Berlin)") {
            _ = HabitTimeZone.calendar(identifier: "Europe/Berlin", base: self.calendar)
        }
        XCTAssertLessThan(perCall, 5, "resolving one timezone should be microseconds")
    }

    /// The day key is formatted once per habit inside that pass. A fixed date and
    /// calendar, so this measures formatting and nothing else.
    func testFormattingADayKey() {
        let now = Date(timeIntervalSince1970: 1_787_000_000)
        timing("DayKey.key(for:calendar:)") {
            _ = DayKey.key(for: now, calendar: self.calendar)
        }
    }

    /// Parsing a day key back into a Date, with the strict round-trip check. This
    /// is what a freshly built `Schedule` does for its anchor, and the anchor is
    /// the same constant string every time.
    func testParsingTheFallbackAnchorDay() {
        timing("DayKey.date(from: fallbackAnchor)") {
            _ = DayKey.date(from: Recurrence.fallbackAnchorDay, calendar: self.calendar)
        }
    }

    /// Building the evaluation wrapper around a rule. Every schedule question
    /// starts here, and the progress pass asks several per habit.
    func testBuildingASchedule() {
        let rule = Recurrence.daily
        timing("Recurrence.schedule(calendar:)") {
            _ = rule.schedule(calendar: self.calendar)
        }
    }

    func testIsScheduledForOneHabit() {
        let habit = Habit(name: "Lesen", itemType: .habit, recurrence: .daily)
        let day = DayKey.key(for: Date(timeIntervalSince1970: 1_787_000_000),
                             calendar: calendar)
        let perCall = timing("GoalEngine.isScheduled") {
            _ = GoalEngine.isScheduled(habit: habit, day: day, calendar: self.calendar)
        }
        XCTAssertLessThan(perCall, 1, "one schedule question should be microseconds")
    }

    // MARK: - The sentence path

    /// Runs when a person presses "Satz lesen" or "Anlegen", so it sits on the
    /// critical path of the thing they just asked for.
    func testReadingASentenceWithoutTheModel() {
        let sentence = "morgens um 7 jeden Montag und Donnerstag Wasser trinken"
        let perCall = timing("stripTime(sentence)") {
            _ = CreateItemDraft.stripTime(from: sentence)
        }
        XCTAssertLessThan(perCall, 5, "a regex over one short sentence should be microseconds")
    }

    func testMappingAModelScheduleOntoARule() {
        timing("CreateItemSchedule.recurrence") {
            _ = CreateItemSchedule(
                frequency: "weekly", interval: 1, weekdays: [2, 4], timesPerPeriod: 0,
                dayOfMonth: 0, month: 0, startDay: "").recurrence
        }
    }

    // MARK: - Rendering a list

    /// Every card and row prints its rule, so this runs once per visible habit
    /// per render.
    func testDescribingManyRecurrences() {
        let rules: [Recurrence] = [
            .daily,
            Recurrence(frequency: .weekly, weekdays: [2, 4, 6]),
            Recurrence(frequency: .weekly, interval: 2, timesPerPeriod: 1),
            Recurrence(frequency: .monthly, rule: .dayOfMonth(15)),
            Recurrence(frequency: .yearly, rule: .dayOfMonth(24), month: 12),
        ]
        timing("RecurrenceText.pattern x5") {
            for rule in rules {
                _ = RecurrenceText.pattern(rule, calendar: self.calendar)
            }
        }
    }

    // MARK: - Where the sentence in a list row actually goes

    /// Broken out, because two plausible-sounding fixes did not move the number
    /// and guessing again would have been wasted work. `Calendar` already caches
    /// its own symbol arrays, so hoisting them was worth almost nothing.
    func testTheCostOfALocalizedString() {
        timing("String(localized:) literal") {
            _ = String(localized: "Jeden Tag")
        }
    }

    func testTheCostOfALocalizedStringWithInterpolation() {
        let weekday = "Montag"
        timing("String(localized:) interpolated") {
            _ = String(localized: "Jeden \(weekday)")
        }
    }

    func testTheCostOfAListFormatter() {
        let names = ["Montag", "Mittwoch", "Freitag"]
        timing("ListFormatter.string(from:)") {
            let formatter = ListFormatter()
            formatter.locale = self.calendar.locale ?? .current
            _ = formatter.string(from: names)
        }
    }

    func testTheCostOfWeekdaySymbols() {
        timing("calendar.weekdaySymbols") {
            _ = self.calendar.weekdaySymbols
        }
    }

    // MARK: - Correctness, so a cache cannot quietly change an answer

    /// A cache keyed on the wrong thing would hand back another timezone's
    /// calendar and move a habit to the wrong day. This is the assertion that
    /// makes the benchmark above safe to have.
    func testTimeZoneResolutionIsUnchangedByRepeatedCalls() {
        let berlin = HabitTimeZone.calendar(identifier: "Europe/Berlin", base: calendar)
        XCTAssertEqual(berlin.timeZone.identifier, "Europe/Berlin")

        // Inherited, explicit, "device", nil and nonsense all have to keep their
        // own answers no matter how often they are asked.
        XCTAssertEqual(HabitTimeZone.calendar(identifier: nil, base: calendar).timeZone,
                       calendar.timeZone)
        XCTAssertEqual(HabitTimeZone.calendar(identifier: "device", base: calendar).timeZone,
                       calendar.timeZone)
        XCTAssertNil(HabitTimeZone.sanitizedIdentifier("Not/AZone"))
        XCTAssertNil(HabitTimeZone.sanitizedIdentifier(nil))
        XCTAssertNil(HabitTimeZone.sanitizedIdentifier("   "))
        XCTAssertEqual(HabitTimeZone.sanitizedIdentifier("device"), "device")

        // A different base calendar must not be polluted by an earlier answer.
        var other = calendar
        other.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(HabitTimeZone.calendar(identifier: nil, base: other).timeZone.identifier,
                       "Asia/Tokyo")
        XCTAssertEqual(HabitTimeZone.calendar(identifier: "Europe/Berlin", base: other)
            .timeZone.identifier, "Europe/Berlin")
    }

    /// The progress pass has to agree with resolving each habit on its own.
    func testTheProgressPassAgreesWithPerHabitResolution() {
        let habits = makeHabits(Self.heavyHabitCount, zones: Self.zones)
        let now = Date(timeIntervalSince1970: 1_787_000_000)

        let whole = ScheduledProgress.today(habits: habits,
                                            defaultTimeZoneIdentifier: nil,
                                            now: now, calendar: calendar)
        var scheduled = 0, completed = 0, flexible = 0, flexibleCompleted = 0
        for habit in habits where habit.archivedAt == nil && habit.isTrackedHabit {
            let itemCalendar = HabitTimeZone.calendar(for: habit,
                                                      defaultIdentifier: nil,
                                                      base: calendar)
            let day = DayKey.key(for: now, calendar: itemCalendar)
            guard GoalEngine.isScheduled(habit: habit, day: day, calendar: itemCalendar) else { continue }
            if habit.recurrence.isFlexible {
                flexible += 1
                if GoalEngine.periodSatisfied(habit: habit, day: day, today: day,
                                              calendar: itemCalendar) { flexibleCompleted += 1 }
            } else {
                scheduled += 1
                if GoalEngine.dayCounts(habit: habit, day: day, calendar: itemCalendar) {
                    completed += 1
                }
            }
        }
        XCTAssertEqual(whole.scheduled, scheduled)
        XCTAssertEqual(whole.completed, completed)
        XCTAssertEqual(whole.flexible, flexible)
        XCTAssertEqual(whole.flexibleCompleted, flexibleCompleted)
    }
}
