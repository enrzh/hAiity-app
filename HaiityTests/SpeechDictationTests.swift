import XCTest
@testable import Haiity

@MainActor
final class SpeechDictationTests: XCTestCase {
    func testMergedTranscriptPreservesPrefixAndReplacesPartialText() {
        let prefix = "Remember to call"
        let firstPartial = SpeechDictation.mergedTranscript(prefix: prefix, transcript: " my dentist")
        let laterPartial = SpeechDictation.mergedTranscript(prefix: prefix, transcript: " my dentist tomorrow")

        XCTAssertEqual(SpeechDictation.mergedTranscript(prefix: prefix, transcript: ""), prefix)
        XCTAssertEqual(firstPartial, "Remember to call my dentist")
        XCTAssertEqual(laterPartial, "Remember to call my dentist tomorrow")
        XCTAssertEqual(SpeechDictation.mergedTranscript(prefix: "Remember to call ", transcript: "my dentist"),
                       "Remember to call my dentist")
        XCTAssertEqual(SpeechDictation.mergedTranscript(prefix: "", transcript: "my dentist"), "my dentist")
        XCTAssertEqual(SpeechDictation.mergedTranscript(prefix: "Remember\n", transcript: "my dentist"),
                       "Remember\nmy dentist")
        XCTAssertEqual(SpeechDictation.mergedTranscript(prefix: laterPartial, transcript: "at ten"),
                       "Remember to call my dentist tomorrow at ten")
    }

    func testCancelWhilePermissionIsPendingIgnoresTheLateGrant() async {
        let requested = expectation(description: "Permission requested")
        var permission: CheckedContinuation<Bool, Never>?
        var starts = 0
        var cancels = 0
        let service = SpeechDictation(
            requestPermissions: {
                await withCheckedContinuation {
                    permission = $0
                    requested.fulfill()
                }
            },
            startRecognition: { _ in starts += 1 },
            cancelRecognition: { cancels += 1 }
        )

        let start = Task { await service.start() }
        await fulfillment(of: [requested], timeout: 1)
        XCTAssertEqual(service.state, .requestingPermission)
        service.cancel()
        service.cancel()
        permission?.resume(returning: true)
        await start.value

        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(cancels, 0)
    }

    func testConcurrentStartsShareOnePermissionAndRecognitionSession() async {
        let requested = expectation(description: "Permission requested")
        var permission: CheckedContinuation<Bool, Never>?
        var permissionCalls = 0
        var starts = 0
        let service = SpeechDictation(
            requestPermissions: {
                permissionCalls += 1
                return await withCheckedContinuation {
                    permission = $0
                    requested.fulfill()
                }
            },
            startRecognition: { _ in starts += 1 }
        )

        let first = Task { await service.start() }
        await fulfillment(of: [requested], timeout: 1)
        await service.start()
        permission?.resume(returning: true)
        await first.value

        XCTAssertEqual(permissionCalls, 1)
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(service.state, .listening)
        service.cancel()
    }

    func testPartialResultsReplaceTranscriptAndStopWaitsForFinalResult() async {
        var callback: SpeechDictation.RecognitionCallback?
        var finishCalls = 0
        var cancelCalls = 0
        var completeCalls = 0
        let service = SpeechDictation(
            requestPermissions: { true },
            startRecognition: { callback = $0 },
            finishRecognition: { finishCalls += 1 },
            cancelRecognition: { cancelCalls += 1 },
            completeRecognition: { completeCalls += 1 }
        )

        await service.start()
        callback?("Set an alarm", false, nil)
        callback?("Set an alarm for seven", false, nil)
        XCTAssertEqual(service.transcript, "Set an alarm for seven")

        service.stop()
        service.stop()
        XCTAssertEqual(service.state, .finalizing)
        XCTAssertEqual(finishCalls, 1)
        callback?("Set an alarm for 7 AM", true, nil)
        callback?("Late words", false, "Late error")
        service.cancel()

        XCTAssertEqual(service.transcript, "Set an alarm for 7 AM")
        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(completeCalls, 1)
        XCTAssertEqual(cancelCalls, 0)
    }

    func testCancelInvalidatesLateRecognitionResultAndCleansOnce() async {
        var callback: SpeechDictation.RecognitionCallback?
        var cancelCalls = 0
        let service = SpeechDictation(
            requestPermissions: { true },
            startRecognition: { callback = $0 },
            cancelRecognition: { cancelCalls += 1 }
        )

        await service.start()
        callback?("Before cancel", false, nil)
        service.stop()
        XCTAssertEqual(service.state, .finalizing)
        service.cancel()
        service.cancel()
        callback?("Late words", true, nil)

        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(service.transcript, "Before cancel")
        XCTAssertEqual(cancelCalls, 1)
    }

    func testStopWithoutFinalResultRetainsPartialAndCleansOnce() async {
        let finalized = expectation(description: "Finalization timed out")
        var callback: SpeechDictation.RecognitionCallback?
        var cancels = 0
        let service = SpeechDictation(
            requestPermissions: { true },
            startRecognition: { callback = $0 },
            cancelRecognition: {
                cancels += 1
                finalized.fulfill()
            }
        )
        await service.start()
        callback?("Usable partial", false, nil)
        service.stop()
        await fulfillment(of: [finalized], timeout: 5)
        callback?("Late final", true, nil)
        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(service.transcript, "Usable partial")
        service.cancel()
        XCTAssertEqual(cancels, 1)
    }

