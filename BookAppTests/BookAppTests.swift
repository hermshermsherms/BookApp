import Foundation
@testable import BookApp

// MARK: - Book Model Tests

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
