import XCTest
@testable import Haiity

/// Die Geometrie der schwebenden Leiste. Beide Rechnungen hier sind der
/// Grund, warum sich der Anlegen-Knopf jetzt BEWEGT statt zu blenden und
/// warum die Auswahl-Lasur einem Finger folgen kann — in der Ansicht wären
/// sie nicht prüfbar.
final class ChromeLayoutTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relative))
    }

    func testNativeShellOwnsBottomChromeAndFallbackOwnsLegacyChrome() throws {
        let content = try source("Haiity/Views/ContentView.swift")

        XCTAssertEqual(content.components(separatedBy: ".overlay(alignment: .bottom) { legacyBottomChrome }").count,
                       2,
                       "legacy chrome must have exactly one owner")
        XCTAssertTrue(content.contains("if #unavailable(iOS 26), !searching"),
                      "legacy chrome must remain an older-system fallback")
        XCTAssertTrue(content.contains("TabView(selection: $nativeTab)"),
                      "iOS 26 must keep one native TabView owner")
    }

    func testNativeToastClearanceUsesChromeLayoutContract() throws {
        XCTAssertEqual(ChromeLayout.toastBottomPadding(nativeBar: true, searching: false),
                       ChromeLayout.nativeTabBarClearance)
        XCTAssertEqual(ChromeLayout.toastBottomPadding(nativeBar: false, searching: false), 0)
        XCTAssertEqual(ChromeLayout.toastBottomPadding(nativeBar: true, searching: true), 0)
    }

    func testNativeOwnerAssertionTargetsTheFallbackBranchOnly() throws {
        let content = try source("Haiity/Views/ContentView.swift")
        let fallback = try XCTUnwrap(content.range(of: "private var shell: some View"))
        let native = try XCTUnwrap(content.range(of: "private var nativeShell: some View"))
        let nativeEnd = try XCTUnwrap(content.range(of: "private func nativeTabRoot"))
        let fallbackSource = String(content[fallback.lowerBound..<native.lowerBound])
        let nativeSource = String(content[native.lowerBound..<nativeEnd.lowerBound])
        XCTAssertEqual(fallbackSource.components(separatedBy: "legacyBottomChrome").count, 2)
        XCTAssertFalse(nativeSource.contains("legacyBottomChrome"))
        XCTAssertTrue(nativeSource.contains("TabView(selection: $nativeTab)"))
    }

    func testSortingModeKeepsNativeListScrolling() throws {
        let content = try source("Haiity/Views/ContentView.swift")

        XCTAssertFalse(content.contains("SortingAutoScrollModifier"),
                       "a list-wide drag observer steals ordinary scrolling in sorting mode")
        XCTAssertFalse(content.contains("sortingAutoScrollTask"))
        XCTAssertFalse(content.contains("simultaneousGesture("))
        XCTAssertTrue(content.contains(".onMove("),
                      "native list reorder already auto-scrolls while dragging a handle")
        XCTAssertTrue(content.contains("editMode == .active"))
        XCTAssertTrue(content.contains("placement: .confirmationAction"))
        XCTAssertTrue(content.contains("accessibilityIdentifier(\"finish-reordering\")"))
    }

    // MARK: – Wohin der Anlegen-Knopf fährt

    func testFallbackSelectorContainsTwoMinimumHitTargets() {
        // 2 Lasuren à 44 + der Spalt dazwischen + Rand links und rechts.
        XCTAssertEqual(ChromeLayout.inset, 4, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(ChromeLayout.navigationWidth,
                                    2 * Theme.Metrics.hit + 3 * ChromeLayout.inset)
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
        XCTAssertEqual(x, ChromeLayout.navigationWidth - Theme.Metrics.gap, accuracy: 0.001)
        XCTAssertLessThan(x, ChromeLayout.navigationWidth)
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

/// Die Mehr-Tafel: Karte oder ganze Seite, ein Zug, drei mögliche Ausgänge.
/// In der Ansicht wäre das eine Sache fürs Auge; hier steht, ab wann sie
/// aufklappt, wie weit sie geht, was dabei mitläuft und wann sie zu ist.
final class MorePanelTests: XCTestCase {
    /// Nutzhöhe (sichere Fläche) eines iPhone 17 Pro Max.
    private let tall: CGFloat = 860
    /// Untere Sicherheitszone desselben Geräts.
    private let safeBottom: CGFloat = 34
    /// Ein niedriger Container — dort greift der Deckel nicht.
    private let short: CGFloat = 600

    // MARK: – Die zwei Größen

    func testTheSmallHeightIsCapped() {
        // 0,58 × 860 = 499 -> unter dem Deckel; 0,58 × 1000 = 580 -> gedeckelt.
        XCTAssertEqual(MorePanel.collapsedHeight(container: tall),
                       tall * MorePanel.ratio, accuracy: 0.001)
        XCTAssertEqual(MorePanel.collapsedHeight(container: 1000), MorePanel.cap, accuracy: 0.001)
    }

    /// Groß heißt jetzt GANZE SEITE: von der oberen Sicherheitszone bis an
    /// die Bildschirmunterkante. Genau deshalb steht die untere
    /// Sicherheitszone in der Rechnung — ohne sie endete die Fläche über dem
    /// Home-Indikator und ließe dort einen Streifen stehen.
    func testTheBigHeightIsTheWholePage() {
        let big = MorePanel.expandedHeight(container: tall, safeBottom: safeBottom)
        XCTAssertEqual(big, tall + safeBottom, accuracy: 0.001)
        XCTAssertGreaterThan(big, tall)
        XCTAssertGreaterThan(big, MorePanel.collapsedHeight(container: tall))
    }

    /// Auf einem niedrigen Container liegt der Deckel des kleinen Zustands
    /// unter der großen Höhe — die Tafel darf beim Aufziehen nicht
    /// schrumpfen.
    func testTheBigHeightIsNeverSmallerThanTheSmallOne() {
        for h in stride(from: 200.0, through: 1200.0, by: 100.0) {
            let container = CGFloat(h)
            XCTAssertGreaterThanOrEqual(
                MorePanel.expandedHeight(container: container, safeBottom: 0),
                MorePanel.collapsedHeight(container: container))
        }
    }

    // MARK: – Während des Zuges

    func testPullingUpGrows() {
        let small = MorePanel.collapsedHeight(container: tall)
        let h = MorePanel.height(container: tall, safeBottom: safeBottom,
                                 expanded: false, drag: -100)
        XCTAssertEqual(h, small + 100, accuracy: 0.001)
    }

    /// Die obere Sicherheitszone ist eine harte Decke, keine, an der man
    /// federt: alles darüber läge unter Statusleiste und Dynamic Island.
    func testGrowthStopsAtTheWholePage() {
        let big = MorePanel.expandedHeight(container: tall, safeBottom: safeBottom)
        for drag in [-100.0, -300.0, -5000.0] {
            let h = MorePanel.height(container: tall, safeBottom: safeBottom,
                                     expanded: true, drag: CGFloat(drag))
            XCTAssertEqual(h, big, accuracy: 0.001)
        }
        // Auch aus dem kleinen Zustand heraus in EINEM Zug nicht weiter.
        XCTAssertEqual(MorePanel.height(container: tall, safeBottom: safeBottom,
                                        expanded: false, drag: -5000),
                       big, accuracy: 0.001)
    }

    func testPullingDownFromSmallMovesInsteadOfShrinking() {
        let small = MorePanel.collapsedHeight(container: tall)
        XCTAssertEqual(MorePanel.height(container: tall, safeBottom: safeBottom,
                                        expanded: false, drag: 80),
                       small, accuracy: 0.001)
        XCTAssertEqual(MorePanel.offset(container: tall, safeBottom: safeBottom,
                                        expanded: false, drag: 80), 80, accuracy: 0.001)
    }

    /// Aus dem großen Zustand schrumpft der Zug die Tafel bis auf die
    /// Kartenhöhe — und geht dort WEITER als Versatz. Genau der Halt an der
    /// Karte war die Rückmeldung („it stops … and then continues"): der
    /// Finger lief, die Tafel stand.
    func testPullingDownFromBigShrinksToTheSmallHeightThenTravelsOn() {
        let small = MorePanel.collapsedHeight(container: tall)
        let big = MorePanel.expandedHeight(container: tall, safeBottom: safeBottom)
        let travel = big - small
        XCTAssertEqual(MorePanel.shrinkTravel(container: tall, safeBottom: safeBottom),
                       travel, accuracy: 0.001)
        XCTAssertEqual(MorePanel.height(container: tall, safeBottom: safeBottom,
                                        expanded: true, drag: 100),
                       big - 100, accuracy: 0.001)
        XCTAssertEqual(MorePanel.height(container: tall, safeBottom: safeBottom,
                                        expanded: true, drag: 5000),
                       small, accuracy: 0.001)
        // Solange die Höhe noch schrumpft, wandert nichts: zu jedem
        // Zeitpunkt bewegt sich genau EINE Größe.
        XCTAssertEqual(MorePanel.offset(container: tall, safeBottom: safeBottom,
                                        expanded: true, drag: 100), 0, accuracy: 0.001)
        XCTAssertEqual(MorePanel.offset(container: tall, safeBottom: safeBottom,
                                        expanded: true, drag: travel), 0, accuracy: 0.001)
        // Hinter der Karte übernimmt der Versatz — Punkt für Punkt.
        XCTAssertEqual(MorePanel.offset(container: tall, safeBottom: safeBottom,
                                        expanded: true, drag: travel + 60),
                       60, accuracy: 0.001)
    }

    /// **Kein Halt an der Karte.** Die sichtbare Oberkante der Tafel
    /// (Höhe minus Versatz) folgt einem Zug vom ganzen Bild bis hinaus
    /// STETIG und ohne Plateau: kein Punktepaar, zwischen dem sie stehen
    /// bliebe, kein Sprung an der Übergabe von Höhe an Versatz.
    func testASlowDragFromFullPassesThroughTheCardWithoutStopping() {
        let big = MorePanel.expandedHeight(container: tall, safeBottom: safeBottom)
        var lastTop = big
        for step in 1...300 {
            let drag = CGFloat(step) * 2          // 0…600, quer über die Karte
            let h = MorePanel.height(container: tall, safeBottom: safeBottom,
                                     expanded: true, drag: drag)
            let off = MorePanel.offset(container: tall, safeBottom: safeBottom,
                                       expanded: true, drag: drag)
            let top = h - off
            // Streng monoton: 2 pt Finger heißen 2 pt Tafel — überall.
            XCTAssertEqual(top, lastTop - 2, accuracy: 0.001,
                           "Tafel hält an oder springt bei Zug \(drag)")
            lastTop = top
        }
    }

    func testAnUntouchedPanelKeepsItsHeight() {
        XCTAssertEqual(MorePanel.height(container: short, safeBottom: 0,
                                        expanded: false, drag: 0),
                       MorePanel.collapsedHeight(container: short), accuracy: 0.001)
        XCTAssertEqual(MorePanel.height(container: short, safeBottom: 0,
                                        expanded: true, drag: 0),
                       MorePanel.expandedHeight(container: short, safeBottom: 0),
                       accuracy: 0.001)
        XCTAssertEqual(MorePanel.offset(container: short, safeBottom: 0,
                                        expanded: false, drag: 0), 0, accuracy: 0.001)
    }

    // MARK: – Was mit der Größe mitläuft

    /// EIN Fortschritt für alles. Er ist 0 auf der Karte, 1 auf der ganzen
    /// Seite und dazwischen streng monoton — sonst liefen Radius und Ränder
    /// der Höhe hinterher oder voraus.
    func testProgressRunsFromCardToWholePageAndIsMonotonic() {
        XCTAssertEqual(MorePanel.progress(container: tall, safeBottom: safeBottom,
                                          expanded: false, drag: 0), 0, accuracy: 0.001)
        XCTAssertEqual(MorePanel.progress(container: tall, safeBottom: safeBottom,
                                          expanded: true, drag: 0), 1, accuracy: 0.001)
        var last: CGFloat = -1
        for drag in stride(from: 0.0, through: -400.0, by: -20.0) {
            let p = MorePanel.progress(container: tall, safeBottom: safeBottom,
                                       expanded: false, drag: CGFloat(drag))
            XCTAssertGreaterThanOrEqual(p, last)
            XCTAssertGreaterThanOrEqual(p, 0)
            XCTAssertLessThanOrEqual(p, 1)
            last = p
        }
        XCTAssertEqual(last, 1, accuracy: 0.001)
    }

    /// Eine bildschirmfüllende Fläche mit Kartenecken sieht aus wie ein
    /// Fehler — der Radius läuft deshalb mit.
    func testCornerRadiusInterpolatesFromCardToScreen() {
        let screen = MorePanel.screenCornerRadius(safeBottom: safeBottom)
        XCTAssertGreaterThan(screen, MorePanel.cardRadius)
        XCTAssertEqual(MorePanel.cornerRadius(progress: 0, safeBottom: safeBottom),
                       MorePanel.cardRadius, accuracy: 0.001)
        XCTAssertEqual(MorePanel.cornerRadius(progress: 1, safeBottom: safeBottom),
                       screen, accuracy: 0.001)
        XCTAssertEqual(MorePanel.cornerRadius(progress: 0.5, safeBottom: safeBottom),
                       (MorePanel.cardRadius + screen) / 2, accuracy: 0.001)
        // Ausserhalb von 0…1 wird geklemmt, nicht extrapoliert.
        XCTAssertEqual(MorePanel.cornerRadius(progress: 2, safeBottom: safeBottom),
                       screen, accuracy: 0.001)
        XCTAssertEqual(MorePanel.cornerRadius(progress: -1, safeBottom: safeBottom),
                       MorePanel.cardRadius, accuracy: 0.001)
    }

    /// Ein Gerät mit rechteckigem Bildschirm (SE) hat keine Bildschirmecke,
    /// auf die man zulaufen könnte — dort bleibt es beim Kartenradius.
    func testASquareScreenKeepsTheCardRadius() {
        XCTAssertEqual(MorePanel.screenCornerRadius(safeBottom: 0), MorePanel.cardRadius)
        XCTAssertEqual(MorePanel.cornerRadius(progress: 1, safeBottom: 0),
                       MorePanel.cardRadius, accuracy: 0.001)
    }

    /// Die Seitenränder schließen sich stetig bis auf 0 — kein Sprung an der
    /// Kante.
    func testSideOverhangClosesTheMarginsContinuously() {
        let gutter = Theme.Metrics.gutter
        XCTAssertEqual(MorePanel.sideOverhang(progress: 0, gutter: gutter), 0, accuracy: 0.001)
        XCTAssertEqual(MorePanel.sideOverhang(progress: 1, gutter: gutter),
                       gutter, accuracy: 0.001)
        XCTAssertEqual(MorePanel.sideOverhang(progress: 0.25, gutter: gutter),
                       gutter / 4, accuracy: 0.001)
        XCTAssertEqual(MorePanel.sideOverhang(progress: 9, gutter: gutter),
                       gutter, accuracy: 0.001)
    }

    /// **Die Fläche wächst, der Inhalt nicht.**
    ///
    /// Die Tafel legt den Überstand zweimal an: einmal als Rand NACH INNEN
    /// (der Inhalt behält seine Breite) und einmal als negativen Rand nach
    /// aussen (die Glasfläche geht bis an die Bildschirmkante). Beide müssen
    /// in JEDEM Zwischenschritt derselbe Wert sein — sonst setzt die Liste
    /// beim Aufziehen ihre Zeilen neu, und genau das sah „buggy" aus.
    func testTheContentKeepsItsWidthAtEveryStep() {
        let gutter = Theme.Metrics.gutter
        let box: CGFloat = 408          // Bildschirm 440 minus beide Ränder
        for step in 0...20 {
            let progress = CGFloat(step) / 20
            let side = MorePanel.sideOverhang(progress: progress, gutter: gutter)
            // So breit ist die Fläche …
            let surface = box + 2 * side
            // … und so breit der Inhalt darin.
            XCTAssertEqual(surface - 2 * side, box, accuracy: 0.001,
                           "Inhaltsbreite wandert bei Fortschritt \(progress)")
        }
        // An den Enden stimmen die beiden Ruhelagen: Karte im Seitenrand,
        // ganze Seite von Kante zu Kante.
        XCTAssertEqual(box + 2 * MorePanel.sideOverhang(progress: 0, gutter: gutter), box)
        XCTAssertEqual(box + 2 * MorePanel.sideOverhang(progress: 1, gutter: gutter),
                       box + 2 * gutter)
    }

    /// Nach unten reicht die volle Größe über die Leiste hinweg bis an die
    /// Bildschirmkante: Leiste + beide Abstände + untere Sicherheitszone.
    func testBottomOverhangReachesTheScreenEdge() {
        let bar = Theme.Metrics.control, gap = Theme.Metrics.gap
        XCTAssertEqual(MorePanel.bottomOverhang(progress: 0, safeBottom: safeBottom,
                                                bar: bar, gap: gap), 0, accuracy: 0.001)
        XCTAssertEqual(MorePanel.bottomOverhang(progress: 1, safeBottom: safeBottom,
                                                bar: bar, gap: gap),
                       safeBottom + bar + 2 * gap, accuracy: 0.001)
        XCTAssertEqual(MorePanel.bottomOverhang(progress: 0.5, safeBottom: safeBottom,
                                                bar: bar, gap: gap),
                       (safeBottom + bar + 2 * gap) / 2, accuracy: 0.001)
    }

    /// Die Probe aufs Exempel: bei voller Größe steht die SICHTBARE Oberkante
    /// der Tafel genau auf der oberen Sicherheitszone und ihre Unterkante
    /// genau auf der Bildschirmkante. Beides fällt aus Höhe minus Überstand,
    /// und beides war der Grund für die Rechnung.
    func testAtFullSizeThePanelSpansSafeTopToScreenBottom() {
        let bar = Theme.Metrics.control, gap = Theme.Metrics.gap
        let h = MorePanel.height(container: tall, safeBottom: safeBottom,
                                 expanded: true, drag: 0)
        let over = MorePanel.bottomOverhang(progress: 1, safeBottom: safeBottom,
                                            bar: bar, gap: gap)
        // Unterkante des Kastens, von der Bildschirmunterkante aus gemessen.
        let boxBottomFromScreenBottom = safeBottom + gap + bar + gap
        XCTAssertEqual(over, boxBottomFromScreenBottom, accuracy: 0.001)
        // Sichtbare Oberkante, von der Bildschirmunterkante aus gemessen.
        let visibleTop = boxBottomFromScreenBottom + (h - over)
        XCTAssertEqual(visibleTop, safeBottom + tall, accuracy: 0.001)
    }

    // MARK: – Was die LEISTE dabei macht
    //
    // Die Leiste wird NACH der Tafel gezeichnet und liegt auf deren unterem
    // Überstand. Auf der Karte ist das richtig; auf der ganzen Seite stünden
    // Umschalter und Anlegen-Knopf mitten in einer bildschirmfüllenden
    // Fläche. Alles hier hängt am SELBEN `progress` wie Höhe, Radius und
    // Überstand — geprüft wird genau das: eine Quelle, drei Wirkungen, keine
    // Sprünge.

    func testTheBarStandsWhileThePanelIsStillACard() {
        XCTAssertEqual(MorePanel.chromeOpacity(progress: 0), 1, accuracy: 0.001)
        XCTAssertEqual(MorePanel.chromeWithdrawal(progress: 0), 0, accuracy: 0.001)
        XCTAssertEqual(MorePanel.chromeOffset(progress: 0, bar: Theme.Metrics.control,
                                              gap: Theme.Metrics.gap, safeBottom: safeBottom),
                       0, accuracy: 0.001)
        // Bis zur Haltegrenze passiert GAR nichts — eine Tafel, die noch wie
        // eine Karte aussieht, hat ihre Leiste.
        XCTAssertEqual(MorePanel.chromeOpacity(progress: MorePanel.chromeHold), 1, accuracy: 0.001)
        XCTAssertEqual(MorePanel.chromeOpacity(progress: MorePanel.chromeHold / 2), 1, accuracy: 0.001)
    }

    /// Der Kern der Rückmeldung: auf der ganzen Seite schwebt nichts mehr
    /// darüber. Weder sichtbar noch — das ist der eigentliche Fehler —
    /// unsichtbar treffbar.
    func testAtFullPageTheBarIsGoneAndUntouchable() {
        XCTAssertEqual(MorePanel.chromeOpacity(progress: 1), 0, accuracy: 0.001)
        XCTAssertFalse(MorePanel.chromeInteractive(progress: 1))
        // Und sie steht dann unter der Bildschirmkante: Leiste + ihr Abstand
        // nach unten + die untere Sicherheitszone.
        let bar = Theme.Metrics.control, gap = Theme.Metrics.gap
        XCTAssertEqual(MorePanel.chromeOffset(progress: 1, bar: bar, gap: gap,
                                              safeBottom: safeBottom),
                       bar + gap + safeBottom, accuracy: 0.001)
    }

    /// Sie ist schon VOR dem Ende weg: die letzten Prozent der Fahrt sollen
    /// eine leere Fläche zeigen, nicht einen Knopf, der noch eben verglüht.
    func testTheBarIsAlreadyGoneBeforeTheVeryEnd() {
        XCTAssertEqual(MorePanel.chromeOpacity(progress: MorePanel.chromeGone), 0, accuracy: 0.001)
        XCTAssertLessThan(MorePanel.chromeGone, 1)
        XCTAssertGreaterThan(MorePanel.chromeGone, MorePanel.chromeHold)
    }

    /// EIN Fortschritt, drei Wirkungen — und keine davon springt. Genau das
    /// unterscheidet „am selben Wert" von „mit einer zweiten Animation
    /// hinterher": ein Sprung wäre eine eigene Bewegung.
    func testWithdrawalIsMonotonicAndContinuous() {
        let bar = Theme.Metrics.control, gap = Theme.Metrics.gap
        var lastOpacity = MorePanel.chromeOpacity(progress: 0)
        var lastOffset = MorePanel.chromeOffset(progress: 0, bar: bar, gap: gap,
                                                safeBottom: safeBottom)
        for step in 1...200 {
            let p = CGFloat(step) / 200
            let opacity = MorePanel.chromeOpacity(progress: p)
            let offset = MorePanel.chromeOffset(progress: p, bar: bar, gap: gap,
                                                safeBottom: safeBottom)
            XCTAssertLessThanOrEqual(opacity, lastOpacity + 0.0001, "Deckkraft steigt bei \(p)")
            XCTAssertGreaterThanOrEqual(offset, lastOffset - 0.0001, "Versatz fällt bei \(p)")
            XCTAssertGreaterThanOrEqual(opacity, 0)
            XCTAssertLessThanOrEqual(opacity, 1)
            // Keine Kante: über einen halben Prozentpunkt Fortschritt darf
            // sich weder Deckkraft noch Versatz sprunghaft ändern. Ein Sprung
            // wäre der sichtbare Beweis für eine zweite Bewegung.
            XCTAssertLessThan(lastOpacity - opacity, 0.05, "Deckkraft springt bei \(p)")
            XCTAssertLessThan(offset - lastOffset, 5, "Versatz springt bei \(p)")
            lastOpacity = opacity
            lastOffset = offset
        }
    }

    /// Ausserhalb von 0…1 wird geklemmt, nicht extrapoliert — genau wie beim
    /// Radius und den Rändern. Ein Wert von 1,2 (Federüberschwinger) darf
    /// keine negative Deckkraft ergeben.
    func testWithdrawalClampsOutsideTheRange() {
        XCTAssertEqual(MorePanel.chromeOpacity(progress: -3), 1, accuracy: 0.001)
        XCTAssertEqual(MorePanel.chromeOpacity(progress: 4), 0, accuracy: 0.001)
        XCTAssertEqual(MorePanel.chromeOffset(progress: -3, bar: 52, gap: 8, safeBottom: 34),
                       0, accuracy: 0.001)
        XCTAssertEqual(MorePanel.chromeOffset(progress: 4, bar: 52, gap: 8, safeBottom: 34),
                       94, accuracy: 0.001)
        XCTAssertTrue(MorePanel.chromeInteractive(progress: -3))
        XCTAssertFalse(MorePanel.chromeInteractive(progress: 4))
    }

    /// Ein Gerät ohne Home-Indikator hat keine untere Sicherheitszone — der
    /// Weg nach unten wird dadurch kürzer, aber nie negativ.
    func testOffsetNeverGoesBackwardsOnASquareScreen() {
        let travel = MorePanel.chromeOffset(progress: 1, bar: 52, gap: 8, safeBottom: 0)
        XCTAssertEqual(travel, 60, accuracy: 0.001)
        XCTAssertEqual(MorePanel.chromeOffset(progress: 1, bar: 52, gap: 8, safeBottom: -20),
                       60, accuracy: 0.001)
    }

    /// **Die Leiste bleibt bedienbar, solange sie zu sehen ist — und wird
    /// unbedienbar, bevor sie unsichtbar ist.**
    ///
    /// Der zweite Teil ist der wichtige: eine Ansicht mit `opacity(0)` ist in
    /// SwiftUI weiterhin treffbar. Ohne die eigene Zusage läge auf der ganzen
    /// Seite ein unsichtbarer Anlegen-Knopf über der Tafel.
    func testHitTestingStopsBeforeTheBarIsInvisible() {
        XCTAssertTrue(MorePanel.chromeInteractive(progress: 0))
        XCTAssertTrue(MorePanel.chromeInteractive(progress: MorePanel.chromeHold))
        for step in 0...200 {
            let p = CGFloat(step) / 200
            if MorePanel.chromeOpacity(progress: p) < 0.5 {
                XCTAssertFalse(MorePanel.chromeInteractive(progress: p),
                               "halb verblasst und trotzdem treffbar bei \(p)")
            }
            if MorePanel.chromeInteractive(progress: p) {
                XCTAssertGreaterThan(MorePanel.chromeOpacity(progress: p), 0.4,
                                     "treffbar, aber praktisch unsichtbar bei \(p)")
            }
        }
    }

    /// Die Probe auf die Rückmeldung selbst: aus einem Zug nach oben, der die
    /// Tafel auf die ganze Seite bringt, folgt eine Leiste, die WEG ist —
    /// gerechnet aus derselben Kette wie die Höhe, nicht aus einem zweiten
    /// Zustand.
    func testAPullToFullPageTakesTheBarWithIt() {
        func chrome(drag: CGFloat, expanded: Bool) -> (Double, Bool) {
            let p = MorePanel.progress(container: tall, safeBottom: safeBottom,
                                       expanded: expanded, drag: drag)
            return (MorePanel.chromeOpacity(progress: p), MorePanel.chromeInteractive(progress: p))
        }
        // Karte, unangetastet: die Leiste steht.
        XCTAssertEqual(chrome(drag: 0, expanded: false).0, 1, accuracy: 0.001)
        XCTAssertTrue(chrome(drag: 0, expanded: false).1)
        // Ein kurzer Zug nach oben: noch alles da.
        XCTAssertEqual(chrome(drag: -60, expanded: false).0, 1, accuracy: 0.001)
        // Ganz nach oben durchgezogen: weg.
        XCTAssertEqual(chrome(drag: -5000, expanded: false).0, 0, accuracy: 0.001)
        XCTAssertFalse(chrome(drag: -5000, expanded: false).1)
        // Eingerastet auf der ganzen Seite: immer noch weg.
        XCTAssertEqual(chrome(drag: 0, expanded: true).0, 0, accuracy: 0.001)
        XCTAssertFalse(chrome(drag: 0, expanded: true).1)
    }

    /// **Kein Steckenbleiben.** Aus der ganzen Seite führt der Zug nach unten
    /// zurück — und die Leiste kommt auf demselben Weg wieder. Das ist die
    /// rechnerische Seite der Zusage „man kommt immer zurück": schon auf
    /// halbem Weg nach unten ist sie wieder voll da und wieder bedienbar.
    func testDraggingBackDownBringsTheBarBack() {
        let big = MorePanel.expandedHeight(container: tall, safeBottom: safeBottom)
        let small = MorePanel.collapsedHeight(container: tall)
        var lastOpacity = 0.0
        for drag in stride(from: 0.0, through: big - small, by: 20.0) {
            let p = MorePanel.progress(container: tall, safeBottom: safeBottom,
                                       expanded: true, drag: CGFloat(drag))
            let opacity = MorePanel.chromeOpacity(progress: p)
            XCTAssertGreaterThanOrEqual(opacity, lastOpacity - 0.0001,
                                        "Leiste wird beim Herunterziehen blasser bei \(drag)")
            lastOpacity = opacity
        }
        // Ganz heruntergezogen ist sie zurück — voll sichtbar und treffbar.
        let backP = MorePanel.progress(container: tall, safeBottom: safeBottom,
                                       expanded: true, drag: 5000)
        XCTAssertEqual(backP, 0, accuracy: 0.001)
        XCTAssertEqual(MorePanel.chromeOpacity(progress: backP), 1, accuracy: 0.001)
        XCTAssertTrue(MorePanel.chromeInteractive(progress: backP))
    }

    // MARK: – Der Griff
    //
    // Er ist auf der ganzen Seite der EINZIGE Weg zurück. Deshalb steht seine
    // Sichtbarkeit hier als Zusage und nicht nur als Augenmaß.

    /// Im Dunkeln deutlich kräftiger als im Hellen — genau das war die
    /// Rückmeldung. Und in beiden Fällen noch ein Griff und kein Balken:
    /// unter voller Deckkraft.
    func testTheGrabberReadsInDarkAndStaysSubtleInLight() {
        let dark = MorePanel.grabberOpacity(dark: true)
        let light = MorePanel.grabberOpacity(dark: false)
        XCTAssertGreaterThan(dark, light)
        // Auf dunklem Glas braucht ein heller Strich mehr als die rund 0,3
        // der hierarchischen Stufen — mit denen war er „kaum zu sehen".
        XCTAssertGreaterThanOrEqual(dark, 0.5)
        // Im Hellen war nie etwas falsch: dort bleibt es in der Nähe des
        // alten Wertes, statt einen schwarzen Riegel hinzustellen.
        XCTAssertGreaterThanOrEqual(light, 0.3)
        XCTAssertLessThanOrEqual(light, 0.4)
        XCTAssertLessThan(dark, 1)
    }

    /// Er ist etwas breiter als die 36 pt der System-Blätter und bleibt
    /// trotzdem ein Strich — und er ist NICHT Teil des Rückzugs: was zurück
    /// führt, darf nicht mit verschwinden.
    func testTheGrabberIsAWideThinLine() {
        XCTAssertGreaterThanOrEqual(MorePanel.grabberWidth, 36)
        XCTAssertLessThanOrEqual(MorePanel.grabberHeight, 6)
        XCTAssertGreaterThan(MorePanel.grabberWidth, MorePanel.grabberHeight * 4)
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

    /// **EINMAL auflösen, drei Ruhelagen.** Aus dem großen Zustand zählt die
    /// Strecke AB der Karte (`travel`): wer davor loslässt, rastet auf der
    /// Karte ein — das ist dann das richtige Ergebnis, kein Zwischenhalt.
    /// Wer dahinter loslässt, ist draussen, ohne zweite Geste.
    func testReleasingFromBigResolvesOnceByPosition() {
        let travel = MorePanel.shrinkTravel(container: tall, safeBottom: safeBottom)
        // Kaum bewegt: zurück aufs ganze Bild.
        XCTAssertEqual(MorePanel.resolve(drag: 20, predicted: 20,
                                         expanded: true, travel: travel), .expand)
        // Mitten im Kartenband losgelassen: Karte.
        XCTAssertEqual(MorePanel.resolve(drag: 150, predicted: 150,
                                         expanded: true, travel: travel), .collapse)
        XCTAssertEqual(MorePanel.resolve(drag: travel, predicted: travel,
                                         expanded: true, travel: travel), .collapse)
        // Hinter der Karte plus Schwelle: zu — in EINEM Zug.
        XCTAssertEqual(MorePanel.resolve(drag: travel + MorePanel.dismissDistance + 1,
                                         predicted: travel + MorePanel.dismissDistance + 1,
                                         expanded: true, travel: travel), .dismiss)
    }

    /// Ein Wurf zählt als Strecke: ein kurzer, schneller Zug vom ganzen Bild
    /// schließt sofort — er muss nicht erst an der Karte vorbei.
    func testAFlickDownFromBigDismissesDirectly() {
        let travel = MorePanel.shrinkTravel(container: tall, safeBottom: safeBottom)
        XCTAssertEqual(MorePanel.resolve(drag: 120,
                                         predicted: travel + MorePanel.flickDistance + 200,
                                         expanded: true, travel: travel), .dismiss)
        // Ein gemächlicher Wurf, der nur bis ins Kartenband trüge: Karte.
        XCTAssertEqual(MorePanel.resolve(drag: 120, predicted: 260,
                                         expanded: true, travel: travel), .collapse)
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
