import XCTest
@testable import Haiity

/// Die Habit-Art „Ja/Nein" — ein Tag ist *unbeantwortet*, *ja* oder *nein*.
///
/// Geprüft wird in drei Schichten, und die Reihenfolge ist die der Risiken:
///
///  1. **Die Codierung** (`YesNoEncodingTests`): eine Antwort muss eine Runde
///     durch einen AUSGELIEFERTEN Build überleben. Das ist der einzige
///     unumkehrbare Fehler in diesem Vorhaben — steht die Antwort an der
///     falschen Stelle, löscht ein Start plus ein Tipp auf Build 7 jedes
///     „Nein" und schiebt das nach iCloud.
///  2. **Die Rechnung** (`YesNoEngineTests`): was ein Nein mit Serie, Quote
///     und Rasterstufe macht — und was ein unbeantworteter Tag macht.
///  3. **Die Oberfläche** (`YesNoSurfaceTests`, `YesNoColorTests`): dass
///     jede Fläche, die Zellen malt oder heute anzeigt, den dritten Zustand
///     kennt.
///
/// Fixtures wie in `GoalEngineTests`: 2026-08-03 Mo … 2026-08-09 So.

// MARK: – 1. Die Codierung

/// **Der Kern der ganzen Sache.** Auf dem Gerät des Nutzers liegen die Builds
/// 1…7 und synchronisieren DIESELBE Datei. Ein solcher Build kennt weder die
/// Habit-Art noch die Antworten; was er nicht kennt, überliest er beim Lesen
/// UND lässt es beim Schreiben weg. Diese Klasse spielt genau das nach.
final class YesNoEncodingTests: XCTestCase {

    /// Was `Habit.encode` in Build 7 geschrieben hat — Zeichen für Zeichen
    /// dieselben Schlüssel wie dort. Der „alte Build" ist hier also kein
    /// Gedankenexperiment, sondern ein Decoder mit genau diesen Feldern.
    private struct LegacyHabitV7: Codable {
        var id: UUID
        var name: String
        var emoji: String
        var createdAt: String
        var reminderMinutes: Int?
        var timeMinutes: Int?
        var log: [String: Int]
        var archivedAt: String?
        var palette: String?
        // `goal` und alles Unbekannte fehlen absichtlich: ein Feld, das
        // dieser Build nicht hat, verschwindet beim Zurückschreiben.
    }

    private func yesNoHabit() -> Habit {
        var h = Habit(name: "Kein Zucker", recurrence: .daily, kind: .yesNo)
        h.createdAt = "2026-08-01"
        h.log["2026-08-05"] = Habit.Answer.yes
        h.log["2026-08-06"] = Habit.Answer.no
        h.log["2026-08-07"] = Habit.Answer.yes
        return h
    }

    // MARK: Die drei Wege, die NICHT gehen

    func testAnswersAreValidDayKeysWithPositiveValues() {
        // Der Filter in `Habit.init(from:)` ist die harte Grenze: `value >= 1
        // && DayKey.isValid(key)`. Genau daran scheitern die naheliegenden
        // Entwürfe — ein Namensraum im Schlüssel und ein negatives Sentinel.
        XCTAssertFalse(DayKey.isValid("2026-08-09#no"), "namensräumiger Schlüssel wäre Müll")
        XCTAssertGreaterThanOrEqual(Habit.Answer.yes, 1)
        XCTAssertGreaterThanOrEqual(Habit.Answer.no, 1)
        XCTAssertTrue(Habit.Answer.isReserved(Habit.Answer.yes))
        XCTAssertTrue(Habit.Answer.isReserved(Habit.Answer.no))
    }

    func testAnswersSurviveTheGarbageFilterOnDecode() throws {
        let raw = try JSONEncoder().encode(yesNoHabit())
        let back = try JSONDecoder().decode(Habit.self, from: raw)
        XCTAssertEqual(back.log["2026-08-06"], Habit.Answer.no)
        XCTAssertEqual(back.log["2026-08-05"], Habit.Answer.yes)
        XCTAssertEqual(back.kind, .yesNo)
    }

    // MARK: Die Runde durch einen ausgelieferten Build

    func testRoundTripThroughAShippedBuildKeepsEveryAnswer() throws {
        let original = yesNoHabit()
        let mine = try JSONEncoder().encode(original)

        // Build 7 liest …
        var old = try JSONDecoder().decode(LegacyHabitV7.self, from: mine)
        XCTAssertEqual(old.log["2026-08-06"], Habit.Answer.no,
                       "die Antwort steht im Log und kommt dort auch an")
        // … der Nutzer tippt etwas (dieser Build hakt einen Tag ab) …
        old.log["2026-08-08"] = 1
        // … und Build 7 schreibt die Datei zurück. Alles, was er nicht
        // kennt, ist jetzt weg.
        let written = try JSONEncoder().encode(old)
        let json = String(data: written, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("\"kind\""), "der Marker überlebt so eine Runde NICHT")

        // Und jetzt wieder hier:
        let healed = try JSONDecoder().decode(Habit.self, from: written)
        XCTAssertEqual(healed.log["2026-08-05"], Habit.Answer.yes)
        XCTAssertEqual(healed.log["2026-08-06"], Habit.Answer.no, "kein Nein ist verloren")
        XCTAssertEqual(healed.log["2026-08-07"], Habit.Answer.yes)
        XCTAssertEqual(healed.kind, .yesNo,
                       "die Art heilt sich an den Antworten, obwohl der Marker fehlt")
        // Der Tipp auf dem alten Build zählt als Ja — er hat dort ja auch
        // „erledigt" gemeint.
        XCTAssertTrue(healed.isAffirmed("2026-08-08"))
    }

