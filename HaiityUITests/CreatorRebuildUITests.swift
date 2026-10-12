import XCTest

@MainActor
final class CreatorRebuildUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func openCreator(rtl: Bool = false, dictation: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-design-fixture", "empty", "-screen", "habits", "-pro", "on",
            "-AppleLanguages", rtl ? "(ar)" : "(en)", "-AppleLocale", rtl ? "ar_SA" : "en_GB"]
        if rtl {
            app.launchArguments += ["-design-appearance", "dark", "-design-photo",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        if let dictation { app.launchEnvironment["HAIITY_TEST_DICTATION"] = dictation }
        app.launch()
        app.open(URL(string: "haiity://new")!)
        XCTAssertTrue(app.textFields["habit-name"].waitForExistence(timeout: 15))
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, down: Bool = false) {
        for _ in 0..<18 {
            if element.isHittable,
               element.frame.midY > app.navigationBars.firstMatch.frame.maxY + 8,
               element.frame.midY < app.frame.maxY - 80 { break }
            if down { app.swipeDown(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
        }
        XCTAssertTrue(element.isHittable, element.identifier)
    }

    @discardableResult
    private func openSentence(in app: XCUIApplication) -> XCUIElement {
        let sentence = app.buttons["speak-to-create"]
        reveal(sentence, in: app, down: true)
        sentence.tap()
        let field = app.textFields["speak-to-create-text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["save-habit"].exists, "the child must own the visible save action")
        return field
    }

    private func waitForRemoval(_ element: XCUIElement) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
    }

    func testCancelReturnsToQuantityRecurrenceAndHiddenNotificationDraft() {
        let app = openCreator()
        let name = app.textFields["habit-name"]
        name.typeText("Unsaved quantity\n")
        let kind = app.segmentedControls["habit-kind-picker"]
        reveal(kind, in: app)
        kind.buttons["Quantity"].tap()
        let target = app.steppers["quantity-target"]
        target.buttons["quantity-target-Increment"].tap()
        let quantity = target.label

        let cadence = app.buttons["cadence-picker"]
        reveal(cadence, in: app, down: true)
        cadence.tap()
        app.buttons["Weekly"].tap()
        let recurrence = app.descendants(matching: .any)["recurrence-details"].firstMatch
        reveal(recurrence, in: app)
        recurrence.tap()
        let interval = app.steppers["interval-stepper"]
        reveal(interval, in: app)
        interval.buttons["interval-stepper-Increment"].tap()
        let intervalLabel = interval.label

        let advanced = app.buttons["creation-advanced"]
        reveal(advanced, in: app)
        advanced.tap()
        let addAlert = app.buttons["add-notification-time"]
        reveal(addAlert, in: app)
        addAlert.tap()
        let mode = app.segmentedControls["habit-notification-mode"]
        reveal(mode, in: app, down: true)
        mode.buttons["Off"].tap()
        XCTAssertFalse(app.datePickers["notification-time-0"].exists)
        let emoji = app.textFields["habit-emoji"]
        reveal(emoji, in: app)
        emoji.tap()
        emoji.typeText("\u{1F4DA}\n")
        let duration = app.switches["duration-toggle"]
        reveal(duration, in: app)
        duration.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()

        let field = openSentence(in: app)
        XCTAssertEqual(field.value as? String, "Unsaved quantity")
        field.tap()
        field.typeText(" child changes")
        app.buttons["speak-to-create-close"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Unsaved quantity")
        reveal(interval, in: app)
        XCTAssertEqual(interval.label, intervalLabel)
        reveal(target, in: app)
        XCTAssertEqual(target.label, quantity)
        reveal(mode, in: app)
        XCTAssertTrue(mode.buttons["Off"].isSelected)
        mode.buttons["Default"].tap()
        XCTAssertTrue(app.datePickers["notification-time-1"].exists)
        reveal(emoji, in: app)
        XCTAssertEqual(emoji.value as? String, "\u{1F4DA}")
        reveal(duration, in: app)
        XCTAssertEqual(duration.value as? String, "1")

        let again = openSentence(in: app)
        XCTAssertEqual(again.value as? String, "Unsaved quantity", "each child starts from the parent once")
        app.buttons["speak-to-create-close"].tap()
        app.buttons["close-create"].tap()
        XCTAssertFalse(app.staticTexts["Unsaved quantity"].exists, "cancelling must never save the parent")
    }

    func testNativeBackKeepsTheManualNameAndOnceSchedule() {
        let app = openCreator()
        let name = app.textFields["habit-name"]
        name.typeText("Manual once\n")
        let repeats = app.switches["repeat-toggle"]
        reveal(repeats, in: app)
        repeats.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        openSentence(in: app)
        let back = app.navigationBars.buttons.matching(NSPredicate(
            format: "identifier != 'speak-to-create-close' AND label != 'Cancel'")).firstMatch
        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Manual once")
        XCTAssertEqual(repeats.value as? String, "0")
        XCTAssertFalse(app.textFields["speak-to-create-text"].exists)
    }

    func testSuccessfulSentenceCreationClosesTheParentAndCreatesOnlyOneItem() {
        let app = openCreator()
        app.textFields["habit-name"].typeText("Discard this manual draft\n")
        let field = openSentence(in: app)
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                              count: "Discard this manual draft".count)
                       + "Dentist 15 10 2099 10 Uhr")
        let confirm = app.buttons["speak-to-create-confirm"]
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        waitForRemoval(field)
        XCTAssertFalse(app.textFields["habit-name"].exists, "success must close the parent, not pop into its draft")
        let habits = app.tabBars.buttons["Habits"].firstMatch
        XCTAssertTrue(habits.waitForExistence(timeout: 5))
        habits.tap()
        let created = app.buttons.matching(NSPredicate(format:
            "identifier BEGINSWITH 'reminder-name-' AND label == %@", "Dentist"))
        XCTAssertTrue(created.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(created.count, 1)
        XCTAssertFalse(app.staticTexts["Discard this manual draft"].exists)
        app.buttons["create-habit"].firstMatch.tap()
        app.buttons["New habit"].firstMatch.tap()
        let fresh = app.textFields["habit-name"]
        XCTAssertTrue(fresh.waitForExistence(timeout: 5))
        XCTAssertNotEqual(fresh.value as? String, "Discard this manual draft")
        XCTAssertEqual(app.switches["repeat-toggle"].value as? String, "1")
    }

    func testExternalRouteCancelsDictationWithoutWritingOrReopeningOldDraft() {
        let app = openCreator(dictation: "transcript")
        app.textFields["habit-name"].typeText("Old manual draft\n")
        let field = openSentence(in: app)
        app.buttons["speak-to-create-dictation"].tap()
        let partial = XCTNSPredicateExpectation(predicate: NSPredicate(
            format: "value CONTAINS 'Zahnarzt'"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [partial], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["speak-to-create-confirm"].isEnabled)
        app.buttons["speak-to-create-dictation"].tap()
        app.open(URL(string: "haiity://new")!)
        let fresh = app.textFields["habit-name"]
        XCTAssertTrue(fresh.waitForExistence(timeout: 10))
        XCTAssertNotEqual(fresh.value as? String, "Old manual draft")
        XCTAssertFalse(field.exists)
        app.buttons["close-create"].tap()
        XCTAssertFalse(app.staticTexts["Zahnarzt"].exists)
        XCTAssertFalse(app.staticTexts["Old manual draft"].exists)
    }

    func testRemovingAllAlertsAndTogglingOffDoesNotRestoreAnInheritedAlert() {
        let app = openCreator()
        app.textFields["habit-name"].typeText("Silent\n")
        let advanced = app.buttons["creation-advanced"]
        reveal(advanced, in: app)
        advanced.tap()
        let add = app.buttons["add-notification-time"]
        reveal(add, in: app)
        add.tap()
        let remove = app.buttons["remove-notification-time-0"]
        reveal(remove, in: app, down: true)
        remove.tap()
        XCTAssertTrue(app.datePickers["notification-time-0"].exists)
        XCTAssertFalse(app.datePickers["notification-time-1"].exists)
        remove.tap()
        XCTAssertFalse(app.datePickers["notification-time-0"].exists)
        let mode = app.segmentedControls["habit-notification-mode"]
        reveal(mode, in: app, down: true)
        mode.buttons["Off"].tap()
        mode.buttons["Default"].tap()
        XCTAssertFalse(app.datePickers["notification-time-0"].exists)
        openSentence(in: app)
        app.buttons["speak-to-create-close"].tap()
        reveal(mode, in: app)
        XCTAssertFalse(app.datePickers["notification-time-0"].exists)
        reveal(add, in: app)
        add.tap()
        XCTAssertTrue(app.datePickers["notification-time-0"].exists)
    }

    func testAX5RTLDateControlsAndKeyboardOpenSentenceRemainReachable() {
        let app = openCreator(rtl: true)
        app.textFields["habit-name"].typeText("Read\n")
        let repeats = app.switches["repeat-toggle"]
        reveal(repeats, in: app)
        repeats.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        let date = app.buttons["once-date"]
        reveal(date, in: app, down: true)
        XCTAssertGreaterThanOrEqual(date.frame.height, 44)
        date.tap()
        let done = app.buttons["start-date-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        let field = openSentence(in: app)
        field.tap()
        field.typeText(" 2099-10-15 10 Uhr")
        let mic = app.buttons["speak-to-create-dictation"]
        let confirm = app.buttons["speak-to-create-confirm"]
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(confirm.isHittable)
        XCTAssertGreaterThanOrEqual(mic.frame.width + 0.001, 44)
        XCTAssertGreaterThanOrEqual(mic.frame.height + 0.001, 44)
        XCTAssertGreaterThanOrEqual(confirm.frame.height + 0.001, 44)
        XCTAssertLessThanOrEqual(confirm.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        app.buttons["speak-to-create-close"].tap()
        XCTAssertEqual(app.textFields["habit-name"].value as? String, "Read")
    }
}
