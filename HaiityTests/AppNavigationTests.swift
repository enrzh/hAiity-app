import XCTest
@testable import Haiity

final class AppNavigationTests: XCTestCase {
    func testPrimaryDeepLinksSelectTheirTabs() {
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://habits")!), .habits)
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://more")!), .more)
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://sync")!), .more)
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://stats")!), .stats)
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://archive")!), .archive)
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://search")!), .search)
        XCTAssertEqual(AppDestination.resolve(url: URL(string: "haiity://new")!), .create)
    }

    func testUnknownAndForeignURLsAreIgnored() {
        XCTAssertNil(AppDestination.resolve(url: URL(string: "https://aiity.de")!))
        XCTAssertNil(AppDestination.resolve(url: URL(string: "haiity://unknown")!))
    }

    func testDestinationsSelectTheirTabs() {
        XCTAssertEqual(AppDestination.stats.selectedTab, .stats)
        XCTAssertEqual(AppDestination.archive.selectedTab, .more)
        XCTAssertEqual(AppDestination.more.selectedTab, .more)
        XCTAssertEqual(AppDestination.search.selectedTab, .search)
        XCTAssertEqual(AppDestination.create.selectedTab, .create)
    }

    func testStatsIsARealTabAndArchiveRoutesViaMoreTab() {
        XCTAssertEqual(AppDestination.stats.effect,
                       AppRouteEffect(tab: .stats, morePage: nil,
                                      opensSearch: false, opensCreate: false))
        XCTAssertEqual(AppDestination.archive.effect,
                       AppRouteEffect(tab: .more, morePage: .archive,
                                      opensSearch: false, opensCreate: false))
    }

    func testSearchAndCreateHaveExplicitEffects() {
        XCTAssertEqual(AppDestination.search.effect.tab, .search)
        XCTAssertTrue(AppDestination.search.effect.opensSearch)
        XCTAssertTrue(AppDestination.create.effect.opensCreate)
    }

    func testMoreRouteWinsOverQueuedSearchWork() {
        var work = RouteWork()
        let searchRoute = work.begin()
        let moreRoute = work.begin()

        // The queued `haiity://search` callback must not apply after
        // `haiity://more` has become the current route.
        XCTAssertFalse(work.isCurrent(searchRoute))
        XCTAssertTrue(work.isCurrent(moreRoute))
    }

    func testNonCreateRoutesDismissOrWaitForCreateCoverLifecycle() {
        let destinations: [AppDestination] = [.habits, .more, .stats, .archive, .search]

        for destination in destinations {
            var work = RouteWork()
            let route = work.begin(destination.effect)

            XCTAssertEqual(work.nextStep(for: route,
                                         presentation: .init(create: .presented)),
                           .dismissCreate,
                           "\(destination) must dismiss create first")
            XCTAssertEqual(work.nextStep(for: route,
                                         presentation: .init(create: .dismissing)),
                           .waitForCreateDismissal,
                           "\(destination) must wait for create onDismiss")
        }

        var work = RouteWork()
        let createRoute = work.begin(AppDestination.create.effect)
        XCTAssertEqual(work.nextStep(for: createRoute,
                                     presentation: .init(create: .presented)),
                       .apply)
    }

    func testRapidCreateToSearchCancelsBeforeContentPresentation() {
        var work = RouteWork()
        let cover = CreateCoverPresentation()
        _ = work.begin(AppDestination.create.effect)
        let search = work.begin(AppDestination.search.effect)

        XCTAssertEqual(work.nextStep(for: search,
                                     presentation: .init(create: cover.phase(requested: true))),
                       .dismissCreate)
        XCTAssertFalse(cover.dismissalIsOwed)
        XCTAssertEqual(work.nextStep(for: search,
                                     presentation: .init(create: cover.phase(requested: false))),
                       .apply)
    }

    func testRapidCreateToStatsCancelsBeforeContentPresentation() {
        var work = RouteWork()
        let cover = CreateCoverPresentation()
        _ = work.begin(AppDestination.create.effect)
        let stats = work.begin(AppDestination.stats.effect)

        XCTAssertEqual(work.nextStep(for: stats,
                                     presentation: .init(create: cover.phase(requested: true))),
                       .dismissCreate)
        XCTAssertFalse(cover.dismissalIsOwed)
        XCTAssertEqual(work.nextStep(for: stats,
                                     presentation: .init(create: cover.phase(requested: false))),
                       .apply)
    }

