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

    /// Whether the user wrote something beyond the star rating.
    var hasText: Bool {
        guard let text = reviewText else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Plain-English label for a star count, shown next to the picker so the
    /// rating reads as an opinion rather than a number.
    static func label(forRating rating: Int) -> String {
        switch rating {
        case 1: return "Not for me"
        case 2: return "It was okay"
        case 3: return "Good read"
        case 4: return "Really liked it"
        case 5: return "A new favorite"
        default: return "Tap a star to rate"
        }
    }

    var ratingLabel: String {
        Review.label(forRating: rating)
    }
}
