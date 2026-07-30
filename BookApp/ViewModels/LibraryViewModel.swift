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

    private static let localUserId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

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
        await fetchLibrary()
    }

    // MARK: - Delete Book

    func deleteBook(_ userBook: UserBook) async {
        libraryStore.remove(id: userBook.id)
        await fetchLibrary()
    }

    // MARK: - Search (Manual Add)

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
        let userId = AuthService.shared.currentUserId ?? Self.localUserId
        libraryStore.add(book: book, userId: userId, status: status)
        searchQuery = ""
        searchResults = []
        await fetchLibrary()
    }
}
