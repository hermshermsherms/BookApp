import SwiftUI
import Foundation

@MainActor
final class DiscoveryViewModel: ObservableObject {
    @Published var books: [Book] = []
    @Published var currentIndex: Int = 0
    @Published var isLoading = false
    @Published var error: String?
    @Published var showPurchaseSheet = false
    @Published var showDetailView = false
    @Published var likeAnimationTrigger = false
    
    var currentBook: Book? {
        guard currentIndex < books.count else { return nil }
        return books[currentIndex]
    }
    
    var nextBook: Book? {
        guard currentIndex + 1 < books.count else { return nil }
        return books[currentIndex + 1]
    }
    
    var previousBook: Book? {
        guard currentIndex > 0 else { return nil }
        return books[currentIndex - 1]
    }

    private var bookQueue: [Book] = []
    private var bookHistory: [Book] = [] // Stack of previously seen books
    private var seenBookIds: Set<String> = []
    private let booksService = GoogleBooksService.shared
    private let supabaseService = SupabaseService.shared
    private let prefetchThreshold = 3
    private var prefetchTask: Task<Void, Never>?

    // MARK: - Load Feed

    func loadFeed() async {
        isLoading = true
        error = nil
        books = [] // Clear existing books

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
            
            // If no books were loaded from API, use mock books
            if books.isEmpty {
                books = mockBooks()
            }
            
            currentIndex = 0
        } catch {
            // If Google Books fails, always use mock data to ensure users see content
            books = mockBooks()
            currentIndex = 0
            // Don't set error for initial load - just use mock books silently
        }

