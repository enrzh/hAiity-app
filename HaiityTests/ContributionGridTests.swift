import XCTest
@testable import Haiity

/// Gemeinsame Basis: fester gregorianischer Kalender in Berlin, damit die
/// Wochentage reproduzierbar sind. Verifizierte Anker:
/// 2026-08-09 = Sonntag, 2026-08-02 = Sonntag, 2024-08-11 = Sonntag.
class GridTestCase: XCTestCase {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        c.firstWeekday = 2
        return c
    }()

    func habit(_ log: [String: Int] = [:],
               recurrence: Recurrence = .daily,
               createdAt: String = "2025-01-01") -> Habit {
        var h = Habit(name: "Test", recurrence: recurrence)
        h.createdAt = createdAt
        h.log = log
        return h
    }

    /// n aufeinanderfolgende Tage rückwärts ab `end`, alle mit `value`.
    func run(days: Int, endingAt end: String, value: Int = 1) -> [String: Int] {
        var out: [String: Int] = [:]
        var day = end
        for _ in 0..<days {
            out[day] = value
            guard let p = DayKey.shifted(day, by: -1, calendar: cal) else { break }
            day = p
        }
        return out
    }
}

// MARK: – Monatsbeschriftung

/// Die Spaltenmathematik der Monatszeile ist eine reine Funktion —
/// hier wird sie festgenagelt, inklusive Jahreswechsel und Februar.
final class MonthLabelTests: GridTestCase {

    func testMarksForFullYearWindow() {
        // Fenster 2025-08-10 … 2026-08-15, Spaltenstart ist immer ein Sonntag.
        let marks = GridCalendar.rawMarks(weeks: 53, today: "2026-08-09", calendar: cal)
        XCTAssertEqual(marks.map(\.column), [4, 8, 12, 17, 21, 25, 29, 34, 38, 43, 47, 51])
        XCTAssertEqual(marks.map(\.month), [9, 10, 11, 12, 1, 2, 3, 4, 5, 6, 7, 8])
    }

    func testMarksCrossYearBoundary() {
        let marks = GridCalendar.rawMarks(weeks: 53, today: "2026-08-09", calendar: cal)
        // Dezember 2025 und Januar 2026 stehen direkt nebeneinander — die
        // Jahreszahl unterscheidet sie, das Label allein täte es nicht.
        XCTAssertEqual(marks[3], MonthMark(column: 17, year: 2025, month: 12))
        XCTAssertEqual(marks[4], MonthMark(column: 21, year: 2026, month: 1))
    }

    func testFebruaryOccupiesFourColumns() {
        // 2026: 1.2. ist ein Sonntag, Februar hat 28 Tage -> exakt vier
        // Spalten, März beginnt bei Spalte 29.
        let marks = GridCalendar.rawMarks(weeks: 53, today: "2026-08-09", calendar: cal)
        let feb = marks.first { $0.month == 2 && $0.year == 2026 }
        let mar = marks.first { $0.month == 3 && $0.year == 2026 }
        XCTAssertEqual(feb?.column, 25)
        XCTAssertEqual(mar?.column, 29)
        XCTAssertEqual((mar?.column ?? 0) - (feb?.column ?? 0), 4)
    }

    func testLeapYearFebruaryStillLabelled() {
        // 2024 ist ein Schaltjahr; Februar bekommt trotzdem genau eine Marke.
        let marks = GridCalendar.rawMarks(weeks: 53, today: "2024-08-11", calendar: cal)
        XCTAssertEqual(marks.filter { $0.month == 2 }.count, 1)
        XCTAssertEqual(marks.first { $0.month == 2 }?.column, 25)
        XCTAssertEqual(marks.map(\.column), [3, 7, 12, 16, 21, 25, 29, 34, 38, 42, 47, 51])
    }

    func testFirstColumnLabelledOnlyAtMonthStart() {
        // weeks = 6 -> Spalte 0 beginnt am 05.07. (Monatsanfang) -> Marke.
        XCTAssertEqual(GridCalendar.rawMarks(weeks: 6, today: "2026-08-09", calendar: cal).first?.column, 0)
        // weeks = 7 -> Spalte 0 beginnt am 28.06., mitten im Monat -> keine
        // Marke, sonst stünde "Jun" über einer Spalte, in der Juni endet.
        XCTAssertEqual(GridCalendar.rawMarks(weeks: 7, today: "2026-08-09", calendar: cal).first?.column, 1)
    }

