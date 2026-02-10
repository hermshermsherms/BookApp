import Foundation

/// Records a user's swipe action on a book in the Discovery feed
struct SwipeAction: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let googleBooksId: String
    let action: SwipeType
    let swipedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case googleBooksId = "google_books_id"
        case action
        case swipedAt = "swiped_at"
    }
}

enum SwipeType: String, Codable {
    case like
    case dislike
    case buy
}
