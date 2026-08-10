import XCTest
@testable import Haiity

/// „Nacharbeiten": die Rechnung hinter der Karte. Hier stehen die Fälle, in
/// denen ein Fehler nicht „sieht komisch aus" heißt, sondern „falscher Tag
/// geschrieben" oder „Tag gar nicht erst wählbar".
final class BackfillBoundsTests: GridTestCase {
    private let today = "2026-08-09"

    // MARK: – Obergrenze

    func testUpperBoundIsTodayNeverTheFuture() {
        let h = habit(createdAt: "2026-01-01")
        let b = Backfill.bounds(habit: h, today: today, calendar: cal)
        XCTAssertEqual(b.latest, today)
        XCTAssertFalse(b.contains("2026-08-10"))
        XCTAssertTrue(b.contains(today))
    }

    // MARK: – Untergrenze

    /// DER Regressionsfall. `createdAt` steht bei der Anlage auf HEUTE — wer
    /// die Untergrenze allein daraus zieht, gibt einem heute angelegten Habit
    /// eine leere Auswahl. Genau dafür gibt es die Funktion aber: Habit
    /// anlegen, dann die letzte Woche nachtragen.
    func testHabitCreatedTodayCanStillBackfillTheWholeGridWindow() {
        var h = habit(createdAt: today)
        h.log = [:]
        let b = Backfill.bounds(habit: h, today: today, calendar: cal)
        let expected = DayKey.shifted(today, by: -Backfill.windowDays, calendar: cal)
        XCTAssertEqual(b.earliest, expected)
        XCTAssertNotEqual(b.earliest, today)
        // Gestern und die Woche davor müssen wählbar sein.
        XCTAssertTrue(b.contains("2026-08-08"))
        XCTAssertTrue(b.contains("2026-08-02"))
        // Und jede Zelle, die das Raster überhaupt zeichnet.
        let keys = GridCalendar.keys(weeks: 53, today: today, calendar: cal)
        for key in keys.flatMap({ $0 }).compactMap({ $0 }) {
            XCTAssertTrue(b.contains(key), "Rasterzelle \(key) ist nicht wählbar")
        }
    }

    /// Das Fenster ist die UNTERSTE Grenze, nicht die einzige: ein Habit, das
    /// es länger gibt als das sichtbare Raster, darf weiter zurück.
    func testOlderCreationDateWidensTheRange() {
        let h = habit(createdAt: "2023-05-04")
        let b = Backfill.bounds(habit: h, today: today, calendar: cal)
        XCTAssertEqual(b.earliest, "2023-05-04")
    }

    /// Importierte Historie kann ÄLTER sein als das Habit selbst (Umzug von
    /// einer anderen App). Dann zählt der älteste Log-Tag.
    func testLogOlderThanCreationWidensTheRange() {
        var h = habit(createdAt: "2026-08-01")
        h.log = ["2022-03-15": 1, "2026-08-01": 1]
        let b = Backfill.bounds(habit: h, today: today, calendar: cal)
        XCTAssertEqual(b.earliest, "2022-03-15")
    }

    /// Unsinniges `createdAt` (kaputter Import) zieht die Grenze nicht auf —
    /// es fällt einfach als Kandidat weg.
    func testImplausibleCreationDateIsIgnored() {
        let h = habit(createdAt: "quatsch")
        let b = Backfill.bounds(habit: h, today: today, calendar: cal)
        XCTAssertEqual(b.earliest, DayKey.shifted(today, by: -Backfill.windowDays, calendar: cal))
    }

    /// Ein `createdAt` aus der ZUKUNFT (Gerät mit falscher Uhr) ist ebenso
    /// wenig ein Kandidat — sonst läge die Untergrenze hinter der Obergrenze.
    func testFutureCreationDateIsIgnored() {
        let h = habit(createdAt: "2027-01-01")
        let b = Backfill.bounds(habit: h, today: today, calendar: cal)
        XCTAssertTrue(b.earliest < b.latest)
        XCTAssertEqual(b.earliest, DayKey.shifted(today, by: -Backfill.windowDays, calendar: cal))
    }

    /// Uralt-Datum (kaputter Import): fällt als Kandidat weg wie jedes andere
    /// unplausible auch — die Karte bietet dann das Rasterfenster an, nicht
    /// dreißig Jahre.
    func testAncientCreationDateFallsBackToTheGridWindow() {
        let h = habit(createdAt: "1900-01-01")
        let b = Backfill.bounds(habit: h, today: today, calendar: cal)
        XCTAssertEqual(b.earliest, DayKey.shifted(today, by: -Backfill.windowDays, calendar: cal))
    }

