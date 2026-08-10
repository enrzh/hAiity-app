import XCTest
@testable import Haiity

/// Punkt 4 der Geräte-Rückmeldung: der Such-Zug soll FRÜHER und mit
/// sichtbarem Fortschritt feuern, und das Chrom (Leiste unten) darf während
/// eines Zugs am Listenanfang — und im Rückschnepper direkt danach — keine
/// Entscheidung treffen.
final class SearchPullFeedbackTests: XCTestCase {

    private func pull(first: CGFloat?) -> SearchPull {
        var p = SearchPull()
        p.latestFirst = first
        return p
    }

    // MARK: – Fortschritt

    func testProgressGrowsWithARubberBandPull() {
        var p = pull(first: 0)
        // Gummiband: Zeilen folgen ~halb so weit wie der Finger.
        XCTAssertFalse(p.update(translation: CGSize(width: 0, height: 30), first: 14))
        let early = p.progress
        XCTAssertGreaterThan(early, 0)
        XCTAssertLessThan(early, 1)
        XCTAssertFalse(p.update(translation: CGSize(width: 0, height: 55), first: 26))
        XCTAssertGreaterThan(p.progress, early)
    }

    func testProgressStaysZeroWhileScrollingOneToOne() {
        var p = pull(first: 0)
        XCTAssertFalse(p.update(translation: CGSize(width: 0, height: 60), first: 60))
        XCTAssertEqual(p.progress, 0)
        XCTAssertFalse(p.update(translation: CGSize(width: 0, height: 120), first: 118))
        XCTAssertEqual(p.progress, 0)
    }

    func testProgressStaysZeroMidList() {
        var p = pull(first: nil)
        XCTAssertFalse(p.update(translation: CGSize(width: 0, height: 200)))
        XCTAssertEqual(p.progress, 0)
    }

    func testFiresAtTheLoweredThreshold() {
        var p = pull(first: 0)
        // 70 pt Fingerweg, Zeilen im Gummiband: das feuert jetzt — vorher
        // (Schwelle 90) war genau dieser Zug „zu spät".
        XCTAssertTrue(p.update(translation: CGSize(width: 0, height: 70), first: 34))
        XCTAssertEqual(p.progress, 1, accuracy: 0.001)
    }

    func testEndedResetsProgress() {
        var p = pull(first: 0)
        _ = p.update(translation: CGSize(width: 0, height: 40), first: 19)
        XCTAssertGreaterThan(p.progress, 0)
        p.ended()
        XCTAssertEqual(p.progress, 0)
    }

    // MARK: – Chrom-Stillhalten

    func testChromeIsSuppressedDuringACandidatePull() {
        var p = pull(first: 0)
        XCTAssertFalse(p.suppressesChrome())
        _ = p.update(translation: CGSize(width: 0, height: 20), first: 8)
        XCTAssertTrue(p.suppressesChrome())
    }

    func testChromeStaysSuppressedForTheGraceAfterRelease() {
        var p = pull(first: 0)
        _ = p.update(translation: CGSize(width: 0, height: 40), first: 19)
        let release = Date()
        p.ended(now: release)
        // Der Rückschnepper des Gummibands fällt in dieses Fenster.
        XCTAssertTrue(p.suppressesChrome(now: release.addingTimeInterval(0.1)))
        XCTAssertTrue(p.suppressesChrome(now: release.addingTimeInterval(SearchPull.chromeGrace - 0.01)))
        // Danach entscheidet das Chrom wieder normal.
        XCTAssertFalse(p.suppressesChrome(now: release.addingTimeInterval(SearchPull.chromeGrace + 0.01)))
    }

    func testMidListGestureDoesNotSuppressChrome() {
        // Titelzeile nicht sichtbar -> kein Kandidat -> das normale
        // Zusammenziehen beim Scrollen bleibt vollständig unberührt.
        var p = pull(first: nil)
        _ = p.update(translation: CGSize(width: 0, height: 80))
        XCTAssertFalse(p.suppressesChrome())
        p.ended()
        XCTAssertFalse(p.suppressesChrome(now: Date().addingTimeInterval(0.1)))
    }
}

/// Punkt 2: der Tafel-Inhalt wird EINMAL in voller Höhe gelayoutet und beim
/// Ziehen nur freigelegt — `contentBottomInset` ist die Zahl, die dabei die
/// Erreichbarkeit der letzten Zeile sichert.
final class MorePanelContentInsetTests: XCTestCase {

    private let container: CGFloat = 800
    private let safeBottom: CGFloat = 34
    private let bar = Theme.Metrics.control
    private let gap = Theme.Metrics.gap

    func testExpandedInsetIsExactlyTheBottomOverhang() {
        let inset = MorePanel.contentBottomInset(container: container,
                                                 safeBottom: safeBottom,
                                                 expanded: true, bar: bar, gap: gap)
        XCTAssertEqual(inset,
                       MorePanel.bottomOverhang(progress: 1, safeBottom: safeBottom,
                                                bar: bar, gap: gap),
                       accuracy: 0.001)
    }

    func testCollapsedInsetHidesExactlyTheClippedPart() {
        // Im kleinen Zustand liegt der Rest der vollen Höhe hinter der
        // Schnittkante — genau so viel muss die Liste früher enden.
        let inset = MorePanel.contentBottomInset(container: container,
                                                 safeBottom: safeBottom,
                                                 expanded: false, bar: bar, gap: gap)
        let expected = MorePanel.expandedHeight(container: container, safeBottom: safeBottom)
            - MorePanel.collapsedHeight(container: container)
        XCTAssertEqual(inset, expected, accuracy: 0.001)
    }

    func testInsetIsNeverNegativeOnShortContainers() {
        // Landscape/Slide-Over: volle Höhe = kleine Höhe (Deckel greift).
        let inset = MorePanel.contentBottomInset(container: 300, safeBottom: 0,
                                                 expanded: false, bar: bar, gap: gap)
        XCTAssertGreaterThanOrEqual(inset, 0)
    }

    func testVisibleContentHeightMatchesTheOldLayoutInBothRestingStates() {
        // Sichtbare Inhaltshöhe = Fensterhöhe − Innenabstand + Überstand.
        // Sie muss in BEIDEN Ruhelagen dieselbe sein wie beim alten Layout
        // (Fenster = Inhaltshöhe, Innenabstand = Überstand): identische
        // Ruhe-Optik war die Zusage.
        let small = MorePanel.collapsedHeight(container: container)
        let large = MorePanel.expandedHeight(container: container, safeBottom: safeBottom)
        for expanded in [false, true] {
            let window = expanded ? large : small
            let inset = MorePanel.contentBottomInset(container: container,
                                                     safeBottom: safeBottom,
                                                     expanded: expanded, bar: bar, gap: gap)
            let overhang = MorePanel.bottomOverhang(progress: expanded ? 1 : 0,
                                                    safeBottom: safeBottom,
                                                    bar: bar, gap: gap)
            // Inhalt steht auf voller Höhe `large`; nutzbar bis zur
            // Schnittkante minus Ziel-Überstand:
            let visibleNew = large - inset
            let visibleOld = window - overhang
            XCTAssertEqual(visibleNew, visibleOld, accuracy: 0.001,
                           "expanded=\(expanded)")
        }
    }
}
