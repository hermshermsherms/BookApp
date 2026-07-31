import Foundation

/// Service for interacting with the Google Books API
final class GoogleBooksService {
    static let shared = GoogleBooksService()

    private let baseURL = "https://www.googleapis.com/books/v1/volumes"

    // Google removed keyless access (anonymous requests now return HTTP 429 with a
    // 0/day quota), so an API key is required. Set it in Secrets.swift.
    private let apiKey: String? = Config.GoogleBooks.apiKey

    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    // MARK: - Fetch Trending/Popular Books

    /// Broad browse subjects used for the feed (cold-start rotation and the
    /// recommendation engine's exploration/exploitation picks share this list).
    static let allSubjects: [String] = [
        "fiction", "mystery", "science fiction", "romance",
        "biography", "history", "self help", "fantasy",
        "thriller", "literary fiction", "philosophy", "psychology"
    ]

    /// Fetches popular books across genres for the Discovery feed.
    /// Rotates through subjects to keep the feed varied (used for cold start).
    func fetchTrendingBooks(startIndex: Int = 0, maxResults: Int = 10) async throws -> [Book] {
        let randomSubject = Self.allSubjects.randomElement() ?? "fiction"
        return try await fetchBooks(subject: randomSubject, startIndex: startIndex, maxResults: maxResults)
    }

    /// Fetches books for a specific subject/genre. Thin wrapper over `searchBooks`
    /// (reuses the transient-error retry) — used by the recommendation feed.
    func fetchBooks(subject: String, startIndex: Int = 0, maxResults: Int = 10) async throws -> [Book] {
        try await searchBooks(query: "subject:\(subject)", startIndex: startIndex, maxResults: maxResults, orderBy: "relevance")
    }

    /// Fetches more books by a specific author — used to retrieve candidates from
    /// the user's favorite authors.
    func fetchByAuthor(_ author: String, startIndex: Int = 0, maxResults: Int = 20) async throws -> [Book] {
        try await searchBooks(query: "inauthor:\(author)", startIndex: startIndex, maxResults: maxResults, orderBy: "relevance")
    }

    // MARK: - Search Books

    /// Search books by title, author, or general query
    func searchBooks(query: String, startIndex: Int = 0, maxResults: Int = 20, orderBy: String = "relevance") async throws -> [Book] {
        guard var components = URLComponents(string: baseURL) else {
            throw GoogleBooksError.invalidURL
        }

        // Pass the raw query — URLComponents percent-encodes query-item values itself.
        // Pre-encoding here caused double-encoding (spaces became %2520), which broke
        // any multi-word subject/query.
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "startIndex", value: "\(startIndex)"),
            URLQueryItem(name: "maxResults", value: "\(maxResults)"),
            URLQueryItem(name: "orderBy", value: orderBy),
            URLQueryItem(name: "printType", value: "books"),
            URLQueryItem(name: "langRestrict", value: "en"),
        ]
        
        // Only add API key if available
        if let apiKey = apiKey {
            components.queryItems?.append(URLQueryItem(name: "key", value: apiKey))
        }

        guard let url = components.url else {
            throw GoogleBooksError.invalidURL
        }

        // The Google Books API intermittently returns 503 (and occasionally other
        // 5xx / 429) for browse-style `subject:` queries, so retry transient failures
        // with a short backoff before giving up.
        let data = try await fetchWithRetry(url: url)

        let booksResponse = try decoder.decode(GoogleBooksResponse.self, from: data)

        let books = booksResponse.items?.compactMap { item -> Book? in
            // English only — `langRestrict` is a soft hint, so enforce the volume's
            // actual language to keep translated/foreign editions out of the feed.
            guard item.volumeInfo.language == "en" else { return nil }
            let book = item.toBook()
            guard book.thumbnailURL != nil, let description = book.description else { return nil }

            // Skip auto-generated public-domain reprints (e.g. "Forgotten Books"),
            // which have thin "Excerpt from …" blurbs and low-resolution scans.
            let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 80 else { return nil }
            let lower = trimmed.lowercased()
            guard !lower.hasPrefix("excerpt from"), !lower.contains("forgotten books") else { return nil }

            return book
        } ?? []

        return books
    }

    // MARK: - Networking

    /// Performs a GET for `url`, retrying transient failures (429 + 5xx) with a
    /// short exponential backoff. Returns the response body on success.
    private func fetchWithRetry(url: URL, maxAttempts: Int = 3) async throws -> Data {
        var lastStatus = 0

        for attempt in 0..<maxAttempts {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleBooksError.invalidResponse
            }

            let status = httpResponse.statusCode
            if 200...299 ~= status {
                return data
            }

            lastStatus = status

            // Retry on rate-limit / server-side transient errors.
            let isTransient = status == 429 || (500...599 ~= status)
            if isTransient, attempt < maxAttempts - 1 {
                // 0.5s, 1.0s, ... plus jitter to avoid hammering in lockstep.
                let backoff = Double(attempt + 1) * 0.5 + Double.random(in: 0...0.25)
                try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                continue
            }

            // Non-retryable, or out of attempts.
            switch status {
            case 429:
                throw GoogleBooksError.rateLimited
            case 403:
                // API key invalid, quota exceeded, or restricted.
                throw GoogleBooksError.rateLimited
            default:
                throw GoogleBooksError.httpError(status)
            }
        }

        throw GoogleBooksError.httpError(lastStatus)
    }

    // MARK: - Fetch Book Details

    /// Fetch detailed info for a single book by its Google Books ID
    func fetchBookDetails(id: String) async throws -> Book {
        var urlString = "\(baseURL)/\(id)"
        if let apiKey = apiKey {
            urlString += "?key=\(apiKey)"
        }
        
        guard let url = URL(string: urlString) else {
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