    /// Die Zusage der Funktion, über alle Eingaben: was sie als Untergrenze
    /// nennt, ist auch WIRKLICH schreibbar. Ein Tag unter
    /// `DayKey.plausibleFloor` wäre für Serien und Statistik unsichtbar
    /// (`validDays` wirft ihn weg) und stünde trotzdem für immer in der Datei
    /// und in iCloud.
    func testLowerBoundIsAlwaysWritable() {
        for created in [today, "2026-08-08", "2023-05-04", "1900-01-01",
                        "quatsch", "2027-01-01", "0001-01-01"] {
            var h = habit(createdAt: created)
            h.log = ["1900-05-05": 1, "2026-08-01": 1]
            let b = Backfill.bounds(habit: h, today: today, calendar: cal)
            XCTAssertTrue(DayKey.isPlausible(b.earliest, today: today, calendar: cal), created)
            XCTAssertTrue(Backfill.canWrite(habit: h, day: b.earliest,
                                            today: today, calendar: cal), created)
            XCTAssertTrue(Backfill.canWrite(habit: h, day: b.latest,
                                            today: today, calendar: cal), created)
        }
    }

    /// Die Spanne für den Picker ist nie leer und nie verdreht.
    func testDateRangeIsOrderedAndContainsToday() {
        for created in [today, "2023-05-04", "1900-01-01", "quatsch", "2027-01-01"] {
            let h = habit(createdAt: created)
            let range = Backfill.dateRange(habit: h, today: today, calendar: cal)
            XCTAssertLessThanOrEqual(range.lowerBound, range.upperBound, created)
            XCTAssertTrue(range.contains(DayKey.date(from: today, calendar: cal)!), created)
        }
    }
}

// MARK: – Die reservierte Höhe des Kalenderblatts

/// Die Karte darf nach dem Erscheinen NICHT mehr ihre Größe ändern.
///
/// Der grafische `DatePicker` meldet seine Höhe in zwei Schritten (beim ersten
/// Layout fehlt eine Wochenzeile, die richtige Höhe kommt Millisekunden später
/// nach) — die Karte wuchs mit und sprang sichtbar. `Backfill.calendarHeight`
/// ist die Reserve, die das verhindert; hier stehen die auf dem Gerät
/// GEMESSENEN Endhöhen, gegen die sie halten muss.
final class BackfillCalendarHeightTests: XCTestCase {
    /// Nachgemessen (Innenmaß der Karte 328 pt): Endhöhe des Kalenderblatts
    /// je Schriftfaktor — Gerät UND Simulator, denn genau ZWISCHEN den drei
    /// ursprünglichen Gerätepunkten lag der Fehler: `UIFontMetrics` skaliert
    /// den Kopf des Blatts in STUFEN, die alte Gerade `67 + 27·Faktor` lag
    /// bei xLarge/xxLarge darunter, und die Karte wuchs nach dem Öffnen
    /// sichtbar nach („sometimes when the popup … gets opened, the calendar
    /// resizes"). Jede Zeile hier ist ein realer Messpunkt, den die Reserve
    /// abdecken MUSS.
    /// Die Faktoren sind die GEMESSENEN (`@ScaledMetric` 100 / 100), nicht
    /// die Verhältnisse der Body-Grade aus der Schrifttabelle —
    /// `UIFontMetrics` skaliert große Werte flacher (xxLarge: Tabelle 1,235,
    /// gemessen 1,1833), und die Reserve bekommt zur Laufzeit den
    /// gemessenen Wert.
    private let measured: [(scale: CGFloat, height: CGFloat)] = [
        (0.824, 370.0),    // xSmall (Gerät)
        (0.8633, 372.0),   // xSmall (Simulator)
        (0.9100, 373.0),   // small (Simulator)
        (0.9533, 374.0),   // medium (Simulator)
        (1.0, 374.7),      // large, Standard (Gerät)
        (1.0, 376.0),      // large, Standard (Simulator)
        (1.0900, 379.7),   // xLarge (Simulator) — alte Reserve 378: zu knapp
        (1.1833, 384.3),   // xxLarge (Simulator) — alte Reserve 381: zu knapp
        (1.3167, 384.3),   // xxxLarge (Simulator)
        (1.353, 384.3),    // xxxLarge (Gerät — dieselbe Stufe)
    ]

