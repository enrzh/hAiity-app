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

/// Die Mehr-Tafel: zwei Höhen, ein Zug, drei mögliche Ausgänge. In der
/// Ansicht wäre das eine Sache fürs Auge; hier steht, ab wann sie aufklappt,
/// wann sie zurückgeht und wann sie zu ist.
final class MorePanelTests: XCTestCase {
    /// Nutzhöhe eines iPhone 17 Pro Max.
    private let tall: CGFloat = 874
    /// Ein niedriger Container — dort greift der Deckel nicht.
    private let short: CGFloat = 600

    // MARK: – Die zwei Höhen

    func testTheSmallHeightIsCapped() {
        // 0,58 × 874 = 507 -> unter dem Deckel; 0,58 × 1000 = 580 -> gedeckelt.
        XCTAssertEqual(MorePanel.collapsedHeight(container: tall),
                       tall * MorePanel.ratio, accuracy: 0.001)
        XCTAssertEqual(MorePanel.collapsedHeight(container: 1000), MorePanel.cap, accuracy: 0.001)
    }

    func testTheBigHeightLeavesAStripOfTheList() {
        let big = MorePanel.expandedHeight(container: tall)
        XCTAssertEqual(big, tall * MorePanel.expandedRatio, accuracy: 0.001)
        XCTAssertLessThan(big, tall)          // nie randlos
        XCTAssertGreaterThan(big, MorePanel.collapsedHeight(container: tall))
    }

    /// Auf einem niedrigen Container liegt der Deckel des kleinen Zustands
    /// unter der großen Höhe — die Tafel darf beim Aufziehen nicht
    /// schrumpfen.
    func testTheBigHeightIsNeverSmallerThanTheSmallOne() {
        for h in stride(from: 200.0, through: 1200.0, by: 100.0) {
            let container = CGFloat(h)
            XCTAssertGreaterThanOrEqual(MorePanel.expandedHeight(container: container),
                                        MorePanel.collapsedHeight(container: container))
        }
    }

    // MARK: – Während des Zuges

    func testPullingUpGrows() {
        let small = MorePanel.collapsedHeight(container: tall)
        let h = MorePanel.height(container: tall, expanded: false, drag: -100)
        XCTAssertEqual(h, small + 100, accuracy: 0.001)
    }

    func testGrowthIsDampedBeyondTheBigHeight() {
        let big = MorePanel.expandedHeight(container: tall)
        let h = MorePanel.height(container: tall, expanded: true, drag: -300)
        XCTAssertGreaterThan(h, big)                  // es geht noch etwas
        XCTAssertLessThan(h, big + 300)               // aber lange nicht alles
        XCTAssertLessThan(h, big + MorePanel.rubberBand(.infinity) + 1)
    }

    func testRubberBandIsMonotonicAndBounded() {
        XCTAssertEqual(MorePanel.rubberBand(0), 0, accuracy: 0.001)
        XCTAssertLessThan(MorePanel.rubberBand(50), MorePanel.rubberBand(200))
        XCTAssertLessThan(MorePanel.rubberBand(100_000), 121)
    }

    func testPullingDownFromSmallMovesInsteadOfShrinking() {
        let small = MorePanel.collapsedHeight(container: tall)
        XCTAssertEqual(MorePanel.height(container: tall, expanded: false, drag: 80),
                       small, accuracy: 0.001)
        XCTAssertEqual(MorePanel.offset(expanded: false, drag: 80), 80, accuracy: 0.001)
    }

    func testPullingDownFromBigShrinksToTheSmallHeightAndStops() {
        let small = MorePanel.collapsedHeight(container: tall)
        let big = MorePanel.expandedHeight(container: tall)
        XCTAssertEqual(MorePanel.height(container: tall, expanded: true, drag: 100),
                       big - 100, accuracy: 0.001)
        XCTAssertEqual(MorePanel.height(container: tall, expanded: true, drag: 5000),
                       small, accuracy: 0.001)
        // Und sie WANDERT dabei nicht: eine Geste, eine Bewegung.
        XCTAssertEqual(MorePanel.offset(expanded: true, drag: 100), 0, accuracy: 0.001)
    }

    func testAnUntouchedPanelKeepsItsHeight() {
        XCTAssertEqual(MorePanel.height(container: short, expanded: false, drag: 0),
                       MorePanel.collapsedHeight(container: short), accuracy: 0.001)
        XCTAssertEqual(MorePanel.height(container: short, expanded: true, drag: 0),
                       MorePanel.expandedHeight(container: short), accuracy: 0.001)
        XCTAssertEqual(MorePanel.offset(expanded: false, drag: 0), 0, accuracy: 0.001)
    }

