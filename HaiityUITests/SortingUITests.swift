import XCTest

@MainActor
final class SortingUITests: XCTestCase {
    private let initialOrder = [700, 701, 702, 799] + Array(703...738)

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(enterSort: Bool = true, github: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-design-fixture", "sorting", "-screen", "habits", "-pro", "on",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_GB",
                               "-design-appearance", "light"]
        if github { app.launchArguments += ["-demo-github-card"] }
        // The app resolves this UUID within its own temporary directory. It
        // cannot name production data; only this test's relaunch reuses it.
        app.launchEnvironment["HAIITY_SORTING_FIXTURE_ID"] = UUID().uuidString
        app.launch()
        if enterSort { enterSorting(app) }
        return app
    }

    private func setDueToday(_ enabled: Bool, in app: XCUIApplication) {
        let filter = app.buttons["habit-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.tap()
        let due = app.descendants(matching: .any)["collection-due-today"].firstMatch
        XCTAssertTrue(due.waitForExistence(timeout: 5))
        let selected = due.isSelected || due.value as? String == "1"
        if selected != enabled { due.tap() } else { filter.tap() }
    }

    private func enterSorting(_ app: XCUIApplication) {
        let sort = app.buttons["reorder-habits"]
        XCTAssertTrue(sort.waitForExistence(timeout: 15))
        setDueToday(true, in: app)
        sort.tap()
        XCTAssertTrue(list(app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["finish-reordering"].isHittable)
        XCTAssertFalse(app.buttons["check-today"].exists)
    }

    private func identifier(_ id: Int) -> String {
        String(format: "sorting-row-00000000-0000-0000-0000-%012d", id)
    }

    func testRetainedSearchQueryDoesNotDisableCollectionSorting() {
        let app = launch(enterSort: false)
        let search = app.tabBars.buttons["Search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        // Submit releases the native keyboard while retaining the query.
        field.typeText("Read\n")
        let habits = app.tabBars.buttons["Habits"].firstMatch
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: habits)
        waitForExpectations(timeout: 5)
        habits.tap()
        let sort = app.buttons["reorder-habits"]
        XCTAssertTrue(sort.waitForExistence(timeout: 5))
        XCTAssertTrue(sort.isEnabled)
        sort.tap()
        XCTAssertTrue(app.buttons["finish-reordering"].waitForExistence(timeout: 5))
        app.buttons["finish-reordering"].tap()
        app.tabBars.buttons["Search"].firstMatch.tap()
        XCTAssertEqual(field.value as? String, "Read")
    }

    private func row(_ id: Int, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier(id)].firstMatch
    }

    private func list(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["habit-sorting-active"].firstMatch
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func reveal(_ id: Int, in app: XCUIApplication, towardBottom: Bool) {
        let target = row(id, in: app)
        let native = app.cells.containing(.any, identifier: identifier(id)).firstMatch.buttons.firstMatch
        for _ in 0..<40 {
            if native.exists && native.isHittable,
               native.frame.midY > app.navigationBars.firstMatch.frame.maxY + 4,
               native.frame.midY < app.tabBars.firstMatch.frame.minY - 4 { break }
            if towardBottom { list(app).swipeUp(velocity: .slow) }
            else { list(app).swipeDown(velocity: .slow) }
        }
        XCTAssertTrue(native.isHittable, "could not scroll to the handle for \(identifier(id))")
        // isHittable can be true for a clipped button whose rectangle center
        // lies behind chrome. The drag uses that center, so verify it too.
        XCTAssertGreaterThan(native.frame.midY, app.navigationBars.firstMatch.frame.maxY + 4)
        XCTAssertLessThan(native.frame.midY, app.tabBars.firstMatch.frame.minY - 4)
        XCTAssertGreaterThan(target.frame.height, 0)
    }

    private func handle(_ id: Int, in app: XCUIApplication) -> XCUICoordinate {
        let cell = app.cells.containing(.any, identifier: identifier(id)).firstMatch
        XCTAssertTrue(cell.exists, "the native cell must identify its item")
        // The owned table supplies one native reorder button per cell. Use
        // that actual target in either layout direction, regardless of labels.
        let native = cell.buttons.firstMatch
        XCTAssertTrue(native.isHittable, "the native reorder handle must be reachable")
        return native.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    }

    private func assertOrder(_ expected: [Int], in app: XCUIApplication,
                             file: StaticString = #filePath, line: UInt = #line) {
        func rows(in snapshot: any XCUIElementSnapshot) -> [(identifier: String, frame: CGRect)] {
            let own = snapshot.identifier.hasPrefix("sorting-row-")
                ? [(identifier: snapshot.identifier, frame: snapshot.frame)] : []
            return own + snapshot.children.flatMap { rows(in: $0) }
        }
        // The original first item stays within the first screen in these
        // scenarios. Anchoring on the expected winner hides preceding rows
        // when a drop lands incorrectly in the middle of the list.
        reveal(initialOrder[0], in: app, towardBottom: false)
        list(app).swipeDown(velocity: .slow)
        var observed: [String] = []
        for _ in 0..<40 {
            let bounds = list(app).frame.intersection(app.frame)
            let top = max(bounds.minY, app.navigationBars.firstMatch.frame.maxY)
            let bottom = min(bounds.maxY, app.tabBars.firstMatch.frame.minY)
            // Index-bound live elements can resolve against different trees
            // between identifier and frame reads as native cells are reused.
            // A public snapshot pairs every identity with its actual geometry.
            guard let snapshot = try? list(app).snapshot() else {
                XCTFail("could not capture the sorting rows", file: file, line: line)
                return
            }
            let visible = rows(in: snapshot)
                // Observe read-only labels by geometry, not activation points.
                // Actual drag targets are checked through their native buttons.
                .filter { $0.frame.height > 0 && $0.frame.midY > top && $0.frame.midY < bottom }
                .sorted { $0.frame.minY < $1.frame.minY }
            for item in visible where !observed.contains(item.identifier) {
                observed.append(item.identifier)
            }
            if observed.count >= expected.count { break }
            // Overlapping half-screen scrolls observe every row, including
            // multiline names, without relying on offscreen estimated frames.
            let start = list(app).coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.75))
            let end = list(app).coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.4))
            start.press(forDuration: 0.01, thenDragTo: end,
                        withVelocity: .slow, thenHoldForDuration: 0)
        }
        XCTAssertEqual(observed, expected.map(identifier), file: file, line: line)
    }

    private func relaunch(_ app: XCUIApplication, expecting order: [Int]) {
        app.terminate()
        app.launch()
        enterSorting(app)
        assertOrder(order, in: app)
    }

    func testGitHubStaysFixedAboveMovableEntries() {
        let app = launch(github: true)
        let fixed = app.descendants(matching: .any)["sorting-github-fixed"].firstMatch
        XCTAssertTrue(fixed.waitForExistence(timeout: 5))
        XCTAssertLessThan(fixed.frame.minY, row(700, in: app).frame.minY)
        XCTAssertEqual(app.cells.containing(.any, identifier: "sorting-github-fixed").count, 0)
        XCTAssertFalse(app.descendants(matching: .any)["github-contribution-card"].exists)
        XCTAssertFalse(app.buttons["github-open-profile"].exists)
        XCTAssertFalse(app.buttons["check-today"].exists)
        capture("sorting-fixed-github")
        app.buttons["finish-reordering"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["github-contribution-card"].waitForExistence(timeout: 5))
    }

    func testBottomToTopAndBackSurvivesReload() {
        let app = launch()
        assertOrder(initialOrder, in: app) // Idle scrolling must not reorder.
        reveal(738, in: app, towardBottom: true)
        capture("sorting-bottom-to-top-before")
        let topGrabber = handle(738, in: app)
        let top = max(list(app).frame.minY, app.navigationBars.firstMatch.frame.maxY) + 12
        let topEdge = app.coordinate(withNormalizedOffset: .zero)
            // Move out of the trailing grabber gutter into the native row's
            // scrolling area, matching the successful native edge-hold pilot.
            .withOffset(CGVector(dx: list(app).frame.midX, dy: top))
        // The hold must cover the whole fixture, not assume a fixed native
        // edge-scroll speed. There is still only one grab and one final drop.
        topGrabber.press(forDuration: 1, thenDragTo: topEdge,
                         withVelocity: .slow, thenHoldForDuration: 30)
        let moved = [738] + Array(initialOrder.dropLast())
        capture("sorting-bottom-to-top-after")
        assertOrder(moved, in: app)
        relaunch(app, expecting: moved)

        reveal(738, in: app, towardBottom: false)
        capture("sorting-top-to-bottom-before")
        let bottomGrabber = handle(738, in: app)
        let bottom = min(list(app).frame.maxY, app.tabBars.firstMatch.frame.minY) - 12
        let bottomEdge = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: list(app).frame.midX, dy: bottom))
        bottomGrabber.press(forDuration: 1, thenDragTo: bottomEdge,
                            withVelocity: .slow, thenHoldForDuration: 30)
        capture("sorting-top-to-bottom-after")
        assertOrder(initialOrder, in: app)
        relaunch(app, expecting: initialOrder)
        capture("sorting-restored-after-reload")
        app.buttons["finish-reordering"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["habit-list"].firstMatch.waitForExistence(timeout: 5))
    }

    func testFastDropsAndNoOpPreserveExactOrder() {
        let app = launch()
        var order = initialOrder
        // Cross several rows in both directions, using interior targets so
        // edge scrolling cannot move the target while the gesture is in flight.
        // Endpoint/edge holds are verified separately by the long-drag test.
        for targetID in [704, 799] {
            let targetIndex = order.firstIndex(of: targetID)!
            let targetIsBelow = targetIndex > order.firstIndex(of: 700)!
            reveal(700, in: app, towardBottom: false)
            reveal(targetID, in: app, towardBottom: targetIsBelow)
            XCTAssertTrue(row(700, in: app).isHittable)
            XCTAssertTrue(row(targetID, in: app).isHittable)
            capture("sorting-fast-drop-\(targetID)-before")
            let grabber = handle(700, in: app)
            let cell = app.cells.containing(.any, identifier: identifier(targetID)).firstMatch
            XCTAssertTrue(cell.exists, "drop geometry must come from the full native cell")
            let frame = cell.frame
            XCTAssertGreaterThan(frame.width, 0)
            let target = cell.coordinate(withNormalizedOffset:
                CGVector(dx: (grabber.screenPoint.x - frame.minX) / frame.width, dy: 0.9))
            grabber.press(forDuration: 0.4, thenDragTo: target,
                          withVelocity: .fast, thenHoldForDuration: 0)
            order.removeAll { $0 == 700 }
            // Native movement targets a row slot: upward movement lands before
            // that item, downward movement after it as preceding rows shift.
            order.insert(700, at: targetIndex)
            capture("sorting-fast-drop-\(targetID)-after")
            assertOrder(order, in: app)
        }
        reveal(700, in: app, towardBottom: false)
        let original = handle(700, in: app)
        original.press(forDuration: 0.4, thenDragTo: original,
                       withVelocity: .slow, thenHoldForDuration: 0.4)
        assertOrder(order, in: app)
        relaunch(app, expecting: order)
    }

    func testNavigationAndBackgroundRecoveryKeepCompletedOrder() {
        let app = launch()
        let grabber = handle(799, in: app)
        let cell = app.cells.containing(.any, identifier: identifier(702)).firstMatch
        XCTAssertTrue(cell.exists)
        let frame = cell.frame
        XCTAssertGreaterThan(frame.width, 0)
        let target = cell.coordinate(withNormalizedOffset:
            CGVector(dx: (grabber.screenPoint.x - frame.minX) / frame.width, dy: 0.1))
        grabber.press(forDuration: 0.4, thenDragTo: target,
                      withVelocity: .fast, thenHoldForDuration: 0)
        let saved = [700, 701, 799, 702] + Array(703...738)
        assertOrder(saved, in: app)
        reveal(700, in: app, towardBottom: false)
        let original = handle(700, in: app)
        original.press(forDuration: 0.4, thenDragTo: original,
                       withVelocity: .slow, thenHoldForDuration: 0)
        // XCUITest's public drag is synchronous: it releases before another
        // action can run. This tests recovery, NOT cancellation while held.
        capture("sorting-before-background")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.descendants(matching: .any)["habit-list"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["finish-reordering"].exists)
        enterSorting(app)
        assertOrder(saved, in: app)
        reveal(700, in: app, towardBottom: false)
        let progress = app.tabBars.buttons["Progress"].firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 3))
        progress.tap()
        XCTAssertTrue(app.descendants(matching: .any)["stats-week-card"].firstMatch.waitForExistence(timeout: 5))
        let settings = app.buttons["open-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()
        XCTAssertTrue(app.buttons["open-appearance"].waitForExistence(timeout: 5))
        app.buttons["close-more-sheet"].tap()
        app.tabBars.buttons["Habits"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["habit-list"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["finish-reordering"].exists)
        enterSorting(app)
        assertOrder(saved, in: app)
        relaunch(app, expecting: saved)
        capture("sorting-after-background-navigation-reload")
        app.buttons["finish-reordering"].tap()
        XCTAssertTrue(app.buttons["reorder-habits"].isHittable)
    }

    private func reduceMotionSwitch(in settings: XCUIApplication) -> XCUIElement {
        let control = settings.switches["Reduce Motion"].firstMatch
        if control.exists { return control }
        for _ in 0..<6 {
            if settings.navigationBars["Settings"].exists { break }
            let back = settings.navigationBars.buttons.firstMatch
            if !back.exists { break }
            back.tap()
        }
        let accessibility = settings.descendants(matching: .any)["Accessibility"].firstMatch
        for _ in 0..<8 where !accessibility.isHittable { settings.swipeUp(velocity: .slow) }
        XCTAssertTrue(accessibility.isHittable, "Settings must expose Accessibility")
        accessibility.tap()
        let motion = settings.descendants(matching: .any)["Motion"].firstMatch
        XCTAssertTrue(motion.waitForExistence(timeout: 5))
        for _ in 0..<6 where !motion.isHittable { settings.swipeUp(velocity: .slow) }
        XCTAssertTrue(motion.isHittable)
        motion.tap()
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        return control
    }

    func testCompactRTLAndLargestTextRestoresOrderAfterDone() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Settings setup belongs only on the isolated compact simulator")
        #endif
        let app = XCUIApplication()
        app.launchArguments = ["-design-fixture", "mixed", "-screen", "habits", "-pro", "on",
                               "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                               "-design-material", "solid", "-design-appearance", "light"]
        app.launch()
        XCTAssertLessThanOrEqual(app.frame.width, 375, "Run this focused gate on the compact SE")
        XCTAssertLessThanOrEqual(app.frame.height, 667, "Run this focused gate on the compact SE")

        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
        settings.launch()
        let reduceMotion = reduceMotionSwitch(in: settings)
        let originalMotion = try XCTUnwrap(reduceMotion.value as? String)
        XCTAssertTrue(["0", "1"].contains(originalMotion))
        // XCTest teardown still restores the simulator setting after a failed
        // assertion or audit. Never write host or private accessibility prefs.
        addTeardownBlock {
            await MainActor.run {
                settings.activate()
                // Settings may restart at its root after being backgrounded.
                let restoredControl = self.reduceMotionSwitch(in: settings)
                if restoredControl.value as? String != originalMotion {
                    restoredControl.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
                }
                XCTAssertEqual(restoredControl.value as? String, originalMotion)
                settings.terminate()
            }
        }
        if originalMotion == "0" {
            reduceMotion.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"),
                                                 object: reduceMotion)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed,
                       "the simulator's Reduce Motion setting must be enabled")
        app.activate()
        enterSorting(app)
        for (id, name) in [(700, "Read for twenty minutes"), (702, "Take a walk"),
                           (799, "Call the dentist")] {
            reveal(id, in: app, towardBottom: true)
            let element = row(id, in: app)
            let frame = element.frame
            XCTAssertTrue(element.label.contains(name), "the combined row must expose its name")
            XCTAssertGreaterThanOrEqual(frame.height, 44)
            XCTAssertGreaterThanOrEqual(frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(frame.maxX, app.frame.maxX)
            let cell = app.cells.containing(.any, identifier: identifier(id)).firstMatch
            XCTAssertTrue(cell.exists)
            let native = cell.buttons.firstMatch
            XCTAssertTrue(native.isHittable, "the native handle must be reachable at largest text")
            XCTAssertTrue(native.label.contains(name), "the native handle must identify its item")
            XCTAssertLessThan(native.frame.midX, frame.midX, "RTL must put the handle on the left")
        }
        capture("sorting-compact-arabic-largest-text-solid-reduced-motion")
        // Public iOS audit types do not expose custom VoiceOver action names.
        // Audit actual labels, clipping and targets without exempting the handle.
        try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription, .textClipped])

        reveal(700, in: app, towardBottom: false)
        reveal(701, in: app, towardBottom: true)
        XCTAssertTrue(row(700, in: app).isHittable)
        let grabber = handle(700, in: app)
        let cell = app.cells.containing(.any, identifier: identifier(701)).firstMatch
        XCTAssertTrue(cell.exists)
        let frame = cell.frame
        XCTAssertGreaterThan(frame.width, 0)
        let target = cell.coordinate(withNormalizedOffset:
            CGVector(dx: (grabber.screenPoint.x - frame.minX) / frame.width, dy: 0.5))
        grabber.press(forDuration: 0.4, thenDragTo: target,
                      withVelocity: .fast, thenHoldForDuration: 0)
        let moved = [701, 700, 702, 799]
        assertOrder(moved, in: app)
        app.buttons["finish-reordering"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["habit-list"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["finish-reordering"].exists)
        XCTAssertTrue(app.buttons["check-today"].firstMatch.waitForExistence(timeout: 5),
                      "Done must restore normal completion controls")
        let details = app.buttons["item-details-00000000-0000-0000-0000-000000000799"]
        for _ in 0..<10 where !details.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(details.isHittable, "Done must restore normal reminder details")
        XCTAssertTrue(details.isEnabled)
        capture("sorting-compact-done-restores-editing")
        details.tap()
        let edit = app.buttons["edit-habit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let name = app.textFields["habit-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue((name.value as? String)?.hasPrefix("Call the dentist") == true)
        app.buttons["close-create"].tap()
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(app.buttons["reorder-habits"].waitForExistence(timeout: 5))
        enterSorting(app)
        assertOrder(moved, in: app)
        capture("sorting-compact-reentry-preserves-order")
        app.buttons["finish-reordering"].tap()
    }

    func testFullCardScrollPerformance() {
        let app = launch(enterSort: false)
        XCTAssertTrue(app.buttons["check-today"].firstMatch.waitForExistence(timeout: 15))
        setDueToday(true, in: app)
        let scroll = app.descendants(matching: .any)["habit-list"].firstMatch
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
            for _ in 0..<3 {
                scroll.swipeUp()
                scroll.swipeDown()
            }
        }
    }

    func testSortingRowsRemainReadableOverPhotosInLightAndDarkMode() throws {
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments = ["-design-fixture", "mixed", "-screen", "habits", "-pro", "on",
                                   "-AppleLanguages", "(en)", "-AppleLocale", "en_GB",
                                   "-design-material", "milky", "-design-photo",
                                   "-design-appearance", appearance]
            app.launch()
            enterSorting(app)
            for id in [700, 799] {
                reveal(id, in: app, towardBottom: true)
                let cell = app.cells.containing(.any, identifier: identifier(id)).firstMatch
                XCTAssertTrue(cell.buttons.firstMatch.isHittable)
                XCTAssertFalse(row(id, in: app).label.isEmpty)
            }
            capture("sorting-photo-\(appearance)")
            let top = app.navigationBars.firstMatch.frame.maxY
            let bottom = app.tabBars.firstMatch.frame.minY
            try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription]) { issue in
                // Native glass toolbar text fails iOS 27's contrast audit even
                // when black on white. Contrast here covers rows and handles;
                // descriptions and touch targets still cover the whole screen.
                guard issue.auditType == .contrast, let element = issue.element else { return false }
                return element.frame.maxY <= top || element.frame.minY >= bottom
            }
            app.buttons["finish-reordering"].tap()
            XCTAssertTrue(app.buttons["check-today"].firstMatch.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testCompactSortingScrollPerformance() {
        let app = launch()
        XCTAssertTrue(row(700, in: app).waitForExistence(timeout: 5))
        let scroll = list(app)
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
            for _ in 0..<3 {
                scroll.swipeUp()
                scroll.swipeDown()
            }
        }
    }
}