    func testShippedBuildMerelyMisreadsAnAnswerAsDone() throws {
        // Was der alte Build ANZEIGT, ist der Preis: ein Nein sieht dort aus
        // wie ein erledigter Tag. Kosmetisch, nicht destruktiv — und die
        // Zusage ist, dass es NUR das ist.
        let raw = try JSONEncoder().encode(yesNoHabit())
        var asCheckbox = try JSONDecoder().decode(Habit.self, from: raw)
        asCheckbox.kind = .checkbox          // so liest ein Build ohne die Art
        XCTAssertTrue(asCheckbox.isDone("2026-08-06"))
        XCTAssertTrue(GoalEngine.dayCounts(habit: asCheckbox, day: "2026-08-06"))
    }

    func testNoDataVersionBump() {
        // Ein Sprung auf 3 würde die ausgelieferten Builds aus ihrer EIGENEN
        // Datei aussperren (`HabitData.init(from:)` lehnt Unbekanntes ab).
        XCTAssertEqual(HabitData.currentVersion, 2)
    }

    func testFileWithoutYesNoHabitsLooksExactlyLikeBefore() throws {
        let plain = Habit(name: "Lesen")
        let json = String(data: try JSONEncoder().encode(plain), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("kind"),
                       "der Marker steht nur bei Ja/Nein in der Datei")
    }

    // MARK: Die Zusage, auf der das Band steht

    func testCountersCanNeverReachTheReservedBand() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-band-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url)
        var quantity = Habit(name: "Wasser", recurrence: Recurrence(target: 3))
        quantity.log["2026-08-09"] = Habit.Answer.maxCount
        store.add(quantity)
        store.increment(quantity.id, day: "2026-08-09")
        XCTAssertEqual(store.habits[0].log["2026-08-09"], Habit.Answer.maxCount,
                       "der Zähler steht am Deckel und läuft nicht ins Band")
        XCTAssertFalse(Habit.Answer.isReserved(store.habits[0].log["2026-08-09"] ?? 0))
    }

    // MARK: Selbstheilung der Art

    func testKindResolutionPrefersAnswersOverTheMarker() {
        XCTAssertEqual(Habit.resolvedKind(marker: nil,
                                          log: ["2026-08-01": Habit.Answer.no],
                                          target: nil), .yesNo)
        XCTAssertEqual(Habit.resolvedKind(marker: "checkbox",
                                          log: ["2026-08-01": Habit.Answer.yes],
                                          target: nil), .yesNo)
        XCTAssertEqual(Habit.resolvedKind(marker: "yesNo", log: [:], target: nil), .yesNo)
        XCTAssertEqual(Habit.resolvedKind(marker: "yesNo", log: [:], target: 3), .yesNo,
                       "die Art gewinnt über ein stehen gebliebenes Mengenziel")
        XCTAssertEqual(Habit.resolvedKind(marker: nil, log: ["2026-08-01": 4], target: 3), .quantity)
        XCTAssertEqual(Habit.resolvedKind(marker: nil, log: ["2026-08-01": 1], target: nil), .checkbox)
        XCTAssertEqual(Habit.resolvedKind(marker: "quatsch", log: [:], target: nil), .checkbox)
    }

    func testLeavingYesNoMigratesTheLog() {
        let log = ["2026-08-01": Habit.Answer.yes,
                   "2026-08-02": Habit.Answer.no,
                   "2026-08-03": 1]
        let migrated = Habit.migratedLog(log, to: .checkbox)
        XCTAssertEqual(migrated["2026-08-01"], 1, "aus Ja wird ein erledigter Tag")
        XCTAssertNil(migrated["2026-08-02"], "für ein Nein gibt es keine Entsprechung")
        XCTAssertEqual(migrated["2026-08-03"], 1)
        // Ohne die Umschreibung käme die Art beim nächsten Lesen zurück.
        XCTAssertEqual(Habit.resolvedKind(marker: "checkbox", log: migrated, target: nil), .checkbox)
        XCTAssertEqual(Habit.migratedLog(log, to: .yesNo), log, "in die Richtung nie")
    }
}

// MARK: – Der Merge

