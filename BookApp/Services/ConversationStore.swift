import Foundation

/// On-device persistence for reading-buddy conversations, following the same
/// pattern as `LibraryStore`: a single JSON file in Application Support so chats
/// survive relaunch with no backend required.
@MainActor
final class ConversationStore: ObservableObject {
    static let shared = ConversationStore()

    /// Most recently updated first.
    @Published private(set) var conversations: [Conversation] = []

    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("BookApp", isDirectory: true)
        fileURL = dir.appendingPathComponent("conversations.json")
        load()
    }

    // MARK: - Persistence

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([Conversation].self, from: data) else {
            conversations = []
            return
        }
        conversations = stored.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func save() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Mutations

    /// Returns the existing conversation for a subject, or creates one. Keeps a
    /// single ongoing thread per book/author rather than a pile of duplicates.
    func conversation(for subject: ChatSubject) -> Conversation {
        if let existing = conversations.first(where: { $0.subject.id == subject.id }) {
            return existing
        }
        let fresh = Conversation(subject: subject)
        conversations.insert(fresh, at: 0)
        save()
        return fresh
    }

    func update(_ conversation: Conversation) {
        var updated = conversation
        updated.updatedAt = Date()

        if let index = conversations.firstIndex(where: { $0.id == updated.id }) {
            conversations[index] = updated
        } else {
            conversations.append(updated)
        }
        conversations.sort { $0.updatedAt > $1.updatedAt }
        save()
    }

    func delete(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        save()
    }

    func deleteAll() {
        conversations.removeAll()
        save()
    }
}
