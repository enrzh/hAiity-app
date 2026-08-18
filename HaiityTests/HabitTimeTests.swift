import XCTest
@testable import Haiity

/// Die Uhrzeit des Habits — eine EIGENSCHAFT des Termins („Laufen um
/// 07:30"), keine Benachrichtigung. Sie ist neu in v5 und deshalb an genau
/// den drei Stellen geprüft, an denen so ein Feld sonst verloren geht: auf
/// der Platte, im Satz und beim Zusammenführen zweier Geräte.
final class HabitTimeTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        return c
    }()

    // MARK: – Platte

    func testTimeSurvivesAFullRoundTrip() throws {
        let habit = Habit(name: "Laufen", timeMinutes: 7 * 60 + 30)
        let raw = try JSONEncoder().encode(habit)
        let back = try JSONDecoder().decode(Habit.self, from: raw)
        XCTAssertEqual(back.timeMinutes, 7 * 60 + 30)
    }

    func testNoTimeWritesNoKey() throws {
        let raw = try JSONEncoder().encode(Habit(name: "Laufen"))
        let text = String(data: raw, encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("timeMinutes"))
    }

    /// Eine Datei ohne den Schlüssel (jede ausgelieferte Version) lädt
    /// unverändert — die Uhrzeit ist schlicht nicht gesetzt.
    func testFileWithoutTheKeyDecodes() throws {
        let raw = """
        {"id":"\(UUID().uuidString)","name":"Lesen","emoji":"","createdAt":"2026-01-01","log":{}}
        """.data(using: .utf8)!
        let habit = try JSONDecoder().decode(Habit.self, from: raw)
        XCTAssertNil(habit.timeMinutes)
    }

    func testLegacyHabitDefaultsToCalendarSyncAndOptOutRoundTrips() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"Lesen","emoji":"","createdAt":"2026-01-01","log":{}}
        """.data(using: .utf8)!
        XCTAssertTrue(try JSONDecoder().decode(Habit.self, from: legacy).calendarSyncEnabled)

        var habit = Habit(name: "Privat")
        habit.calendarSyncEnabled = false
        let back = try JSONDecoder().decode(Habit.self, from: JSONEncoder().encode(habit))
        XCTAssertFalse(back.calendarSyncEnabled)
    }

    func testNotificationsDefaultOnAndOptOutRoundTrips() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"Lesen","emoji":"","createdAt":"2026-01-01","log":{}}
        """.data(using: .utf8)!
        XCTAssertTrue(try JSONDecoder().decode(Habit.self, from: legacy).notificationsEnabled)

        var habit = Habit(name: "Lesen")
        habit.notificationsEnabled = false
        let back = try JSONDecoder().decode(Habit.self, from: JSONEncoder().encode(habit))
        XCTAssertFalse(back.notificationsEnabled)
    }

    func testGarbageTimesAreDropped() throws {
        XCTAssertNil(Habit(name: "X", timeMinutes: 1500).timeMinutes)
        XCTAssertNil(Habit(name: "X", timeMinutes: -5).timeMinutes)
        let raw = """
        {"id":"\(UUID().uuidString)","name":"Lesen","emoji":"","createdAt":"2026-01-01",
         "log":{},"timeMinutes":99999}
        """.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(Habit.self, from: raw).timeMinutes)
    }

    func testMidnightIsAValidTime() {
        XCTAssertEqual(Habit(name: "X", timeMinutes: 0).timeMinutes, 0)
        XCTAssertEqual(RecurrenceText.timeText(0), "00:00")
        XCTAssertEqual(RecurrenceText.timeText(24 * 60 - 1), "23:59")
        XCTAssertNil(RecurrenceText.timeText(24 * 60))
        XCTAssertNil(RecurrenceText.timeText(nil))
    }

    // MARK: – Im Satz

    func testTimeAppearsInTheRecurrenceSentence() {
        XCTAssertEqual(RecurrenceText.summary(.weekdays([2]), timeMinutes: 7 * 60 + 30,
                                              calendar: calendar),
                       "Jeden Montag um 07:30")
        XCTAssertEqual(RecurrenceText.summary(.daily, timeMinutes: 6 * 60, calendar: calendar),
                       "Jeden Tag um 06:00")
    }

    /// Reihenfolge: erst das Muster, dann die Uhrzeit, dann das Ende — so
    /// liest es ein Mensch.
    func testTimeStandsBeforeTheEndClause() {
        let rule = Recurrence.weekdays([2], start: "2026-01-05", end: .on("2026-12-31"))
        XCTAssertEqual(RecurrenceText.summary(rule, timeMinutes: 7 * 60 + 30, calendar: calendar),
                       "Jeden Montag um 07:30, bis 31.12.2026")
    }

    func testWithoutATimeTheSentenceIsUnchanged() {
        XCTAssertEqual(RecurrenceText.summary(.weekdays([2]), calendar: calendar),
                       RecurrenceText.summary(.weekdays([2]), timeMinutes: nil, calendar: calendar))
    }

    func testAnImpossibleTimeNeverReachesTheSentence() {
        XCTAssertEqual(RecurrenceText.summary(.daily, timeMinutes: 4000, calendar: calendar),
                       "Jeden Tag")
    }

    // MARK: – Durch den Editor

    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 9))!
    }

    func testDraftCarriesTheTimeBothWays() {
        let draft = RecurrenceDraft(.weekdays([2]), timeMinutes: 7 * 60 + 30,
                                    today: today, calendar: calendar)
        XCTAssertTrue(draft.hasTime)
        XCTAssertEqual(draft.timeMinutes(calendar: calendar), 7 * 60 + 30)
        XCTAssertEqual(draft.summary(calendar: calendar), "Jeden Montag um 07:30")
    }

    func testDraftWithoutATimeStaysWithoutOne() {
        let draft = RecurrenceDraft(.weekdays([2]), today: today, calendar: calendar)
        XCTAssertFalse(draft.hasTime)
        XCTAssertNil(draft.timeMinutes(calendar: calendar))
        XCTAssertEqual(draft.summary(calendar: calendar), "Jeden Montag")
    }

    func testDraftRoundTripsOnceWithItsSelectedDateAndNoEndRule() {
        let selected = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        let rule = Recurrence(frequency: .once, start: "2026-10-12", end: .after(5))

        let draft = RecurrenceDraft(rule, today: today, calendar: calendar)

        XCTAssertEqual(draft.frequency, .once)
        XCTAssertEqual(draft.start, selected)
        XCTAssertTrue(draft.hasStart)

        let back = draft.recurrence(calendar: calendar)
        XCTAssertEqual(back.frequency, .once)
        XCTAssertEqual(back.start, "2026-10-12")
        XCTAssertEqual(back.end, .never)
    }

    /// Der Schalter allein genügt: er nimmt die Vorgabezeit mit, ohne dass
    /// der Nutzer am Rad drehen muss.
    func testSwitchingTheTimeOnUsesTheDefaultHour() {
        var draft = RecurrenceDraft(today: today, calendar: calendar)
        draft.hasTime = true
        XCTAssertEqual(draft.timeMinutes(calendar: calendar),
                       RecurrenceDraft.defaultHour * 60)
    }

    func testEditorSourceShowsOneDayBeforeDailyAndDropsEndTitleField() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Views/EditHabitSheet.swift"))

        let once = try XCTUnwrap(source.range(of: "Text(String(localized: \"Ein Tag\")).tag(Recurrence.Frequency.once)"))
        let daily = try XCTUnwrap(source.range(of: "Text(String(localized: \"Täglich\")).tag(Recurrence.Frequency.daily)"))

        XCTAssertLessThan(once.lowerBound, daily.lowerBound)
        XCTAssertFalse(source.contains("accessibilityIdentifier(\"end-title\")"))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"end-date\")"))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"end-count\")"))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"once-date\")"))
        XCTAssertTrue(source.contains(".datePickerStyle(.compact)"))
        XCTAssertTrue(source.contains("if draft.frequency != .once"))
        XCTAssertTrue(source.contains("itemType = .reminder"))
        XCTAssertFalse(source.contains("draft.hasStart = true"))
    }

    // MARK: – Zwei Geräte

    func testMergeCarriesTheTime() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("time-merge-\(UUID().uuidString).json")
        let store = HabitStore(url: url)
        let local = Habit(name: "Laufen")
        store.add(local)

        var remoteHabit = local
        remoteHabit.timeMinutes = 6 * 60 + 45
        let remote = HabitData(version: 2, updatedAt: Date().timeIntervalSince1970 + 999,
                               summaryMinutes: nil, habits: [remoteHabit])
        store.merge(remote: remote)
        XCTAssertEqual(store.habits.first?.timeMinutes, 6 * 60 + 45)
    }
}

