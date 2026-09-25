import XCTest
@testable import Haiity

/// Guards the wiring between the recogniser and the field it is supposed to
/// fill.
///
/// This exists because the two were once disconnected: `SpeechDictation` wrote
/// every recognised word into its own `transcript`, the sheet's `TextField` was
/// bound to a separate `text`, and nothing copied between them. The recogniser
/// worked perfectly and the field stayed empty, so the symptom was "it doesn't
/// note down what was said" with no error anywhere. That is the shape of bug a
/// passing build and a green suite both miss.
final class VoiceCreateSheetTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        try String(contentsOf: sourceURL(path), encoding: .utf8)
    }

    /// The field must follow the recogniser while it is running. Without this the
    /// transcript is recognised and then dropped on the floor.
    func testTheTranscriptIsCopiedIntoTheField() throws {
        let sheet = try source("Haiity/Views/SpeakToCreateSheet.swift")
        XCTAssertTrue(sheet.contains(".onChange(of: dictation.transcript)"),
                      "the sheet must observe the recogniser's transcript")
        XCTAssertTrue(sheet.contains("text = spoken"),
                      "the recognised words must be assigned to the field's state")
        // And the field has to be bound to that same state, not to a copy.
        XCTAssertTrue(sheet.contains("text: $text"),
                      "the field must stay bound to the state that receives the transcript")
    }

    /// The last partial result can arrive after listening has ended, so the final
    /// text is taken before the stop rather than relied on to arrive in time.
    func testTheFinalTranscriptIsTakenBeforeListeningStops() throws {
        let sheet = try source("Haiity/Views/SpeakToCreateSheet.swift")
        let stop = try XCTUnwrap(sheet.range(of: "private func stopEverything()"))
        let body = sheet[stop.upperBound...].prefix(420)
        let takesText = body.range(of: "text = dictation.transcript")
        let stops = body.range(of: "dictation.stop()")
        XCTAssertNotNil(takesText)
        XCTAssertNotNil(stops)
        XCTAssertTrue(takesText!.lowerBound < stops!.lowerBound,
                      "the transcript must be read before stop() ends the session")
    }

    /// A recogniser that fails has to say so. Falling through to a plain stop
    /// made a broken session look exactly like silence.
    func testARecogniserFailureIsNotIndistinguishableFromSilence() throws {
        let dictation = try source("Haiity/Services/SpeechDictation.swift")
        let callback = try XCTUnwrap(dictation.range(of: "recognitionTask(with: request)"))
        let body = dictation[callback.upperBound...].prefix(1200)
        XCTAssertTrue(body.contains("if let error"),
                      "the recognition callback must handle an error explicitly")
        XCTAssertTrue(body.contains("state = .failed"),
                      "a failed recognition must set a state the sheet can explain")
    }

    /// The sheet's own control and the standing button both need stable
    /// identifiers, because they are the only handles the UI tests have.
    func testTheVoiceControlsRemainAddressable() throws {
        let sheet = try source("Haiity/Views/SpeakToCreateSheet.swift")
        for identifier in ["speak-to-create-toggle", "speak-to-create-text",
                           "speak-to-create-confirm", "speak-to-create-close"] {
            XCTAssertTrue(sheet.contains(identifier), "missing identifier: \(identifier)")
        }
        let content = try source("Haiity/Views/ContentView.swift")
        XCTAssertTrue(content.contains("accessibilityIdentifier(\"speak-to-create\")"),
                      "the standing button needs its own identifier")
    }

    /// The waveform is decorative, so it must stay out of the accessibility
    /// tree — but the panel around it carries the status, so it combines rather
    /// than ignores.
    func testTheWaveformIsDecorativeAndItsPanelIsNot() throws {
        let waveform = try source("Haiity/Views/VoiceWaveform.swift")
        XCTAssertTrue(waveform.contains(".accessibilityHidden(true)"),
                      "the bars carry no information a screen reader needs")
        let sheet = try source("Haiity/Views/SpeakToCreateSheet.swift")
        XCTAssertTrue(sheet.contains(".accessibilityElement(children: .combine)"),
                      "the status line must be read as one thing with the panel")
    }

    /// The audio teardown has to be complete and idempotent.
    ///
    /// It used to leave the engine running and the tap installed, so a session
    /// that failed once left live audio hardware behind and the next attempt put
    /// a second tap on an already-running engine. That is the shape of crash this
    /// guards, and it cannot be observed without a microphone.
    func testAudioTeardownStopsEverythingExactlyOnce() throws {
        let dictation = try source("Haiity/Services/SpeechDictation.swift")

        let teardown = try XCTUnwrap(dictation.range(of: "private func teardown()"))
        let body = dictation[teardown.upperBound...]
            .prefix(700)
        for step in ["engine.stop()", "removeTap", "tapInstalled = false",
                     "inputNode = nil", "task?.cancel()",
                     "setActive(false"] {
            XCTAssertTrue(body.contains(step),
                          "teardown must include \(step) or a failure leaves audio hardware live")
        }
        // Stopping must route through teardown rather than half-doing the job.
        let stop = try XCTUnwrap(dictation.range(of: "func stop() {"))
        let stopBody = dictation[stop.upperBound...].prefix(260)
        XCTAssertTrue(stopBody.contains("teardown()"),
                      "stop() must delegate to teardown so there is one owner of the audio stack")
        XCTAssertFalse(stopBody.contains("engine.inputNode"),
                       "stop() must not re-query inputNode; the captured instance is the one with the tap")
    }

    /// A tap is installed behind a guard, so a retry cannot stack a second one.
    func testTheTapIsInstalledBehindAGuard() throws {
        let dictation = try source("Haiity/Services/SpeechDictation.swift")
        XCTAssertTrue(dictation.contains("if tapInstalled { input.removeTap"),
                      "an existing tap must be removed before a new one is installed")
        XCTAssertTrue(dictation.contains("tapInstalled = true"),
                      "the guard has to be set once the tap exists")
        XCTAssertTrue(dictation.contains("inputNode = input"),
                      "the node the tap is installed on must be the one later removed")
    }

    // MARK: - The floating dock

    /// Liquid Glass belongs to the floating functional layer and nowhere else.
    /// The rule is easy to state and easy to break by accident, so it is pinned
    /// here rather than trusted: glass on a card, a panel or a text field is a
    /// defect, and the material exists to frame content, not to replace it.
    func testGlassStaysOnTheFloatingControlsAndOffTheContent() throws {
        let sheet = try source("Haiity/Views/SpeakToCreateSheet.swift")
        let content = ["waveformPanel", "transcriptField", "draftPreview"]
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
        // And the glass that IS there sits on the two floating controls.
        XCTAssertTrue(sheet.contains("ChromeGlass(id: \"speak-dock-mic\""))
        XCTAssertTrue(sheet.contains("ChromeGlass(id: \"speak-dock-create\""))
    }

    /// Two glass shapes in one container sharing a union is what makes iOS draw
    /// one surface instead of two panes of blur side by side.
    func testTheDockIsOneSurfaceNotTwo() throws {
        let sheet = try source("Haiity/Views/SpeakToCreateSheet.swift")
        XCTAssertTrue(sheet.contains("GlassEffectContainer"),
                      "the dock's glass needs a shared container to merge in")
        XCTAssertTrue(sheet.contains("union: dockUnion"),
                      "both shapes must join the same union")
        XCTAssertTrue(sheet.contains("private var dockUnion: String { \"speak-dock\" }"),
                      "the union has to be a single named identity")
        // One identifier each, so the two cannot be confused.
        XCTAssertTrue(sheet.contains("\"speak-dock-mic\""))
        XCTAssertTrue(sheet.contains("\"speak-dock-create\""))
    }

    /// The dock has to float, not sit in the scroll. A `safeAreaInset` is what
    /// keeps the content above it and the glass above the content.
    func testTheDockFloatsRatherThanScrollingWithTheContent() throws {
        let sheet = try source("Haiity/Views/SpeakToCreateSheet.swift")
        XCTAssertTrue(sheet.contains(".safeAreaInset(edge: .bottom, spacing: 0) { dock }"),
                      "the dock belongs in a safe-area inset, above the scroll")
        XCTAssertTrue(sheet.contains("dockClearance"),
                      "and the content needs room so the dock never covers the last card")
        // The create action is no longer part of the scrolling stack.
        let scroll = sheet.range(of: "ScrollView {")
        let stack = sheet.range(of: "VStack(spacing: Theme.Metrics.settingsSectionGap) {")
        XCTAssertTrue(scroll != nil && stack != nil)
        if let stack {
            let after = sheet[stack.upperBound...].prefix(400)
            XCTAssertFalse(after.contains("createControl"),
                           "the primary action must not scroll away with the content")
        }
    }

    /// Moving the microphone out of the card must not lose it. The status line
    /// promises this control, and it is the only way to stop a recording.
    func testTheMicrophoneIsStillReachableAndStillLabelled() throws {
        let sheet = try source("Haiity/Views/SpeakToCreateSheet.swift")
        XCTAssertTrue(sheet.contains("accessibilityIdentifier(\"speak-to-create-toggle\")"))
        XCTAssertTrue(sheet.contains("Aufnahme starten"))
        XCTAssertTrue(sheet.contains("Aufnahme beenden"))
        XCTAssertTrue(sheet.contains("func toggleListening()"))
        // The panel no longer holds a button, so it cannot answer a tap meant
        // for the dock.
        let panel = try XCTUnwrap(sheet.range(of: "private var waveformPanel"))
        let rest = sheet[panel.upperBound...]
        let end = rest.range(of: "\n    // MARK:")?.lowerBound ?? rest.endIndex
        XCTAssertFalse(String(rest[rest.startIndex..<end]).contains("Button {"),
                       "the content panel should no longer host a control")
    }

    /// Glass on both sides of the same dock is a hierarchy problem, so the
    /// microphone stays neutral and only the primary action is tinted.
    func testOnlyThePrimaryActionIsTinted() throws {
        let sheet = try source("Haiity/Views/SpeakToCreateSheet.swift")
        let mic = try XCTUnwrap(sheet.range(of: "private var micControl"))
        let create = try XCTUnwrap(sheet.range(of: "private var createControl"))
        let micBody = String(sheet[mic.upperBound..<create.lowerBound])

        XCTAssertFalse(micBody.contains("accent: palettes.style"),
                       "the microphone stays neutral glass; one tinted control is enough")
        let createBody = String(sheet[create.upperBound...].prefix(900))
        XCTAssertTrue(createBody.contains("accent: palettes.style"),
                      "the primary action is the one that gets the colour")
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

    private func sourceURL(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }
}
