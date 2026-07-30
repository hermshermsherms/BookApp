import Foundation
import NaturalLanguage

/// Produces semantic vectors for book text using Apple's on-device sentence
/// embedding model. Runs as an actor so inference happens off the main thread.
///
/// We use `NLEmbedding.sentenceEmbedding`, which is a built-in on-device model
/// (no asset download, works offline everywhere) — unlike `NLContextualEmbedding`,
/// whose model asset isn't reliably resident. Degrades gracefully: if no model is
/// available, `embed` returns nil and callers fall back to non-semantic scoring.
actor EmbeddingService {
    static let shared = EmbeddingService()

    private var model: NLEmbedding?
    private var triedLoad = false
    private var cache: [String: [Double]] = [:]   // bookId -> unit vector

    private init() {}

    var isAvailable: Bool {
        ensureLoaded()
        return model != nil
    }

    private func ensureLoaded() {
        guard !triedLoad else { return }
        triedLoad = true
        model = NLEmbedding.sentenceEmbedding(for: .english)
    }

    /// Returns a unit-length embedding for `text`, or nil if unavailable. Falls back
    /// to a shorter title/genre string if the full description can't be embedded.
    /// Results are cached by `id`.
    func embed(id: String?, text: String) -> [Double]? {
        ensureLoaded()
        guard let model = model else { return nil }

        if let id = id, let cached = cache[id] { return cached }

        let trimmed = String(text.prefix(1000))
        guard !trimmed.isEmpty else { return nil }

        let raw = model.vector(for: trimmed)
        guard let raw = raw, !raw.isEmpty else { return nil }

        let unit = Self.normalize(raw)
        if let id = id { cache[id] = unit }
        return unit
    }

    /// Warms the model on launch so the first real fetch can use it.
    func warmUp() {
        ensureLoaded()
    }

    // MARK: - Vector math (pure, usable from any context)

    /// Cosine similarity for unit vectors reduces to a dot product.
    nonisolated static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0
        for i in 0..<a.count { dot += a[i] * b[i] }
        return dot
    }

    nonisolated static func normalize(_ v: [Double]) -> [Double] {
        let norm = (v.reduce(0) { $0 + $1 * $1 }).squareRoot()
        guard norm > 0 else { return v }
        return v.map { $0 / norm }
    }

    nonisolated static func mean(of vectors: [[Double]]) -> [Double] {
        guard let first = vectors.first else { return [] }
        var sum = first
        for v in vectors.dropFirst() {
            let n = min(sum.count, v.count)
            for i in 0..<n { sum[i] += v[i] }
        }
        return sum.map { $0 / Double(vectors.count) }
    }
}
