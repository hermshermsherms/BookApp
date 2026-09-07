import Foundation

/// What a conversation is *about*. The buddy is always scoped to one subject —
/// a specific book, or an author's body of work — which is what keeps it a
/// reading companion rather than a general chatbot.
struct ChatSubject: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case book
        case author
    }

    let kind: Kind
    /// Book title, or the author's name when `kind == .author`.
    let name: String
    /// Author of the book. `nil` for author subjects.
    let author: String?
    /// Google Books volume id, when this came from a real catalog entry.
    let bookID: String?
    let coverURLString: String?
    let synopsis: String?
    let categories: [String]
    let publishedDate: String?
    let pageCount: Int?

    var id: String { "\(kind.rawValue):\(bookID ?? name.lowercased())" }

    var coverURL: URL? {
        coverURLString.flatMap(URL.init(string:))
    }

    /// Line shown under the title in lists.
    var subtitle: String {
        switch kind {
        case .book: return author ?? "Unknown author"
        case .author: return "Author"
        }
    }

    static func book(_ book: Book) -> ChatSubject {
        ChatSubject(
            kind: .book,
            name: book.title,
            author: book.authorDisplay,
            bookID: book.id,
            coverURLString: book.highQualityImageURL?.absoluteString,
            synopsis: book.description,
            categories: book.categories,
            publishedDate: book.publishedDate,
            pageCount: book.pageCount
        )
    }

    static func author(_ name: String, coverURL: URL? = nil) -> ChatSubject {
        ChatSubject(
            kind: .author,
            name: name,
            author: nil,
            bookID: nil,
            coverURLString: coverURL?.absoluteString,
            synopsis: nil,
            categories: [],
            publishedDate: nil,
            pageCount: nil
        )
    }
}

struct ChatMessage: Identifiable, Codable, Hashable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var text: String
    let createdAt: Date

    init(id: UUID = UUID(), role: Role, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

struct Conversation: Identifiable, Codable, Hashable {
    let id: UUID
    var subject: ChatSubject
    var messages: [ChatMessage]
    var updatedAt: Date
    /// Free-text answer to "how far are you?" — fed to the model so it can keep
    /// spoilers behind wherever the reader actually is. `nil` means unset, and
    /// the buddy will avoid late-book material until asked.
    var progressNote: String?
    /// Recaps, character cards, timeline and discussion starters generated for
    /// this conversation. Persisted so reopening a book doesn't re-bill a model
    /// call for work that hasn't gone stale.
    var study: StudyCache

    init(
        id: UUID = UUID(),
        subject: ChatSubject,
        messages: [ChatMessage] = [],
        updatedAt: Date = Date(),
        progressNote: String? = nil,
        study: StudyCache = StudyCache()
    ) {
        self.id = id
        self.subject = subject
        self.messages = messages
        self.updatedAt = updatedAt
        self.progressNote = progressNote
        self.study = study
    }

    /// Conversations saved before the study tools existed have no `study` key;
    /// decode it as an empty cache rather than failing the whole file.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        subject = try container.decode(ChatSubject.self, forKey: .subject)
        messages = try container.decode([ChatMessage].self, forKey: .messages)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        progressNote = try container.decodeIfPresent(String.self, forKey: .progressNote)
        study = try container.decodeIfPresent(StudyCache.self, forKey: .study) ?? StudyCache()
    }

    /// Preview line for the conversation list.
    var lastLine: String {
        messages.last?.text.replacingOccurrences(of: "\n", with: " ")
            ?? "No messages yet"
    }
}
