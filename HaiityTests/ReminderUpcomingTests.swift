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
        var habit = Habit(name: "Lesen", emoji: "📚", timeMinutes: 18 * 60 + 15,
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

    func testHabitPlansKeepLegacyReminderAsFallback() {
        let habit = Habit(name: "Alt", reminderMinutes: 18 * 60, recurrence: .daily)
        XCTAssertFalse(Reminders.habitPlans(habits: [habit], now: now, calendar: calendar).isEmpty)
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
        // MIT Sekunden: ohne sie feuerte der Meilenstein zur vollen Minute —
        // bei einem Start um hh:mm:45 bis zu 45 Sekunden zu früh.
        XCTAssertEqual(plan?.dateMatching, calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: now.addingTimeInterval(30 * 60)
        ))
        XCTAssertEqual(plan?.body, "Deine geplante Dauer ist erreicht.")
        XCTAssertNil(Reminders.sessionMilestonePlan(
            HabitSession(id: UUID(), habitID: UUID(), day: "2026-08-09", startedAt: now,
                         plannedMinutes: nil), calendar: calendar
        ))
    }

    // MARK: – v16: flexible Regeln erinnern nicht mehr täglich

    /// „1× pro Woche, dienstags": die Wochentagsmenge neben einem flexiblen
    /// Ziel ist die VERABREDUNG — genau sie steuert die Erinnerung. Vorher
    /// klingelte so ein Habit an allen sieben Tagen (isScheduled ist in der
    /// Periode überall wahr).
    func testFlexibleWeeklyRemindsOnlyOnAgreedWeekdays() {
        let habit = Habit(name: "Yoga", timeMinutes: 18 * 60,
                          recurrence: .times(1, per: .weekly, weekdays: [3]))

        let plans = Reminders.habitPlans(habits: [habit], now: now, calendar: calendar)

        // Fixture: So 09.08. Der einzige Dienstag im Fenster ist der 11.08.
        XCTAssertEqual(plans.map(\.identifier), [
            Reminders.habitReminderIdentifier(habitID: habit.id, day: "2026-08-11")
        ])
    }

    /// Eine ERFÜLLTE Periode schweigt: „1× pro Woche" mit einem Check-in am
    /// Mittwoch erinnert nicht mehr am Sonntag derselben Woche — erst die
    /// nächste Periode ist wieder dran.
    func testFlexibleWeeklySilencesASatisfiedPeriod() {
        var habit = Habit(name: "Schwimmen", timeMinutes: 18 * 60,
                          recurrence: .times(1, per: .weekly))
        habit.log["2026-08-05"] = 1

        let plans = Reminders.habitPlans(habits: [habit], now: now, calendar: calendar)
        let days = plans.map { String($0.identifier.suffix(10)) }

        XCTAssertFalse(days.contains("2026-08-09"),
                       "erfüllte Periode darf heute nicht mehr erinnern")
        XCTAssertEqual(days.first, "2026-08-10")
        // Fenster heute+8: 10.–17.08., alle in noch unerfüllten Perioden.
        XCTAssertEqual(days.count, 8)
    }

    /// Das 64er-Budget des Systems läuft nicht mehr stumm über: ab sechs
    /// Habits mit Uhrzeit schrumpft das Voraus-Fenster, statt dass iOS die
    /// hintersten Anfragen wegwirft.
    func testReminderWindowShrinksWithManyTimedHabits() {
        XCTAssertEqual(Reminders.reminderWindow(timedHabitCount: 0), 9)
        XCTAssertEqual(Reminders.reminderWindow(timedHabitCount: 1), 9)
        XCTAssertEqual(Reminders.reminderWindow(timedHabitCount: 5), 9)
        XCTAssertEqual(Reminders.reminderWindow(timedHabitCount: 6), 8)
        XCTAssertEqual(Reminders.reminderWindow(timedHabitCount: 10), 5)
        XCTAssertEqual(Reminders.reminderWindow(timedHabitCount: 64), 1)
    }

    // MARK: – v16: die Wochenmeldung fällt nicht mehr aus

    /// Montag geöffnet, Termin am Freitag: „bis heute" wäre die Woche leer
    /// und der (wiederholende!) Wochen-Wecker würde gelöscht und nie neu
    /// gestellt — die Meldung fiele für die ganze Woche aus. `fullWeek`
    /// zählt Geschuldetes über die ganze Woche; erfüllt wird weiter nur,
    /// was im Log steht.
    func testWeeklyStatusFullWeekKeepsAnEarlyWeekLaunchHonest() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reminder-fullweek-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url)
        store.add(Habit(name: "Freitags", recurrence: .weekdays([6])))
        let monday = "2026-08-03"

        let toDate = store.weeklyStatus(monday, calendar: calendar)
        XCTAssertEqual(toDate.total, 0)
        XCTAssertNil(Reminders.weeklySummaryPlan(minutes: 18 * 60, weekday: 1,
                                                 status: toDate, calendar: calendar))

        let full = store.weeklyStatus(monday, calendar: calendar, fullWeek: true)
        XCTAssertEqual(full.total, 1)
        XCTAssertEqual(full.done, 0)
        XCTAssertEqual(full.missing, ["Freitags"])
        XCTAssertNotNil(Reminders.weeklySummaryPlan(minutes: 18 * 60, weekday: 1,
                                                    status: full, calendar: calendar))
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
