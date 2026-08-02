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
    @Published var dislikeAnimationTrigger = false

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
    private let engine = RecommendationEngine.shared
    private let prefetchThreshold = 3
    private var isFetchingMore = false

    init(seedBooks: [Book] = []) {
        var seen = Set<String>()
        books = seedBooks.filter { seen.insert($0.id).inserted }
        currentIndex = 0
    }

    // MARK: - Load Feed

    func loadFeed() async {
        isLoading = true
        error = nil
        books = [] // Clear existing books

        // Seed from the durable on-device signal store so previously seen/disliked
        // books stay excluded across launches.
        engine.load()
        seenBookIds = engine.seenBookIds

        do {
            // When Supabase auth lands, union in the server's swiped ids too.
            if let userId = AuthService.shared.currentUserId,
               let serverSeen = try? await supabaseService.fetchSwipedBookIds(userId: userId) {
                seenBookIds.formUnion(serverSeen)
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

    func loadFeedIfNeeded() async {
        guard books.isEmpty else { return }
        await loadFeed()
    }

    // MARK: - Fetch More Books

    private func fetchMoreBooks() async throws {
        // Only one fetch at a time. Rapid like/dislike swiping used to fire several
        // concurrent fetches that each snapshotted `books` before appending, producing
        // duplicate IDs in the ForEach and blanking the screen.
        guard !isFetchingMore else { return }
        isFetchingMore = true
        defer { isFetchingMore = false }

        var addedCount = 0
        var attempts = 0
        var lastError: Error?

        // Retry with fresh genres until we actually add some books. Strict English
        // filtering plus seen/disliked exclusions can leave a single fetch nearly
        // empty, which otherwise strands the user at the end with nothing to scroll.
        while addedCount < 5 && attempts < 4 {
            attempts += 1
            do {
                let candidates = try await fetchCandidates()
                let ranked = await engine.rankBySimilarity(candidates)

                // Compute exclusions AFTER the awaits, so anything that entered the
                // feed meanwhile is still excluded (no duplicate ForEach IDs).
                let existingIds = Set(books.map { $0.id })
                let fresh = ranked.filter {
                    !existingIds.contains($0.id) && !seenBookIds.contains($0.id)
                }

                // Mix in variety so lower-ranked exploration/modern books surface
                // instead of being buried by the taste-match ranking, then spread
                // same-author books apart (the "gap" rule).
                let mixed = mixExploreExploit(fresh)
                let diversified = applyAuthorGap(mixed, take: 10)
                books.append(contentsOf: diversified)
                addedCount += diversified.count
            } catch {
                lastError = error
            }
        }

        if addedCount == 0 {
            // Nothing new — keep content on screen; surface the error only if we have
            // literally nothing to show.
            if books.isEmpty {
                books.append(contentsOf: mockBooks())
            }
            if let lastError = lastError {
                throw lastError
            }
        }
    }

    /// Decides what to fetch: popular rotation during cold start, otherwise a
    /// mostly on-taste subject with a ~25% exploration fraction to avoid a bubble.
    private func fetchCandidates() async throws -> [Book] {
        // Page randomly into results so repeated fetches pull *different* books
        // instead of the same top ~20 every time (a key cause of running dry).
        let startIndex = Int.random(in: 0...3) * 20

        // Cold start — popular rotation, a big page.
        guard engine.hasSignals() else {
            return try await booksService.fetchTrendingBooks(startIndex: startIndex, maxResults: 40)
        }

        // Warm: gather a large, interest-driven pool from several sources at once —
        // your top genre, a favorite author, exploration, and modern releases.
        async let genre = genreCandidates(startIndex: startIndex)
        async let author = authorCandidates()
        async let exploration = explorationCandidates()
        async let modern = modernCandidates()

        let combined = await genre + author + exploration + modern
        var seen = Set<String>()
        let unique = combined.filter { seen.insert($0.id).inserted }

        if unique.isEmpty { throw GoogleBooksError.noResults }
        return unique
    }

    /// Recent, mainstream-friendly books so the feed isn't all older classics.
    /// Pulls quality (relevance-ranked) results from broad contemporary genres and
    /// keeps only those published in roughly the last 15 years.
    private func modernCandidates() async -> [Book] {
        let modernSubjects = ["fiction", "thriller", "romance", "science fiction", "mystery", "fantasy", "young adult"]
        let subject = modernSubjects.randomElement() ?? "fiction"
        let books = (try? await booksService.fetchBooks(subject: subject, startIndex: Int.random(in: 0...2) * 20, maxResults: 40)) ?? []
        return books.filter { ($0.publicationYear ?? 0) >= 2010 }
    }

    private func genreCandidates(startIndex: Int) async -> [Book] {
        if let subject = weightedSubject() {
            return (try? await booksService.fetchBooks(subject: subject, startIndex: startIndex, maxResults: 40)) ?? []
        }
        return (try? await booksService.fetchTrendingBooks(startIndex: startIndex, maxResults: 40)) ?? []
    }

    private func authorCandidates() async -> [Book] {
        guard let author = engine.topPositiveAuthors(limit: 3).randomElement() else { return [] }
        // Keep this modest so a single author can't dominate the candidate pool.
        return (try? await booksService.fetchByAuthor(author, maxResults: 8)) ?? []
    }

    private func explorationCandidates() async -> [Book] {
        (try? await booksService.fetchTrendingBooks(startIndex: Int.random(in: 0...3) * 20, maxResults: 20)) ?? []
    }

    /// Guarantees variety: keeps the strongest taste-matches on top but shuffles the
    /// long tail, so exploration/modern books (which rank lower) still break through
    /// instead of the feed being 100% on-taste classics.
    private func mixExploreExploit(_ ranked: [Book]) -> [Book] {
        let exploitCount = 7
        guard ranked.count > exploitCount else { return ranked }
        let top = Array(ranked.prefix(exploitCount))
        let rest = Array(ranked.dropFirst(exploitCount)).shuffled()
        return top + rest
    }

    /// Author "gap" rule: skips a candidate whose primary author already appears
    /// within the last `authorGap` books of the feed, so no single author clusters
    /// or floods. Deferred books are used only to avoid coming up short.
    private func applyAuthorGap(_ candidates: [Book], take: Int) -> [Book] {
        let authorGap = 6
        var recentAuthors = books.map { $0.primaryAuthor }
        var picked: [Book] = []
        var deferred: [Book] = []

        for book in candidates {
            if recentAuthors.suffix(authorGap).contains(book.primaryAuthor) {
                deferred.append(book)
            } else {
                picked.append(book)
                recentAuthors.append(book.primaryAuthor)
                if picked.count >= take { break }
            }
        }

        if picked.count < take {
            picked.append(contentsOf: deferred.prefix(take - picked.count))
        }
        return picked
    }

    /// Picks a broad browse subject from the user's top categories, weighted by
    /// affinity. Weights use the raw category affinity; the fetch uses its
    /// canonical (broad) subject form.
    private func weightedSubject() -> String? {
        let top = engine.topPositiveCategories(limit: 5)
        guard !top.isEmpty else { return nil }

        let weights = top.map { max(0.05, engine.affinity(for: $0)) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return top.randomElement().map { canonicalSubject(for: $0) } }

        var roll = Double.random(in: 0..<total)
        for (category, weight) in zip(top, weights) {
            roll -= weight
            if roll <= 0 { return canonicalSubject(for: category) }
        }
        return top.last.map { canonicalSubject(for: $0) }
    }

    /// Maps a possibly-granular category (e.g. "Psychological Thriller") to a broad
    /// subject Google Books browses well (e.g. "thriller").
    private func canonicalSubject(for category: String) -> String {
        let lower = category.lowercased()
        if let match = GoogleBooksService.allSubjects.first(where: { lower.contains($0) }) {
            return match
        }
        return lower.split(separator: " ").first.map(String.init) ?? lower
    }

    // MARK: - Index Management
    
    func updateCurrentIndex(_ newIndex: Int) {
        guard newIndex >= 0 && newIndex < books.count else { return }
        currentIndex = newIndex
        prefetchIfNeeded()
    }

    /// Kicks off a background fetch when the feed is running low. The
    /// `isFetchingMore` guard (in fetchMoreBooks) keeps this from stacking up.
    private func prefetchIfNeeded() {
        guard currentIndex >= books.count - prefetchThreshold, !isFetchingMore else { return }
        Task { [weak self] in try? await self?.fetchMoreBooks() }
    }

    private func advanceToNext() {
        if currentIndex < books.count - 1 {
            currentIndex += 1
            prefetchIfNeeded()
        } else {
            // At the very end, fetch then advance once new books arrive.
            Task { [weak self] in
                guard let self = self else { return }
                try? await self.fetchMoreBooks()
                if self.currentIndex < self.books.count - 1 {
                    self.currentIndex += 1
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

    /// Swipe right: positive taste signal, save to Library, and advance.
    func swipeLike() {
        guard let book = currentBook else { return }
        triggerLikeAnimation()
        engine.record(book: book, action: .like)
        recordSwipe(book: book, action: .like)
        saveToLibrary(book: book)
        advanceToNext()
    }

    /// Swipe left: negative taste signal (won't resurface), and advance.
    func swipeDislike() {
        guard let book = currentBook else { return }
        triggerDislikeAnimation()
        engine.record(book: book, action: .dislike)
        recordSwipe(book: book, action: .dislike)
        advanceToNext()
    }

    /// Like + save the current book without advancing (used by the detail view's
    /// Save button, which stays on the book).
    func likeCurrent() {
        guard let book = currentBook else { return }
        triggerLikeAnimation()
        engine.record(book: book, action: .like)
        recordSwipe(book: book, action: .like)
        saveToLibrary(book: book)
    }

    /// Neutral skip — a mild negative signal recorded when the user swipes up past
    /// a book without judging it. Keeps it from resurfacing.
    func skipCurrent() {
        guard let book = currentBook else { return }
        engine.record(book: book, action: .skip)
        seenBookIds.insert(book.id)
    }

    // MARK: - Feedback Animations

    private func triggerLikeAnimation() {
        likeAnimationTrigger = true
        Task {
            try? await Task.sleep(nanoseconds: UInt64(0.8 * 1_000_000_000))
            await MainActor.run { self.likeAnimationTrigger = false }
        }
    }

    private func triggerDislikeAnimation() {
        dislikeAnimationTrigger = true
        Task {
            try? await Task.sleep(nanoseconds: UInt64(0.8 * 1_000_000_000))
            await MainActor.run { self.dislikeAnimationTrigger = false }
        }
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
        let userId = AuthService.shared.currentUserId ?? Self.localUserId
        // Durable local save (works offline, no backend needed).
        LibraryStore.shared.add(book: book, userId: userId, status: .wantToRead)

        // Best-effort server sync for when Supabase auth lands.
        guard let authedId = AuthService.shared.currentUserId else { return }
        Task { [weak self] in
            guard let self = self else { return }
            _ = try? await self.supabaseService.addUserBook(
                userId: authedId,
                googleBooksId: book.id,
                status: .wantToRead
            )
        }
    }

    /// Stable local user id used before real auth exists.
    private static let localUserId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    
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
                thumbnailURL: "https://covers.openlibrary.org/b/id/8354226-M.jpg",
                largeCoverURL: "https://covers.openlibrary.org/b/id/8354226-L.jpg",
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
                thumbnailURL: "https://covers.openlibrary.org/b/id/11200092-M.jpg",
                largeCoverURL: "https://covers.openlibrary.org/b/id/11200092-L.jpg",
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
                thumbnailURL: "https://covers.openlibrary.org/b/id/10201431-M.jpg",
                largeCoverURL: "https://covers.openlibrary.org/b/id/10201431-L.jpg",
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
                thumbnailURL: "https://covers.openlibrary.org/b/id/12539702-M.jpg",
                largeCoverURL: "https://covers.openlibrary.org/b/id/12539702-L.jpg",
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
                thumbnailURL: "https://covers.openlibrary.org/b/id/9407338-M.jpg",
                largeCoverURL: "https://covers.openlibrary.org/b/id/9407338-L.jpg",
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
                thumbnailURL: "https://covers.openlibrary.org/b/id/8314077-M.jpg",
                largeCoverURL: "https://covers.openlibrary.org/b/id/8314077-L.jpg",
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
                thumbnailURL: "https://covers.openlibrary.org/b/id/10313767-M.jpg",
                largeCoverURL: "https://covers.openlibrary.org/b/id/10313767-L.jpg",
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
                thumbnailURL: "https://covers.openlibrary.org/b/id/6976407-M.jpg",
                largeCoverURL: "https://covers.openlibrary.org/b/id/6976407-L.jpg",
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
                thumbnailURL: "https://covers.openlibrary.org/b/id/8794265-M.jpg",
                largeCoverURL: "https://covers.openlibrary.org/b/id/8794265-L.jpg",
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
                thumbnailURL: "https://covers.openlibrary.org/b/id/8824664-M.jpg",
                largeCoverURL: "https://covers.openlibrary.org/b/id/8824664-L.jpg",
                infoLink: nil
            )
        ]
    }
}
