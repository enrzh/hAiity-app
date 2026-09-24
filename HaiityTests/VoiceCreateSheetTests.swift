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

    private func sourceURL(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }
}