    /// Standardraster: 12 pt Zelle + 3 pt Lücke.
    private let pitch: CGFloat = 15
    private var contentWidth: CGFloat { 53 * pitch - 3 }

    func testNarrowLabelsAllFit() {
        let marks = GridCalendar.rawMarks(weeks: 53, today: "2026-08-09", calendar: cal)
        let placed = GridCalendar.placeMarks(marks, pitch: pitch, contentWidth: contentWidth) { _ in 26 }
        XCTAssertEqual(placed.map(\.mark.column), [4, 8, 12, 17, 21, 25, 29, 34, 38, 43, 47, 51])
        // Jedes Label steht über seiner Spalte …
        for p in placed.dropLast() {
            XCTAssertEqual(p.x, CGFloat(p.mark.column) * pitch, accuracy: 0.01)
        }
        // … und keins überlappt das nächste.
        for (a, b) in zip(placed, placed.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.x, a.x + 26)
        }
    }

    func testWideLabelsDropInsteadOfOverlapping() {
        let marks = GridCalendar.rawMarks(weeks: 53, today: "2026-08-09", calendar: cal)
        // Große Dynamic-Type-Stufe: ein Label ist breiter als vier Spalten.
        let placed = GridCalendar.placeMarks(marks, pitch: pitch, contentWidth: contentWidth) { _ in 70 }
        XCTAssertLessThan(placed.count, marks.count)
        for (a, b) in zip(placed, placed.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.x - (a.x + 70), 4, "Labels dürfen sich nie berühren")
        }
    }

    func testRightEdgeLabelShiftsLeftInsteadOfClipping() {
        // today = 02.08.2026 (Sonntag) -> die August-Marke liegt auf der
        // letzten Spalte. Ein breites Label (arabisch, große Schrift) würde
        // dort abgeschnitten; es rutscht nach links statt zu verschwinden.
        let marks = GridCalendar.rawMarks(weeks: 53, today: "2026-08-02", calendar: cal)
        XCTAssertEqual(marks.last?.column, 52)
        let placed = GridCalendar.placeMarks(marks, pitch: pitch, contentWidth: contentWidth) { _ in 30 }
        XCTAssertEqual(placed.last?.mark.column, 52)
        XCTAssertEqual(placed.last?.x ?? 0, contentWidth - 30, accuracy: 0.01,
                       "die letzte Marke rutscht genau an den rechten Rand")
        XCTAssertLessThanOrEqual((placed.last?.x ?? 0) + 30, contentWidth,
                                 "nichts ragt über das Raster hinaus")
    }

    func testRightEdgeLabelDroppedWhenShiftingWouldOverlap() {
        // Sehr breites Label (arabisch bei großer Schrift): der Platz links
        // gehört schon dem Vormonat -> lieber weglassen als überlappen.
        let marks = GridCalendar.rawMarks(weeks: 53, today: "2026-08-02", calendar: cal)
        let placed = GridCalendar.placeMarks(marks, pitch: pitch, contentWidth: contentWidth) { _ in 48 }
        XCTAssertEqual(placed.last?.mark.column, 48)
        XCTAssertNil(placed.first { $0.mark.column == 52 })
    }

    func testEveryLabelStaysInsideTheGrid() {
        let marks = GridCalendar.rawMarks(weeks: 53, today: "2026-08-09", calendar: cal)
        for w in [12, 26, 40, 70, 120] as [CGFloat] {
            let placed = GridCalendar.placeMarks(marks, pitch: pitch, contentWidth: contentWidth) { _ in w }
            for p in placed {
                XCTAssertGreaterThanOrEqual(p.x, 0)
                XCTAssertLessThanOrEqual(p.x + w, contentWidth, "Breite \(w) ragt heraus")
            }
        }
    }

    func testLabelWiderThanGridIsDropped() {
        let marks = GridCalendar.rawMarks(weeks: 53, today: "2026-08-09", calendar: cal)
        XCTAssertTrue(GridCalendar.placeMarks(marks, pitch: pitch, contentWidth: 100) { _ in 200 }.isEmpty)
    }

    func testLabelsAreLocalized() {
        var de = cal; de.locale = Locale(identifier: "de_DE")
        var en = cal; en.locale = Locale(identifier: "en_US")
        let december = MonthMark(column: 0, year: 2026, month: 12)
        // Bewusst mit hasPrefix statt exaktem Vergleich: die CLDR-Form
        // wechselt zwischen ICU-Versionen ("Dez" vs. "Dez."), die Sprache
        // nicht.
        XCTAssertTrue(GridCalendar.label(for: december, calendar: de).hasPrefix("Dez"))
        XCTAssertTrue(GridCalendar.label(for: december, calendar: en).hasPrefix("Dec"))
        XCTAssertNotEqual(GridCalendar.label(for: december, calendar: de),
                          GridCalendar.label(for: december, calendar: en))
        XCTAssertTrue(GridCalendar.label(for: MonthMark(column: 0, year: 2026, month: 1),
                                         calendar: de).hasPrefix("Jan"))
    }

    func testLabelOutOfRangeIsEmptyNotACrash() {
        XCTAssertEqual(GridCalendar.label(for: MonthMark(column: 0, year: 2026, month: 13), calendar: cal), "")
        XCTAssertEqual(GridCalendar.label(for: MonthMark(column: 0, year: 2026, month: 0), calendar: cal), "")
    }
}

