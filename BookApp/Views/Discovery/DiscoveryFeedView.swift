import SwiftUI

struct DiscoveryFeedView: View {
    @StateObject private var viewModel = DiscoveryViewModel()
    @State private var currentPage: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var horizontalDrag: CGFloat = 0
    @State private var swipeAxis: Axis? = nil
    @State private var isDragging = false

    // Constants for better maintainability
    private static let swipeThreshold: CGFloat = 80
    private static let screenWidth = UIScreen.main.bounds.width
    private static let screenHeight = UIScreen.main.bounds.height

    /// De-duplicated books for the ForEach — a last line of defense against
    /// duplicate IDs, which make SwiftUI render a blank screen.
    private var feedBooks: [Book] {
        var seen = Set<String>()
        return viewModel.books.filter { seen.insert($0.id).inserted }
    }

    /// currentPage clamped into range, so a card is always visible.
    private var clampedPage: Int {
        guard !feedBooks.isEmpty else { return 0 }
        return min(max(currentPage, 0), feedBooks.count - 1)
    }

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea(.all)

            if viewModel.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(Theme.accent)
                        .scaleEffect(1.5)
                    Text("Finding books for you...")
                        .font(Theme.body())
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else if !viewModel.books.isEmpty {
                // Instagram Reels-style fluid swipe container
                ZStack {
                    ForEach(Array(feedBooks.enumerated()), id: \.element.id) { index, book in
                        BookCardView(book: book)
                            .frame(width: Self.screenWidth, height: Self.screenHeight)
                            .background(Theme.background)
                            .clipped()
                            .offset(y: calculateOffset(for: index))
                            .offset(x: calculateXOffset(for: index))
                            .rotationEffect(.degrees(calculateRotation(for: index)))
                            .opacity(calculateOpacity(for: index))
                            .scaleEffect(calculateScale(for: index))
                            .onTapGesture {
                                viewModel.singleTap()
                            }
                            .onLongPressGesture(minimumDuration: 0.5) {
                                viewModel.buyBook()
                            }
                    }
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let w = value.translation.width
                            let h = value.translation.height
                            // Lock to one axis once the gesture clearly favors a direction,
                            // so horizontal like/dislike and vertical paging never conflict.
                            if swipeAxis == nil, hypot(w, h) > 12 {
                                swipeAxis = abs(w) > abs(h) ? .horizontal : .vertical
                            }
                            switch swipeAxis {
                            case .horizontal:
                                horizontalDrag = w
                            case .vertical:
                                isDragging = true
                                dragOffset = h
                            case .none:
                                break
                            }
                        }
                        .onEnded { value in
                            if swipeAxis == .horizontal {
                                handleHorizontalEnd(width: value.translation.width)
                            } else {
                                handleVerticalEnd(height: value.translation.height)
                            }
                            swipeAxis = nil
                        }
                )
                .ignoresSafeArea(.all)
                .onAppear {
                    currentPage = viewModel.currentIndex
                }
                .onChange(of: viewModel.currentIndex) { newIndex in
                    if newIndex != currentPage {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            currentPage = newIndex
                        }
                    }
                }
                
                // Pre-load next book image into the shared cache (hidden)
                if let nextBook = viewModel.nextBook,
                   let imageURL = nextBook.highQualityImageURL {
                    CachedAsyncImage(url: imageURL) { _ in
                        EmptyView()
                    }
                    .frame(width: 0, height: 0)
                    .opacity(0)
                }

                // Live like/dislike indicator that fades in while swiping horizontally
                if swipeAxis == .horizontal, horizontalDrag != 0 {
                    Image(systemName: horizontalDrag > 0 ? "heart.fill" : "xmark")
                        .font(.system(size: 96, weight: .bold))
                        .foregroundColor(horizontalDrag > 0 ? Theme.positive : Theme.negative)
                        .opacity(min(1.0, abs(horizontalDrag) / Self.swipeThreshold))
                        .zIndex(11)
                }

                // Like animation overlay
                if viewModel.likeAnimationTrigger {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 80))
                        .foregroundColor(Theme.positive)
                        .shadow(color: .black.opacity(0.3), radius: 8)
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(10)
                }

                // Dislike animation overlay
                if viewModel.dislikeAnimationTrigger {
                    Image(systemName: "xmark")
                        .font(.system(size: 80, weight: .bold))
                        .foregroundColor(Theme.negative)
                        .shadow(color: .black.opacity(0.3), radius: 8)
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(10)
                }

            } else if let error = viewModel.error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.6))
                    Text(error)
                        .font(Theme.body())
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        Task { await viewModel.loadFeed() }
                    }
                    .primaryButtonStyle()
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.6))
                    Text("No more books right now")
                        .font(Theme.serifTitle(20))
                        .foregroundColor(.white)
                    Text("Check back later for new recommendations")
                        .font(Theme.body(14))
                        .foregroundColor(.white.opacity(0.7))
                    Button("Refresh") {
                        Task { await viewModel.loadFeed() }
                    }
                    .primaryButtonStyle()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            }
        }
        .sheet(isPresented: $viewModel.showDetailView) {
            if let book = viewModel.currentBook {
                BookDetailView(book: book, onLike: {
                    viewModel.likeCurrent()
                    viewModel.showDetailView = false
                }, onBuy: {
                    // Close detail view and open purchase sheet
                    viewModel.showDetailView = false
                    Task {
                        try? await Task.sleep(nanoseconds: UInt64(0.1 * 1_000_000_000))
                        await MainActor.run {
                            viewModel.showPurchaseSheet = true
                        }
                    }
                }, onDislike: {
                    // Close detail view - no action needed
                    viewModel.showDetailView = false
                })
            }
        }
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
            await viewModel.loadFeed()
        }
    }

    // MARK: - Gesture End Handlers

    private func handleVerticalEnd(height verticalMovement: CGFloat) {
        var targetPage = currentPage

        if verticalMovement < -Self.swipeThreshold && currentPage < feedBooks.count - 1 {
            targetPage = currentPage + 1   // swipe up → next
        } else if verticalMovement > Self.swipeThreshold && currentPage > 0 {
            targetPage = currentPage - 1   // swipe down → previous
        }

        if targetPage != currentPage {
            let movingForward = targetPage > currentPage
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                currentPage = targetPage
                dragOffset = 0
            }
            // Swiping up past a book (without judging) is a mild skip signal.
            if movingForward {
                viewModel.skipCurrent()
            }
            viewModel.updateCurrentIndex(targetPage)
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                dragOffset = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isDragging = false
        }
    }

    private func handleHorizontalEnd(width: CGFloat) {
        guard abs(width) > Self.swipeThreshold else {
            // Not far enough — snap back to center.
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                horizontalDrag = 0
            }
            return
        }
        // Register the judgment (shows the heart/X overlay + advances the feed),
        // and return the card to center as the next book slides up.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            horizontalDrag = 0
        }
        if width > 0 {
            viewModel.swipeLike()
        } else {
            viewModel.swipeDislike()
        }
    }

    // MARK: - Helper Methods for Fluid Swipe Animation

    /// Horizontal follow-the-finger offset, applied only to the current card.
    private func calculateXOffset(for index: Int) -> CGFloat {
        guard swipeAxis == .horizontal, index == currentPage else { return 0 }
        return horizontalDrag
    }

    /// Subtle Tinder-style tilt while dragging the current card sideways.
    private func calculateRotation(for index: Int) -> Double {
        guard swipeAxis == .horizontal, index == currentPage else { return 0 }
        return Double(horizontalDrag / 20)
    }

    private func calculateOffset(for index: Int) -> CGFloat {
        let page = clampedPage
        let currentOffset = CGFloat(index - page) * Self.screenHeight

        if isDragging {
            // During drag, apply the drag offset only to the current and adjacent cards
            if index == page {
                return currentOffset + dragOffset
            } else if index == page + 1 || index == page - 1 {
                return currentOffset + dragOffset
            }
        }

        return currentOffset
    }

    private func calculateOpacity(for index: Int) -> Double {
        let distance = abs(index - clampedPage)
        
        if distance > 2 {
            return 0.0
        } else if distance > 1 {
            return 0.3
        }
        
        return 1.0
    }
    
    private func calculateScale(for index: Int) -> CGFloat {
        let distance = abs(index - clampedPage)
        
        if distance > 2 {
            return 0.8
        } else if distance > 1 {
            return 0.9
        }
        
        return 1.0
    }
}
