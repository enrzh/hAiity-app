import AVFoundation
import Foundation
import Observation
import Speech

@Observable
@MainActor
final class SpeechDictation {
    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        case finalizing
        case denied
        case unavailable(String)
        case failed(String)

        var isActive: Bool {
            switch self {
            case .requestingPermission, .listening, .finalizing: true
            default: false
            }
        }
    }

    typealias RecognitionCallback = @MainActor (_ transcript: String?, _ isFinal: Bool, _ error: String?) -> Void

    private(set) var state: State = .idle
    private(set) var transcript = ""

    @ObservationIgnored private let localeIdentifier: String
    @ObservationIgnored private let permissionRequest: (() async -> Bool)?
    @ObservationIgnored private let recognitionStart: ((@escaping RecognitionCallback) throws -> Void)?
    @ObservationIgnored private let recognitionFinish: (() -> Void)?
    @ObservationIgnored private let recognitionCancel: (() -> Void)?
    @ObservationIgnored private let recognitionComplete: (() -> Void)?
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var recognitionActive = false
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var inputNode: AVAudioNode?
    @ObservationIgnored private var tapInstalled = false
    @ObservationIgnored private var previousAudioCategory: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var finalizationTask: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0

    init(
        localeIdentifier: String = Locale.current.identifier,
        requestPermissions: (() async -> Bool)? = nil,
        startRecognition: ((@escaping RecognitionCallback) throws -> Void)? = nil,
        finishRecognition: (() -> Void)? = nil,
        cancelRecognition: (() -> Void)? = nil,
        completeRecognition: (() -> Void)? = nil
    ) {
        self.localeIdentifier = localeIdentifier
        self.permissionRequest = requestPermissions
        self.recognitionStart = startRecognition
        self.recognitionFinish = finishRecognition
        self.recognitionCancel = cancelRecognition
        self.recognitionComplete = completeRecognition
    }

    static func makeForCreationInput() -> SpeechDictation {
        #if DEBUG && targetEnvironment(simulator)
        if DesignFixture.scenario != nil {
            switch ProcessInfo.processInfo.environment["HAIITY_TEST_DICTATION"] {
            case "denied":
                return SpeechDictation(requestPermissions: { false }, startRecognition: { _ in })
            case "unavailable":
                return SpeechDictation(requestPermissions: { true }, startRecognition: { _ in
                    throw DictationError.recognitionUnavailable
                })
            case "transcript":
                var callback: RecognitionCallback?
                return SpeechDictation(
                    requestPermissions: { true },
                    startRecognition: {
                        callback = $0
                        $0("Zahnarzt 15 10 2099", false, nil)
                    },
                    finishRecognition: {
                        let final = callback
                        Task { @MainActor in final?("Zahnarzt 15 10 2099 10 Uhr", true, nil) }
                    },
                    cancelRecognition: { callback = nil },
                    completeRecognition: { callback = nil }
                )
            default: break
            }
        }
        #endif
        return SpeechDictation()
    }

    func start(localeIdentifier: String? = nil) async {
        guard !state.isActive else { return }
        generation &+= 1
        let session = generation
        state = .requestingPermission

        let authorized: Bool
        if let permissionRequest {
            authorized = await permissionRequest()
        } else {
            authorized = await requestSystemPermissions(for: session)
        }
        guard generation == session else { return }
        guard !Task.isCancelled else { cancel(); return }
        guard authorized else {
            state = .denied
            return
        }

        if recognitionStart == nil {
            guard let identifier = Self.recognitionLocaleIdentifier(
                for: localeIdentifier ?? self.localeIdentifier,
                supportedIdentifiers: SFSpeechRecognizer.supportedLocales().map(\.identifier)),
                  let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)),
                  recognizer.isAvailable,
                  recognizer.supportsOnDeviceRecognition else {
                state = .unavailable(Self.unavailableMessage)
                return
            }
            self.recognizer = recognizer
        }

        do {
            transcript = ""
            recognitionActive = true
            try beginRecognition { [weak self] text, isFinal, error in
                guard let self, self.generation == session else { return }
                if let text { self.transcript = text }
                if isFinal {
                    self.finishSession(session: session, state: .idle, cancel: false)
                } else if error != nil {
                    self.finishSession(session: session,
                        state: .failed(String(localized: "Diktieren konnte nicht abgeschlossen werden. Bitte versuche es erneut.")), cancel: true)
                }
            }
            guard generation == session else { return }
            state = .listening
            if recognitionStart == nil { installAudioObservers(for: session) }
        } catch {
            guard generation == session else { return }
            let nextState: State
            switch error {
            case DictationError.recognitionUnavailable:
                nextState = .unavailable(Self.unavailableMessage)
            case DictationError.microphoneUnavailable:
                nextState = .failed(String(localized: "Das Mikrofon ist nicht verfügbar. Du kannst weiter tippen."))
            default:
                nextState = .failed(String(localized: "Diktieren konnte nicht gestartet werden. Bitte versuche es erneut."))
            }
            finishSession(session: session, state: nextState, cancel: true)
        }
    }

    func stop() {
        if state == .requestingPermission {
            generation &+= 1
            state = .idle
            return
        }
        guard state == .listening else { return }
        state = .finalizing
        let session = generation
        if let recognitionFinish { recognitionFinish() }
        else if recognitionStart == nil { stopCaptureAndEndAudio() }
        guard generation == session else { return }
        finalizationTask?.cancel()
        finalizationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, self.generation == session,
                  self.state == .finalizing else { return }
            self.finishSession(session: session, state: .idle, cancel: true)
        }
    }

    func cancel() {
        generation &+= 1
        finalizationTask?.cancel()
        finalizationTask = nil
        releaseResources(cancel: true)
        state = .idle
    }

    func reset() {
        guard !state.isActive else { return }
        transcript = ""
        if state != .denied { state = .idle }
    }

    static func mergedTranscript(prefix: String, transcript: String) -> String {
        guard !transcript.isEmpty else { return prefix }
        guard !prefix.isEmpty else { return transcript }
        let hasBoundaryWhitespace = prefix.last?.isWhitespace == true || transcript.first?.isWhitespace == true
        return prefix + (hasBoundaryWhitespace ? "" : " ") + transcript
    }

    static func recognitionLocaleIdentifier(for identifier: String, supportedIdentifiers: [String]) -> String? {
        let requested = Locale(identifier: identifier)
        let candidates = supportedIdentifiers.sorted().filter {
            let supported = Locale(identifier: $0)
            return supported.language.languageCode == requested.language.languageCode
                && supported.language.script == requested.language.script
                && (requested.region == nil || supported.region == requested.region)
        }
        // A full locale keeps its region; a language-only preference uses a stable default.
        let preferred = ["de": "de-DE", "en": "en-US"][requested.language.languageCode?.identifier ?? ""]
        return candidates.first { $0.replacingOccurrences(of: "_", with: "-") == preferred }
            ?? candidates.first
    }

    private func beginRecognition(_ callback: @escaping RecognitionCallback) throws {
        if let recognitionStart {
            try recognitionStart(callback)
            return
        }

        let engine = AVAudioEngine()
        self.engine = engine
        let session = AVAudioSession.sharedInstance()
        previousAudioCategory = (session.category, session.mode, session.categoryOptions)
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw DictationError.microphoneUnavailable
        }
        inputNode = input
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()
        task = recognizer?.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let failed = error != nil
            Task { @MainActor in callback(text, isFinal, failed ? "failed" : nil) }
        }
    }

    private func stopCaptureAndEndAudio() {
        if engine?.isRunning == true { engine?.stop() }
        if tapInstalled {
            inputNode?.removeTap(onBus: 0)
            tapInstalled = false
        }
        inputNode = nil
        request?.endAudio()
    }

    private func finishSession(session: UInt64, state nextState: State, cancel: Bool) {
        guard generation == session else { return }
        generation &+= 1
        finalizationTask?.cancel()
        finalizationTask = nil
        releaseResources(cancel: cancel)
        state = nextState
    }

    private func releaseResources(cancel: Bool) {
        guard recognitionActive else { return }
        recognitionActive = false
        if recognitionStart != nil {
            if cancel { recognitionCancel?() } else { recognitionComplete?() }
        } else {
            stopCaptureAndEndAudio()
            if cancel { task?.cancel() }
            task = nil
            request = nil
            recognizer = nil
            engine = nil
            restoreAudioSession()
            removeAudioObservers()
        }
    }

    private func restoreAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        if let previousAudioCategory {
            try? session.setCategory(previousAudioCategory.0,
                                     mode: previousAudioCategory.1,
                                     options: previousAudioCategory.2)
            self.previousAudioCategory = nil
        }
    }

    private func installAudioObservers(for session: UInt64) {
        let center = NotificationCenter.default
        notificationTokens = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.generation == session else { return }
                    self.finishSession(session: session,
                        state: .failed(String(localized: "Die Audioaufnahme wurde unterbrochen. Bitte versuche es erneut.")), cancel: true)
                }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.generation == session else { return }
                    self.finishSession(session: session,
                        state: .failed(String(localized: "Die Mikrofonverbindung wurde getrennt. Bitte versuche es erneut.")), cancel: true)
                }
            }
        ]
    }

    private func removeAudioObservers() {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        notificationTokens.removeAll()
    }

    private func requestSystemPermissions(for session: UInt64) async -> Bool {
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAuthorized, generation == session, !Task.isCancelled else { return false }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    private enum DictationError: Error {
        case microphoneUnavailable
        case recognitionUnavailable
    }

    private static var unavailableMessage: String {
        String(localized: "Diktieren auf diesem Gerät ist für diese Sprache nicht verfügbar. Du kannst weiter tippen.")
    }
}