// MARK: – Fenster, Ränder, Zukunft

final class GridWindowTests: GridTestCase {

    func testWindowIsExactlyWeeksTimesSevenCells() {
        let keys = GridCalendar.keys(weeks: 53, today: "2026-08-09", calendar: cal)
        XCTAssertEqual(keys.count, 53)
        XCTAssertTrue(keys.allSatisfy { $0.count == 7 })
    }

    func testTodayIsInTheLastColumn() {
        let keys = GridCalendar.keys(weeks: 53, today: "2026-08-09", calendar: cal)
        XCTAssertTrue(keys[52].contains("2026-08-09"))
        // 09.08.2026 ist ein Sonntag -> erste Zeile der letzten Spalte.
        XCTAssertEqual(keys[52][0], "2026-08-09")
    }

    func testFutureCellsAreNil() {
        let keys = GridCalendar.keys(weeks: 53, today: "2026-08-09", calendar: cal)
        // Sonntag ist heute -> Mo…Sa derselben Spalte liegen in der Zukunft.
        XCTAssertEqual(keys[52].compactMap { $0 }, ["2026-08-09"])
        XCTAssertEqual(keys[52].filter { $0 == nil }.count, 6)
        // Kein einziger Schlüssel im ganzen Fenster liegt nach heute.
        XCTAssertTrue(keys.flatMap { $0 }.compactMap { $0 }.allSatisfy { $0 <= "2026-08-09" })
    }

    func testFutureCellsAreNotTappable() {
        XCTAssertFalse(GridCalendar.isTappable(key: nil, interactive: true, today: "2026-08-09"))
        XCTAssertFalse(GridCalendar.isTappable(key: "2026-08-10", interactive: true, today: "2026-08-09"))
        XCTAssertFalse(GridCalendar.isTappable(key: "2099-01-01", interactive: true, today: "2026-08-09"))
        XCTAssertFalse(GridCalendar.isTappable(key: "quatsch", interactive: true, today: "2026-08-09"))
        XCTAssertFalse(GridCalendar.isTappable(key: "2026-08-08", interactive: false, today: "2026-08-09"))
        XCTAssertTrue(GridCalendar.isTappable(key: "2026-08-09", interactive: true, today: "2026-08-09"))
        XCTAssertTrue(GridCalendar.isTappable(key: "2025-12-31", interactive: true, today: "2026-08-09"))
    }

    // MARK: – Treffertest des gemeinsamen Tipp-Erkenners
    //
    // Seit die Zellen keinen eigenen Erkenner mehr tragen, entscheidet
    // `hitKey` über die Trefferfläche. Sie muss exakt die alte sein: die
    // Zelle trifft, die Lücke nicht, außerhalb ist nichts.

    func testHitKeyMapsPointsToCells() {
        let keys = GridCalendar.keys(weeks: 53, today: "2026-08-09", calendar: cal)
        let cell: CGFloat = 11, gap: CGFloat = 3   // pitch 14
        // Ecke der ersten Zelle -> ältester Sonntag.
        XCTAssertEqual(GridCalendar.hitKey(location: CGPoint(x: 0, y: 0),
                                           keys: keys, cell: cell, gap: gap), keys[0][0])
        // Mitte einer mittleren Zelle.
        XCTAssertEqual(GridCalendar.hitKey(location: CGPoint(x: 14 * 10 + 5, y: 14 * 3 + 5),
                                           keys: keys, cell: cell, gap: gap), keys[10][3])
        // Letzte Spalte, Zeile heute (Sonntag).
        XCTAssertEqual(GridCalendar.hitKey(location: CGPoint(x: 14 * 52 + 1, y: 1),
                                           keys: keys, cell: cell, gap: gap), keys[52][0])
        // Zukunftszelle liefert nil-Schlüssel (Spalte heute, Zeile morgen).
        XCTAssertNil(GridCalendar.hitKey(location: CGPoint(x: 14 * 52 + 1, y: 14 + 1),
                                         keys: keys, cell: cell, gap: gap))
    }

