import Foundation
import SwiftUI
import XCTest
@testable import Haiity

final class GitHubWidgetTests: XCTestCase {
    func testThreeLargeWidgetsAreRegisteredAndOldOverviewIsNotInGallery() throws {
        let source = try source("HaiityWidget/HaiityWidget.swift")
        XCTAssertTrue(source.contains("HaiityLargeListWidget"))
        XCTAssertTrue(source.contains("HaiityLargeGridWidget"))
        XCTAssertTrue(source.contains("HaiityLargeFocusWidget"))
        XCTAssertEqual(source.components(separatedBy: ".supportedFamilies([.systemLarge])").count - 1, 3)
        XCTAssertFalse(source.contains("HaiityRosterWidget()"))
    }

    func testOldOverviewProviderStillReadsTheAutomaticEntryPath() throws {
        let source = try source("HaiityWidget/HaiityWidget.swift")
        let providerSource = try section(source, startingAt: "struct HaiityRosterProvider", endingAt: "// MARK: – Bundle")

        XCTAssertTrue(providerSource.contains("completion(context.isPreview ? .demo : WidgetData.entry())"))
        XCTAssertTrue(providerSource.contains("completion(WidgetData.timeline())"))
        XCTAssertFalse(source.contains("struct HaiityRosterWidget: Widget"))
    }

    func testLargeWidgetActionsBindTheCurrentItemAndNeverTheParentCollection() throws {
        for (name, text, marker, end) in [("roster", try source("HaiityWidget/RosterWidgetView.swift"), "private struct LargeWidgetItem", "\nstruct LargeListWidgetView"),
                                          ("grid", try source("HaiityWidget/WidgetGridViews.swift"), "private struct LargeGridItem", "\n/// Gemeinsame Rasterbausteine")]
        {
            let item = try section(text, startingAt: marker, endingAt: end)
            XCTAssertTrue(text.contains("habit: habit"))
            XCTAssertTrue(item.contains("HaiityWidgetLink.habit(habit.id)"), "\(name) item link is not current habit")
            XCTAssertFalse(text.contains("widgetURL(URL(string: \"haiity://habits\")"))
            for intent in ["CheckOffHabitIntent", "AnswerYesHabitIntent",
                           "AnswerNoHabitIntent", "ResetHabitIntent"] {
                XCTAssertTrue(item.contains("\(intent)(habit: habit)"),
                              "missing current-item binding for \(intent)")
            }
        }
    }

    func testLargeWidgetConfigurationIsReadOnlyAndHasNoHabitOrICloudPersistence() throws {
        let text = try section(try source("HaiityWidget/WidgetLogic.swift"), startingAt: "static func resolveLargeItems", endingAt: "\n    static ")
        XCTAssertFalse(text.contains("save"))
        XCTAssertFalse(text.contains("UserDefaults"))
        XCTAssertFalse(text.contains("NSUbiquitous"))
    }

    func testLargeRenderersKeepReminderGraphFreeAndUseAllActions() throws {
        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        let grid = try source("HaiityWidget/WidgetGridViews.swift")
        for text in [roster, grid] {
            XCTAssertTrue(text.contains("habit.isReminder"))
            XCTAssertTrue(text.contains("CheckOffHabitIntent"))
            XCTAssertTrue(text.contains("AnswerYesHabitIntent"))
            XCTAssertTrue(text.contains("AnswerNoHabitIntent"))
            XCTAssertTrue(text.contains("ResetHabitIntent"))
            XCTAssertTrue(text.contains("HaiityWidgetLink.habit"))
        }
    }

    func testLargeWidgetIntentsExposeExpectedOptionalSlots() throws {
        let source = try source("Haiity/Intents/LargeWidgetIntent.swift")
        XCTAssertTrue(source.contains("struct LargeWidgetListIntent: WidgetConfigurationIntent"))
        XCTAssertTrue(source.contains("struct LargeWidgetGridIntent: WidgetConfigurationIntent"))
        XCTAssertTrue(source.contains("struct LargeWidgetFocusIntent: WidgetConfigurationIntent"))
        XCTAssertEqual(source.components(separatedBy: "var slot").count - 1, 10)
        XCTAssertTrue(source.contains("var featured: HabitEntity?"))
        XCTAssertTrue(source.contains("var queue1: HabitEntity?"))
        XCTAssertTrue(source.contains("var queue2: HabitEntity?"))
        XCTAssertTrue(source.contains("var queue3: HabitEntity?"))
        XCTAssertFalse(source.contains("struct ReminderEntity"))
    }

