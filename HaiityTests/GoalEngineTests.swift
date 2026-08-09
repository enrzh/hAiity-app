import XCTest
@testable import Haiity

/// Fixtures mit verifizierten Wochentagen (Europa/Berlin):
/// 2026-08-03 Mo … 2026-08-07 Fr, 2026-08-08 Sa, 2026-08-09 So,
/// 2026-08-10 Mo; Montage: 06.07., 13.07., 20.07., 27.07., 03.08.;
/// Jahreswechsel: 2026-12-28 Mo … 2027-01-03 So, 2027-01-04 Mo.
final class GoalEngineTests: XCTestCase {
    /// Berlin, Montag als Wochenanfang (deutsche/ISO-Woche).
    private var monday: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }

    /// Berlin, Sonntag als Wochenanfang (US-Woche).
    private var sunday: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.firstWeekday = 1
        c.minimumDaysInFirstWeek = 1
        return c
    }

    /// Ruhetage Sa/So in Calendar-Nummern (1 = So, 7 = Sa).
    private let weekend: Set<Int> = [1, 7]

    /// ALLE Fixtures laufen durch die MIGRATION: jedes Alt-Ziel wird zur
    /// Wiederholungsregel und muss dieselben Antworten liefern wie vorher.
    /// Damit ist diese Datei zugleich die Regressionsprobe der Migration.
    private func habit(_ days: [String: Int], legacy: LegacyGoal = .daily, createdAt: String = "2026-01-01") -> Habit {
        var h = Habit(name: "Test", legacy: legacy)
        h.createdAt = createdAt
        for (d, v) in days { h.log[d] = v }
        return h
    }

    private func checked(_ days: [String], legacy: LegacyGoal = .daily, createdAt: String = "2026-01-01") -> Habit {
        habit(Dictionary(uniqueKeysWithValues: days.map { ($0, 1) }), legacy: legacy, createdAt: createdAt)
    }

    // MARK: – dayCounts

    func testDayCountsCheckbox() {
        let h = habit(["2026-08-09": 1])
        XCTAssertTrue(GoalEngine.dayCounts(habit: h, day: "2026-08-09", calendar: monday))
        XCTAssertFalse(GoalEngine.dayCounts(habit: h, day: "2026-08-08", calendar: monday))
    }

    func testDayCountsQuantityBelowTargetFails() {
        let h = habit(["2026-08-09": 2], legacy: LegacyGoal(target: 3))
        XCTAssertFalse(GoalEngine.dayCounts(habit: h, day: "2026-08-09", calendar: monday))
    }

    func testDayCountsQuantityAtTargetCounts() {
        let h = habit(["2026-08-09": 3], legacy: LegacyGoal(target: 3))
        XCTAssertTrue(GoalEngine.dayCounts(habit: h, day: "2026-08-09", calendar: monday))
    }

    func testDayCountsQuantityAboveTargetCounts() {
        let h = habit(["2026-08-09": 5], legacy: LegacyGoal(target: 3))
        XCTAssertTrue(GoalEngine.dayCounts(habit: h, day: "2026-08-09", calendar: monday))
    }

    // MARK: – Tägliche Serie mit Ruhetagen

    func testRestDayStreakSpansWeekend() {
        // Mo–Fr zweier Wochen erledigt, Sa/So Ruhetage -> Serie 10 läuft
        // ungebrochen übers Wochenende (heute = So, selbst Ruhetag).
        let h = checked(["2026-07-27", "2026-07-28", "2026-07-29", "2026-07-30", "2026-07-31",
                         "2026-08-03", "2026-08-04", "2026-08-05", "2026-08-06", "2026-08-07"],
                        legacy: LegacyGoal(restDays: weekend), createdAt: "2026-07-27")
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-09", calendar: monday), 10)
    }

    func testRestDayStreakBrokenByMissedWorkday() {
        // Do 06.08. (Arbeitstag) fehlt -> nur Freitag zählt.
        let h = checked(["2026-08-03", "2026-08-04", "2026-08-07"],
                        legacy: LegacyGoal(restDays: weekend), createdAt: "2026-08-03")
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-07", calendar: monday), 1)
    }

    func testCheckinOnRestDayCountsTowardStreak() {
        // Check-in AM Ruhetag (Sa) bricht nichts und zählt mit.
        let h = checked(["2026-08-07", "2026-08-08"],
                        legacy: LegacyGoal(restDays: weekend), createdAt: "2026-08-07")
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-08", calendar: monday), 2)
    }

    func testFullRestWeekNeverBreaksStreak() {
        // Alle sieben Wochentage Ruhetage: nichts bricht je, nur die
        // Check-ins selbst zählen — und die Schleife terminiert trotzdem.
        let h = checked(["2026-08-03", "2026-08-06"],
                        legacy: LegacyGoal(restDays: [1, 2, 3, 4, 5, 6, 7]), createdAt: "2026-08-01")
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-09", calendar: monday), 2)
    }

    func testDailyStreakGraceForOpenTodayWithRestDays() {
        // Mo 10.08. noch offen, Sa/So Ruhetage -> Serie der Vorwoche lebt.
        let h = checked(["2026-08-03", "2026-08-04", "2026-08-05", "2026-08-06", "2026-08-07"],
                        legacy: LegacyGoal(restDays: weekend), createdAt: "2026-08-03")
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-10", calendar: monday), 5)
    }

    // MARK: – Wochen-Serie

    func testWeeklyStreakCountsCompletedWeeks() {
        // Drei erfüllte Vorwochen + laufende Woche schon erfüllt -> 4.
        let h = checked(["2026-07-13", "2026-07-15", "2026-07-17",
                         "2026-07-20", "2026-07-21", "2026-07-22",
                         "2026-07-27", "2026-07-29", "2026-07-31",
                         "2026-08-03", "2026-08-04", "2026-08-05"],
                        legacy: .weekly(times: 3))
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-06", calendar: monday), 4)
    }

    func testWeeklyStreakAliveMidWeekWhenStillAchievable() {
        // Laufende Woche erst 1/3, aber Mittwoch -> noch erreichbar:
        // Serie zeigt die 2 abgeschlossenen Vorwochen, bricht nicht.
        let h = checked(["2026-07-20", "2026-07-21", "2026-07-22",
                         "2026-07-27", "2026-07-28", "2026-07-29",
                         "2026-08-03"],
                        legacy: .weekly(times: 3))
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-05", calendar: monday), 2)
    }

    func testWeeklyStreakDiesWhenNoLongerAchievable() {
        // So 09.08., laufende Woche 0/3, nur noch heute übrig -> tot,
        // obwohl die Vorwoche erfüllt war.
        let h = checked(["2026-07-27", "2026-07-29", "2026-07-31"],
                        legacy: .weekly(times: 3))
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-09", calendar: monday), 0)
    }

    func testWeeklyStreakAcrossYearBoundary() {
        // Wochen 21.12., 28.12. (über Silvester) und 04.01. je 2x -> Serie 3.
        let h = checked(["2026-12-21", "2026-12-23",
                         "2026-12-28", "2027-01-01",
                         "2027-01-04", "2027-01-05"],
                        legacy: .weekly(times: 2))
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2027-01-06", calendar: monday), 3)
    }

    func testWeeklyStreakYearBoundaryRespectsFirstWeekday() {
        // Sonntags-Check-ins am Jahreswechsel: die Kalender bucketieren
        // dieselben Tage in verschiedene Wochen.
        let h = checked(["2026-12-27", "2027-01-03", "2027-01-04"],
                        legacy: .weekly(times: 1))
        // Montag-Woche: 27.12. -> KW 21.12., 03.01. -> KW 28.12.,
        // 04.01. -> laufende Woche: drei erfüllte Wochen in Folge.
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2027-01-04", calendar: monday), 3)
        // Sonntag-Woche: 27.12. eröffnet die eine, 03.01. die nächste Woche
        // (04.01. liegt in derselben) -> zwei erfüllte Wochen.
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2027-01-04", calendar: sunday), 2)
    }

    func testWeeklyStreakSundayFirstSplitsWeekendPair() {
        // Sa 01.08. + So 02.08.: Montags-Woche hält beide zusammen (erfüllt),
        // Sonntags-Woche trennt sie -> Serie 0 (Vorwoche nur 1/2).
        let h = checked(["2026-08-01", "2026-08-02"], legacy: .weekly(times: 2))
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-02", calendar: monday), 1)
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-02", calendar: sunday), 0)
    }

    func testWeeklyQuantityDaysNeedTarget() {
        // Wochenziel 2x mit Tagesziel 3: Tage unter 3 zählen nicht.
        let partial = habit(["2026-08-03": 2, "2026-08-04": 2],
                            legacy: LegacyGoal(cadence: .weekly(times: 2), target: 3))
        XCTAssertEqual(GoalEngine.streak(habit: partial, today: "2026-08-09", calendar: monday), 0)
        let full = habit(["2026-08-03": 3, "2026-08-04": 3],
                         legacy: LegacyGoal(cadence: .weekly(times: 2), target: 3))
        XCTAssertEqual(GoalEngine.streak(habit: full, today: "2026-08-09", calendar: monday), 1)
    }

    // MARK: – Abschlussquote

    func testCompletionDailyExcludesRestDaysFromDenominator() {
        // Mo–Fr erledigt, Sa/So Ruhetage, 7-Tage-Fenster -> 100 %.
        let h = checked(["2026-08-03", "2026-08-04", "2026-08-05", "2026-08-06", "2026-08-07"],
                        legacy: LegacyGoal(restDays: weekend))
        XCTAssertEqual(GoalEngine.completion(habit: h, lastNDays: 7, today: "2026-08-09", calendar: monday),
                       1.0, accuracy: 0.0001)
    }

    func testCompletionDailyCountsMissedWorkdays() {
        // 3 von 5 Arbeitstagen -> 0.6.
        let h = checked(["2026-08-03", "2026-08-04", "2026-08-05"],
                        legacy: LegacyGoal(restDays: weekend))
        XCTAssertEqual(GoalEngine.completion(habit: h, lastNDays: 7, today: "2026-08-09", calendar: monday),
                       0.6, accuracy: 0.0001)
    }

    func testCompletionAllRestDaysIsZero() {
        // Leerer Nenner (nur Ruhetage im Fenster) -> 0, nie Division durch 0.
        let h = checked(["2026-08-05"], legacy: LegacyGoal(restDays: [1, 2, 3, 4, 5, 6, 7]))
        XCTAssertEqual(GoalEngine.completion(habit: h, lastNDays: 7, today: "2026-08-09", calendar: monday), 0)
    }

    func testCompletionDailyPlainWindow() {
        // Ohne Ruhetage: 4 von 7 Tagen -> 4/7.
        let h = checked(["2026-08-06", "2026-08-07", "2026-08-08", "2026-08-09"])
        XCTAssertEqual(GoalEngine.completion(habit: h, lastNDays: 7, today: "2026-08-09", calendar: monday),
                       4.0 / 7.0, accuracy: 0.0001)
    }

    func testCompletionWeeklyMeasuresWeeks() {
        // 4 Kalenderwochen im 28-Tage-Fenster, 3 erfüllt (2x-Ziel) -> 0.75.
        let h = checked(["2026-07-13", "2026-07-15",      // KW 13.07. erfüllt
                         "2026-07-20",                     // KW 20.07. NICHT erfüllt
                         "2026-07-27", "2026-07-28",      // KW 27.07. erfüllt
                         "2026-08-03", "2026-08-04"],     // laufende KW erfüllt
                        legacy: .weekly(times: 2))
        XCTAssertEqual(GoalEngine.completion(habit: h, lastNDays: 28, today: "2026-08-09", calendar: monday),
                       0.75, accuracy: 0.0001)
    }

    func testCompletionWeeklyExcludesUnfinishedCurrentWeek() {
        // Laufende, unerfüllte Woche fällt aus dem Nenner -> 3/3 statt 3/4.
        let h = checked(["2026-07-13", "2026-07-15",
                         "2026-07-20", "2026-07-21",
                         "2026-07-27", "2026-07-28"],
                        legacy: .weekly(times: 2))
        XCTAssertEqual(GoalEngine.completion(habit: h, lastNDays: 24, today: "2026-08-05", calendar: monday),
                       1.0, accuracy: 0.0001)
    }

    // MARK: – Beste Serie (Ziel-Semantik)

    func testBestStreakEmptyLogIsZero() {
        XCTAssertEqual(GoalEngine.bestStreak(habit: habit([:]), today: "2026-08-09", calendar: monday), 0)
        XCTAssertEqual(GoalEngine.bestStreak(habit: habit([:], legacy: .weekly(times: 3)),
                                             today: "2026-08-09", calendar: monday), 0)
    }

    /// Ein Mengen-Habit zählt NUR Tage ab `target`. Vier zusammenhängende
    /// Log-Tage, von denen einer unter dem Ziel liegt, sind zwei Serien à 2
    /// und 1 — nicht ein Lauf von 4 (das war die rohe Log-Tage-Zählung).
    func testBestStreakQuantityIgnoresDaysBelowTarget() {
        let h = habit(["2026-08-03": 3, "2026-08-04": 3, "2026-08-05": 1, "2026-08-06": 3],
                      legacy: LegacyGoal(target: 3), createdAt: "2026-08-01")
        XCTAssertEqual(GoalEngine.bestStreak(habit: h, today: "2026-08-09", calendar: monday), 2)
    }

    func testBestStreakQuantityCountsDaysAtOrAboveTarget() {
        let h = habit(["2026-08-03": 3, "2026-08-04": 4, "2026-08-05": 3],
                      legacy: LegacyGoal(target: 3), createdAt: "2026-08-01")
        XCTAssertEqual(GoalEngine.bestStreak(habit: h, today: "2026-08-09", calendar: monday), 3)
    }

    /// Ruhetage überbrücken: zwei volle Arbeitswochen mit Wochenend-Ruhetagen
    /// sind EINE Serie von 10, nicht zwei von 5.
    func testBestStreakRestDaysBridgeInsteadOfBreaking() {
        let days = ["2026-07-27", "2026-07-28", "2026-07-29", "2026-07-30", "2026-07-31",
                    "2026-08-03", "2026-08-04", "2026-08-05", "2026-08-06", "2026-08-07"]
        let resting = checked(days, legacy: LegacyGoal(restDays: weekend), createdAt: "2026-07-01")
        XCTAssertEqual(GoalEngine.bestStreak(habit: resting, today: "2026-08-09", calendar: monday), 10)
        // Gegenprobe ohne Ruhetage: das Wochenende bricht, längster Lauf 5.
        let plain = checked(days, createdAt: "2026-07-01")
        XCTAssertEqual(GoalEngine.bestStreak(habit: plain, today: "2026-08-09", calendar: monday), 5)
    }

    /// Wochen-Kadenz misst WOCHEN: fünf Check-ins in derselben Kalenderwoche
    /// sind eine erfüllte Woche.
    func testBestStreakWeeklyCountsWeeksNotDays() {
        let h = checked(["2026-08-03", "2026-08-04", "2026-08-05", "2026-08-06", "2026-08-07"],
                        legacy: .weekly(times: 2), createdAt: "2026-07-01")
        XCTAssertEqual(GoalEngine.bestStreak(habit: h, today: "2026-08-09", calendar: monday), 1)
    }

    /// Drei erfüllte Wochen über den Jahreswechsel (KW 52 -> KW 1) müssen
    /// EINE Kette sein. Über Wochennummern gerechnet risse sie hier.
    func testBestStreakWeeklyAcrossYearBoundary() {
        let h = checked(["2026-12-21", "2026-12-22",   // Woche ab Mo 21.12.
                         "2026-12-28", "2026-12-29",   // Woche ab Mo 28.12.
                         "2027-01-04", "2027-01-05",   // Woche ab Mo 04.01.
                         "2027-01-18", "2027-01-19"],  // nach einer Lücke
                        legacy: .weekly(times: 2), createdAt: "2026-12-01")
        XCTAssertEqual(GoalEngine.bestStreak(habit: h, today: "2027-02-01", calendar: monday), 3)
    }

    // MARK: – Intensität

    func testIntensityQuantityScalesWithTarget() {
        let h = habit(["2026-08-03": 1, "2026-08-04": 2, "2026-08-05": 3, "2026-08-06": 4],
                      legacy: LegacyGoal(target: 4))
        XCTAssertEqual(GoalEngine.intensity(habit: h, key: "2026-08-03", calendar: monday), 1)
        XCTAssertEqual(GoalEngine.intensity(habit: h, key: "2026-08-04", calendar: monday), 2)
        XCTAssertEqual(GoalEngine.intensity(habit: h, key: "2026-08-05", calendar: monday), 3)
        XCTAssertEqual(GoalEngine.intensity(habit: h, key: "2026-08-06", calendar: monday), 4)
    }

    func testIntensityQuantityClampsAtFour() {
        let h = habit(["2026-08-09": 9], legacy: LegacyGoal(target: 4))
        XCTAssertEqual(GoalEngine.intensity(habit: h, key: "2026-08-09", calendar: monday), 4)
    }

    /// Der erste Zähler MUSS Stufe 1 sein — auch bei kleinen Zielen. Die
    /// alte ceil-Formel sprang bei target 3 sofort auf Stufe 2
    /// (`ceil(4/3) = 2`), Stufe 1 war unerreichbar.
    func testIntensityQuantitySmallTargetStartsAtLevelOne() {
        let h = habit(["2026-08-08": 1, "2026-08-09": 2], legacy: LegacyGoal(target: 3))
        XCTAssertEqual(GoalEngine.intensity(habit: h, key: "2026-08-08", calendar: monday), 1)
        XCTAssertEqual(GoalEngine.intensity(habit: h, key: "2026-08-09", calendar: monday), 2)
    }

    /// Die Rampe über die kritischen Zielgrößen: erster Zähler immer 1,
    /// erreichtes Ziel immer 4, dazwischen monoton steigend.
    func testIntensityQuantityRampAcrossTargets() {
        let expected: [Int: [Int]] = [
            1: [4],                                     // 1/1
            2: [1, 4],                                  // 1/2, 2/2
            3: [1, 2, 4],                               // 1/3 … 3/3
            4: [1, 2, 3, 4],                            // alle vier Stufen
            10: [1, 1, 1, 2, 2, 2, 3, 3, 3, 4],         // 1/10 … 10/10
        ]
        for (target, levels) in expected {
            for (i, level) in levels.enumerated() {
                let value = i + 1
                let h = habit(["2026-08-09": value], legacy: LegacyGoal(target: target))
                XCTAssertEqual(GoalEngine.intensity(habit: h, key: "2026-08-09", calendar: monday),
                               level,
                               "target \(target), Wert \(value)")
            }
            // Erster Zähler ist Stufe 1 (außer bei target 1, wo er das Ziel
            // schon erfüllt), erreichtes Ziel ist Stufe 4.
            XCTAssertEqual(levels.first, target == 1 ? 4 : 1, "target \(target): erster Zähler")
            XCTAssertEqual(levels.last, 4, "target \(target): erfülltes Ziel")
        }
    }

    func testIntensityQuantityZeroWhenEmpty() {
        let h = habit([:], legacy: LegacyGoal(target: 4))
        XCTAssertEqual(GoalEngine.intensity(habit: h, key: "2026-08-09", calendar: monday), 0)
    }

    func testIntensityCheckboxKeepsRunSemantics() {
        // Checkbox behält v1-Lauflängen: Lauf-Anfang 1, 3er-Lauf-Ende 2,
        // 8er-Lauf-Ende 4.
        let days = (0..<8).compactMap { DayKey.shifted("2026-08-09", by: -$0, calendar: monday) }
        let h = checked(days)
        XCTAssertEqual(GoalEngine.intensity(habit: h, key: "2026-08-02", calendar: monday), 1)
        XCTAssertEqual(GoalEngine.intensity(habit: h, key: "2026-08-04", calendar: monday), 2)
        XCTAssertEqual(GoalEngine.intensity(habit: h, key: "2026-08-09", calendar: monday), 4)
    }
}

