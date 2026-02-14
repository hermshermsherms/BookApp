import SwiftUI

struct DiscoveryFeedView: View {
    @StateObject private var viewModel = DiscoveryViewModel()
    @State private var dragOffset: CGSize = .zero
    @State private var cardOpacity: Double = 1.0
    @State private var dragDirection: DragDirection = .none

    private let swipeThreshold: CGFloat = 100
    private let directionThreshold: CGFloat = 30 // Threshold to lock into a direction
    
    enum DragDirection {
        case none, vertical, horizontal
    }

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            if viewModel.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(Theme.accent)
                        .scaleEffect(1.5)
                    Text("Finding books for you...")
                        .font(Theme.body())
                        .foregroundColor(Theme.secondaryText)
                }
            } else if let book = viewModel.currentBook {
                GeometryReader { geometry in
                    ZStack {
                        // Previous book preview (above, visible when swiping down)
                        if let previousBook = viewModel.previousBook {
                            BookCardView(book: previousBook)
                                .id("previous-\(previousBook.id)")
                                .offset(y: dragDirection == .vertical && dragOffset.height > 0 ? 
                                       dragOffset.height - geometry.size.height : -geometry.size.height)
                                .opacity(dragDirection == .vertical && dragOffset.height > 0 ? 
                                        min(1.0, dragOffset.height / 150) : 0)
                                .allowsHitTesting(false) // Prevent interaction with preview
                        }
                        
                        // Next book preview (slides up from bottom as you swipe up)
                        if let nextBook = viewModel.nextBook {
                            BookCardView(book: nextBook)
                                .id("next-\(nextBook.id)")
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .offset(y: dragDirection == .vertical && dragOffset.height < 0 ? 
                                       geometry.size.height + dragOffset.height : geometry.size.height)
                                .opacity(dragDirection == .vertical && dragOffset.height < 0 ? 
                                        min(1.0, abs(dragOffset.height) / 200) : 0)
                                .allowsHitTesting(false) // Prevent interaction with preview
                        }
                    
                        // Current book card with gesture handling
                        BookCardView(book: book)
                            .id(book.id) // Force view recreation when book changes
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .offset(y: dragOffset.height)
                            .opacity(cardOpacity)
                            .onTapGesture(count: 2) {
                                viewModel.doubleTap()
                            }
                            .onTapGesture(count: 1) {
                                viewModel.singleTap()
                            }
                            .gesture(dragGesture)
                    }
                }
                
                // Pre-load next book image (hidden)
                if let nextBook = viewModel.nextBook {
                    AsyncImage(url: URL(string: nextBook.largeCoverURL ?? nextBook.thumbnailURL ?? "")) { _ in
                        EmptyView()
                    }
                    .frame(width: 0, height: 0)
                    .opacity(0)
                }

                // Like animation overlay
                if viewModel.likeAnimationTrigger {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 8)
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(10)
                }

                // Swipe direction indicators
                swipeIndicators

            } else if let error = viewModel.error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.muted)
                    Text(error)
                        .font(Theme.body())
                        .foregroundColor(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        Task { await viewModel.loadFeed() }
                    }
                    .primaryButtonStyle()
                }
                .padding()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.muted)
                    Text("No more books right now")
                        .font(Theme.serifTitle(20))
                        .foregroundColor(Theme.primaryText)
                    Text("Check back later for new recommendations")
                        .font(Theme.body(14))
                        .foregroundColor(Theme.secondaryText)
                    Button("Refresh") {
                        Task { await viewModel.loadFeed() }
                    }
                    .primaryButtonStyle()
                }
            }
        }
        .sheet(isPresented: $viewModel.showDetailView) {
            if let book = viewModel.currentBook {
                BookDetailView(book: book, onLike: {
                    viewModel.doubleTap()
                    viewModel.showDetailView = false
                }, onBuy: {
                    // Open purchase sheet from detail view
                    viewModel.showDetailView = false
                    // Could add purchase functionality here if needed
                }, onDislike: {
                    // Close detail view - no action needed
                    viewModel.showDetailView = false
                })
            }
        }
        .task {
            await viewModel.loadFeed()
        }
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let translation = value.translation
                
                // Only allow vertical movement for feed-like behavior
                if abs(translation.height) > abs(translation.width) {
                    // This is primarily a vertical swipe
                    dragOffset = CGSize(width: 0, height: translation.height)
                    dragDirection = .vertical
                    // Fade card as it's dragged further
                    let distance = abs(translation.height)
                    cardOpacity = max(0.6, 1.0 - (distance / 400))
                } else {
                    // Ignore horizontal movement - no left/right swipes
                    dragOffset = .zero
                    dragDirection = .none
                }
            }
            .onEnded { value in
                let vertical = value.translation.height

                if vertical < -swipeThreshold {
                    // Swipe up — next (immediate transition)
                    viewModel.swipeUp()
                    resetCard()
                } else if vertical > swipeThreshold {
                    // Swipe down — previous (immediate transition)  
                    viewModel.swipeDown()
                    resetCard()
                } else {
                    // Snap back
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragOffset = .zero
                        cardOpacity = 1.0
                    }
                }
            }
    }

    private func resetCard() {
        dragOffset = .zero
        cardOpacity = 1.0
        dragDirection = .none
    }

    // MARK: - Swipe Indicators

    @ViewBuilder  
    private var swipeIndicators: some View {
        // No swipe indicators needed - clean interface
        EmptyView()
    }
}
