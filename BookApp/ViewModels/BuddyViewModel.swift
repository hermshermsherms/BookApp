import Foundation

@MainActor
final class BuddyViewModel: ObservableObject {
    @Published private(set) var conversation: Conversation
    @Published var draft = ""
    @Published private(set) var isStreaming = false
    @Published var errorMessage: String?
    /// Set once a reply finishes streaming, so the view can read it aloud.
    /// Cleared as soon as it's consumed.
    @Published var lastCompletedReply: String?

    /// Which of Chat / Understand / Discuss is showing.
    @Published var tab: BuddyTab = .chat
    /// Study material currently being generated. A set rather than a flag so
    /// the timeline can load while the recap is still coming back.
    @Published private(set) var generating: Set<StudyKind> = []
    /// Per-section failure, cleared when that section is retried. Kept apart
    /// from `errorMessage` so a failed recap doesn't throw an alert over a
    /// conversation the reader is still typing in.
    @Published private(set) var studyErrors: [StudyKind: String] = [:]

    private let store = ConversationStore.shared
    private var streamTask: Task<Void, Never>?
    private var studyTasks: [StudyKind: Task<Void, Never>] = [:]

    init(conversation: Conversation) {
        self.conversation = conversation
    }

    var subject: ChatSubject { conversation.subject }
    var messages: [ChatMessage] { conversation.messages }
    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }

    /// Openers offered on an empty conversation — subject-aware so they read as
    /// real questions rather than generic prompts.
    var suggestedOpeners: [String] {
        switch subject.kind {
        case .book:
            return [
                "What should I be paying attention to as I read this?",
                "What's this book actually about, underneath the plot?",
                "Who would I compare this author to?"
            ]
        case .author:
            return [
                "Where should I start with \(subject.name)?",
                "What keeps coming back in their work?",
                "How did their writing change over time?"
            ]
        }
    }

    /// An author has no plot to recap, so their conversation is Chat + Discuss.
    var availableTabs: [BuddyTab] {
        subject.kind == .book ? BuddyTab.allCases : [.chat, .discuss]
    }

    /// Sections that make sense for this subject. An author has no plot to
    /// recap, so their conversation gets discussion starters only.
    var availableStudyKinds: [StudyKind] {
        subject.kind == .book
            ? StudyKind.allCases
            : StudyKind.allCases.filter(\.appliesToAuthors)
    }

    var progressNote: String? { conversation.progressNote }
    var hasProgress: Bool { (progressNote?.isEmpty == false) }

    func setProgress(_ note: String?) {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        conversation.progressNote = (trimmed?.isEmpty == false) ? trimmed : nil
        store.update(conversation)
    }

    func send(_ text: String? = nil) {
        let outgoing = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !outgoing.isEmpty, !isStreaming else { return }

        draft = ""
        errorMessage = nil
        conversation.messages.append(ChatMessage(role: .user, text: outgoing))
        captureProgressIfStated(in: outgoing)

        let placeholder = ChatMessage(role: .assistant, text: "")
        conversation.messages.append(placeholder)
        store.update(conversation)

        isStreaming = true
        let system = BuddyPrompt.system(for: conversation)
        // The placeholder isn't part of the request — only real turns are sent.
        let history = Array(conversation.messages.dropLast())

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = await ClaudeService.shared.streamReply(system: system, history: history)
                for try await chunk in stream {
                    self.append(chunk, to: placeholder.id)
                }
                self.finish(placeholder.id)
            } catch is CancellationError {
                self.finish(placeholder.id)
            } catch {
                self.fail(error, placeholder: placeholder.id)
            }
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    /// Stops everything in flight — the reply and any study material still
    /// generating. Called when the conversation is dismissed.
    func cancelAll() {
        cancel()
        studyTasks.values.forEach { $0.cancel() }
        studyTasks = [:]
        generating = []
    }

    // MARK: - Study material

    var recap: Recap? { conversation.study.recap?.value }
    var characters: [CharacterProfile]? { conversation.study.characters?.value }
    var timeline: [TimelineBeat]? { conversation.study.timeline?.value }
    var starters: [DiscussionStarter]? { conversation.study.starters?.value }

    func isGenerating(_ kind: StudyKind) -> Bool { generating.contains(kind) }

    func error(for kind: StudyKind) -> String? { studyErrors[kind] }

    /// True when something exists for this section but the reader has moved on
    /// since it was made — the card is still useful, it just isn't current.
    func isStale(_ kind: StudyKind) -> Bool {
        guard let signature = signature(for: kind) else { return false }
        return signature != StudyCache.signature(for: conversation.progressNote)
    }

    func hasContent(_ kind: StudyKind) -> Bool { signature(for: kind) != nil }

    private func signature(for kind: StudyKind) -> String? {
        switch kind {
        case .recap: return conversation.study.recap?.progressSignature
        case .characters: return conversation.study.characters?.progressSignature
        case .timeline: return conversation.study.timeline?.progressSignature
        case .starters: return conversation.study.starters?.progressSignature
        }
    }

    /// Generates a section if it isn't there yet. `force` regenerates it — used
    /// by the refresh button and by the "you've moved on" prompt.
    func loadStudy(_ kind: StudyKind, force: Bool = false) {
        guard !generating.contains(kind) else { return }
        guard force || !hasContent(kind) else { return }

        studyErrors[kind] = nil
        generating.insert(kind)
        let snapshot = conversation
        let signature = StudyCache.signature(for: snapshot.progressNote)

        studyTasks[kind] = Task { [weak self] in
            guard let self else { return }
            do {
                let generatedAt = Date()
                switch kind {
                case .recap:
                    let value = try await BuddyStudyService.shared.recap(for: snapshot)
                    self.conversation.study.recap = StudyResult(
                        value: value, progressSignature: signature, generatedAt: generatedAt
                    )
                case .characters:
                    let value = try await BuddyStudyService.shared.characters(for: snapshot)
                    self.conversation.study.characters = StudyResult(
                        value: value, progressSignature: signature, generatedAt: generatedAt
                    )
                case .timeline:
                    let value = try await BuddyStudyService.shared.timeline(for: snapshot)
                    self.conversation.study.timeline = StudyResult(
                        value: value, progressSignature: signature, generatedAt: generatedAt
                    )
                case .starters:
                    let value = try await BuddyStudyService.shared.starters(for: snapshot)
                    self.conversation.study.starters = StudyResult(
                        value: value, progressSignature: signature, generatedAt: generatedAt
                    )
                }
                self.finishStudy(kind, error: nil)
            } catch is CancellationError {
                self.finishStudy(kind, error: nil)
            } catch {
                self.finishStudy(kind, error: error.localizedDescription)
            }
        }
    }

    /// Takes a card into the conversation: switches to Chat and sends the
    /// question, so anything generated can be argued with rather than just read.
    func discuss(_ question: String) {
        tab = .chat
        send(question)
    }

    func discuss(_ starter: DiscussionStarter) {
        discuss(starter.question)
    }

    func discuss(_ character: CharacterProfile) {
        discuss("Let's talk about \(character.name). What should I be making of them so far?")
    }

    func discuss(_ beat: TimelineBeat) {
        discuss("Why does \"\(beat.title)\" matter to the book? I'm looking at \(beat.marker).")
    }

    func discuss(_ note: StudyNote) {
        discuss("You mentioned \"\(note.title)\" — say more about that.")
    }

    // MARK: - Progress capture

    /// Words that suggest the reader is reporting where they are. The check is
    /// deliberately loose — it only decides whether to spend a small model call
    /// reading the message properly, and the model makes the real judgement.
    private static let positionHints = [
        "chapter", "chapters", "ch.", "part ", "page", "pages", "%", "percent",
        "halfway", "half way", "just started", "just finished", "finished",
        "started", "beginning", "start of", "end of", "just got", "just read",
        "up to", "i'm at", "im at", "i am at", "so far", "haven't read",
        "havent read", "not started", "partway", "part way"
    ]

    /// Picks the reader's position out of what they just typed, when the buddy
    /// doesn't have one yet. Runs alongside the reply rather than blocking it,
    /// and stays silent when the message wasn't about position at all.
    private func captureProgressIfStated(in message: String) {
        guard conversation.progressNote == nil else { return }
        let lowered = message.lowercased()
        guard Self.positionHints.contains(where: { lowered.contains($0) }) else { return }

        let subject = conversation.subject
        Task { [weak self] in
            let detected = try? await BuddyStudyService.shared.detectProgress(
                in: message,
                subject: subject
            )
            guard let self, let detected, self.conversation.progressNote == nil else { return }
            self.setProgress(detected)
        }
    }

    private func finishStudy(_ kind: StudyKind, error: String?) {
        generating.remove(kind)
        studyTasks[kind] = nil
        studyErrors[kind] = error
        if error == nil { store.update(conversation) }
    }

    // MARK: - Stream handling

    private func append(_ chunk: String, to id: UUID) {
        guard let index = conversation.messages.firstIndex(where: { $0.id == id }) else { return }
        conversation.messages[index].text += chunk
    }

    private func finish(_ id: UUID) {
        isStreaming = false
        streamTask = nil

        guard let index = conversation.messages.firstIndex(where: { $0.id == id }) else { return }
        let reply = conversation.messages[index].text
        if reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Nothing came back — don't leave an empty bubble behind.
            conversation.messages.remove(at: index)
        } else {
            lastCompletedReply = reply
        }
        store.update(conversation)
    }

    private func fail(_ error: Error, placeholder id: UUID) {
        isStreaming = false
        streamTask = nil

        if let index = conversation.messages.firstIndex(where: { $0.id == id }),
           conversation.messages[index].text.isEmpty {
            conversation.messages.remove(at: index)
        }
        errorMessage = error.localizedDescription
        store.update(conversation)
    }
}
