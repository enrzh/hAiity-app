import XCTest

/// The speak-to-create sheet's floating dock.
///
/// The sheet had no UI coverage at all, which is why the microphone could sit
/// inside a content card for as long as it did without anything noticing. These
/// drive it the way a person does: open the sheet, find the controls, use them.
final class SpeakToCreateDockUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-design-fixture", "realistic", "-screen", "habits", "-pro", "on",
                               "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
    }

    private func openSheet() -> XCUIElement {
        XCTAssertFalse(app.buttons["speak-to-create"].exists,
                       "sentence creation is an optional creator action")
        let create = app.buttons["create-habit"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 20))
        create.tap()
        let opener = app.buttons["speak-to-create"]
        XCTAssertTrue(opener.waitForExistence(timeout: 20),
                      "the creator offers sentence creation")
        for _ in 0..<6 where !opener.isHittable { app.swipeUp(velocity: .slow) }
        opener.tap()
        let field = app.textFields["speak-to-create-text"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the sheet should open")
        return field
    }

    /// Writes the screenshot to a path that only exists on this machine AND
    /// attaches it, so the same capture can be read from a real device or CI.
    private func capture(_ name: String) {
        let image = XCUIScreen.main.screenshot().image
        let shots = ProcessInfo.processInfo.environment["HAIITY_SHOT_DIR"]
            ?? "/private/var/folders/gp/c79f6sdj4h1d1t7rrpq24k8m0000gn/T/opencode/shots"
        try? FileManager.default.createDirectory(atPath: shots,
                                                 withIntermediateDirectories: true)
        try? image.pngData()?.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Both controls have to be on screen at once, and hittable. The dock moved
    /// them out of the scrolling content, so a layout that put the dock off-screen
    /// or under the home indicator would still pass a source test.
    func testTheDockShowsItsControlAndItIsHittable() {
        openSheet()

        let mic = app.buttons["speak-to-create-dictation"]
        XCTAssertTrue(mic.waitForExistence(timeout: 5))
        XCTAssertTrue(mic.isHittable)
        XCTAssertGreaterThanOrEqual(mic.frame.width, 44)
        XCTAssertGreaterThanOrEqual(mic.frame.height, 44)

        let create = app.buttons["speak-to-create-confirm"]
        XCTAssertTrue(create.waitForExistence(timeout: 5), "the create action must be reachable")
        XCTAssertTrue(create.isHittable, "the create action must not be covered")
        // Apple's floor is 44 by 44 pt.
        XCTAssertGreaterThanOrEqual(create.frame.height, 44)
        XCTAssertGreaterThanOrEqual(create.frame.width, 44)
    }

    /// The create action starts disabled because there is nothing to create, and
    /// the dock should say so by looking unavailable rather than by pretending.
    func testTheCreateActionIsUnavailableUntilThereIsASentence() {
        let field = openSheet()
        let create = app.buttons["speak-to-create-confirm"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertFalse(create.isEnabled, "an empty sentence cannot create anything")

        field.tap()
        field.typeText("Wasser trinken")

        // The draft appears from the deterministic half, so this needs no model.
        let draft = app.descendants(matching: .any)["speak-to-create-draft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5),
                      "a sentence should produce a draft")
        XCTAssertTrue(create.isEnabled, "a real sentence should enable the create action")
    }

    func testNumericDateAndTimeArePreviewedAndInvalidInputCannotBeSaved() {
        let field = openSheet()
        field.tap()
        let sentence = "Zahnarzt 15.10.2099 10 uhr"
        field.typeText(sentence)
        let schedule = app.staticTexts["speak-to-create-schedule"]
        XCTAssertTrue(schedule.waitForExistence(timeout: 5))
        XCTAssertTrue(schedule.label.contains("2099"), schedule.label)
        XCTAssertTrue(schedule.label.contains("10:00"), schedule.label)
        XCTAssertFalse(schedule.label.contains("15:10"), schedule.label)
        let create = app.buttons["speak-to-create-confirm"]
        XCTAssertTrue(create.isEnabled)
        XCTAssertFalse(app.alerts.element.exists, "typing must never request permissions")

        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: sentence.count)
                       + "Zahnarzt 31.02.2099 10 uhr")
        XCTAssertTrue(app.staticTexts["speak-to-create-validation"].waitForExistence(timeout: 5))
        XCTAssertFalse(create.isEnabled)
        capture("text-create-invalid-date")
    }

    func testISODatePreviewAndInlineMicrophoneInEnglishAndArabicPhotoAppearances() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for (language, locale, appearance, photo) in [
            ("en-US", "en_US", "light", false),
            ("ar-EG", "ar_EG", "dark", true)
        ] {
            app.terminate()
            app.launchArguments = ["-design-fixture", "realistic", "-screen", "habits", "-pro", "on",
                "-AppleLanguages", "(\(language))", "-AppleLocale", locale,
                "-design-appearance", appearance,
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
            if photo { app.launchArguments += ["-design-photo"] }
            app.launch()
            let field = openSheet()
            let mic = app.buttons["speak-to-create-dictation"]
            XCTAssertTrue(mic.waitForExistence(timeout: 5))
            XCTAssertTrue(mic.isHittable, language)
            XCTAssertGreaterThanOrEqual(mic.frame.width, 44)
            XCTAssertGreaterThanOrEqual(mic.frame.height, 44)
            XCTAssertLessThan(mic.frame.minY, field.frame.maxY, "the microphone must be inline")
            XCTAssertGreaterThan(mic.frame.maxY, field.frame.minY, "the microphone must be inline")
            if language == "ar-EG" {
                XCTAssertLessThanOrEqual(mic.frame.maxX, field.frame.minX,
                                         "RTL must place the microphone to the left of the field")
            } else {
                XCTAssertGreaterThanOrEqual(mic.frame.minX, field.frame.maxX)
            }
            XCTAssertFalse(app.alerts.element.exists)
            XCTAssertFalse(springboard.alerts.element.exists, "opening must not request permissions")
            capture("text-create-\(language)-\(appearance)-inline-mic")

            field.tap()
            field.typeText("Dentist 2099-10-15 10 Uhr")
            let schedule = app.staticTexts["speak-to-create-schedule"]
            XCTAssertTrue(schedule.waitForExistence(timeout: 5))
            XCTAssertNotNil(schedule.label.range(of: "(?<![0-9])10:00(?![0-9])",
                                                 options: .regularExpression), schedule.label)
            if language == "en-US" {
                XCTAssertTrue(schedule.label.contains("October 15, 2099"), schedule.label)
            }
            let create = app.buttons["speak-to-create-confirm"]
            XCTAssertTrue(create.waitForExistence(timeout: 5))
            if !schedule.isHittable || schedule.frame.maxY > create.frame.minY {
                app.scrollViews.firstMatch.swipeUp()
            }
            XCTAssertTrue(schedule.isHittable, "the preview must be visible with the keyboard open")
            XCTAssertGreaterThan(schedule.frame.height, 0)
            XCTAssertGreaterThanOrEqual(schedule.frame.minY,
                                       app.buttons["speak-to-create-close"].frame.maxY)
            XCTAssertLessThanOrEqual(schedule.frame.maxY, create.frame.minY,
                                     "the preview must remain above the floating dock")
            XCTAssertFalse(app.alerts.element.exists)
            XCTAssertFalse(springboard.alerts.element.exists, "typing must not request permissions")
            capture("text-create-\(language)-\(appearance)-iso-preview")
        }
    }

    func testSpaceSeparatedDatePreviewAndSavingAgree() {
        let field = openSheet()
        field.tap()
        field.typeText("Zahnarzt 15 10 2099 10 uhr")
        let schedule = app.staticTexts["speak-to-create-schedule"]
        XCTAssertTrue(schedule.waitForExistence(timeout: 5))
        XCTAssertTrue(schedule.label.contains("2099"), schedule.label)
        XCTAssertTrue(schedule.label.contains("10:00"), schedule.label)
        capture("text-create-date-preview")
        app.buttons["speak-to-create-confirm"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        let saved = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'reminder-row-'"))
            .containing(.staticText, identifier: "Zahnarzt").firstMatch
        for _ in 0..<16 where !saved.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        let dateAndTime = saved.staticTexts.matching(NSPredicate(format: "label CONTAINS '2099' AND label CONTAINS '10:00'")).firstMatch
        XCTAssertTrue(dateAndTime.exists)
        let edit = saved.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'reminder-edit-'")).firstMatch
        XCTAssertTrue(edit.isHittable)
        edit.tap()
        XCTAssertTrue(app.textFields["habit-name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["habit-name"].value as? String, "Zahnarzt")
        XCTAssertTrue(app.datePickers["once-date"].exists)
        XCTAssertTrue(app.datePickers["habit-time"].exists)
        capture("text-create-saved-date")
    }

    func testDeniedDictationKeepsTypedTextAndEditingAvailable() {
        app.terminate()
        app.launchEnvironment["HAIITY_TEST_DICTATION"] = "denied"
        app.launchArguments += ["-design-appearance", "dark", "-design-material", "solid",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let field = openSheet()
        field.tap()
        field.typeText("Wasser trinken")
        let mic = app.buttons["speak-to-create-dictation"]
        if !mic.isHittable { app.swipeDown() }
        XCTAssertTrue(mic.isHittable)
        mic.tap()
        let status = app.staticTexts["speak-to-create-prompt"]
        let denied = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "nicht erlaubt"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [denied], timeout: 5), .completed)
        XCTAssertEqual(field.value as? String, "Wasser trinken")
        XCTAssertFalse(app.alerts.element.exists)
        capture("text-create-dark-large-denied")
        field.tap()
        field.typeText(" um 10 Uhr")
        XCTAssertTrue((field.value as? String)?.contains("10 Uhr") == true)
    }

    func testDictationPreservesPrefixAndFinalizesBeforeCreation() {
        app.terminate()
        app.launchEnvironment["HAIITY_TEST_DICTATION"] = "transcript"
        app.launch()
        let field = openSheet()
        field.tap()
        field.typeText("Bitte")
        let mic = app.buttons["speak-to-create-dictation"]
        mic.tap()
        let partial = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "Bitte Zahnarzt"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [partial], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["speak-to-create-confirm"].isEnabled)
        mic.tap()
        let final = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "10 Uhr"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [final], timeout: 5), .completed)
        XCTAssertTrue((field.value as? String)?.hasPrefix("Bitte Zahnarzt") == true)
        XCTAssertTrue(app.buttons["speak-to-create-confirm"].isEnabled)
        XCTAssertTrue(field.exists, "dictation must never create an entry automatically")
        capture("text-create-final-dictation")
        field.tap()
        field.typeText(" bitte")
        XCTAssertTrue((field.value as? String)?.contains(" bitte") == true)
        XCTAssertTrue((field.value as? String)?.contains("10 Uhr") == true)
    }

    /// The dock is a functional layer over content, so the content still scrolls
    /// under it. If the dock were in the scroll view, the last card would be
    /// unreachable once the sheet grew.
    func testTheContentStillScrollsBeneathTheDock() {
        openSheet()
        let field = app.textFields["speak-to-create-text"]
        field.tap()
        field.typeText("jeden Montag und Donnerstag morgens um 7 Wasser trinken")

        // A combined accessibility element is not exposed as .otherElements, so
        // match any type rather than guessing wrong.
        let draft = app.descendants(matching: .any)["speak-to-create-draft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5),
                      "a sentence should produce a draft")
        // Put the keyboard away so the swipe is about the sheet, not the field.
        if app.keyboards.element.exists {
            app.keyboards.buttons.element(boundBy: 0).tap()
        }

        // The dock stays put while the content moves.
        let create = app.buttons["speak-to-create-confirm"]
        let before = create.frame.minY
        app.swipeUp()
        XCTAssertEqual(create.frame.minY, before, accuracy: 1,
                       "the dock must not scroll away with the content")
    }

    /// Writes the sheet at both heights to disk so the material can be looked at
    /// rather than argued about. Layout assertions cannot tell you whether glass
    /// reads as glass; only a picture can, and the previous round of this work
    /// shipped a dock that every assertion passed and that looked broken.
    func testCaptureTheSheetForReview() throws {
        // The main page, so the entry point can be judged against its neighbours.
        capture("dock-00-main")
        let field = openSheet()
        capture("dock-01-half")

        // Typing expands the sheet to the full page, and the draft comes to rest
        // above the dock rather than underneath it.
        field.tap()
        field.typeText("jeden Montag und Donnerstag morgens um 7 Wasser trinken")
        XCTAssertTrue(app.descendants(matching: .any)["speak-to-create-draft"]
            .waitForExistence(timeout: 5))
        capture("dock-02-full")
    }
}
