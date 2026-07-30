import Foundation

/// A user taste signal on a book. Persisted on-device and shaped to map cleanly
/// onto Supabase's `swipe_history` table once sign-in/backend lands.
enum SignalAction: String, Codable {
    case like
    case dislike
    case skip
}

/// One recorded interaction. `categories`/`authors` are captured locally so the
/// taste profile can be recomputed without re-fetching book metadata; they are
/// not part of the future server payload.
struct InteractionSignal: Codable, Identifiable {
    let id: UUID
    let googleBooksId: String   // -> google_books_id
    let action: SignalAction
    let categories: [String]    // local-only (taste profile)
    let authors: [String]       // local-only (taste profile)
    let timestamp: Date         // -> swiped_at
    var syncedToServer: Bool
    var embedding: [Double]?    // local-only semantic vector, backfilled async

    init(book: Book, action: SignalAction, timestamp: Date) {
        self.id = UUID()
        self.googleBooksId = book.id
        self.action = action
        self.categories = book.categories
        self.authors = book.authors
        self.timestamp = timestamp
        self.syncedToServer = false
        self.embedding = nil
    }
}

private struct RecStoreData: Codable {
    var signals: [InteractionSignal]
    var version: Int
}

/// On-device recommendation engine: durable signal log + derived taste profile +
/// content-based scoring. Fully local (no backend required); the Discovery feed
/// uses it to bias which books it fetches and how it ranks them.
@MainActor
final class RecommendationEngine: ObservableObject {
    static let shared = RecommendationEngine()

    // MARK: Derived state (read by the feed)
    private(set) var seenBookIds: Set<String> = []      // like + dislike + skip
    private(set) var dislikedBookIds: Set<String> = []  // never resurface
    private(set) var categoryAffinity: [String: Double] = [:]  // normalized ~ -1...1
    private(set) var authorAffinity: [String: Double] = [:]

    /// Semantic "taste" vector: mean of liked book embeddings, pushed away from
    /// disliked ones. nil until at least one liked book has been embedded.
    private(set) var tasteVector: [Double]?

    // MARK: Signal log
    private var signals: [InteractionSignal] = []

