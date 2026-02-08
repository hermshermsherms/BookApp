import Foundation

/// A user's review of a book they've read
struct Review: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: UUID
    let googleBooksId: String
    var rating: Int // 1-5
    var reviewText: String?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case googleBooksId = "google_books_id"
        case rating
        case reviewText = "review_text"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var isValid: Bool {
        rating >= 1 && rating <= 5
    }
}
