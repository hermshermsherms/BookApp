import SwiftUI
import UIKit

/// Process-wide in-memory cache of decoded cover images, shared by every view
/// that shows a book cover (feed card, detail sheet, similar books). This means a
/// cover downloads/decodes once and is instant on every subsequent appearance —
/// including when you tap a card open, or scroll back to a book you already saw.
final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 300
        cache.totalCostLimit = 120 * 1024 * 1024 // ~120 MB
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL, cost: image.approximateCost)
    }
}

private extension UIImage {
    /// Rough decoded byte size, used to weight the NSCache eviction cost.
    var approximateCost: Int {
        guard let cg = cgImage else { return 1 }
        return cg.bytesPerRow * cg.height
    }
}

/// The load state of a `CachedAsyncImage`, mirroring `AsyncImage.Phase` so call
/// sites read almost identically.
enum CachedImagePhase {
    case empty
    case success(Image)
    case failure
}

/// A drop-in replacement for `AsyncImage` that caches decoded images in
/// `ImageCache` and decodes off the main thread to keep scrolling smooth.
struct CachedAsyncImage<Content: View>: View {
    private let url: URL?
    private let content: (CachedImagePhase) -> Content

    @State private var phase: CachedImagePhase

    init(url: URL?, @ViewBuilder content: @escaping (CachedImagePhase) -> Content) {
        self.url = url
        self.content = content
        // Start already-resolved on a cache hit so there's no placeholder flash
        // (this is what makes a tapped-open cover appear instantly).
        if let url = url, let cached = ImageCache.shared.image(for: url) {
            _phase = State(initialValue: .success(Image(uiImage: cached)))
        } else {
            _phase = State(initialValue: .empty)
        }
    }

    var body: some View {
        content(phase)
            .task(id: url) { await load() }
    }

    private func load() async {
        guard let url = url else {
            phase = .failure
            return
        }

        // Cache hit — already handled in init, but re-check in case the view was
        // reused for a new URL that is now cached.
        if let cached = ImageCache.shared.image(for: url) {
            phase = .success(Image(uiImage: cached))
            return
        }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let raw = UIImage(data: data) else {
                if !Task.isCancelled { phase = .failure }
                return
            }
            // Decode off the main thread so setting the image doesn't hitch scrolling.
            let prepared = await raw.byPreparingForDisplay() ?? raw
            ImageCache.shared.insert(prepared, for: url)
            if !Task.isCancelled {
                phase = .success(Image(uiImage: prepared))
            }
        } catch {
            if !Task.isCancelled {
                phase = .failure
            }
        }
    }
}
