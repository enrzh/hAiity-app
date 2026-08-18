import XCTest
@testable import Haiity

/// Der SATZ, den die beiden Zusammenfassungen tragen. Er ist das Einzige,
/// was der Nutzer von der ganzen Rechnung je zu sehen bekommt — deshalb steht
/// er hier Wort für Wort fest, wie der Regel-Satz in `RecurrenceTextTests`.
final class SummaryTextTests: XCTestCase {
    private let locale = Locale(identifier: "de_DE")

    private func status(_ done: Int, _ total: Int, _ missing: [String]) -> SummaryStatus {
        SummaryStatus(done: done, total: total, missing: missing)
    }

    // MARK: – Namensliste

    func testOneNameStandsAlone() {
        XCTAssertEqual(SummaryText.nameList(["Laufen"], locale: locale), "Laufen")
    }

    func testTwoNamesGetAnAnd() {
        XCTAssertEqual(SummaryText.nameList(["Laufen", "Lesen"], locale: locale),
                       "Laufen und Lesen")
    }

    /// Genau die Grenze steht noch vollständig da — abgeschnitten wird erst
    /// ab dem einen Namen zu viel.
    func testExactlyTheLimitIsNotTruncated() {
        let names = ["Laufen", "Lesen", "Meditation"]
        XCTAssertEqual(SummaryText.nameList(names, locale: locale),
                       "Laufen, Lesen und Meditation")
    }

    /// Der EINE Name zu viel wird noch ausgeschrieben — „und 1 weiteres"
    /// wäre länger als „und Wasser" und sagte weniger.
    func testOneOverTheLimitIsStillSpelledOut() {
        let names = ["Laufen", "Lesen", "Meditation", "Wasser"]
        XCTAssertEqual(SummaryText.nameList(names, locale: locale),
                       "Laufen, Lesen, Meditation und Wasser")
    }

    func testLongListIsTruncatedWithACount() {
        let names = ["A", "B", "C", "D", "E", "F", "G"]
        // Drei Namen plus „4 weitere" — nie sieben Namen auf dem
        // Sperrbildschirm.
        XCTAssertEqual(SummaryText.nameList(names, locale: locale), "A, B, C und 4 weitere")
    }

    func testEmptyListIsEmpty() {
        XCTAssertEqual(SummaryText.nameList([], locale: locale), "")
    }

    // MARK: – Tag

    func testDailyNothingScheduledSaysNothing() {
        // Der wichtigste Fall: kein Termin heißt keine Meldung.
        XCTAssertNil(SummaryText.daily(status(0, 0, []), locale: locale))
    }

    func testDailyAllDone() {
        XCTAssertEqual(SummaryText.daily(status(5, 5, []), locale: locale),
                       "Alles erledigt — 5 von 5.")
    }

    func testDailyNoneDone() {
        XCTAssertEqual(SummaryText.daily(status(0, 2, ["Laufen", "Lesen"]), locale: locale),
                       "0 von 2 erledigt · offen: Laufen und Lesen")
    }

    func testDailyPartial() {
        XCTAssertEqual(SummaryText.daily(status(3, 5, ["Laufen", "Meditation"]), locale: locale),
                       "3 von 5 erledigt · offen: Laufen und Meditation")
    }

    func testDailyTruncatesALongOpenList() {
        let open = ["Laufen", "Lesen", "Meditation", "Wasser", "Dehnen"]
        XCTAssertEqual(SummaryText.daily(status(1, 6, open), locale: locale),
                       "1 von 6 erledigt · offen: Laufen, Lesen, Meditation und 2 weitere")
    }

    // MARK: – Woche

    func testWeeklyNothingDueSaysNothing() {
        XCTAssertNil(SummaryText.weekly(status(0, 0, []), locale: locale))
    }

    func testWeeklyFullWeek() {
        XCTAssertEqual(SummaryText.weekly(status(18, 18, []), locale: locale),
                       "Volle Woche — 18 von 18 Terminen.")
    }

    func testWeeklyPartialNamesTheStragglers() {
        XCTAssertEqual(SummaryText.weekly(status(12, 18, ["Laufen", "Meditation"]), locale: locale),
                       "12 von 18 Terminen · offen: Laufen und Meditation")
    }

