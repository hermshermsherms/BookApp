import Foundation

/// On-device persistence for the user's library (Want to Read / Reading / Read).
/// Stores a snapshot of each book's metadata alongside its status so the Library
/// works instantly and offline — no backend required. Designed to later sync to
/// Supabase's `user_books` table.
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    /// User books with their `.book` metadata populated, most-recently-added first.
    @Published private(set) var entries: [UserBook] = []

    private let fileURL: URL

    /// Persisted row: UserBook (status/dates) + a snapshot of the book metadata,
    /// since `UserBook.book` is transient and not part of its own Codable keys.
    private struct StoredEntry: Codable {
        var userBook: UserBook
        var book: Book?
    }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("BookApp", isDirectory: true)
        fileURL = dir.appendingPathComponent("library.json")
        load()
    }

    // MARK: - Persistence

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([StoredEntry].self, from: data) else {
            entries = []
            return
        }
        entries = stored.map { stored in
            var userBook = stored.userBook
            userBook.book = stored.book
            return userBook
        }
    }

    private func persist() {
        let stored = entries.map { StoredEntry(userBook: $0, book: $0.book) }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Queries

    func contains(googleBooksId: String) -> Bool {
        entries.contains { $0.googleBooksId == googleBooksId }
    }

    // MARK: - Mutations

    /// Adds a book (default Want to Read). No-op if it's already in the library.
    @discardableResult
    func add(book: Book, userId: UUID, status: BookStatus = .wantToRead) -> UserBook {
        if let existing = entries.first(where: { $0.googleBooksId == book.id }) {
            return existing
        }
        let now = Date()
        var userBook = UserBook(
            id: UUID(),
            userId: userId,
            googleBooksId: book.id,
            status: status,
            addedAt: now,
            updatedAt: now,
            book: book
        )
        userBook.book = book
        entries.insert(userBook, at: 0)
        persist()
        return userBook
    }

    func updateStatus(id: UUID, status: BookStatus) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let current = entries[index]
        var updated = UserBook(
            id: current.id,
            userId: current.userId,
            googleBooksId: current.googleBooksId,
            status: status,
            addedAt: current.addedAt,
            updatedAt: Date(),
            book: current.book
        )
        updated.book = current.book
        entries[index] = updated
        persist()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }
}
