import XCTest
@testable import Haiity

/// Die Geometrie der schwebenden Leiste. Beide Rechnungen hier sind der
/// Grund, warum sich der Anlegen-Knopf jetzt BEWEGT statt zu blenden und
/// warum die Auswahl-Lasur einem Finger folgen kann — in der Ansicht wären
/// sie nicht prüfbar.
final class ChromeLayoutTests: XCTestCase {

    // MARK: – Wohin der Anlegen-Knopf fährt

    func testCollapsedWidthFollowsTheMetrics() {
        // 2 Lasuren à 44 + der Spalt dazwischen + Rand links und rechts.
        XCTAssertEqual(ChromeLayout.inset, 4, accuracy: 0.001)
        XCTAssertEqual(ChromeLayout.collapsedSwitcherWidth, 100, accuracy: 0.001)
        XCTAssertEqual(ChromeLayout.collapsedSwitcherWidth,
                       2 * Theme.Metrics.hit + 3 * ChromeLayout.inset,
                       accuracy: 0.001)
    }

    func testExpandedButtonSitsFlushAtTheTrailingEdge() {
        let row: CGFloat = 361            // 393 pt Gerät minus 2 × 16 Rand
        let x = ChromeLayout.addButtonX(collapsed: false, rowWidth: row)
        XCTAssertEqual(x + Theme.Metrics.control, row, accuracy: 0.001)
    }

    func testCollapsedButtonOverlapsTheCapsule() {
        let x = ChromeLayout.addButtonX(collapsed: true, rowWidth: 361)
        // Er steht NICHT daneben, sondern greift um `gap` in die Kapsel —
        // näher als der Container-Abstand, damit das Glas verschmilzt.
        XCTAssertEqual(x, ChromeLayout.collapsedSwitcherWidth - Theme.Metrics.gap, accuracy: 0.001)
        XCTAssertLessThan(x, ChromeLayout.collapsedSwitcherWidth)
    }

    func testTheTravelIsOneContinuousDistance() {
        // Der springende Punkt der ganzen Übung: zwischen beiden Zuständen
        // liegt EINE Strecke, die sich interpolieren lässt — nicht zwei
        // Views, zwischen denen übergeblendet wird.
        let row: CGFloat = 361
        let open = ChromeLayout.addButtonX(collapsed: false, rowWidth: row)
        let shut = ChromeLayout.addButtonX(collapsed: true, rowWidth: row)
        XCTAssertGreaterThan(open - shut, 200)
        // Auf halber Strecke ist der Knopf weder in der Ecke noch im Blob.
        let middle = (open + shut) / 2
        XCTAssertGreaterThan(middle, shut + 50)
        XCTAssertLessThan(middle, open - 50)
    }

    func testNarrowRowNeverPushesTheButtonBackwards() {
        // Vorschauen und sehr schmale Fenster: der ausgeklappte Platz darf
        // nicht LINKS vom Blob-Platz liegen, sonst führe der Knopf beim
        // Zusammenziehen nach rechts statt nach links.
        let x = ChromeLayout.addButtonX(collapsed: false, rowWidth: 120)
        XCTAssertGreaterThanOrEqual(x, ChromeLayout.addButtonX(collapsed: true, rowWidth: 120))
    }

    // MARK: – Welches Segment trifft der Finger

    private enum Seg: Hashable { case left, right }

    /// Zwei 44er-Segmente mit 4 pt Spalt, wie im zusammengezogenen Blob.
    private let frames: [Seg: CGRect] = [
        .left: CGRect(x: 4, y: 4, width: 44, height: 44),
        .right: CGRect(x: 52, y: 4, width: 44, height: 44),
    ]

    func testPointInsideASegmentHitsIt() {
        XCTAssertEqual(ChromeLayout.segment(at: CGPoint(x: 20, y: 26), frames: frames), .left)
        XCTAssertEqual(ChromeLayout.segment(at: CGPoint(x: 70, y: 26), frames: frames), .right)
    }

    func testFingerPastTheEdgeStillMeansTheOuterSegment() {
        // Wer über den linken Rand hinauszieht, meint weiterhin links.
        XCTAssertEqual(ChromeLayout.segment(at: CGPoint(x: -12, y: 26), frames: frames), .left)
        XCTAssertEqual(ChromeLayout.segment(at: CGPoint(x: 110, y: 26), frames: frames), .right)
    }

    func testTheGapBetweenSegmentsIsDeterministic() {
        // Exakt im Spalt: immer dieselbe Antwort, nie ein Flackern.
        let gapPoint = CGPoint(x: 50, y: 26)
        XCTAssertEqual(ChromeLayout.segment(at: gapPoint, frames: frames), .left)
        XCTAssertEqual(ChromeLayout.segment(at: gapPoint, frames: frames), .left)
    }

    func testSmallVerticalDriftKeepsTracking() {
        // Ein Finger, der beim Ziehen ein paar Punkte nach oben rutscht,
        // darf die Auswahl nicht abbrechen lassen.
        XCTAssertEqual(ChromeLayout.segment(at: CGPoint(x: 70, y: -14), frames: frames), .right)
        XCTAssertEqual(ChromeLayout.segment(at: CGPoint(x: 70, y: 62), frames: frames), .right)
    }

    func testFarAwayIsACancel() {
        // Weit weg losgelassen = Abbruch. Die Lasur schnappt zurück, statt
        // eine Wahl zu treffen, die niemand gemeint hat.
        XCTAssertNil(ChromeLayout.segment(at: CGPoint(x: 70, y: 300), frames: frames))
        XCTAssertNil(ChromeLayout.segment(at: CGPoint(x: -200, y: 26), frames: frames))
        XCTAssertNil(ChromeLayout.segment(at: CGPoint(x: 400, y: 26), frames: frames))
    }

    func testNoFramesMeansNoHit() {
        // Vor der ersten Layout-Runde gibt es keine Rahmen — dann darf der
        // Treffertest raten statt zu raten.
        XCTAssertNil(ChromeLayout.segment(at: .zero, frames: [Seg: CGRect]()))
    }

    func testExpandedSegmentsAreWiderAndStillHit() {
        // Ausgeklappt tragen die Segmente Beschriftungen und sind breiter.
        let wide: [Seg: CGRect] = [
            .left: CGRect(x: 4, y: 4, width: 96, height: 44),
            .right: CGRect(x: 104, y: 4, width: 84, height: 44),
        ]
        XCTAssertEqual(ChromeLayout.segment(at: CGPoint(x: 60, y: 26), frames: wide), .left)
        XCTAssertEqual(ChromeLayout.segment(at: CGPoint(x: 150, y: 26), frames: wide), .right)
    }
}
