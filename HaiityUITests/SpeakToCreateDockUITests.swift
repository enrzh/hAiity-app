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

        // There is one control in the dock now. The microphone went away with
        // the in-app recogniser, and this is where that is pinned: a button
        // coming back would need a permission prompt that no longer exists.
        XCTAssertFalse(app.buttons["speak-to-create-toggle"].exists,
                       "there is no microphone control in the sheet any more")

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