    func testHitKeyMissesGapsAndOutside() {
        let keys = GridCalendar.keys(weeks: 53, today: "2026-08-09", calendar: cal)
        let cell: CGFloat = 11, gap: CGFloat = 3
        // In der Lücke rechts neben bzw. unter einer Zelle: kein Treffer.
        XCTAssertNil(GridCalendar.hitKey(location: CGPoint(x: 12, y: 5),
                                         keys: keys, cell: cell, gap: gap))
        XCTAssertNil(GridCalendar.hitKey(location: CGPoint(x: 5, y: 12),
                                         keys: keys, cell: cell, gap: gap))
        // Außerhalb des Rasters.
        XCTAssertNil(GridCalendar.hitKey(location: CGPoint(x: -1, y: 0),
                                         keys: keys, cell: cell, gap: gap))
        XCTAssertNil(GridCalendar.hitKey(location: CGPoint(x: 0, y: 14 * 7 + 1),
                                         keys: keys, cell: cell, gap: gap))
        XCTAssertNil(GridCalendar.hitKey(location: CGPoint(x: 14 * 53 + 1, y: 0),
                                         keys: keys, cell: cell, gap: gap))
        // Entartete Maße stürzen nicht ab.
        XCTAssertNil(GridCalendar.hitKey(location: .zero, keys: keys, cell: 0, gap: 0))
    }

    func testHabitCreatedTodayRendersEmptyGrid() {
        let h = habit(createdAt: "2026-08-09")
        let snap = GridCalendar.snapshot(habit: h, weeks: 53, today: "2026-08-09", calendar: cal)
        XCTAssertEqual(snap.keys.count, 53)
        XCTAssertEqual(snap.filledCount, 0)
        XCTAssertTrue(snap.levels.flatMap { $0 }.allSatisfy { $0 == 0 })
        // Nur heute ist tippbar-relevant: alles danach ist nil.
        XCTAssertTrue(GridCalendar.isTappable(key: snap.keys[52][0], interactive: true, today: snap.today))
    }

    func testHabitCreatedMidYearHasHistoryOnlyAfterCreation() {
        let h = habit(run(days: 40, endingAt: "2026-08-09"), createdAt: "2026-07-01")
        let snap = GridCalendar.snapshot(habit: h, weeks: 53, today: "2026-08-09", calendar: cal)
        XCTAssertEqual(snap.filledCount, 40)
        // Die ältesten Spalten (vor der Anlage) bleiben leer.
        XCTAssertTrue(snap.levels[0].allSatisfy { $0 == 0 })
    }

    func testDisplayWindowKeepsARecentHabitWithinTheViewport() {
        let recent = habit([:], createdAt: "2026-08-01")
        let weeks = GridCalendar.weeksForDisplay(habit: recent,
                                                 today: "2026-08-09",
                                                 minimumWeeks: 24,
                                                 maximumWeeks: 53,
                                                 calendar: cal)

        XCTAssertEqual(weeks, 24)
    }

    func testDisplayWindowTracksOlderMeaningfulHistoryWithoutAFullBlankYear() {
        let older = habit(run(days: 5, endingAt: "2026-08-09"),
                          createdAt: "2026-01-01")
        let weeks = GridCalendar.weeksForDisplay(habit: older,
                                                 today: "2026-08-09",
                                                 minimumWeeks: 24,
                                                 maximumWeeks: 53,
                                                 calendar: cal)

        XCTAssertGreaterThan(weeks, 24)
        XCTAssertLessThan(weeks, 53)
    }

    func testHorizontalScrollIsDisabledWhenTheGraphFitsItsViewport() {
        XCTAssertFalse(GridCalendar.needsHorizontalScroll(contentWidth: 320,
                                                           viewportWidth: 320))
        XCTAssertFalse(GridCalendar.needsHorizontalScroll(contentWidth: 320,
                                                           viewportWidth: 320.4))
        XCTAssertTrue(GridCalendar.needsHorizontalScroll(contentWidth: 320.6,
                                                          viewportWidth: 320))
        XCTAssertTrue(GridCalendar.needsHorizontalScroll(contentWidth: 320,
                                                          viewportWidth: 0))
    }

