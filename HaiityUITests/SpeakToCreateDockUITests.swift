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
        app.launchArguments = ["-screen", "habits", "-pro"]
        app.launch()
    }

    private func openSheet() -> XCUIElement {
        let opener = app.buttons["speak-to-create"]
        XCTAssertTrue(opener.waitForExistence(timeout: 20),
                      "the speak button should be on the habits screen")
        opener.tap()
        let field = app.textFields["speak-to-create-text"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the sheet should open")
        return field
    }

    /// Both controls have to be on screen at once, and hittable. The dock moved
    /// them out of the scrolling content, so a layout that put the dock off-screen
    /// or under the home indicator would still pass a source test.
    func testTheDockShowsBothControlsAndTheyAreHittable() {
        openSheet()

        let mic = app.buttons["speak-to-create-toggle"]
        let create = app.buttons["speak-to-create-confirm"]
        XCTAssertTrue(mic.waitForExistence(timeout: 5), "the microphone must be reachable")
        XCTAssertTrue(create.waitForExistence(timeout: 5), "the create action must be reachable")

        XCTAssertTrue(mic.isHittable, "the microphone must not be covered by the dock or the inset")
        XCTAssertTrue(create.isHittable, "the create action must not be covered")

        // Apple's floor is 44 by 44 pt; the mic is a 52 pt circle and the create
        // control is at least as tall, so neither may be smaller than that.
        XCTAssertGreaterThanOrEqual(mic.frame.width, 44)
        XCTAssertGreaterThanOrEqual(mic.frame.height, 44)
        XCTAssertGreaterThanOrEqual(create.frame.height, 44)
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
        let mic = app.buttons["speak-to-create-toggle"]
        let before = mic.frame.minY
        app.swipeUp()
        XCTAssertEqual(mic.frame.minY, before, accuracy: 1,
                       "the dock must not scroll away with the content")
    }

    /// Writes the sheet at both heights to disk so the material can be looked at
    /// rather than argued about. Layout assertions cannot tell you whether glass
    /// reads as glass; only a picture can, and the previous round of this work
    /// shipped a dock that every assertion passed and that looked broken.
    func testCaptureTheSheetForReview() throws {
        let shots = ProcessInfo.processInfo.environment["HAIITY_SHOT_DIR"]
            ?? "/private/var/folders/gp/c79f6sdj4h1d1t7rrpq24k8m0000gn/T/opencode/shots"
        try? FileManager.default.createDirectory(atPath: shots,
                                                 withIntermediateDirectories: true)
        func capture(_ name: String) {
            let image = XCUIScreen.main.screenshot().image
            try? image.pngData()?.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
            // The path above only exists on the machine that ran the tests. An
            // attachment travels with the result bundle instead, so the same
            // three states can be reviewed from a real device — where that path
            // is not writable — and from CI.
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        // The main page, so the entry point can be judged against its neighbours.
        let opener = app.buttons["speak-to-create"]
        XCTAssertTrue(opener.waitForExistence(timeout: 20))
        capture("dock-00-main")

        opener.tap()
        let field = app.textFields["speak-to-create-text"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
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
