import Foundation

/// Service for interacting with the Supabase backend (PostgreSQL)
final class SupabaseService {
    static let shared = SupabaseService()

    // TODO: Move to environment config before release
    private let supabaseURL = "https://YOUR_PROJECT.supabase.co"
    private let supabaseAnonKey = "YOUR_ANON_KEY"

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private var accessToken: String?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Auth Token

    func setAccessToken(_ token: String?) {
        self.accessToken = token
    }

    // MARK: - Request Builder

    private func makeRequest(path: String, method: String = "GET", body: Data? = nil, queryItems: [URLQueryItem]? = nil) throws -> URLRequest {
        guard var components = URLComponents(string: "\(supabaseURL)/rest/v1/\(path)") else {
            throw SupabaseError.invalidURL
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw SupabaseError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")

        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = body
        return request
    }

    // MARK: - User Books

    func fetchUserBooks(userId: UUID, status: BookStatus? = nil) async throws -> [UserBook] {
        var queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId.uuidString)"),
            URLQueryItem(name: "order", value: "added_at.desc"),
        ]

        if let status = status {
            queryItems.append(URLQueryItem(name: "status", value: "eq.\(status.rawValue)"))
        }

        let request = try makeRequest(path: "user_books", queryItems: queryItems)
        let (data, _) = try await session.data(for: request)
        return try decoder.decode([UserBook].self, from: data)
    }

    func addUserBook(userId: UUID, googleBooksId: String, status: BookStatus = .wantToRead) async throws -> UserBook {
        let body: [String: Any] = [
            "user_id": userId.uuidString,
            "google_books_id": googleBooksId,
            "status": status.rawValue,
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let request = try makeRequest(path: "user_books", method: "POST", body: bodyData)
        let (data, _) = try await session.data(for: request)

        let books = try decoder.decode([UserBook].self, from: data)
        guard let book = books.first else {
            throw SupabaseError.noData
        }
        return book
    }

    func updateBookStatus(bookId: UUID, status: BookStatus) async throws {
        let body: [String: Any] = [
            "status": status.rawValue,
            "updated_at": ISO8601DateFormatter().string(from: Date()),
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let queryItems = [URLQueryItem(name: "id", value: "eq.\(bookId.uuidString)")]
        let request = try makeRequest(path: "user_books", method: "PATCH", body: bodyData, queryItems: queryItems)
        let _ = try await session.data(for: request)
    }

    func deleteUserBook(bookId: UUID) async throws {
        let queryItems = [URLQueryItem(name: "id", value: "eq.\(bookId.uuidString)")]
        let request = try makeRequest(path: "user_books", method: "DELETE", queryItems: queryItems)
        let _ = try await session.data(for: request)
    }

    // MARK: - Reviews

    func fetchReview(userId: UUID, googleBooksId: String) async throws -> Review? {
        let queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId.uuidString)"),
            URLQueryItem(name: "google_books_id", value: "eq.\(googleBooksId)"),
        ]

        let request = try makeRequest(path: "reviews", queryItems: queryItems)
        let (data, _) = try await session.data(for: request)
        let reviews = try decoder.decode([Review].self, from: data)
        return reviews.first
    }

    func fetchUserReviews(userId: UUID) async throws -> [Review] {
        let queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId.uuidString)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
        ]

        let request = try makeRequest(path: "reviews", queryItems: queryItems)
        let (data, _) = try await session.data(for: request)
        return try decoder.decode([Review].self, from: data)
    }

    func upsertReview(userId: UUID, googleBooksId: String, rating: Int, reviewText: String?) async throws -> Review {
        let body: [String: Any?] = [
            "user_id": userId.uuidString,
            "google_books_id": googleBooksId,
            "rating": rating,
            "review_text": reviewText,
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body.compactMapValues { $0 })

        var request = try makeRequest(path: "reviews", method: "POST", body: bodyData)
        // Upsert: if review exists for this user+book, update it
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        let (data, _) = try await session.data(for: request)
        let reviews = try decoder.decode([Review].self, from: data)
        guard let review = reviews.first else {
            throw SupabaseError.noData
        }
        return review
    }

    func deleteReview(reviewId: UUID) async throws {
        let queryItems = [URLQueryItem(name: "id", value: "eq.\(reviewId.uuidString)")]
        let request = try makeRequest(path: "reviews", method: "DELETE", queryItems: queryItems)
        let _ = try await session.data(for: request)
    }

    // MARK: - Swipe History

    func recordSwipe(userId: UUID, googleBooksId: String, action: SwipeType) async throws {
        let body: [String: Any] = [
            "user_id": userId.uuidString,
            "google_books_id": googleBooksId,
            "action": action.rawValue,
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let request = try makeRequest(path: "swipe_history", method: "POST", body: bodyData)
        let _ = try await session.data(for: request)
    }

    func fetchSwipedBookIds(userId: UUID) async throws -> Set<String> {
        let queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId.uuidString)"),
            URLQueryItem(name: "select", value: "google_books_id"),
        ]

        let request = try makeRequest(path: "swipe_history", queryItems: queryItems)
        let (data, _) = try await session.data(for: request)

        struct SwipeRecord: Codable {
            let google_books_id: String
        }

        let records = try decoder.decode([SwipeRecord].self, from: data)
        return Set(records.map { $0.google_books_id })
    }

    // MARK: - User Stats

    struct UserStats: Codable {
        let booksRead: Int
        let reviewsWritten: Int
        let totalBooks: Int
    }

    func fetchUserStats(userId: UUID) async throws -> UserStats {
        async let booksResult = fetchUserBooks(userId: userId)
        async let reviewsResult = fetchUserReviews(userId: userId)

        let books = try await booksResult
        let reviews = try await reviewsResult

        return UserStats(
            booksRead: books.filter { $0.status == .read }.count,
            reviewsWritten: reviews.count,
            totalBooks: books.count
        )
    }
}

// MARK: - Errors

enum SupabaseError: LocalizedError {
    case invalidURL
    case noData
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL."
        case .noData:
            return "No data returned from server."
        case .unauthorized:
            return "You must be signed in to perform this action."
        }
    }
}