/// Was MAX pro Tag mit zwei Antworten macht. Die Ordnung im Band
/// (`yes > no > maxCount`) ist genau dafür gewählt.
final class YesNoMergeTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-ynmerge-\(UUID().uuidString).json")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: url) }

    private func merged(local: [String: Int], remote: [String: Int],
                        remoteNewer: Bool = false) -> Habit {
        let store = HabitStore(url: url)
        var h = Habit(name: "Kein Zucker", kind: .yesNo)
        h.log = local
        store.add(h)
        var r = h
        r.log = remote
        store.merge(remote: HabitData(version: 2,
                                      updatedAt: remoteNewer ? Date().timeIntervalSince1970 + 100 : 0,
                                      summaryMinutes: nil,
                                      habits: [r]))
        return store.habits[0]
    }

    func testAnswerBeatsNothing() {
        let h = merged(local: [:], remote: ["2026-08-01": Habit.Answer.no])
        XCTAssertEqual(h.log["2026-08-01"], Habit.Answer.no,
                       "eine Antwort verschwindet nie — wie ein Check-in nie verschwindet")
    }

    func testYesBeatsNoInEitherDirection() {
        XCTAssertEqual(merged(local: ["2026-08-01": Habit.Answer.no],
                              remote: ["2026-08-01": Habit.Answer.yes]).log["2026-08-01"],
                       Habit.Answer.yes)
        XCTAssertEqual(merged(local: ["2026-08-01": Habit.Answer.yes],
                              remote: ["2026-08-01": Habit.Answer.no]).log["2026-08-01"],
                       Habit.Answer.yes,
                       "nie von Ja auf Nein — dieselbe Richtung wie überall in diesem Merge")
    }

    func testAnswerBeatsALegacyCounter() {
        // Der Rückweg von einem ausgelieferten Build: dessen „1" darf das
        // Nein nicht überschreiben.
        XCTAssertEqual(merged(local: ["2026-08-01": Habit.Answer.no],
                              remote: ["2026-08-01": 1]).log["2026-08-01"],
                       Habit.Answer.no)
    }

    func testMergeNeverTurnsAnAnswerIntoUnanswered() {
        for local in [Habit.Answer.yes, Habit.Answer.no] {
            for remote in [0, 1, 99, Habit.Answer.yes, Habit.Answer.no] {
                var remoteLog: [String: Int] = [:]
                if remote > 0 { remoteLog["2026-08-01"] = remote }
                let value = merged(local: ["2026-08-01": local], remote: remoteLog)
                    .log["2026-08-01"] ?? 0
                XCTAssertTrue(Habit.Answer.isAnswer(value),
                              "aus \(local)/\(remote) wurde \(value)")
            }
        }
    }

    func testMergeRestoresTheKindFromTheOtherSidesAnswers() {
        // Die Gegenseite bringt die erste Antwort mit; lokal ist es (noch)
        // ein Checkbox-Habit, weil ein alter Build den Marker abgeräumt hat.
        let store = HabitStore(url: url)
        var local = Habit(name: "Kein Zucker")
        XCTAssertEqual(local.kind, .checkbox)
        store.add(local)
        local.log["2026-08-01"] = Habit.Answer.no
        store.merge(remote: HabitData(version: 2, updatedAt: 0, summaryMinutes: nil,
                                      habits: [local]))
        XCTAssertEqual(store.habits[0].kind, .yesNo)
    }
}

// MARK: – 2. Die Rechnung

