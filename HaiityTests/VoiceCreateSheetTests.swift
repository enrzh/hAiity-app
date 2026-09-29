import XCTest
@testable import Haiity

/// The sheet, and the microphone that is no longer in it.
///
/// **Why the microphone is gone.** It was ours, which meant a microphone
/// permission and a speech-recognition permission, a second privacy promise in
/// App Store review, and a recogniser that was worse than the one already on the
/// keyboard. Dictation is the keyboard's job and it does it in the user's own
/// language under the system's own consent. The permission assertions below are
/// the load-bearing ones: they are what a future contributor would have to
/// deliberately undo to bring recording back.
///
/// What is left here is structure: one glass bar, content that carries no glass,
/// and the draft that waits for the full page.
final class VoiceCreateSheetTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        try String(contentsOf: sourceURL(path), encoding: .utf8)
    }

    // MARK: - No microphone, and nothing that needs permission

    /// The recogniser is gone, not merely hidden.
    ///
    /// Keeping the service around "in case" would be the interesting failure: it
    /// compiles, nothing calls it, and the next person to add a button has a
    /// working recogniser sitting one line away.
    func testTheRecogniserServiceIsGone() throws {
        let service = sourceURL("Haiity/Services/SpeechDictation.swift")
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.path),
                       "the recogniser service must be deleted, not left unused")
        let sheet = try source("Haiity/Views/SpeakToCreateSheet.swift")
        // Symbols, not the English word: the sheet is allowed to *mention*
        // dictation in a comment, because the keyboard's key is the replacement
        // and people have to be told about it.
        for gone in ["SpeechDictation", "dictation.state", "dictation.transcript",
                     "SFSpeechRecognizer", "micControl", "VoiceWaveform",
                     "toggleListening"] {
            XCTAssertFalse(sheet.contains(gone),
                           "the sheet must not carry \(gone) any more")
        }
    }

    /// No permission prompt, because nothing is recorded.
    ///
    /// This is the assertion that matters most in the whole file. A usage
    /// description that survives its feature is worse than one that was never
    /// written: the app keeps asking for the microphone in a sheet where the
    /// only way to speak is the keyboard.
    func testNeitherTheMicrophoneNorSpeechRecognitionIsDeclared() throws {
        let plist = try source("Haiity/Info.plist")
        XCTAssertFalse(plist.contains("NSMicrophoneUsageDescription"),
                       "nothing records audio, so the microphone prompt must be gone")
        XCTAssertFalse(plist.contains("NSSpeechRecognitionUsageDescription"),
                       "nothing transcribes, so the speech prompt must be gone")
    }

    /// The panel that used to draw the waveform now has to earn its space by
    /// pointing at the dictation key that replaced it. Someone arriving from the
    /// old in-app microphone will look for a button; this is where they are told
    /// there is one on the keyboard.
    func testThePromptPointsAtTheKeyboardsDictationKey() throws {
        let sheet = try source("Haiity/Views/SpeakToCreateSheet.swift")
        XCTAssertTrue(sheet.contains("Diktier-Taste"),
                      "the prompt must name the keyboard's dictation key, or speech looks gone")
        XCTAssertTrue(sheet.contains("private var promptPanel"),
                      "and it needs somewhere to live")
        // A placeholder is not a substitute: the sentence still goes in a field.
        XCTAssertTrue(sheet.contains("text: $text"),
                      "the sentence must stay a real, editable field")
        XCTAssertTrue(sheet.contains("speak-to-create-text"),
                      "with the identifier the UI tests drive it by")
    }

    /// Typing is the action now, so the sheet opens ready to type. This inverts
    /// the old rule, which held the keyboard down while a waveform had the half
    /// height to itself — there is no waveform to protect, and not raising the
    /// keyboard means one extra tap before anything can be said.
    func testTheSheetOpensReadyToType() throws {
        let sheet = try source("Haiity/Views/SpeakToCreateSheet.swift")
        XCTAssertTrue(sheet.contains(".onAppear { fieldFocused = true }"),
                      "the only way in now is the keyboard, so it should be up")
        XCTAssertTrue(sheet.contains("@FocusState private var fieldFocused"))
    }

    // MARK: - The floating dock

    /// Liquid Glass belongs to the floating functional layer and nowhere else.
    /// The rule is easy to state and easy to break by accident, so it is pinned
    /// here rather than trusted: glass on a card, a panel or a text field is a
    /// defect, and the material exists to frame content, not to replace it.
    func testGlassStaysOnTheFloatingControlsAndOffTheContent() throws {
        let sheet = try source("Haiity/Views/SpeakToCreateSheet.swift")
        let content = ["promptPanel", "transcriptField", "draftPreview"]
        for name in content {
            // Some of these are computed properties and one is a function, so the
            // declaration is matched either way rather than assuming a shape.
            let declaration = try XCTUnwrap(
                sheet.range(of: "private var \(name)")
                    ?? sheet.range(of: "private func \(name)"),
                "no declaration found for \(name)")
            let rest = sheet[declaration.upperBound...]
            let end = rest.range(of: "\n    // MARK:")?.lowerBound
                ?? rest.range(of: "\n    private var")?.lowerBound
                ?? rest.range(of: "\n    private func")?.lowerBound
                ?? rest.endIndex
            let body = String(rest[rest.startIndex..<end])
            XCTAssertFalse(body.contains("ChromeGlass"),
                           "\(name) is content, and content must not carry glass")
            XCTAssertFalse(body.contains("glassEffect"),
                           "\(name) is content, and content must not carry glass")
        }
        // And the glass that IS there sits on one bar, once.
        XCTAssertTrue(sheet.contains("ChromeGlass(id: \"speak-dock\""),
                      "the dock's glass belongs on the bar")
        XCTAssertEqual(sheet.components(separatedBy: "ChromeGlass(id:").count - 1, 1,
                       "the sheet carries exactly one glass surface")
    }

    /// ONE glass bar, and nothing inside it that is also glass.
    func testTheDockIsOneGlassBar() throws {
        let sheet = try source("Haiity/Views/SpeakToCreateSheet.swift")
        XCTAssertTrue(sheet.contains("kind: .bar"),
                      "the dock is a single bar; two pills do not read as a dock")
        XCTAssertTrue(sheet.contains("ChromeGlass(id: \"speak-dock\""),
                      "and the bar is the one thing carrying the glass")
        let create = try XCTUnwrap(sheet.range(of: "private var createControl"))
        XCTAssertFalse(sheet[create.upperBound...].prefix(700).contains("ChromeGlass"),
                       "the create action sits ON the glass, not in another layer of it")
    }

    /// The control needs a real surface of its own. The screenshot showed a bare
    /// glyph and a washed-out blob, which is what you get when a control relies
    /// on the bar behind it for its own contrast.
    func testTheCreateControlHasItsOwnVisibleSurface() throws {
        let sheet = try source("Haiity/Views/SpeakToCreateSheet.swift")
        let create = try XCTUnwrap(sheet.range(of: "private var createControl"))
        let end = try XCTUnwrap(sheet.range(of: "private var dockUnion"))
        XCTAssertTrue(sheet[create.upperBound..<end.lowerBound].contains("in: Capsule()"),
                      "the create action needs its own filled capsule")
    }

    /// The bar is glass, so nothing on it may also be glass, and the primary
    /// action is the one that is coloured.
    func testOnlyThePrimaryActionIsColoured() throws {
        let sheet = try source("Haiity/Views/SpeakToCreateSheet.swift")
        let create = try XCTUnwrap(sheet.range(of: "private var createControl"))
        XCTAssertTrue(sheet[create.upperBound...].prefix(1200)
            .contains("Theme.accentFill(palettes.style)"),
                      "the primary action is the one that is always coloured")
        // And it goes neutral rather than fading when there is nothing to create.
        XCTAssertTrue(sheet[create.upperBound...].prefix(1200)
            .contains("Color(.tertiarySystemFill)"),
                      "a faded accent reads as a rendering fault, not as disabled")
    }

    /// The dock has to float, not sit in the scroll. A `safeAreaInset` is what
    /// keeps the content above it and the glass above the content.
    func testTheDockFloatsRatherThanScrollingWithTheContent() throws {
        let sheet = try source("Haiity/Views/SpeakToCreateSheet.swift")
        XCTAssertTrue(sheet.contains(".safeAreaInset(edge: .bottom, spacing: 0) { dock }"),
                      "the dock belongs in a safe-area inset, above the scroll")
        XCTAssertTrue(sheet.contains("dockClearance"),
                      "and the content needs room so the dock never covers the last card")
        let scroll = sheet.range(of: "ScrollView {")
        let stack = sheet.range(of: "VStack(spacing: Theme.Metrics.settingsSectionGap) {")
        XCTAssertTrue(scroll != nil && stack != nil)
        if let stack {
            let after = sheet[stack.upperBound...].prefix(400)
            XCTAssertFalse(after.contains("createControl"),
                           "the primary action must not scroll away with the content")
        }
    }

    /// The glass component was private to ContentView, so the sheet could not
    /// reach the same material logic and a second copy would have drifted.
    func testTheSheetAndTheHubShareOneGlassComponent() throws {
        let glass = try source("Haiity/Views/ChromeGlass.swift")
        XCTAssertTrue(glass.contains("struct ChromeGlass"))
        XCTAssertFalse(glass.contains("private struct ChromeGlass"),
                       "shared, so both surfaces get the same material decisions")
        let content = try source("Haiity/Views/ContentView.swift")
        XCTAssertFalse(content.contains("private struct ChromeGlass"),
                       "the copy in ContentView is gone")
        XCTAssertTrue(content.contains("ChromeGlass("),
                      "and the hub still uses the shared one")
    }

    // MARK: - Detents and the draft

    /// Half a page to begin with, the full page once there is a sentence to look
    /// at. A half sheet is right for typing and wrong for deciding what a
    /// sentence became.
    func testTheSheetOpensAtHalfAndGrowsWhenThereIsSomethingToReview() throws {
        let sheet = try source("Haiity/Views/SpeakToCreateSheet.swift")
        XCTAssertTrue(sheet.contains("@State private var detent: PresentationDetent = .fraction(0.5)"),
                      "the sheet must open at half a page, not full")
        XCTAssertTrue(sheet.contains("presentationDetents([.fraction(0.5), .large], selection: $detent)"),
                      "both heights have to be offered, with the selection bound")
        XCTAssertTrue(sheet.contains("presentationDragIndicator(.visible)"),
                      "and it must be draggable by hand as well as automatic")
        XCTAssertTrue(sheet.contains("expandForReview()"),
                      "something has to move it to the full page")
        XCTAssertTrue(sheet.contains(".onChange(of: fieldFocused)"),
                      "tapping the text to edit also needs the room")
    }

    /// At half height the page behind stays usable, which is the point of a half
    /// sheet: you can see what you are adding to.
    func testHalfTheSheetLeavesThePageBehindUsable() throws {
        let sheet = try source("Haiity/Views/SpeakToCreateSheet.swift")
        XCTAssertTrue(sheet.contains("presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.5)))"),
                      "a half sheet that blocks the page behind it is just a tall sheet")
    }

    /// The main-page entry point is on the same glass as the rest of the floating
    /// chrome, and says what it is. It was a microphone, which read as "record a
    /// voice note" and clashed with the sheet's own mic and the keyboard's.
    func testTheMainPageEntryPointIsGlassAndNoLongerAMicrophone() throws {
        let content = try source("Haiity/Views/ContentView.swift")
        let button = try XCTUnwrap(content.range(of: "private var speakButton"))
        let body = content[button.upperBound...].prefix(1400)

        XCTAssertTrue(body.contains("ChromeGlass("),
                      "the main-page button belongs on the shared glass, like the other chrome")
        XCTAssertTrue(body.contains("kind: .circle"))
        XCTAssertTrue(body.contains("systemName: \"sparkles\""),
                      "a sparkle says what this is; a microphone said 'record something'")
        XCTAssertFalse(body.contains("systemName: \"mic.fill\""),
                       "there is no microphone left in the app to clash with")
        // Still the quieter of the floating controls: no drop shadow competing
        // with the toolbar's create action.
        XCTAssertFalse(body.contains(".shadow("),
                       "one prominent action per view; this one stays secondary")
    }

    /// The draft belongs at the full height only.
    ///
    /// It used to appear at half as well, and that is what produced the reported
    /// bug: the draft card does not fit at half, and arriving scrolled the
    /// sentence up under a transparent navigation bar — so the words being typed
    /// showed through "Abbrechen" and the title.
    func testTheDraftOnlyExistsOnTheFullPage() throws {
        let sheet = try source("Haiity/Views/SpeakToCreateSheet.swift")
        XCTAssertTrue(sheet.contains("if let draft, detent == .large {"),
                      "the draft card must wait for the full page")
        XCTAssertFalse(sheet.contains("if let draft {"),
                       "an ungated draft is the bug this replaces")
    }

    /// And the scroll that keeps the card clear of the dock waits for the same
    /// moment, so it can never move the sentence out of view.
    func testScrollingToTheDraftWaitsForTheFullPage() throws {
        let sheet = try source("Haiity/Views/SpeakToCreateSheet.swift")

        // Both things that can change the answer are watched, because neither
        // alone is sufficient: expanding happens when the field is focused, which
        // is before a word is typed, and the draft arrives after that.
        XCTAssertTrue(sheet.contains(".onChange(of: detent)"),
                      "the height has to be watched, or the scroll never runs")
        XCTAssertTrue(sheet.contains(".onChange(of: draft != nil)"),
                      "so does the draft arriving, or it scrolls against nothing")

        let helper = try XCTUnwrap(sheet.range(of: "private func scrollDraftIntoView"))
        let body = sheet[helper.upperBound...].prefix(400)
        XCTAssertTrue(body.contains("detent == .large"),
                      "half is for typing; scrolling there is the bug")
        XCTAssertTrue(body.contains("draft != nil"),
                      "and there is nothing to bring into view without one")
    }

    // MARK: - Turning the entry point off

    /// The button is a shortcut, not a habit, so it can be taken away — and the
    /// way it is gated matters: on the property itself, not only at the call
    /// site, so no other route can bring it back by accident.
    func testTheMainPageButtonRespectsThePreference() throws {
        let content = try source("Haiity/Views/ContentView.swift")
        XCTAssertTrue(content.contains("viewPreferences.dictateCreateEnabled"),
                      "the button must ask the preference before drawing itself")
    }

    func testTheCreateFromASentenceToggleIsOfferedInAppearance() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        XCTAssertTrue(more.contains("dictate-create-toggle"),
                      "the toggle needs an identifier the UI tests can find")
        XCTAssertTrue(more.contains("statsCards.dictateCreateEnabled"),
                      "and it must be bound to the preference")

        let button = try XCTUnwrap(more.range(of: "private var compactModeSection"))
        let body = more[button.upperBound...].prefix(2000)
        XCTAssertTrue(body.contains("dictate-create-toggle"),
                      "it belongs in Darstellung, next to the other view toggles")
    }

    /// On by default, and an older payload without the key keeps the button —
    /// otherwise adding the preference would silently take the button away from
    /// everyone who upgrades.
    func testThePreferenceDefaultsToOnAndSurvivesAnOlderPayload() throws {
        XCTAssertTrue(ViewPreferences().dictateCreateEnabled,
                      "a fresh install gets the button")

        let older = #"{"updatedAt":0,"statsCards":{"active":["today"],"customized":false},"compactMode":false}"#
        let decoded = try JSONDecoder().decode(ViewPreferences.self,
                                               from: Data(older.utf8))
        XCTAssertTrue(decoded.dictateCreateEnabled,
                      "a payload written before the preference existed must keep the button")
    }

    func testThePreferenceRoundTrips() throws {
        var prefs = ViewPreferences()
        prefs.dictateCreateEnabled = false
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(ViewPreferences.self, from: data)
        XCTAssertFalse(decoded.dictateCreateEnabled,
                       "turning it off has to survive a save and reload")
    }

    private func sourceURL(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }
}