    func testLargeWidgetIntentTitlesAreLocalizable() throws {
        let source = try source("Haiity/Intents/LargeWidgetIntent.swift")
        XCTAssertTrue(source.contains("LocalizedStringResource"))
        XCTAssertTrue(source.contains("Automatisch"))
        XCTAssertTrue(source.contains("Element 1"))
    }

    func testGraphWidgetSourceHasOnlyHabitAndGitHubCases() {
        XCTAssertEqual(GraphWidgetSource.allCases, [.habit, .github])
    }

    func testGraphPaletteQueryIncludesBuiltInsAndCustomPalettes() async throws {
        let custom = CustomPalette(name: "Petrol", base: 0x0F766E)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("graph-palettes-(UUID().uuidString).json")
        let data = HabitData(version: HabitData.currentVersion,
                             updatedAt: 1,
                             summaryMinutes: nil,
                             habits: [],
                             customPalettes: [custom])
        try JSONEncoder().encode(data).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let items = try await GraphPaletteEntityQuery(dataURL: url).suggestedEntities()

        XCTAssertEqual(items.count, GraphPalette.allCases.count + 1)
        XCTAssertTrue(items.contains { $0.id == PaletteRef.custom(custom.id).rawValue })
        XCTAssertTrue(items.contains { $0.id == GraphPalette.green.rawValue })
    }

    func testDeletedCustomPaletteFallsBackThroughPaletteRef() {
        let id = UUID()
        let entity = GraphPaletteEntity(ref: .custom(id), name: "Petrol")

        XCTAssertEqual(entity.paletteRef, .custom(id))
        XCTAssertNil(entity.paletteRef.style(customs: []))
    }

    func testSharedSnapshotRoundTripsWithoutCredentials() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = root.appendingPathComponent("github-contributions.json")
        let snapshot = GitHubContributionSnapshot(
            username: "enrzh",
            days: [GitHubContributionDay(date: "2026-08-17", count: 3, level: 2)],
            fetchedAt: Date(timeIntervalSince1970: 0))