    func testReserveCoversTheMeasuredHeights() {
        for case let (scale, height) in measured {
            let reserved = Backfill.calendarHeight(width: 328, typeScale: scale)
            XCTAssertGreaterThanOrEqual(reserved, height,
                                        "Reserve zu knapp bei Faktor \(scale)")
        }
    }

    /// Zu VIEL Reserve ist auch ein Fehler: dann steht unter dem Kalender ein
    /// leerer Streifen. Höchstens ein paar Punkte darüber. (Wo Gerät und
    /// Simulator verschieden messen, zählt für die Verschwendung der größere
    /// Messwert der Stufe — deshalb je Faktor gegen das Maximum geprüft.)
    func testReserveIsNotWasteful() {
        let maxPerScale = Dictionary(grouping: measured, by: \.scale)
            .mapValues { $0.map(\.height).max()! }
        for (scale, height) in maxPerScale {
            let reserved = Backfill.calendarHeight(width: 328, typeScale: scale)
            XCTAssertLessThanOrEqual(reserved - height, 4,
                                     "Reserve zu großzügig bei Faktor \(scale)")
        }
    }

    /// Die Stufen zwischen den Messpunkten dürfen nie wieder unter die
    /// Hüllkurve rutschen: zwischen zwei benachbarten Messpunkten darf die
    /// Reserve nirgends KLEINER sein als am linken UND als der rechte
    /// Messwert verlangt — sonst gäbe es wieder eine Schriftgröße, bei der
    /// die Karte nach dem Öffnen wächst. Monotonie deckt genau das ab.
    func testReserveIsMonotoneInTypeScale() {
        var previous = Backfill.calendarHeight(width: 328, typeScale: 0.5)
        for step in stride(from: 0.52, through: 2.0, by: 0.02) {
            let next = Backfill.calendarHeight(width: 328, typeScale: step)
            XCTAssertGreaterThanOrEqual(next, previous, "Reserve fällt bei Faktor \(step)")
            previous = next
        }
    }

    /// Ein Monat mit SECHS Wochenzeilen (z. B. August 2026, Montag zuerst)
    /// muss in dieselbe Reserve passen wie einer mit fünf: der Kalender hält
    /// die Blatthöhe über die Monate konstant (nachgemessen beim Blättern
    /// April bis August 2026, keine Höhenänderung) — die Reserve ist von
    /// vornherein auf sechs Zeilen gerechnet. Wer die 6 in der Formel je
    /// durch eine „echte Zeilenzahl des Monats" ersetzt, bricht hier.
    func testReserveAssumesSixWeekRows() {
        let width: CGFloat = 328
        let sixRows = 6 * width / 7
        XCTAssertGreaterThanOrEqual(Backfill.calendarHeight(width: width),
                                    sixRows,
                                    "Reserve deckt keine sechs Wochenzeilen mehr")
    }

    /// Eine schmalere Karte heißt schmalere Spalten und damit ein flacheres
    /// Blatt — sechs Zeilen, jede so hoch wie eine Spalte breit ist.
    func testNarrowerCardReservesLess() {
        let wide = Backfill.calendarHeight(width: 328)
        let narrow = Backfill.calendarHeight(width: 311)   // iPhone SE
        XCTAssertLessThan(narrow, wide)
        XCTAssertEqual(wide - narrow, (6 * (328 - 311) / 7), accuracy: 1.5)
    }

    func testLargerTypeReservesMore() {
        XCTAssertGreaterThan(Backfill.calendarHeight(width: 328, typeScale: 1.353),
                             Backfill.calendarHeight(width: 328, typeScale: 0.824))
    }

    /// Entartete Eingaben dürfen die Karte nicht zerlegen.
    func testDegenerateInputsStayFinite() {
        XCTAssertGreaterThan(Backfill.calendarHeight(width: 0, typeScale: 0), 0)
        XCTAssertGreaterThan(Backfill.calendarHeight(width: -50, typeScale: -3), 0)
        // Ausreißer nach oben werden geklemmt, sonst reserviert eine kaputte
        // Umgebung eine bildschirmhohe leere Fläche.
        XCTAssertEqual(Backfill.calendarHeight(width: 328, typeScale: 99),
                       Backfill.calendarHeight(width: 328, typeScale: 2))
    }

