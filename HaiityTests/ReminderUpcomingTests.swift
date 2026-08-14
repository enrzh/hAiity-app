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

    /// Das 64er-Budget des Systems läuft nicht mehr stumm über: ab fünf
    /// Habits mit Uhrzeit schrumpft das Voraus-Fenster, statt dass iOS die
    /// hintersten Anfragen wegwirft.
    ///
    /// Die Grenze wanderte von sechs auf fünf, als die sieben
    /// Motivationsnachrichten in die feste Rechnung kamen: den Habits
    /// bleiben seither 43 statt 50 Anfragen.
    func testReminderWindowShrinksWithManyTimedHabits() {
        XCTAssertEqual(Reminders.habitRequestBudget(reservingMotivation: true), 43)
        XCTAssertEqual(Reminders.reminderWindow(timedHabitCount: 0,
                                                reservingMotivation: true), 9)
        XCTAssertEqual(Reminders.reminderWindow(timedHabitCount: 1,
                                                reservingMotivation: true), 9)
        XCTAssertEqual(Reminders.reminderWindow(timedHabitCount: 4,
                                                reservingMotivation: true), 9)
        XCTAssertEqual(Reminders.reminderWindow(timedHabitCount: 5,
                                                reservingMotivation: true), 8)
        XCTAssertEqual(Reminders.reminderWindow(timedHabitCount: 6,
                                                reservingMotivation: true), 7)
        XCTAssertEqual(Reminders.reminderWindow(timedHabitCount: 10,
                                                reservingMotivation: true), 4)
        XCTAssertEqual(Reminders.reminderWindow(timedHabitCount: 64,
                                                reservingMotivation: true), 1)
    }

    func testDisabledMotivationDoesNotReduceTheExistingHabitWindow() {
        XCTAssertEqual(Reminders.reminderWindow(timedHabitCount: 5), 9,
                       "an opt-in feature must not consume slots while disabled")
    }

    /// Der Deckel als RECHNUNG, nicht als Zuversicht: für jede Anzahl von
    /// Habits mit Uhrzeit muss die Gesamtzahl anstehender Anfragen unter 64
    /// bleiben — feste Anfragen plus Habit-Wecker.
    ///
    /// Das Fenster allein genügt dafür nicht: es fällt nie unter einen Tag,
    /// also ergäben 50 Habits ohne den zusätzlichen Gesamt-Deckel in
    /// `habitPlans` genau 50 Anfragen und damit 69 insgesamt. Genau diese
    /// Lücke hält der Test zu.
    func testWorstCaseRequestCountStaysUnderTheSystemLimit() {
        for reservingMotivation in [false, true] {
            let fixed = Reminders.fixedRequestEstimate(
                reservingMotivation: reservingMotivation)
            let budget = Reminders.habitRequestBudget(
                reservingMotivation: reservingMotivation)
            for count in 0...80 {
                let habits = (0..<count).map {
                    Habit(name: "H\($0)", timeMinutes: 20 * 60, recurrence: .daily)
                }
                let habitRequests = Reminders.habitPlans(
                    habits: habits, reservingMotivation: reservingMotivation,
                    now: now, calendar: calendar).count
                XCTAssertLessThanOrEqual(habitRequests, budget,
                                         "\(count) Habits mit Uhrzeit")
                XCTAssertLessThanOrEqual(habitRequests + fixed,
                                         Reminders.pendingBudget,
                                         "\(count) Habits mit Uhrzeit")
            }
        }
    }

    // MARK: – Die tägliche Motivationsnachricht

    /// Eine Anfrage JE TAG, keine wiederholende: nur so trägt jeder Tag
    /// seinen eigenen Satz. Heute ist mit dabei, solange die Uhrzeit noch
    /// bevorsteht (Fixture: 12:00, Nachricht um 20:00).
    func testMotivationPlansOnePerDayWithFullDates() {
        let plans = Reminders.motivationPlans(minutes: 20 * 60, name: nil,
                                              now: now, calendar: calendar)
        XCTAssertEqual(plans.count, Reminders.motivationDays)
        XCTAssertEqual(plans.first?.identifier, Reminders.motivationId(day: "2026-08-09"))
        XCTAssertEqual(plans.last?.identifier, Reminders.motivationId(day: "2026-08-15"))
        for plan in plans {
            XCTAssertFalse(plan.repeats, "wiederholend zeigte ewig denselben Satz")
            XCTAssertNotNil(plan.dateMatching.year, "einmaliger Wecker braucht das volle Datum")
            XCTAssertEqual(plan.dateMatching.hour, 20)
            XCTAssertEqual(plan.dateMatching.minute, 0)
            XCTAssertFalse(plan.body.isEmpty)
            XCTAssertFalse(plan.title.contains("%@"), "Platzhalter darf nie sichtbar werden")
        }
        // Der Vorrat ist der Grund für die Tagesanfragen: die Sätze der
        // sieben Tage dürfen nicht alle gleich sein.
        XCTAssertGreaterThan(Set(plans.map(\.body)).count, 1)
    }

    /// Der Tag, dessen Uhrzeit vorbei ist, fällt heraus — sonst stellte die
    /// App einen Wecker in die Vergangenheit, den iOS sofort verwirft.
    func testMotivationSkipsTodayWhenTheTimeHasPassed() {
        let plans = Reminders.motivationPlans(minutes: 9 * 60, name: nil,
                                              now: now, calendar: calendar)
        XCTAssertEqual(plans.count, Reminders.motivationDays - 1)
        XCTAssertEqual(plans.first?.identifier, Reminders.motivationId(day: "2026-08-10"))
    }

    /// Aus = keine einzige Anfrage; kaputte Uhrzeiten ebenso.
    func testMotivationDisabledOrInvalidPlansNothing() {
        XCTAssertTrue(Reminders.motivationPlans(minutes: nil, name: "Mo",
                                                now: now, calendar: calendar).isEmpty)
        XCTAssertTrue(Reminders.motivationPlans(minutes: -1, name: "Mo",
                                                now: now, calendar: calendar).isEmpty)
        XCTAssertTrue(Reminders.motivationPlans(minutes: 24 * 60, name: "Mo",
                                                now: now, calendar: calendar).isEmpty)
        XCTAssertTrue(Reminders.motivationPlans(minutes: 20 * 60, name: "Mo", days: 0,
                                                now: now, calendar: calendar).isEmpty)
    }

    /// Mit Namen die %@-Fassung, ohne die neutrale — und die Zeile bleibt
    /// in beiden Fällen dieselbe, weil nur die Anrede den Namen kennt.
    func testMotivationUsesTheNameOnlyInTheTitle() {
        let withName = Reminders.motivationPlans(minutes: 20 * 60, name: "Mo",
                                                 now: now, calendar: calendar)
        let without = Reminders.motivationPlans(minutes: 20 * 60, name: nil,
                                                now: now, calendar: calendar)
        XCTAssertEqual(withName.map(\.body), without.map(\.body))
        XCTAssertEqual(withName.map(\.identifier), without.map(\.identifier))
        XCTAssertTrue(withName.allSatisfy { $0.title.contains("Mo") })
        XCTAssertTrue(without.allSatisfy { !$0.title.contains("%@") })
    }

    /// Die Kennung trägt den Tag — daran hängt sowohl das Ersetzen beim
    /// Umstellen der Uhrzeit als auch das Aufräumen beim Ausschalten.
    func testMotivationIdentifiersCarryTheDayAndSharePrefix() {
        XCTAssertEqual(Reminders.motivationId(day: "2026-08-09"), "motivation-2026-08-09")
        let plans = Reminders.motivationPlans(minutes: 20 * 60, name: nil,
                                              now: now, calendar: calendar)
        XCTAssertTrue(plans.allSatisfy { $0.identifier.hasPrefix(Reminders.motivationPrefix) })
        XCTAssertEqual(Set(plans.map(\.identifier)).count, plans.count, "keine Kennung doppelt")
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

/// Das App-Icon-Auswahlraster (v11, seit v22 namensbasiert): die pure
/// Abbildung zwischen dem, was iOS als `alternateIconName` meldet, und der
/// Miniatur-Farbtafel, mit der die Zelle im Raster gemalt wird.
final class AppIconPickerTests: XCTestCase {
    func testStyleRoundTripsForEveryPalette() {
        for palette in GraphPalette.allCases {
            XCTAssertEqual(AppIcons.style(forIconName: AppIcons.name(for: palette)),
                           palette.style, palette.rawValue)
        }
    }

    func testStyleRoundTripsForEveryHueIcon() {
        for hue in AppIcons.hues {
            XCTAssertEqual(AppIcons.style(forIconName: hue.name), hue.style, hue.name)
        }
    }

    func testUnknownIconNameFallsBackToTheGreenStyle() {
        // Kaputter Stand oder künftiges Icon: die Miniatur malt Grün, weil
        // nil ohnehin „Primär-Icon" heißt.
        XCTAssertEqual(AppIcons.style(forIconName: "AppIcon-Petrol"), GraphPalette.green.style)
        XCTAssertEqual(AppIcons.style(forIconName: nil), GraphPalette.green.style)
    }

    func testHueIconNamesFollowTheCatalogPattern() {
        XCTAssertEqual(AppIcons.hues.count, 12)
        XCTAssertEqual(AppIcons.hues.map(\.degrees), Array(stride(from: 0, to: 360, by: 30)))
        for hue in AppIcons.hues {
            XCTAssertTrue(hue.name.hasPrefix("AppIcon-H"), hue.name)
            XCTAssertEqual(hue.name.count, "AppIcon-H000".count, hue.name)
        }
    }
}