        isLoading = false
    }

    // MARK: - Fetch More Books

    private func fetchMoreBooks() async throws {
        do {
            let newBooksFromAPI = try await booksService.fetchTrendingBooks(maxResults: 10)
            let filteredBooks = newBooksFromAPI.filter { !seenBookIds.contains($0.id) }
            
            await MainActor.run {
                books.append(contentsOf: filteredBooks)
            }
        } catch {
            // If we have no books at all, add mock books to prevent empty state
            if books.isEmpty {
                await MainActor.run {
                    books.append(contentsOf: mockBooks())
                }
            }
            throw error // Re-throw to let caller handle if needed
        }
    }

    // MARK: - Index Management
    
    func updateCurrentIndex(_ newIndex: Int) {
        currentIndex = newIndex
        
        // Pre-fetch more books if running low
        if currentIndex >= books.count - prefetchThreshold {
            prefetchTask?.cancel()
            prefetchTask = Task { [weak self] in
                guard let self = self else { return }
                try? await self.fetchMoreBooks()
            }
        }
    }
    
    private func advanceToNext() {
        if currentIndex < books.count - 1 {
            currentIndex += 1
        } else {
            // At the end, try to load more books
            Task {
                try? await fetchMoreBooks()
                if currentIndex < books.count - 1 {
                    currentIndex += 1
                }
            }
        }
    }
    
    private func goToPrevious() {
        if currentIndex > 0 {
            currentIndex -= 1
        }
    }

    // MARK: - Swipe Actions


    func swipeUp() {
        advanceToNext()
    }
    
    func swipeDown() {
        goToPrevious()
    }

    func doubleTap() {
        guard let book = currentBook else { return }

        // Trigger heart animation
        likeAnimationTrigger = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.likeAnimationTrigger = false
        }

        // Save to library but don't advance - just show the like animation
        recordSwipe(book: book, action: .like)
        saveToLibrary(book: book)
        // Note: Don't advance to next book on double tap - just save it
    }


    func singleTap() {
        guard currentBook != nil else { return }
        showDetailView = true
    }
    
    func buyBook() {
        guard currentBook != nil else { return }
        showPurchaseSheet = true
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
            _ = try? await self.supabaseService.addUserBook(
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
                id: "cygWzgEACAAJ",
                title: "The Seven Husbands of Evelyn Hugo",
                authors: ["Taylor Jenkins Reid"],
                description: "From the New York Times bestselling author of Malibu Rising comes the story of legendary film actress Evelyn Hugo, who has lived a life of glamour, ambition, and scandal. When she finally decides to tell her story, she chooses unknown magazine reporter Monique Grant for the job.",
                categories: ["Fiction", "Romance"],
                averageRating: 4.3,
                pageCount: 400,
                publishedDate: "2017-06-13",
                thumbnailURL: "https://books.google.com/books/content?id=cygWzgEACAAJ&printsec=frontcover&img=1&zoom=1",
                largeCoverURL: "https://books.google.com/books/content?id=cygWzgEACAAJ&printsec=frontcover&img=1&zoom=3",
                infoLink: nil
            ),
            Book(
                id: "NzjhzQEACAAJ",
                title: "Project Hail Mary",
                authors: ["Andy Weir"],
                description: "The sole survivor on a desperate, last-chance mission—and if he fails, humanity and the earth itself will perish. Except that right now, he doesn't know that. He can't even remember his own name, let alone the nature of his assignment or how to complete it.",
                categories: ["Science Fiction", "Thriller"],
                averageRating: 4.6,
                pageCount: 482,
                publishedDate: "2021-05-04",
                thumbnailURL: "https://books.google.com/books/content?id=NzjhzQEACAAJ&printsec=frontcover&img=1&zoom=1",
                largeCoverURL: "https://books.google.com/books/content?id=NzjhzQEACAAJ&printsec=frontcover&img=1&zoom=3",
                infoLink: nil
            ),
            Book(
                id: "XVvGzwEACAAJ",
                title: "The Thursday Murder Club",
                authors: ["Richard Osman"],
                description: "Four unlikely friends meet each week to investigate cold cases. But when a brutal murder occurs in their own backyard, the Thursday Murder Club find themselves in the middle of their first live case.",
                categories: ["Mystery", "Crime"],
                averageRating: 4.1,
                pageCount: 368,
                publishedDate: "2020-09-03",
                thumbnailURL: "https://books.google.com/books/content?id=XVvGzwEACAAJ&printsec=frontcover&img=1&zoom=1",
                largeCoverURL: "https://books.google.com/books/content?id=XVvGzwEACAAJ&printsec=frontcover&img=1&zoom=3",
                infoLink: nil
            ),
            Book(
                id: "fFCjDwAAQBAJ",
                title: "Atomic Habits",
                authors: ["James Clear"],
                description: "An easy & proven way to build good habits & break bad ones. Tiny changes, remarkable results. No matter your goals, Atomic Habits offers a proven framework for improving every day.",
                categories: ["Self Help", "Psychology"],
                averageRating: 4.7,
                pageCount: 320,
                publishedDate: "2018-10-16",
                thumbnailURL: "https://books.google.com/books/content?id=fFCjDwAAQBAJ&printsec=frontcover&img=1&zoom=1",
                largeCoverURL: "https://books.google.com/books/content?id=fFCjDwAAQBAJ&printsec=frontcover&img=1&zoom=3",
                infoLink: nil
            ),
            Book(
                id: "RLV5DwAAQBAJ",
                title: "The Silent Patient",
                authors: ["Alex Michaelides"],
                description: "A woman's act of violence against her husband—and of the therapist obsessed with uncovering her motive. It will keep you guessing until the final page.",
                categories: ["Mystery", "Psychological Thriller"],
                averageRating: 4.2,
                pageCount: 336,
                publishedDate: "2019-02-05",
                thumbnailURL: "https://books.google.com/books/content?id=RLV5DwAAQBAJ&printsec=frontcover&img=1&zoom=1",
                largeCoverURL: "https://books.google.com/books/content?id=RLV5DwAAQBAJ&printsec=frontcover&img=1&zoom=3",
                infoLink: nil
            ),
            Book(
                id: "2ObWDgAAQBAJ",
                title: "Educated",
                authors: ["Tara Westover"],
                description: "A memoir about a young girl who, kept out of school, leaves her survivalist family and goes on to earn a PhD from Cambridge University.",
                categories: ["Biography", "Memoir"],
                averageRating: 4.4,
                pageCount: 334,
                publishedDate: "2018-02-20",
                thumbnailURL: "https://books.google.com/books/content?id=2ObWDgAAQBAJ&printsec=frontcover&img=1&zoom=1",
                largeCoverURL: "https://books.google.com/books/content?id=2ObWDgAAQBAJ&printsec=frontcover&img=1&zoom=3",
                infoLink: nil
            ),
            Book(
                id: "W2ZDDwAAQBAJ",
                title: "The Midnight Library",
                authors: ["Matt Haig"],
                description: "Between life and death there is a library, and within that library, the shelves go on forever. Every book provides a chance to try another life you could have lived.",
                categories: ["Fiction", "Fantasy"],
                averageRating: 4.0,
                pageCount: 288,
                publishedDate: "2020-08-13",
                thumbnailURL: "https://books.google.com/books/content?id=W2ZDDwAAQBAJ&printsec=frontcover&img=1&zoom=1",
                largeCoverURL: "https://books.google.com/books/content?id=W2ZDDwAAQBAJ&printsec=frontcover&img=1&zoom=3",
                infoLink: nil
            ),
            Book(
                id: "B1hSG45JCX4C",
                title: "Dune",
                authors: ["Frank Herbert"],
                description: "Set on the desert planet Arrakis, Dune is the story of the boy Paul Atreides, heir to a noble family tasked with ruling an inhospitable world.",
                categories: ["Science Fiction", "Adventure"],
                averageRating: 4.3,
                pageCount: 688,
                publishedDate: "1965-08-01",
                thumbnailURL: "https://books.google.com/books/content?id=B1hSG45JCX4C&printsec=frontcover&img=1&zoom=1",
                largeCoverURL: "https://books.google.com/books/content?id=B1hSG45JCX4C&printsec=frontcover&img=1&zoom=3",
                infoLink: nil
            ),
            Book(
                id: "H7GeDAAAQBAJ",
                title: "Normal People",
                authors: ["Sally Rooney"],
                description: "A story of mutual fascination, friendship and love. It takes us from that first conversation to the years beyond, in the company of two people who try to stay apart but find they can't.",
                categories: ["Fiction", "Literary Fiction"],
                averageRating: 3.9,
                pageCount: 266,
                publishedDate: "2018-08-28",
                thumbnailURL: "https://books.google.com/books/content?id=H7GeDAAAQBAJ&printsec=frontcover&img=1&zoom=1",
                largeCoverURL: "https://books.google.com/books/content?id=H7GeDAAAQBAJ&printsec=frontcover&img=1&zoom=3",
                infoLink: nil
            ),
            Book(
                id: "hi18DwAAQBAJ",
                title: "Becoming",
                authors: ["Michelle Obama"],
                description: "In her memoir, a work of deep reflection and mesmerizing storytelling, Michelle Obama invites readers into her world, chronicling the experiences that have shaped her.",
                categories: ["Biography", "Politics"],
                averageRating: 4.5,
                pageCount: 448,
                publishedDate: "2018-11-13",
                thumbnailURL: "https://books.google.com/books/content?id=hi18DwAAQBAJ&printsec=frontcover&img=1&zoom=1",
                largeCoverURL: "https://books.google.com/books/content?id=hi18DwAAQBAJ&printsec=frontcover&img=1&zoom=3",
                infoLink: nil
            )
        ]
    }
    
    deinit {
        prefetchTask?.cancel()
    }
}