/// Serien, Quoten, Zellstufen. **Die eine Regel, die alles trägt:** eine
/// ausdrückliche Verneinung ist nie durchsichtig.
final class YesNoEngineTests: XCTestCase {
    private var monday: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }

    private func habit(_ log: [String: Int],
                       recurrence: Recurrence = .daily,
                       createdAt: String = "2026-07-01") -> Habit {
        var h = Habit(name: "Kein Zucker", recurrence: recurrence, kind: .yesNo)
        h.createdAt = createdAt
        h.log = log
        h.kind = .yesNo
        return h
    }

    private func answers(_ days: [String], yes: Bool) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: days.map { ($0, yes ? Habit.Answer.yes : Habit.Answer.no) })
    }

    // MARK: dayCounts

    func testOnlyYesCounts() {
        let h = habit(["2026-08-07": Habit.Answer.yes,
                       "2026-08-08": Habit.Answer.no])
        XCTAssertTrue(GoalEngine.dayCounts(habit: h, day: "2026-08-07", calendar: monday))
        XCTAssertFalse(GoalEngine.dayCounts(habit: h, day: "2026-08-08", calendar: monday),
                       "ein Nein ist ein Wert ≥ 1 und darf trotzdem nicht zählen")
        XCTAssertFalse(GoalEngine.dayCounts(habit: h, day: "2026-08-09", calendar: monday))
    }

    func testTheKindWinsOverALeftoverQuantityTarget() {
        var h = habit(["2026-08-07": Habit.Answer.yes], recurrence: Recurrence(target: 5))
        h.kind = .yesNo
        XCTAssertTrue(GoalEngine.dayCounts(habit: h, day: "2026-08-07", calendar: monday))
        XCTAssertEqual(GoalEngine.intensity(habit: h, key: "2026-08-07", calendar: monday), 1)
    }

    func testThreeStatesAreThreeStates() {
        let h = habit(["2026-08-07": Habit.Answer.yes,
                       "2026-08-08": Habit.Answer.no])
        XCTAssertTrue(h.isAffirmed("2026-08-07"))
        XCTAssertFalse(h.isDeclined("2026-08-07"))
        XCTAssertTrue(h.isAnswered("2026-08-07"))

        XCTAssertFalse(h.isAffirmed("2026-08-08"))
        XCTAssertTrue(h.isDeclined("2026-08-08"))
        XCTAssertTrue(h.isAnswered("2026-08-08"))

        XCTAssertFalse(h.isAffirmed("2026-08-09"))
        XCTAssertFalse(h.isDeclined("2026-08-09"))
        XCTAssertFalse(h.isAnswered("2026-08-09"), "unbeantwortet ist der dritte Zustand")
    }

    // MARK: Serie

    func testNoBreaksTheStreak() {
        var log = answers(["2026-08-05", "2026-08-06", "2026-08-07", "2026-08-08", "2026-08-09"],
                          yes: true)
        XCTAssertEqual(GoalEngine.streak(habit: habit(log), today: "2026-08-09", calendar: monday), 5)
        log["2026-08-07"] = Habit.Answer.no
        XCTAssertEqual(GoalEngine.streak(habit: habit(log), today: "2026-08-09", calendar: monday), 2,
                       "die Serie beginnt nach dem Nein neu")
    }

    func testNoTodayBreaksImmediately() {
        var log = answers(["2026-08-06", "2026-08-07", "2026-08-08"], yes: true)
        log["2026-08-09"] = Habit.Answer.no
        XCTAssertEqual(GoalEngine.streak(habit: habit(log), today: "2026-08-09", calendar: monday), 0,
                       "heute ist beantwortet — und zwar mit Nein")
    }

    func testUnansweredTodayKeepsTheStreakAlive() {
        let log = answers(["2026-08-06", "2026-08-07", "2026-08-08"], yes: true)
        XCTAssertEqual(GoalEngine.streak(habit: habit(log), today: "2026-08-09", calendar: monday), 3,
                       "heute noch offen ist etwas anderes als heute verneint")
    }

    func testUnansweredScheduledDayInThePastBreaksLikeAnyOpenDay() {
        var log = answers(["2026-08-05", "2026-08-06", "2026-08-08", "2026-08-09"], yes: true)
        log["2026-08-07"] = nil
        XCTAssertEqual(GoalEngine.streak(habit: habit(log), today: "2026-08-09", calendar: monday), 2)
    }

    /// **Der Unterschied, für den es die Habit-Art gibt.** Am selben
    /// terminfreien Tag: unbeantwortet überbrückt, Nein bricht.
    func testNoBreaksEvenOnAnUnscheduledDay() {
        // Mo/Mi/Fr — der Samstag 2026-08-08 ist frei.
        let rule = Recurrence.weekdays([2, 4, 6])
        let scheduled = ["2026-08-03", "2026-08-05", "2026-08-07"]
        var log = answers(scheduled, yes: true)
        // Heute (So) und gestern (Sa) sind ohnehin nicht fällig.
        XCTAssertEqual(GoalEngine.streak(habit: habit(log, recurrence: rule),
                                         today: "2026-08-09", calendar: monday), 3,
                       "terminfreie Tage sind durchsichtig")
        log["2026-08-08"] = Habit.Answer.no
        XCTAssertEqual(GoalEngine.streak(habit: habit(log, recurrence: rule),
                                         today: "2026-08-09", calendar: monday), 0,
                       "eine Aussage an einem freien Tag ist trotzdem eine Aussage")
    }

    func testBonusYesOnAnUnscheduledDayStillCounts() {
        let rule = Recurrence.weekdays([2, 4, 6])
        var log = answers(["2026-08-03", "2026-08-05", "2026-08-07"], yes: true)
        log["2026-08-08"] = Habit.Answer.yes
        log["2026-08-09"] = Habit.Answer.yes
        XCTAssertEqual(GoalEngine.streak(habit: habit(log, recurrence: rule),
                                         today: "2026-08-09", calendar: monday), 5,
                       "Mehrleistung wird nie bestraft")
    }

    // MARK: Beste Serie

    func testBestStreakUsesTheSameSemantics() {
        var log = answers(["2026-08-01", "2026-08-02", "2026-08-03",
                           "2026-08-06", "2026-08-07", "2026-08-08", "2026-08-09"], yes: true)
        log["2026-08-04"] = Habit.Answer.no
        log["2026-08-05"] = Habit.Answer.no
        XCTAssertEqual(GoalEngine.bestStreak(habit: habit(log), today: "2026-08-09",
                                             calendar: monday), 4)
    }

    func testBestStreakOfNothingButNoIsZero() {
        let log = answers(["2026-08-07", "2026-08-08", "2026-08-09"], yes: false)
        let h = habit(log)
        XCTAssertEqual(GoalEngine.bestStreak(habit: h, today: "2026-08-09", calendar: monday), 0)
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-09", calendar: monday), 0)
        XCTAssertEqual(h.checkInCount(today: "2026-08-09", calendar: monday), 0,
                       "Gesamt zählt keine Verneinungen")
        XCTAssertEqual(h.declinedCount(today: "2026-08-09", calendar: monday), 3)
    }

    // MARK: Quote

    func testCompletionCountsNoInTheDenominator() {
        var log = answers(["2026-08-07", "2026-08-08", "2026-08-09"], yes: true)
        XCTAssertEqual(GoalEngine.completion(habit: habit(log), lastNDays: 3,
                                             today: "2026-08-09", calendar: monday), 1, accuracy: 0.001)
        log["2026-08-08"] = Habit.Answer.no
        XCTAssertEqual(GoalEngine.completion(habit: habit(log), lastNDays: 3,
                                             today: "2026-08-09", calendar: monday),
                       2.0 / 3.0, accuracy: 0.001)
    }

    func testAnsweredDaysEnterTheDenominatorEvenWhenUnscheduled() {
        // Nur Montag ist fällig; das Nein am Dienstag zählt trotzdem.
        let rule = Recurrence.weekdays([2])
        var log = ["2026-08-03": Habit.Answer.yes]
        XCTAssertEqual(GoalEngine.completion(habit: habit(log, recurrence: rule), lastNDays: 7,
                                             today: "2026-08-09", calendar: monday), 1, accuracy: 0.001)
        log["2026-08-04"] = Habit.Answer.no
        XCTAssertEqual(GoalEngine.completion(habit: habit(log, recurrence: rule), lastNDays: 7,
                                             today: "2026-08-09", calendar: monday),
                       0.5, accuracy: 0.001)
    }

    func testABonusYesNeverLowersTheQuota() {
        let rule = Recurrence.weekdays([2])
        var log = ["2026-08-03": Habit.Answer.yes, "2026-08-04": Habit.Answer.no]
        let before = GoalEngine.completion(habit: habit(log, recurrence: rule), lastNDays: 7,
                                           today: "2026-08-09", calendar: monday)
        log["2026-08-05"] = Habit.Answer.yes
        let after = GoalEngine.completion(habit: habit(log, recurrence: rule), lastNDays: 7,
                                          today: "2026-08-09", calendar: monday)
        XCTAssertGreaterThan(after, before)
    }

    /// Bei einem flexiblen Ziel ist die PERIODE die Einheit, nicht der Tag —
    /// ein Nein macht dort einfach keinen zählenden Tag und reißt keine
    /// Periodenserie ab.
    func testFlexibleGoalsMeasureThePeriodNotTheDay() {
        let rule = Recurrence.times(2, per: .weekly)
        var log = answers(["2026-08-03", "2026-08-05"], yes: true)      // Mo, Mi
        log["2026-08-04"] = Habit.Answer.no                              // Di
        let h = habit(log, recurrence: rule)
        XCTAssertTrue(GoalEngine.periodSatisfied(habit: h, day: "2026-08-05",
                                                 today: "2026-08-09", calendar: monday))
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-09", calendar: monday), 1)
    }

    // MARK: Zellstufe

    func testDeclinedGetsItsOwnLevel() {
        let h = habit(["2026-08-08": Habit.Answer.no, "2026-08-09": Habit.Answer.yes])
        XCTAssertEqual(GoalEngine.intensity(habit: h, key: "2026-08-08", calendar: monday),
                       Habit.Answer.declinedLevel)
        XCTAssertNotEqual(GoalEngine.intensity(habit: h, key: "2026-08-08", calendar: monday), 0,
                          "ein Nein ist keine leere Zelle")
        XCTAssertGreaterThanOrEqual(GoalEngine.intensity(habit: h, key: "2026-08-09",
                                                         calendar: monday), 1)
        XCTAssertEqual(GoalEngine.intensity(habit: h, key: "2026-08-07", calendar: monday), 0)
    }

    func testYesShadesByRunLengthAndNoInterruptsTheRun() {
        // Acht Ja-Tage: der letzte leuchtet am hellsten.
        let long = habit(answers((0..<8).compactMap { DayKey.shifted("2026-08-09", by: -$0,
                                                                     calendar: monday) },
                                 yes: true))
        XCTAssertEqual(GoalEngine.intensity(habit: long, key: "2026-08-09", calendar: monday), 4)

        var log = answers((0..<8).compactMap { DayKey.shifted("2026-08-09", by: -$0,
                                                              calendar: monday) }, yes: true)
        log["2026-08-08"] = Habit.Answer.no
        XCTAssertEqual(GoalEngine.intensity(habit: habit(log), key: "2026-08-09", calendar: monday), 1,
                       "der Lauf beginnt nach dem Nein von vorn")
    }

    func testTheGridCacheSeesTheKind() {
        GridCalendar.resetCache()
        var h = habit(["2026-08-08": Habit.Answer.no])
        _ = GridCalendar.snapshot(habit: h, weeks: 4, today: "2026-08-09", calendar: monday)
        let after = GridCalendar.computeCount
        h.kind = .checkbox
        let plain = GridCalendar.snapshot(habit: h, weeks: 4, today: "2026-08-09", calendar: monday)
        XCTAssertGreaterThan(GridCalendar.computeCount, after,
                             "die Art gehört in den Cache-Schlüssel")
        XCTAssertFalse(plain.levels.flatMap { $0 }.contains(Habit.Answer.declinedLevel))
    }
}

