import XCTest
@testable import Haiity

/// v21: das gestaffelte Motiv-Raster (Leerzustand + Einrichtung) und der
/// mehrseitige Einrichtungs-Bildschirm.
final class SetupFlowTests: XCTestCase {

    // MARK: – MotifGrid-Mathematik

    func testMotifDelayStartsAtZeroAndGrowsMonotonically() {
        XCTAssertEqual(MotifGrid.delay(for: 0), 0)
        for i in 1..<48 {
            XCTAssertGreaterThan(MotifGrid.delay(for: i), MotifGrid.delay(for: i - 1))
        }
    }

    /// Der ganze Auftritt bleibt unter einer Sekunde — eine Begrüßung,
    /// kein Ladebalken.
    func testMotifEntranceStaysUnderASecond() {
        XCTAssertLessThan(MotifGrid.delay(for: 47), 1.0)
    }

    func testMotifDelayToleratesNegativeIndices() {
        XCTAssertEqual(MotifGrid.delay(for: -3), 0)
    }

    /// Das feste Markenmotiv füllt ganze Zeilen und bleibt in der Rampe.
    func testBrandMotifFillsWholeRowsWithinTheRamp() {
        XCTAssertEqual(MotifGrid.brand.count % MotifGrid.columns, 0)
        XCTAssertTrue(MotifGrid.brand.allSatisfy { (0...4).contains($0) })
        // Ein Motiv, nicht eine leere Fläche: mehrere gefüllte Stufen.
        XCTAssertGreaterThan(Set(MotifGrid.brand.filter { $0 > 0 }).count, 2)
    }

    func testRandomPatternStaysInTheRamp() {
        for _ in 0..<50 {
            let p = MotifGrid.randomPattern()
            XCTAssertEqual(p.count, 48)
            XCTAssertTrue(p.allSatisfy { (0...4).contains($0) })
        }
    }

