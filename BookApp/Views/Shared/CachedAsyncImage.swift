import CoreImage
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

/// Pre-blurred, heavily downscaled covers used as the full-screen feed backdrop.
///
/// The feed used to build its backdrop with `.blur(radius: 34)` applied live to a
/// full-screen cover. That forces a full-screen offscreen GPU pass on *every*
/// frame of a swipe — for two layers at once during a page transition — which
/// both dropped frames and, when the render pass ran out of budget mid-swipe,
/// left large black rectangles across the screen. Blurring once at load time,
/// into a ~96pt image that the GPU simply scales up, removes the pass entirely.
enum BackdropImageCache {
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 60
        return cache
    }()

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Synchronous cache lookup, so an already-prepared backdrop renders on the
    /// very first frame instead of fading in from black.
    static func cached(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    static func backdrop(for url: URL) async -> UIImage? {
        if let hit = cached(for: url) { return hit }

        guard let source = await sourceImage(for: url),
              let prepared = blurred(source) else { return nil }
        cache.setObject(prepared, forKey: url as NSURL)
        return prepared
    }

    /// Warms the backdrops for the neighbouring pages so a swipe never has to
    /// cross-fade into an empty layer.
    static func prewarm(_ urls: [URL]) async {
        for url in urls where cached(for: url) == nil {
            _ = await backdrop(for: url)
        }
    }

    private static func sourceImage(for url: URL) async -> UIImage? {
        if let hit = ImageCache.shared.image(for: url) { return hit }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let raw = UIImage(data: data) else { return nil }
        let prepared = await raw.byPreparingForDisplay() ?? raw
        ImageCache.shared.insert(prepared, for: url)
        return prepared
    }

    /// Downscale first, then blur. Gaussian blur cost scales with pixel count, so
    /// running it on a 96pt-wide image is effectively free, and the upscale back
    /// to screen size softens it further.
    private static func blurred(_ image: UIImage) -> UIImage? {
        let targetWidth: CGFloat = 96
        guard image.size.width > 0, image.size.height > 0 else { return nil }

        let ratio = image.size.height / image.size.width
        let smallSize = CGSize(width: targetWidth, height: max(1, (targetWidth * ratio).rounded()))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let downscaled = UIGraphicsImageRenderer(size: smallSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: smallSize))
        }

        guard let input = CIImage(image: downscaled) else { return downscaled }
        // Clamp before blurring, otherwise the kernel pulls in transparent pixels
        // from outside the extent and the edges wash out to black.
        guard let filter = CIFilter(
            name: "CIGaussianBlur",
            parameters: [kCIInputImageKey: input.clampedToExtent(), kCIInputRadiusKey: 9]
        ), let output = filter.outputImage,
           let rendered = ciContext.createCGImage(output, from: input.extent) else {
            return downscaled
        }
        return UIImage(cgImage: rendered)
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
