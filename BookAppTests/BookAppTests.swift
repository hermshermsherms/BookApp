import XCTest
import Foundation
@testable import BookApp

// MARK: - Book Model Tests

class BookModelTests: XCTestCase {

func testBookMapping() {
    let item = GoogleBookItem(
        id: "test-id",
        volumeInfo: VolumeInfo(
            title: "Test Book",
            authors: ["Test Author"],
            description: "A test description",
            categories: ["Fiction"],
            averageRating: 4.5,
            pageCount: 300,
            publishedDate: "2024-01-01",
            imageLinks: ImageLinks(
                smallThumbnail: nil,
                thumbnail: "http://example.com/thumb.jpg",
                small: nil,
                medium: nil,
                large: nil
            ),
            infoLink: nil
        )
    )

    let book = item.toBook()
    assert(book.id == "test-id")
    assert(book.title == "Test Book")
    assert(book.authors == ["Test Author"])
    assert(book.averageRating == 4.5)
    assert(book.pageCount == 300)
    assert(book.thumbnailURL == "https://example.com/thumb.jpg")
    assert(book.authorDisplay == "Test Author")
    assert(book.ratingDisplay == "4.5")
    assert(book.pageCountDisplay == "300 pages")
    assert(book.genreDisplay == "Fiction")
}

func testBookHookTruncation() {
    let longDescription = String(repeating: "a", count: 200)
    let item = GoogleBookItem(
        id: "test",
        volumeInfo: VolumeInfo(
            title: "Test",
            authors: nil,
            description: longDescription,
            categories: nil,
            averageRating: nil,
            pageCount: nil,
            publishedDate: nil,
            imageLinks: nil,
            infoLink: nil
        )
    )

    let book = item.toBook()
    assert(book.hook.count <= 120)
    assert(book.hook.hasSuffix("..."))
    assert(book.authors == ["Unknown Author"])
    assert(book.genreDisplay == "General")
    assert(book.ratingDisplay == "—")
}

func testPurchaseURLGeneration() {
    let book = Book(
        id: "test",
        title: "The Great Book",
        authors: ["Author One"],
        description: "A great book",
        categories: ["Fiction"],
        averageRating: 4.0,
        pageCount: 200,
        publishedDate: "2024",
        thumbnailURL: nil,
        largeCoverURL: nil,
        infoLink: nil
    )
    
    XCTAssertNotNil(book.amazonURL)
    XCTAssertNotNil(book.appleBooksURL)
    XCTAssertNotNil(book.bookshopURL)
    
    XCTAssertTrue(book.amazonURL!.absoluteString.contains("amazon.com"))
    XCTAssertTrue(book.appleBooksURL!.absoluteString.contains("books.apple.com"))
    XCTAssertTrue(book.bookshopURL!.absoluteString.contains("bookshop.org"))
}

func testPurchaseURLWithEmptyTitle() {
    let book = Book(
        id: "test",
        title: "",
        authors: ["Author"],
        description: "Description",
        categories: [],
        averageRating: nil,
        pageCount: nil,
        publishedDate: nil,
        thumbnailURL: nil,
        largeCoverURL: nil,
        infoLink: nil
    )
    
    XCTAssertNil(book.amazonURL)
    XCTAssertNil(book.appleBooksURL)
    XCTAssertNil(book.bookshopURL)
}

func testHighQualityImageURL() {
    // Test with both URLs available - should prefer large
    var book = Book(
        id: "test1",
        title: "Test",
        authors: ["Author"],
        description: nil,
        categories: [],
        averageRating: nil,
        pageCount: nil,
        publishedDate: nil,
        thumbnailURL: "https://example.com/small.jpg",
        largeCoverURL: "https://example.com/large.jpg",
        infoLink: nil
    )
    
    XCTAssertEqual(book.highQualityImageURL?.absoluteString, "https://example.com/large.jpg")
    
    // Test with only thumbnail available
    book = Book(
        id: "test2",
        title: "Test",
        authors: ["Author"],
        description: nil,
        categories: [],
        averageRating: nil,
        pageCount: nil,
        publishedDate: nil,
        thumbnailURL: "https://example.com/thumb.jpg",
        largeCoverURL: nil,
        infoLink: nil
    )
    
    XCTAssertEqual(book.highQualityImageURL?.absoluteString, "https://example.com/thumb.jpg")
    
    // Test with no URLs available
    book = Book(
        id: "test3",
        title: "Test",
        authors: ["Author"],
        description: nil,
        categories: [],
        averageRating: nil,
        pageCount: nil,
        publishedDate: nil,
        thumbnailURL: nil,
        largeCoverURL: nil,
        infoLink: nil
    )
    
    XCTAssertNil(book.highQualityImageURL)
    
    // Test with empty string URLs
    book = Book(
        id: "test4",
        title: "Test",
        authors: ["Author"],
        description: nil,
        categories: [],
        averageRating: nil,
        pageCount: nil,
        publishedDate: nil,
        thumbnailURL: "",
        largeCoverURL: "",
        infoLink: nil
    )
    
    XCTAssertNil(book.highQualityImageURL)
}

}