    func testLatestRouteWinsDuringRequestedCreateCancellation() {
        var work = RouteWork()
        let cover = CreateCoverPresentation()
        _ = work.begin(AppDestination.create.effect)
        let search = work.begin(AppDestination.search.effect)
        let stats = work.begin(AppDestination.stats.effect)

        XCTAssertNil(work.nextStep(for: search,
                                   presentation: .init(create: cover.phase(requested: false))))
        XCTAssertEqual(work.nextStep(for: stats,
                                     presentation: .init(create: cover.phase(requested: false))),
                       .apply)
    }

    /// Das Kaufblatt ist die oberste Präsentation und wird von KEINER Route
    /// gewollt. Bleibt es stehen, wechselt der Bereich darunter und der
    /// Nutzer sitzt auf einer Kaufseite fest, die zu seinem Tipp nicht mehr
    /// gehört (im Simulator reproduziert: `haiity://new` → Kaufblatt,
    /// danach `haiity://stats` → Blatt blieb).
    func testEveryRouteDismissesAnOpenPaywallFirst() {
        let destinations: [AppDestination] = [.habits, .more, .stats, .archive,
                                              .search, .create]

        for destination in destinations {
            var work = RouteWork()
            let route = work.begin(destination.effect)

            XCTAssertEqual(work.nextStep(for: route,
                                         presentation: .init(paywall: .presented)),
                           .dismissPaywall,
                           "\(destination) must dismiss the paywall first")
            XCTAssertEqual(work.nextStep(for: route,
                                         presentation: .init(paywall: .dismissing)),
                           .waitForPaywallDismissal,
                           "\(destination) must wait for the paywall onDismiss")
            // Ist es weg, geht die Route ihren gewohnten Weg weiter.
            XCTAssertEqual(work.nextStep(for: route, presentation: .init()), .apply)
        }
    }

    /// Das Kaufblatt gewinnt gegen das Anlege-Cover UND gegen die
    /// Mehr-Seite: es liegt über beiden.
    func testPaywallIsDismissedBeforeCoverAndMoreSheet() {
        var work = RouteWork()
        let route = work.begin(AppDestination.stats.effect)

        XCTAssertEqual(work.nextStep(for: route,
                                     presentation: .init(create: .presented,
                                                         paywall: .presented,
                                                         more: .presented,
                                                         morePage: .archive)),
                       .dismissPaywall)
    }

