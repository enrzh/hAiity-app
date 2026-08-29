import XCTest
@testable import Haiity

/// Die Such-Präsentation als Zustandsmaschine (`SearchFlow`) — die Regeln,
/// die auf dem Gerät zwei Fehler beendet haben:
///  * „X schließt nicht in einem Tipp": das System präsentierte mitten in
///    der Abklapp-Animation erneut (Binding → `true`), zeitlich NACH unserem
///    Schließen. Im Schließ-Fenster wird jedes System-`true` verworfen.
///  * „Anlegen-Schließen öffnet die Suche": der Such-Rollen-Tab (der
///    Anlegen-Kreis) spielte seine Such-Aktivierung verspätet rund um das
///    Cover aus. Bei offenem Cover und im Fenster nach dem Zufahren wird
///    jedes System-`true` verworfen — eine echte Lupen-Berührung ist dort
///    physisch unmöglich, die Lupe liegt unter dem Cover.
///
/// Zeit wird IMMER explizit übergeben (dieselbe Lehre wie ChromeScroll).
final class SearchFlowTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func t(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testSearchDismissalDoesNotAnimateTabSelectionWithGlassCollapse() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Views/ContentView.swift"))
        XCTAssertFalse(source.contains("withAnimation { nativeTab = lastNonSearchTab }"))
        XCTAssertTrue(source.contains("returnFromSearchAfterCollapse()"))
        XCTAssertTrue(source.contains("transaction.disablesAnimations = true"))
    }

    func testSearchCloseClearsPresentationStateWithoutTransientOverlay() throws {
        var flow = SearchFlow()
        flow.userOpened()
        flow.dismissed(now: t0)
        XCTAssertEqual(flow.state, .closing(since: t0))
        XCTAssertEqual(SearchFlow.closeCleanup,
                       SearchFlow.Cleanup(clearFocus: true, clearQuery: true,
                                          leaveSearchTab: true))
    }

    // Der frühere Verhaltens-Umschalter (`.automatic` nur für Deep-Links)
    // ist mit dem echten Such-Tab gegenstandslos: es gibt nur noch EIN
    // `.searchable`, und es wohnt am Such-Tab selbst.

    // MARK: – Grundfälle

    func testStartsClosed() {
        XCTAssertEqual(SearchFlow().state, .closed)
    }

    func testSystemLupePresentsFromClosed() {
        var flow = SearchFlow()
        XCTAssertTrue(flow.systemPresented(now: t0))
        XCTAssertEqual(flow.state, .open)
    }

    func testUserOpenAlwaysWins() {
        var flow = SearchFlow()
        flow.userOpened()
        XCTAssertEqual(flow.state, .open)
        // Das anschließende Binding-`true` läuft als systemPresented durch —
        // im `open`-Zustand wird es durchgewinkt, nicht verworfen.
        XCTAssertTrue(flow.systemPresented(now: t0))
    }

    func testDismissStartsClosingWindow() {
        var flow = SearchFlow()
        flow.userOpened()
        flow.dismissed(now: t0)
        XCTAssertEqual(flow.state, .closing(since: t0))
    }

    // MARK: – Ein Tipp schließt (Re-Present-Klemme)

    func testRepresentDuringCloseWindowIsRejected() {
        var flow = SearchFlow()
        flow.userOpened()
        flow.dismissed(now: t0)
        // Das System schreibt im nächsten Umlauf wieder `true` — genau der
        // Geräte-Fehler. Muss verworfen werden, egal wie schnell es kommt.
        XCTAssertFalse(flow.systemPresented(now: t(0.01)))
        XCTAssertFalse(flow.systemPresented(now: t(0.3)))
        XCTAssertNotEqual(flow.state, .open)
    }

    func testRejectedRepresentDoesNotRestartCloseWindow() {
        var flow = SearchFlow()
        flow.userOpened()
        flow.dismissed(now: t0)
        _ = flow.systemPresented(now: t(0.2))
        // Unser Zurückschreiben auf `false` feuert `dismissed` erneut — das
        // darf das Fenster NICHT verlängern (sonst zählte jeder verworfene
        // Versuch von vorn und ein echter Tipp kurz danach ginge verloren).
        flow.dismissed(now: t(0.21))
        XCTAssertEqual(flow.state, .closing(since: t0))
    }

    func testRealReopenAfterCloseWindowIsAccepted() {
        var flow = SearchFlow()
        flow.userOpened()
        flow.dismissed(now: t0)
        XCTAssertTrue(flow.systemPresented(now: t(SearchFlow.closeSettle + 0.01)))
        XCTAssertEqual(flow.state, .open)
    }

    func testProgrammaticReopenDuringCloseWindowIsAccepted() {
        // Schnelles Wiederöffnen per Zug/Deep-Link ist AUSDRÜCKLICHE Absicht
        // und darf nicht im Schließ-Fenster hängen bleiben.
        var flow = SearchFlow()
        flow.userOpened()
        flow.dismissed(now: t0)
        flow.userOpened()
        XCTAssertEqual(flow.state, .open)
        XCTAssertTrue(flow.systemPresented(now: t(0.1)))
    }

    // MARK: – Anlegen-Cover (Such-Rollen-Tab)

    func testPresentWhileCoverOpenIsRejected() {
        var flow = SearchFlow()
        flow.coverChanged(open: true, now: t0)
        XCTAssertFalse(flow.systemPresented(now: t(0.2)))
        XCTAssertEqual(flow.state, .closed)
    }

    func testPresentDuringCoverDismissWindowIsRejected() {
        var flow = SearchFlow()
        flow.coverChanged(open: true, now: t0)
        flow.coverChanged(open: false, now: t(1))
        // Der verspätete Such-Rollen-Impuls kommt WÄHREND oder kurz nach der
        // Zoom-Rückfahrt — verwerfen.
        XCTAssertFalse(flow.systemPresented(now: t(1.1)))
        XCTAssertFalse(flow.systemPresented(now: t(1 + SearchFlow.coverSettle - 0.01)))
    }

    func testPresentAfterCoverSettleIsAccepted() {
        var flow = SearchFlow()
        flow.coverChanged(open: true, now: t0)
        flow.coverChanged(open: false, now: t(1))
        XCTAssertTrue(flow.systemPresented(now: t(1 + SearchFlow.coverSettle + 0.01)))
        XCTAssertEqual(flow.state, .open)
    }

    func testUserOpenWhileCoverJustClosedIsAccepted() {
        // Direkte Nutzerabsicht nach dem Anlegen-Schließen schlägt das Fenster.
        var flow = SearchFlow()
        flow.coverChanged(open: true, now: t0)
        flow.coverChanged(open: false, now: t(1))
        flow.userOpened()
        XCTAssertEqual(flow.state, .open)
        XCTAssertTrue(flow.systemPresented(now: t(1.1)))
    }

    func testOpenSearchSurvivesCoverCycle() {
        // Suche offen, Anlegen öffnet und schließt darüber: die offene Suche
        // bleibt offen — das Cover-Fenster verwirft nur NEUE Präsentationen.
        var flow = SearchFlow()
        flow.userOpened()
        flow.coverChanged(open: true, now: t0)
        flow.coverChanged(open: false, now: t(1))
        XCTAssertTrue(flow.systemPresented(now: t(1.1)))
        XCTAssertEqual(flow.state, .open)
    }

    func testCoverCycleWhileClosedLeavesClosed() {
        var flow = SearchFlow()
        flow.coverChanged(open: true, now: t0)
        flow.dismissed(now: t(0.5))     // Streuschuss im geschlossenen Zustand
        flow.coverChanged(open: false, now: t(1))
        XCTAssertEqual(flow.state, .closed)
    }

    // MARK: – Der Feld-Beobachter (iOS 27)
    //
    // Auf iOS 27 klappt das System die Suche zu, ohne `isPresented`
    // zurückzuschreiben — und reisst das halb zugeklappte Feld sofort wieder
    // auf, weil das Binding wahr geblieben ist. Der Beobachter misst das
    // Feld an der echten Ansicht; hier stehen die Regeln, nach denen aus
    // Messbildern ein „zu" wird. Die Zahlen stammen aus dem iOS-27-Simulator
    // (17 Pro Max): Ruhebreite 344 pt, Zuklappen fällt sofort auf 280 pt,
    // Absenden über die Tastatur lässt 344 pt stehen.

    private func open(_ w: CGFloat = 344) -> SearchFlow {
        var flow = SearchFlow()
        flow.userOpened()
        // Ein Messbild mit Eingabe setzt die Ruhebreite.
        _ = flow.fieldReading(.init(present: true, width: w, focused: true), now: t0)
        return flow
    }

    private func reading(_ present: Bool, _ width: CGFloat, _ focused: Bool) -> SearchFieldReading {
        .init(present: present, width: width, focused: focused)
    }

    func testRestingFieldNeverCloses() {
        var flow = open()
        for i in 0..<40 {
            XCTAssertFalse(flow.fieldReading(reading(true, 344, true), now: t(Double(i) * 0.05)))
        }
        XCTAssertEqual(flow.state, .open)
    }

    func testKeyboardSubmitDoesNotClose() {
        // „Suchen" auf der Tastatur gibt die Eingabe ab, lässt das Feld aber
        // in voller Breite stehen — das ist KEIN Zuklappen.
        var flow = open()
        for i in 1...40 {
            XCTAssertFalse(flow.fieldReading(reading(true, 344, false), now: t(Double(i) * 0.05)))
        }
    }

    func testCollapsingFieldClosesAfterSettle() {
        var flow = open()
        XCTAssertFalse(flow.fieldReading(reading(true, 280, false), now: t(1)))
        XCTAssertFalse(flow.fieldReading(reading(true, 285, false), now: t(1 + SearchFlow.dismissSettle - 0.01)))
        XCTAssertTrue(flow.fieldReading(reading(true, 300, false), now: t(1 + SearchFlow.dismissSettle)))
    }

    func testAbortedCollapseWithinSettleDoesNotClose() {
        // Nur ein einzelnes schmales Messbild: zu wenig für ein Zuklappen.
        var flow = open()
        XCTAssertFalse(flow.fieldReading(reading(true, 280, false), now: t(1)))
        XCTAssertFalse(flow.fieldReading(reading(true, 344, false), now: t(1.05)))
        // … und die Uhr beginnt danach von vorn.
        XCTAssertFalse(flow.fieldReading(reading(true, 280, false), now: t(1.1)))
        XCTAssertFalse(flow.fieldReading(reading(true, 280, false), now: t(1.1 + SearchFlow.dismissSettle - 0.01)))
        XCTAssertTrue(flow.fieldReading(reading(true, 280, false), now: t(1.1 + SearchFlow.dismissSettle)))
    }

    func testVanishedFieldCloses() {
        var flow = open()
        XCTAssertFalse(flow.fieldReading(.none, now: t(1)))
        XCTAssertTrue(flow.fieldReading(.none, now: t(1 + SearchFlow.dismissSettle)))
    }

    func testMissingFieldBeforeItWasEverSeenNeverCloses() {
        // Beim Aufklappen ist das Feld ein paar Bilder lang noch nicht da —
        // dann darf nichts schließen.
        var flow = SearchFlow()
        flow.userOpened()
        for i in 0..<20 {
            XCTAssertFalse(flow.fieldReading(.none, now: t(Double(i) * 0.05)))
        }
        XCTAssertEqual(flow.state, .open)
    }

    func testNarrowFieldWithoutRestingWidthNeverCloses() {
        // Feld da, ohne je die Eingabe gehalten zu haben: es gibt keinen
        // Maßstab, also auch kein Urteil.
        var flow = SearchFlow()
        flow.userOpened()
        for i in 0..<20 {
            XCTAssertFalse(flow.fieldReading(reading(true, 200, false), now: t(Double(i) * 0.05)))
        }
    }

    func testCloseIsReportedOnlyOnce() {
        // Der Takt fragt zwanzigmal je Sekunde — gemeldet wird EINMAL.
        var flow = open()
        _ = flow.fieldReading(.none, now: t(1))
        XCTAssertTrue(flow.fieldReading(.none, now: t(1 + SearchFlow.dismissSettle)))
        for i in 1...20 {
            XCTAssertFalse(flow.fieldReading(.none, now: t(1 + SearchFlow.dismissSettle + Double(i) * 0.05)))
        }
    }

    func testNoJudgementOutsideOpenState() {
        var flow = open()
        flow.dismissed(now: t(1))
        for i in 0..<20 {
            XCTAssertFalse(flow.fieldReading(.none, now: t(1 + Double(i) * 0.05)))
        }
        XCTAssertEqual(flow.state, .closing(since: t(1)))
    }

    /// Der Kern der Sache: FÜNF Runden hintereinander, jede genau gleich.
    /// Genau hier ging die erste Bauart kaputt — sie trug Reste aus dem
    /// vorigen Durchgang mit und schwieg ab dem zweiten.
    func testFiveCyclesBehaveIdentically() {
        var flow = SearchFlow()
        var now = t0
        for cycle in 1...5 {
            // Lupe getippt.
            XCTAssertTrue(flow.systemPresented(now: now), "Runde \(cycle): Öffnen abgewiesen")
            XCTAssertEqual(flow.state, .open)
            // Aufklappen: erst nichts, dann das wachsende Feld, dann Ruhe.
            XCTAssertFalse(flow.fieldReading(.none, now: now))
            now = now.addingTimeInterval(0.05)
            XCTAssertFalse(flow.fieldReading(reading(true, 380, true), now: now))
            for _ in 0..<20 {
                now = now.addingTimeInterval(0.05)
                XCTAssertFalse(flow.fieldReading(reading(true, 344, true), now: now),
                               "Runde \(cycle): Ruhezustand als Zuklappen gelesen")
            }
            // X getippt: Eingabe weg, Feld klappt ein.
            now = now.addingTimeInterval(0.05)
            XCTAssertFalse(flow.fieldReading(reading(true, 280, false), now: now))
            now = now.addingTimeInterval(SearchFlow.dismissSettle)
            XCTAssertTrue(flow.fieldReading(reading(true, 290, false), now: now),
                          "Runde \(cycle): Zuklappen nicht erkannt")
            flow.dismissed(now: now)
            XCTAssertEqual(flow.state, .closing(since: now))
            // Warten wie ein Mensch, der gleich wieder auf die Lupe tippt.
            now = now.addingTimeInterval(SearchFlow.closeSettle + 0.1)
        }
    }

    /// Dasselbe im Schnelldurchlauf: Tipp auf Tipp, ohne Pause. Öffnen darf
    /// erst nach dem Schließ-Fenster wieder greifen, danach aber sofort.
    func testFastRepeatsStayInStep() {
        var flow = SearchFlow()
        var now = t0
        for _ in 1...5 {
            XCTAssertTrue(flow.systemPresented(now: now))
            now = now.addingTimeInterval(0.05)
            XCTAssertFalse(flow.fieldReading(reading(true, 344, true), now: now))
            now = now.addingTimeInterval(0.05)
            XCTAssertFalse(flow.fieldReading(reading(true, 280, false), now: now))
            now = now.addingTimeInterval(SearchFlow.dismissSettle)
            XCTAssertTrue(flow.fieldReading(reading(true, 280, false), now: now))
            flow.dismissed(now: now)
            now = now.addingTimeInterval(SearchFlow.closeSettle)
        }
        XCTAssertEqual(flow.state, .closing(since: now.addingTimeInterval(-SearchFlow.closeSettle)))
    }

    /// Nach einem Zyklus mit getipptem Text ist nichts anders: der Text lebt
    /// im Suchbegriff, nicht in der Zustandsmaschine.
    func testCloseAfterTypingBehavesLikeAnyOtherClose() {
        var flow = open()
        // Tippen ändert an den Messbildern nichts (gleiche Breite, Eingabe da).
        for i in 1...10 {
            XCTAssertFalse(flow.fieldReading(reading(true, 344, true), now: t(Double(i) * 0.05)))
        }
        XCTAssertFalse(flow.fieldReading(reading(true, 280, false), now: t(1)))
        XCTAssertTrue(flow.fieldReading(reading(true, 280, false), now: t(1 + SearchFlow.dismissSettle)))
    }

    /// Die Ruhebreite gehört zu DIESEM Öffnen. Wird beim nächsten Mal eine
    /// andere gemessen (andere Sprache, anderes Gerät), gilt die neue.
    func testRestingWidthIsTakenFreshEachTime() {
        var flow = open(344)
        flow.dismissed(now: t(1))
        XCTAssertTrue(flow.systemPresented(now: t(2)))
        _ = flow.fieldReading(reading(true, 260, true), now: t(2.1))
        // 280 war im vorigen Durchgang ein Zuklappen — bei Ruhebreite 260
        // ist es der Ruhezustand.
        XCTAssertFalse(flow.fieldReading(reading(true, 280, false), now: t(2.2)))
        XCTAssertFalse(flow.fieldReading(reading(true, 280, false), now: t(3)))
        XCTAssertFalse(flow.fieldReading(reading(true, 250, false), now: t(3.1)))
        XCTAssertTrue(flow.fieldReading(reading(true, 250, false), now: t(3.1 + SearchFlow.dismissSettle)))
    }

    /// Bei offenem Anlegen-Cover verschwindet die Navigationsleiste unter dem
    /// Cover — das ist kein Zuklappen durch den Nutzer, aber der Abgleich
    /// darf trotzdem schließen: unter dem Cover ist keine Suche zu bedienen.
    func testCoverHidingTheFieldClosesTheSearch() {
        var flow = open()
        flow.coverChanged(open: true, now: t(1))
        XCTAssertFalse(flow.fieldReading(.none, now: t(1.1)))
        XCTAssertTrue(flow.fieldReading(.none, now: t(1.1 + SearchFlow.dismissSettle)))
    }

    func testFieldMeasurementContract() {
        // Das Zuklapp-Fenster muss in das gemessene Zeitfenster passen: das
        // abgebrochene Zuklappen liegt rund 0,22 s unter der Ruhebreite.
        XCTAssertGreaterThan(SearchFlow.dismissSettle, 0.05)
        XCTAssertLessThan(SearchFlow.dismissSettle, 0.2)
        // Der Breitenabstand muss über dem Messrauschen und deutlich unter
        // dem gemessenen Einklapp-Sprung (344 -> 280 pt) liegen.
        XCTAssertGreaterThanOrEqual(SearchFlow.collapseMargin, 4)
        XCTAssertLessThan(SearchFlow.collapseMargin, 64)
    }

    // MARK: – Fenstergrößen als Vertrag

    func testWindowsStayWithinPhysicalBounds() {
        // Schließ-Fenster: länger als die Abklapp-Animation (~0,35 s), aber
        // kurz genug, dass ein echter neuer Lupen-Tipp nie hineinfällt.
        XCTAssertGreaterThan(SearchFlow.closeSettle, 0.35)
        XCTAssertLessThanOrEqual(SearchFlow.closeSettle, 0.6)
        // Cover-Fenster: länger als die Zoom-Rückfahrt (~0,5 s).
        XCTAssertGreaterThan(SearchFlow.coverSettle, 0.5)
        XCTAssertLessThanOrEqual(SearchFlow.coverSettle, 1.0)
    }
}
