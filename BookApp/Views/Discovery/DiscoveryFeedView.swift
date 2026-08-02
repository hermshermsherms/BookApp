import Combine
import SwiftUI

private enum DiscoveryRoute: Hashable {
    case similar(sourceTitle: String, selectedBook: Book, catalog: [Book])
    case reader(book: Book, resource: BookReadingResource)
}

struct DiscoveryFeedView: View {
    @State private var path: [DiscoveryRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            DiscoveryPagerView(
                onBrowseSimilar: pushSimilarFeed,
                onReadEPUB: pushReader
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: DiscoveryRoute.self) { route in
                switch route {
                case .similar(let sourceTitle, _, let catalog):
                    DiscoveryPagerView(
                        seedBooks: catalog,
                        onBrowseSimilar: pushSimilarFeed,
                        onReadEPUB: pushReader
                    )
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(.visible, for: .navigationBar)
                    .toolbarBackground(.hidden, for: .navigationBar)
                    .toolbarColorScheme(.dark, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text("Similar to \(sourceTitle)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.62)
                                .shadow(color: .black.opacity(0.95), radius: 5, y: 2)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }

                case .reader(let book, let resource):
                    EPUBReaderView(book: book, resource: resource)
                }
            }
        }
    }

    private func pushSimilarFeed(source: Book, selected: Book, catalog: [Book]) {
        path.append(.similar(sourceTitle: source.title, selectedBook: selected, catalog: catalog))
    }

    private func pushReader(book: Book, resource: BookReadingResource) {
        path.append(.reader(book: book, resource: resource))
    }
}

private struct DiscoveryPagerView: View {
    @StateObject private var viewModel: DiscoveryViewModel
    @State private var currentPage = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    /// De-duplicated snapshot of `viewModel.books`. Recomputing the filter inside
    /// `body` meant walking the whole feed and building a `Set` on every frame of
    /// every swipe; the feed only changes when the view model publishes.
    @State private var feedBooks: [Book] = []

    let onBrowseSimilar: (Book, Book, [Book]) -> Void
    let onReadEPUB: (Book, BookReadingResource) -> Void

    private static let swipeThreshold: CGFloat = 80
    /// A fast flick can cross well under `swipeThreshold` before the finger lifts.
    /// Pagination also honours the projected end point so flicks page immediately
    /// instead of springing back.
    private static let flickThreshold: CGFloat = 190

    init(
        seedBooks: [Book] = [],
        onBrowseSimilar: @escaping (Book, Book, [Book]) -> Void,
        onReadEPUB: @escaping (Book, BookReadingResource) -> Void
    ) {
        var seen = Set<String>()
        let unique = seedBooks.filter { seen.insert($0.id).inserted }
        _viewModel = StateObject(wrappedValue: DiscoveryViewModel(seedBooks: unique))
        // Seeded up front so a similar-books feed renders its first card
        // immediately rather than flashing the empty state for a frame while the
        // view model's first publish lands.
        _feedBooks = State(initialValue: unique)
        self.onBrowseSimilar = onBrowseSimilar
        self.onReadEPUB = onReadEPUB
    }