    func testLongHistoryClampsWindowButKeepsTotals() {
        // 500 Tage Historie = mehr als 53 Wochen (371 Tage).
        let h = habit(run(days: 500, endingAt: "2026-08-09"), createdAt: "2025-01-01")
        let snap = GridCalendar.snapshot(habit: h, weeks: 53, today: "2026-08-09", calendar: cal)
        XCTAssertEqual(snap.keys.count, 53, "Layout darf nie über 53 Spalten wachsen")
        XCTAssertEqual(snap.filledCount, 371 - 6, "sichtbares Fenster minus die 6 Zukunftszellen")
        // Die Gesamtzahl kennt die ganze Historie, nicht nur das Fenster.
        XCTAssertEqual(h.checkInCount(today: "2026-08-09", calendar: cal), 500)
        XCTAssertEqual(StatsMath.totalCheckIns([h], today: "2026-08-09", calendar: cal), 500)
    }

    func testZeroWeeksIsEmptyNotACrash() {
        XCTAssertTrue(GridCalendar.keys(weeks: 0, today: "2026-08-09", calendar: cal).isEmpty)
        XCTAssertTrue(GridCalendar.rawMarks(weeks: 0, today: "2026-08-09", calendar: cal).isEmpty)
    }

    func testQuantityHabitShadesByRatio() {
        // 1/3 muss sichtbar heller sein als 3/3 — sonst ist die Mengen-
        // Semantik im Raster unsichtbar. Der erste Zähler landet auf der
        // NIEDRIGSTEN Stufe; früher sprang 1/3 direkt auf Stufe 2 und die
        // hellste Schattierung kam bei kleinen Zielen nie vor.
        let h = habit(["2026-08-07": 1, "2026-08-08": 2, "2026-08-09": 3],
                      recurrence: Recurrence(target: 3), createdAt: "2026-08-01")
        let snap = GridCalendar.snapshot(habit: h, weeks: 53, today: "2026-08-09", calendar: cal)
        let levels = Dictionary(uniqueKeysWithValues:
            zip(snap.keys.flatMap { $0 }, snap.levels.flatMap { $0 })
                .compactMap { key, level in key.map { ($0, level) } })
        XCTAssertEqual(levels["2026-08-07"], 1)
        XCTAssertEqual(levels["2026-08-08"], 2)
        XCTAssertEqual(levels["2026-08-09"], 4)
        XCTAssertLessThan(levels["2026-08-07"] ?? 0, levels["2026-08-09"] ?? 0)
        // Nur der volle Tag zählt als erledigt.
        XCTAssertEqual(snap.filledCount, 1)
    }
}

// MARK: – Müll- und Angriffsdaten aus Import/Sync

final class HostileDataTests: GridTestCase {
    /// Ein Log, wie es aus einer manipulierten oder kaputten Datei kommt.
    private var poison: [String: Int] {
        ["quatsch": 1,                 // gar kein Datum
         "": 1,                        // leer
         "2026-8-9": 1,                // ungepolstert
         "2026-13-45": 1,              // unmöglicher Monat/Tag
         "2026-02-30": 1,              // 30. Februar
         "2026-00-00": 1,              // Nullen
         "2099-01-01": 1,              // ferne Zukunft
         "1900-01-01": 1,              // ferne Vergangenheit
         "2026-08-06": 0,              // Nullwert
         "2026-08-05": -3,             // negativer Wert
         "2026-08-09": 1]              // der einzige echte Check-in
    }

    func testDayKeyRejectsGarbage() {
        for key in ["quatsch", "", "2026-8-9", "2026-13-45", "2026-02-30",
                    "2026-00-00", "2026-08-09T12:00", "20260809", "-100-01-01",
                    "٢٠٢٦-٠٨-٠٩"] {
            XCTAssertNil(DayKey.date(from: key, calendar: cal), "\(key) darf kein Datum ergeben")
            XCTAssertFalse(DayKey.isValid(key, calendar: cal))
        }
        XCTAssertNotNil(DayKey.date(from: "2026-08-09", calendar: cal))
        XCTAssertNotNil(DayKey.date(from: "2024-02-29", calendar: cal), "Schalttag ist gültig")
        XCTAssertNil(DayKey.date(from: "2026-02-29", calendar: cal), "2026 ist kein Schaltjahr")
    }

