import Foundation
import SwiftUI
import XCTest
@testable import Haiity

final class GitHubWidgetTests: XCTestCase {
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

    func testOverviewWidgetIsLargeOnly() throws {
        let widget = try source("HaiityWidget/HaiityWidget.swift")
        let start = try XCTUnwrap(widget.range(of: "struct HaiityRosterWidget: Widget"))
        let end = widget.range(of: "// MARK: – Sperrbildschirm", range: start.upperBound..<widget.endIndex)
            ?? widget.endIndex..<widget.endIndex
        let roster = widget[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(roster.contains(".supportedFamilies([.systemLarge])"))
        XCTAssertFalse(roster.contains(".systemMedium"))
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relative))
    }
}
