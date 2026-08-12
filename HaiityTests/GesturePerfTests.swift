import XCTest
@testable import Haiity

final class HabitCardInteractionSourceTests: XCTestCase {

    func testCardHeaderHasNoEllipsisEditButton() throws {
        let source = try habitCardSource()
        XCTAssertFalse(source.contains("private var editButton"))
        XCTAssertFalse(source.contains("Image(systemName: \"ellipsis\")"))
    }

    func testLongPressMenuKeepsEditAction() throws {
        let habitActions = try habitActionsSource()
        XCTAssertTrue(habitActions.contains("Button(action: onEdit)"))
        XCTAssertTrue(habitActions.contains("Label(String(localized: \"Bearbeiten\"), systemImage: \"pencil\")"))
        XCTAssertTrue(habitActions.contains(".accessibilityIdentifier(\"edit-habit\")"))
    }

    private func habitCardSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Haiity/Views/HabitCard.swift")
        return try String(contentsOf: url)
    }

    private func habitActionsSource() throws -> String {
        let source = try habitCardSource()
        let startMarker = "private var habitActions: some View {"
        let endMarker = "    // MARK: – Kopf auf nacktem Grund"
        guard let start = source.range(of: startMarker),
              let end = source.range(of: endMarker, range: start.upperBound..<source.endIndex) else {
            XCTFail("Could not locate habitActions block in HabitCard.swift")
            return ""
        }
        return String(source[start.lowerBound..<end.lowerBound])
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