// MARK: – 3. Die Oberfläche

/// Jede Fläche, die heute anzeigt oder Zellen malt, muss den dritten Zustand
/// kennen — sonst behauptet eine davon etwas anderes als die Rechnung.
final class YesNoSurfaceTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-ynui-\(UUID().uuidString).json")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: url) }

    private func store(_ habit: Habit) -> HabitStore {
        let s = HabitStore(url: url)
        s.add(habit)
        return s
    }

    // MARK: Schreibwege

    func testAnswerTogglesTheSameAnswerBackOff() {
        let h = Habit(name: "Kein Zucker", kind: .yesNo)
        let s = store(h)
        s.answer(h.id, day: "2026-08-09", yes: false)
        XCTAssertEqual(s.habits[0].log["2026-08-09"], Habit.Answer.no)
        s.answer(h.id, day: "2026-08-09", yes: true)
        XCTAssertEqual(s.habits[0].log["2026-08-09"], Habit.Answer.yes, "umschwenken geht direkt")
        s.answer(h.id, day: "2026-08-09", yes: true)
        XCTAssertNil(s.habits[0].log["2026-08-09"], "dieselbe Antwort noch einmal nimmt sie zurück")
    }

    func testWidgetButtonAnswersYesAndNeverUnanswers() {
        var h = Habit(name: "Kein Zucker", kind: .yesNo)
        h.log["2026-08-09"] = Habit.Answer.no
        let s = store(h)
        XCTAssertTrue(CheckOffLogic.apply(to: s, habitId: h.id, day: "2026-08-09"))
        XCTAssertEqual(s.habits[0].log["2026-08-09"], Habit.Answer.yes,
                       "der Knopf meint Ja")
        XCTAssertFalse(CheckOffLogic.apply(to: s, habitId: h.id, day: "2026-08-09"),
                       "idempotent — er nimmt das Ja nicht zurück")
        XCTAssertEqual(s.habits[0].log["2026-08-09"], Habit.Answer.yes)
    }

    // MARK: Nacharbeiten

    func testBackfillStateIsTheThirdState() {
        var h = Habit(name: "Kein Zucker", kind: .yesNo)
        h.log = ["2026-08-07": Habit.Answer.yes, "2026-08-08": Habit.Answer.no]
        XCTAssertEqual(Backfill.state(habit: h, day: "2026-08-07"), .done)
        XCTAssertEqual(Backfill.state(habit: h, day: "2026-08-08"), .declined)
        XCTAssertEqual(Backfill.state(habit: h, day: "2026-08-06"), .empty)
        XCTAssertFalse(Backfill.state(habit: h, day: "2026-08-08").counts)
    }

    func testBackfillStateForgivesALegacyOne() {
        var h = Habit(name: "Kein Zucker", kind: .yesNo)
        h.log = ["2026-08-07": 1]   // von einem ausgelieferten Build
        XCTAssertEqual(Backfill.state(habit: h, day: "2026-08-07"), .done)
    }

    func testEveryYesNoStateOffersExactlyTwoUsefulActions() {
        for (state, kinds) in [(Backfill.DayState.empty, [Backfill.Action.Kind.affirmed, .declined]),
                               (.done, [.declined, .clear]),
                               (.declined, [.affirmed, .clear])] {
            let actions = Backfill.actions(for: state, kind: .yesNo)
            XCTAssertEqual(actions.map(\.kind), kinds, "Zustand \(state)")
        }
    }

    func testYesNoActionsWriteTheReservedCodes() {
        XCTAssertEqual(Backfill.Action.affirm.value, Habit.Answer.yes)
        XCTAssertEqual(Backfill.Action.decline.value, Habit.Answer.no)
        XCTAssertNil(Backfill.Action.clear.value)
        XCTAssertEqual(Backfill.Action.affirm.accessibilityIdentifier, "backfill-action-affirmed")
        XCTAssertEqual(Backfill.Action.decline.accessibilityIdentifier, "backfill-action-declined")
    }

    func testCheckboxActionsAreUnchanged() {
        XCTAssertEqual(Backfill.actions(for: .empty).map(\.kind), [.done])
        XCTAssertEqual(Backfill.actions(for: .done).map(\.kind), [.clear])
        XCTAssertEqual(Backfill.actions(for: .quantity(value: 1, target: 3)).map(\.kind),
                       [.quantity, .clear])
    }

    func testMultiSelectWritesYes() {
        var h = Habit(name: "Kein Zucker", kind: .yesNo)
        h.kind = .yesNo
        let set = Backfill.setActions(habit: h)
        XCTAssertEqual(set.map(\.kind), [.affirmed, .clear])
        XCTAssertEqual(set[0].value, Habit.Answer.yes)
    }

    func testStatusTextSpeaksTheLanguageOfTheQuestion() {
        XCTAssertEqual(Backfill.statusText(for: .declined), Backfill.statusText(for: .declined))
        XCTAssertNotEqual(Backfill.statusText(for: .done, kind: .yesNo),
                          Backfill.statusText(for: .done, kind: .checkbox))
        XCTAssertNotEqual(Backfill.statusText(for: .empty, kind: .yesNo),
                          Backfill.statusText(for: .empty, kind: .checkbox))
    }

    // MARK: Zusammenfassung

    func testADeclinedDayIsNeitherDoneNorOpen() {
        var h = Habit(name: "Kein Zucker", kind: .yesNo)
        h.log["2026-08-09"] = Habit.Answer.no
        let s = store(h)
        s.add(Habit(name: "Lesen"))
        let status = s.dailyStatus("2026-08-09")
        XCTAssertEqual(status.total, 2)
        XCTAssertEqual(status.done, 0)
        XCTAssertEqual(status.missing, ["Lesen"],
                       "an eine beantwortete Frage wird nicht erinnert")
        XCTAssertEqual(s.openToday("2026-08-09").map(\.name), ["Lesen"])
    }

    // MARK: Widget

    func testWidgetStatusHasItsOwnCaseForNo() {
        var h = Habit(name: "Kein Zucker", kind: .yesNo)
        h.log["2026-08-09"] = Habit.Answer.no
        XCTAssertEqual(WidgetLogic.status(habit: h, today: "2026-08-09"), .declined)
        h.log["2026-08-09"] = Habit.Answer.yes
        XCTAssertEqual(WidgetLogic.status(habit: h, today: "2026-08-09"), .done)
        h.log["2026-08-09"] = nil
        XCTAssertEqual(WidgetLogic.status(habit: h, today: "2026-08-09"), .open)
    }

    func testWidgetStatusPrefersDeclinedOverFree() {
        var h = Habit(name: "Kein Zucker", recurrence: .weekdays([2]), kind: .yesNo)
        h.kind = .yesNo
        h.log["2026-08-09"] = Habit.Answer.no   // Sonntag, kein Termin
        XCTAssertEqual(WidgetLogic.status(habit: h, today: "2026-08-09"), .declined)
    }

    func testWidgetRingCountsADeclinedDayAsNotMet() {
        var h = Habit(name: "Kein Zucker", kind: .yesNo)
        h.log["2026-08-09"] = Habit.Answer.no
        let progress = WidgetLogic.progress(habits: [h], today: "2026-08-09")
        XCTAssertEqual(progress.due, 1)
        XCTAssertEqual(progress.met, 0)
    }

    func testLockScreenGivesTheDeclinedCellItsOwnOpacity() {
        // Auf dem Sperrbildschirm gibt es keine Farbe — die einzige freie
        // Richtung ist unter die leere Zelle.
        let declined = WidgetInk.opacity(Habit.Answer.declinedLevel)
        XCTAssertLessThan(declined, WidgetInk.opacities[0])
        for (i, step) in WidgetInk.opacities.enumerated() {
            XCTAssertGreaterThanOrEqual(abs(step - declined), 0.05,
                                        "Verneinung ist von Stufe \(i) nicht zu unterscheiden")
        }
        // Und die fünf Stufen bleiben unangetastet.
        for level in 0...4 {
            XCTAssertEqual(WidgetInk.opacity(level), WidgetInk.opacities[level])
        }
    }

    // MARK: Rückgängig-Meldung

    func testUndoMessageNamesTheAnswer() {
        var h = Habit(name: "Kein Zucker", kind: .yesNo)
        h.kind = .yesNo
        let no = CheckInUndo.message(habit: h, value: Habit.Answer.no, day: "2026-08-09",
                                     today: "2026-08-09")
        let yes = CheckInUndo.message(habit: h, value: Habit.Answer.yes, day: "2026-08-09",
                                      today: "2026-08-09")
        let none = CheckInUndo.message(habit: h, value: 0, day: "2026-08-09", today: "2026-08-09")
        XCTAssertNotEqual(no, yes)
        XCTAssertNotEqual(no, none)
        XCTAssertNotEqual(yes, none)
    }
}

