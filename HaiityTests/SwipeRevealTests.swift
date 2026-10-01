import XCTest
import SwiftUI
@testable import Haiity

/// Die reine Aufzieh-Mechanik (`SwipeReveal`) — Klemmen, Gummiband und
/// Schnapp-Entscheidungen, exakt die Regeln, die im Simulator per
/// synthetischem Zug verifiziert wurden. Die Geste selbst (UIKit-Pan samt
/// Raster-Arbitrage) steht in `SwipeRevealPan`; hier steht, WAS sie
/// entscheidet.
final class SwipeRevealTests: XCTestCase {
    @MainActor
    func testCheckInActionsApplyWithoutWaitingForSettleAnimation() {
        for operation: SwipeOperation in [.done, .reset, .increment, .yes, .no] {
            let session = SwipeRevealSession()
            session.offset = 100
            var count = 0
            let action = RevealAction(operation: operation, title: "Test", symbol: "checkmark", tint: .green) {
                count += 1
            }
            session.perform(action, reduceMotion: false)
            XCTAssertEqual(count, 1, "\(operation) must apply during the tap callback")
            XCTAssertEqual(session.offset, 0)
            session.perform(action, reduceMotion: false)
            XCTAssertEqual(count, 1, "the settle lock must prevent duplicate delivery")
        }
    }

    @MainActor
    func testInterruptedGestureClosesWithoutDeliveringAnAction() {
        let session = SwipeRevealSession()
        session.width = 350
        session.begin()
        session.applyTranslation(-100, leadingCount: 1, trailingCount: 1)
        XCTAssertLessThan(session.offset, 0)
        session.snap(to: 0, reduceMotion: true)
        XCTAssertEqual(session.offset, 0)
        XCTAssertFalse(session.actionLock)
        session.begin()
        session.applyTranslation(40, leadingCount: 1, trailingCount: 1)
        XCTAssertEqual(session.offset, 40, "a fresh swipe must start from the closed position")
    }


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

    func testInitialVelocityNormalizesAndClampsReleaseSpeed() {
        XCTAssertEqual(SwipeReveal.initialVelocity(velocity: 0, distance: 100), 0)
        XCTAssertEqual(SwipeReveal.initialVelocity(velocity: 200, distance: 100), 2)
        XCTAssertEqual(SwipeReveal.initialVelocity(velocity: -2_000, distance: 100), -8)
        XCTAssertEqual(SwipeReveal.initialVelocity(velocity: 2_000, distance: 100), 8)
        XCTAssertEqual(SwipeReveal.initialVelocity(velocity: 500, distance: 1), 0)
    }

    func testSpringVelocityFollowsTheDirectionOfTravel() {
        XCTAssertEqual(SwipeReveal.initialVelocity(velocity: -200, distance: -100), 2)
        XCTAssertEqual(SwipeReveal.initialVelocity(velocity: 200, distance: -100), -2)
        XCTAssertEqual(SwipeReveal.initialVelocity(velocity: -500, distance: -0.5), 0)
    }

    func testGraphFitsWholeColumnsBetweenEqualInsets() {
        for viewport: CGFloat in [280, 343, 361, 393, 700] {
            let cell = ContributionChart.fittedCell(viewport: viewport, cell: 12, gap: 3)
            let columns = (viewport - 8 + 3) / (cell + 3)
            XCTAssertEqual(columns, columns.rounded(), accuracy: 0.000001)
            XCTAssertGreaterThanOrEqual(cell, 12)
            XCTAssertEqual(columns * (cell + 3) - 3 + 8, viewport, accuracy: 0.000001)
        }
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