    /// Das Innenmaß der Karte, aus dem die Reserve fällt: gedeckelt auf 360,
    /// sonst Fenster minus beiden Seitenrändern — und noch einmal minus dem
    /// Innenrand der Karte.
    func testContentWidthIsCappedAndInset() {
        XCTAssertEqual(BackfillCard.contentWidth(window: 440), 328)   // Pro Max
        XCTAssertEqual(BackfillCard.contentWidth(window: 393), 328)   // gedeckelt
        XCTAssertEqual(BackfillCard.contentWidth(window: 375), 311)   // SE
        XCTAssertGreaterThanOrEqual(BackfillCard.contentWidth(window: 0), 0)
    }
}

// MARK: – Der Torwächter

/// `HabitStore.setValue` prüft seinen Tagesschlüssel NICHT — es ist der
/// exakte Setter für „Rückgängig". Die Karte ist sein erster Aufrufer mit
/// einem vom Nutzer gewählten Tag, und deshalb steht hier ein zweites Schloss
/// neben den Picker-Grenzen.
final class BackfillGateTests: GridTestCase {
    private let today = "2026-08-09"

    func testPlausibleDayInsideTheRangeIsWritable() {
        let h = habit(createdAt: "2026-01-01")
        XCTAssertTrue(Backfill.canWrite(habit: h, day: "2026-07-01", today: today, calendar: cal))
        XCTAssertTrue(Backfill.canWrite(habit: h, day: today, today: today, calendar: cal))
    }

    func testFutureIsRejected() {
        let h = habit(createdAt: "2026-01-01")
        XCTAssertFalse(Backfill.canWrite(habit: h, day: "2026-08-10", today: today, calendar: cal))
        XCTAssertFalse(Backfill.canWrite(habit: h, day: "2099-01-01", today: today, calendar: cal))
    }

    /// Der Fall, den die Grenzen ALLEIN durchlassen würden: "2026-02-30"
    /// liegt zwischen Unter- und Obergrenze (Schlüssel werden als Text
    /// verglichen), ist aber kein Tag. Ohne `DayKey.isPlausible` stünde er
    /// danach in der Datei und in iCloud — unsichtbar für Serien und
    /// Statistik, weil `validDays` ihn wegwirft.
    func testKeyInsideTheRangeButNotARealDayIsRejected() {
        let h = habit(createdAt: "2026-01-01")
        let b = Backfill.bounds(habit: h, today: today, calendar: cal)
        XCTAssertTrue(b.contains("2026-02-30"), "Vorbedingung: die Grenzen allein greifen hier nicht")
        XCTAssertFalse(Backfill.canWrite(habit: h, day: "2026-02-30", today: today, calendar: cal))
    }

    func testGarbageKeysAreRejected() {
        let h = habit(createdAt: "2026-01-01")
        for bad in ["quatsch", "", "2026-13-45", "26-08-09", "2026-8-9", "2026-08-09T12:00"] {
            XCTAssertFalse(Backfill.canWrite(habit: h, day: bad, today: today, calendar: cal), bad)
        }
    }

    /// Vor der Untergrenze: formal ein Tag, aber ausserhalb dessen, was die
    /// Karte anbietet.
    func testDayBeforeTheLowerBoundIsRejected() {
        var h = habit(createdAt: today)
        h.log = [:]
        let b = Backfill.bounds(habit: h, today: today, calendar: cal)
        let tooOld = DayKey.shifted(b.earliest, by: -1, calendar: cal)!
        XCTAssertFalse(Backfill.canWrite(habit: h, day: tooOld, today: today, calendar: cal))
    }
}

// MARK: – Zustand und Aktionen

/// Die Karte hat keinen Kippknopf, sondern eine LISTE aus Aktionen, die aus
/// einem benannten Zustand fällt. Der Grund steht an `Backfill.DayState`:
/// die Habit-Art „Ja/Nein" kennt drei Zustände, und die passen in keinen
/// zweiwertigen Umschalter.
final class BackfillStateTests: GridTestCase {
    private let day = "2026-08-05"

    func testCheckboxStates() {
        var h = habit(createdAt: "2026-01-01")
        XCTAssertEqual(Backfill.state(habit: h, day: day), .empty)
        h.log[day] = 1
        XCTAssertEqual(Backfill.state(habit: h, day: day), .done)
    }

