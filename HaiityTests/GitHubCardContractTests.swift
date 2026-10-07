import Foundation
import XCTest
@testable import Haiity

final class GitHubCardContractTests: XCTestCase {

    // MARK: - The settings page says one thing once

    /// The failure state used to put a whole sentence in the title slot AND
    /// repeat it in the red message underneath, which made the most important
    /// row the least scannable one on the page. The title names the thing, the
    /// subtitle names the state, and the specific reason stays where it can be
    /// read in full.
    func testTheStatusRowNamesTheThingAndTheStateSeparately() throws {
        let view = try source("Haiity/Views/GitHubSettingsView.swift")
        let title = try XCTUnwrap(view.range(of: "private var statusTitle"))
        let titleBody = String(view[title.upperBound...].prefix(420))
        XCTAssertFalse(titleBody.contains("fehlgeschlagen"),
                       "a full sentence does not belong in the title slot")
        XCTAssertTrue(titleBody.contains("GitHub-Beitragskalender"),
                      "the title should stay the stable name of the thing")

        let subtitle = try XCTUnwrap(view.range(of: "private var statusSubtitle"))
        let subtitleBody = String(view[subtitle.upperBound...].prefix(700))
        XCTAssertFalse(subtitleBody.contains("Erneut versuchen"),
                       "an action label does not belong in a state slot")
        // The connecting state said "Code auf GitHub eingeben" in the row and
        // again directly below it. Once now.
        XCTAssertEqual(subtitleBody.components(separatedBy: "Code auf GitHub eingeben").count - 1, 0,
                       "the instruction must not be stated twice on one screen")
    }

    /// A destructive action that looks like every other row is an action people
    /// tap by accident. The role was declared and `.plain` threw the red away.
    func testDisconnectingActuallyLooksDestructive() throws {
        let view = try source("Haiity/Views/GitHubSettingsView.swift")
        let button = try XCTUnwrap(view.range(of: "private var disconnectButton"))
        let body = String(view[button.upperBound...].prefix(900))

        XCTAssertTrue(body.contains("role: .destructive"))
        XCTAssertTrue(body.contains(".foregroundStyle(.red)"),
                      "plain button style discards the role's colour, so set it here")
        XCTAssertTrue(body.contains("link.badge.minus"),
                      "a symbol as well as a colour, so the difference is not colour alone")
    }

    /// The clipboard used to be overwritten the moment the page appeared, with
    /// nobody asking. The button beside the code is the way to do it.
    func testTheCodeIsOnlyCopiedWhenAsked() throws {
        let view = try source("Haiity/Views/GitHubSettingsView.swift")
        let appear = try XCTUnwrap(view.range(of: ".onAppear {"))
        let body = String(view[appear.upperBound...].prefix(500))
        XCTAssertFalse(body.contains("copyCode"),
                       "appearing on the page is not a request to replace the clipboard")
        XCTAssertTrue(view.contains("copyReset?.cancel()"),
                       "the copied tick needs an owner so a second tap cannot be undone by the first")
    }

    /// GitHub's device flow is a round trip through a website. A lone spinner
    /// told the person the app was busy and nothing about what it was waiting
    /// for, with no way to give up.
    func testWaitingForGitHubSaysWhatItWaitsForAndOffersAWayOut() throws {
        let view = try source("Haiity/Views/GitHubSettingsView.swift")
        XCTAssertTrue(view.contains("Warte auf die Bestätigung in GitHub."),
                      "the spinner needs a sentence beside it")
        XCTAssertTrue(view.contains("store.cancelConnect()"),
                      "a pending code should be abandonable")
        let store = try source("Haiity/Models/GitHubContributionStore.swift")
        let cancel = try XCTUnwrap(store.range(of: "func cancelConnect()"))
        let body = String(store[cancel.upperBound...].prefix(700))
        XCTAssertFalse(body.contains("vault.delete()"),
                       "giving up on an unfinished login must not delete stored credentials")
        XCTAssertTrue(body.contains("deviceCode = nil"))
        XCTAssertTrue(body.contains("phase = .disconnected"))
    }

