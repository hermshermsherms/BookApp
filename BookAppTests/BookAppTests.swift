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
        
        viewModel.currentBook = mockBook
        
        // Test single tap
        viewModel.singleTap()
        XCTAssertTrue(viewModel.showDetailView)
        
        // Test swipe right (buy)
        viewModel.swipeRight()
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