    func testQuantityStateCarriesValueAndTarget() {
        var h = habit(recurrence: Recurrence(target: 3), createdAt: "2026-01-01")
        XCTAssertEqual(Backfill.state(habit: h, day: day), .quantity(value: 0, target: 3))
        h.log[day] = 2
        XCTAssertEqual(Backfill.state(habit: h, day: day), .quantity(value: 2, target: 3))
    }

    /// Ein leerer Tag bietet genau EINE Aktion an, und die schreibt 1.
    func testEmptyCheckboxDayOffersDoneWritingOne() {
        let actions = Backfill.actions(for: .empty)
        XCTAssertEqual(actions.map(\.kind), [.done])
        XCTAssertEqual(actions[0].value, 1)
    }

    func testDoneDayOffersOnlyClearWritingNil() {
        let actions = Backfill.actions(for: .done)
        XCTAssertEqual(actions.map(\.kind), [.clear])
        XCTAssertNil(actions[0].value)
    }

    /// Mengenziel: EXAKT das Ziel, nicht „einer mehr". Ein nachgetragener Tag
    /// wird nicht hochgezählt — man sieht den Stand von damals gar nicht vor
    /// sich, ein Delta wäre also eine Rechnung im Blindflug.
    func testQuantityActionWritesExactlyTheTargetNotAnIncrement() {
        let actions = Backfill.actions(for: .quantity(value: 0, target: 5))
        XCTAssertEqual(actions.map(\.kind), [.quantity])
        XCTAssertEqual(actions[0].value, 5)

        let partial = Backfill.actions(for: .quantity(value: 4, target: 5))
        XCTAssertEqual(partial.map(\.kind), [.quantity, .clear])
        XCTAssertEqual(partial[0].value, 5, "nicht 5 (=4+1) durch Zufall, sondern das Ziel")
        XCTAssertNil(partial[1].value)
    }

    func testQuantityAtOrAboveTargetOffersOnlyClear() {
        XCTAssertEqual(Backfill.actions(for: .quantity(value: 5, target: 5)).map(\.kind), [.clear])
        XCTAssertEqual(Backfill.actions(for: .quantity(value: 9, target: 5)).map(\.kind), [.clear])
    }

    /// Der Zustand, den noch keine Habit-Art erzeugt: die Liste kann ihn
    /// schon. Das ist der ganze Zweck der Form — wenn „Ja/Nein" kommt, ändert
    /// sich hier nichts ausser einem weiteren Fall in `state`.
    func testDeclinedStateAlreadyYieldsSaneActions() {
        let actions = Backfill.actions(for: .declined)
        XCTAssertEqual(actions.map(\.kind), [.done, .clear])
        XCTAssertEqual(actions[0].value, 1)
        XCTAssertNil(actions[1].value)
    }

    /// Jede Aktion hat genau EINE stabile Kennung — die Oberfläche hängt
    /// daran, und zwei Aktionen mit derselben wären im Baum nicht mehr
    /// auseinanderzuhalten.
    func testActionIdentifiersAreUniquePerList() {
        let lists: [[Backfill.Action]] = [
            Backfill.actions(for: .empty),
            Backfill.actions(for: .done),
            Backfill.actions(for: .declined),
            Backfill.actions(for: .quantity(value: 1, target: 3))
        ]
        for list in lists {
            XCTAssertEqual(Set(list.map(\.accessibilityIdentifier)).count, list.count)
            XCTAssertTrue(list.allSatisfy { $0.accessibilityIdentifier.hasPrefix("backfill-action-") })
            XCTAssertTrue(list.allSatisfy { !$0.title.isEmpty })
        }
    }

    func testCountsMatchesGoalEngine() {
        var h = habit(recurrence: Recurrence(target: 3), createdAt: "2026-01-01")
        h.log[day] = 2
        XCTAssertEqual(Backfill.state(habit: h, day: day).counts,
                       GoalEngine.dayCounts(habit: h, day: day, calendar: cal))
        h.log[day] = 3
        XCTAssertEqual(Backfill.state(habit: h, day: day).counts,
                       GoalEngine.dayCounts(habit: h, day: day, calendar: cal))
        XCTAssertTrue(Backfill.state(habit: h, day: day).counts)
    }

    // MARK: – Mehrere Tage auf einmal

