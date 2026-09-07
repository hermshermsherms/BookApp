import AVFoundation
import Foundation
import Speech

/// Microphone dictation and spoken replies for the reading buddy.
///
/// Both halves are on-device Apple frameworks — `SFSpeechRecognizer` turns
/// speech into text that fills the composer, and `AVSpeechSynthesizer` reads
/// replies back. Nothing extra goes over the network: the Claude call is the
/// same text request either way.
@MainActor
final class VoiceController: NSObject, ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var isSpeaking = false
    /// Live partial transcript while dictating.
    @Published private(set) var transcript = ""
    @Published var errorMessage: String?
    /// User toggle — when on, finished replies are read aloud.
    @Published var speakRepliesAloud = false

    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isAvailable: Bool {
        recognizer?.isAvailable == true
    }

    // MARK: - Permissions

    /// Asks for speech recognition and microphone access. Returns false if
    /// either is denied, so the caller can surface a single clear message.
    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            errorMessage = "Speech recognition access is off. Turn it on in Settings to dictate."
            return false
        }

        // The iOS 17 replacement and the older session call have the same shape;
        // both are wrapped rather than relying on an async overload existing.
        let micGranted: Bool = await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission {
                    continuation.resume(returning: $0)
                }
            }
        }
        guard micGranted else {
            errorMessage = "Microphone access is off. Turn it on in Settings to dictate."
            return false
        }
        return true
    }

    // MARK: - Dictation

    func startListening() async {
        guard !isListening else { return }
        guard await requestPermissions() else { return }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }

        // Never listen and speak at once — the mic would pick up the synthesizer.
        stopSpeaking()

        do {
            try configureSession(forRecording: true)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.channelCount > 0 else {
                errorMessage = "No audio input is available."
                teardown()
                return
            }

            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            engine.prepare()
            try engine.start()

            transcript = ""
            isListening = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if error != nil || result?.isFinal == true {
                        self.stopListening()
                    }
                }
            }
        } catch {
            errorMessage = "Couldn't start the microphone: \(error.localizedDescription)"
            teardown()
        }
    }

    /// Stops dictation and returns whatever was heard.
    @discardableResult
    func stopListening() -> String {
        guard isListening else { return transcript }
        teardown()
        return transcript
    }

    private func teardown() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
    }

    // MARK: - Spoken replies

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        stopSpeaking()
        try? configureSession(forRecording: false)

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.postUtteranceDelay = 0.1

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    // MARK: - Audio session

    private func configureSession(forRecording: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        if forRecording {
            try session.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth]
            )
        } else {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        }
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
}

extension VoiceController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in self?.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in self?.isSpeaking = false }
    }
}
