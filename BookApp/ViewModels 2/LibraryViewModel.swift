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

    private let supabaseService = SupabaseService.shared
    private let booksService = GoogleBooksService.shared

    // MARK: - Fetch Library

    func fetchLibrary() async {
        guard let userId = AuthService.shared.currentUserId else { return }

        isLoading = true
        error = nil

        do {
            let allBooks = try await supabaseService.fetchUserBooks(userId: userId)

            // Enrich each UserBook with Google Books data
            var enrichedBooks: [UserBook] = []
            for var userBook in allBooks {
                if let book = try? await booksService.fetchBookDetails(id: userBook.googleBooksId) {
                    userBook.book = book
                }
                enrichedBooks.append(userBook)
            }

            wantToReadBooks = enrichedBooks.filter { $0.status == .wantToRead }
            readingBooks = enrichedBooks.filter { $0.status == .reading }
            readBooks = enrichedBooks.filter { $0.status == .read }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Update Status

    func updateStatus(userBook: UserBook, newStatus: BookStatus) async {
        do {
            try await supabaseService.updateBookStatus(bookId: userBook.id, status: newStatus)
            await fetchLibrary()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Delete Book

    func deleteBook(_ userBook: UserBook) async {
        do {
            try await supabaseService.deleteUserBook(bookId: userBook.id)
            await fetchLibrary()
        } catch {
            self.error = error.localizedDescription
        }
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
        guard let userId = AuthService.shared.currentUserId else { return }

        do {
            let _ = try await supabaseService.addUserBook(
                userId: userId,
                googleBooksId: book.id,
                status: status
            )
            searchQuery = ""
            searchResults = []
            await fetchLibrary()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