    func testPlausibilityRejectsFutureAndAncientDays() {
        XCTAssertTrue(DayKey.isPlausible("2026-08-09", today: "2026-08-09", calendar: cal))
        XCTAssertTrue(DayKey.isPlausible("2020-01-01", today: "2026-08-09", calendar: cal))
        XCTAssertFalse(DayKey.isPlausible("2026-08-10", today: "2026-08-09", calendar: cal))
        XCTAssertFalse(DayKey.isPlausible("2099-01-01", today: "2026-08-09", calendar: cal))
        XCTAssertFalse(DayKey.isPlausible("1900-01-01", today: "2026-08-09", calendar: cal))
    }

    func testValidDaysKeepsOnlyTheRealCheckIn() {
        let h = habit(poison, createdAt: "2026-08-01")
        XCTAssertEqual(h.validDays(today: "2026-08-09", calendar: cal), ["2026-08-09"])
        XCTAssertEqual(h.checkInCount(today: "2026-08-09", calendar: cal), 1)
    }

    func testGridIgnoresGarbageAndRendersFullWindow() {
        let h = habit(poison, createdAt: "2026-08-01")
        let snap = GridCalendar.snapshot(habit: h, weeks: 53, today: "2026-08-09", calendar: cal)
        XCTAssertEqual(snap.keys.count, 53)
        XCTAssertEqual(snap.filledCount, 1)
        // Kein Müllschlüssel taucht im Raster auf …
        let rendered = Set(snap.keys.flatMap { $0 }.compactMap { $0 })
        XCTAssertTrue(rendered.isDisjoint(with: ["quatsch", "2026-13-45", "2099-01-01", "1900-01-01"]))
        // … und genau eine Zelle leuchtet.
        XCTAssertEqual(snap.levels.flatMap { $0 }.filter { $0 > 0 }.count, 1)
    }

    func testStatsDoNotCountGarbage() {
        let h = habit(poison, createdAt: "2026-08-01")
        XCTAssertEqual(StatsMath.totalCheckIns([h], today: "2026-08-09", calendar: cal), 1)
        let months = StatsMath.monthlyCounts(habit: h, months: 12, today: "2026-08-09", calendar: cal)
        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(months.reduce(0, +), 1)
        XCTAssertEqual(months.last, 1)
    }

    func testStreaksDoNotCountGarbage() {
        let h = habit(poison, createdAt: "2026-08-01")
        // Nur der 09.08. zählt: Serie 1, beste Serie 1 — "quatsch" ist kein Tag.
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-09", calendar: cal), 1)
        XCTAssertEqual(h.bestStreak(today: "2026-08-09", calendar: cal), 1)
    }

    func testWeeklyTargetCannotBeMetWithGarbage() {
        // Fünf Müllschlüssel in derselben "Woche" dürfen ein 3×/Woche-Ziel
        // nicht erfüllen.
        var log = ["quatsch": 1, "2026-13-01": 1, "2026-13-02": 1,
                   "2026-02-30": 1, "2099-08-05": 1]
        log["2026-08-05"] = 1
        let h = habit(log, recurrence: .times(3, per: .weekly), createdAt: "2026-08-01")
        XCTAssertEqual(GoalEngine.streak(habit: h, today: "2026-08-09", calendar: cal), 0)
    }

    func testCompletionIgnoresNonPositiveValues() {
        let h = habit(["2026-08-09": 0, "2026-08-08": -1], createdAt: "2026-08-08")
        XCTAssertEqual(GoalEngine.completion(habit: h, lastNDays: 2, today: "2026-08-09", calendar: cal), 0)
        XCTAssertFalse(GoalEngine.dayCounts(habit: h, day: "2026-08-08", calendar: cal))
        XCTAssertFalse(h.isDone("2026-08-09"))
    }

