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
        // Such-Zug direkt nach dem Anlegen-Schließen: Absicht schlägt Fenster.
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
