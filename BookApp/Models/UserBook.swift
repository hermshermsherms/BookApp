import Foundation

/// Represents a book saved to a user's library
struct UserBook: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: UUID
    let googleBooksId: String
    let status: BookStatus
    let addedAt: Date
    let updatedAt: Date

    /// Transient — populated from Google Books API, not stored in DB
    var book: Book?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case googleBooksId = "google_books_id"
        case status
        case addedAt = "added_at"
        case updatedAt = "updated_at"
    }

    static func == (lhs: UserBook, rhs: UserBook) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status && lhs.updatedAt == rhs.updatedAt
    }
}

enum BookStatus: String, Codable, CaseIterable {
    case wantToRead = "want_to_read"
    case reading = "reading"
    case read = "read"

    var displayName: String {
        switch self {
        case .wantToRead: return "Want to Read"
        case .reading: return "Reading"
        case .read: return "Read"
        }
    }

    var iconName: String {
        switch self {
        case .wantToRead: return "bookmark"
        case .reading: return "book.fill"
        case .read: return "checkmark.circle.fill"
        }
    }
}