    private var clampedPage: Int {
        guard !feedBooks.isEmpty else { return 0 }
        return min(max(currentPage, 0), feedBooks.count - 1)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if viewModel.isLoading {
                    loadingView
                } else if !feedBooks.isEmpty {
                    feed(in: geometry.size)
                } else if let error = viewModel.error {
                    errorView(error)
                } else {
                    emptyView
                }
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $viewModel.showPurchaseSheet) {
            if let book = viewModel.currentBook {
                PurchaseSheetView(book: book) {
                    viewModel.showPurchaseSheet = false
                }
                .presentationDetents([.height(400), .medium])
                .presentationDragIndicator(.visible)
            }
        }
        .onReceive(viewModel.$books) { books in
            var seen = Set<String>()
            feedBooks = books.filter { seen.insert($0.id).inserted }
        }
        .task {
            await viewModel.loadFeedIfNeeded()
            currentPage = viewModel.currentIndex
        }
    }

    private func feed(in size: CGSize) -> some View {
        let pageWidth = UIScreen.main.bounds.width

        return ZStack {
            CoverBackdropView(
                currentURL: feedBooks[clampedPage].highQualityImageURL,
                transitionURL: transitionBook?.highQualityImageURL,
                transitionProgress: min(abs(dragOffset) / max(size.height * 0.72, 1), 1)
            )
            .frame(width: pageWidth, height: size.height)
            .clipped()

            // `.equatable()` keeps the card bodies from being re-evaluated on every
            // frame of a drag: the cards only depend on which page is current, and
            // the live drag translation is applied as a plain offset on top.
            FeedCardStack(
                books: feedBooks,
                currentPage: clampedPage,
                pageWidth: pageWidth,
                pageHeight: size.height,
                onSave: { viewModel.likeCurrent() },
                onBuy: { viewModel.buyBook() },
                onSkip: { advanceBySkipping() },
                onBrowseSimilar: onBrowseSimilar,
                onReadEPUB: onReadEPUB
            )
            .equatable()
            .offset(y: dragOffset)

            feedbackOverlay
        }
        .frame(width: pageWidth, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(pagingGesture)
        .task(id: clampedPage) {
            await BackdropImageCache.prewarm(neighbourBackdropURLs)
        }
        .onChange(of: viewModel.currentIndex) { newIndex in
            guard newIndex != currentPage else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                currentPage = newIndex
            }
        }
    }

    private var neighbourBackdropURLs: [URL] {
        [clampedPage - 1, clampedPage + 1]
            .filter { $0 >= 0 && $0 < feedBooks.count }
            .compactMap { feedBooks[$0].highQualityImageURL }
    }

    private var transitionBook: Book? {
        guard isDragging else { return nil }
        if dragOffset < 0, clampedPage < feedBooks.count - 1 {
            return feedBooks[clampedPage + 1]
        }
        if dragOffset > 0, clampedPage > 0 {
            return feedBooks[clampedPage - 1]
        }
        return nil
    }

    private var pagingGesture: some Gesture {
        // A short activation distance keeps the card glued to the finger. The 3D
        // cover's own pan recogniser now stands down for vertical drags, so this
        // no longer has to out-wait it.
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let height = value.translation.height
                if abs(height) > abs(value.translation.width) {
                    isDragging = true
                    dragOffset = height
                }
            }
            .onEnded { value in
                if abs(value.translation.height) > abs(value.translation.width) {
                    handleVerticalEnd(value)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        dragOffset = 0
                    }
                    isDragging = false
                }
            }
    }

    private func handleVerticalEnd(_ value: DragGesture.Value) {
        let height = value.translation.height
        let projected = value.predictedEndTranslation.height
        // The projected sign is the release velocity's direction, so a drag that
        // is flicked back the way it came still springs home instead of paging.
        let wantsNext = (height < -Self.swipeThreshold && projected <= 0) || projected < -Self.flickThreshold
        let wantsPrevious = (height > Self.swipeThreshold && projected >= 0) || projected > Self.flickThreshold

        var target = currentPage
        if wantsNext, currentPage < feedBooks.count - 1 {
            target += 1
        } else if wantsPrevious, currentPage > 0 {
            target -= 1
        }

        if target != currentPage {
            let movingForward = target > currentPage
            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                currentPage = target
                dragOffset = 0
            }
            if movingForward { viewModel.skipCurrent() }
            viewModel.updateCurrentIndex(target)
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                dragOffset = 0
            }
        }
        isDragging = false
    }

    private func advanceBySkipping() {
        guard currentPage < feedBooks.count - 1 else { return }
        let target = currentPage + 1
        viewModel.skipCurrent()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            currentPage = target
        }
        viewModel.updateCurrentIndex(target)
    }

    @ViewBuilder
    private var feedbackOverlay: some View {
        if viewModel.likeAnimationTrigger {
            Image(systemName: "heart.fill")
                .font(.system(size: 72))
                .foregroundColor(Theme.positive)
                .shadow(color: .black.opacity(0.2), radius: 8)
                .transition(.scale.combined(with: .opacity))
                .allowsHitTesting(false)
                .zIndex(12)
        } else if viewModel.dislikeAnimationTrigger {
            Image(systemName: "xmark")
                .font(.system(size: 76, weight: .bold))
                .foregroundColor(Theme.negative)
                .shadow(color: .black.opacity(0.2), radius: 8)
                .allowsHitTesting(false)
                .zIndex(12)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().tint(Theme.accent).scaleEffect(1.4)
            Text("Finding books for you…")
                .font(Theme.body())
                .foregroundColor(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(Theme.muted)
            Text(error)
                .font(Theme.body())
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Try Again") { Task { await viewModel.loadFeed() } }
                .primaryButtonStyle()
        }
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 40))
                .foregroundColor(Theme.muted)
            Text("No more books right now")
                .font(Theme.serifTitle(20))
                .foregroundColor(Theme.primaryText)
            Button("Refresh") { Task { await viewModel.loadFeed() } }
                .primaryButtonStyle()
        }
    }
}

