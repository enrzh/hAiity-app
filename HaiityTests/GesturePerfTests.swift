import XCTest
import SwiftUI
import UIKit
@testable import Haiity

final class HabitCardInteractionSourceTests: XCTestCase {

    func testCardHeaderOffersExplicitEditWithoutAnEllipsisMenu() throws {
        let source = try habitCardSource()
        XCTAssertTrue(source.contains("private var editButton"))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"edit-habit\")"))
        XCTAssertFalse(source.contains("Image(systemName: \"ellipsis\")"))
    }

    /// Der Halten-Popup ist das SYSTEM-Kontextmenü (UIContextMenuInteraction
    /// — dieselbe Engine wie das Halten auf einem Link): SwiftUI-Langdruck
    /// und SwiftUI-contextMenu scheitern hier beide (Gesten feuern in der
    /// List-Zelle-mit-ScrollView-Verschachtelung nicht bzw. es gibt keinen
    /// Vorschau-Tipp). Jeder Karten-Wrapper besitzt deshalb seine eigene
    /// Interaktion und bleibt aus der gemeinsamen Listenzelle heraus.
    func testHeldGraphShowsTheSystemContextMenu() throws {
        let source = try habitCardSource()
        XCTAssertTrue(source.contains("UIContextMenuInteraction"))
        XCTAssertTrue(source.contains("GraphContextMenu"))
        XCTAssertTrue(source.contains("final class MenuHost: UIView, UIContextMenuInteractionDelegate"))
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

    /// Der Tipp AUF die Vorschau committet sofort zu Bearbeiten, während UIKit
    /// das Kontextmenü noch abbaut — dadurch fühlt sich der Editor direkt an.
    func testPreviewTapCommitsToEdit() throws {
        let source = try habitCardSource()
        XCTAssertTrue(source.contains("willPerformPreviewActionForMenuWith"))
        XCTAssertTrue(source.contains("animator.preferredCommitStyle = .dismiss"))
        XCTAssertTrue(source.contains("            commit()"),
                      "the editor request must be sent during the commit callback")
        XCTAssertFalse(source.contains("animator.addCompletion { commit() }"),
                       "the editor must not wait for the context-menu dismissal")
        XCTAssertTrue(source.contains("commit: onEdit"))
    }

    func testLongPressMenuKeepsEditAction() throws {
        let habitActions = try habitActionsSource()
        XCTAssertTrue(habitActions.contains("String(localized: \"Bearbeiten\")"))
        XCTAssertTrue(habitActions.contains("handler: onEdit"))
        XCTAssertTrue(habitActions.contains("String(localized: \"Nacharbeiten\")"))
        XCTAssertTrue(habitActions.contains("String(localized: \"Archivieren\")"))
        XCTAssertTrue(habitActions.contains("String(localized: \"Als Bild teilen\")"))
        XCTAssertTrue(habitActions.contains("String(localized: \"Rückgängig\")"))
        XCTAssertTrue(habitActions.contains("handler: onClear"))
        XCTAssertTrue(habitActions.contains("String(localized: \"Löschen\")"))
        XCTAssertTrue(habitActions.contains("destructive: true"))
    }

    func testHabitGraphsHaveNoDirectCellSelectionPath() throws {
        let card = try habitCardSource()
        let content = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Views/ContentView.swift"))
        let grid = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Views/ContributionGrid.swift"))

        XCTAssertFalse(card.contains("onSelectDay"))
        XCTAssertFalse(content.contains("onSelectDay:"))
        XCTAssertFalse(grid.contains("GridTap"))
    }

    func testStatsContextMenuFillsTheStatsTileFrame() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Views/StatsView.swift"))

        XCTAssertTrue(source.contains(".frame(maxWidth: statsPreviewWidth)"),
                      "the UIKit preview host must use a finite width")
    }

    func testStatsContextMenuUsesAHeightForEachCardShape() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Views/StatsView.swift"))

        XCTAssertTrue(source.contains("private func statsContextMenu(id: String,"),
                      "context menus need a dedicated stats preview helper")
        XCTAssertTrue(source.contains("preview: @escaping () -> AnyView,\n                                  height: CGFloat)"),
                      "context menus need an explicit height instead of one hero-sized constant")
        XCTAssertTrue(source.contains("statsHeroPreviewHeight"))
        XCTAssertTrue(source.contains("statsTilePreviewHeight"))
        XCTAssertTrue(source.contains("statsRowPreviewHeight"))
        XCTAssertTrue(source.contains("height: statsTilePreviewHeight"),
                      "small tiles must not inherit the hero preview height")
        XCTAssertTrue(source.contains("height: statsHeroPreviewHeight"))
        XCTAssertTrue(source.contains("height: statsRowPreviewHeight"))
    }

    func testContextMenuDoesNotUseTheSharedListCellAsItsInteractionView() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Views/HabitCard.swift"))

        XCTAssertTrue(source.contains("isUserInteractionEnabled = true"),
                      "the interaction must be installed on the card host")
        XCTAssertFalse(source.contains("UICollectionViewCell"),
                       "the interaction must not be installed on a shared collection cell")
        XCTAssertFalse(source.contains("UITableViewCell"),
                       "the interaction must not be installed on a shared table cell")
    }

    func testLongPressMenuDoesNotDuplicatePermanentCheckInActions() throws {
        let actions = try habitActionsSource()
        XCTAssertFalse(actions.contains("onMarkDone"))
        XCTAssertFalse(actions.contains("onAnswer"))
        XCTAssertEqual(actions.components(separatedBy: "handler: onClear").count - 1, 1)
    }

    @MainActor
    func testStatusControlsUseTheHabitPaletteForPositiveAndNegativeStates() throws {
        XCTAssertTrue(try habitCardSource().contains("HabitActionControls("),
                      "The collection must render the shared action controls")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = "2026-10-10"
        let now = try XCTUnwrap(DayKey.date(from: day, calendar: calendar))
        let palettes = PaletteBook(global: .rose)

        for scheme in [ColorScheme.light, .dark] {
            for (kind, value) in [(HabitKind.checkbox, 1), (.quantity, 3),
                                  (.yesNo, Habit.Answer.yes), (.yesNo, Habit.Answer.no)] {
                var habit = Habit(name: "Read", recurrence: Recurrence(target: kind == .quantity ? 3 : nil),
                                  kind: kind)
                habit.palette = .blue
                habit.log[day] = value
                let style = palettes.style(for: habit)
                let dark = scheme == .dark
                let negative = kind == .yesNo && value == Habit.Answer.no
                let fill = kind != .yesNo ? (dark ? style.accentTextDark : style.accentTextLight)
                    : negative ? style.negative(dark: dark) : (dark ? style.accentFillDark : style.accentFillLight)
                let globalFill = kind != .yesNo
                    ? (dark ? palettes.style.accentTextDark : palettes.style.accentTextLight)
                    : negative ? palettes.style.negative(dark: dark)
                    : (dark ? palettes.style.accentFillDark : palettes.style.accentFillLight)
                XCTAssertNotEqual(fill, globalFill, "The fixture must distinguish the item's palette from the app tint")
                let content = HabitActionControls(habit: habit, calendar: calendar, now: now,
                    onToggleDay: { _ in }, onIncrement: {}, onAnswer: { _ in })
                    .environment(\.palettes, palettes)
                    .environment(\.colorScheme, scheme)
                    .environment(\.dynamicTypeSize, .large)
                    .frame(width: 240, height: 70)
                    .background(Color.white)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 1
                var image: UIImage?
                UITraitCollection(userInterfaceStyle: dark ? .dark : .light).performAsCurrent {
                    image = renderer.uiImage
                }
                let cg = try XCTUnwrap(image?.cgImage)
                var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
                pixels.withUnsafeMutableBytes { bytes in
                    let context = CGContext(data: bytes.baseAddress, width: cg.width, height: cg.height,
                        bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                }
                func matchingPixels(_ hex: UInt32) -> Int {
                    let rgb = [Int((hex >> 16) & 255), Int((hex >> 8) & 255), Int(hex & 255)]
                    return stride(from: 0, to: pixels.count, by: 4).filter { offset in
                        (0..<3).allSatisfy { abs(Int(pixels[offset + $0]) - rgb[$0]) <= 2 }
                    }.count
                }
                XCTAssertGreaterThan(matchingPixels(fill), kind == .yesNo ? 100 : 10,
                                     "The selected \(kind) control must paint the item's \(scheme) answer color")
                XCTAssertEqual(matchingPixels(globalFill), 0, "The app tint must not override the item's answer palette")
            }
        }
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
