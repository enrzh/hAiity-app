import XCTest

/// The model page, actually opened and looked at.
///
/// The page was written blind: it compiled, it was routed, it had a test proving
/// both — and it still could not be opened, and had no surface. Every assertion
/// that could be made about it from the source was true while the page was dead
/// on arrival. So it is opened here, the way a person does it, and captured.
///
/// This is also the only coverage of the catalogue's layout. Five models with a
/// size, a summary and a control each is a page nobody has seen on a screen.
final class LocalModelPageUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-screen", "more", "-pro", "on"]
        app.launch()
    }

    private func capture(_ name: String) {
        let image = XCUIScreen.main.screenshot().image
        let shots = ProcessInfo.processInfo.environment["HAIITY_SHOT_DIR"]
            ?? "/private/var/folders/gp/c79f6sdj4h1d1t7rrpq24k8m0000gn/T/opencode/shots"
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        try? image.pngData()?.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Scrolls until the element is on screen and can actually be pressed.
    ///
    /// A control below the fold exists in the accessibility tree but is not
    /// hittable, which is what made this page look broken twice: first the route
    /// did nothing, then the row turned out to be real and merely off-screen. A
    /// test that only waits for existence passes on both, so it is checked for
    /// hittability after every scroll.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, _ identifier: String) -> Bool {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        if element.exists && element.isHittable { return true }
        XCTFail("\(identifier) never became hittable after scrolling")
        return false
    }

    /// Walk the whole way a person does: Mehr, Verhalten & Teilen, then the
    /// model page. Every hop is asserted, because "the row does nothing" is a
    /// failure that no source-level test can see.
    func testTheModelPageOpensFromBehaviourAndShowsTheCatalogue() {
        let behaviour = app.buttons["open-habit-behavior"].firstMatch
        XCTAssertTrue(behaviour.waitForExistence(timeout: 20),
                      "Verhalten & Teilen should be on the More page")
        behaviour.tap()

        let row = app.buttons["open-local-model"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15),
                      "the model row should be on Verhalten & Teilen")
        XCTAssertTrue(scrollTo(row, "open-local-model"),
                      "the model row is at the foot of a long page and must be reachable")
        capture("model-01-behaviour")

        row.tap()

        // The catalogue itself. The smallest model is the default, so its row is
        // the one that has to be on screen.
        let first = app.descendants(matching: .any)["local-model-qwen25-0.5b"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15),
                      "the model page must open and show the catalogue")
        capture("model-02-page")

        // The page must offer every model, not only the ones that happen to fit
        // above the fold. Scrolling is the point: a 2 GB option that cannot be
        // reached is not offered.
        for id in ["qwen3-0.6b", "qwen25-1.5b", "gemma2-2b", "phi35-mini"] {
            let element = app.descendants(matching: .any)["local-model-\(id)"].firstMatch
            XCTAssertTrue(scrollTo(element, id),
                          "\(id) should be reachable by scrolling the catalogue")
        }
        capture("model-04-scrolled")

        // Each model offers exactly one action: a download while it is absent, a
        // remove once it is on the phone. Which one depends on whether this
        // simulator has run the download before, and asserting a particular one
        // makes the test depend on leftover state.
        let download = app.buttons["local-model-download-qwen25-0.5b"].firstMatch
        let remove = app.buttons["local-model-delete-qwen25-0.5b"].firstMatch
        let downloading = app.descendants(matching: .any)["local-model-progress-qwen25-0.5b"].firstMatch
        let offered = download.waitForExistence(timeout: 8) || remove.exists
        XCTAssertTrue(offered || downloading.exists,
                      "a model must always offer an action: download it, remove it, or show progress")
        if download.exists {
            XCTAssertTrue(download.isEnabled,
                          "a fresh install has room for the smallest model")
        }
        capture("model-03-download")
    }

    /// The page has to say the weights stay put. A gigabyte of model appearing on
    /// a second device through iCloud would be a surprise, and the one line that
    /// prevents it is on this page.
    func testThePageStatesThatModelsStayOnThisDevice() {
        let behaviour = app.buttons["open-habit-behavior"].firstMatch
        XCTAssertTrue(behaviour.waitForExistence(timeout: 20))
        behaviour.tap()
        let row = app.buttons["open-local-model"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertTrue(scrollTo(row, "open-local-model"))
        row.tap()

        XCTAssertTrue(app.descendants(matching: .any)["local-model-footnote"]
            .waitForExistence(timeout: 15), "the page must say models are device-local")
    }
}
