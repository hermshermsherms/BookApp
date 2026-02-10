import Foundation

/// Service for interacting with the Google Books API
final class GoogleBooksService {
    static let shared = GoogleBooksService()

    private let baseURL = "https://www.googleapis.com/books/v1/volumes"

    // TODO: Move to environment config before release
    private let apiKey = "YOUR_GOOGLE_BOOKS_API_KEY"

    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    // MARK: - Fetch Trending/Popular Books

    /// Fetches popular books across genres for the Discovery feed.
    /// Rotates through subjects to keep the feed varied.
    func fetchTrendingBooks(startIndex: Int = 0, maxResults: Int = 10) async throws -> [Book] {
        let subjects = [
            "fiction", "mystery", "science fiction", "romance",
            "biography", "history", "self help", "fantasy",
            "thriller", "literary fiction", "philosophy", "psychology"
        ]

        let randomSubject = subjects.randomElement() ?? "fiction"
        let query = "subject:\(randomSubject)"

        return try await searchBooks(query: query, startIndex: startIndex, maxResults: maxResults, orderBy: "relevance")
    }

    // MARK: - Search Books

    /// Search books by title, author, or general query
    func searchBooks(query: String, startIndex: Int = 0, maxResults: Int = 20, orderBy: String = "relevance") async throws -> [Book] {
        guard var components = URLComponents(string: baseURL) else {
            throw GoogleBooksError.invalidURL
        }

        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query

        components.queryItems = [
            URLQueryItem(name: "q", value: encodedQuery),
            URLQueryItem(name: "startIndex", value: "\(startIndex)"),
            URLQueryItem(name: "maxResults", value: "\(maxResults)"),
            URLQueryItem(name: "orderBy", value: orderBy),
            URLQueryItem(name: "printType", value: "books"),
            URLQueryItem(name: "langRestrict", value: "en"),
            URLQueryItem(name: "key", value: apiKey),
        ]

        guard let url = components.url else {
            throw GoogleBooksError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleBooksError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 429 {
                throw GoogleBooksError.rateLimited
            }
            throw GoogleBooksError.httpError(httpResponse.statusCode)
        }

        let booksResponse = try decoder.decode(GoogleBooksResponse.self, from: data)

        let books = booksResponse.items?.compactMap { item -> Book? in
            let book = item.toBook()
            // Filter out books without covers or descriptions
            guard book.thumbnailURL != nil, book.description != nil else { return nil }
            return book
        } ?? []

        return books
    }

    // MARK: - Fetch Book Details

    /// Fetch detailed info for a single book by its Google Books ID
    func fetchBookDetails(id: String) async throws -> Book {
        guard let url = URL(string: "\(baseURL)/\(id)?key=\(apiKey)") else {
            throw GoogleBooksError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GoogleBooksError.invalidResponse
        }

        let item = try decoder.decode(GoogleBookItem.self, from: data)
        return item.toBook()
    }

    // MARK: - Fetch Similar Books

    /// Fetch books similar to the given book (by same author or category)
    func fetchSimilarBooks(to book: Book, maxResults: Int = 6) async throws -> [Book] {
        let query: String
        if let category = book.categories.first {
            query = "subject:\(category)"
        } else {
            query = "inauthor:\(book.authors.first ?? "")"
        }

        let results = try await searchBooks(query: query, maxResults: maxResults + 1)
        // Filter out the original book
        return results.filter { $0.id != book.id }
    }
}

// MARK: - Errors

enum GoogleBooksError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case rateLimited
    case noResults

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL."
        case .invalidResponse:
            return "Invalid response from server."
        case .httpError(let code):
            return "Server error (HTTP \(code))."
        case .rateLimited:
            return "Too many requests. Please try again later."
        case .noResults:
            return "No books found."
        }
    }
}
