import SwiftUI

@MainActor
final class DiscoveryViewModel: ObservableObject {
    @Published var currentBook: Book?
    @Published var isLoading = false
    @Published var error: String?
    @Published var showPurchaseSheet = false
    @Published var showDetailView = false
    @Published var likeAnimationTrigger = false

    private var bookQueue: [Book] = []
    private var seenBookIds: Set<String> = []
    private let booksService = GoogleBooksService.shared
    private let supabaseService = SupabaseService.shared
    private let prefetchThreshold = 3

    // MARK: - Load Feed

    func loadFeed() async {
        guard let userId = AuthService.shared.currentUserId else { return }

        isLoading = true
        error = nil

        do {
            // Load previously swiped book IDs to exclude from feed
            seenBookIds = try await supabaseService.fetchSwipedBookIds(userId: userId)
            try await fetchMoreBooks()
            advanceToNext()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Fetch More Books

    private func fetchMoreBooks() async throws {
        let books = try await booksService.fetchTrendingBooks(maxResults: 10)
        let newBooks = books.filter { !seenBookIds.contains($0.id) }
        bookQueue.append(contentsOf: newBooks)
    }

    // MARK: - Advance Feed

    private func advanceToNext() {
        if bookQueue.isEmpty {
            currentBook = nil
            return
        }
        currentBook = bookQueue.removeFirst()

        // Pre-fetch more if running low
        if bookQueue.count < prefetchThreshold {
            Task {
                try? await fetchMoreBooks()
            }
        }
    }

    // MARK: - Swipe Actions

    func swipeLeft() {
        guard let book = currentBook else { return }
        recordSwipe(book: book, action: .dislike)
        advanceToNext()
    }

    func swipeUp() {
        advanceToNext()
    }

    func doubleTap() {
        guard let book = currentBook else { return }

        // Trigger heart animation
        likeAnimationTrigger = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.likeAnimationTrigger = false
        }

        recordSwipe(book: book, action: .like)
        saveToLibrary(book: book)
        advanceToNext()
    }

    func swipeRight() {
        guard let book = currentBook else { return }
        recordSwipe(book: book, action: .buy)
        saveToLibrary(book: book)
        showPurchaseSheet = true
        // Don't advance yet — user is viewing purchase options
    }

    func dismissPurchaseSheet() {
        showPurchaseSheet = false
        advanceToNext()
    }

    func singleTap() {
        guard currentBook != nil else { return }
        showDetailView = true
    }

    // MARK: - Helpers

    private func recordSwipe(book: Book, action: SwipeType) {
        seenBookIds.insert(book.id)
        guard let userId = AuthService.shared.currentUserId else { return }

        Task {
            try? await supabaseService.recordSwipe(
                userId: userId,
                googleBooksId: book.id,
                action: action
            )
        }
    }

    private func saveToLibrary(book: Book) {
        guard let userId = AuthService.shared.currentUserId else { return }

        Task {
            try? await supabaseService.addUserBook(
                userId: userId,
                googleBooksId: book.id,
                status: .wantToRead
            )
        }
    }
}
