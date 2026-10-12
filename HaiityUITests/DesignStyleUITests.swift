import XCTest

@MainActor
final class DesignStyleUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(photo: Bool = false, accessibleRTL: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-design-fixture", "mixed", "-screen", "habits", "-pro", "on",
                               "-design-appearance", photo ? "dark" : "light",
                               "-design-material", photo ? "milky" : "solid",
                               "-AppleLanguages", accessibleRTL ? "(ar)" : "(en)",
                               "-AppleLocale", accessibleRTL ? "ar_SA" : "en_GB"]
        if photo { app.launchArguments += ["-design-photo"] }
        if accessibleRTL {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        openSettings(in: app)
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<16 where !element.exists || !element.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
    }

    private func selectTab(_ title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[title].firstMatch
        if !tab.exists {
            let collapsed = app.tabBars.buttons.matching(NSPredicate(format: "value == 'Collapsed'")).firstMatch
            if collapsed.exists { collapsed.tap() }
        }
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
    }

    private func openSettings(in app: XCUIApplication) {
        let settings = app.buttons["open-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.buttons["open-appearance"].waitForExistence(timeout: 5))
    }

    private func returnToHub(in app: XCUIApplication) {
        XCTAssertFalse(app.buttons["close-more-sheet"].exists, "a child uses Back, not the hub close action")
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(app.buttons["open-appearance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["close-more-sheet"].isHittable)
    }

    private func openAppearance(in app: XCUIApplication) {
        let entry = app.buttons["open-appearance"].firstMatch
        reveal(entry, in: app)
        entry.tap()
        let customize = app.descendants(matching: .any)["appearance-customize"].buttons.firstMatch
        XCTAssertTrue(customize.waitForExistence(timeout: 5))
        if !app.buttons["appearance-design-native"].exists { customize.tap() }
        XCTAssertTrue(app.buttons["appearance-design-native"].waitForExistence(timeout: 5))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testStyleTapsApplyAcrossRootAndAccountPages() {
        let app = launch()
        for style in ["native", "quiet", "focus", "studio"] {
            if !app.buttons["open-appearance"].exists { openSettings(in: app) }
            openAppearance(in: app)
            let option = app.buttons["appearance-design-\(style)"]
            reveal(option, in: app)
            option.tap()
            XCTAssertTrue(option.isSelected)
            capture("style-\(style)-selector")
            returnToHub(in: app)
            app.buttons["close-more-sheet"].tap()
            selectTab("Habits", in: app)
            XCTAssertTrue(app.buttons["check-today"].firstMatch.waitForExistence(timeout: 5))
            capture("style-\(style)-habits")
            selectTab("Progress", in: app)
            XCTAssertTrue(app.descendants(matching: .any)["stats-week-card"].firstMatch.waitForExistence(timeout: 5))
            capture("style-\(style)-stats")
            openSettings(in: app)
            let account = app.buttons["open-account"].firstMatch
            reveal(account, in: app)
            capture("style-\(style)-more")
            account.tap()
            XCTAssertTrue(app.descendants(matching: .any)["account-header"].firstMatch.waitForExistence(timeout: 5))
            capture("style-\(style)-account")
            returnToHub(in: app)
            openAppearance(in: app)
            XCTAssertTrue(app.buttons["appearance-design-\(style)"].isSelected,
                          "navigation must retain the chosen design")
            returnToHub(in: app)
            app.buttons["close-more-sheet"].tap()
        }
    }

    func testEveryStyleKeepsPhotoMaterialAndAdvancedControls() {
        let app = launch(photo: true)
        for style in ["native", "quiet", "focus", "studio"] {
            if !app.buttons["open-appearance"].exists { openSettings(in: app) }
            openAppearance(in: app)
            let option = app.buttons["appearance-design-\(style)"]
            reveal(option, in: app)
            option.tap()
            let material = app.buttons["appearance-material-milky"].firstMatch
            reveal(material, in: app)
            XCTAssertTrue(material.isSelected, "design selection must preserve the user's material")
            capture("style-\(style)-customize-dark-photo")
            let removePhoto = app.buttons["appearance-background-remove"].firstMatch
            reveal(removePhoto, in: app)
            XCTAssertTrue(removePhoto.isHittable, "design selection must preserve the photo")
            let compact = app.switches["compact-mode-toggle"].firstMatch
            reveal(compact, in: app)
            if style == "native", compact.value as? String == "0" {
                // The native switch's AX frame includes its label. Tap the thumb.
                compact.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            }
            XCTAssertEqual(compact.value as? String, "1",
                           "changing design must preserve a non-default compact preference")
            returnToHub(in: app)
            app.buttons["close-more-sheet"].tap()
        }
    }

    func testSelectorAndCustomizeWorkWithLargestTextAndRTL() {
        let app = launch(accessibleRTL: true)
        openAppearance(in: app)
        let original = app.buttons["appearance-design-native"]
        XCTAssertGreaterThanOrEqual(original.frame.width, 44)
        capture("styles-rtl-ax5-original")
        let studio = app.buttons["appearance-design-studio"]
        reveal(studio, in: app)
        XCTAssertGreaterThanOrEqual(studio.frame.width, 44)
        studio.tap()
        reveal(studio, in: app)
        XCTAssertTrue(studio.isSelected)
        capture("styles-rtl-ax5-studio")
        let solid = app.buttons["appearance-material-solid"].firstMatch
        reveal(solid, in: app)
        XCTAssertGreaterThanOrEqual(solid.frame.height, 44)
        XCTAssertTrue(solid.isSelected)
        capture("styles-rtl-ax5-material")
    }
}
