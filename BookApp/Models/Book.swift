import Foundation

/// Represents a book from the Google Books API
struct Book: Identifiable, Codable, Equatable {
    let id: String // Google Books volume ID
    let title: String
    let authors: [String]
    let description: String?
    let categories: [String]
    let averageRating: Double?
    let pageCount: Int?
    let publishedDate: String?
    let thumbnailURL: String?
    let largeCoverURL: String?
    let infoLink: String?

    var authorDisplay: String {
        authors.joined(separator: ", ")
    }

    var genreDisplay: String {
        categories.first ?? "General"
    }

    var hook: String {
        guard let desc = description else { return "" }
        if desc.count > 120 {
            return String(desc.prefix(117)) + "..."
        }
        return desc
    }

    /// Text fed to the on-device embedding model to build a semantic vector for
    /// this book (title + authors + genres + description).
    var embeddingText: String {
        var parts: [String] = [title]
        if !authors.isEmpty { parts.append(authors.joined(separator: ", ")) }
        if !categories.isEmpty { parts.append(categories.joined(separator: ", ")) }
        if let description = description, !description.isEmpty { parts.append(description) }
        return parts.joined(separator: ". ")
    }

    var ratingDisplay: String {
        guard let rating = averageRating else { return "—" }
        return String(format: "%.1f", rating)
    }

    var pageCountDisplay: String {
        guard let pages = pageCount else { return "—" }
        return "\(pages) pages"
    }
    
    /// Returns the highest quality image URL available, falling back gracefully.
    var highQualityImageURL: URL? {
        upgradedCoverURL(from: largeCoverURL) ?? upgradedCoverURL(from: thumbnailURL)
    }

    /// Google's Books API only advertises a ~128px `thumbnail` for most volumes,
    /// which looks grainy at full-card size. Google actually hosts the full scan,
    /// so we request a larger render via `&w=` and drop the page-curl effect.
    /// Non-Google URLs (e.g. Open Library) are returned as-is (https-normalized).
    private func upgradedCoverURL(from raw: String?) -> URL? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        var s = raw.replacingOccurrences(of: "http://", with: "https://")
        if s.contains("books.google") && s.contains("/books/content") {
            s = s.replacingOccurrences(of: "&edge=curl", with: "")
            if !s.contains("w=") {
                s += "&w=800"
            }
        }
        return URL(string: s)
    }

    // MARK: - Purchase URLs

    var amazonURL: URL? {
        let searchTerm = "\(title) \(authorDisplay)"
        guard let query = searchTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              !query.isEmpty else { return nil }
        // Use mobile-friendly Amazon URL that works better in in-app browsers
        return URL(string: "https://www.amazon.com/s?k=\(query)&i=stripbooks&ref=nb_sb_noss")
    }

    var appleBooksURL: URL? {
        let searchTerm = "\(title) \(authorDisplay)"
        guard let query = searchTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              !query.isEmpty else { return nil }
        // Use web URL for Safari in-app browser (works better than app URL scheme)
        return URL(string: "https://books.apple.com/us/search?term=\(query)")
    }

    var bookshopURL: URL? {
        let searchTerm = "\(title) \(authorDisplay)"
        guard let query = searchTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              !query.isEmpty else { return nil }
        return URL(string: "https://bookshop.org/search?keywords=\(query)")
    }
}

// MARK: - Google Books API Response Models

struct GoogleBooksResponse: Codable {
    let totalItems: Int?
    let items: [GoogleBookItem]?
}

struct GoogleBookItem: Codable {
    let id: String
    let volumeInfo: VolumeInfo
}

struct VolumeInfo: Codable {
    let title: String
    let authors: [String]?
    let description: String?
    let categories: [String]?
    let averageRating: Double?
    let pageCount: Int?
    let publishedDate: String?
    let imageLinks: ImageLinks?
    let infoLink: String?
    let language: String?
}

struct ImageLinks: Codable {
    let smallThumbnail: String?
    let thumbnail: String?
    let small: String?
    let medium: String?
    let large: String?

    var bestQuality: String? {
        large ?? medium ?? small ?? thumbnail ?? smallThumbnail
    }

    var thumbnailHTTPS: String? {
        thumbnail?.replacingOccurrences(of: "http://", with: "https://")
    }

    var bestQualityHTTPS: String? {
        bestQuality?.replacingOccurrences(of: "http://", with: "https://")
    }
}

// MARK: - Mapping

extension GoogleBookItem {
    func toBook() -> Book {
        Book(
            id: id,
            title: volumeInfo.title,
            authors: volumeInfo.authors ?? ["Unknown Author"],
            description: volumeInfo.description,
            categories: volumeInfo.categories ?? [],
            averageRating: volumeInfo.averageRating,
            pageCount: volumeInfo.pageCount,
            publishedDate: volumeInfo.publishedDate,
            thumbnailURL: volumeInfo.imageLinks?.thumbnailHTTPS,
            largeCoverURL: volumeInfo.imageLinks?.bestQualityHTTPS,
            infoLink: volumeInfo.infoLink
        )
    }
}