// MARK: - Discovery ViewModel Tests

class DiscoveryViewModelTests: XCTestCase {
    
    @MainActor
    func testInitialState() {
        let viewModel = DiscoveryViewModel()
        
        XCTAssertNil(viewModel.currentBook)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.showPurchaseSheet)
        XCTAssertFalse(viewModel.showDetailView)
        XCTAssertFalse(viewModel.likeAnimationTrigger)
    }
    
    @MainActor
    func testSwipeActions() {
        let viewModel = DiscoveryViewModel()
        let mockBook = Book(
            id: "test-book",
            title: "Test Book",
            authors: ["Test Author"],
            description: "Test description",
            categories: ["Fiction"],
            averageRating: 4.0,
            pageCount: 200,
            publishedDate: "2024",
            thumbnailURL: nil,
            largeCoverURL: nil,
            infoLink: nil
        )
        
        // Simulate having books loaded
        viewModel.books = [mockBook]
        viewModel.currentIndex = 0
        
        // Test single tap
        viewModel.singleTap()
        XCTAssertTrue(viewModel.showDetailView)
        
        // Test buy action
        viewModel.buyBook()
        XCTAssertTrue(viewModel.showPurchaseSheet)
        
        // Test double tap (like) - should trigger animation
        viewModel.doubleTap()
        XCTAssertTrue(viewModel.likeAnimationTrigger)
    }
}

// MARK: - Google Books Service Tests

class GoogleBooksServiceTests: XCTestCase {
    
    func testErrorCases() {
        let service = GoogleBooksService.shared
        
        // Test error descriptions
        XCTAssertNotNil(GoogleBooksError.invalidURL.errorDescription)
        XCTAssertNotNil(GoogleBooksError.rateLimited.errorDescription)
        XCTAssertNotNil(GoogleBooksError.httpError(404).errorDescription)
    }
    
    func testURLConstruction() {
        // Test that URL construction handles special characters
        let testQuery = "test query with spaces & symbols"
        let encodedQuery = testQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        XCTAssertNotNil(encodedQuery)
        XCTAssertFalse(encodedQuery!.contains(" "))
        XCTAssertFalse(encodedQuery!.contains("&"))
    }
}

// MARK: - Authentication Tests

class AuthServiceTests: XCTestCase {
    