// MARK: – Die Farbe der Verneinung

/// Die Verneinung wird durch DENSELBEN OKLCH-Löser gerechnet wie jede Rampe
/// und muss deshalb auch dieselbe Art Zusage einhalten: sie ist von der
/// leeren Zelle UND von jeder gefüllten Stufe unterscheidbar — in beiden
/// Schemata, für alle sechs eingebauten Familien und für jede Farbe, die ein
/// Nutzer wählen kann.
final class YesNoColorTests: XCTestCase {
    /// Dieselbe Schwelle, die auch zwischen zwei Rampenstufen gilt.
    private let minStep = 1.15

    private func hueDistance(_ a: UInt32, _ b: UInt32) -> Double? {
        guard let x = PaletteGenerator.hueDegrees(a), let y = PaletteGenerator.hueDegrees(b)
        else { return nil }
        let d = abs(x - y).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    private func check(_ style: PaletteStyle, _ label: String) {
        for dark in [false, true] {
            let ramp = style.ramp(dark: dark)
            let negative = style.negative(dark: dark)
            let scheme = dark ? "dunkel" : "hell"
            for (i, level) in ramp.enumerated() {
                XCTAssertGreaterThanOrEqual(Contrast.ratio(negative, level), minStep,
                    "\(label) \(scheme): Verneinung sieht aus wie l\(i)")
            }
            // Sichtbar auf der Karte — deutlich mehr als die leere Zelle
            // (die bei höchstens 1,85 : 1 liegt).
            XCTAssertGreaterThanOrEqual(Contrast.ratio(negative, Theme.cardHex(dark: dark)), 2.0,
                "\(label) \(scheme): Verneinung verschwindet in der Karte")
            // Und nicht so schwer, dass sie die Rampe überstimmt.
            XCTAssertLessThanOrEqual(Contrast.ratio(negative, Theme.cardHex(dark: dark)),
                                     Contrast.ratio(ramp[4], Theme.cardHex(dark: dark)),
                "\(label) \(scheme): Verneinung ist schwerer als die vollste Stufe")
        }
    }

    func testBuiltinPalettesAllHaveADistinguishableNegative() {
        for palette in GraphPalette.allCases {
            check(palette.style, palette.rawValue)
        }
    }

    func testGeneratedPalettesAllHaveADistinguishableNegative() {
        for (label, base) in GeneratedRampInvariantTests.bases {
            check(PaletteGenerator.style(base: base), label)
        }
    }

    /// Die Verneinung weicht dem Farbton der Palette aus. Sie ist rot, außer
    /// die Palette ist es selbst — dann gilt Unterscheidbarkeit mehr als
    /// Konvention (Rosé bekommt den Gegenfarbton).
    func testNegativeKeepsItsDistanceFromThePaletteHue() {
        let clearance = PaletteGenerator.negativeHueClearance * 180 / .pi
        for (label, base) in GeneratedRampInvariantTests.bases {
            let style = PaletteGenerator.style(base: base)
            for dark in [false, true] {
                guard let distance = hueDistance(style.negative(dark: dark), base) else { continue }
                XCTAssertGreaterThanOrEqual(distance, clearance - 12,
                    "\(label) \(dark ? "dunkel" : "hell"): Verneinung liegt im Farbton der Palette")
            }
        }
    }

    func testNegativeIsRedWhereThePaletteLeavesRoom() {
        // Grün, Blau, Violett und Monochrom lassen Rot frei.
        for palette in [GraphPalette.green, .blue, .violet, .gray] {
            for dark in [false, true] {
                let hue = PaletteGenerator.hueDegrees(palette.style.negative(dark: dark))
                XCTAssertNotNil(hue, "\(palette) \(dark): die Verneinung ist immer bunt")
                XCTAssertLessThan(min(abs((hue ?? 0) - 29), 360 - abs((hue ?? 0) - 29)), 25,
                                  "\(palette) \(dark ? "dunkel" : "hell"): das sollte Rot sein")
            }
        }
    }

    func testRosePaletteDodgesToItsComplement() {
        // Rosé liegt selbst bei 9° — ein rotes Nein wäre dort eine Zelle wie
        // jede andere.
        for dark in [false, true] {
            let hue = PaletteGenerator.hueDegrees(GraphPalette.rose.style.negative(dark: dark)) ?? 0
            XCTAssertGreaterThan(min(abs(hue - 29), 360 - abs(hue - 29)), 60,
                                 "\(dark ? "dunkel" : "hell"): Rosé darf nicht rot verneinen")
        }
    }

    func testEveryPaletteHasItsOwnNegative() {
        // Sie hängt an der Rampe — zwei Familien dürfen sie sich nicht teilen
        // (sonst sähe dieselbe Farbe in zwei Rastern verschieden „richtig" aus).
        for dark in [false, true] {
            let all = GraphPalette.allCases.map { $0.style.negative(dark: dark) }
            XCTAssertEqual(Set(all).count, all.count, dark ? "dunkel" : "hell")
        }
    }

    func testThemeMapsTheDeclinedLevelAndStillClampsGarbage() {
        for palette in GraphPalette.allCases {
            for dark in [false, true] {
                XCTAssertEqual(Theme.level(Habit.Answer.declinedLevel, dark: dark, palette: palette),
                               Theme.color(palette.style.negative(dark: dark)))
                XCTAssertNotEqual(Theme.level(Habit.Answer.declinedLevel, dark: dark, palette: palette),
                                  Theme.level(0, dark: dark, palette: palette))
                // Jeder ANDERE Ausreißer bleibt ein Fehler und wird geklemmt.
                XCTAssertEqual(Theme.level(-3, dark: dark, palette: palette),
                               Theme.level(0, dark: dark, palette: palette))
                XCTAssertEqual(Theme.level(99, dark: dark, palette: palette),
                               Theme.level(4, dark: dark, palette: palette))
            }
        }
    }

    func testNegativeIsStableAcrossReads() {
        // Sie wird gecacht; zwei Lesungen derselben Palette müssen dieselbe
        // Farbe geben (sonst flackerte das Raster beim Scrollen).
        for palette in GraphPalette.allCases {
            XCTAssertEqual(palette.style.negative(dark: false), palette.style.negative(dark: false))
            XCTAssertEqual(palette.style.negative(dark: true), palette.style.negative(dark: true))
        }
    }
}
