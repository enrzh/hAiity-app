import XCTest

@MainActor
final class ProductSimplificationUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(fixture: String = "mixed") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-design-fixture", fixture, "-screen", "habits", "-pro", "on",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
        app.launch()
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<14 where !element.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCreatorDefaultsKeepHabitTypeAndSentenceHandoffKeepsTypedName() {
        let app = launch()
        XCTAssertFalse(app.buttons["speak-to-create"].exists)
        let add = app.buttons["create-habit"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        let name = app.textFields["habit-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Read every day\n")
        let repeating = app.switches["repeat-toggle"]
        reveal(repeating, in: app)
        XCTAssertEqual(repeating.value as? String, "1")
        repeating.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(repeating.value as? String, "0")
        XCTAssertTrue(app.segmentedControls["item-type-picker"].buttons["Habit"].isSelected)
        let sentence = app.buttons["speak-to-create"]
        for _ in 0..<6 where !sentence.isHittable { app.swipeDown(velocity: .slow) }
        XCTAssertTrue(sentence.isHittable)
        XCTAssertEqual(name.value as? String, "Read every day")
        sentence.tap()
        let text = app.textFields["speak-to-create-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        XCTAssertEqual(text.value as? String, "Read every day")
        XCTAssertFalse(app.textFields["habit-name"].exists)
        capture("product-creator-sentence-handoff")
        app.buttons["speak-to-create-close"].tap()
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["speak-to-create-text"].exists)
        XCTAssertFalse(app.staticTexts["Read every day"].exists, "cancel must not create an item")
    }

    func testDeepLinkDismissesSentenceCreationBeforeOpeningNewCreator() {
        let app = launch()
        let add = app.buttons["create-habit"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        let sentence = app.buttons["speak-to-create"]
        XCTAssertTrue(sentence.waitForExistence(timeout: 5))
        sentence.tap()
        XCTAssertTrue(app.textFields["speak-to-create-text"].waitForExistence(timeout: 10))
        app.open(URL(string: "haiity://new")!)
        XCTAssertTrue(app.textFields["habit-name"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["speak-to-create-text"].exists)
        XCTAssertEqual(app.switches["repeat-toggle"].value as? String, "1")
        capture("product-deep-link-new-after-sentence")
    }

    func testMoreHubOffersNavigationAndNicknameWithOptionalAppleConnection() {
        let app = launch()
        app.tabBars.buttons["More"].tap()
        let personal = app.buttons["open-account"].firstMatch
        reveal(personal, in: app)
        XCTAssertTrue(personal.label.contains("Personalization"))
        XCTAssertFalse(app.buttons["apple-signin-more"].exists)
        XCTAssertFalse(app.buttons["connect-github"].exists)
        personal.tap()
        XCTAssertTrue(app.textFields["personal-alias"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["apple-signin"].exists)
        capture("product-personalization-nickname")
        let optionalApple = app.descendants(matching: .any)["personal-apple-connection"].firstMatch
        reveal(optionalApple, in: app)
        optionalApple.tap()
        let signIn = app.buttons["apple-signin"]
        reveal(signIn, in: app)
        capture("product-personalization-optional-apple")
    }

    func testAppearanceKeepsDesignAndMaterialsInsideCustomize() {
        let app = launch()
        app.tabBars.buttons["More"].tap()
        let appearance = app.buttons["open-appearance"]
        reveal(appearance, in: app)
        appearance.tap()
        let customize = app.descendants(matching: .any)["appearance-customize"].buttons.firstMatch
        XCTAssertTrue(customize.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["appearance-design-quiet"].exists)
        capture("product-appearance-simple")
        customize.tap()
        XCTAssertTrue(app.buttons["appearance-design-quiet"].waitForExistence(timeout: 5))
        let quiet = app.buttons["appearance-design-quiet"]
        reveal(quiet, in: app)
        quiet.tap()
        XCTAssertTrue(quiet.isSelected)
        capture("product-appearance-customize")
    }

    func testFlexibleWeeklyCreationSavesAndReopensWithItsQuota() {
        let app = launch(fixture: "empty")
        let add = app.buttons["add-first-habit"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        let name = app.textFields["habit-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Run any three days\n")
        let cadence = app.buttons["cadence-picker"].firstMatch
        reveal(cadence, in: app)
        cadence.tap()
        app.buttons["Weekly"].tap()
        let flexible = app.switches["flexible-week-toggle"]
        reveal(flexible, in: app)
        flexible.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(flexible.value as? String, "1")
        XCTAssertTrue(app.steppers["weekly-times-stepper"].label.contains("3"))
        let advanced = app.descendants(matching: .any)["creation-advanced"].firstMatch
        reveal(advanced, in: app)
        advanced.tap()
        let notifications = app.segmentedControls["habit-notification-mode"]
        reveal(notifications, in: app)
        notifications.buttons["Off"].tap()
        capture("product-flexible-week-preview")
        app.buttons["save-habit"].tap()
        let edit = app.buttons["edit-habit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        XCTAssertEqual(app.textFields["habit-name"].value as? String, "Run any three days")
        XCTAssertEqual(app.switches["flexible-week-toggle"].value as? String, "1")
        XCTAssertTrue(app.steppers["weekly-times-stepper"].label.contains("3"))
        XCTAssertFalse(app.buttons["speak-to-create"].exists, "editing must not offer a second creator")
        capture("product-flexible-week-reopened")
    }
}