    /// Die Auswahl-Leiste ist VOLLSTÄNDIG je Habit-Art — die alte
    /// „kein Nein für alle"-Regel ist bewusst weg. Einheitlich bleibt der
    /// Schreibvorgang trotzdem: jede Aktion trägt EINEN Wert für alle Tage.
    func testSelectActionsCoverEveryTargetState() {
        let checkbox = habit(createdAt: "2026-01-01")
        let a = Backfill.selectActions(habit: checkbox)
        XCTAssertEqual(a.map(\.kind), [.done, .clear])
        XCTAssertEqual(a[0].value, 1)
        XCTAssertNil(a[1].value)

        let quantity = habit(recurrence: Recurrence(target: 4), createdAt: "2026-01-01")
        let q = Backfill.selectActions(habit: quantity)
        XCTAssertEqual(q.map(\.kind), [.quantity, .clear])
        XCTAssertEqual(q[0].value, 4, "ohne Steller gilt genau das Tagesziel")
        XCTAssertNil(q[1].value)
    }

    /// Der Mengen-Steller der Karte fließt in die Aktion ein — Massen-Menge
    /// mit frei gewähltem Wert, geklemmt auf das echte Zählerband.
    func testSelectActionsTakeTheDialledAmount() {
        let quantity = habit(recurrence: Recurrence(target: 4), createdAt: "2026-01-01")
        XCTAssertEqual(Backfill.selectActions(habit: quantity, amount: 7)[0].value, 7)
        XCTAssertEqual(Backfill.selectActions(habit: quantity, amount: 0)[0].value, 1,
                       "eine Menge unter 1 wäre `Leeren` in Verkleidung")
        XCTAssertEqual(Backfill.selectActions(habit: quantity,
                                              amount: Habit.Answer.maxCount + 5)[0].value,
                       Habit.Answer.maxCount,
                       "nie ins reservierte Antwortband hineinschreiben")
    }

    /// Die Zusammenfassung sagt, was eine einheitliche Aktion noch ändert.
    func testSelectionSummaryCountsWhatIsAlreadyDone() {
        var h = habit(createdAt: "2026-01-01")
        h.log = ["2026-08-01": 1, "2026-08-03": 1]
        let days: Set<String> = ["2026-08-01", "2026-08-02", "2026-08-03",
                                 "2026-08-04", "2026-08-05"]
        let s = Backfill.selection(habit: h, days: days)
        XCTAssertEqual(s.count, 5)
        XCTAssertEqual(s.done, 2)
        let text = Backfill.selectionText(s)
        XCTAssertTrue(text.contains("5"))
        XCTAssertTrue(text.contains("2"))
    }

    /// Mengen-Habits zählen nur ERREICHTE Ziele als erledigt.
    func testSelectionSummaryUsesGoalSemantics() {
        var h = habit(recurrence: Recurrence(target: 3), createdAt: "2026-01-01")
        h.log = ["2026-08-01": 3, "2026-08-02": 1]
        let s = Backfill.selection(habit: h, days: ["2026-08-01", "2026-08-02"])
        XCTAssertEqual(s.done, 1)
    }

    func testSelectionTextHandlesNoneAndOne() {
        XCTAssertEqual(Backfill.selectionText(Backfill.Selection(count: 0, done: 0)),
                       String(localized: "Keine Tage ausgewählt"))
        XCTAssertEqual(Backfill.selectionText(Backfill.Selection(count: 1, done: 0)),
                       String(localized: "1 Tag ausgewählt"))
    }

    /// `MultiDatePicker` nimmt eine halboffene Spanne und rechnet darin in
    /// TAGEN: der Tag, in dem die Obergrenze liegt, ist noch wählbar. Die
    /// Obergrenze ist deshalb der Beginn von HEUTE — mit dem Folgetag stand
    /// morgen wählbar im Kalender (am Bildschirm nachgemessen).
    func testExclusiveRangeEndsOnTodayNotTomorrow() {
        let h = habit(createdAt: "2026-01-01")
        let r = Backfill.dateRangeExclusive(habit: h, today: "2026-08-09", calendar: cal)
        XCTAssertEqual(r.upperBound, DayKey.date(from: "2026-08-09", calendar: cal)!)
        XCTAssertEqual(r.lowerBound,
                       DayKey.date(from: Backfill.bounds(habit: h, today: "2026-08-09",
                                                         calendar: cal).earliest,
                                   calendar: cal)!)
        XCTAssertFalse(r.isEmpty)
        // Alles ab morgen liegt ausserhalb — auch als Augenblick gerechnet.
        XCTAssertFalse(r.contains(DayKey.date(from: "2026-08-10", calendar: cal)!))
    }

