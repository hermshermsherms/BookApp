import Foundation

/// Drives the hands-free conversation: listen, send, speak, listen again.
///
/// It owns nothing that the text chat doesn't already own — the same
/// `BuddyViewModel` holds the turns (so a spoken conversation is still there in
/// the transcript afterwards) and the same `VoiceController` owns the audio.
/// This is the loop that connects them.
@MainActor
final class VoiceConversationViewModel: ObservableObject {
    enum Phase: Equatable {
        /// Waiting on microphone and speech permission.
        case starting
        /// Mic is open, waiting for the reader to speak or finish speaking.
        case listening
        /// Their turn is in, the reply hasn't started arriving.
        case thinking
        /// Reading a reply aloud.
        case speaking
        /// Mic deliberately closed — muted, timed out, or an error was shown.
        case paused
        case failed(String)
    }

    @Published private(set) var phase: Phase = .starting
    /// What the reader is saying right now, or said last turn.
    @Published private(set) var heardText = ""
    /// The reply as it streams, shown as captions under the orb.
    @Published private(set) var replyText = ""
    /// Set when the mic closed itself after a long silence, so the view can
    /// explain why it went quiet instead of just sitting there.
    @Published private(set) var didTimeOut = false

    let voice: VoiceController
    private let buddy: BuddyViewModel

    /// Text that has streamed in but hasn't been handed to the synthesizer yet,
    /// because it isn't a whole sentence.
    private var pendingSpeech = ""
    /// False once a turn has been interrupted, so the tail of its reply is
    /// dropped instead of being spoken over whatever comes next.
    private var isAwaitingReply = false
    private var hasStarted = false

    init(buddy: BuddyViewModel, voice: VoiceController) {
        self.buddy = buddy
        self.voice = voice
    }

    var subject: ChatSubject { buddy.subject }

    /// Openers to show while the reader works out what to say first.
    var prompts: [String] { buddy.suggestedOpeners }

    var isIdleAtStart: Bool {
        buddy.messages.isEmpty && heardText.isEmpty && replyText.isEmpty
    }

    // MARK: - Lifecycle

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        buddy.isVoiceMode = true
        guard await voice.beginConversationSession() else {
            fail(with: "Voice mode needs microphone access.")
            return
        }

        voice.onEndOfTurn = { [weak self] heard in
            self?.submit(heard)
        }
        voice.onIdleTimeout = { [weak self] in
            guard let self else { return }
            self.didTimeOut = true
            self.phase = .paused
        }
        voice.onInterrupted = { [weak self] in
            guard let self else { return }
            self.isAwaitingReply = false
            self.buddy.cancel()
            self.phase = .paused
        }
        voice.onFinishedSpeaking = { [weak self] in
            guard let self, self.phase == .speaking else { return }
            Task { await self.listen() }
        }
        buddy.onReplyChunk = { [weak self] chunk in
            self?.receive(chunk)
        }
        buddy.onReplyEnded = { [weak self] reply in
            self?.replyEnded(reply)
        }

