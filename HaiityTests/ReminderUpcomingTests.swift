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

    // MARK: – Eigene Habit-Erinnerungen

    func testHabitPlansAreConcreteRecurrenceAwareAndSkipCompletedDays() {
        var habit = Habit(name: "Lesen", emoji: "📚", reminderMinutes: 18 * 60 + 15,
                          recurrence: .weekdays([2]))
        habit.log["2026-08-10"] = 1

        let plans = Reminders.habitPlans(habits: [habit], now: now, calendar: calendar)

        XCTAssertEqual(plans.map(\.identifier), [
            Reminders.habitReminderIdentifier(habitID: habit.id, day: "2026-08-17")
        ])
        XCTAssertEqual(plans.first?.dateMatching.hour, 18)
        XCTAssertEqual(plans.first?.dateMatching.minute, 15)
        XCTAssertEqual(plans.first?.title, "📚 Lesen")
        XCTAssertEqual(plans.first?.body, "Zeit für Lesen")
        XCTAssertFalse(plans.first?.repeats ?? true)
    }

    func testHabitPlansSuppressArchivedAndTodayAlreadyCompleted() {
        var archived = Habit(name: "Alt", reminderMinutes: 18 * 60)
        archived.archivedAt = "2026-08-01"
        var done = Habit(name: "Fertig", reminderMinutes: 18 * 60)
        done.log["2026-08-09"] = 1

        let plans = Reminders.habitPlans(habits: [archived, done], now: now, calendar: calendar)

        XCTAssertFalse(plans.map(\.identifier).contains(
            Reminders.habitReminderIdentifier(habitID: done.id, day: "2026-08-09")
        ))
        XCTAssertFalse(plans.contains { $0.identifier.contains(archived.id.uuidString) })
    }

    func testHabitReminderIdentifiersDoNotOverlapSummaryOrSessionIdentifiers() {
        let habitID = UUID()
        let identifier = Reminders.habitReminderIdentifier(habitID: habitID, day: "2026-08-10")
        let session = HabitSession(id: UUID(), habitID: habitID, day: "2026-08-09",
                                   startedAt: now, plannedMinutes: 30)

        XCTAssertNotEqual(identifier, Reminders.summaryId)
        XCTAssertNotEqual(identifier, Reminders.weeklySummaryId)
        XCTAssertFalse(identifier.hasPrefix(Reminders.sessionMilestonePrefix))
        XCTAssertNotEqual(Reminders.sessionMilestoneIdentifier(session), identifier)
    }

    func testSessionMilestoneUsesPlannedEndAndHasNoPlanWithoutDuration() {
        let session = HabitSession(id: UUID(), habitID: UUID(), day: "2026-08-09",
                                   startedAt: now, plannedMinutes: 30)
        let plan = Reminders.sessionMilestonePlan(session, calendar: calendar)

        XCTAssertEqual(plan?.identifier, Reminders.sessionMilestoneIdentifier(session))
        XCTAssertEqual(plan?.dateMatching, calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: now.addingTimeInterval(30 * 60)
        ))
        XCTAssertEqual(plan?.body, "Deine geplante Dauer ist erreicht.")
        XCTAssertNil(Reminders.sessionMilestonePlan(
            HabitSession(id: UUID(), habitID: UUID(), day: "2026-08-09", startedAt: now,
                         plannedMinutes: nil), calendar: calendar
        ))
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