    func testAuthErrorDescriptions() {
        let errors: [AuthError] = [
            .invalidCredential,
            .cancelled,
            .appleSignInFailed("Test error"),
            .invalidURL,
            .supabaseAuthFailed,
            .invalidUserId,
            .notAuthenticated
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
}

// MARK: - Swipe Action Tests

class SwipeActionTests: XCTestCase {
    
    func testSwipeTypeCoding() throws {
        let swipeTypes: [SwipeType] = [.like, .dislike, .buy]
        
        for swipeType in swipeTypes {
            let encoded = try JSONEncoder().encode(swipeType)
            let decoded = try JSONDecoder().decode(SwipeType.self, from: encoded)
            XCTAssertEqual(swipeType, decoded)
        }
    }
    
    func testSwipeActionCoding() throws {
        let swipeAction = SwipeAction(
            id: UUID(),
            userId: UUID(),
            googleBooksId: "test-book-id",
            action: .like,
            swipedAt: Date()
        )
        
        let encoded = try JSONEncoder().encode(swipeAction)
        let decoded = try JSONDecoder().decode(SwipeAction.self, from: encoded)
        
        XCTAssertEqual(swipeAction.id, decoded.id)
        XCTAssertEqual(swipeAction.userId, decoded.userId)
        XCTAssertEqual(swipeAction.googleBooksId, decoded.googleBooksId)
        XCTAssertEqual(swipeAction.action, decoded.action)
    }
}

// MARK: - Profile Shelf Tests

@MainActor
class ProfileShelfTests: XCTestCase {

    private let userId = UUID()

    private func makeBook(id: String, title: String) -> Book {
        Book(
            id: id,
            title: title,
            authors: ["Author"],
            description: nil,
            categories: [],
            averageRating: nil,
            pageCount: nil,
            publishedDate: nil,
            thumbnailURL: nil,
            largeCoverURL: nil,
            infoLink: nil
        )
    }

    private func makeUserBook(id: String, title: String, status: BookStatus, finishedAt: Date) -> UserBook {
        var userBook = UserBook(
            id: UUID(),
            userId: userId,
            googleBooksId: id,
            status: status,
            addedAt: finishedAt,
            updatedAt: finishedAt,
            book: nil
        )
        userBook.book = makeBook(id: id, title: title)
        return userBook
    }

    private func makeReview(bookId: String, rating: Double, text: String? = nil) -> Review {
        Review(
            id: UUID(),
            userId: userId,
            googleBooksId: bookId,
            rating: rating,
            reviewText: text,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func testShelfOnlyIncludesReadBooks() {
        let viewModel = ProfileViewModel()
        let books = [
            makeUserBook(id: "a", title: "Finished", status: .read, finishedAt: Date()),
            makeUserBook(id: "b", title: "In Progress", status: .reading, finishedAt: Date()),
            makeUserBook(id: "c", title: "Saved", status: .wantToRead, finishedAt: Date()),
        ]

        let shelf = viewModel.shelf(books: books, reviews: [])

        XCTAssertEqual(shelf.count, 1)
        XCTAssertEqual(shelf.first?.userBook.googleBooksId, "a")
    }

    func testShelfJoinsReviewsToBooks() {
        let viewModel = ProfileViewModel()
        let books = [makeUserBook(id: "a", title: "Finished", status: .read, finishedAt: Date())]
        let reviews = [makeReview(bookId: "a", rating: 3.5, text: "Loved the ending.")]

        let shelf = viewModel.shelf(books: books, reviews: reviews)

        XCTAssertEqual(shelf.first?.rating, 3.5)
        XCTAssertEqual(shelf.first?.review?.hasText, true)
    }

    func testShelfSortsByRecentThenRatingThenTitle() {
        let viewModel = ProfileViewModel()
        let old = Date(timeIntervalSince1970: 1_000)
        let recent = Date(timeIntervalSince1970: 2_000)

        let books = [
            makeUserBook(id: "a", title: "Zebra", status: .read, finishedAt: old),
            makeUserBook(id: "b", title: "Apple", status: .read, finishedAt: recent),
        ]
        let reviews = [
            makeReview(bookId: "a", rating: 4.5),
            makeReview(bookId: "b", rating: 4.0),
        ]

        viewModel.sort = .recent
        XCTAssertEqual(viewModel.shelf(books: books, reviews: reviews).map(\.title), ["Apple", "Zebra"])

        // Half a star is enough to separate them.
        viewModel.sort = .rating
        XCTAssertEqual(viewModel.shelf(books: books, reviews: reviews).map(\.title), ["Zebra", "Apple"])

        viewModel.sort = .title
        XCTAssertEqual(viewModel.shelf(books: books, reviews: reviews).map(\.title), ["Apple", "Zebra"])
    }

    func testStatsCountAndAverage() {
        let viewModel = ProfileViewModel()
        let books = [
            makeUserBook(id: "a", title: "One", status: .read, finishedAt: Date()),
            makeUserBook(id: "b", title: "Two", status: .read, finishedAt: Date()),
            makeUserBook(id: "c", title: "Three", status: .wantToRead, finishedAt: Date()),
        ]
        let reviews = [
            makeReview(bookId: "a", rating: 4.5),
            makeReview(bookId: "b", rating: 2.0),
        ]

        let stats = viewModel.stats(books: books, reviews: reviews)

        XCTAssertEqual(stats.booksRead, 2)
        XCTAssertEqual(stats.reviewsWritten, 2)
        XCTAssertEqual(stats.totalBooks, 3)
        XCTAssertEqual(stats.averageRating ?? 0, 3.25, accuracy: 0.001)
    }

    func testStatsAverageIsNilWithoutReviews() {
        let viewModel = ProfileViewModel()
        let books = [makeUserBook(id: "a", title: "One", status: .read, finishedAt: Date())]

        XCTAssertNil(viewModel.stats(books: books, reviews: []).averageRating)
    }
}

// MARK: - Half Star Rating Tests

class HalfStarRatingTests: XCTestCase {

    func testSnapRoundsToNearestHalfAndClamps() {
        XCTAssertEqual(Review.snap(3.24), 3.0)
        XCTAssertEqual(Review.snap(3.26), 3.5)
        XCTAssertEqual(Review.snap(0), 0.5)
        XCTAssertEqual(Review.snap(-2), 0.5)
        XCTAssertEqual(Review.snap(9), 5.0)
    }

    func testRatingValidity() {
        let base = Review(
            id: UUID(),
            userId: UUID(),
            googleBooksId: "a",
            rating: 3.5,
            reviewText: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertTrue(base.isValid)

        var quarterStar = base
        quarterStar.rating = 3.25
        XCTAssertFalse(quarterStar.isValid)

        var tooHigh = base
        tooHigh.rating = 5.5
        XCTAssertFalse(tooHigh.isValid)

        var unrated = base
        unrated.rating = 0
        XCTAssertFalse(unrated.isValid)
    }

    func testDisplayTrimsWholeNumbers() {
        XCTAssertEqual(Review.display(4), "4")
        XCTAssertEqual(Review.display(4.5), "4.5")
    }

    func testSymbolPerStarPosition() {
        // A 3.5 rating: three full, one half, one empty.
        let symbols = (1...5).map { StarRatingView.symbol(for: $0, rating: 3.5) }
        XCTAssertEqual(symbols, [
            "star.fill",
            "star.fill",
            "star.fill",
            "star.leadinghalf.filled",
            "star",
        ])
    }

    /// Ratings written before half stars existed were whole-number JSON values.
    func testWholeNumberRatingStillDecodes() throws {
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "user_id": "\(UUID().uuidString)",
            "google_books_id": "abc",
            "rating": 4,
            "created_at": 0,
            "updated_at": 0
        }
        """.data(using: .utf8)!

        let review = try JSONDecoder().decode(Review.self, from: json)

        XCTAssertEqual(review.rating, 4.0)
        XCTAssertTrue(review.isValid)
    }
}
