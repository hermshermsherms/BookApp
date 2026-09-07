import SwiftUI

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var wantToReadBooks: [UserBook] = []
    @Published var readingBooks: [UserBook] = []
    @Published var readBooks: [UserBook] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var searchQuery = ""
    @Published var searchResults: [Book] = []
    @Published var isSearching = false

    private let libraryStore = LibraryStore.shared
    private let booksService = GoogleBooksService.shared

    // MARK: - Fetch Library

    func fetchLibrary() async {
        // Local store is the source of truth — book metadata is stored alongside the
        // status, so this is instant and works offline.
        let all = libraryStore.entries
        wantToReadBooks = all.filter { $0.status == .wantToRead }
        readingBooks = all.filter { $0.status == .reading }
        readBooks = all.filter { $0.status == .read }
    }

    // MARK: - Update Status

    func updateStatus(userBook: UserBook, newStatus: BookStatus) async {
        libraryStore.updateStatus(id: userBook.id, status: newStatus)
        // Finishing a book is a strong positive taste signal.
        if newStatus == .read, let book = userBook.book {
            RecommendationEngine.shared.record(book: book, action: .like)
        }
        await fetchLibrary()
    }

    // MARK: - Delete Book

    func deleteBook(_ userBook: UserBook) async {
        libraryStore.remove(id: userBook.id)
        // The review belongs to the shelf entry, so it goes with it — otherwise
        // it would linger in the profile's review count with no book attached.
        ReviewStore.shared.remove(googleBooksId: userBook.googleBooksId)
        await fetchLibrary()
    }

    // MARK: - Search (Manual Add)

    private var searchTask: Task<Void, Never>?

    /// Debounced search — call on every keystroke; runs the query after a short pause.
    func searchDebounced() {
        searchTask?.cancel()
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.searchBooks()
        }
    }

    func searchBooks() async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        do {
            searchResults = try await booksService.searchBooks(query: searchQuery, maxResults: 15)
        } catch {
            self.error = error.localizedDescription
        }
        isSearching = false
    }

    func addBookToLibrary(book: Book, status: BookStatus = .wantToRead) async {
        let userId = AuthService.shared.effectiveUserId
        libraryStore.add(book: book, userId: userId, status: status)
        searchQuery = ""
        searchResults = []
        await fetchLibrary()
    }
}