        await listen()
    }

    func end() {
        isAwaitingReply = false
        buddy.onReplyChunk = nil
        buddy.onReplyEnded = nil
        buddy.isVoiceMode = false
        buddy.cancel()
        voice.endConversationSession()
        phase = .paused
    }

    // MARK: - Turn taking

    func listen() async {
        guard !isFailed else { return }
        didTimeOut = false
        // The last reply stays on screen while the reader answers it; only the
        // live transcript is reset.
        heardText = ""
        phase = .listening
        await voice.startListening()
        // `startListening` bails out on a permission or hardware problem.
        if !voice.isListening, phase == .listening {
            fail(with: "The microphone stopped working.")
        }
    }

    /// Shows the controller's own message when it has one, and takes it off the
    /// controller so the chat underneath doesn't alert about it a second time.
    private func fail(with fallback: String) {
        let message = voice.errorMessage ?? fallback
        voice.errorMessage = nil
        phase = .failed(message)
    }

    /// The big button: whatever is happening, this hands the turn back to the
    /// reader. Barge-in is a tap rather than automatic, because the mic would
    /// otherwise hear the synthesizer and answer itself.
    func takeTurn() async {
        switch phase {
        case .speaking:
            isAwaitingReply = false
            voice.stopSpeaking()
        case .thinking:
            isAwaitingReply = false
            buddy.cancel()
        case .listening:
            // Already listening — treat the tap as "I'm done talking".
            let heard = voice.stopListening().trimmingCharacters(in: .whitespacesAndNewlines)
            if heard.isEmpty {
                phase = .paused
            } else {
                submit(heard)
            }
            return
        case .failed:
            // "Try again" — rebuild the audio session from scratch, since the
            // failure may have been permission or hardware.
            phase = .paused
            hasStarted = false
            await start()
            return
        case .paused, .starting:
            break
        }
        await listen()
    }

    func pause() {
        voice.stopListening()
        voice.stopSpeaking()
        isAwaitingReply = false
        buddy.cancel()
        phase = .paused
    }

    /// Sends one of the suggested openers as if it had been spoken.
    func send(_ text: String) {
        voice.stopListening()
        submit(text)
    }

    private func submit(_ heard: String) {
        let trimmed = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Task { await listen() }
            return
        }

        heardText = trimmed
        replyText = ""
        pendingSpeech = ""
        isAwaitingReply = true
        phase = .thinking
        voice.beginSpokenReply()
        buddy.send(trimmed)
    }

    // MARK: - Reply streaming

    private func receive(_ chunk: String) {
        guard isAwaitingReply else { return }
        replyText += chunk
        pendingSpeech += chunk

        // Speak whole sentences as they land so the reply starts playing while
        // the rest is still streaming.
        while let sentence = Self.takeSentence(from: &pendingSpeech) {
            phase = .speaking
            voice.enqueueSpokenChunk(sentence)
        }
    }

    private func replyEnded(_ reply: String?) {
        guard isAwaitingReply else { return }
        isAwaitingReply = false

        let tail = pendingSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingSpeech = ""
        if !tail.isEmpty {
            phase = .speaking
            voice.enqueueSpokenChunk(tail)
        }
        // This can call back synchronously when nothing was queued, but it only
        // ever schedules the next listen, so the phase check below still holds.
        voice.endSpokenReply()

        if let message = buddy.errorMessage {
            buddy.errorMessage = nil
            voice.stopSpeaking()
            phase = .failed(message)
            return
        }
        if phase == .thinking {
            // Nothing speakable came back — don't leave the reader staring at a
            // dead screen, just open the mic again.
            Task { await listen() }
        }
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    /// Pulls the next speakable sentence off the buffer, or nil while the buffer
    /// is still mid-sentence. Short fragments are held back so the synthesizer
    /// isn't handed "Yes." on its own with a gap either side.
    private static func takeSentence(from buffer: inout String) -> String? {
        let terminators: Set<Character> = [".", "!", "?", "\n"]
        var index = buffer.startIndex
        var candidate: String.Index?

        while index < buffer.endIndex {
            if terminators.contains(buffer[index]) {
                let next = buffer.index(after: index)
                // A terminator only ends a sentence if what follows is a space,
                // a newline, or nothing yet — this keeps "3.5" and "Mr." whole.
                if next == buffer.endIndex {
                    break
                }
                if buffer[next].isWhitespace,
                   buffer.distance(from: buffer.startIndex, to: next) >= 25 {
                    candidate = next
                    break
                }
            }
            index = buffer.index(after: index)
        }

        guard let end = candidate else { return nil }
        let sentence = String(buffer[buffer.startIndex..<end])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = String(buffer[end...])
        return sentence.isEmpty ? nil : sentence
    }
}
