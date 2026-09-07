import SwiftUI

@MainActor
final class ProfileViewModel: ObservableObject {

    /// One finished book paired with its review, ready for the shelf grid.
    struct ShelfItem: Identifiable {
        let userBook: UserBook
        let review: Review?

        var id: UUID { userBook.id }
        var book: Book? { userBook.book }
        var rating: Double { review?.rating ?? 0 }
        var title: String { userBook.book?.title ?? "Unknown Title" }
    }

    struct Stats {
        let booksRead: Int
        let reviewsWritten: Int
        let totalBooks: Int
        let averageRating: Double?
    }

    enum ShelfSort: String, CaseIterable, Identifiable {
        case recent
        case rating
        case title

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .recent: return "Recently Finished"
            case .rating: return "Highest Rated"
            case .title: return "Title"
            }
        }

        var iconName: String {
            switch self {
            case .recent: return "clock"
            case .rating: return "star"
            case .title: return "textformat.abc"
            }
        }
    }

    @Published var displayName: String = "Reader"
    @Published var sort: ShelfSort = .recent

    func refreshDisplayName() {
        displayName = AuthService.shared.displayName ?? "Reader"
    }

    // MARK: - Shelf

    /// The user's finished books, each joined to its review, in the current sort order.
    func shelf(books: [UserBook], reviews: [Review]) -> [ShelfItem] {
        let reviewsByBook = Dictionary(
            reviews.map { ($0.googleBooksId, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let items = books
            .filter { $0.status == .read }
            .map { ShelfItem(userBook: $0, review: reviewsByBook[$0.googleBooksId]) }

        switch sort {
        case .recent:
            return items.sorted { $0.userBook.updatedAt > $1.userBook.updatedAt }
        case .rating:
            // Ties fall back to most recently finished.
            return items.sorted { ($0.rating, $0.userBook.updatedAt) > ($1.rating, $1.userBook.updatedAt) }
        case .title:
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    // MARK: - Stats

    func stats(books: [UserBook], reviews: [Review]) -> Stats {
        let ratings = reviews.map(\.rating)
        let average = ratings.isEmpty ? nil : ratings.reduce(0, +) / Double(ratings.count)

        return Stats(
            booksRead: books.filter { $0.status == .read }.count,
            reviewsWritten: reviews.count,
            totalBooks: books.count,
            averageRating: average
        )
    }
}