/// **Bestandsschutz.** Zwei Einstellungen sind aus der Oberfläche
/// verschwunden (die Anzahl pro Periode und das Ende der Regel) und eine
/// dritte wird nicht mehr ausgewertet (die eigene Erinnerung je Habit). Alle
/// drei stehen weiterhin in ausgelieferten Dateien — diese Tests halten fest,
/// dass so eine Datei vollständig lädt, sich unverändert VERHÄLT und eine
/// Runde durch den Editor übersteht.
final class LegacyFieldsSurviveTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        return c
    }()

    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 9))!
    }

    /// Eine Datei aus v4: eigene Erinnerung um 19:00, Regel mit Enddatum.
    private func legacyHabitJSON(_ id: UUID) -> Data {
        """
        {"id":"\(id.uuidString)","name":"Lesen","emoji":"📚","createdAt":"2026-01-01",
         "reminderMinutes":1140,"log":{"2026-08-03":1},
         "goal":{"freq":"weekly","weekdays":[2],"start":"2026-01-05","endDate":"2026-12-31"}}
        """.data(using: .utf8)!
    }

    func testLegacyReminderMinutesStillDecodeAndAreKept() throws {
        let habit = try JSONDecoder().decode(Habit.self, from: legacyHabitJSON(UUID()))
        XCTAssertEqual(habit.reminderMinutes, 1140)
        // Und sie stehen nach einem Speichern immer noch da: ein Gerät mit
        // altem Build soll dieselbe Datei unverändert wiederfinden.
        let text = String(data: try JSONEncoder().encode(habit), encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("reminderMinutes"))
    }

    func testLegacyEndConditionStillLimitsTheSchedule() throws {
        let habit = try JSONDecoder().decode(Habit.self, from: legacyHabitJSON(UUID()))
        XCTAssertEqual(habit.recurrence.end, .on("2026-12-31"))
        XCTAssertTrue(habit.recurrence.isScheduled(on: "2026-08-10", calendar: calendar))
        XCTAssertFalse(habit.recurrence.isScheduled(on: "2027-01-04", calendar: calendar))
    }

    /// Der Editor zeigt das Ende nicht mehr an — er darf es aber auch nicht
    /// verlieren. Das ist der Weg, den „Bearbeiten, Sichern" nimmt.
    func testEndConditionSurvivesARoundTripThroughTheEditor() {
        for end in [Recurrence.End.on("2026-12-31"), .after(10)] {
            let rule = Recurrence.weekdays([2], start: "2026-01-05", end: end)
            let draft = RecurrenceDraft(rule, today: today, calendar: calendar)
            XCTAssertEqual(draft.recurrence(calendar: calendar).end, end)
        }
    }

    /// Dasselbe für das flexible Ziel: „3× pro Woche" lässt sich nicht mehr
    /// einstellen, muss aber eine Bearbeitung überleben — samt Verabredung.
    func testFlexibleGoalSurvivesARoundTripThroughTheEditor() {
        let rule = Recurrence.times(3, per: .weekly, weekdays: [3])
        let draft = RecurrenceDraft(rule, today: today, calendar: calendar)
        XCTAssertTrue(draft.flexible)
        let back = draft.recurrence(calendar: calendar)
        XCTAssertEqual(back.timesPerPeriod, 3)
        XCTAssertEqual(back.weekdays, [3])
        XCTAssertEqual(RecurrenceText.summary(back, calendar: calendar),
                       "3× pro Woche, gedacht am Dienstag")
    }

    /// Ein migriertes Alt-Ziel (`{"cadence":"weekly","times":2}`) bleibt
    /// flexibel — auch durch den Editor hindurch.
    func testMigratedLegacyGoalStaysFlexible() throws {
        let raw = """
        {"id":"\(UUID().uuidString)","name":"Sport","emoji":"","createdAt":"2026-01-01",
         "log":{},"goal":{"cadence":"weekly","times":2}}
        """.data(using: .utf8)!
        let habit = try JSONDecoder().decode(Habit.self, from: raw)
        XCTAssertEqual(habit.recurrence.timesPerPeriod, 2)
        let draft = RecurrenceDraft(habit.recurrence, today: today, calendar: calendar)
        XCTAssertEqual(draft.recurrence(calendar: calendar).timesPerPeriod, 2)
    }

    /// Und die Rechnung dahinter ist unverändert: zwei zählende Tage in der
    /// Woche erfüllen „2× pro Woche", egal an welchen Tagen.
    func testFlexibleGoalStillComputesTheSameWay() {
        var habit = Habit(name: "Sport", recurrence: .times(2, per: .weekly))
        habit.log["2026-08-04"] = 1
        habit.log["2026-08-06"] = 1
        XCTAssertTrue(GoalEngine.periodSatisfied(habit: habit, day: "2026-08-09",
                                                 today: "2026-08-09", calendar: calendar))
        XCTAssertEqual(GoalEngine.streak(habit: habit, today: "2026-08-09", calendar: calendar), 1)
    }
}