/// Codable: das ausgelieferte Ziel-Format, tolerantes Dekodieren und die
/// v1-Migration (die keine ist — v1-Dateien laden unverändert mit
/// Standardwerten). Alle Alt-Formen kommen als `Recurrence` zurück.
final class ModelV2CodableTests: XCTestCase {

    /// Wörtliches v1-Format von der Platte (persist() schrieb
    /// prettyPrinted+sortedKeys, ohne goal/archivedAt, version 1).
    static let v1JSON = """
    {
      "habits" : [
        {
          "createdAt" : "2026-08-01",
          "emoji" : "📖",
          "id" : "9AC9D1B1-2AAA-4E5B-8F19-111111111111",
          "log" : {
            "2026-08-01" : 1,
            "2026-08-02" : 1
          },
          "name" : "Lesen"
        }
      ],
      "summaryMinutes" : 1140,
      "updatedAt" : 1754745600.5,
      "version" : 1
    }
    """

    func testV1FixtureDecodesWithDailyDefaults() throws {
        let data = try JSONDecoder().decode(HabitData.self, from: Data(Self.v1JSON.utf8))
        XCTAssertEqual(data.version, 1)
        XCTAssertEqual(data.summaryMinutes, 1140)
        let h = try XCTUnwrap(data.habits.first)
        XCTAssertEqual(h.name, "Lesen")
        XCTAssertEqual(h.recurrence, .daily)
        XCTAssertEqual(h.recurrence.frequency, .daily)
        XCTAssertNil(h.recurrence.target)
        XCTAssertNil(h.archivedAt)
        XCTAssertEqual(h.log["2026-08-02"], 1)
    }