    func testIdleAndDeniedCancelDoNotCleanUnstartedRecognition() async {
        var permissionCalls = 0
        var starts = 0
        var cancels = 0
        let service = SpeechDictation(
            requestPermissions: { permissionCalls += 1; return false },
            startRecognition: { _ in starts += 1 },
            cancelRecognition: { cancels += 1 }
        )
        XCTAssertEqual(permissionCalls, 0)
        service.cancel()
        service.cancel()
        await service.start()
        XCTAssertEqual(service.state, .denied)
        XCTAssertFalse(service.state.isActive)
        service.cancel()
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(cancels, 0)
    }

    func testOldPermissionResultCannotChangeRestartedSession() async {
        let requested = expectation(description: "First permission requested")
        var permission: CheckedContinuation<Bool, Never>?
        var permissionCalls = 0
        var starts = 0
        let service = SpeechDictation(
            requestPermissions: {
                permissionCalls += 1
                guard permissionCalls == 1 else { return true }
                return await withCheckedContinuation {
                    permission = $0
                    requested.fulfill()
                }
            },
            startRecognition: { _ in starts += 1 }
        )
        let first = Task { await service.start() }
        await fulfillment(of: [requested], timeout: 1)
        service.stop()
        XCTAssertEqual(service.state, .idle)
        await service.start()
        permission?.resume(returning: false)
        await first.value
        XCTAssertEqual(service.state, .listening)
        XCTAssertEqual(starts, 1)
        service.cancel()
    }

    func testNaturalFinalInvalidatesCallbacksAcrossRestart() async {
        var callbacks: [SpeechDictation.RecognitionCallback] = []
        var completes = 0
        var cancels = 0
        let service = SpeechDictation(
            requestPermissions: { true },
            startRecognition: { callbacks.append($0) },
            cancelRecognition: { cancels += 1 },
            completeRecognition: { completes += 1 }
        )
        await service.start()
        callbacks[0]("Final text", true, nil)
        callbacks[0]("Late text", false, "Late error")
        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(service.transcript, "Final text")
        XCTAssertEqual(completes, 1)
        await service.start()
        callbacks[0]("Old final", true, nil)
        callbacks[1]("New partial", false, nil)
        XCTAssertEqual(service.state, .listening)
        XCTAssertEqual(service.transcript, "New partial")
        service.cancel()
        service.cancel()
        XCTAssertEqual(cancels, 1)
    }

    func testSynchronousFinalDuringStartCannotRestoreListening() async {
        var completes = 0
        let service = SpeechDictation(
            requestPermissions: { true },
            startRecognition: { $0("Immediate final", true, nil) },
            completeRecognition: { completes += 1 }
        )
        await service.start()
        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(service.transcript, "Immediate final")
        XCTAssertEqual(completes, 1)
    }

    func testRecognitionFailureRetainsTextAndHidesRawError() async {
        var callback: SpeechDictation.RecognitionCallback?
        var cancels = 0
        let service = SpeechDictation(
            requestPermissions: { true },
            startRecognition: { callback = $0 },
            cancelRecognition: { cancels += 1 }
        )
        await service.start()
        callback?("Usable text", false, nil)
        callback?(nil, false, "Private diagnostic details")
        callback?("Late text", true, nil)
        XCTAssertEqual(service.state, .failed(String(localized:
            "Diktieren konnte nicht abgeschlossen werden. Bitte versuche es erneut.")))
        XCTAssertEqual(service.transcript, "Usable text")
        service.cancel()
        XCTAssertEqual(cancels, 1)
    }

    func testStartupFailureCleansOnceAndInvalidatesCallback() async {
        var callback: SpeechDictation.RecognitionCallback?
        var cancels = 0
        let service = SpeechDictation(
            requestPermissions: { true },
            startRecognition: {
                callback = $0
                throw NSError(domain: "Private startup details", code: 1)
            },
            cancelRecognition: { cancels += 1 }
        )
        await service.start()
        callback?("Late text", true, nil)
        XCTAssertEqual(service.state, .failed(String(localized:
            "Diktieren konnte nicht gestartet werden. Bitte versuche es erneut.")))
        XCTAssertEqual(service.transcript, "")
        service.cancel()
        XCTAssertEqual(cancels, 1)
    }

    func testLocaleSelectionIgnoresFormattingModifiersAndKeepsRegionAndScript() {
        let supported = ["de-DE", "en-GB", "en-US", "zh-CN", "zh-TW"]
        for identifier in ["de-DE", "de_DE@calendar=buddhist", "de-DE-u-ca-buddhist"] {
            XCTAssertEqual(SpeechDictation.recognitionLocaleIdentifier(
                for: identifier, supportedIdentifiers: supported), "de-DE")
        }
        XCTAssertEqual(SpeechDictation.recognitionLocaleIdentifier(
            for: "en_GB@calendar=gregorian", supportedIdentifiers: supported), "en-GB")
        XCTAssertEqual(SpeechDictation.recognitionLocaleIdentifier(
            for: "en", supportedIdentifiers: supported.reversed()), "en-US")
        XCTAssertEqual(SpeechDictation.recognitionLocaleIdentifier(
            for: "zh-Hant-TW", supportedIdentifiers: supported), "zh-TW")
        XCTAssertNil(SpeechDictation.recognitionLocaleIdentifier(
            for: "zh-Hans-TW", supportedIdentifiers: supported))
        XCTAssertNil(SpeechDictation.recognitionLocaleIdentifier(
            for: "en-AU", supportedIdentifiers: supported))
        XCTAssertNil(SpeechDictation.recognitionLocaleIdentifier(
            for: "fr-FR", supportedIdentifiers: supported))
    }
}