    func testDecodeDropsStructurallyBrokenKeysButKeepsOddDates() throws {
        let json = """
        {"version":2,"updatedAt":0,"habits":[{
          "id":"11111111-1111-1111-1111-111111111111","name":"Import","emoji":"",
          "createdAt":"2026-08-01",
          "log":{"quatsch":1,"2026-13-45":1,"2026-02-30":2,"2026-08-09":1,
                 "2026-08-08":0,"2026-08-07":-5,"1900-01-01":1,"2099-01-01":1}
        }]}
        """.data(using: .utf8)!
        let data = try JSONDecoder().decode(HabitData.self, from: json)
        let h = try XCTUnwrap(data.habits.first)
        // Struktureller Müll und Werte <= 1 sind weg …
        XCTAssertNil(h.log["quatsch"])
        XCTAssertNil(h.log["2026-13-45"])
        XCTAssertNil(h.log["2026-02-30"])
        XCTAssertNil(h.log["2026-08-08"])
        XCTAssertNil(h.log["2026-08-07"])
        // … echte Daten bleiben, auch unplausible: Datenverlust beim Import
        // wäre schlimmer als eine Zahl, die die Rechen-Schicht ignoriert.
        XCTAssertEqual(h.log["2026-08-09"], 1)
        XCTAssertEqual(h.log["1900-01-01"], 1)
        XCTAssertEqual(h.log["2099-01-01"], 1)
        XCTAssertEqual(h.validDays(today: "2026-08-09").count, 1)
    }

    func testAncientCreatedAtDoesNotStallStreakLoop() {
        // Alle sieben Wochentage sind Ruhetage: die Serienschleife hat kein
        // natürliches Abbruchkriterium außer der unteren Grenze. Mit einem
        // createdAt aus 1900 wären das ~46.000 Kalenderschritte.
        var h = habit([:], recurrence: .from(legacy: LegacyGoal(restDays: [1, 2, 3, 4, 5, 6, 7])), createdAt: "1900-01-01")
        h.log["1900-01-02"] = 1
        let start = Date()
        _ = GoalEngine.streak(habit: h, today: "2026-08-09", calendar: cal)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5,
                          "Uralt-Daten dürfen die Serienberechnung nicht ausbremsen")
    }
}

// MARK: – Tempo

final class GridPerformanceTests: GridTestCase {

    func testSnapshotIsComputedOncePerHabitAndDay() {
        GridCalendar.resetCache()
        let h = habit(run(days: 365, endingAt: "2026-08-09"))
        // 100 "body"-Auswertungen (Scrollen) = EINE Berechnung.
        for _ in 0..<100 {
            _ = GridCalendar.snapshot(habit: h, weeks: 53, today: "2026-08-09", calendar: cal)
        }
        XCTAssertEqual(GridCalendar.computeCount, 1)

        // Neuer Tag -> neue Berechnung.
        _ = GridCalendar.snapshot(habit: h, weeks: 53, today: "2026-08-10", calendar: cal)
        XCTAssertEqual(GridCalendar.computeCount, 2)

        // Geänderter Log -> neue Berechnung (kein veraltetes Raster).
        var changed = h
        changed.log["2026-08-09"] = 4
        _ = GridCalendar.snapshot(habit: changed, weeks: 53, today: "2026-08-09", calendar: cal)
        XCTAssertEqual(GridCalendar.computeCount, 3)
        GridCalendar.resetCache()
    }

    func testFiveHabitsWithAYearOfDataStayCheap() {
        let habits = (0..<5).map { _ in habit(run(days: 365, endingAt: "2026-08-09")) }
        GridCalendar.resetCache()

        // Kalt: fünf volle Raster.
        let cold = Date()
        for h in habits { _ = GridCalendar.snapshot(habit: h, weeks: 53, today: "2026-08-09", calendar: cal) }
        let coldTime = Date().timeIntervalSince(cold)
        XCTAssertLessThan(coldTime, 1.0, "fünf Raster kalt: \(coldTime) s")

        // Warm: 60 Frames × 5 Habits, wie beim Scrollen.
        let warm = Date()
        for _ in 0..<60 {
            for h in habits { _ = GridCalendar.snapshot(habit: h, weeks: 53, today: "2026-08-09", calendar: cal) }
        }
        let warmTime = Date().timeIntervalSince(warm)
        XCTAssertLessThan(warmTime, 0.2, "300 Raster-Zugriffe warm: \(warmTime) s")
        XCTAssertEqual(GridCalendar.computeCount, 5)
        GridCalendar.resetCache()
    }

    func testScrollFrameBudget() {
        let habits = (0..<5).map { _ in habit(run(days: 365, endingAt: "2026-08-09")) }
        for h in habits { _ = GridCalendar.snapshot(habit: h, weeks: 53, today: "2026-08-09", calendar: cal) }
        measure {
            for _ in 0..<60 {
                for h in habits {
                    _ = GridCalendar.snapshot(habit: h, weeks: 53, today: "2026-08-09", calendar: cal)
                }
            }
        }
    }
}

