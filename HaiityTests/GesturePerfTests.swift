import XCTest
@testable import Haiity

final class HabitCardInteractionSourceTests: XCTestCase {

    func testCardHeaderHasNoEllipsisEditButton() throws {
        let source = try habitCardSource()
        XCTAssertFalse(source.contains("private var editButton"))
        XCTAssertFalse(source.contains("Image(systemName: \"ellipsis\")"))
    }

    /// Der Halten-Popup ist das SYSTEM-Kontextmenü (UIContextMenuInteraction
    /// — dieselbe Engine wie das Halten auf einem Link): SwiftUI-Langdruck
    /// und SwiftUI-contextMenu scheitern hier beide (Gesten feuern in der
    /// List-Zelle-mit-ScrollView-Verschachtelung nicht bzw. es gibt keinen
    /// Vorschau-Tipp). Die Interaktion hängt an der ZELLE — der eigene
    /// Wrapper ist nur ein Geschwister des Karteninhalts und sieht keine
    /// Berührungen (nachgemessen).
    func testHeldGraphShowsTheSystemContextMenu() throws {
        let source = try habitCardSource()
        XCTAssertTrue(source.contains("UIContextMenuInteraction"))
        XCTAssertTrue(source.contains("GraphContextMenu"))
        XCTAssertTrue(source.contains("if view is UICollectionViewCell || view is UITableViewCell"))
        // Angehoben wird NUR die Karte (visiblePath), nicht die ganze Zeile.
        XCTAssertTrue(source.contains("visiblePath"))
        XCTAssertTrue(source.contains("habitPreview"))
        // Die kaputten Bauarten bleiben draußen (Aufrufformen, keine
        // Kommentare: die dürfen `.contextMenu(preview:)` weiter erklären).
        XCTAssertFalse(source.contains(".onLongPressGesture(minimumDuration"))
        XCTAssertFalse(source.contains(".contextMenu {"))
        XCTAssertFalse(source.contains(".contextMenu(menuItems"))
        XCTAssertFalse(source.contains("showingGraphPreview"))
    }

    /// Der Tipp AUF die Vorschau committet zu Bearbeiten — wie das Öffnen
    /// eines gehaltenen Links; gehandelt wird erst NACH der Abbau-Animation.
    func testPreviewTapCommitsToEdit() throws {
        let source = try habitCardSource()
        XCTAssertTrue(source.contains("willPerformPreviewActionForMenuWith"))
        XCTAssertTrue(source.contains("animator.addCompletion { commit() }"))
        XCTAssertTrue(source.contains("commit: onEdit"))
    }

    func testLongPressMenuKeepsEditAction() throws {
        let habitActions = try habitActionsSource()
        XCTAssertTrue(habitActions.contains("String(localized: \"Bearbeiten\")"))
        XCTAssertTrue(habitActions.contains("handler: onEdit"))
        XCTAssertTrue(habitActions.contains("String(localized: \"Nacharbeiten\")"))
        XCTAssertTrue(habitActions.contains("String(localized: \"Archivieren\")"))
        XCTAssertTrue(habitActions.contains("String(localized: \"Als Bild teilen\")"))
    }

    func testLongPressMenuDoesNotDuplicatePermanentCheckInActions() throws {
        let actions = try habitActionsSource()
        XCTAssertFalse(actions.contains("onMarkDone"))
        XCTAssertFalse(actions.contains("onAnswer"))
        XCTAssertFalse(actions.contains("onClear"))
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
        let startMarker = "private var menuActions: [GraphMenuAction] {"
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
