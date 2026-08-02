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

    let onBrowseSimilar: (Book, Book, [Book]) -> Void
    let onReadEPUB: (Book, BookReadingResource) -> Void

    private static let swipeThreshold: CGFloat = 80

    init(
        seedBooks: [Book] = [],
        onBrowseSimilar: @escaping (Book, Book, [Book]) -> Void,
        onReadEPUB: @escaping (Book, BookReadingResource) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: DiscoveryViewModel(seedBooks: seedBooks))
        self.onBrowseSimilar = onBrowseSimilar
        self.onReadEPUB = onReadEPUB
    }

    private var feedBooks: [Book] {
        var seen = Set<String>()
        return viewModel.books.filter { seen.insert($0.id).inserted }
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

            ForEach(Array(feedBooks.enumerated()), id: \.element.id) { index, book in
                BookCardView(
                    book: book,
                    catalog: feedBooks,
                    isCurrent: index == clampedPage,
                    onSave: { viewModel.likeCurrent() },
                    onBuy: { viewModel.buyBook() },
                    onSkip: { advanceBySkipping() },
                    onBrowseSimilar: { selected, catalog in
                        onBrowseSimilar(book, selected, catalog)
                    },
                    onReadEPUB: { resource in
                        onReadEPUB(book, resource)
                    }
                )
                .frame(width: pageWidth, height: size.height)
                .clipped()
                .offset(y: calculateOffset(for: index, pageHeight: size.height))
                .opacity(calculateOpacity(for: index))
            }

            feedbackOverlay
        }
        .frame(width: pageWidth, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(pagingGesture)
        .onChange(of: viewModel.currentIndex) { newIndex in
            guard newIndex != currentPage else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                currentPage = newIndex
            }
        }
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
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                let height = value.translation.height
                if abs(height) > abs(value.translation.width) {
                    isDragging = true
                    dragOffset = height
                }
            }
            .onEnded { value in
                if abs(value.translation.height) > abs(value.translation.width) {
                    handleVerticalEnd(height: value.translation.height)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        dragOffset = 0
                    }
                    isDragging = false
                }
            }
    }

    private func handleVerticalEnd(height: CGFloat) {
        var target = currentPage
        if height < -Self.swipeThreshold, currentPage < feedBooks.count - 1 {
            target += 1
        } else if height > Self.swipeThreshold, currentPage > 0 {
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

    private func calculateOffset(for index: Int, pageHeight: CGFloat) -> CGFloat {
        let currentOffset = CGFloat(index - clampedPage) * pageHeight
        guard isDragging, abs(index - clampedPage) <= 1 else { return currentOffset }
        return currentOffset + dragOffset
    }

    private func calculateOpacity(for index: Int) -> Double {
        abs(index - clampedPage) > 1 ? 0 : 1
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

private struct CoverBackdropView: View {
    let currentURL: URL?
    let transitionURL: URL?
    let transitionProgress: CGFloat

    var body: some View {
        ZStack {
            backdropImage(url: currentURL)
                .opacity(1 - transitionProgress)

            if let transitionURL {
                backdropImage(url: transitionURL)
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
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.linear(duration: 0.12), value: transitionProgress)
    }

    private func backdropImage(url: URL?) -> some View {
        CachedAsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .empty, .failure:
                Color.black
            }
        }
        .scaleEffect(1.18)
        .blur(radius: 34, opaque: true)
        .clipped()
    }
}
