import XCTest
@testable import Haiity

/// Die VORAUS geplanten Tagesmeldungen (v11): ohne sie war die
/// Tageszusammenfassung ein einmaliger Wecker, den nur ein App-Start am
/// selben Tag vor der Uhrzeit stellte — drei Tage App zu hieß drei Tage
/// Stille. Hier steht die pure Planung fest: welche Tage einen Wecker
/// bekommen, welche bewusst keinen, und was auf ihm steht.
final class ReminderUpcomingTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        c.locale = Locale(identifier: "de_DE")
        return c
    }()

    /// So, 09.08.2026, 12:00 — Fixture-Wochenlage wie in SummaryTests.
    private var now: Date {
        DayKey.date(from: "2026-08-09", calendar: calendar)!.addingTimeInterval(12 * 3600)
    }

    private func habit(_ name: String, _ recurrence: Recurrence) -> Habit {
        Habit(name: name, recurrence: recurrence)
    }

    func testDailyHabitGetsOnePlanPerUpcomingDay() {
        let plans = Reminders.upcomingDailyPlans(minutes: 20 * 60,
                                                 habits: [habit("Laufen", .daily)],
                                                 now: now, calendar: calendar)
        XCTAssertEqual(plans.count, Reminders.upcomingDays)
        // Der erste Wecker gilt MORGEN — heute deckt der echte Stand ab.
        XCTAssertEqual(plans.first?.identifier, Reminders.upcomingPrefix + "2026-08-10")
        XCTAssertEqual(plans.last?.identifier, Reminders.upcomingPrefix + "2026-08-16")
        for plan in plans {
            XCTAssertFalse(plan.repeats)
            XCTAssertEqual(plan.dateMatching.hour, 20)
            XCTAssertEqual(plan.dateMatching.minute, 0)
            XCTAssertNotNil(plan.dateMatching.year, "einmaliger Wecker braucht das volle Datum")
            XCTAssertEqual(plan.body, "Heute fällig: Laufen")
        }
    }

    func testDaysWithoutAnythingDueGetNoPlan() {
        // Nur montags: in den nächsten 7 Tagen ist genau der 10.08. ein Montag.
        let plans = Reminders.upcomingDailyPlans(minutes: 9 * 60 + 30,
                                                 habits: [habit("Lesen", .weekdays([2]))],
                                                 now: now, calendar: calendar)
        XCTAssertEqual(plans.map(\.identifier), [Reminders.upcomingPrefix + "2026-08-10"])
        XCTAssertEqual(plans.first?.dateMatching.minute, 30)
    }

    func testBodyListsAllDueHabitsOfThatDay() {
        let plans = Reminders.upcomingDailyPlans(minutes: 20 * 60,
                                                 habits: [habit("Laufen", .daily),
                                                          habit("Lesen", .weekdays([2]))],
                                                 now: now, calendar: calendar)
        let monday = plans.first { $0.identifier == Reminders.upcomingPrefix + "2026-08-10" }
        XCTAssertEqual(monday?.body, "Heute fällig: Laufen und Lesen")
    }

    func testArchivedHabitsScheduleNothing() {
        var archived = habit("Alt", .daily)
        archived.archivedAt = "2026-08-01"
        XCTAssertTrue(Reminders.upcomingDailyPlans(minutes: 20 * 60, habits: [archived],
                                                   now: now, calendar: calendar).isEmpty)
    }

    func testDisabledOrInvalidTimeSchedulesNothing() {
        let habits = [habit("Laufen", .daily)]
        XCTAssertTrue(Reminders.upcomingDailyPlans(minutes: nil, habits: habits,
                                                   now: now, calendar: calendar).isEmpty)
        XCTAssertTrue(Reminders.upcomingDailyPlans(minutes: 24 * 60, habits: habits,
                                                   now: now, calendar: calendar).isEmpty)
        XCTAssertTrue(Reminders.upcomingDailyPlans(minutes: -1, habits: habits,
                                                   now: now, calendar: calendar).isEmpty)
    }

    func testIdentifiersAreDistinctFromTodayAndWeekly() {
        let plans = Reminders.upcomingDailyPlans(minutes: 20 * 60,
                                                 habits: [habit("Laufen", .daily)],
                                                 now: now, calendar: calendar)
        // reschedule löscht per Präfix — die festen Kennungen dürfen ihm
        // nicht in die Quere kommen (und umgekehrt).
        XCTAssertFalse(plans.map(\.identifier).contains(Reminders.summaryId))
        XCTAssertFalse(plans.map(\.identifier).contains(Reminders.weeklySummaryId))
        XCTAssertFalse(Reminders.summaryId.hasPrefix(Reminders.upcomingPrefix))
        XCTAssertFalse(Reminders.testId.hasPrefix(Reminders.upcomingPrefix))
        XCTAssertEqual(Set(plans.map(\.identifier)).count, plans.count)
    }

    // MARK: – Prospektiver Satz

    func testUpcomingTextNamesTheDueHabits() {
        XCTAssertEqual(SummaryText.upcoming(["Laufen"], locale: Locale(identifier: "de_DE")),
                       "Heute fällig: Laufen")
        XCTAssertEqual(SummaryText.upcoming(["A", "B", "C", "D", "E"],
                                            locale: Locale(identifier: "de_DE")),
                       "Heute fällig: A, B, C und 2 weitere")
    }

    func testUpcomingTextIsNilWhenNothingIsDue() {
        XCTAssertNil(SummaryText.upcoming([]))
    }
}

/// Das App-Icon-Auswahlraster (v11): die pure Abbildung zwischen dem, was
/// iOS als `alternateIconName` meldet, und der Familie, die im Raster
/// markiert wird.
final class AppIconPickerTests: XCTestCase {
    func testIconNameRoundTripsForEveryPalette() {
        for palette in GraphPalette.allCases {
            XCTAssertEqual(AppIcons.palette(forIconName: AppIcons.name(for: palette)), palette)
        }
    }

    func testUnknownIconNameFallsBackToDefault() {
        XCTAssertEqual(AppIcons.palette(forIconName: "AppIcon-Petrol"), .default)
    }

    func testNilMeansThePrimaryGreenIcon() {
        XCTAssertEqual(AppIcons.palette(forIconName: nil), .green)
    }

    func testEveryPaletteHasAThumbnailAssetName() {
        // Das Raster lädt die Icons per UIImage(named:) — der Name des
        // Primär-Icons ist "AppIcon", alle anderen ihr Katalogname.
        XCTAssertEqual(AppIcons.assetName(for: .green), "AppIcon")
        for palette in GraphPalette.allCases where palette != .green {
            XCTAssertEqual(AppIcons.assetName(for: palette), AppIcons.name(for: palette))
        }
    }
}