    // MARK: – Quell-Verträge

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relative))
    }

    func testFreshLaunchStartsWithHabitCreationNotPermissionSetup() throws {
        let content = try source("Haiity/Views/ContentView.swift")
        let setup = try source("Haiity/Views/ReminderSetupView.swift")
        let more = try source("Haiity/Views/MoreView.swift")
        let bootStart = try XCTUnwrap(content.range(of: "private func boot() async"))
        let bootEnd = try XCTUnwrap(content.range(of: "private func rescheduleReminders() async",
                                                   range: bootStart.upperBound..<content.endIndex))
        let boot = String(content[bootStart.lowerBound..<bootEnd.lowerBound])

        XCTAssertTrue(content.contains("add-first-habit"))
        XCTAssertFalse(boot.contains("showReminderSetup = true"),
                       "a fresh launch must stay on the habit creation loop")
        XCTAssertFalse(boot.contains("requestAccess()"))
        XCTAssertFalse(boot.contains("ensurePermission()"))
        XCTAssertFalse(content.contains("ReminderSetup.shouldPresent"))
        XCTAssertFalse(setup.contains("completedKey"))
        XCTAssertTrue(more.contains("ReminderSetupView"),
                      "notification setup must remain reachable from More")
    }

    /// Beide Auftritte nutzen DASSELBE Raster — Leerzustand und Einrichtung
    /// driften sonst auseinander.
    func testEmptyStateAndSetupShareTheMotifGrid() throws {
        let content = try source("Haiity/Views/ContentView.swift")
        let setup = try source("Haiity/Views/ReminderSetupView.swift")
        XCTAssertTrue(content.contains("MotifGrid(pattern: pattern, palette: palette)"))
        XCTAssertTrue(setup.contains("MotifGrid(pattern: MotifGrid.brand"))
        // Kein zweites, eigenes Rasterbau-Duplikat mehr im Setup.
        XCTAssertFalse(setup.contains("LazyVGrid"))
    }

    /// Der gestaffelte Auftritt respektiert `reduceMotion`.
    func testMotifGridHonorsReduceMotion() throws {
        let grid = try source("Haiity/Views/MotifGrid.swift")
        XCTAssertTrue(grid.contains("accessibilityReduceMotion"))
        XCTAssertTrue(grid.contains("reduceMotion ? nil"))
    }

    /// Die Einrichtung ist ein Pager mit drei Seiten — und der Ausstieg
    /// „Jetzt nicht" steht im gemeinsamen Fuß, also auf JEDER Seite.
    func testSetupIsAThreePagePagerWithAlwaysReachableSkip() throws {
        let setup = try source("Haiity/Views/ReminderSetupView.swift")
        XCTAssertTrue(setup.contains("TabView(selection: $page)"))
        XCTAssertTrue(setup.contains(".tabViewStyle(.page(indexDisplayMode: .never))"))
        for tag in ["introPage.tag(0)", "summariesPage.tag(1)", "startPage.tag(2)"] {
            XCTAssertTrue(setup.contains(tag), tag)
        }
        // Die Kennungen, an denen UI-Automatisierung und Doku hängen.
        for id in ["\"setup-next\"", "\"enable-notifications\"",
                   "\"skip-notification-setup\"",
                   "\"setup-daily-toggle\"", "\"setup-weekly-toggle\""] {
            XCTAssertTrue(setup.contains(id), id)
        }
        // Der Ausstieg wohnt im Fuß, außerhalb der if-Verzweigung der Seiten.
        XCTAssertTrue(setup.contains("Button(String(localized: \"Jetzt nicht\")) { finish() }"))
    }

    func testSetupPagesUseTheAvailableHeightForBalancedLayout() throws {
        let setup = try source("Haiity/Views/ReminderSetupView.swift")

        XCTAssertTrue(setup.contains("GeometryReader"),
                      "setup pages need the actual available height to avoid top-heavy layouts")
        XCTAssertTrue(setup.contains("proxy.size.height"),
                      "the page container must react to the device and footer height")
        XCTAssertTrue(setup.contains("minHeight:"),
                      "short setup pages should center instead of leaving a blank lower half")
    }

    func testSetupPagesUseTopCompositionAndTransparentFooter() throws {
        let setup = try source("Haiity/Views/ReminderSetupView.swift")
        let footer = try XCTUnwrap(setup.range(of: "private var footer: some View"))
        let pageDots = try XCTUnwrap(setup.range(of: "            pageDots\n",
                                                  range: footer.upperBound..<setup.endIndex))
        let footerEnd = try XCTUnwrap(setup.range(of: "    /// Eigene Punkte",
                                                    range: pageDots.upperBound..<setup.endIndex))
        let footerSource = String(setup[footer.lowerBound..<footerEnd.lowerBound])
        XCTAssertTrue(setup.contains(".safeAreaInset(edge: .bottom) { footer }"))
        XCTAssertTrue(footerSource.contains(".background(.clear)"))
        XCTAssertFalse(footerSource.contains("appSurface"))
        XCTAssertTrue(footerSource.contains("pageDots"), "footer must own the page indicator")
        XCTAssertTrue(setup.contains("minHeight: max(0, proxy.size.height - Theme.Metrics.gutter * 2)"))
    }

    func testSetupUsesAppearanceAwareChromeAndReducedMotion() throws {
        let setup = try source("Haiity/Views/ReminderSetupView.swift")

        XCTAssertTrue(setup.contains("@Environment(\\.accessibilityReduceMotion)"),
                      "setup paging must honor the system motion setting")
        XCTAssertTrue(setup.contains(".pageHeaderChrome()"),
                      "setup navigation must keep the shared fading header material")
        XCTAssertTrue(setup.contains("withAnimation(reduceMotion ? nil"),
                      "next-page movement must stop animating when motion is reduced")
        XCTAssertTrue(setup.contains(".animation(reduceMotion ? nil"),
                      "page progress must stop animating when motion is reduced")
        XCTAssertTrue(setup.contains("accessibilityLabel(String(localized: \"Einrichtungsseite\"))"),
                      "VoiceOver needs a name for the page progress")
        XCTAssertTrue(setup.contains("accessibilityValue(String.localizedStringWithFormat"),
                      "VoiceOver needs the current page and total page count")
    }

    func testSetupControlsUseStableNativeHitTargets() throws {
        let setup = try source("Haiity/Views/ReminderSetupView.swift")

        XCTAssertTrue(setup.contains(".frame(minHeight: Theme.Metrics.settingsRowMinHeight"),
                      "setup cards need a readable minimum row height")
        XCTAssertTrue(setup.contains(".frame(minHeight: Theme.Metrics.hit"),
                      "permission rows must retain a native hit target")
        XCTAssertTrue(setup.contains("minHeight: Theme.Metrics.hit"),
                      "footer actions must remain reachable at normal and large type")
        XCTAssertTrue(setup.contains("accessibilityValue"),
                      "setup controls must expose their current state to VoiceOver")
    }

    func testSetupRequestsAllNativePermissionsUsedByTheApp() throws {
        let setup = try source("Haiity/Views/ReminderSetupView.swift")
        XCTAssertTrue(setup.contains("Reminders.ensurePermission()"))
        XCTAssertTrue(setup.contains("CalendarSync.requestAccess()"))
        XCTAssertTrue(setup.contains("ReminderSync.requestAccess()"))
        XCTAssertTrue(setup.contains("Berechtigungen aktivieren"))
    }

    /// Alle Texte des Einrichtungs-Bildschirms stehen im Katalog — die
    /// v16-Texte fehlten dort und fielen in allen 16 Sprachen auf Deutsch
    /// zurück.
    func testSetupStringsAreInTheCatalog() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Localizable.xcstrings"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        for key in ["Erinnerungen", "Dein Rhythmus", "Benachrichtigungen aktivieren",
                    "Jetzt nicht", "Weiter", "Zusammenfassungen", "Los geht's"] {
            XCTAssertNotNil(strings[key], "fehlt im Katalog: \(key)")
        }
    }
}