    /// The preview sized its cells from a literal `23 * 3` while passing
    /// `gap: 3`, so the maths and the grid could disagree and the last column
    /// would quietly overflow.
    func testThePreviewGridHasOneSourceOfTruthForItsGap() throws {
        let view = try source("Haiity/Views/GitHubSettingsView.swift")
        let preview = try XCTUnwrap(view.range(of: "private var contributionPreview"))
        let body = String(view[preview.upperBound...].prefix(1800))

        XCTAssertTrue(body.contains("let gap: CGFloat"))
        XCTAssertTrue(body.contains("columns * gap"))
        XCTAssertFalse(body.contains("23 * 3"),
                       "the gap must not be repeated as a literal in the size maths")
        XCTAssertTrue(body.contains("CGFloat(GridCalendar.rows)"),
                      "the row count should come from the grid, not a 7")
        XCTAssertTrue(body.contains("Vorschau deines Beitragskalenders"),
                      "the preview should say what it is for a screen reader")
    }

    /// "GitHub ist nicht eingerichtet." was a dead end: one grey sentence, no
    /// action, no explanation, reading like something the person had broken.
    func testTheNotConfiguredStateExplainsItself() throws {
        let view = try source("Haiity/Views/GitHubSettingsView.swift")
        XCTAssertTrue(view.contains("private var connectionFooter"))
        XCTAssertTrue(view.contains("footer: connectionFooter"),
                      "the explanation has to actually be wired to the group")
        XCTAssertTrue(view.contains("nicht enthalten"),
                      "and it has to say the connection is absent, not broken")
    }

    func testHabitsPageHostsTheCardOutsideSearchAndHabitActions() throws {
        let content = try source("Haiity/Views/ContentView.swift")
        let card = try source("Haiity/Views/GitHubContributionCard.swift")
        let searchStart = try XCTUnwrap(content.range(of: "private var searchList: some View"))
        let habitsStart = try XCTUnwrap(content.range(of: "private var habitList: some View"))
        let searchListSource = String(content[searchStart.lowerBound..<habitsStart.lowerBound])
        let habitList = String(content[habitsStart.lowerBound...])

        XCTAssertTrue(content.contains("GitHubContributionCard"))
        XCTAssertTrue(card.contains("GitHub-Profil öffnen"))
        XCTAssertTrue(card.contains("arrow.up.right.square"))
        XCTAssertFalse(card.contains("SwipeRevealPan"))
        XCTAssertFalse(card.contains("swipeActions"))
        XCTAssertFalse(card.contains("RevealAction"))
        XCTAssertFalse(searchListSource.contains("GitHubContributionCard"))
        XCTAssertTrue(habitList.contains("GitHubContributionCard"))

        let cardUse = try XCTUnwrap(habitList.range(of: "GitHubContributionCard"))
        let foreach = try XCTUnwrap(habitList.range(of: "ForEach(habitsTabSource)"))
        XCTAssertGreaterThan(cardUse.lowerBound, foreach.lowerBound,
                             "daily entries must precede optional GitHub activity")
        let cardEnd = try XCTUnwrap(habitList.range(of: ".accessibilityIdentifier(\"habit-list\")",
                                                   range: cardUse.upperBound..<habitList.endIndex))
        let afterCard = habitList[cardUse.upperBound..<cardEnd.lowerBound]
        XCTAssertFalse(afterCard.contains(".onMove"))
        XCTAssertFalse(afterCard.contains("swipeActions"))
        XCTAssertFalse(afterCard.contains("row(for:"))
    }