final class EditHabitSheetContractTests: XCTestCase {
    func testEditorExposesOneDayCadenceAndOnlyFiniteEndControls() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Views/EditHabitSheet.swift"))

        XCTAssertTrue(source.contains("$draft.endMode"))
        let once = try XCTUnwrap(source.range(of: "Text(String(localized: \"Ein Tag\")).tag(Recurrence.Frequency.once)"))
        let daily = try XCTUnwrap(source.range(of: "Text(String(localized: \"Täglich\")).tag(Recurrence.Frequency.daily)"))
        XCTAssertLessThan(once.lowerBound, daily.lowerBound)
        XCTAssertTrue(source.contains(".tag(RecurrenceDraft.EndMode.never)"))
        XCTAssertTrue(source.contains(".tag(RecurrenceDraft.EndMode.onDate)"))
        XCTAssertTrue(source.contains(".tag(RecurrenceDraft.EndMode.afterCount)"))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"end-date\")"))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"end-count\")"))
        XCTAssertFalse(source.contains("accessibilityIdentifier(\"end-title\")"))
        XCTAssertTrue(source.contains("displayedComponents: .date"))
        XCTAssertTrue(source.contains(".datePickerStyle(.compact)"))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"once-date\")"))
        XCTAssertTrue(source.contains("if draft.frequency != .once"))
        XCTAssertTrue(source.contains("itemType = .reminder"))
        XCTAssertTrue(source.contains("Text(String(localized: \"Ende\"))"))
        XCTAssertTrue(source.contains("$notificationsEnabled"))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"habit-notification-toggle\")"))
    }

    func testEndPickerKeepsOneUnstyledFormRow() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Views/EditHabitSheet.swift"))
        let group = try XCTUnwrap(source.range(of: "VStack(alignment: .leading, spacing: 8)"))
        let switchStart = try XCTUnwrap(source.range(of: "switch draft.endMode", range: group.upperBound..<source.endIndex))
        let endControls = source[group.lowerBound..<switchStart.lowerBound]

        XCTAssertTrue(endControls.contains("VStack(alignment: .leading"))
        XCTAssertTrue(endControls.contains("Picker(String(localized: \"Ende\")"))
        XCTAssertFalse(endControls.contains(".font(.headline)"))
        XCTAssertFalse(endControls.contains("Endtitel"))
    }
}