    func testPaywallSheetIsWiredIntoTheRouteStateMachine() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("onDismiss: deliverPendingPaywallDismissalRoute"))
        XCTAssertTrue(source.contains(".onAppear { paywallDidPresent(context) }"))
        XCTAssertTrue(source.contains("let waitsForOnDismiss = paywallIsPresented"))
        // Die Bereiche mit EIGENEM Kaufblatt räumen es am Routen-Zähler weg.
        XCTAssertTrue(source.contains("routeToken &+= 1"))
        for host in ["Haiity/Views/MoreView.swift", "Haiity/Views/StatsView.swift"] {
            let text = try String(contentsOf: sourceURL(host))
            XCTAssertTrue(text.contains(".onChange(of: routeToken)"), host)
        }
    }

    func testCreateCoverSeparatesRequestFromActualPresentation() {
        var cover = CreateCoverPresentation()

        XCTAssertEqual(cover.phase(requested: true), .requested)
        XCTAssertFalse(cover.dismissalIsOwed)

        cover.didPresent()
        XCTAssertEqual(cover.phase(requested: true), .presented)
        XCTAssertEqual(cover.phase(requested: false), .dismissing)
        XCTAssertTrue(cover.dismissalIsOwed)

        cover.didDismiss()
        XCTAssertEqual(cover.phase(requested: false), .absent)
        XCTAssertFalse(cover.dismissalIsOwed)
    }

    func testArchiveRouteDismissesForeignSheetThenAppliesAfterOnDismiss() {
        var work = RouteWork()
        let archive = work.begin(AppDestination.archive.effect)

        // Ein fremdes Blatt (z. B. "Ueber", morePage nil) muss erst weichen.
        XCTAssertEqual(work.nextStep(for: archive,
                                     presentation: .init(more: .presented,
                                                         morePage: nil)),
                       .dismissMore)
        XCTAssertEqual(work.nextStep(for: archive,
                                     presentation: .init(more: .dismissing)),
                       .waitForMoreDismissal)
        XCTAssertEqual(work.nextStep(for: archive, presentation: .init()), .apply)
    }

    func testRoutesLeavingMoreDismissPresentedSheetOnBothHosts() {
        let destinations: [AppDestination] = [.create, .search, .habits]

        for destination in destinations {
            var work = RouteWork()
            let route = work.begin(destination.effect)

            // RoutePresentation is deliberately platform-neutral: the same
            // transition governs fallback moreSheet and native morePageRoute.
            XCTAssertEqual(work.nextStep(for: route,
                                         presentation: .init(more: .presented,
                                                             morePage: .archive)),
                           .dismissMore,
                           "\(destination) must depart More through onDismiss")
        }
    }

    func testAlreadyPresentedMoreDestinationDoesNotDismissOrRepresent() {
        for destination in [AppDestination.archive] {
            var work = RouteWork()
            let route = work.begin(destination.effect)

            XCTAssertEqual(work.nextStep(for: route,
                                         presentation: .init(more: .presented,
                                                             morePage: destination.effect.morePage)),
                           .keepCurrentMorePage)
        }
    }

    func testLatestRouteWinsOverStaleDismissalCallbacks() {
        var work = RouteWork()
        let stats = work.begin(AppDestination.stats.effect)
        let habits = work.begin(AppDestination.habits.effect)

        XCTAssertNil(work.nextStep(for: stats, presentation: .init()))
        XCTAssertEqual(work.nextStep(for: habits, presentation: .init()), .apply)
    }

    func testFallbackTabLayersExposeOnlyTheSelectedMountedTree() {
        let habits = AppTabLayerState(tab: .habits, selectedTab: .habits)
        let hiddenMore = AppTabLayerState(tab: .more, selectedTab: .habits)

        XCTAssertEqual(habits, .init(opacity: 1, allowsHitTesting: true,
                                    accessibilityHidden: false, zIndex: 1))
        XCTAssertEqual(hiddenMore, .init(opacity: 0, allowsHitTesting: false,
                                        accessibilityHidden: true, zIndex: 0))
        XCTAssertEqual(AppTabLayerState(tab: .habits, selectedTab: .more), hiddenMore)
        XCTAssertEqual(AppTabLayerState(tab: .more, selectedTab: .more), habits)
    }

    func testContentViewDeclaresAllFourTabs() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("value: AppTab.stats"))
        XCTAssertTrue(source.contains("value: AppTab.habits"))
        XCTAssertTrue(source.contains("value: AppTab.more"))
        XCTAssertTrue(source.contains("value: AppTab.search, role: .search"))
        XCTAssertFalse(source.contains("enum NativeTab"))
    }

    func testFallbackKeepsBothDestinationTreesMounted() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("fallbackTabLayer(.stats) { fallbackStatsContent }"))
        XCTAssertTrue(source.contains("fallbackTabLayer(.habits) { habitsStack }"))
        XCTAssertTrue(source.contains("fallbackTabLayer(.more) { fallbackMoreContent }"))
        XCTAssertFalse(source.contains("if nativeTab == .more {"))
        XCTAssertTrue(source.contains(".opacity(state.opacity)"))
        XCTAssertTrue(source.contains(".allowsHitTesting(state.allowsHitTesting)"))
        XCTAssertTrue(source.contains(".accessibilityHidden(state.accessibilityHidden)"))
    }

    func testBothMoreSheetHostsDeliverPendingRouteFromOnDismiss() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertEqual(source.components(separatedBy:
            "onDismiss: deliverPendingMoreDismissalRoute").count - 1, 2)
        XCTAssertEqual(source.components(separatedBy:
            ".onAppear { moreSheetDidPresent(route) }").count - 1, 2)
        XCTAssertTrue(source.contains("moreSheetIsPresented"))
        XCTAssertTrue(source.contains("pendingRoute"))
    }

    func testMoreRouteCanReplaceARequestedButNotPresentedSheet() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("let waitsForOnDismiss = moreSheetIsPresented"))
        XCTAssertTrue(source.contains("if !waitsForOnDismiss"))
        XCTAssertTrue(source.contains("advance(route)"))
    }

    func testCreateRouteCanReplaceARequestedButNotPresentedCover() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("createPage.onAppear { createCoverDidPresent() }"))
        XCTAssertTrue(source.contains("guard showAdd else { return }"))
        XCTAssertTrue(source.contains("let waitsForOnDismiss = createCover.dismissalIsOwed"))
        XCTAssertTrue(source.contains("if !waitsForOnDismiss { advance(route) }"))
        XCTAssertTrue(source.contains("createCover.phase(requested: showAdd)"))
        XCTAssertTrue(source.contains("chrome.searchFlow.coverChanged(open: open)"))
        XCTAssertFalse(source.contains("if open { createCoverIsPresented = true }"))
    }

    func testCreateAccessibilityContractIsSharedAcrossCustomControls() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("static let label = String(localized: \"Neuer Habit\")"))
        XCTAssertTrue(source.contains("static let identifier = \"create-habit\""))
        XCTAssertGreaterThanOrEqual(source.components(separatedBy:
            ".accessibilityLabel(CreateAccessibility.label)").count - 1, 2)
        XCTAssertGreaterThanOrEqual(source.components(separatedBy:
            ".accessibilityIdentifier(CreateAccessibility.identifier)").count - 1, 2)
        XCTAssertTrue(source.contains("private var createToolbarItem: some ToolbarContent"))
    }

    func testContentViewKeepsHabitReorderingReachable() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("@State private var editMode: EditMode = .inactive"))
        XCTAssertTrue(source.contains(".environment(\\.editMode, $editMode)"))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"reorder-habits\")"))
        XCTAssertTrue(source.contains(".onMove(perform: search.isEmpty"))
    }

    func testMainMorePageExposesGitHubConnectionAndLogout() throws {
        let more = try String(contentsOf: sourceURL("Haiity/Views/MoreView.swift"))
        let content = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        let aboutStart = try XCTUnwrap(more.range(of: "struct AboutView: View"))
        let about = more[aboutStart.lowerBound...]

        XCTAssertTrue(more.contains("let github: GitHubContributionStore"))
        XCTAssertTrue(more.contains("private var githubSection: some View"))
        XCTAssertTrue(more.contains("accessibilityIdentifier(\"open-github-settings\")"))
        XCTAssertTrue(more.contains("accessibilityIdentifier(\"disconnect-github\")"))
        XCTAssertGreaterThanOrEqual(content.components(separatedBy: "github: github").count - 1, 4)
        XCTAssertFalse(about.contains("NavigationLink(value: MoreRoute.github)"))
    }

    func testHabitToolbarKeepsManagementDestinationsReachable() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"habit-management\")"))
        // Statistik ist ein eigener Tab; im Menue bleibt nur noch das Archiv.
        XCTAssertFalse(source.contains("accessibilityIdentifier(\"open-stats\")"))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"open-archive\")"))
    }

    func testSearchIsARealTabWithItsOwnSearchable() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        XCTAssertTrue(source.contains("value: AppTab.search, role: .search"))
        // Der Such-Tab traegt sein EIGENES searchable (Fotos-Muster) …
        XCTAssertTrue(source.contains("private var searchTabContent: some View"))
        XCTAssertTrue(source.contains(".searchFocused($searchFieldFocused)"))
        // … seine Auswahl BLEIBT stehen, solange die Suche OFFEN ist (kein
        // Zurückspringen beim Betreten — der v15-Käfer); das Betreten
        // fokussiert nur noch das Feld.
        XCTAssertFalse(source.contains("nativeTab = old == .search ? .habits : old"))
        XCTAssertTrue(source.contains("@State private var searchPresentationArmed = false"))
        // ZUKLAPPEN dagegen heißt verlassen: X kehrt auf den zuletzt
        // gewählten echten Bereich zurück, damit die Leiste in den
        // Such-KREIS zurückschrumpft, statt als leere Leiste liegen zu
        // bleiben (v24).
        XCTAssertTrue(source.contains("if tab != .search { lastNonSearchTab = tab }"))
        XCTAssertTrue(source.contains("returnFromSearchAfterCollapse()"))
        XCTAssertFalse(source.contains("withAnimation { nativeTab = lastNonSearchTab }"))
    }

    func testSingleNativeShellWithoutCompilerGates() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Views/ContentView.swift"))
        // Die Rollen-Verrenkung (prominent hinter #if compiler) ist Geschichte.
        XCTAssertFalse(source.contains("role: .prominent"))
        XCTAssertFalse(source.contains("#if compiler(>=6.4)"))
        XCTAssertFalse(source.contains("private var splitShell"))
        XCTAssertTrue(source.contains("private var nativeShell: some View"))
    }

    private func sourceURL(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }
}