    // MARK: Tuning
    private let likeWeight = 1.0
    private let dislikeWeight = -1.0
    private let skipWeight = -0.15
    private let halfLifeDays = 30.0
    private let storeVersion = 1

    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("BookApp", isDirectory: true)
        self.fileURL = dir.appendingPathComponent("rec_signals.json")
        load()
        // Warm the embedding model so the first feed fetch can rank semantically.
        Task { await EmbeddingService.shared.warmUp() }
    }

    // MARK: - Persistence

    /// Loads the signal log from disk. Tolerant of a missing or corrupt file
    /// (first launch, or a schema we can't read) — falls back to an empty store.
    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let store = try? JSONDecoder().decode(RecStoreData.self, from: data) else {
            signals = []
            recomputeAffinities()
            recomputeTasteVector()
            return
        }
        signals = store.signals
        recomputeAffinities()
        recomputeTasteVector()
    }

    private func persist() {
        let store = RecStoreData(signals: signals, version: storeVersion)
        guard let data = try? JSONEncoder().encode(store) else { return }
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Recording

    /// Records a signal, updates the derived profile, and persists. The semantic
    /// embedding is computed off the main thread and backfilled when ready.
    func record(book: Book, action: SignalAction) {
        let signal = InteractionSignal(book: book, action: action, timestamp: Date())
        signals.append(signal)

        seenBookIds.insert(book.id)
        if action == .dislike {
            dislikedBookIds.insert(book.id)
        }

        recomputeAffinities()
        persist()

        // Backfill the embedding (used for semantic taste), then re-persist.
        let signalId = signal.id
        let text = book.embeddingText
        let bookId = book.id
        Task { [weak self] in
            guard let vector = await EmbeddingService.shared.embed(id: bookId, text: text) else { return }
            guard let self = self else { return }
            guard let index = self.signals.firstIndex(where: { $0.id == signalId }) else { return }
            self.signals[index].embedding = vector
            self.recomputeTasteVector()
            self.persist()
        }
    }

    // MARK: - Taste profile

    private func weight(for action: SignalAction) -> Double {
        switch action {
        case .like: return likeWeight
        case .dislike: return dislikeWeight
        case .skip: return skipWeight
        }
    }

    /// Rebuilds category/author affinity maps from the full signal log, applying
    /// a gentle recency decay, then normalizing so the strongest signal is ~±1.
    private func recomputeAffinities() {
        // Rebuild the fast-lookup sets too (covers the load-from-disk path).
        seenBookIds = Set(signals.map { $0.googleBooksId })
        dislikedBookIds = Set(signals.filter { $0.action == .dislike }.map { $0.googleBooksId })

        let now = Date()
        var rawCat: [String: Double] = [:]
        var rawAuth: [String: Double] = [:]

        for signal in signals {
            let ageDays = now.timeIntervalSince(signal.timestamp) / 86_400
            let decay = pow(0.5, ageDays / halfLifeDays)
            let value = weight(for: signal.action) * decay

            for category in signal.categories {
                rawCat[category, default: 0] += value
            }
            for author in signal.authors {
                rawAuth[author, default: 0] += value
            }
        }

        categoryAffinity = normalize(rawCat)
        authorAffinity = normalize(rawAuth)
    }

    private func normalize(_ raw: [String: Double]) -> [String: Double] {
        let maxAbs = max(1.0, raw.values.map { abs($0) }.max() ?? 1.0)
        return raw.mapValues { $0 / maxAbs }
    }

    // MARK: - Scoring & ranking

    /// Content-based score for a candidate book. Higher = better fit.
    func score(_ book: Book) -> Double {
        // Average category affinity (so multi-tagged books don't dominate).
        let categoryScore: Double
        if book.categories.isEmpty {
            categoryScore = 0
        } else {
            let sum = book.categories.reduce(0.0) { $0 + (categoryAffinity[$1] ?? 0) }
            categoryScore = sum / Double(book.categories.count)
        }

        // Max author affinity (one loved author counts fully).
        let authorScore = book.authors.map { authorAffinity[$0] ?? 0 }.max() ?? 0

        let ratingNorm = (book.averageRating ?? 3.5) / 5.0

        return 1.00 * categoryScore
             + 0.80 * authorScore
             + 0.20 * ratingNorm
             + 0.15 * Double.random(in: 0...1)   // exploration jitter / tie-break
    }

    /// Content-based ranking (genre/author). Fallback when embeddings are absent.
    func rank(_ candidates: [Book]) -> [Book] {
        candidates
            .filter { !seenBookIds.contains($0.id) && !dislikedBookIds.contains($0.id) }
            .sorted { score($0) > score($1) }
    }

    /// Semantic ranking: embeds each candidate and sorts by cosine similarity to the
    /// user's taste vector (blended with rating). Falls back to `rank` when the taste
    /// vector or embeddings aren't available yet.
    func rankBySimilarity(_ candidates: [Book]) async -> [Book] {
        let pool = candidates.filter { !seenBookIds.contains($0.id) && !dislikedBookIds.contains($0.id) }

        guard let taste = tasteVector else {
            return rank(pool)   // no semantic profile yet
        }

        var scored: [(book: Book, score: Double)] = []
        var anyEmbedded = false
        for book in pool {
            let vector = await EmbeddingService.shared.embed(id: book.id, text: book.embeddingText)
            let similarity: Double
            if let vector = vector {
                similarity = EmbeddingService.cosine(vector, taste)
                anyEmbedded = true
            } else {
                similarity = 0
            }
            let ratingNorm = (book.averageRating ?? 3.5) / 5.0
            let value = 0.85 * similarity
                      + 0.15 * ratingNorm
                      + 0.05 * Double.random(in: 0...1)
            scored.append((book, value))
        }

        // If nothing could be embedded (model unavailable), use content ranking.
        guard anyEmbedded else { return rank(pool) }

        return scored.sorted { $0.score > $1.score }.map { $0.book }
    }

    /// Rebuilds the semantic taste vector from stored like/dislike embeddings.
    private func recomputeTasteVector() {
        let liked = signals.filter { $0.action == .like }.compactMap { $0.embedding }
        guard !liked.isEmpty else { tasteVector = nil; return }

        var vector = EmbeddingService.mean(of: liked)

        let disliked = signals.filter { $0.action == .dislike }.compactMap { $0.embedding }
        if !disliked.isEmpty {
            let dislikedMean = EmbeddingService.mean(of: disliked)
            let n = min(vector.count, dislikedMean.count)
            for i in 0..<n { vector[i] -= 0.5 * dislikedMean[i] }
        }

        tasteVector = EmbeddingService.normalize(vector)
    }

    // MARK: - Profile queries

    func hasSignals() -> Bool {
        !signals.isEmpty
    }

    /// The user's most-liked categories (positive affinity only), strongest first.
    func topPositiveCategories(limit: Int) -> [String] {
        categoryAffinity
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }

    /// Affinity weight for a category (0 if unknown) — used for weighted subject picks.
    func affinity(for category: String) -> Double {
        categoryAffinity[category] ?? 0
    }

    // MARK: - Future Supabase sync (stubs)

    func unsyncedSignals() -> [InteractionSignal] {
        signals.filter { !$0.syncedToServer }
    }

    func markSynced(ids: Set<UUID>) {
        for index in signals.indices where ids.contains(signals[index].id) {
            signals[index].syncedToServer = true
        }
        persist()
    }
}