final class GraphCacheRegressionTests: XCTestCase {
    func testOverflowEvictsOnlyOldestAndReplacementDoesNotEvict() {
        var cache = BoundedGraphCache<Int, String>(limit: 2)
        cache[1] = "first"
        cache[2] = "second"
        cache[2] = "updated"
        XCTAssertEqual(cache[1], "first")
        cache[3] = "third"
        XCTAssertNil(cache[1])
        XCTAssertEqual(cache[2], "updated")
        XCTAssertEqual(cache[3], "third")
        cache.removeAll()
        XCTAssertNil(cache[2])
        XCTAssertNil(cache[3])
    }

    func testHabitSnapshotKeyIncludesRecurrenceAndCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let habit = Habit(name: "Daily")
        let original = GridCalendar.HabitSnapshotKey(habit: habit, weeks: 12,
                                                     today: "2026-09-12", calendar: calendar)
        var edited = habit
        edited.recurrence = .weekdays([2])
        let newRule = GridCalendar.HabitSnapshotKey(habit: edited, weeks: 12,
                                                    today: "2026-09-12", calendar: calendar)
        XCTAssertNotEqual(original, newRule)
        XCTAssertTrue(original.canDisplaySnapshot(for: newRule))
        calendar.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        let newZone = GridCalendar.HabitSnapshotKey(habit: habit, weeks: 12,
                                                    today: "2026-09-12", calendar: calendar)
        XCTAssertNotEqual(original, newZone)
        XCTAssertFalse(original.canDisplaySnapshot(for: newZone))
        let otherHabit = GridCalendar.HabitSnapshotKey(habit: Habit(name: "Other"), weeks: 12,
                                                       today: "2026-09-12", calendar: calendar)
        XCTAssertFalse(original.canDisplaySnapshot(for: otherHabit))
    }

    func testGitHubSnapshotNeverShowsAnotherSourceWhileRefreshing() {
        let original = GitHubContributionGraph.SnapshotRequest(
            days: [.init(date: "2026-09-12", count: 2, level: 1)], weeks: 12, today: "2026-09-12")
        let other = GitHubContributionGraph.SnapshotRequest(
            days: [.init(date: "2026-09-12", count: 8, level: 4)], weeks: 12, today: "2026-09-12")
        XCTAssertTrue(original.canDisplaySnapshot(for: original))
        XCTAssertFalse(original.canDisplaySnapshot(for: other))
    }
}

final class GitHubGraphPerformanceTests: XCTestCase {
    private func days() -> [GitHubContributionDay] {
        [
            GitHubContributionDay(date: "2026-08-01", count: 1, level: 1),
            GitHubContributionDay(date: "2026-08-02", count: 3, level: 2),
            GitHubContributionDay(date: "2026-08-03", count: 0, level: 0),
            GitHubContributionDay(date: "2026-08-04", count: 7, level: 4)
        ]
    }

    func testGitHubLayoutReusesStableGeometryUntilContributionDataChanges() {
        GitHubContributionGraph.resetLayoutCache()
        let original = days()

        let first = GitHubContributionGraph.layout(days: original, weekLimit: 12)
        let second = GitHubContributionGraph.layout(days: original, weekLimit: 12)

        XCTAssertEqual(first.columns.count, second.columns.count)
        XCTAssertEqual(first.marks, second.marks)
        XCTAssertEqual(GitHubContributionGraph.layoutComputeCount, 1)

        var changed = original
        changed[1] = GitHubContributionDay(date: changed[1].date, count: 8, level: 4)
        _ = GitHubContributionGraph.layout(days: changed, weekLimit: 12)
        XCTAssertEqual(GitHubContributionGraph.layoutComputeCount, 2)
        GitHubContributionGraph.resetLayoutCache()
    }

    func testGitHubDataMapsIntoTheSharedSevenRowSnapshot() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let snapshot = GridCalendar.snapshot(
            levelsByDay: ["2026-08-02": 1, "2026-08-05": 4],
            weeks: 2,
            today: "2026-08-08",
            calendar: calendar)

        XCTAssertEqual(snapshot.keys.count, 2)
        XCTAssertTrue(snapshot.keys.allSatisfy { $0.count == GridCalendar.rows })
        XCTAssertTrue(snapshot.levels.allSatisfy { $0.count == GridCalendar.rows })
        XCTAssertEqual(snapshot.filledCount, 2)
        XCTAssertEqual(snapshot.levels.flatMap { $0 }.max(), 4)
    }
}