        try GitHubContributionSnapshot.saveShared(snapshot, to: url)
        XCTAssertEqual(GitHubContributionSnapshot.loadShared(from: url), snapshot)
        let text = try String(contentsOf: url)
        XCTAssertFalse(text.contains("access_token"))
        XCTAssertFalse(text.contains("device_code"))
    }

    func testGitHubGraphEntryDoesNotResolveAHabit() {
        let entry = HaiityEntry(date: .now,
                                habits: [],
                                graphSource: .github,
                                githubSnapshot: nil)
        XCTAssertNil(entry.habit)
    }

    func testGitHubEntryCarriesCustomPaletteWithoutResolvingAHabit() {
        let custom = CustomPalette(name: "Petrol", base: 0x0F766E)
        let habit = Habit(name: "Laufen")
        let entry = HaiityEntry(date: .now,
                                habits: [habit],
                                palettes: PaletteBook(global: .default, customs: [custom]),
                                selected: habit.id,
                                graphSource: .github,
                                selectedPalette: .custom(custom.id),
                                githubSnapshot: nil)

        XCTAssertNil(entry.habit)
        XCTAssertEqual(entry.resolvedGraphPalette, custom.style)
    }

    func testMissingSelectedPaletteFallsBackToGlobalPalette() {
        let entry = HaiityEntry(date: .now,
                                habits: [],
                                palettes: PaletteBook(global: .blue),
                                graphSource: .github,
                                selectedPalette: .custom(UUID()))

        XCTAssertEqual(entry.resolvedGraphPalette, GraphPalette.blue.style)
    }

    func testGraphIntentRequiresSourceAndUsesSafeFallback() throws {
        let source = try source("Haiity/Intents/SelectGraphIntent.swift")
        XCTAssertTrue(source.contains("@Parameter(title: \"Quelle\")"))
        XCTAssertTrue(source.contains("var source: GraphWidgetSource?"))
        XCTAssertTrue(source.contains("struct GraphHabitEntity"))
        XCTAssertTrue(source.contains("var habit: GraphHabitEntity?"))
        XCTAssertTrue(source.contains("isTrackedHabit"))
        XCTAssertTrue(source.contains("source ?? .habit"))
        XCTAssertFalse(source.contains("@IntentParameterDependency"))
    }

    func testMainWidgetRendersRemindersWithoutGraphOrGitHub() throws {
        let source = try source("HaiityWidget/HaiityWidgetView.swift")
        XCTAssertTrue(source.contains("habit.isReminder"))
        XCTAssertTrue(source.contains("reminderContent"))
        XCTAssertFalse(source.contains("GitHubContributionGraph"))
    }

    func testMainWidgetCanRenderAndResetQuantityAndYesNoStates() throws {
        let widgetSource = try source("HaiityWidget/HaiityWidgetView.swift")
        let intent = try source("Haiity/Intents/CheckOffHabitIntent.swift")
        XCTAssertTrue(widgetSource.contains("ResetHabitIntent"))
        XCTAssertTrue(widgetSource.contains("habit.kind == .yesNo"))
        XCTAssertTrue(widgetSource.contains("habit.kind == .quantity"))
        XCTAssertTrue(intent.contains("struct ResetHabitIntent"))
        XCTAssertTrue(widgetSource.contains("AnswerYesHabitIntent"),
                      "Ja/Nein widgets need an explicit Ja action")
        XCTAssertTrue(widgetSource.contains("AnswerNoHabitIntent"),
                      "Ja/Nein widgets need an explicit Nein action")
        XCTAssertTrue(intent.contains("struct AnswerYesHabitIntent"))
        XCTAssertTrue(intent.contains("struct AnswerNoHabitIntent"))
    }

    func testHabitSpecificWidgetsUseHabitDeepLinks() throws {
        let main = try source("HaiityWidget/HaiityWidgetView.swift")
        let roster = try source("HaiityWidget/RosterWidgetView.swift")

        XCTAssertTrue(main.contains("HaiityWidgetLink.habit"),
                      "the selected habit widget must open its habit")
        XCTAssertTrue(roster.contains("HaiityWidgetLink.habit"),
                      "overview rows must open the habit they represent")
    }

    func testOverviewWidgetSupportsAllInteractiveItemKinds() throws {
        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        let logic = try source("HaiityWidget/WidgetLogic.swift")

        XCTAssertTrue(logic.contains("let active = habits.filter { $0.archivedAt == nil }"),
                      "overview selection must include reminders")
        for symbol in ["CheckOffHabitIntent", "AnswerYesHabitIntent",
                       "AnswerNoHabitIntent", "ResetHabitIntent"] {
            XCTAssertTrue(roster.contains(symbol),
                          "overview rows need the (symbol) action")
        }
        XCTAssertTrue(roster.contains("habit.isReminder"),
                      "reminder rows must render without a habit graph")
    }

    func testGraphContextMenuScopesItsHitTestToItsHost() throws {
        let source = try source("Haiity/Views/HabitCard.swift")
        XCTAssertTrue(source.contains("final class MenuHost: UIView, UIContextMenuInteractionDelegate"),
                      "each graph must own its context interaction")
        XCTAssertTrue(source.contains("guard bounds.contains(location) else { return nil }"),
                      "a graph touch must stay inside its own host")
        XCTAssertFalse(source.contains("GraphContextMenuHub"),
                       "a GitHub tile must not use a shared list-cell hub")
    }

    func testGitHubTilesHaveNoBackfillSelectionHandler() throws {
        let card = try source("Haiity/Views/GitHubContributionCard.swift")
        let graph = try source("Haiity/Views/GitHubContributionGraph.swift")

        XCTAssertFalse(card.contains("onSelectDay"),
                       "GitHub tiles must remain display-only")
        XCTAssertFalse(graph.contains("onSelectDay"),
                       "GitHub tiles must not reuse the habit backfill callback")
        XCTAssertTrue(card.contains("GitHub-Profil öffnen"),
                      "the profile action remains available through the hold menu")
    }

    func testInteractiveWidgetActionsAreNotReplacedByAParentWidgetURL() throws {
        let main = try source("HaiityWidget/HaiityWidgetView.swift")
        let roster = try source("HaiityWidget/RosterWidgetView.swift")

        XCTAssertTrue(main.contains("Link(destination: HaiityWidgetLink.habit"),
                      "the main widget needs a link around non-action content")
        XCTAssertTrue(roster.contains("Link(destination: HaiityWidgetLink.habit"),
                      "each overview row needs its own non-action link")
        XCTAssertFalse(main.contains(".widgetURL(entry.habit.map"),
                       "a parent widget URL can swallow AppIntent buttons")
        XCTAssertFalse(roster.contains(".widgetURL(URL(string: \"haiity://habits\")"),
                        "the overview parent URL must not override row targets")
    }

    func testGitHubWidgetHasASeparatePaletteOnlyConfiguration() throws {
        let intentSource = try source("Haiity/Intents/SelectGitHubWidgetIntent.swift")
        XCTAssertTrue(intentSource.contains("struct SelectGitHubWidgetIntent"))
        XCTAssertTrue(intentSource.contains("var palette: GraphPaletteEntity?"))
        XCTAssertFalse(intentSource.contains("var habit:"))

        let widget = try source("HaiityWidget/HaiityWidget.swift")
        XCTAssertTrue(widget.contains("struct HaiityGitHubWidget"))
        XCTAssertTrue(widget.contains("kind: \"HaiityGitHubWidget\""))
    }

    func testGitHubWidgetRendererUsesOnlyWidgetSupportedViews() throws {
        let renderer = try source("HaiityWidget/GitHubWidgetGraph.swift")
        XCTAssertFalse(renderer.contains("ScrollView"))
        XCTAssertFalse(renderer.contains("Canvas"))
        XCTAssertTrue(renderer.contains("GraphLayout.trailing"))
        XCTAssertTrue(renderer.contains("HomeWidgetInk.level"))
        XCTAssertFalse(renderer.contains("monthLabels"))
        XCTAssertFalse(renderer.contains("GridCalendar.label(for:"))

        let graph = try source("HaiityWidget/GraphWidgetView.swift")
        XCTAssertTrue(graph.contains("GitHubWidgetGraph"))
    }

    func testGitHubWidgetKeepsValidEmptyCachesOutOfTheConnectPromptPath() throws {
        let logic = try source("HaiityWidget/WidgetLogic.swift")
        let graph = try source("HaiityWidget/GraphWidgetView.swift")
        let renderer = try source("HaiityWidget/GitHubWidgetGraph.swift")

        XCTAssertTrue(logic.contains("enum GitHubWidgetContent"))
        XCTAssertTrue(logic.contains("static func gitHubWidgetContent"))
        XCTAssertTrue(graph.contains("WidgetLogic.gitHubWidgetContent(snapshot: entry.githubSnapshot"))
        XCTAssertTrue(renderer.contains("case .connectPrompt"))
        XCTAssertTrue(renderer.contains("case .graph(let days)"))
    }

    func testHomeGraphWidgetsRespectWidgetRenderingMode() throws {
        let graph = try source("HaiityWidget/GraphWidgetView.swift")
        let main = try source("HaiityWidget/HaiityWidgetView.swift")
        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        let github = try source("HaiityWidget/GitHubWidgetGraph.swift")

        for source in [graph, main, roster] {
            XCTAssertTrue(source.contains("@Environment(\\.widgetRenderingMode)"))
            XCTAssertTrue(source.contains("mode: mode"))
        }
        XCTAssertTrue(github.contains("mode: WidgetRenderingMode"))
        XCTAssertTrue(github.contains("HomeWidgetInk.level(level,"))
        XCTAssertTrue(github.contains("mode: mode"))
    }

    func testSparseGitHubSnapshotExpandsToAStableWidgetWindow() throws {
        let days = [GitHubContributionDay(date: "2026-08-17", count: 3, level: 2)]

        let window = GitHubContributionGraph.widgetWindow(days: days, weeks: 24)
        let layout = GitHubContributionGraph.layout(days: window, weekLimit: 24)

        XCTAssertEqual(window.count, 24 * GridCalendar.rows)
        XCTAssertEqual(layout.columns.count, 24)
        XCTAssertEqual(window.first?.date, "2026-03-08")
        XCTAssertEqual(window.first?.level, 0)
        XCTAssertTrue(window.contains { $0.date == "2026-08-17" && $0.level == 2 })
    }

    func testExistingGraphWidgetKeepsItsConfigurationIntent() throws {
        let widget = try source("HaiityWidget/HaiityWidget.swift")
        XCTAssertTrue(widget.contains("kind: \"HaiityGraphWidget\""))
        XCTAssertTrue(widget.contains("intent: SelectGraphIntent.self"))
        XCTAssertTrue(widget.contains("provider: GraphWidgetProvider()"))
    }

    func testOverviewCardsPutMetadataOverTheGraph() throws {
        let roster = try source("HaiityWidget/RosterWidgetView.swift")
        XCTAssertTrue(roster.contains("ZStack(alignment: .bottomLeading)"))
        XCTAssertTrue(roster.contains(".ultraThinMaterial"))
        XCTAssertTrue(roster.contains("TrailingGrid(habit: habit"))
    }

    func testLegacyOverviewIsKeptOutOfTheGallery() throws {
        let widget = try source("HaiityWidget/HaiityWidget.swift")
        XCTAssertTrue(widget.contains("struct HaiityRosterProvider"))
        XCTAssertFalse(widget.contains("struct HaiityRosterWidget: Widget"))
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relative))
    }

    private func section(_ text: String, startingAt start: String, endingAt end: String) throws -> String {
        guard let startRange = text.range(of: start) else {
            XCTFail("missing section start marker: \(start)")
            throw NSError(domain: "GitHubWidgetTests", code: 1)
        }
        let tail = text[startRange.lowerBound...]
        guard let endRange = tail.range(of: end) else {
            XCTFail("missing section end marker: \(end)")
            throw NSError(domain: "GitHubWidgetTests", code: 2)
        }
        return String(tail[..<endRange.lowerBound])
    }
}