    /// Auch wenn Ober- und Untergrenze auf denselben Tag fielen, darf die
    /// Spanne nicht leer sein — eine leere Spanne wäre ein Kalender ohne
    /// einen einzigen wählbaren Tag.
    func testExclusiveRangeIsNeverEmpty() {
        let now = "2026-08-09"
        for created in [now, "2023-05-04", "quatsch"] {
            let h = habit(createdAt: created)
            let r = Backfill.dateRangeExclusive(habit: h, today: now, calendar: cal)
            XCTAssertFalse(r.isEmpty, created)
            XCTAssertLessThan(r.lowerBound, r.upperBound, created)
        }
    }

    func testStatusLineNamesTheDayAndTheState() {
        var h = habit(createdAt: "2026-01-01")
        let empty = Backfill.statusLine(habit: h, day: day, calendar: cal)
        XCTAssertTrue(empty.contains(Backfill.dayText(day, calendar: cal)))
        XCTAssertTrue(empty.contains(String(localized: "Kein Eintrag")))
        h.log[day] = 1
        XCTAssertTrue(Backfill.statusLine(habit: h, day: day, calendar: cal)
            .contains(String(localized: "Erledigt")))
    }
}

// MARK: – Schreiben und Zurücknehmen

/// Der ganze Weg, wie ihn die Karte geht: Vorwert merken, über den EXAKTEN
/// Setter schreiben, Toast anmelden — und mit dem Toast wieder exakt dorthin
/// zurück, wo es vorher stand.
final class BackfillWriteTests: XCTestCase {
    private var url: URL!
    private var store: HabitStore!

    override func setUp() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-backfill-\(UUID().uuidString).json")
        store = HabitStore(url: url)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Spiegelt `ContentView.mutate`: vorher lesen, schreiben, Toast.
    @discardableResult
    private func write(_ habit: Habit, day: String, value: Int?,
                       into state: inout UndoToastState) -> Int? {
        let before = store.value(habit.id, day: day)
        store.setValue(habit.id, day: day, value: value)
        let after = store.value(habit.id, day: day) ?? 0
        state.present(habitId: habit.id, day: day, previousValue: before,
                      message: CheckInUndo.message(habit: habit, value: after, day: day))
        return before
    }

    /// Spiegelt `ContentView.performUndo`: der GANZE Vorgang zurück, jeder
    /// Tag auf seinen eigenen Vorwert.
    private func undo(_ state: inout UndoToastState) {
        guard let toast = state.take() else { return XCTFail("kein Toast") }
        for entry in toast.entries {
            store.setValue(toast.habitId, day: entry.day, value: entry.previousValue)
        }
    }

    func testBackfillOfAnEmptyDayIsUndoneToNothing() {
        let h = Habit(name: "Lesen")
        store.add(h)
        var state = UndoToastState()
        write(h, day: "2026-08-05", value: 1, into: &state)
        XCTAssertEqual(store.habits[0].log["2026-08-05"], 1)
        undo(&state)
        XCTAssertNil(store.habits[0].log["2026-08-05"])
    }

    /// Der Fall, für den es `setValue` überhaupt gibt: ein Mengen-Tag, der
    /// vorher auf 3 stand, muss nach dem Zurücknehmen wieder auf 3 stehen —
    /// nicht auf 0 und nicht auf „irgendwas ≥ 1".
    func testBackfillOverAnExistingQuantityRestoresTheExactPriorValue() {
        let h = Habit(name: "Wasser", recurrence: Recurrence(target: 6))
        store.add(h)
        store.setValue(h.id, day: "2026-08-05", value: 3)
        var state = UndoToastState()
        let before = write(h, day: "2026-08-05", value: 6, into: &state)
        XCTAssertEqual(before, 3)
        XCTAssertEqual(store.habits[0].log["2026-08-05"], 6)
        undo(&state)
        XCTAssertEqual(store.habits[0].log["2026-08-05"], 3)
    }

