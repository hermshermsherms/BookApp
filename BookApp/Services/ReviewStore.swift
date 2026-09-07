import Foundation

/// On-device persistence for star ratings and written reviews.
///
/// Mirrors `LibraryStore`: the local file is the source of truth, so rating a
/// book is instant and works offline — no backend required. Reviews are keyed
/// by Google Books ID, one per book per user. Designed to later sync to
/// Supabase's `reviews` table.
@MainActor
final class ReviewStore: ObservableObject {
    static let shared = ReviewStore()

    /// All of the user's reviews, most recently updated first.
    @Published private(set) var reviews: [Review] = []

    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("BookApp", isDirectory: true)
        fileURL = dir.appendingPathComponent("reviews.json")
        load()
    }

    // MARK: - Persistence

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([Review].self, from: data) else {
            reviews = []
            return
        }
        reviews = stored.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(reviews) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Queries

    func review(forGoogleBooksId googleBooksId: String) -> Review? {
        reviews.first { $0.googleBooksId == googleBooksId }
    }

    // MARK: - Mutations

    /// Saves a rating (and optional review text), replacing any existing review
    /// for the same book. The rating is snapped to a valid half-star value.
    @discardableResult
    func upsert(userId: UUID, googleBooksId: String, rating: Double, reviewText: String?) -> Review {
        let trimmed = reviewText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (trimmed?.isEmpty == false) ? trimmed : nil
        let snapped = Review.snap(rating)
        let now = Date()

        if let index = reviews.firstIndex(where: { $0.googleBooksId == googleBooksId }) {
            var updated = reviews[index]
            updated.rating = snapped
            updated.reviewText = text
            updated.updatedAt = now
            reviews.remove(at: index)
            reviews.insert(updated, at: 0)
            persist()
            return updated
        }

        let review = Review(
            id: UUID(),
            userId: userId,
            googleBooksId: googleBooksId,
            rating: snapped,
            reviewText: text,
            createdAt: now,
            updatedAt: now
        )
        reviews.insert(review, at: 0)
        persist()
        return review
    }

    func remove(googleBooksId: String) {
        reviews.removeAll { $0.googleBooksId == googleBooksId }
        persist()
    }
}
