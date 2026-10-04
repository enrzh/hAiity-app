import XCTest

@MainActor
final class TodayProgressUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(_ fixture: String = "realistic", largeText: Bool = false,
                        appearance: String = "light", screen: String = "habits",
                        material: String? = nil, photo: Bool = false,
                        account: String? = nil, github: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-design-fixture", fixture, "-screen", screen, "-pro", "on",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_GB",
                               "-design-appearance", appearance]
        if let material { app.launchArguments += ["-design-material", material] }
        if photo { app.launchArguments += ["-design-photo"] }
        if let account { app.launchArguments += ["-design-account", account] }
        if github { app.launchArguments += ["-demo-github-card"] }
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func selectTab(_ title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[title].firstMatch
        if !tab.exists {
            let collapsed = app.tabBars.buttons.matching(NSPredicate(format: "value == 'Collapsed'")).firstMatch
            if collapsed.exists { collapsed.tap() }
        }
        XCTAssertTrue(tab.waitForExistence(timeout: 3))
        tab.tap()
    }

    func testColdLaunchResponsivenessWithCrowdedData() {
        let app = XCUIApplication()
        app.launchArguments = ["-design-fixture", "crowded", "-screen", "habits", "-pro", "on"]
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            app.launch()
            XCTAssertTrue(app.buttons["check-today"].firstMatch.waitForExistence(timeout: 15))
            app.terminate()
        }
    }

    func testRepeatedNavigationAndScrollingStayInteractive() {
        let app = launch("crowded")
        XCTAssertTrue(app.buttons["check-today"].firstMatch.waitForExistence(timeout: 15))
        for _ in 0..<3 {
            selectTab("Stats", in: app)
            let week = app.descendants(matching: .any)["stats-week-card"].firstMatch
            XCTAssertTrue(week.waitForExistence(timeout: 5))
            app.swipeUp()
            XCTAssertTrue(app.descendants(matching: .any)["stats-row"].firstMatch.waitForExistence(timeout: 5))
            selectTab("Habits", in: app)
            app.swipeUp()
            app.swipeDown()
            XCTAssertTrue(app.buttons["habit-filter"].firstMatch.isHittable)
        }
    }

    func testFirstHabitCanBeCreatedAndCheckedWithoutSetup() {
        let app = launch("empty")
        let create = app.buttons["add-first-habit"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        create.tap()
        let name = app.textFields["habit-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Read a page\n")
        XCTAssertFalse(app.descendants(matching: .any)["end-mode-picker"].exists)
        capture("simple-habit-creation")
        app.buttons["save-habit"].tap()
        let check = app.buttons["check-today"].firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["habit-name"].exists)
        XCTAssertEqual(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.count, 0)
        let grid = app.descendants(matching: .any)["contribution-grid"].firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        let before = grid.label
        check.tap()
        expectation(for: NSPredicate(format: "label != %@", before), evaluatedWith: grid)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.buttons["undo-action"].isHittable)
        capture("first-habit-grid-feedback")
    }

    func testRejectedCreationSaveKeepsDraftAndAllowsRetry() {
        let app = XCUIApplication()
        app.launchArguments = ["-design-fixture", "empty", "-design-write-conflict", "-pro", "on",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
        app.launch()
        let create = app.buttons["add-first-habit"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        create.tap()
        let name = app.textFields["habit-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Keep this draft\n")
        app.buttons["save-habit"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.firstMatch.buttons["OK"].tap()
        XCTAssertEqual(name.value as? String, "Keep this draft")
        XCTAssertTrue(app.buttons["save-habit"].isEnabled)
        capture("creation-save-conflict-recovery")
        app.buttons["save-habit"].tap()
        XCTAssertTrue(app.buttons["check-today"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(name.exists)
    }

    func testDailyEntriesPrecedeGitHubAndGitHubOnlyStateOffersCreation() {
        let app = launch(github: true)
        let check = app.buttons["check-today"].firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 15))
        XCTAssertTrue(check.isHittable)
        let github = app.descendants(matching: .any)["github-contribution-card"].firstMatch
        XCTAssertFalse(github.isHittable, "optional activity must follow the actionable entries")
        capture("daily-actions-before-github")
        for _ in 0..<12 where !github.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(github.isHittable)
        capture("github-after-daily-entries")
        app.terminate()

        let empty = launch("empty", github: true)
        let create = empty.buttons["add-first-habit"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        XCTAssertTrue(create.isHittable)
        create.tap()
        XCTAssertTrue(empty.textFields["habit-name"].waitForExistence(timeout: 5))
    }

    func testDeepLinkDismissesAnUnsavedEditorBeforeOpeningStatsOrCreation() {
        let app = XCUIApplication()
        app.launchArguments = ["-design-fixture", "mixed", "-pro", "on",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
        app.launch()
        let edit = app.buttons["reminder-edit-00000000-0000-0000-0000-000000000799"]
        XCTAssertTrue(app.buttons["check-today"].firstMatch.waitForExistence(timeout: 15))
        for _ in 0..<10 where !edit.isHittable { app.swipeUp(velocity: .slow) }
        edit.tap()
        let name = app.textFields["habit-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let savedName = name.value as? String
        name.tap()
        name.typeText(" unsaved")
        app.open(URL(string: "haiity://stats")!)
        XCTAssertTrue(app.descendants(matching: .any)["stats-week-card"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(name.exists)
        app.open(URL(string: "haiity://habits")!)
        for _ in 0..<12 where !edit.isHittable { app.swipeUp(velocity: .slow) }
        edit.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, savedName, "routing must discard, not save, an unfinished draft")
        app.open(URL(string: "haiity://new")!)
        XCTAssertTrue(app.buttons["close-create"].waitForExistence(timeout: 5))
        XCTAssertTrue(name.exists)
        XCTAssertFalse(app.buttons["save-habit"].isEnabled)
        capture("deep-link-new-after-editor")
    }

    func testPhotoBackgroundKeepsReminderAndSettingsControlsReadable() {
        for appearance in ["light", "dark"] {
            let app = launch("mixed", appearance: appearance, material: "milky", photo: true)
            let edit = app.buttons["reminder-edit-00000000-0000-0000-0000-000000000799"]
            XCTAssertTrue(app.buttons["check-today"].firstMatch.waitForExistence(timeout: 15))
            for _ in 0..<10 where !edit.isHittable { app.swipeUp() }
            XCTAssertTrue(edit.isHittable)
            capture("photo-reminder-\(appearance)")
            selectTab("More", in: app)
            let settings = app.buttons["open-appearance"].firstMatch
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            settings.tap()
            XCTAssertTrue(app.descendants(matching: .any)["appearance-picker"].firstMatch
                .waitForExistence(timeout: 5))
            capture("photo-settings-\(appearance)")
            app.terminate()
        }
    }

    func testReminderEditButtonPreservesCompletionAtBothTextSizes() {
        let reminderID = "00000000-0000-0000-0000-000000000799"
        for largeText in [false, true] {
            let app = launch("mixed", largeText: largeText, appearance: "dark")
            let edit = app.buttons["reminder-edit-\(reminderID)"]
            XCTAssertTrue(app.buttons["check-today"].firstMatch.waitForExistence(timeout: 15))
            for _ in 0..<10 where !edit.isHittable { app.swipeUp() }
            XCTAssertTrue(edit.isHittable)
            XCTAssertGreaterThanOrEqual(edit.frame.width, 44)
            XCTAssertGreaterThanOrEqual(edit.frame.height, 44)
            let check = app.buttons["reminder-check-\(reminderID)"]
            let before = check.value as? String
            capture(largeText ? "reminder-large-text" : "reminder-edit-control")
            edit.tap()
            XCTAssertTrue(app.textFields["habit-name"].waitForExistence(timeout: 5))
            XCTAssertTrue((app.textFields["habit-name"].value as? String)?.hasPrefix("Call the dentist") == true)
            app.buttons["Cancel"].firstMatch.tap()
            XCTAssertTrue(check.waitForExistence(timeout: 5))
            XCTAssertEqual(check.value as? String, before, "editing must not complete the reminder")
            app.terminate()
        }
    }

    func testAccessibilityUndoStaysAvailableAndRestoresTheCheckIn() {
        let app = launch(largeText: true, appearance: "dark")
        let check = app.buttons["check-today"].firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 15))
        let title = app.staticTexts["Habits"].firstMatch
        let summary = app.descendants(matching: .any)["today-progress"].firstMatch
        XCTAssertLessThanOrEqual(title.frame.maxY, summary.frame.minY,
                                 "the large root title must not overlap the next section")
        for _ in 0..<5 where !check.isHittable { app.swipeUp() }
        let before = check.label
        check.tap()
        let undo = app.buttons["undo-action"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        // Longer than the ordinary expiry. This is a timed UX contract.
        RunLoop.current.run(until: Date().addingTimeInterval(7))
        XCTAssertTrue(undo.isHittable)
        capture("accessible-undo")
        undo.tap()
        XCTAssertEqual(check.label, before)
    }

    func testScrollingClosesReminderSwipeAndLeavesItsEditButtonUsable() {
        let app = launch("mixed")
        let reminderID = "00000000-0000-0000-0000-000000000799"
        let edit = app.buttons["reminder-edit-\(reminderID)"]
        XCTAssertTrue(app.buttons["check-today"].firstMatch.waitForExistence(timeout: 15))
        for _ in 0..<10 where !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(edit.isHittable)
        let row = app.descendants(matching: .any)["reminder-row-\(reminderID)"].firstMatch
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        let end = row.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        XCTAssertTrue(row.buttons["reveal-action-done"].waitForExistence(timeout: 3))
        app.swipeDown()
        for _ in 0..<5 where !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(edit.isHittable, "vertical scrolling must close the reveal layer")
        edit.tap()
        XCTAssertTrue(app.textFields["habit-name"].waitForExistence(timeout: 5))
    }

    func testRedesignRootAndSecondaryPagesInBothAppearances() {
        for appearance in ["light", "dark"] {
            let app = launch("crowded", appearance: appearance, screen: "more")
            let settings = app.buttons["open-appearance"].firstMatch
            XCTAssertTrue(settings.waitForExistence(timeout: 15))
            XCTAssertTrue(settings.isHittable)
            capture("redesign-more-\(appearance)")
            settings.tap()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
            capture("redesign-appearance-\(appearance)")
            app.terminate()

            let stats = launch("crowded", appearance: appearance, screen: "stats")
            let weekly = stats.descendants(matching: .any)["stats-week-card"].firstMatch
            XCTAssertTrue(weekly.waitForExistence(timeout: 15))
            capture("redesign-stats-\(appearance)")
            stats.swipeUp()
            XCTAssertTrue(stats.descendants(matching: .any)["stats-row"].firstMatch
                .waitForExistence(timeout: 5))
            capture("redesign-stats-ranking-\(appearance)")
            stats.terminate()
        }
    }

    func testContributionChartLightAndDarkScreenshots() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance)
            XCTAssertTrue(app.buttons["check-today"].firstMatch.waitForExistence(timeout: 15))
            capture("contribution-chart-\(appearance)")
            app.descendants(matching: .any)["habit-history"].firstMatch.tap()
            XCTAssertTrue(app.buttons["backfill-close"].waitForExistence(timeout: 5),
                      "the history sheet did not open")
            app.buttons["history-previous-month"].tap()
            capture("history-editor-\(appearance)")
            app.terminate()
        }
    }

    /// iOS 27 drops taps on grouped `List` rows, so the settings sub-pages were
    /// moved to the hub's continuous group surface. This drives the real taps so
    /// a regression back to `List` fails here instead of on a user's phone.
    func testMigratedSettingsPagesKeepTheirRowsHittable() {
        let pages: [(row: String, target: String, name: String)] = [
            ("open-notifications", "dnd-toggle", "migrated-notifications"),
            ("open-account", "personal-alias", "migrated-account"),
            ("connect-github", "github-username-toggle", "github-login-action"),
            ("open-github-settings", "github-username-toggle", "migrated-github"),
            ("open-github-settings", "github-month-labels-toggle", "migrated-github-months")
        ]

        for page in pages {
            let app = launch("crowded", screen: "more")
            let row = app.buttons[page.row].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 15), page.row)
            XCTAssertTrue(row.isHittable, page.row)
            row.tap()

            let target = app.descendants(matching: .any)[page.target].firstMatch
            XCTAssertTrue(target.waitForExistence(timeout: 10), page.target)
            XCTAssertTrue(target.isHittable,
                          "\(page.target) must stay tappable after moving off List")
            capture(page.name)
            app.terminate()
        }
    }

    func testAppleAccountPageHasLivePersonalizationAndIndependentHubActions() {
        for appearance in ["light", "dark"] {
            let app = launch("crowded", appearance: appearance, screen: "more", account: "connected")
            let account = app.buttons["open-account"]
            XCTAssertTrue(account.waitForExistence(timeout: 20))
            for _ in 0..<8 where !account.isHittable { app.swipeUp() }
            let hubSignOut = app.buttons["apple-signout-more"]
            XCTAssertTrue(hubSignOut.waitForExistence(timeout: 10))
            for _ in 0..<5 where !hubSignOut.isHittable { app.swipeUp() }
            XCTAssertTrue(hubSignOut.isHittable)
            capture("apple-account-more-\(appearance)")
            account.tap()
            let alias = app.textFields["personal-alias"]
            XCTAssertTrue(alias.waitForExistence(timeout: 15))
            XCTAssertEqual(alias.value as? String, "Alex")
            // Cloud workers may keep the development-region UI language; match
            // the greeting by content rather than a single localized string.
            assertGreeting(in: app, contains: "Alex")
            XCTAssertFalse(app.buttons["copy-unrecognized-apple-user-id"].exists)
            XCTAssertFalse(app.staticTexts["fixture-apple-account"].exists)
            let preview = app.descendants(matching: .any)["account-motivation-preview"].firstMatch
            XCTAssertTrue(preview.waitForExistence(timeout: 10))
            XCTAssertTrue(preview.label.contains("Alex"))
            capture("apple-account-connected-\(appearance)")
            alias.tap()
            alias.typeText(" Taylor")
            assertGreeting(in: app, contains: "Alex Taylor", timeout: 10)
            XCTAssertTrue(preview.label.contains("Alex Taylor"), "the preview must use the edited alias immediately")
            dismissAccountKeyboard(in: app)
            XCTAssertTrue(app.buttons["apple-signout-more"].waitForExistence(timeout: 15))
            app.buttons["apple-signout-more"].tap()
            XCTAssertTrue(app.buttons["apple-signin-more"].waitForExistence(timeout: 15),
                          "logout on the hub must expose native sign-in without opening the account page")
            account.tap()
            XCTAssertTrue(alias.waitForExistence(timeout: 15))
            XCTAssertEqual(alias.value as? String, "Alex Taylor", "sign-out must keep the local alias")
            assertGreeting(in: app, contains: "Alex Taylor")
            app.terminate()
        }
    }

    private func assertGreeting(in app: XCUIApplication, contains name: String, timeout: TimeInterval = 10) {
        let greeting = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ AND (label BEGINSWITH %@ OR label BEGINSWITH %@)",
                        name, "Hello,", "Hallo,")
        ).firstMatch
        XCTAssertTrue(greeting.waitForExistence(timeout: timeout),
                      "expected a Hello/Hallo greeting containing \(name)")
    }

    private func dismissAccountKeyboard(in app: XCUIApplication) {
        let done = app.buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "Done", "Fertig")
        ).firstMatch
        if done.waitForExistence(timeout: 3) {
            done.tap()
            return
        }
        // Keyboard accessory may be absent on Cloud; dismiss by ending editing.
        app.swipeDown()
    }

    func testAppleAccountControlsRemainUsableWithLargeTextAndSolidAppearance() {
        let app = launch("crowded", largeText: true, appearance: "dark", screen: "more", material: "solid")
        let account = app.buttons["open-account"]
        XCTAssertTrue(account.waitForExistence(timeout: 15))
        for _ in 0..<8 where !account.isHittable { app.swipeUp() }
        let signIn = app.buttons["apple-signin-more"]
        for _ in 0..<3 where !signIn.isHittable { app.swipeUp() }
        XCTAssertTrue(signIn.isHittable)
        XCTAssertGreaterThanOrEqual(signIn.frame.width, 140)
        XCTAssertGreaterThanOrEqual(signIn.frame.height, 44)
        capture("apple-account-more-large-text")
        account.tap()
        let alias = app.textFields["personal-alias"]
        XCTAssertTrue(alias.waitForExistence(timeout: 5))
        for _ in 0..<5 where !alias.isHittable { app.swipeUp() }
        XCTAssertTrue(alias.isHittable)
        capture("apple-account-large-text")
        let pageSignIn = app.buttons["apple-signin"]
        for _ in 0..<8 where !pageSignIn.isHittable { app.swipeUp() }
        XCTAssertTrue(pageSignIn.isHittable)
        XCTAssertGreaterThanOrEqual(pageSignIn.frame.height, 44)
        capture("apple-account-signin-large-text")
    }

    /// Behavior & sharing is the densest settings page in the app: five groups
    /// of toggles, pickers and action rows, all of them tap targets. This taps
    /// one for real so a regression back to `List` cannot pass silently.
    func testBehaviorPageTogglesStayTappableAfterLeavingTheList() {
        let app = launch("crowded", screen: "notification-actions")
        let autoArchive = app.switches["auto-archive-completed-items-toggle"].firstMatch
        XCTAssertTrue(autoArchive.waitForExistence(timeout: 15))
        XCTAssertTrue(autoArchive.isHittable)

        let before = (autoArchive.value as? String) ?? ""
        autoArchive.tap()
        XCTAssertNotEqual((autoArchive.value as? String) ?? "", before,
                          "the archive toggle must actually respond to a tap")

        // The calendar group sits below the fold, so scroll to it first: a
        // control that is off-screen is not in the accessibility tree yet.
        app.swipeUp()
        app.swipeUp()
        for identifier in ["calendar-sync-habits-toggle",
                           "calendar-sync-reminders-toggle"] {
            let control = app.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 5), identifier)
            XCTAssertTrue(control.isHittable, identifier)
        }
        capture("migrated-behavior")
    }

    /// The design system requires every shared component to survive AX5 without
    /// clipped or hidden text. The statistics captions and the notification
    /// rows lost their `lineLimit(1)` for exactly this reason, so it needs a
    /// look at the largest text size, not just a source assertion.
    func testMigratedPagesSurviveAccessibilityTextSize() {
        let stats = launch("crowded", largeText: true, appearance: "dark", screen: "stats")
        XCTAssertTrue(stats.descendants(matching: .any)["stats-today-summary"]
            .firstMatch.waitForExistence(timeout: 15))
        capture("a11y-ax5-stats-dark")

        let more = launch("crowded", largeText: true, appearance: "dark", screen: "more")
        let notifications = more.buttons["open-notifications"].firstMatch
        XCTAssertTrue(notifications.waitForExistence(timeout: 15))
        XCTAssertTrue(notifications.isHittable,
                      "a hub row must stay hittable when its label wraps to several lines")
        capture("a11y-ax5-more-dark")
        notifications.tap()
        XCTAssertTrue(more.descendants(matching: .any)["dnd-toggle"]
            .firstMatch.waitForExistence(timeout: 10))
        capture("a11y-ax5-notifications-dark")
    }

    func testCompletionUndoAndTodayFilterKeepFirstHabitInPlace() {
        let app = launch()
        let summary = app.descendants(matching: .any)["today-progress"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        let filter = app.segmentedControls["today-all-filter"]
        filter.buttons["Today"].tap()
        let first = app.buttons["check-today"].firstMatch
        XCTAssertTrue(first.isHittable)
        first.tap()
        XCTAssertTrue(app.buttons["check-today"].firstMatch.label.contains("Done"))
        app.buttons["check-today"].firstMatch.tap()
        XCTAssertFalse(app.buttons["check-today"].firstMatch.label.contains("Done"))
        XCTAssertTrue(app.staticTexts["Read for twenty minutes"].firstMatch.exists)
        capture("today-completion-undo")
    }

    func testSortingStaysOnTheHabitsPageAndDoneExitsInlineMode() {
        let app = launch("crowded")
        let sort = app.buttons["reorder-habits"]
        XCTAssertTrue(sort.waitForExistence(timeout: 15))
        sort.tap()

        let sortingList = app.descendants(matching: .any)["habit-sorting-active"].firstMatch
        XCTAssertTrue(sortingList.waitForExistence(timeout: 8))
        let done = app.buttons["finish-reordering"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["sorting-row-00000000-0000-0000-0000-000000000700"]
            .firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["check-today"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["habit-history"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["today-progress"].firstMatch.exists)
        capture("sorting-mode")
        done.tap()
        let habitList = app.descendants(matching: .any)["habit-list"].firstMatch
        XCTAssertTrue(habitList.waitForExistence(timeout: 5))
        XCTAssertTrue(sort.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["habit-filter"].waitForExistence(timeout: 5))
        sort.tap()
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        sort.tap()
        XCTAssertTrue(habitList.waitForExistence(timeout: 5), "the sort icon must also toggle sorting off")
        XCTAssertFalse(done.exists)
    }

    func testSortingDoesNotCheckOffRowsAndStopsWhenLeavingHabits() {
        let app = launch("mixed")
        let sort = app.buttons["reorder-habits"]
        XCTAssertTrue(sort.waitForExistence(timeout: 15))
        let check = app.buttons["check-today"].firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        let before = check.label
        let reminderID = "00000000-0000-0000-0000-000000000799"
        let reminderCheck = app.buttons["reminder-check-\(reminderID)"]
        for _ in 0..<10 where !reminderCheck.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(reminderCheck.isHittable)
        let reminderBefore = reminderCheck.value as? String
        sort.tap()
        let habitRow = app.descendants(matching: .any)["sorting-row-00000000-0000-0000-0000-000000000700"].firstMatch
        let reminderRow = app.descendants(matching: .any)["sorting-row-\(reminderID)"].firstMatch
        XCTAssertTrue(habitRow.waitForExistence(timeout: 5))
        for (row, towardBottom) in [(habitRow, false), (reminderRow, true)] {
            for _ in 0..<8 where !row.isHittable {
                if towardBottom { app.swipeUp(velocity: .slow) }
                else { app.swipeDown(velocity: .slow) }
            }
            XCTAssertTrue(row.isHittable)
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)).tap()
            XCTAssertFalse(app.textFields["habit-name"].exists, "sorting rows must not open editing")
        }
        XCTAssertFalse(app.buttons["check-today"].exists)
        XCTAssertFalse(reminderCheck.exists)
        XCTAssertFalse(app.buttons["reminder-edit-\(reminderID)"].exists)
        selectTab("More", in: app)
        XCTAssertTrue(app.buttons["open-appearance"].waitForExistence(timeout: 5))
        selectTab("Habits", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["habit-list"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["finish-reordering"].exists, "sorting must end before changing tabs")
        for _ in 0..<10 where !check.isHittable { app.swipeDown(velocity: .slow) }
        XCTAssertTrue(check.isHittable)
        XCTAssertEqual(check.label, before, "a sorting tap must not check off the habit")
        for _ in 0..<10 where !reminderCheck.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(reminderCheck.isHittable)
        XCTAssertEqual(reminderCheck.value as? String, reminderBefore)
    }

    func testSortingCanDragAReminderAboveAHabitAndRestoreEditing() {
        let app = launch("mixed")
        let sort = app.buttons["reorder-habits"]
        XCTAssertTrue(sort.waitForExistence(timeout: 15))
        sort.tap()
        let reminderID = "00000000-0000-0000-0000-000000000799"
        let reminder = app.descendants(matching: .any)["sorting-row-\(reminderID)"].firstMatch
        for _ in 0..<8 where !reminder.isHittable {
            app.swipeUp(velocity: .slow)
        }
        let habitRow = app.descendants(matching: .any)["sorting-row-00000000-0000-0000-0000-000000000702"].firstMatch
        XCTAssertTrue(reminder.isHittable)
        XCTAssertTrue(habitRow.isHittable)
        capture("sorting-mixed-before")
        let handle = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Reorder Call the dentist"))
            .firstMatch
        let cell = app.cells.containing(.any, identifier: "sorting-row-\(reminderID)").firstMatch
        let right = cell.exists ? cell.frame.maxX
            : app.descendants(matching: .any)["habit-sorting-active"].firstMatch.frame.maxX
        let start = handle.isHittable
            ? handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            : app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: right - 24, dy: reminder.frame.midY))
        let end = habitRow.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.1))
        start.press(forDuration: 0.4, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)
        let moved = NSPredicate { _, _ in
            reminder.frame.height > 0 && habitRow.frame.height > 0 && reminder.frame.minY < habitRow.frame.minY
        }
        expectation(for: moved, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        capture("sorting-mixed-after")
        app.buttons["finish-reordering"].tap()
        let edit = app.buttons["reminder-edit-\(reminderID)"]
        XCTAssertTrue(edit.isHittable)
        edit.tap()
        XCTAssertTrue(app.textFields["habit-name"].waitForExistence(timeout: 5))
    }

    /// The Search tab must show a search field that a hand tap actually turns
    /// into live input.
    ///
    /// iOS 27's prominent search role owns that navigation bar: the app cannot
    /// focus the field on tab entry, cannot re-open it from the tab-bar
    /// magnifier, and cannot add its own toolbar item there. Tapping the visible
    /// field is the supported way in, so that is what this pins.
    ///
    /// The assertion is that typed text reaches the field, not that a software
    /// keyboard window appears. The simulator here has a hardware keyboard
    /// attached, so the software keyboard never exists even on a correct focus;
    /// asserting it made this test fail for the environment rather than the app.
    func testSearchTabShowsATappableSearchField() {
        let app = launch()
        let searchTab = app.tabBars.buttons["Search"].firstMatch
        XCTAssertTrue(searchTab.waitForExistence(timeout: 15))

        searchTab.tap()
        XCTAssertTrue(searchTab.waitForExistence(timeout: 5))
        XCTAssertTrue(searchTab.isSelected)
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        XCTAssertTrue(searchField.isHittable,
                      "the visible search field is the way into search on iOS 27")

        searchField.tap()
        searchField.typeText("lesen")
        // The field re-renders on every keystroke as the results filter, so
        // XCUITest can drop a character mid-burst. Waiting for "any query landed"
        // pins the behaviour that matters — the tap focused the field and it
        // accepts input — without depending on every character surviving.
        let entered = NSPredicate(format: "value != %@", searchField.placeholderValue ?? "")
        expectation(for: entered, evaluatedWith: searchField)
        waitForExpectations(timeout: 5)
        let value = searchField.value as? String ?? ""
        XCTAssertFalse(value.isEmpty,
                       "tapping the field must focus it so typing is accepted")
    }

    func testGraphOpensHistoryAndCanEditAnEarlierMonth() {
        let app = launch()
        let history = app.descendants(matching: .any)["habit-history"].firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 15), "the Habits page has no history row")
        XCTAssertTrue(history.isHittable, "the history row exists but cannot be tapped")
        history.tap()
        XCTAssertTrue(app.buttons["backfill-close"].waitForExistence(timeout: 5),
                      "the history sheet did not open")
        XCTAssertTrue(app.descendants(matching: .any)["history-month-preview"].exists,
                      "the sheet opened without a month preview")
        app.buttons["history-previous-month"].tap()
        app.buttons["history-selection-mode"].tap()
        app.buttons["history-select-all"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'history-day-'"))
        XCTAssertGreaterThan(rows.count, 0)
        let status = app.staticTexts["backfill-status"]
        let originalStatus = status.label
        // The count has to be read off the page, not out of the calendar.
        //
        // It used to be `contains("31")` — correct only in a month where the
        // previous calendar month has 31 days, so this test passed or failed
        // depending on the date it was run on, and needed no code change at all
        // to start failing. What the assertion is actually about is that
        // "select all" selected every day on screen and the status says so.
        let selectedCount = Int(originalStatus.prefix(while: { $0.isNumber })) ?? -1
        XCTAssertEqual(selectedCount, rows.count,
                       "\"\(originalStatus)\" does not account for the \(rows.count) rows on screen")
        let before = rows.firstMatch.label
        app.buttons["backfill-action-clear"].tap()
        XCTAssertNotEqual(status.label, originalStatus)
        XCTAssertTrue(app.buttons["history-undo"].isEnabled, "undo never became available")
        app.buttons["history-undo"].tap()
        XCTAssertEqual(rows.firstMatch.label, before)
        XCTAssertEqual(status.label, originalStatus)
        app.buttons["history-select-all"].tap()
        rows.element(boundBy: 0).tap()
        rows.element(boundBy: 1).tap()
        capture("history-entry-editor")
        app.buttons["backfill-close"].tap()
        XCTAssertTrue(history.waitForExistence(timeout: 5), "the history row vanished after closing")
    }

    func testHistoryQuantityUpdateUndoAndMissingFilter() {
        let app = launch()
        let graphs = app.descendants(matching: .any).matching(identifier: "habit-history")
        XCTAssertTrue(graphs.firstMatch.waitForExistence(timeout: 15))
        graphs.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["backfill-close"].waitForExistence(timeout: 5))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'history-day-'"))
        let previous = rows.firstMatch.label
        rows.firstMatch.tap()
        XCTAssertNotEqual(rows.firstMatch.label, previous)
        app.buttons["history-undo"].tap()
        XCTAssertEqual(rows.firstMatch.label, previous)
        app.buttons["history-previous-month"].tap()
        app.switches["history-missing-filter"].tap()
        app.buttons["history-selection-mode"].tap()
        XCTAssertFalse(app.buttons["backfill-action-quantity"].isEnabled)
        app.buttons["history-select-all"].tap()
        XCTAssertTrue(app.buttons["backfill-action-quantity"].isEnabled)
        capture("history-quantity-editor")
    }

    func testHistoryOneTapEditsAndSequentialUndo() {
        let app = launch()
        let graph = app.descendants(matching: .any)["habit-history"].firstMatch
        XCTAssertTrue(graph.waitForExistence(timeout: 15))
        graph.tap()
        XCTAssertTrue(app.buttons["backfill-close"].waitForExistence(timeout: 5))
        app.buttons["history-previous-month"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'history-day-'"))
        let first = rows.element(boundBy: 0)
        let second = rows.element(boundBy: 1)
        let firstBefore = first.label
        let secondBefore = second.label
        XCTAssertFalse(app.buttons["backfill-action-clear"].exists)
        XCTAssertGreaterThanOrEqual(first.frame.height, 44)
        XCTAssertEqual(first.frame.width, first.frame.height, accuracy: 1)
        first.tap()
        XCTAssertNotEqual(first.label, firstBefore)
        second.tap()
        XCTAssertNotEqual(second.label, secondBefore)
        app.buttons["history-undo"].tap()
        XCTAssertEqual(second.label, secondBefore)
        XCTAssertNotEqual(first.label, firstBefore)
        app.buttons["history-undo"].tap()
        XCTAssertEqual(first.label, firstBefore)
        XCTAssertFalse(app.buttons["history-undo"].isEnabled)
        capture("compact-history-direct-edit")
    }

    func testCreationLivePreviewAndAdvancedControls() {
        let app = launch("empty")
        let create = app.buttons["create-habit"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        create.tap()
        let name = app.textFields["habit-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Morning pages\n")
        let preview = app.descendants(matching: .any)["creation-preview"].firstMatch
        XCTAssertTrue(preview.label.contains("Morning pages"))
        capture("creation-live-preview")
        let advanced = app.descendants(matching: .any)["creation-advanced"].firstMatch
        for _ in 0..<6 {
            if advanced.isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        capture("creation-advanced-navigation")
        if !advanced.exists {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "creation-accessibility-tree"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(advanced.exists)
        advanced.tap()
        for _ in 0..<4 {
            if app.buttons["habit-timezone"].isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(app.buttons["habit-timezone"].exists)
        capture("creation-advanced")
    }

    func testCreatorDisclosuresStayReachableWithLargestTextAndRTL() {
        let app = XCUIApplication()
        app.launchArguments = ["-design-fixture", "empty", "-pro", "on",
                               "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA",
                               "-design-appearance", "dark", "-design-material", "solid",
                               "-design-photo", "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let create = app.buttons["add-first-habit"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        create.tap()
        let name = app.textFields["habit-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Read\n")
        capture("creator-rtl-largest-text")
        let repeatToggle = app.switches["repeat-toggle"]
        for _ in 0..<15 {
            if repeatToggle.isHittable,
               repeatToggle.frame.midY > app.navigationBars.firstMatch.frame.maxY + 8,
               repeatToggle.frame.midY < app.frame.maxY - 80 { break }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(repeatToggle.isHittable)
        capture("creator-rtl-repeat-control")
        // Native RTL switch accessibility bounds include its full label row.
        // Activate the actual switch on the leading edge, not the empty center.
        repeatToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.14, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: repeatToggle)
        waitForExpectations(timeout: 5)
        let recurrence = app.descendants(matching: .any)["recurrence-details"].firstMatch
        for _ in 0..<8 where !recurrence.isHittable { app.swipeUp(velocity: .slow) }
        if !recurrence.isHittable {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "creator-rtl-disclosure-tree"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            capture("creator-rtl-disclosure-failure")
        }
        XCTAssertTrue(recurrence.isHittable)
        recurrence.tap()
        let ending = app.descendants(matching: .any)["end-mode-picker"].firstMatch
        for _ in 0..<12 where !ending.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(ending.isHittable)
        capture("creator-rtl-recurrence-details")
        let additional = app.buttons["creation-advanced"].firstMatch
        for _ in 0..<18 where !additional.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(additional.isHittable)
        XCTAssertGreaterThanOrEqual(additional.frame.height, 44)
        additional.tap()
        let zone = app.buttons["habit-timezone"]
        for _ in 0..<12 where !zone.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(zone.isHittable)
        XCTAssertGreaterThanOrEqual(zone.frame.height, 44)
        zone.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        capture("creator-rtl-timezone")
    }

    func testDataTransferIsReachableWithoutDeveloperAccess() {
        let app = XCUIApplication()
        app.launchArguments = ["-design-fixture", "crowded", "-pro", "on",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
        app.launch()
        XCTAssertTrue(app.buttons["check-today"].firstMatch.waitForExistence(timeout: 15))
        selectTab("More", in: app)
        let transfer = app.buttons["open-data-transfer"]
        XCTAssertTrue(app.buttons["open-appearance"].waitForExistence(timeout: 15))
        for _ in 0..<10 where !transfer.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(transfer.isHittable)
        transfer.tap()
        XCTAssertTrue(app.buttons["export-data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["export-data"].isHittable)
        XCTAssertTrue(app.buttons["import-data"].isHittable)
        XCTAssertFalse(app.buttons["copy-apple-identifier"].exists)
        capture("public-data-transfer")
        app.open(URL(string: "haiity://stats")!)
        XCTAssertTrue(app.descendants(matching: .any)["stats-week-card"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["export-data"].exists)
        XCTAssertFalse(app.buttons["import-data"].exists)
    }

    func testStatisticsDetailsExpandWithoutChangingSummaryValues() {
        let app = launch("crowded", screen: "stats")
        let summary = app.descendants(matching: .any)["stats-today-summary"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        let original = summary.value as? String
        let explanation = app.staticTexts["stats-today-explanation"]
        XCTAssertFalse(explanation.exists)
        let details = app.descendants(matching: .any)["stats-today-details"].firstMatch
        XCTAssertTrue(details.isHittable)
        details.tap()
        XCTAssertTrue(explanation.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.value as? String, original)
        capture("statistics-expanded-details")
        details.tap()
        XCTAssertFalse(explanation.exists)
    }

    func testMultipleNotificationTimesCanBeAddedRemovedAndSavedForBothItemTypes() {
        for reminder in [false, true] {
            let app = launch("mixed", appearance: reminder ? "dark" : "light")
            func openEditor() {
                if reminder {
                    let edit = app.buttons["reminder-edit-00000000-0000-0000-0000-000000000799"]
                    XCTAssertTrue(app.buttons["check-today"].firstMatch.waitForExistence(timeout: 15))
                    for _ in 0..<10 where !edit.isHittable { app.swipeUp(velocity: .slow) }
                    XCTAssertTrue(edit.isHittable)
                    edit.tap()
                } else {
                    let graph = app.descendants(matching: .any)["habit-history"].firstMatch
                    XCTAssertTrue(graph.waitForExistence(timeout: 15))
                    graph.press(forDuration: 1)
                    let edit = app.buttons["Edit"].firstMatch
                    XCTAssertTrue(edit.waitForExistence(timeout: 5))
                    edit.tap()
                }
                XCTAssertTrue(app.textFields["habit-name"].waitForExistence(timeout: 5))
            }
            func showNotifications() {
                let mode = app.segmentedControls["habit-notification-mode"]
                for _ in 0..<12 where !mode.isHittable { app.swipeUp(velocity: .slow) }
                XCTAssertTrue(mode.isHittable)
                if !mode.buttons["Default"].isSelected { mode.buttons["Default"].tap() }
                let add = app.buttons["add-notification-time"]
                for _ in 0..<12 where !add.isHittable { app.swipeUp(velocity: .slow) }
                XCTAssertTrue(add.isHittable)
            }
            func disableNotifications() {
                let mode = app.segmentedControls["habit-notification-mode"]
                for _ in 0..<12 where !mode.isHittable { app.swipeDown(velocity: .slow) }
                XCTAssertTrue(mode.isHittable)
                mode.buttons["Off"].tap()
                XCTAssertFalse(app.buttons["add-notification-time"].exists)
            }
            openEditor()
            showNotifications()
            app.buttons["add-notification-time"].tap()
            app.buttons["add-notification-time"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["notification-time-2"].firstMatch.exists)
            app.buttons["remove-notification-time-0"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["notification-time-1"].firstMatch.exists)
            XCTAssertFalse(app.descendants(matching: .any)["notification-time-2"].firstMatch.exists)
            capture(reminder ? "reminder-multiple-notifications" : "habit-multiple-notifications")
            // Configure times, then switch off before saving. The hidden times
            // must survive without requesting system notification permission.
            disableNotifications()
            app.buttons["save-habit"].tap()
            openEditor()
            showNotifications()
            XCTAssertTrue(app.descendants(matching: .any)["notification-time-1"].firstMatch.exists)
            app.buttons["remove-notification-time-1"].tap()
            app.buttons["remove-notification-time-0"].tap()
            XCTAssertTrue(app.staticTexts["No notifications scheduled"].exists)
            disableNotifications()
            app.buttons["save-habit"].tap()
            openEditor()
            showNotifications()
            XCTAssertFalse(app.descendants(matching: .any)["notification-time-0"].firstMatch.exists)
            app.buttons["Cancel"].firstMatch.tap()
            app.terminate()
        }
    }

    func testCrowdedListLargeTextKeepsPrimaryActionReachable() throws {
        let app = launch("crowded", largeText: true)
        let summary = app.descendants(matching: .any)["today-progress"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        capture("crowded-accessibility-xxxl")
        let check = app.buttons["check-today"].firstMatch
        for _ in 0..<6 {
            if check.isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(check.isHittable)
        XCTAssertGreaterThanOrEqual(check.frame.height, 44)
        if #available(iOS 17.0, *) {
            // Contrast is covered visually across palettes; inspect actionable
            // geometry and labels with the platform accessibility audit.
            try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription])
        }
        capture("crowded-accessible-actions")
    }

    func testAccountTimeZoneAndDarkHistorySelectionRemainLegible() {
        for appearance in ["light", "dark"] {
            let app = launch("crowded", appearance: appearance, screen: "more")
            // The default time zone moved from the More hub into Verhalten &
            // Teilen, so reach the selector the way a user does.
            let behavior = app.buttons["open-habit-behavior"].firstMatch
            XCTAssertTrue(behavior.waitForExistence(timeout: 15), "no Verhalten & Teilen row on the hub")
            behavior.tap()
            let timezone = app.buttons["default-timezone-picker"].firstMatch
            for _ in 0..<6 {
                if timezone.isHittable { break }
                app.swipeUp(velocity: .slow)
            }
            XCTAssertTrue(timezone.waitForExistence(timeout: 15), "no timezone selector inside Verhalten & Teilen")
            timezone.tap()
            let deviceTimeZone = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "Device time zone"))
                .firstMatch
            XCTAssertTrue(deviceTimeZone.waitForExistence(timeout: 5), "the timezone menu did not open")
            capture("timezone-menu-\(appearance)")
            deviceTimeZone.tap()
            app.terminate()

            let account = launch("crowded", appearance: appearance, screen: "more")
            let accountButton = account.buttons["open-account"].firstMatch
            XCTAssertTrue(accountButton.waitForExistence(timeout: 15), "no Konto row on the hub")
            accountButton.tap()
            XCTAssertTrue(account.navigationBars.firstMatch.waitForExistence(timeout: 5),
                          "the account page did not push a navigation bar")
            capture("account-\(appearance)")
            account.terminate()
        }

        let app = launch(appearance: "dark")
        let history = app.descendants(matching: .any)["habit-history"].firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 15))
        history.tap()
        XCTAssertTrue(app.buttons["backfill-close"].waitForExistence(timeout: 5))
        app.buttons["history-previous-month"].tap()
        app.buttons["history-selection-mode"].tap()
        app.buttons["history-select-all"].tap()
        capture("history-selection-dark")
    }

    func testLightDarkHomeAndCreationVisualMatrix() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance)
            XCTAssertTrue(app.buttons["check-today"].firstMatch.waitForExistence(timeout: 15))
            capture("home-realistic-\(appearance)")
            app.buttons["create-habit"].firstMatch.tap()
            let name = app.textFields["habit-name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            app.segmentedControls["item-type-picker"].buttons["Habit"].tap()
            name.tap()
            name.typeText("Morning pages\n")
            XCTAssertTrue(app.descendants(matching: .any)["creation-preview"].firstMatch.label.contains("Morning pages"))
            capture("creation-\(appearance)")
            app.terminate()
        }
        let empty = launch("empty")
        XCTAssertTrue(empty.buttons["create-habit"].firstMatch.waitForExistence(timeout: 15))
        capture("home-empty-light")
        empty.terminate()
        let crowded = launch("crowded")
        XCTAssertTrue(crowded.buttons["check-today"].firstMatch.waitForExistence(timeout: 15))
        capture("home-crowded-light")
    }
}
