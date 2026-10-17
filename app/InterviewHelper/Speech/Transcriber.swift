import Foundation
import AVFoundation
import Speech

@MainActor @Observable
public final class Transcriber: NSObject {
    public enum AuthState: Sendable {
        case unknown, requesting, granted, denied
    }

    public var authState: AuthState = .unknown
    public var isListening = false
    public var lastError: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognizer: SFSpeechRecognizer?
    private var pipeline: AudioPipeline?
    private var onResult: (@MainActor @Sendable (String, Bool) -> Void)?

    public override init() {
        super.init()
        recognizer = SFSpeechRecognizer()
    }

    public func requestAuthorization() async {
        authState = .requesting
        // Sync fast paths: when the user already decided, make no async calls
        // at all (fewer callbacks crossing threads, no prompt re-trigger).
        let speechGranted: Bool
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechGranted = true
        case .denied, .restricted:
            speechGranted = false
        case .notDetermined:
            speechGranted = await requestSpeechAuthorization()
        @unknown default:
            speechGranted = false
        }
        let micGranted: Bool
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            micGranted = true
        case .denied:
            micGranted = false
        case .undetermined:
            micGranted = await AVAudioApplication.requestRecordPermission()
        @unknown default:
            micGranted = false
        }
        authState = (speechGranted && micGranted) ? .granted : .denied
    }

    /// Single-resume wrapper: the system auth handler must resume its
    /// continuation exactly once — a second resume traps (EXC_BREAKPOINT).
    private func requestSpeechAuthorization() async -> Bool {
        let gate = ResumeGate()
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                guard gate.claim() else { return }
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    @discardableResult
    public func start(onResult: @escaping @MainActor @Sendable (String, Bool) -> Void) -> Bool {
        if isListening { return true }
        self.onResult = onResult
        guard let recognizer = recognizer ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            lastError = "Speech recognition unavailable"
            return false
        }
        self.recognizer = recognizer
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: [])
        } catch {
            lastError = error.localizedDescription
            return false
        }
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        // Without microphone access the input format has no channels and
        // installTap traps (SIGABRT). Never tap an invalid format.
        guard format.channelCount > 0, format.sampleRate > 0 else {
            lastError = "Microphone unavailable. Grant microphone access in Settings and try again."
            try? AVAudioSession.sharedInstance().setActive(false)
            return false
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        // The tap and the recognition callback run on Apple's real-time and
        // Speech queues — NOT the main thread. They must be nonisolated:
        // closures created in this @MainActor context inherit MainActor
        // isolation, and Swift 6 traps when they execute elsewhere
        // (dispatch_assert_queue → EXC_BREAKPOINT). AudioPipeline builds them
        // in a nonisolated context; UI work hops back via Task.
        let pipeline = AudioPipeline(owner: self, request: request, node: inputNode, format: format)
        pipeline.installTap()
        recognitionRequest = request
        audioEngine = engine
        self.pipeline = pipeline
        recognitionTask = recognizer.recognitionTask(with: request, resultHandler: pipeline.makeResultHandler())
        do {
            engine.prepare()
            try engine.start()
            isListening = true
            return true
        } catch {
            lastError = error.localizedDescription
            stop()
            return false
        }
    }

    /// MainActor entry point for pipeline callbacks (text/error only —
    /// everything crossing the queue boundary is Sendable by construction).
    fileprivate func handlePipelineResult(hasResult: Bool, text: String, isFinal: Bool, errorDescription: String?) {
        guard isListening else { return }
        if hasResult, !text.isEmpty {
            onResult?(text, isFinal)
        }
        if let errorDescription {
            lastError = errorDescription
            stop()
        }
        // Keep listening on final results — only the user stops listening.
    }

    public func stop() {
        recognitionTask?.cancel()
        recognitionTask = nil
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        recognitionRequest = nil
        pipeline = nil
        onResult = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        isListening = false
    }

    public func injectTranscript(_ text: String, isFinal: Bool = true) {
        Task { @MainActor in
            self.onResult?(text, isFinal)
        }
    }
}

/// Owns the pieces of a listening session that execute off the main thread:
/// the real-time audio tap and the Speech-callback handler. Everything here
/// is nonisolated, so Swift 6 emits no main-executor assertions for it.
private struct AudioPipeline: @unchecked Sendable {
    weak var owner: Transcriber?
    let request: SFSpeechAudioBufferRecognitionRequest
    let node: AVAudioInputNode
    let format: AVAudioFormat

    nonisolated func installTap() {
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [request] buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated func makeResultHandler() -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { [pipeline = self] result, error in
            // Reduce to Sendable values before hopping; SFSpeech types and
            // Error existentials must not cross into the MainActor Task.
            let hasResult = result != nil
            let text = result?.bestTranscription.formattedString ?? ""
            let isFinal = result?.isFinal ?? false
            let errorDescription = error?.localizedDescription
            Task { @MainActor in
                guard let owner = pipeline.owner else { return }
                owner.handlePipelineResult(
                    hasResult: hasResult,
                    text: text,
                    isFinal: isFinal,
                    errorDescription: errorDescription
                )
            }
        }
    }
}

/// One-shot claim box: guards a checked continuation against double-resume
/// when a system callback fires more than once (a second resume traps).
private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            if claimed { return false }
            claimed = true
            return true
        }
    }
}
