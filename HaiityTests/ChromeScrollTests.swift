import XCTest
@testable import Haiity

/// Der selbstgebaute Ersatz für `.tabBarMinimizeBehavior(.onScrollDown)`.
/// Die Regeln stecken in `ChromeScroll` und sind hier festgenagelt — die
/// Oberfläche selbst lässt sich nicht scrollen, ohne einen Simulator
/// anzuwerfen, die Entscheidung darüber schon.
///
/// Zeit wird IMMER explizit übergeben: die Nachlaufsperre ist eine
/// Zeitspanne, und ein Test, der auf `Date.now` wartet, ist ein Test, der
/// irgendwann auf einer langsamen Maschine kippt.
final class ChromeScrollTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// Ruhelage: erste Zeile unter der großen Überschrift, drei Karten sichtbar.
    private func atRest() -> [Int: CGFloat] { [0: 96, 1: 300, 2: 504] }

    /// Alle sichtbaren Zeilen wandern um denselben Betrag — genau das nutzt
    /// die Delta-Rechnung aus.
    private func scrolled(by amount: CGFloat, from frames: [Int: CGFloat]) -> [Int: CGFloat] {
        frames.mapValues { $0 - amount }
    }

    // MARK: – Grundfälle

    func testFirstMeasurementChangesNothing() {
        var chrome = ChromeScroll()
        XCTAssertNil(chrome.decide(atRest(), now: t0))
        XCTAssertFalse(chrome.collapsed)
    }

    func testScrollingDownCollapses() {
        var chrome = ChromeScroll()
        _ = chrome.decide(atRest(), now: t0)
        XCTAssertEqual(chrome.decide(scrolled(by: 60, from: atRest()), now: t0.addingTimeInterval(0.1)), true)
    }

    func testTinyMovementDoesNotCollapse() {
        var chrome = ChromeScroll()
        _ = chrome.decide(atRest(), now: t0)
        // 12 pt sind ein Zittern, kein Wisch — und liegen unter der Schwelle.
        XCTAssertNil(chrome.decide(scrolled(by: 12, from: atRest()), now: t0.addingTimeInterval(0.1)))
    }

    /// Mehrere kleine Schritte in dieselbe Richtung summieren sich; darauf
    /// beruht das Gefühl, dass ein langsamer Wisch genauso wirkt wie ein
    /// schneller.
    func testSmallStepsAccumulate() {
        var chrome = ChromeScroll()
        var frames = atRest()
        _ = chrome.decide(frames, now: t0)
        var result: Bool?
        for step in 1...3 {
            frames = scrolled(by: 10, from: frames)
            result = chrome.decide(frames, now: t0.addingTimeInterval(0.05 * Double(step)))
        }
        XCTAssertEqual(result, true)
    }

    func testDirectionChangeResetsTheRun() {
        var chrome = ChromeScroll()
        var frames = atRest()
        _ = chrome.decide(frames, now: t0)
        frames = scrolled(by: 20, from: frames)          // fast, aber nicht ganz
        XCTAssertNil(chrome.decide(frames, now: t0.addingTimeInterval(0.1)))
        frames = scrolled(by: -8, from: frames)          // Richtungswechsel
        XCTAssertNil(chrome.decide(frames, now: t0.addingTimeInterval(0.2)))
        frames = scrolled(by: 20, from: frames)          // wieder runter, aber von vorn
        XCTAssertNil(chrome.decide(frames, now: t0.addingTimeInterval(0.3)))
    }

    // MARK: – Nachlaufsperre

    /// Das Zusammenziehen SELBST verschiebt die Zeilen (die Köpfe werden
    /// kleiner). Ohne Sperre liest sich der eigene Umbau als weiterer Wisch
    /// und der Umschalter flackert.
    func testReflowRightAfterACollapseIsIgnored() {
        var chrome = ChromeScroll()
        var frames = atRest()
        _ = chrome.decide(frames, now: t0)
        frames = scrolled(by: 60, from: frames)
        XCTAssertEqual(chrome.decide(frames, now: t0.addingTimeInterval(0.1)), true)
        chrome.collapsed = true
        chrome.settle(now: t0.addingTimeInterval(0.1))

        // Kopfhöhen schrumpfen: alle Zeilen rutschen hoch, ohne dass jemand
        // den Finger bewegt hätte.
        frames = scrolled(by: 40, from: frames)
        XCTAssertNil(chrome.decide(frames, now: t0.addingTimeInterval(0.2)))
        frames = scrolled(by: 40, from: frames)
        XCTAssertNil(chrome.decide(frames, now: t0.addingTimeInterval(0.4)))
    }

    func testAfterTheSettleWindowScrollingUpExpandsAgain() {
        var chrome = ChromeScroll()
        var frames = atRest()
        _ = chrome.decide(frames, now: t0)
        frames = scrolled(by: 200, from: frames)
        XCTAssertEqual(chrome.decide(frames, now: t0.addingTimeInterval(0.1)), true)
        chrome.collapsed = true
        chrome.settle(now: t0.addingTimeInterval(0.1))

        frames = scrolled(by: -40, from: frames)
        XCTAssertEqual(chrome.decide(frames, now: t0.addingTimeInterval(1)), false)
    }

    // MARK: – Oben ist immer offen

    func testBackAtTheTopExpandsEvenWithoutAnUpwardRun() {
        var chrome = ChromeScroll()
        _ = chrome.decide(atRest(), now: t0)
        chrome.collapsed = true
        // Erste Zeile steht wieder auf ihrer Ruheposition.
        XCTAssertEqual(chrome.decide(atRest(), now: t0.addingTimeInterval(1)), false)
    }

    func testAlreadyExpandedAtTheTopReportsNoChange() {
        var chrome = ChromeScroll()
        _ = chrome.decide(atRest(), now: t0)
        XCTAssertNil(chrome.decide(atRest(), now: t0.addingTimeInterval(1)))
    }

    /// Gummiband am Listenanfang zieht die erste Zeile ÜBER ihre Ruhelage.
    /// Das darf die Ruhelage nicht dauerhaft verschieben — sonst gilt „oben"
    /// nie wieder.
    func testOverscrollAtTheTopKeepsTheRestPositionUsable() {
        var chrome = ChromeScroll()
        _ = chrome.decide(atRest(), now: t0)
        _ = chrome.decide(scrolled(by: -50, from: atRest()), now: t0.addingTimeInterval(0.1))
        chrome.collapsed = true
        // Zurück in der Ruhelage: der Slack ist klein, die Ruhelage wurde
        // durchs Gummiband angehoben — trotzdem muss ein echter Wisch nach
        // oben wieder ausklappen.
        var frames = scrolled(by: 300, from: atRest())
        _ = chrome.decide(frames, now: t0.addingTimeInterval(0.2))
        frames = scrolled(by: -40, from: frames)
        XCTAssertEqual(chrome.decide(frames, now: t0.addingTimeInterval(0.3)), false)
    }

    // MARK: – Ausreißer

    /// Bereichswechsel, Tastatur, Drehung: das sind Layout-Sprünge, keine
    /// Wischgesten. Wer die mitrechnet, klappt das Chrom bei jedem Blatt zu.
    func testHugeJumpsAreIgnored() {
        var chrome = ChromeScroll()
        _ = chrome.decide(atRest(), now: t0)
        XCTAssertNil(chrome.decide(scrolled(by: 900, from: atRest()), now: t0.addingTimeInterval(0.1)))
    }

    /// Wird die Liste gefiltert, verschwinden Zeilen. Ohne gemeinsame Zeile
    /// gibt es kein Delta — und dann lieber gar keine Entscheidung als eine
    /// geratene.
    func testNoSharedRowMeansNoDecision() {
        var chrome = ChromeScroll()
        _ = chrome.decide([3: -200, 4: -10], now: t0)
        XCTAssertNil(chrome.decide([7: -300, 8: -100], now: t0.addingTimeInterval(0.1)))
    }

    func testRebaseAndExpandResetTheState() {
        var chrome = ChromeScroll()
        var frames = atRest()
        _ = chrome.decide(frames, now: t0)
        frames = scrolled(by: 20, from: frames)
        _ = chrome.decide(frames, now: t0.addingTimeInterval(0.1))
        // Bereich gewechselt: Messung übernehmen, Lauf verwerfen.
        chrome.rebase(scrolled(by: 20, from: frames))
        chrome.collapsed = true
        chrome.expand()
        XCTAssertFalse(chrome.collapsed)
        // Der verworfene Lauf darf nicht nachträglich zuschlagen.
        XCTAssertNil(chrome.decide(scrolled(by: 20, from: frames), now: t0.addingTimeInterval(0.2)))
    }
}