    func testHabitWithRecurrenceRoundTrips() throws {
        var h = Habit(name: "Sport",
                      recurrence: Recurrence(frequency: .weekly, interval: 2,
                                             weekdays: [2, 5], start: "2026-08-03",
                                             end: .after(12), target: 5))
        h.archivedAt = "2026-08-05"
        h.log["2026-08-04"] = 3
        let raw = try JSONEncoder().encode(h)
        let back = try JSONDecoder().decode(Habit.self, from: raw)
        XCTAssertEqual(back, h)
    }

    func testDefaultRecurrenceStaysImplicitInJSON() throws {
        // Einfache Habits sehen im JSON weiter aus wie in v1.
        let raw = try JSONEncoder().encode(Habit(name: "Simpel"))
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
        XCTAssertNil(obj["goal"])
        XCTAssertNil(obj["archivedAt"])
    }

    func testUnknownCadenceFallsBackToDaily() throws {
        let r = try JSONDecoder().decode(
            Recurrence.self, from: Data(#"{"cadence":"monatlich","times":9}"#.utf8))
        XCTAssertEqual(r, .daily)
    }

    /// Auch eine Datei aus einer NEUEREN Version (unbekannte Häufigkeit)
    /// darf höchstens die Regel verlieren, nie das Habit: gelesen wird dann
    /// der Alt-Spiegel, der danebensteht.
    func testUnknownFrequencyFallsBackToTheLegacyMirror() throws {
        let r = try JSONDecoder().decode(
            Recurrence.self,
            from: Data(#"{"freq":"fortnightly","cadence":"weekly","times":3}"#.utf8))
        XCTAssertEqual(r, .times(3, per: .weekly))
    }

    func testWeeklyTimesClampedToOneThroughSeven() throws {
        let high = try JSONDecoder().decode(
            Recurrence.self, from: Data(#"{"cadence":"weekly","times":99}"#.utf8))
        XCTAssertEqual(high.timesPerPeriod, 7)
        XCTAssertEqual(Recurrence.from(legacy: .weekly(times: 0)).timesPerPeriod, 1)
    }

    func testInvalidRestDaysAndTargetSanitized() throws {
        let r = try JSONDecoder().decode(
            Recurrence.self, from: Data(#"{"cadence":"daily","restDays":[0,3,8],"target":0}"#.utf8))
        // Nur die 3 war ein gültiger Ruhetag -> alle anderen sechs Tage sind
        // Termine.
        XCTAssertEqual(r.weekdays, [1, 2, 4, 5, 6, 7])
        XCTAssertNil(r.target)
    }

    func testFutureVersionRejected() throws {
        let raw = Data(#"{"version":3,"updatedAt":0,"habits":[]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(HabitData.self, from: raw))
    }
}
