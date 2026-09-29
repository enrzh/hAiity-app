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

        let download = app.buttons["local-model-download-qwen25-0.5b"].firstMatch
        XCTAssertTrue(download.waitForExistence(timeout: 15), "the smallest model offers a download")
        XCTAssertTrue(scrollTo(download), "the download control must be reachable")
        download.tap()
        capture("e2e-01-downloading")

        // Progress first — otherwise a download that never starts looks identical
        // to one that finished instantly.
        let progress = app.descendants(matching: .any)["local-model-progress-qwen25-0.5b"].firstMatch
        let failed = app.descendants(matching: .any)["local-model-failed-qwen25-0.5b"].firstMatch
        let sawProgress = progress.waitForExistence(timeout: 30)
        XCTAssertTrue(sawProgress, "tapping Laden must start a download, not silently do nothing")
        capture("e2e-02-progress")

        // Then the model on the phone. 290 MB over a real network.
        let ready = app.descendants(matching: .any)["local-model-delete-qwen25-0.5b"].firstMatch
        let deadline = Date().addingTimeInterval(15 * 60)
        while Date() < deadline {
            if ready.exists {
                break
            }
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
    }
}