    func testWeeklyTruncatesALongList() {
        let behind = ["A", "B", "C", "D", "E"]
        XCTAssertEqual(SummaryText.weekly(status(2, 20, behind), locale: locale),
                       "2 von 20 Terminen · offen: A, B, C und 2 weitere")
    }
}

/// Woher die Zahlen kommen. Der Text oben ist nur so gut wie diese Rechnung:
/// sie entscheidet, WAS überhaupt als fällig zählt.
final class SummaryStatusTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2                       // Woche beginnt Montag
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        return c
    }()

    /// So, 09.08.2026 — das Ende einer Woche, die am Mo 03.08. begann.
    private let today = "2026-08-09"

    private func store(_ habits: [Habit]) -> HabitStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("summary-\(UUID().uuidString).json")
        let s = HabitStore(url: url)
        for h in habits { s.add(h) }
        return s
    }

    private func habit(_ name: String,
                       _ recurrence: Recurrence,
                       done days: [String] = []) -> Habit {
        var h = Habit(name: name, recurrence: recurrence)
        for day in days { h.log[day] = 1 }
        return h
    }

    // MARK: – Tag

    func testDailyStatusCountsOnlyWhatIsScheduledToday() {
        // Sonntag: „Laufen" ist täglich (fällig, offen), „Lesen" nur montags
        // (nicht fällig, steht in keiner Zahl), „Wasser" ist täglich und
        // erledigt.
        let s = store([habit("Laufen", .daily),
                       habit("Lesen", .weekdays([2])),
                       habit("Wasser", .daily, done: [today])])
        let status = s.dailyStatus(today, calendar: calendar)
        XCTAssertEqual(status.total, 2)
        XCTAssertEqual(status.done, 1)
        XCTAssertEqual(status.missing, ["Laufen"])
    }

    func testDailyStatusIsEmptyWhenNothingIsDue() {
        let s = store([habit("Lesen", .weekdays([2]))])   // nur montags
        let status = s.dailyStatus(today, calendar: calendar)
        XCTAssertTrue(status.isEmpty)
        XCTAssertNil(SummaryText.daily(status))
    }

    func testArchivedHabitsAreNotInTheSummary() {
        var archived = habit("Alt", .daily)
        archived.archivedAt = "2026-08-01"
        let s = store([archived])
        XCTAssertTrue(s.dailyStatus(today, calendar: calendar).isEmpty)
    }

    func testReminderItemsAreNotInDailyOrWeeklySummaries() {
        var reminder = Habit(name: "Tabletten", itemType: .reminder)
        reminder.log[today] = 1
        let s = store([habit("Lesen", .daily), reminder])

        XCTAssertEqual(s.dailyStatus(today, calendar: calendar).missing, ["Lesen"])
        XCTAssertEqual(s.dailyStatus(today, calendar: calendar).total, 1)
        XCTAssertEqual(s.weeklyStatus(today, calendar: calendar).missing, ["Lesen"])
        XCTAssertEqual(s.weeklyStatus(today, calendar: calendar).total, 7)
    }

    /// Mengenziele zählen erst ab dem Ziel als erledigt — dieselbe Semantik
    /// wie im Raster.
    func testQuantityHabitCountsOnlyAtItsTarget() {
        var h = habit("Wasser", Recurrence(frequency: .daily, target: 3))
        h.log[today] = 2
        let s = store([h])
        XCTAssertEqual(s.dailyStatus(today, calendar: calendar).missing, ["Wasser"])
        s.setValue(h.id, day: today, value: 3)
        XCTAssertEqual(s.dailyStatus(today, calendar: calendar).done, 1)
    }

    // MARK: – Woche

    func testWeeklyStatusCountsDueOccurrencesUpToToday() {
        // Mo/Mi/Fr in der Woche 03.–09.08.: drei fällige Termine, zwei
        // gehalten.
        let s = store([habit("Sport", .weekdays([2, 4, 6]),
                             done: ["2026-08-03", "2026-08-05"])])
        let status = s.weeklyStatus(today, calendar: calendar)
        XCTAssertEqual(status.total, 3)
        XCTAssertEqual(status.done, 2)
        XCTAssertEqual(status.missing, ["Sport"])
    }

    func testWeeklyStatusSumsOverHabits() {
        let s = store([habit("Sport", .weekdays([2]), done: ["2026-08-03"]),
                       habit("Lesen", .weekdays([3, 5]), done: ["2026-08-04", "2026-08-06"])])
        let status = s.weeklyStatus(today, calendar: calendar)
        XCTAssertEqual(status.total, 3)
        XCTAssertEqual(status.done, 3)
        XCTAssertTrue(status.missing.isEmpty)
        XCTAssertEqual(SummaryText.weekly(status, locale: Locale(identifier: "de_DE")),
                       "Volle Woche — 3 von 3 Terminen.")
    }

    /// „3× pro Woche" schuldet DREI Termine, nicht sieben — sonst stünde ein
    /// flexibles Ziel jede Woche als Totalausfall da.
    func testFlexibleWeeklyGoalOwesItsCountNotSevenDays() {
        let s = store([habit("Joggen", .times(3, per: .weekly),
                             done: ["2026-08-04", "2026-08-07"])])
        let status = s.weeklyStatus(today, calendar: calendar)
        XCTAssertEqual(status.total, 3)
        XCTAssertEqual(status.done, 2)
        XCTAssertEqual(status.missing, ["Joggen"])
    }

    /// Mehrleistung sprengt die Bilanz nicht: vier Läufe bei einem Ziel von
    /// drei sind 3 von 3.
    func testFlexibleGoalIsCappedAtItsTarget() {
        let s = store([habit("Joggen", .times(3, per: .weekly),
                             done: ["2026-08-03", "2026-08-04", "2026-08-05", "2026-08-06"])])
        let status = s.weeklyStatus(today, calendar: calendar)
        XCTAssertEqual(status.total, 3)
        XCTAssertEqual(status.done, 3)
        XCTAssertTrue(status.missing.isEmpty)
    }

    /// „5× pro Monat" ist keine Wochenschuld und steht deshalb gar nicht in
    /// der Wochenbilanz.
    func testMonthlyFlexibleGoalStaysOutOfTheWeek() {
        let s = store([habit("Putzen", .times(5, per: .monthly))])
        XCTAssertTrue(s.weeklyStatus(today, calendar: calendar).isEmpty)
    }

    func testWeeklyStatusIgnoresDaysBeforeTheWeekStarted() {
        // Der Check-in vom Sonntag DAVOR (02.08.) darf die laufende Woche
        // nicht auffüllen.
        let s = store([habit("Sport", .weekdays([2]), done: ["2026-07-27"])])
        let status = s.weeklyStatus(today, calendar: calendar)
        XCTAssertEqual(status.total, 1)
        XCTAssertEqual(status.done, 0)
    }
}

