import AVFoundation
import Foundation
import Speech

/// Microphone input and spoken replies for the reading buddy.
///
/// Both halves are on-device Apple frameworks — `SFSpeechRecognizer` turns
/// speech into text and `AVSpeechSynthesizer` reads replies back. Nothing extra
/// goes over the network: the Claude call is the same text request either way.
///
/// Two modes share this object. Dictation fills the composer and stops when the
/// user taps stop. The hands-free conversation additionally needs to know when a
/// turn has ended and when a reply has finished playing, which is what
/// `onEndOfTurn`, `onIdleTimeout` and `onFinishedSpeaking` are for.
@MainActor
final class VoiceController: NSObject, ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var isSpeaking = false
    /// Live partial transcript while listening.
    @Published private(set) var transcript = ""
    /// Smoothed mic level, 0...1, for the waveform in voice mode.
    @Published private(set) var inputLevel: Double = 0
    @Published var errorMessage: String?
    /// User toggle in the text chat — when on, finished replies are read aloud.
    @Published var speakRepliesAloud = false

    // MARK: Hands-free hooks

    /// The speaker said something and has now been quiet long enough to count as
    /// the end of their turn. Carries the transcript; listening is already stopped.
    var onEndOfTurn: ((String) -> Void)?
    /// Nothing at all was said for `idleTimeout` seconds.
    var onIdleTimeout: (() -> Void)?
    /// Everything queued for the current reply has finished playing.
    var onFinishedSpeaking: (() -> Void)?

    /// Something took the audio session away — a phone call, another app, a
    /// headset being unplugged.
    var onInterrupted: (() -> Void)?

    /// How long a pause has to run before the turn is treated as finished.
    var endOfTurnSilence: TimeInterval = 1.4
    /// How long to hold the mic open when the speaker says nothing at all.
    var idleTimeout: TimeInterval = 20

    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Written from the audio tap on its own thread, drained on the main actor.
    private let meter = LevelMeter()
    private var monitor: Timer?
    private var listeningStartedAt = Date()
    private var lastVoiceActivity = Date()
    private var heardAnything = false

    /// Utterances still queued or playing for the current reply. Cleared wholesale
    /// when speech is stopped so late delegate callbacks can't fire the drain hook.
    private var liveUtterances: Set<ObjectIdentifier> = []
    /// True while a reply is still streaming in, so an empty queue isn't the end.
    private var expectsMoreSpeech = false
    /// In a hands-free conversation the audio session stays in `.playAndRecord`
    /// for the whole call instead of flipping category on every turn.
    private var isConversationSession = false

    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
        synthesizer.delegate = self

        // A call or another app taking the session leaves the engine dead but the
        // UI still saying "listening", so hand it back to the caller to reset.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let info = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard info == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor [weak self] in self?.handleInterruption() }
        }
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    private func handleInterruption() {
        guard isListening || isSpeaking else { return }
        stopListening()
        stopSpeaking()
        onInterrupted?()
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
            errorMessage = "Speech recognition access is off. Turn it on in Settings to talk."
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
            errorMessage = "Microphone access is off. Turn it on in Settings to talk."
            return false
        }
        return true
    }

    // MARK: - Conversation session

    /// Puts the audio session into the shape a back-and-forth call needs and
    /// keeps it there. Returns false if the user hasn't granted access.
    func beginConversationSession() async -> Bool {
        guard await requestPermissions() else { return false }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return false
        }
        do {
            isConversationSession = true
            try configureSession(forRecording: true)
            return true
        } catch {
            isConversationSession = false
            errorMessage = "Couldn't start audio: \(error.localizedDescription)"
            return false
        }
    }

    func endConversationSession() {
        isConversationSession = false
        onEndOfTurn = nil
        onIdleTimeout = nil
        onFinishedSpeaking = nil
        onInterrupted = nil
        stopListening()
        stopSpeaking()
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    // MARK: - Listening

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

            let meter = self.meter
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
                meter.record(buffer)
            }

            engine.prepare()
            try engine.start()

            transcript = ""
            heardAnything = false
            listeningStartedAt = Date()
            lastVoiceActivity = Date()
            isListening = true
            startMonitor()

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self, self.isListening else { return }
                    if let result {
                        let text = result.bestTranscription.formattedString
                        if text != self.transcript {
                            self.transcript = text
                            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                self.heardAnything = true
                            }
                            self.lastVoiceActivity = Date()
                        }
                    }
                    if error != nil || result?.isFinal == true {
                        // A final result during a call still ends that turn.
                        if self.onEndOfTurn != nil, self.heardAnything {
                            self.finishTurn()
                        } else {
                            self.stopListening()
                        }
                    }
                }
            }
        } catch {
            errorMessage = "Couldn't start the microphone: \(error.localizedDescription)"
            teardown()
        }
    }

    /// Stops listening and returns whatever was heard.
    @discardableResult
    func stopListening() -> String {
        guard isListening else { return transcript }
        teardown()
        return transcript
    }

    private func teardown() {
        monitor?.invalidate()
        monitor = nil
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
        if inputLevel != 0 { inputLevel = 0 }
        meter.reset()
    }

    // MARK: - Endpointing

    /// One timer covers both jobs: publishing the mic level for the waveform and
    /// deciding when the speaker has stopped talking.
    private func startMonitor() {
        monitor?.invalidate()
        monitor = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        guard isListening else { return }

        let level = meter.drain()
        // Only the voice-mode waveform reads this, and republishing it twenty
        // times a second would redraw the chat behind it for nothing.
        if isConversationSession {
            // Ease towards the new level so the waveform doesn't strobe.
            inputLevel = inputLevel * 0.6 + level * 0.4
        }
        // Loud frames count as activity too: the recogniser's partial results
        // lag behind the speaker, so silence alone is not enough to endpoint on.
        if level > 0.14 { lastVoiceActivity = Date() }

        guard onEndOfTurn != nil else { return }

        let quietFor = Date().timeIntervalSince(lastVoiceActivity)
        if heardAnything, quietFor >= endOfTurnSilence {
            finishTurn()
        } else if !heardAnything, Date().timeIntervalSince(listeningStartedAt) >= idleTimeout {
            stopListening()
            onIdleTimeout?()
        }
    }

    private func finishTurn() {
        let heard = stopListening().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty else { return }
        onEndOfTurn?(heard)
    }

    // MARK: - Spoken replies

    /// Speaks one block of text as a self-contained reply.
    func speak(_ text: String) {
        beginSpokenReply()
        enqueueSpokenChunk(text)
        endSpokenReply()
    }

    /// Starts a reply that will arrive in pieces. Chunks are spoken in order as
    /// they land, so the buddy starts talking before the whole reply has streamed.
    func beginSpokenReply() {
        stopSpeaking()
        expectsMoreSpeech = true
        if !isConversationSession {
            try? configureSession(forRecording: false)
        }
    }

    func enqueueSpokenChunk(_ text: String) {
        let trimmed = Self.speakable(text)
        guard !trimmed.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.postUtteranceDelay = 0.05

        liveUtterances.insert(ObjectIdentifier(utterance))
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// No more chunks are coming. If everything queued has already played, the
    /// reply is over now.
    func endSpokenReply() {
        expectsMoreSpeech = false
        if liveUtterances.isEmpty {
            isSpeaking = false
            onFinishedSpeaking?()
        }
    }

    func stopSpeaking() {
        expectsMoreSpeech = false
        liveUtterances.removeAll()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    /// Strips the handful of characters that a synthesizer reads out loud or
    /// stumbles over. The prompt already asks for plain prose; this is a net.
    private static func speakable(_ text: String) -> String {
        text
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Audio session

    private func configureSession(forRecording: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        if forRecording || isConversationSession {
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
        Task { @MainActor [weak self] in self?.utteranceEnded(utterance) }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in self?.utteranceEnded(utterance) }
    }

    private func utteranceEnded(_ utterance: AVSpeechUtterance) {
        // A cancelled reply already emptied the set, so this is a no-op for it.
        guard liveUtterances.remove(ObjectIdentifier(utterance)) != nil else { return }
        guard liveUtterances.isEmpty, !expectsMoreSpeech else { return }
        isSpeaking = false
        onFinishedSpeaking?()
    }
}

/// Peak level from the audio tap, handed across threads.
///
/// The tap runs on a real-time audio thread that must not hop actors, so it
/// writes the loudest frame it has seen behind a lock and the main-actor timer
/// drains it.
private final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Double = 0

    func record(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?.pointee else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        var sum: Float = 0
        for index in 0..<frames {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = (sum / Float(frames)).squareRoot()
        // -50 dBFS reads as silence, 0 dBFS as full scale.
        let decibels = 20 * log10(max(Double(rms), 1e-7))
        let normalized = max(0, min(1, (decibels + 50) / 50))

        lock.lock()
        peak = max(peak, normalized)
        lock.unlock()
    }

    func drain() -> Double {
        lock.lock()
        defer { peak = 0; lock.unlock() }
        return peak
    }

    func reset() {
        lock.lock()
        peak = 0
        lock.unlock()
    }
}