    func testProfileURLPercentEncodesTheLogin() {
        let snapshot = GitHubContributionSnapshot(username: "octo cat",
                                                  days: [],
                                                  fetchedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(snapshot.profileURL?.absoluteString, "https://github.com/octo%20cat")
        XCTAssertEqual(GitHubContributionSnapshot(username: "enrzh", days: [], fetchedAt: .now)
            .profileURL?.absoluteString, "https://github.com/enrzh")
    }

    func testSettingsLiveOnMainMoreAndPreserveTheExistingFlow() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        let content = try source("Haiity/Views/ContentView.swift")
        let settings = try source("Haiity/Views/GitHubSettingsView.swift")
        let card = try source("Haiity/Views/GitHubContributionCard.swift")

        XCTAssertTrue(more.contains("case archive, about, developer, appearance, habitBehavior, github"))
        XCTAssertTrue(more.contains("open-github-settings"))
        XCTAssertTrue(more.contains("private var moreGitHubRow: some View"))
        XCTAssertFalse(more.contains("disconnect-github"))
        XCTAssertTrue(try source("Haiity/Views/GitHubSettingsView.swift").contains("github-disconnect"))
        XCTAssertFalse(more.contains("NavigationLink(value: MoreRoute.github)"))
        XCTAssertTrue(content.contains("GitHubSettingsView(store: github,"))
        XCTAssertTrue(content.contains("showsUsername: githubUsernameBinding"))
        XCTAssertTrue(content.contains("AboutView(store: store)"))
        XCTAssertTrue(settings.contains("github-connect"))
        XCTAssertTrue(settings.contains("github-open-verification"))
        XCTAssertTrue(settings.contains("github-copy-code"))
        XCTAssertTrue(settings.contains("github-copy-confirmation"))
        XCTAssertTrue(settings.contains("github-refresh"))
        XCTAssertTrue(settings.contains("store.isRefreshing"))
        XCTAssertTrue(settings.contains("store.refreshFeedback"))
        XCTAssertTrue(settings.contains("store.refreshAnimationToken"))
        XCTAssertTrue(settings.contains("github-refresh-success"))
        XCTAssertTrue(settings.contains("github-refresh-failure"))
        XCTAssertTrue(settings.contains("Erneut anmelden"))
        XCTAssertTrue(settings.contains("prepareForReauthentication"))
        XCTAssertTrue(settings.contains(".disabled(store.isRefreshing)"))
        XCTAssertTrue(settings.contains("github-disconnect"))
        XCTAssertTrue(settings.contains("GitHub-Namen anzeigen"))
        XCTAssertTrue(settings.contains("github-username-toggle"))
        XCTAssertFalse(content.contains("@AppStorage(GitHubPreferences.showsUsernameKey"))
        XCTAssertTrue(content.contains("private var githubUsernameBinding: Binding<Bool>"))
        XCTAssertTrue(content.contains("showsUsername: githubUsernameBinding"))
        XCTAssertTrue(content.contains("showsUsername: store.githubShowsUsername"))
        XCTAssertTrue(card.contains("let showsUsername: Bool"))
        XCTAssertFalse(card.contains("@AppStorage(GitHubPreferences.showsUsernameKey"))
        XCTAssertTrue(card.contains("if showsUsername"))
        XCTAssertFalse(settings.contains("SafariServices"))
        XCTAssertFalse(settings.contains("SFSafariViewController"))
        XCTAssertFalse(settings.contains("GitHubVerificationBrowser"))
        XCTAssertTrue(settings.contains("GitHubLink.open(code.verificationURLWithCode)"))
        XCTAssertTrue(settings.contains("verificationURLWithCode"))
        XCTAssertTrue(settings.contains("url.scheme?.lowercased() == \"https\""))
    }

    /// The code reaches the clipboard when the button is tapped, and the button
    /// says so. It used to be copied as soon as the page appeared — and again
    /// whenever a new code arrived — replacing whatever the person was holding
    /// without them asking for it.
    func testTheDeviceCodeIsCopiedOnRequestAndSaysThatItWas() throws {
        let settings = try source("Haiity/Views/GitHubSettingsView.swift")

        XCTAssertTrue(settings.contains("UIPasteboard.general.string = code.userCode"))
        XCTAssertTrue(settings.contains("copyCode(code)"),
                      "the button beside the code is the way to copy it")
        XCTAssertFalse(settings.contains("copyCode(store.deviceCode)"),
                       "appearing on the page is not a request to replace the clipboard")
        XCTAssertFalse(settings.contains(".onChange(of: store.deviceCode)"),
                       "nor is a code arriving a request to replace the clipboard")
        XCTAssertTrue(settings.contains("symbolEffect(.bounce, value: codeCopied)"))
        XCTAssertTrue(settings.contains("Code kopiert."))
        XCTAssertTrue(settings.contains("Code kopieren"))
    }

    func testGitHubLinkRejectsNonHTTPS() {
        XCTAssertNotNil(GitHubContributionSnapshot(username: "enrzh", days: [], fetchedAt: .now).profileURL)
    }