/// Aus Zahlen wird ein Weckruf: WANN und in welcher Form. Reine
/// Datenrechnung, ohne `UNUserNotificationCenter`.
final class SummaryPlanTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        return c
    }()

    /// So, 09.08.2026, 18:00 Ortszeit.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 9, hour: 18))!
    }

    private let open = SummaryStatus(done: 3, total: 5, missing: ["Laufen", "Meditation"])

    // MARK: – Tag

    func testDailyPlanNeedsAFutureTime() {
        // 17:00 ist um 18:00 vorbei — dann steht heute nichts mehr an.
        XCTAssertNil(Reminders.dailySummaryPlan(minutes: 17 * 60, status: open,
                                                now: now, calendar: calendar))
    }

    func testDailyPlanNeedsTheSettingOn() {
        XCTAssertNil(Reminders.dailySummaryPlan(minutes: nil, status: open,
                                                now: now, calendar: calendar))
    }

    func testDailyPlanIsSkippedWhenNothingIsDue() {
        let empty = SummaryStatus(done: 0, total: 0, missing: [])
        XCTAssertNil(Reminders.dailySummaryPlan(minutes: 20 * 60, status: empty,
                                                now: now, calendar: calendar))
    }

    func testDailyPlanCarriesTheSummaryAsItsBody() {
        let plan = Reminders.dailySummaryPlan(minutes: 20 * 60, status: open,
                                              now: now, calendar: calendar)
        XCTAssertEqual(plan?.identifier, Reminders.summaryId)
        XCTAssertEqual(plan?.repeats, false)
        XCTAssertEqual(plan?.isOneShot, true)
        XCTAssertEqual(plan?.dateMatching.hour, 20)
        XCTAssertEqual(plan?.dateMatching.day, 9)
        XCTAssertEqual(plan?.body, SummaryText.daily(open, locale: calendar.locale ?? .current))
    }

    func testGarbageMinutesAreIgnored() {
        XCTAssertNil(Reminders.dailySummaryPlan(minutes: 5000, status: open,
                                                now: now, calendar: calendar))
        XCTAssertNil(Reminders.dailySummaryPlan(minutes: -1, status: open,
                                                now: now, calendar: calendar))
    }

    // MARK: – Woche

    /// Wochentag + Uhrzeit ergeben den WIEDERHOLENDEN Trigger — nur so kommt
    /// die Meldung auch, wenn die App eine Woche lang zu war.
    func testWeeklyPlanUsesAWeekdayTrigger() {
        let status = SummaryStatus(done: 12, total: 18, missing: ["Laufen"])
        let plan = Reminders.weeklySummaryPlan(minutes: 18 * 60 + 30, weekday: 1,
                                               status: status, calendar: calendar)
        XCTAssertEqual(plan?.identifier, Reminders.weeklySummaryId)
        XCTAssertEqual(plan?.dateMatching.weekday, 1)
        XCTAssertEqual(plan?.dateMatching.hour, 18)
        XCTAssertEqual(plan?.dateMatching.minute, 30)
        // Kein Datum: ein Muster, kein Termin.
        XCTAssertNil(plan?.dateMatching.year)
        XCTAssertEqual(plan?.repeats, true)
        XCTAssertEqual(plan?.isWeekly, true)
        XCTAssertEqual(plan?.body, SummaryText.weekly(status, locale: calendar.locale ?? .current))
    }

    func testWeeklyPlanNeedsTheSettingOn() {
        let status = SummaryStatus(done: 1, total: 2, missing: ["Laufen"])
        XCTAssertNil(Reminders.weeklySummaryPlan(minutes: nil, weekday: 1,
                                                 status: status, calendar: calendar))
    }

    func testWeeklyPlanRejectsAnImpossibleWeekday() {
        let status = SummaryStatus(done: 1, total: 2, missing: ["Laufen"])
        XCTAssertNil(Reminders.weeklySummaryPlan(minutes: 18 * 60, weekday: 0,
                                                 status: status, calendar: calendar))
        XCTAssertNil(Reminders.weeklySummaryPlan(minutes: 18 * 60, weekday: 8,
                                                 status: status, calendar: calendar))
    }

    func testWeeklyPlanIsSkippedWhenNothingWasDue() {
        let empty = SummaryStatus(done: 0, total: 0, missing: [])
        XCTAssertNil(Reminders.weeklySummaryPlan(minutes: 18 * 60, weekday: 1,
                                                 status: empty, calendar: calendar))
    }

    /// Die beiden Meldungen dürfen sich nicht gegenseitig überschreiben, und
    /// das Aufräumen muss die ALTEN Habit-Weckrufe noch finden.
    func testIdentifiersAreDistinctAndTheLegacyPrefixIsStillKnown() {
        XCTAssertNotEqual(Reminders.summaryId, Reminders.weeklySummaryId)
        XCTAssertEqual(Reminders.legacyHabitPrefix, "habit-")
        XCTAssertFalse(Reminders.summaryId.hasPrefix(Reminders.legacyHabitPrefix))
        XCTAssertFalse(Reminders.weeklySummaryId.hasPrefix(Reminders.legacyHabitPrefix))
    }
}

