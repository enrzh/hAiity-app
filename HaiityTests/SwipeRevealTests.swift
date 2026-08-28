import XCTest
@testable import Haiity

/// Die reine Aufzieh-Mechanik (`SwipeReveal`) — Klemmen, Gummiband und
/// Schnapp-Entscheidungen, exakt die Regeln, die im Simulator per
/// synthetischem Zug verifiziert wurden. Die Geste selbst (UIKit-Pan samt
/// Raster-Arbitrage) steht in `SwipeRevealPan`; hier steht, WAS sie
/// entscheidet.
final class SwipeRevealTests: XCTestCase {

    // MARK: – Maße

    func testRevealWidthGrowsPerButton() {
        XCTAssertEqual(SwipeReveal.revealWidth(count: 0), 0)
        XCTAssertEqual(SwipeReveal.revealWidth(count: 1),
                       SwipeReveal.buttonWidth + SwipeReveal.buttonGap)
        XCTAssertEqual(SwipeReveal.revealWidth(count: 2),
                       2 * (SwipeReveal.buttonWidth + SwipeReveal.buttonGap))
    }

    // MARK: – Gummiband

    func testRubberBandIsZeroWithoutExcess() {
        XCTAssertEqual(SwipeReveal.rubberBand(0), 0)
        XCTAssertEqual(SwipeReveal.rubberBand(-10), 0)
    }

    func testRubberBandIsMonotonicAndCapped() {
        let small = SwipeReveal.rubberBand(20)
        let large = SwipeReveal.rubberBand(400)
        XCTAssertGreaterThan(small, 0)
        XCTAssertGreaterThan(large, small)
        XCTAssertLessThan(large, 64)
    }

    // MARK: – Versatz

    func testOffsetIsLinearWithinRestingWidths() {
        XCTAssertEqual(SwipeReveal.offset(start: 0, translation: -50,
                                          leadingWidth: 80, trailingWidth: 80), -50)
        XCTAssertEqual(SwipeReveal.offset(start: -40, translation: 15,
                                          leadingWidth: 80, trailingWidth: 80), -25)
    }

    func testOffsetRubberBandsPastTheButtons() {
        let offset = SwipeReveal.offset(start: 0, translation: -300,
                                        leadingWidth: 80, trailingWidth: 80)
        XCTAssertLessThan(offset, -80)
        XCTAssertGreaterThan(offset, -80 - 64)
    }

    // MARK: – Schnappen

    func testShortPullSnapsClosed() {
        XCTAssertEqual(SwipeReveal.resting(pull: -20, velocity: 0,
                                           leadingWidth: 80, trailingWidth: 80,
                                           cardWidth: 400), .closed)
    }

    func testHalfPullSnapsOpen() {
        XCTAssertEqual(SwipeReveal.resting(pull: -50, velocity: 0,
                                           leadingWidth: 80, trailingWidth: 80,
                                           cardWidth: 400), .trailing)
        XCTAssertEqual(SwipeReveal.resting(pull: 50, velocity: 0,
                                           leadingWidth: 80, trailingWidth: 80,
                                           cardWidth: 400), .leading)
    }

    /// Ein flotter kurzer Wisch öffnet; ein Zurückschnipsen aus offener
    /// Lage schließt — die Geschwindigkeit projiziert den Zug.
    func testVelocityProjectsThePull() {
        XCTAssertEqual(SwipeReveal.resting(pull: -25, velocity: -400,
                                           leadingWidth: 80, trailingWidth: 80,
                                           cardWidth: 400), .trailing)
        XCTAssertEqual(SwipeReveal.resting(pull: -60, velocity: 500,
                                           leadingWidth: 80, trailingWidth: 80,
                                           cardWidth: 400), .closed)
    }

