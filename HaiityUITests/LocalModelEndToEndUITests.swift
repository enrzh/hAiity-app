import XCTest

/// A real model, really downloaded, really run.
///
/// Everything before this checked the chain one link at a time: the catalogue's
/// numbers came from Hugging Face, the downloader fetches the CDN's resolve path,
/// the reader compiles, and the parser has 27 tests. None of that has ever put a
/// token through a model, because it all needs 290 MB and a device. This does.
///
/// It is deliberately not part of the routine suite. A 290 MB download and a
/// first-run model load take minutes and need the network, so it is gated behind
/// HAIITY_RUN_MODEL_E2E and skipped without it. When it is wrong, it is wrong
/// loudly rather than not at all.
final class LocalModelEndToEndUITests: XCTestCase {

    /// `touch /tmp/haiity-run-model-e2e` to run the heavy test.
    static let marker = "/tmp/haiity-run-model-e2e"

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // A marker file, not an environment variable: a UI test runs in its own
        // process, which does not inherit the shell's environment from
        // xcodebuild, so an env gate here is silently always-off. The file is
        // explicit and says what it does.
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.marker),
                          "touch \(Self.marker) to run this: it downloads ~290 MB")
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

    @discardableResult
    private func scrollTo(_ element: XCUIElement) -> Bool {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    /// Download the smallest model from Hugging Face and wait for it to be usable.
    ///
    /// The assertion is the one that matters and the one that is easy to fake: the
    /// page has to report the model as being ON THE PHONE. A progress bar that
    /// reaches the end without the files arriving would leave a model that claims
    /// to be ready and cannot load, which is the failure this whole layer was
    /// written to prevent.
    func testTheSmallestModelDownloadsFromHuggingFaceAndBecomesReady() throws {
        let behaviour = app.buttons["open-habit-behavior"].firstMatch
        XCTAssertTrue(behaviour.waitForExistence(timeout: 30))
        behaviour.tap()

        let row = app.buttons["open-local-model"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertTrue(scrollTo(row), "the model row must be reachable")
        row.tap()

        // The download button is only offered when the model is NOT on the phone,
        // so a simulator that already has it shows "Entfernen" instead. That is
        // persistence working, and this test has to cope with both states.
        let download = app.buttons["local-model-download-qwen25-0.5b"].firstMatch
        let ready = app.descendants(matching: .any)["local-model-delete-qwen25-0.5b"].firstMatch
        let failed = app.descendants(matching: .any)["local-model-failed-qwen25-0.5b"].firstMatch

        if download.waitForExistence(timeout: 5), scrollTo(download) {
            download.tap()
            capture("e2e-01-downloading")

            // Progress first — otherwise a download that never starts looks
            // identical to one that finished instantly.
            let progress = app.descendants(matching: .any)["local-model-progress-qwen25-0.5b"].firstMatch
            XCTAssertTrue(progress.waitForExistence(timeout: 30),
                          "tapping Laden must start a download, not silently do nothing")
            capture("e2e-02-progress")
        }

        // Then the model on the phone. 290 MB over a real network.
        let deadline = Date().addingTimeInterval(15 * 60)
        while Date() < deadline {
            if ready.exists { break }
            if failed.exists {
                XCTFail("the download reported a failure instead of finishing")
                capture("e2e-03-failed")
                return
            }
            sleep(3)
        }
        XCTAssertTrue(ready.exists,
                      "the model should be on the phone; a progress bar that ends without files "
                      + "arriving is the failure this layer exists to prevent")
        capture("e2e-03-ready")

        // And now the part nothing has ever done: ask the model to read a
        // sentence and see what comes back.
        //
        // The model is on the phone but Apple's Foundation Models is not available
        // in a simulator, so this also proves the sheet routes to the local model
        // rather than to Apple's — the button is only offered when one of them
        // can answer, and here only the local one can.
        // The model page is a presented sheet over the whole app, so switching
        // tabs would not reach the button underneath it. Relaunch straight onto
        // Habits instead: the weights are on the disk already, and the sheet does
        // not care which tab opened it.
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-screen", "habits", "-pro", "on"]
        app.launch()

        let opener = app.buttons["speak-to-create"].firstMatch
        XCTAssertTrue(opener.waitForExistence(timeout: 15),
                      "the create-from-a-sentence entry point must be on the habits screen")
        opener.tap()

        let field = app.textFields["speak-to-create-text"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15), "the sheet should open")
        field.tap()
        field.typeText("jeden Montag morgens um 7 Wasser trinken")

        let read = app.buttons["speak-to-create-read"].firstMatch
        XCTAssertTrue(read.waitForExistence(timeout: 15),
                      "a downloaded model must make the read button available where Apple's is absent")
        XCTAssertTrue(read.isEnabled, "and it must be enabled once there is a sentence")
        read.tap()
        capture("e2e-04-reading")

        // A first load of a 0.5B is seconds, not milliseconds.
        let draft = app.descendants(matching: .any)["speak-to-create-draft"].firstMatch
        let finished = NSPredicate(format: "exists == true")
        expectation(for: finished, evaluatedWith: draft)
        waitForExpectations(timeout: 300)
        capture("e2e-05-draft")
    }
}