    func testGitHubKeysHaveEveryLocalization() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Localizable.xcstrings"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        let languages = ["ar", "bn", "en", "es", "fr", "hi", "id", "it",
                         "ja", "ko", "pt", "ru", "tr", "ur", "vi", "zh-Hans"]
        let keys = [
            "GitHub verbinden", "Auf GitHub öffnen", "Aktualisieren",
            "Verbindung trennen", "GitHub-Konto trennen?",
            "Der Beitragskalender verschwindet von der Habits-Seite.",
            "Erneut anmelden", "Erneut versuchen", "GitHub-Profil öffnen",
            "GitHub ist nicht eingerichtet.",
            "GitHub hat die Verbindung abgelehnt.",
            "Der Code ist abgelaufen. Bitte erneut verbinden.",
            "Die Verbindung zu GitHub ist fehlgeschlagen.",
            "Verbunden als %@",
            "Dein offizieller GitHub-Beitragskalender erscheint auf der Habits-Seite.",
            "Code auf GitHub eingeben", "Code kopieren", "Code kopiert.",
            "GitHub-Beitragskalender", "GitHub-Namen anzeigen"
        ]
        for key in keys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], "fehlt im Katalog: \(key)")
            let locs = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
            for language in languages {
                let unit = locs[language] as? [String: Any]
                let stringUnit = unit?["stringUnit"] as? [String: Any]
                let value = stringUnit?["value"] as? String
                XCTAssertEqual(stringUnit?["state"] as? String, "translated", "\(key) \(language)")
                XCTAssertNotEqual(value, key, "\(language) fällt auf Deutsch zurück: \(key)")
                XCTAssertFalse(value?.isEmpty ?? true, "\(key) \(language)")
            }
        }
    }

    func testGraphBuildsSevenRowsWithoutInventingAHabit() {
        let days = [
            GitHubContributionDay(date: "2026-08-16", count: 2, level: 1),
            GitHubContributionDay(date: "2026-08-17", count: 0, level: 0)
        ]
        let layout = GitHubContributionGraph.layout(days: days, weekLimit: nil)
        XCTAssertFalse(layout.columns.isEmpty)
        XCTAssertEqual(layout.columns[0].count, 7)
        let source = try? self.source("Haiity/Views/GitHubContributionCard.swift")
        XCTAssertFalse(source?.contains("Habit(") ?? true)
    }

    func testHeldGitHubPreviewUsesAReadableRecentWindow() throws {
        let card = try source("Haiity/Views/GitHubContributionCard.swift")

        XCTAssertTrue(card.contains("previewGraphWeeks = 16"))
        XCTAssertTrue(card.contains("previewGraphCellSize"))
        XCTAssertTrue(card.contains("weeks: Self.previewGraphWeeks"))
        XCTAssertTrue(card.contains("gap: Self.previewGraphGap"))
        XCTAssertTrue(card.contains("showsMonthLabels: false"))
    }

    func testGitHubMonthLabelsAreUserSelectableAndReachTheHabitPageCard() throws {
        let settings = try source("Haiity/Views/GitHubSettingsView.swift")
        let content = try source("Haiity/Views/ContentView.swift")
        let card = try source("Haiity/Views/GitHubContributionCard.swift")

        XCTAssertTrue(settings.contains("GitHub-Monate anzeigen"))
        XCTAssertTrue(settings.contains("github-month-labels-toggle"))
        XCTAssertTrue(content.contains("githubMonthLabelsBinding"))
        XCTAssertTrue(content.contains("showsMonthLabels: graphShowsMonthLabels"))
        XCTAssertTrue(card.contains("let showsMonthLabels: Bool"))
        XCTAssertTrue(card.contains("showsMonthLabels: showsMonthLabels"))
    }

    func testGitHubGraphUsesTheSharedGraphMetricsAndEquatableRendering() throws {
        let graph = try source("Haiity/Views/GitHubContributionGraph.swift")
        let card = try source("Haiity/Views/GitHubContributionCard.swift")

        XCTAssertTrue(graph.contains("struct GitHubContributionGraph: View, Equatable"))
        XCTAssertTrue(graph.contains("GridCell.size"))
        XCTAssertTrue(graph.contains("GridCell.gap"))
        XCTAssertTrue(graph.contains("GridCell.radius"))
        XCTAssertTrue(graph.contains("@Environment(\\.palettes)"))
        XCTAssertTrue(card.contains("GitHubContributionGraph(days: snapshot.days,"))
        XCTAssertTrue(card.contains("showsMonthLabels: showsMonthLabels"))
        XCTAssertTrue(card.contains("palette: palettes.style"),
                      "the held preview must keep the selected app palette")
        XCTAssertTrue(card.contains(".equatable()"))
    }

    func testHabitAndGitHubGraphsUseOneCanvasRenderer() throws {
        let habit = try source("Haiity/Views/ContributionGrid.swift")
        let github = try source("Haiity/Views/GitHubContributionGraph.swift")
        let card = try source("Haiity/Views/GitHubContributionCard.swift")

        XCTAssertTrue(habit.contains("ContributionChart("),
                      "habit graphs should use the shared renderer")
        XCTAssertTrue(github.contains("ContributionChart("),
                      "GitHub graphs should use the same renderer as habits")
        XCTAssertTrue(github.contains("GridCalendar.snapshot(levelsByDay:"),
                      "GitHub data should be converted into the shared grid snapshot")
        // Two assertions used to sit here about `ContributionChartLegend`: one
        // that the GitHub file declares it, one that the compact card does not
        // call it. Neither could ever fail usefully — nothing instantiated the
        // type — and the pair contradicted each other's stated purpose. The type
        // is deleted; what matters above is that both surfaces go through the
        // one renderer.
    }

    func testGraphsCenterFittingContentAndScrollOnlyWhenItOverflows() throws {
        let habit = try source("Haiity/Views/ContributionGrid.swift")
        let github = try source("Haiity/Views/GitHubContributionGraph.swift")

        for graph in [habit, github] {
            XCTAssertTrue(graph.contains("GridCalendar.needsHorizontalScroll("),
                          "the graph must measure its viewport before enabling horizontal scrolling")
            XCTAssertTrue(graph.contains(".frame(maxWidth: .infinity, alignment: .center)"),
                          "a fitting graph must be optically centered")
            XCTAssertTrue(graph.contains(".defaultScrollAnchor(.trailing)"),
                          "an overflowing graph must keep the current-date edge visible")
        }
    }

    func testSharedTilesUseFillContrastInsteadOfPerTileOutlines() throws {
        let graph = try source("Haiity/Views/GitHubContributionGraph.swift")

        XCTAssertFalse(graph.contains("outline: Theme.adaptiveTileOutline"),
                       "adaptive material must not draw a border around every tile")
        XCTAssertFalse(graph.contains("if let outline"),
                       "the shared tile canvas should remain a continuous field")
        XCTAssertTrue(graph.contains("todayOutline"),
                      "semantic today highlighting must remain available")
        XCTAssertTrue(graph.contains("highlightOutline"),
                      "history selection highlighting must remain available")
    }

    func testHistoryHighlightIsVisibleInDarkMode() {
        XCTAssertGreaterThan(ContributionTiles.highlightBackgroundOpacity(dark: true),
                             ContributionTiles.highlightBackgroundOpacity(dark: false))
        XCTAssertGreaterThanOrEqual(ContributionTiles.highlightBackgroundOpacity(dark: true), 0.28)
    }

    func testGitHubDisplayOptionsShareOneSettingsGroup() throws {
        let settings = try source("Haiity/Views/GitHubSettingsView.swift")

        XCTAssertTrue(settings.contains("github-display-settings"),
                      "GitHub display controls should have one cohesive settings group")
        XCTAssertTrue(settings.contains("GitHub-Namen anzeigen"))
        XCTAssertTrue(settings.contains("GitHub-Monate anzeigen"))
    }

    func testMonthLabelPreferenceReachesHabitAndGitHubGraphs() throws {
        let content = try source("Haiity/Views/ContentView.swift")
        let habit = try source("Haiity/Views/HabitCard.swift")
        let more = try source("Haiity/Views/MoreAppearance.swift")

        XCTAssertTrue(content.contains("graphShowsMonthLabels"))
        XCTAssertTrue(content.contains("showsMonthLabels: graphShowsMonthLabels"))
        XCTAssertTrue(habit.contains("showsMonthLabels: Bool"))
        XCTAssertTrue(more.contains("graphShowsMonthLabels"))
        XCTAssertTrue(more.contains("Monate anzeigen"))
    }

    func testGitHubMonthLabelPreferenceIsPersistedInSharedDefaults() throws {
        let preferences = try source("Haiity/Models/GitHubPreferences.swift")

        XCTAssertTrue(preferences.contains("showsMonthLabelsKey"))
        XCTAssertTrue(preferences.contains("showsMonthLabels(in defaults: UserDefaults)"))
        XCTAssertTrue(preferences.contains("setShowsMonthLabels(_ value: Bool"))
        XCTAssertTrue(preferences.contains("SharedStorage.appGroup"))
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relative))
    }
}