    // MARK: – Was ein losgelassener Zug bedeutet

    func testAShortPullUpExpands() {
        XCTAssertEqual(MorePanel.resolve(drag: -80, predicted: -80, expanded: false), .expand)
    }

    func testAFlickUpExpandsEvenIfTheFingerBarelyMoved() {
        XCTAssertEqual(MorePanel.resolve(drag: -20, predicted: -400, expanded: false), .expand)
    }

    func testATinyPullChangesNothing() {
        XCTAssertEqual(MorePanel.resolve(drag: -10, predicted: -10, expanded: false), .collapse)
        XCTAssertEqual(MorePanel.resolve(drag: 10, predicted: 10, expanded: true), .expand)
    }

    func testPullingDownFromSmallDismisses() {
        XCTAssertEqual(MorePanel.resolve(drag: 120, predicted: 120, expanded: false), .dismiss)
        // Kurz und knapp über der Schnappgrenze: erst zurück, nicht gleich zu.
        XCTAssertEqual(MorePanel.resolve(drag: 70, predicted: 70, expanded: false), .collapse)
    }

    /// Aus dem großen Zustand führt ein Zug nach unten ZURÜCK auf die kleine
    /// Höhe — nicht sofort hinaus. Erst ein Zug über die ganze Tafel schließt.
    func testPullingDownFromBigGoesBackFirst() {
        XCTAssertEqual(MorePanel.resolve(drag: 150, predicted: 150, expanded: true), .collapse)
        XCTAssertEqual(MorePanel.resolve(drag: 400, predicted: 400, expanded: true), .dismiss)
    }
}

/// Die Vorschau des langen Drucks: sie soll den Bildschirm ausfüllen (bis auf
/// einen schmalen Rand) und so viel Historie zeigen, wie hineinpasst. Beides
/// hängt an der FENSTERBREITE — auf einem SE muss es genauso stimmen wie auf
/// einem Max, und ein Screenshot je Gerät ist keine Prüfung.
final class HabitPreviewMetricsTests: XCTestCase {

    func testPreviewIsScreenWideMinusASmallMargin() {
        for width in [375.0, 393.0, 430.0, 440.0] {
            let m = HabitCard.previewMetrics(windowWidth: CGFloat(width))
            XCTAssertEqual(m.width, CGFloat(width) - 2 * HabitCard.previewMargin, accuracy: 0.001)
        }
    }

    /// Auf einem sehr schmalen Fenster (Slide-Over) greift die Untergrenze —
    /// eine 40-pt-Vorschau wäre keine.
    func testVeryNarrowWindowsGetTheMinimum() {
        let m = HabitCard.previewMetrics(windowWidth: 120)
        XCTAssertEqual(m.width, HabitCard.previewMinWidth, accuracy: 0.001)
    }

    /// Mehr Breite heißt MEHR WOCHEN, nicht dasselbe Raster in einer
    /// größeren Schachtel.
    func testWiderWindowsShowMoreWeeks() {
        let se = HabitCard.previewMetrics(windowWidth: 375).weeks
        let max = HabitCard.previewMetrics(windowWidth: 440).weeks
        XCTAssertGreaterThan(max, se)
        XCTAssertGreaterThan(se, 8)
    }

    /// Die Wochen müssen auch WIRKLICH hineinpassen: Rastermaß × Wochen darf
    /// das Innenmaß nicht überschreiten, sonst steht die Vorschau doch wieder
    /// abgeschnitten da.
    func testTheWeeksFitIntoTheWidth() {
        for width in [320.0, 375.0, 393.0, 440.0, 1024.0] {
            let m = HabitCard.previewMetrics(windowWidth: CGFloat(width))
            let content = m.width - 2 * Theme.Metrics.gutter
            let used = CGFloat(m.weeks) * (HabitCard.previewCell + HabitCard.previewGap)
                - HabitCard.previewGap
            XCTAssertLessThanOrEqual(used, content + 0.001, "bei \(width) pt")
        }
    }

    /// Das Raster IST ein Jahr — auf einem sehr breiten Fenster hört es bei
    /// 53 Wochen auf.
    func testAYearIsTheCeiling() {
        XCTAssertEqual(HabitCard.previewMetrics(windowWidth: 4000).weeks, 53)
    }
}