    /// Der Voll-Wisch entscheidet am ROHEN Zug: das Gummiband deckelt die
    /// Anzeige unterhalb der Schwelle — am gummierten Versatz gemessen wäre
    /// der Voll-Wisch unerreichbar (so gebaut, im Simulator ertappt, hier
    /// festgenagelt).
    func testFullSwipeCommitsOnRawPull() {
        XCTAssertEqual(SwipeReveal.resting(pull: -300, velocity: 0,
                                           leadingWidth: 80, trailingWidth: 80,
                                           cardWidth: 400), .commitTrailing)
        XCTAssertEqual(SwipeReveal.resting(pull: 300, velocity: 0,
                                           leadingWidth: 80, trailingWidth: 80,
                                           cardWidth: 400), .commitLeading)
        // Der gummierte Maximal-Versatz (Ruheweite + Deckel) committet NICHT.
        XCTAssertEqual(SwipeReveal.resting(pull: -140, velocity: 0,
                                           leadingWidth: 80, trailingWidth: 80,
                                           cardWidth: 400), .trailing)
    }

    func testCommitNeedsButtonsOnThatSide() {
        XCTAssertEqual(SwipeReveal.resting(pull: 300, velocity: 0,
                                           leadingWidth: 0, trailingWidth: 80,
                                           cardWidth: 400), .closed)
    }

    // MARK: – Beginnen dürfen

    func testVerticalIntentNeverBegins() {
        XCTAssertFalse(SwipeReveal.horizontalIntent(dx: 6, dy: 20))
        XCTAssertFalse(SwipeReveal.canBegin(towardTrailing: true, horizontalIntent: false,
                                            open: false, hasLeading: true, hasTrailing: true,
                                            overGrid: false, gridAtTrailingEnd: true))
    }

    func testNearHorizontalIntentStartsResponsively() {
        XCTAssertTrue(SwipeReveal.horizontalIntent(dx: 8, dy: 7))
        XCTAssertFalse(SwipeReveal.horizontalIntent(dx: 20, dy: 24))
    }

    func testTrailingOverGridOnlyAtTheEnd() {
        // Am Ende: Aufziehen. Mitten in der Historie: Scrollen.
        XCTAssertTrue(SwipeReveal.canBegin(towardTrailing: true, horizontalIntent: true,
                                           open: false, hasLeading: true, hasTrailing: true,
                                           overGrid: true, gridAtTrailingEnd: true))
        XCTAssertFalse(SwipeReveal.canBegin(towardTrailing: true, horizontalIntent: true,
                                            open: false, hasLeading: true, hasTrailing: true,
                                            overGrid: true, gridAtTrailingEnd: false))
    }

    func testLeadingOverGridBelongsToHistory() {
        XCTAssertFalse(SwipeReveal.canBegin(towardTrailing: false, horizontalIntent: true,
                                            open: false, hasLeading: true, hasTrailing: true,
                                            overGrid: true, gridAtTrailingEnd: true))
        // Vom Kopf (nicht über dem Raster) geht leading.
        XCTAssertTrue(SwipeReveal.canBegin(towardTrailing: false, horizontalIntent: true,
                                           open: false, hasLeading: true, hasTrailing: true,
                                           overGrid: false, gridAtTrailingEnd: true))
    }

    func testOpenCardIsSteeredByAnyHorizontalDrag() {
        XCTAssertTrue(SwipeReveal.canBegin(towardTrailing: false, horizontalIntent: true,
                                           open: true, hasLeading: false, hasTrailing: true,
                                           overGrid: true, gridAtTrailingEnd: false))
    }

    func testSidesWithoutActionsDoNotBegin() {
        XCTAssertFalse(SwipeReveal.canBegin(towardTrailing: true, horizontalIntent: true,
                                            open: false, hasLeading: true, hasTrailing: false,
                                            overGrid: false, gridAtTrailingEnd: true))
        XCTAssertFalse(SwipeReveal.canBegin(towardTrailing: false, horizontalIntent: true,
                                            open: false, hasLeading: false, hasTrailing: true,
                                            overGrid: false, gridAtTrailingEnd: true))
    }
}
