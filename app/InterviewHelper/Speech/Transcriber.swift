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
    private var onResult: (@MainActor @Sendable (String, Bool) -> Void)?

    public override init() {
        super.init()
        recognizer = SFSpeechRecognizer()
    }

    public func requestAuthorization() async {
        authState = .requesting
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        let micGranted = await AVAudioApplication.requestRecordPermission()
        authState = (speechGranted && micGranted) ? .granted : .denied
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
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        recognitionRequest = request
        audioEngine = engine
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.isListening else { return }
                if let result = result, !result.bestTranscription.formattedString.isEmpty {
                    self.onResult?(result.bestTranscription.formattedString, result.isFinal)
                }
                if error != nil {
                    self.lastError = error?.localizedDescription
                    self.stop()
                } else if result?.isFinal == true {
                    self.stop()
                }
            }
        }
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

    public func stop() {
        recognitionTask?.cancel()
        recognitionTask = nil
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        recognitionRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        isListening = false
    }

    public func injectTranscript(_ text: String, isFinal: Bool = true) {
        Task { @MainActor in
            self.onResult?(text, isFinal)
        }
    }
}