/// The page window rendered at any one time.
///
/// Every card hosts a live SceneKit renderer for the 3D cover. The feed grows to
/// 30+ books, and materialising a card per book meant 30 simultaneous SCNViews
/// all running their own 60fps render loop — which is what made fast swipes
/// stutter while slow ones tracked fine. Keeping one page behind and two ahead
/// caps that at four, and pre-warms the next renderer off-screen so paging into
/// it never hitches.
private struct FeedCardStack: View, Equatable {
    let books: [Book]
    let currentPage: Int
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let onSave: () -> Void
    let onBuy: () -> Void
    let onSkip: () -> Void
    let onBrowseSimilar: (Book, Book, [Book]) -> Void
    let onReadEPUB: (Book, BookReadingResource) -> Void

    private static let pagesBehind = 1
    private static let pagesAhead = 2

    /// Identified by book id, not by index, so a card keeps its state (loaded
    /// cover, similar books, expanded synopsis) as the window slides over it.
    private struct Page: Identifiable {
        let index: Int
        let book: Book
        var id: String { book.id }
    }

    private var window: [Page] {
        guard !books.isEmpty else { return [] }
        let lower = max(0, currentPage - Self.pagesBehind)
        let upper = min(books.count - 1, currentPage + Self.pagesAhead)
        guard lower <= upper else { return [] }
        return (lower...upper).map { Page(index: $0, book: books[$0]) }
    }

    var body: some View {
        ZStack {
            ForEach(window) { entry in
                let distance = abs(entry.index - currentPage)
                BookCardView(
                    book: entry.book,
                    catalog: books,
                    isCurrent: entry.index == currentPage,
                    // Only the page you can actually see keeps its renderer alive.
                    isRendering: distance <= 1,
                    onSave: onSave,
                    onBuy: onBuy,
                    onSkip: onSkip,
                    onBrowseSimilar: { selected, catalog in
                        onBrowseSimilar(entry.book, selected, catalog)
                    },
                    onReadEPUB: { resource in
                        onReadEPUB(entry.book, resource)
                    }
                )
                .frame(width: pageWidth, height: pageHeight)
                .clipped()
                .offset(y: CGFloat(entry.index - currentPage) * pageHeight)
                .opacity(distance <= 1 ? 1 : 0)
                // Cards entering/leaving the window must not fade — they'd flash
                // through the card that is paging into view.
                .transition(.identity)
            }
        }
        .frame(width: pageWidth, height: pageHeight)
    }

    /// The closures are deliberately excluded: they capture only stable
    /// references (the view model and the navigation callbacks), and comparing
    /// them is impossible. The feed itself is append-only, so count plus the
    /// first/last ids identify it.
    static func == (lhs: FeedCardStack, rhs: FeedCardStack) -> Bool {
        lhs.currentPage == rhs.currentPage
            && lhs.pageWidth == rhs.pageWidth
            && lhs.pageHeight == rhs.pageHeight
            && lhs.books.count == rhs.books.count
            && lhs.books.first?.id == rhs.books.first?.id
            && lhs.books.last?.id == rhs.books.last?.id
    }
}

private struct CoverBackdropView: View {
    let currentURL: URL?
    let transitionURL: URL?
    let transitionProgress: CGFloat

    var body: some View {
        ZStack {
            Color.black

            BackdropLayer(url: currentURL)

            // The incoming backdrop fades in *over* the current one rather than
            // cross-fading with it. A cross-fade dips through the black base
            // whenever the incoming layer hasn't decoded yet, which read as the
            // background dropping out mid-swipe.
            if let transitionURL {
                BackdropLayer(url: transitionURL)
                    .opacity(transitionProgress)
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.58),
                    Color.black.opacity(0.42),
                    Color.black.opacity(0.68)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }
}

/// A single full-bleed backdrop image. The blur is baked into the cached bitmap
/// by `BackdropImageCache`, so this is a plain scaled image with no filter,
/// no offscreen pass, and nothing to re-render while paging.
private struct BackdropLayer: View {
    let url: URL?

    @State private var image: UIImage?

    init(url: URL?) {
        self.url = url
        // Resolve synchronously on a cache hit so a prewarmed backdrop is on
        // screen from the first frame instead of fading up out of the black base.
        _image = State(initialValue: url.flatMap { BackdropImageCache.cached(for: $0) })
    }

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .task(id: url) {
                guard let url else {
                    image = nil
                    return
                }
                if let cached = BackdropImageCache.cached(for: url) {
                    image = cached
                    return
                }
                let loaded = await BackdropImageCache.backdrop(for: url)
                if !Task.isCancelled { image = loaded }
            }
    }
}