    func testClearingABackfilledDayIsUndoable() {
        let h = Habit(name: "Lesen")
        store.add(h)
        store.setValue(h.id, day: "2026-08-05", value: 1)
        var state = UndoToastState()
        write(h, day: "2026-08-05", value: nil, into: &state)
        XCTAssertNil(store.habits[0].log["2026-08-05"])
        undo(&state)
        XCTAssertEqual(store.habits[0].log["2026-08-05"], 1)
    }

    /// Ein Nachtrag darf den HEUTIGEN Stand nicht anfassen — der Toast zeigt
    /// auf den nachgetragenen Tag, und nur der bewegt sich.
    /// Der Fall, für den die Mehrfachauswahl da ist — und der Fall, in dem
    /// ein schludriges Zurück am meisten kostet: EIN Griff schreibt sieben
    /// Tage, EIN Zurück holt alle sieben zurück, jeden auf SEINEN Vorwert.
    func testBatchBackfillIsUndoneInOneStepAndPerDayExactly() {
        let h = Habit(name: "Lesen")
        store.add(h)
        // Ausgangslage: gemischt — zwei Tage stehen schon, fünf sind leer.
        store.setValue(h.id, day: "2026-08-02", value: 1)
        store.setValue(h.id, day: "2026-08-04", value: 1)
        let days = (2...8).map { String(format: "2026-08-%02d", $0) }

        var state = UndoToastState()
        let entries = days.map {
            CheckInUndo.Entry(day: $0, previousValue: store.value(h.id, day: $0))
        }
        for day in days { store.setValue(h.id, day: day, value: 1) }
        state.present(habitId: h.id, entries: entries,
                      message: CheckInUndo.message(habit: h, days: days.count, cleared: false))

        XCTAssertEqual(days.filter { store.habits[0].log[$0] == 1 }.count, 7)
        // EIN Toast, nicht sieben.
        XCTAssertEqual(state.current?.entries.count, 7)

        undo(&state)
        XCTAssertEqual(store.habits[0].log["2026-08-02"], 1, "stand vorher schon")
        XCTAssertEqual(store.habits[0].log["2026-08-04"], 1, "stand vorher schon")
        for day in ["2026-08-03", "2026-08-05", "2026-08-06", "2026-08-07", "2026-08-08"] {
            XCTAssertNil(store.habits[0].log[day], "war vorher leer: \(day)")
        }
        XCTAssertNil(state.current)
    }

    /// Dasselbe für Mengen-Habits: jeder Tag hatte einen anderen Stand, und
    /// jeder muss GENAU dorthin zurück.
    func testBatchUndoRestoresDifferentPriorQuantities() {
        let h = Habit(name: "Wasser", recurrence: Recurrence(target: 6))
        store.add(h)
        store.setValue(h.id, day: "2026-08-02", value: 2)
        store.setValue(h.id, day: "2026-08-03", value: 5)
        let days = ["2026-08-02", "2026-08-03", "2026-08-04"]

        var state = UndoToastState()
        let entries = days.map {
            CheckInUndo.Entry(day: $0, previousValue: store.value(h.id, day: $0))
        }
        for day in days { store.setValue(h.id, day: day, value: 6) }
        state.present(habitId: h.id, entries: entries, message: "x")
        XCTAssertTrue(days.allSatisfy { store.habits[0].log[$0] == 6 })

        undo(&state)
        XCTAssertEqual(store.habits[0].log["2026-08-02"], 2)
        XCTAssertEqual(store.habits[0].log["2026-08-03"], 5)
        XCTAssertNil(store.habits[0].log["2026-08-04"])
    }

    func testBatchMessageCountsTheDays() {
        let h = Habit(name: "Lesen")
        let added = CheckInUndo.message(habit: h, days: 7, cleared: false)
        let cleared = CheckInUndo.message(habit: h, days: 7, cleared: true)
        XCTAssertTrue(added.contains("7"))
        XCTAssertTrue(cleared.contains("7"))
        XCTAssertNotEqual(added, cleared)
    }

    func testBackfillLeavesOtherDaysAlone() {
        let today = DayKey.today()
        let h = Habit(name: "Lesen")
        store.add(h)
        store.toggle(h.id, day: today)
        var state = UndoToastState()
        write(h, day: "2026-08-05", value: 1, into: &state)
        XCTAssertEqual(store.habits[0].log[today], 1)
        undo(&state)
        XCTAssertEqual(store.habits[0].log[today], 1)
        XCTAssertNil(store.habits[0].log["2026-08-05"])
    }
}