/// Die Einstellungen der beiden Zusammenfassungen: sie liegen in derselben
/// Datei wie alles andere, additiv und ohne Versionssprung.
final class SummarySettingsTests: XCTestCase {
    private func store() -> HabitStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("summary-settings-\(UUID().uuidString).json")
        return HabitStore(url: url)
    }

    func testWeeklySettingsRoundTripThroughTheFile() throws {
        let s = store()
        s.weeklySummaryMinutes = 19 * 60 + 15
        s.weeklySummaryWeekday = 6
        let reloaded = HabitStore(url: s.url)
        XCTAssertEqual(reloaded.weeklySummaryMinutes, 19 * 60 + 15)
        XCTAssertEqual(reloaded.weeklySummaryWeekday, 6)
    }

    func testDefaultsAreOffAndSunday() {
        let s = store()
        XCTAssertNil(s.weeklySummaryMinutes)
        XCTAssertEqual(s.weeklySummaryWeekday, HabitData.defaultSummaryWeekday)
        XCTAssertEqual(HabitData.defaultSummaryWeekday, 1)
    }

    func testAnImpossibleWeekdayFallsBackToTheDefault() throws {
        let raw = """
        {"version":2,"updatedAt":1,"habits":[],
         "weeklySummaryMinutes":1080,"weeklySummaryWeekday":42}
        """.data(using: .utf8)!
        let data = try JSONDecoder().decode(HabitData.self, from: raw)
        XCTAssertEqual(data.weeklySummaryMinutes, 1080)
        XCTAssertEqual(data.weeklySummaryWeekday, HabitData.defaultSummaryWeekday)
    }

    /// Eine Datei aus einem Build OHNE die Wochenzusammenfassung lädt
    /// unverändert — kein Versionssprung, keine Pflichtfelder.
    func testFileWithoutTheWeeklyKeysStillLoads() throws {
        let raw = """
        {"version":2,"updatedAt":1,"summaryMinutes":1200,"habits":[]}
        """.data(using: .utf8)!
        let data = try JSONDecoder().decode(HabitData.self, from: raw)
        XCTAssertEqual(data.summaryMinutes, 1200)
        XCTAssertNil(data.weeklySummaryMinutes)
        XCTAssertEqual(data.version, 2)
    }

    /// Der Wochentag steht nur in der Datei, wenn die Meldung überhaupt
    /// läuft — sonst wäre er eine Einstellung ohne Wirkung in jeder Datei.
    func testTheWeekdayIsOnlyWrittenWhenTheWeeklySummaryIsOn() throws {
        var data = HabitData(version: 2, updatedAt: 1, summaryMinutes: nil, habits: [])
        data.weeklySummaryWeekday = 4
        let off = String(data: try JSONEncoder().encode(data), encoding: .utf8) ?? ""
        XCTAssertFalse(off.contains("weeklySummaryWeekday"))
        data.weeklySummaryMinutes = 18 * 60
        let on = String(data: try JSONEncoder().encode(data), encoding: .utf8) ?? ""
        XCTAssertTrue(on.contains("weeklySummaryWeekday"))
    }

    /// Merge: das neuere Gerät gibt die Einstellung vor — wie bei der
    /// Tageszusammenfassung.
    func testMergeTakesTheNewerWeeklySetting() {
        let s = store()
        var remote = HabitData(version: 2, updatedAt: Date().timeIntervalSince1970 + 999,
                               summaryMinutes: nil, habits: [])
        remote.weeklySummaryMinutes = 17 * 60
        remote.weeklySummaryWeekday = 3
        s.merge(remote: remote)
        XCTAssertEqual(s.weeklySummaryMinutes, 17 * 60)
        XCTAssertEqual(s.weeklySummaryWeekday, 3)
    }

    // MARK: – Die Motivationsnachricht: derselbe Weg wie summaryMinutes

    func testMotivationSettingRoundTripsThroughTheFile() {
        let s = store()
        XCTAssertNil(s.motivationMinutes, "Voreinstellung ist AUS")
        s.motivationMinutes = 8 * 60
        XCTAssertEqual(HabitStore(url: s.url).motivationMinutes, 8 * 60)
        s.motivationMinutes = nil
        XCTAssertNil(HabitStore(url: s.url).motivationMinutes)
    }

    func testMotivationDeliveryDefaultsToNotificationAndRoundTrips() throws {
        let s = store()
        XCTAssertEqual(s.motivationDelivery, .notification)

        s.motivationDelivery = .liveActivity
        XCTAssertEqual(HabitStore(url: s.url).motivationDelivery, .liveActivity)

        let text = String(data: try Data(contentsOf: s.url), encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("motivationDelivery"))
    }

    /// Der Schlüssel steht nur in der Datei, wenn die Nachricht läuft — und
    /// eine Datei aus einem Build ohne ihn lädt unverändert weiter.
    func testMotivationKeyIsAdditiveAndOptional() throws {
        var data = HabitData(version: 2, updatedAt: 1, summaryMinutes: nil, habits: [])
        let off = String(data: try JSONEncoder().encode(data), encoding: .utf8) ?? ""
        XCTAssertFalse(off.contains("motivationMinutes"))
        data.motivationMinutes = 8 * 60
        let on = String(data: try JSONEncoder().encode(data), encoding: .utf8) ?? ""
        XCTAssertTrue(on.contains("motivationMinutes"))

        let old = Data(#"{"version":2,"updatedAt":1,"summaryMinutes":1200,"habits":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(HabitData.self, from: old)
        XCTAssertNil(decoded.motivationMinutes)
        XCTAssertEqual(decoded.summaryMinutes, 1200)
    }

    func testGitHubUsernameVisibilityIsOptionalAndRoundTrips() throws {
        var data = HabitData(version: 2, updatedAt: 1, summaryMinutes: nil, habits: [])
        XCTAssertNil(data.githubShowsUsername)

        data.githubShowsUsername = false
        let back = try JSONDecoder().decode(HabitData.self,
                                             from: JSONEncoder().encode(data))
        XCTAssertEqual(back.githubShowsUsername, false)

        let old = try JSONDecoder().decode(HabitData.self,
                                           from: Data(#"{"version":2,"updatedAt":1,"habits":[]}"#.utf8))
        XCTAssertNil(old.githubShowsUsername)
    }

    /// Merge: ein neuerer Stand darf optionale Einstellungen auch abschalten.
    /// `nil` ist hier eine echte Nutzerentscheidung, keine fehlende Information.
    func testNewerRemoteCanTurnOptionalSettingsOff() {
        let newer = Date().timeIntervalSince1970 + 999

        let s = store()
        s.summaryMinutes = 20 * 60
        s.weeklySummaryMinutes = 18 * 60
        s.motivationMinutes = 8 * 60
        s.motivationDelivery = .liveActivity

        s.merge(remote: HabitData(version: 2, updatedAt: newer,
                                  summaryMinutes: nil, habits: [],
                                  weeklySummaryMinutes: nil,
                                  motivationMinutes: nil,
                                  motivationDelivery: .notification))
        XCTAssertNil(s.summaryMinutes)
        XCTAssertNil(s.weeklySummaryMinutes)
        XCTAssertNil(s.motivationMinutes)
        XCTAssertEqual(s.motivationDelivery, .notification)

        // Älter, mit Wert: verliert.
        let older = store()
        older.motivationMinutes = 8 * 60
        var stale = HabitData(version: 2, updatedAt: 0, summaryMinutes: nil, habits: [])
        stale.motivationMinutes = 21 * 60
        older.merge(remote: stale)
        XCTAssertEqual(older.motivationMinutes, 8 * 60)
    }

    func testNewerRemoteCarriesGitHubVisibility() throws {
        var local = HabitData(version: 2, updatedAt: 1, summaryMinutes: nil, habits: [])
        local.githubShowsUsername = false
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("github-visibility-\(UUID().uuidString).json")
        try JSONEncoder().encode(local).write(to: url)
        let store = HabitStore(url: url)

        var remote = HabitData(version: 2, updatedAt: 2, summaryMinutes: nil, habits: [])
        remote.githubShowsUsername = true
        store.merge(remote: remote)
        XCTAssertEqual(store.data.githubShowsUsername, true)
    }
}
