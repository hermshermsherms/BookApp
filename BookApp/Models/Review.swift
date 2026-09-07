import Foundation

/// A user's review of a book they've read
struct Review: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: UUID
    let googleBooksId: String
    /// 0.5 to 5, in half-star steps. Stored as a Double so half stars survive a
    /// round trip; whole-number ratings written before half stars decode as-is.
    var rating: Double
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
        rating >= Review.step && rating <= 5 && (rating / Review.step).truncatingRemainder(dividingBy: 1) == 0
    }

    /// Whether the user wrote something beyond the star rating.
    var hasText: Bool {
        guard let text = reviewText else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The smallest rating increment — half a star.
    static let step: Double = 0.5

    /// Snaps an arbitrary value to the nearest valid half-star rating.
    static func snap(_ value: Double) -> Double {
        min(max((value / step).rounded() * step, step), 5)
    }

    /// "4" or "3.5" — trailing ".0" trimmed so whole ratings read cleanly.
    static func display(_ rating: Double) -> String {
        rating.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(rating))
            : String(format: "%.1f", rating)
    }

    var ratingDisplay: String {
        Review.display(rating)
    }
}
