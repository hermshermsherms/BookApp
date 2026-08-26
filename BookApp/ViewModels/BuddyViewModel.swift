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

    private let store = ConversationStore.shared
    private var streamTask: Task<Void, Never>?

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
