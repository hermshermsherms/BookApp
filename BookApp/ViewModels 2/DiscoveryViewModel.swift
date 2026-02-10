import SwiftUI
import Foundation

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
    private var prefetchTask: Task<Void, Never>?

    // MARK: - Load Feed

    func loadFeed() async {
        isLoading = true
        error = nil

        do {
            // In development mode, skip Supabase and use local tracking
            if let userId = AuthService.shared.currentUserId {
                do {
                    seenBookIds = try await supabaseService.fetchSwipedBookIds(userId: userId)
                } catch {
                    // Fallback to empty set if Supabase fails (development mode)
                    seenBookIds = []
                }
            }
            
            try await fetchMoreBooks()
            advanceToNext()
        } catch {
            // If Google Books fails, use mock data and set error message
            self.error = "Unable to fetch new books. Showing sample content."
            bookQueue = mockBooks()
            advanceToNext()
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
            prefetchTask?.cancel()
            prefetchTask = Task { [weak self] in
                guard let self = self else { return }
                try? await self.fetchMoreBooks()
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

        Task { [weak self] in
            guard let self = self else { return }
            try? await self.supabaseService.recordSwipe(
                userId: userId,
                googleBooksId: book.id,
                action: action
            )
        }
    }

    private func saveToLibrary(book: Book) {
        guard let userId = AuthService.shared.currentUserId else { return }

        Task { [weak self] in
            guard let self = self else { return }
            try? await self.supabaseService.addUserBook(
                userId: userId,
                googleBooksId: book.id,
                status: .wantToRead
            )
        }
    }
    
    // MARK: - Mock Data (Development)
    
    private func mockBooks() -> [Book] {
        return [
            Book(
                id: "mock1",
                title: "The Seven Husbands of Evelyn Hugo",
                authors: ["Taylor Jenkins Reid"],
                description: "From the New York Times bestselling author of Malibu Rising comes the story of legendary film actress Evelyn Hugo, who has lived a life of glamour, ambition, and scandal. When she finally decides to tell her story, she chooses unknown magazine reporter Monique Grant for the job.",
                categories: ["Fiction", "Romance"],
                averageRating: 4.3,
                pageCount: 400,
                publishedDate: "2017-06-13",
                thumbnailURL: "https://books.google.com/books/content?id=example1&printsec=frontcover&img=1&zoom=1",
                largeCoverURL: "https://books.google.com/books/content?id=example1&printsec=frontcover&img=1&zoom=3",
                infoLink: nil
            ),
            Book(
                id: "mock2",
                title: "Project Hail Mary",
                authors: ["Andy Weir"],
                description: "The sole survivor on a desperate, last-chance mission—and if he fails, humanity and the earth itself will perish. Except that right now, he doesn't know that. He can't even remember his own name, let alone the nature of his assignment or how to complete it.",
                categories: ["Science Fiction", "Thriller"],
                averageRating: 4.6,
                pageCount: 482,
                publishedDate: "2021-05-04",
                thumbnailURL: "https://books.google.com/books/content?id=example2&printsec=frontcover&img=1&zoom=1",
                largeCoverURL: "https://books.google.com/books/content?id=example2&printsec=frontcover&img=1&zoom=3",
                infoLink: nil
            ),
            Book(
                id: "mock3",
                title: "The Thursday Murder Club",
                authors: ["Richard Osman"],
                description: "Four unlikely friends meet each week to investigate cold cases. But when a brutal murder occurs in their own backyard, the Thursday Murder Club find themselves in the middle of their first live case.",
                categories: ["Mystery", "Crime"],
                averageRating: 4.1,
                pageCount: 368,
                publishedDate: "2020-09-03",
                thumbnailURL: "https://books.google.com/books/content?id=example3&printsec=frontcover&img=1&zoom=1",
                largeCoverURL: "https://books.google.com/books/content?id=example3&printsec=frontcover&img=1&zoom=3",
                infoLink: nil
            ),
            Book(
                id: "mock4",
                title: "Atomic Habits",
                authors: ["James Clear"],
                description: "An easy & proven way to build good habits & break bad ones. Tiny changes, remarkable results. No matter your goals, Atomic Habits offers a proven framework for improving every day.",
                categories: ["Self Help", "Psychology"],
                averageRating: 4.7,
                pageCount: 320,
                publishedDate: "2018-10-16",
                thumbnailURL: "https://books.google.com/books/content?id=example4&printsec=frontcover&img=1&zoom=1",
                largeCoverURL: "https://books.google.com/books/content?id=example4&printsec=frontcover&img=1&zoom=3",
                infoLink: nil
            ),
            Book(
                id: "mock5",
                title: "The Silent Patient",
                authors: ["Alex Michaelides"],
                description: "A woman's act of violence against her husband—and of the therapist obsessed with uncovering her motive. It will keep you guessing until the final page.",
                categories: ["Mystery", "Psychological Thriller"],
                averageRating: 4.2,
                pageCount: 336,
                publishedDate: "2019-02-05",
                thumbnailURL: "https://books.google.com/books/content?id=example5&printsec=frontcover&img=1&zoom=1",
                largeCoverURL: "https://books.google.com/books/content?id=example5&printsec=frontcover&img=1&zoom=3",
                infoLink: nil
            ),
            Book(
                id: "mock6",
                title: "Educated",
                authors: ["Tara Westover"],
                description: "A memoir about a young girl who, kept out of school, leaves her survivalist family and goes on to earn a PhD from Cambridge University.",
                categories: ["Biography", "Memoir"],
                averageRating: 4.4,
                pageCount: 334,
                publishedDate: "2018-02-20",
                thumbnailURL: "https://books.google.com/books/content?id=example6&printsec=frontcover&img=1&zoom=1",
                largeCoverURL: "https://books.google.com/books/content?id=example6&printsec=frontcover&img=1&zoom=3",
                infoLink: nil
            ),
            Book(
                id: "mock7",
                title: "The Midnight Library",
                authors: ["Matt Haig"],
                description: "Between life and death there is a library, and within that library, the shelves go on forever. Every book provides a chance to try another life you could have lived.",
                categories: ["Fiction", "Fantasy"],
                averageRating: 4.0,
                pageCount: 288,
                publishedDate: "2020-08-13",
                thumbnailURL: "https://books.google.com/books/content?id=example7&printsec=frontcover&img=1&zoom=1",
                largeCoverURL: "https://books.google.com/books/content?id=example7&printsec=frontcover&img=1&zoom=3",
                infoLink: nil
            ),
            Book(
                id: "mock8",
                title: "Dune",
                authors: ["Frank Herbert"],
                description: "Set on the desert planet Arrakis, Dune is the story of the boy Paul Atreides, heir to a noble family tasked with ruling an inhospitable world.",
                categories: ["Science Fiction", "Adventure"],
                averageRating: 4.3,
                pageCount: 688,
                publishedDate: "1965-08-01",
                thumbnailURL: "https://books.google.com/books/content?id=example8&printsec=frontcover&img=1&zoom=1",
                largeCoverURL: "https://books.google.com/books/content?id=example8&printsec=frontcover&img=1&zoom=3",
                infoLink: nil
            ),
            Book(
                id: "mock9",
                title: "Normal People",
                authors: ["Sally Rooney"],
                description: "A story of mutual fascination, friendship and love. It takes us from that first conversation to the years beyond, in the company of two people who try to stay apart but find they can't.",
                categories: ["Fiction", "Literary Fiction"],
                averageRating: 3.9,
                pageCount: 266,
                publishedDate: "2018-08-28",
                thumbnailURL: "https://books.google.com/books/content?id=example9&printsec=frontcover&img=1&zoom=1",
                largeCoverURL: "https://books.google.com/books/content?id=example9&printsec=frontcover&img=1&zoom=3",
                infoLink: nil
            ),
            Book(
                id: "mock10",
                title: "Becoming",
                authors: ["Michelle Obama"],
                description: "In her memoir, a work of deep reflection and mesmerizing storytelling, Michelle Obama invites readers into her world, chronicling the experiences that have shaped her.",
                categories: ["Biography", "Politics"],
                averageRating: 4.5,
                pageCount: 448,
                publishedDate: "2018-11-13",
                thumbnailURL: "https://books.google.com/books/content?id=example10&printsec=frontcover&img=1&zoom=1",
                largeCoverURL: "https://books.google.com/books/content?id=example10&printsec=frontcover&img=1&zoom=3",
                infoLink: nil
            )
        ]
    }
    
    deinit {
        prefetchTask?.cancel()
    }
}
