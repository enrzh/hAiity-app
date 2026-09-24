import AVFoundation
import Foundation
import Observation
import Speech

/// Live speech-to-text for the one thing the app asks a voice for: a sentence
/// that becomes a habit.
///
/// **Why the app runs its own recogniser.** The system keyboard's dictation would
/// put the words in the field for free, but it exposes no audio amplitude, so
/// there is nothing to animate and no way to know when the person is speaking
/// versus pausing. The waveform and the "still listening" state both come from
/// the buffers, so the recogniser has to be ours. The cost is two permission
/// prompts, which is the price of a voice feature and is asked for only at the
/// moment of the tap.
///
/// **On-device preferred, and honest about the rest.** `requiresOnDeviceRecognition`
/// is set and never relaxed, and a recogniser that cannot do it locally is
/// treated as unavailable rather than quietly falling back to a server.
///
/// What this class does *not* claim is that nothing is transmitted. Apple's own
/// permission dialog states that speech data is sent to Apple to process the
/// request, and it is shown directly above this app's usage string. So the usage
/// string deliberately says what is true — what the recording is for, and when it
/// stops — and says nothing about transport, because the app cannot promise
/// anything the system prompt contradicts. `requiresOnDeviceRecognition` is a
/// request for local processing, not a guarantee the app gets to advertise.
///
/// **Nothing starts without a tap.** The microphone is opened by `start()` and
/// released by `stop()`. There is no ambient listening, no wake phrase, and
/// nothing that records in the background.
@Observable
@MainActor
final class SpeechDictation {

    enum State: Equatable {
        case idle
        case requestingPermission
        case denied
        case unavailable(String)
        case listening
        case failed(String)

        var isListening: Bool { self == .listening }
    }

    private(set) var state: State = .idle
    /// The transcript so far, updated on every partial result.
    private(set) var transcript: String = ""
    /// 0…1, smoothed. Drives the waveform; it is the only reason this is ours.
    private(set) var level: Double = 0

    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private let engine = AVAudioEngine()
    /// The input node is captured once and reused. Reaching through
    /// `engine.inputNode` a second time can hand back a different wrapper, and
    /// removing a tap from a node it was never installed on leaves the real one
    /// running.
    @ObservationIgnored private var inputNode: AVAudioNode?
    /// Guards the tap so it is installed once and removed once, whatever path
    /// gets us here. Installing a second tap on a live engine is the classic way
    /// to take an app down with an audio crash.
    @ObservationIgnored private var tapInstalled = false
    /// Smooths the bars. A raw amplitude track looks like a seismograph; speech
    /// reads better with a short rise and a slower fall.
    @ObservationIgnored private var smoothedLevel: Double = 0

    private let localeIdentifier: String

    init(localeIdentifier: String = Locale.current.language.languageCode?.identifier ?? "en") {
        self.localeIdentifier = localeIdentifier
    }

    // MARK: - Permission

    /// Asks for the microphone and speech permission, in that order — the
    /// recogniser is useless without the microphone, so it is not worth asking
    /// for both at once.
    func requestPermission() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speech else { return false }

        let microphone = await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        return microphone
    }

    // MARK: - Recording

    /// Opens the microphone and starts transcribing. Returns false when the
    /// recogniser could not start, leaving `state` as the reason.
    @discardableResult
    func start() async -> Bool {
        guard !state.isListening else { return true }
        guard await requestPermission() else {
            state = .denied
            return false
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.isAvailable else {
            state = .unavailable(String(localized: "Spracherkennung ist hier nicht verfügbar."))
            return false
        }
        // The promise is on-device or nothing. A recogniser that would need a
        // server is not one we can use.
        guard recognizer.supportsOnDeviceRecognition else {
            state = .unavailable(String(localized: "Erkennung nur auf diesem Gerät ist hier nicht verfügbar."))
            return false
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        self.request = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .failed(String(localized: "Das Mikrofon ließ sich nicht öffnen."))
            teardown()
            return false
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // A zero sample rate means the hardware gave us nothing usable. Asking
        // `inputNode` for a format at all can also raise on some routes, which
        // Swift cannot catch, so the check has to happen before the tap exists.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            state = .failed(String(localized: "Das Mikrofon ließ sich nicht öffnen."))
            teardown()
            return false
        }
        inputNode = input
        if tapInstalled { input.removeTap(onBus: 0) }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let amplitude = Self.rmsLevel(of: buffer)
            Task { @MainActor [weak self] in self?.absorb(amplitude) }
        }
        tapInstalled = true

        engine.prepare()
        do {
            try engine.start()
        } catch {
            state = .failed(String(localized: "Das Mikrofon ließ sich nicht öffnen."))
            teardown()
            return false
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // The callback is not on the main actor; the state and the
            // transcript are, so the hop is explicit rather than assumed.
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if let error {
                    // Previously this fell through to `stop()`, so a failed
                    // session was indistinguishable from finishing normally:
                    // the waveform froze and the status line went back to
                    // "Tippe auf den Knopf" with nothing said, which reads as
                    // "it did not hear me" rather than "it broke".
                    NSLog("SpeechDictation: recognition failed: %@", String(describing: error))
                    self.teardown()
                    self.state = .failed(String(localized: "Erkennung ist fehlgeschlagen."))
                    return
                }
                if result?.isFinal == true {
                    self.stop()
                }
            }
        }
        state = .listening
        return true
    }

    func stop() {
        guard state.isListening || engine.isRunning || tapInstalled else { return }
        teardown()
        state = .idle
    }

    /// Clears the transcript so the sheet can be reused for a second sentence.
    func reset() {
        stop()
        transcript = ""
        level = 0
        smoothedLevel = 0
        if case .failed = state { state = .idle }
        if case .unavailable = state { state = .idle }
    }

    /// Stop everything, in the only order that is safe, and do it idempotently.
    ///
    /// This used to leave the engine running. Every failure path called it, so a
    /// session that failed once left a live engine with a live tap, and the next
    /// attempt installed a second tap on top of it. Engine first, then the tap,
    /// then the session, then the references.
    private func teardown() {
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            inputNode?.removeTap(onBus: 0)
            tapInstalled = false
        }
        inputNode = nil
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        recognizer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Level

    /// Rise fast, fall slow, so the bars read as a voice rather than noise.
    private func absorb(_ amplitude: Double) {
        let target = min(1, max(0, amplitude))
        smoothedLevel = target > smoothedLevel
            ? smoothedLevel + (target - smoothedLevel) * 0.55
            : smoothedLevel + (target - smoothedLevel) * 0.12
        level = smoothedLevel
    }

    /// RMS of an int16 buffer, normalised against a level that leaves headroom
    /// so ordinary speech does not peg every bar at full height.
    static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Double = 0
        for index in 0..<count {
            let sample = Double(channel[index])
            sum += sample * sample
        }
        return min(1, sqrt(sum / Double(count)) * 6)
    }
}
