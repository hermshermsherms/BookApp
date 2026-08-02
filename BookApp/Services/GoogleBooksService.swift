import Foundation

/// Service for interacting with the Google Books API
final class GoogleBooksService {
    static let shared = GoogleBooksService()

    private let baseURL = "https://www.googleapis.com/books/v1/volumes"

    // Google removed keyless access (anonymous requests now return HTTP 429 with a
    // 0/day quota), so an API key is required. Set GOOGLE_BOOKS_API_KEY in
    // the app target's Info settings when you are ready to use live data.
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
        try await fetchBookItem(id: id).toBook()
    }

    /// Finds a provider-authorized reader. Google may expose a sample, purchased
    /// edition, or public-domain book depending on region/account; Gutenberg is
    /// used only for an exact public-domain title/author match.
    func fetchReadingResource(for book: Book) async throws -> BookReadingResource {
        if let direct = try? await fetchBookItem(id: book.id),
           let resource = direct.readingResource(fallbackTitle: book.title) {
            return resource
        }

        if let googleResource = try? await fetchGoogleEPUBEdition(for: book) {
            return googleResource
        }

        if let gutenbergResource = try? await fetchGutenbergEPUBEdition(for: book) {
            return gutenbergResource
        }

        throw GoogleBooksError.epubUnavailable
    }

    private func fetchGoogleEPUBEdition(for book: Book) async throws -> BookReadingResource {

        guard var components = URLComponents(string: baseURL) else {
            throw GoogleBooksError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: "intitle:\(book.title) inauthor:\(book.primaryAuthor)"),
            URLQueryItem(name: "maxResults", value: "10"),
            URLQueryItem(name: "printType", value: "books")
        ]
        if let apiKey {
            components.queryItems?.append(URLQueryItem(name: "key", value: apiKey))
        }
        guard let url = components.url else { throw GoogleBooksError.invalidURL }

        let data = try await fetchWithRetry(url: url)
        let response = try decoder.decode(GoogleBooksResponse.self, from: data)
        let normalizedTitle = book.title.normalizedBookSearchText
        let normalizedAuthor = book.primaryAuthor.normalizedBookSearchText

        let candidates = response.items ?? []
        let closest = candidates.first {
            $0.volumeInfo.title.normalizedBookSearchText == normalizedTitle
                && ($0.volumeInfo.authors ?? []).contains {
                    $0.normalizedBookSearchText.contains(normalizedAuthor)
                        || normalizedAuthor.contains($0.normalizedBookSearchText)
                }
        }

        guard let resource = closest?.readingResource(fallbackTitle: book.title) else {
            throw GoogleBooksError.epubUnavailable
        }
        return resource
    }

    /// Project Gutenberg is a public-domain fallback for books that Google does
    /// not expose as EPUB. We verify the title and author on Gutenberg's own book
    /// page, then retain its EPUB URL while presenting the corresponding full
    /// HTML rendition in WebKit for reliable in-app reading.
    private func fetchGutenbergEPUBEdition(for book: Book) async throws -> BookReadingResource {
        guard var components = URLComponents(string: "https://www.gutenberg.org/ebooks/search/") else {
            throw GoogleBooksError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "query", value: "\(book.title) \(book.primaryAuthor)"),
            URLQueryItem(name: "submit_search", value: "Go!")
        ]
        guard let url = components.url else { throw GoogleBooksError.invalidURL }

        let data = try await fetchWithRetry(url: url)
        guard let searchHTML = String(data: data, encoding: .utf8) else {
            throw GoogleBooksError.invalidResponse
        }

        let candidateIDs = Array(searchHTML.regexCaptures(#"/ebooks/([0-9]+)"#).uniqued().prefix(8))
        let expectedTitle = book.title.normalizedBookSearchText
        let expectedAuthorTokens = book.primaryAuthor.normalizedBookSearchTokens

        for candidateID in candidateIDs {
            guard let detailURL = URL(string: "https://www.gutenberg.org/ebooks/\(candidateID)") else {
                continue
            }
            let detailData = try await fetchWithRetry(url: detailURL)
            guard let detailHTML = String(data: detailData, encoding: .utf8),
                  let heading = detailHTML.firstRegexCapture(
                    #"<h1[^>]*id="book_title"[^>]*>(.*?)</h1>"#
                  )?.decodingCommonHTMLEntities,
                  let byRange = heading.range(of: " by ", options: [.caseInsensitive, .backwards]) else {
                continue
            }

            let candidateTitle = String(heading[..<byRange.lowerBound]).normalizedBookSearchText
            let candidateAuthor = String(heading[byRange.upperBound...]).normalizedBookSearchTokens
            guard candidateTitle == expectedTitle,
                  expectedAuthorTokens.isSubset(of: candidateAuthor),
                  let readerPath = detailHTML.firstRegexCapture(
                    #"class="read-online-button"[^>]*href="([^"]+)""#
                  ),
                  let epubPath = detailHTML.firstRegexCapture(
                    #"class="featured-format-link"[^>]*href="([^"]+\.epub[^"]*)""#
                  ),
                  let readerURL = URL(string: readerPath, relativeTo: detailURL)?.absoluteURL,
                  let epubURL = URL(string: epubPath, relativeTo: detailURL)?.absoluteURL else {
                continue
            }

            return BookReadingResource(
                id: "gutenberg-\(candidateID)",
                bookID: book.id,
                title: String(heading[..<byRange.lowerBound]),
                readerURL: readerURL,
                epubDownloadURL: epubURL,
                isPublicDomain: true
            )
        }

        throw GoogleBooksError.epubUnavailable
    }

    private func fetchBookItem(id: String) async throws -> GoogleBookItem {
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

        return try decoder.decode(GoogleBookItem.self, from: data)
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
        // Filter out the exact volume and duplicate editions of the source title.
        // Google frequently returns several scans/editions with different IDs.
        let sourceTitle = book.title.normalizedBookSearchText
        return results.filter {
            $0.id != book.id && $0.title.normalizedBookSearchText != sourceTitle
        }
    }
}

// MARK: - Errors

enum GoogleBooksError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case rateLimited
    case noResults
    case epubUnavailable

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
        case .epubUnavailable:
            return "A readable preview is not available for this book."
        }
    }
}

private extension GoogleBookItem {
    func readingResource(fallbackTitle: String) -> BookReadingResource? {
        guard let rawReaderURL = accessInfo?.webReaderLink,
              let readerURL = URL(string: rawReaderURL.replacingOccurrences(of: "http://", with: "https://")) else {
            return nil
        }
        let downloadURL = accessInfo?.epub?.downloadLink
            .flatMap { URL(string: $0.replacingOccurrences(of: "http://", with: "https://")) }
        return BookReadingResource(
            id: id,
            bookID: id,
            title: volumeInfo.title.isEmpty ? fallbackTitle : volumeInfo.title,
            readerURL: readerURL,
            epubDownloadURL: downloadURL,
            isPublicDomain: accessInfo?.publicDomain ?? false
        )
    }
}

private extension String {
    var normalizedBookSearchText: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var normalizedBookSearchTokens: Set<String> {
        Set(normalizedBookSearchText.split(separator: " ").map(String.init))
    }

    func regexCaptures(_ pattern: String) -> [String] {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let fullRange = NSRange(startIndex..<endIndex, in: self)
        return expression.matches(in: self, range: fullRange).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: self) else { return nil }
            return String(self[range])
        }
    }

    func firstRegexCapture(_ pattern: String) -> String? {
        regexCaptures(pattern).first
    }

    var decodingCommonHTMLEntities: String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
