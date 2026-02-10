import SwiftUI

struct DiscoveryFeedView: View {
    @StateObject private var viewModel = DiscoveryViewModel()
    @State private var dragOffset: CGSize = .zero
    @State private var cardOpacity: Double = 1.0

    private let swipeThreshold: CGFloat = 100

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
                // Book card with gesture handling
                BookCardView(book: book)
                    .offset(x: dragOffset.width, y: dragOffset.height)
                    .rotationEffect(.degrees(Double(dragOffset.width) / 20))
                    .opacity(cardOpacity)
                    .gesture(dragGesture)
                    .onTapGesture(count: 2) {
                        viewModel.doubleTap()
                    }
                    .onTapGesture(count: 1) {
                        viewModel.singleTap()
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: dragOffset)

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
        .sheet(isPresented: $viewModel.showPurchaseSheet) {
            if let book = viewModel.currentBook {
                PurchaseSheetView(book: book) {
                    viewModel.dismissPurchaseSheet()
                }
                .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $viewModel.showDetailView) {
            if let book = viewModel.currentBook {
                BookDetailView(book: book, onLike: {
                    viewModel.doubleTap()
                    viewModel.showDetailView = false
                }, onBuy: {
                    viewModel.showDetailView = false
                    viewModel.swipeRight()
                }, onDislike: {
                    viewModel.swipeLeft()
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
                dragOffset = value.translation
                // Fade card as it's dragged further
                let distance = abs(value.translation.width) + abs(value.translation.height)
                cardOpacity = max(0.5, 1.0 - (distance / 500))
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height

                if horizontal < -swipeThreshold {
                    // Swipe left — dislike
                    withAnimation(.easeOut(duration: 0.3)) {
                        dragOffset = CGSize(width: -500, height: 0)
                        cardOpacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        resetCard()
                        viewModel.swipeLeft()
                    }
                } else if horizontal > swipeThreshold {
                    // Swipe right — buy
                    withAnimation(.easeOut(duration: 0.3)) {
                        dragOffset = CGSize(width: 500, height: 0)
                        cardOpacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        resetCard()
                        viewModel.swipeRight()
                    }
                } else if vertical < -swipeThreshold {
                    // Swipe up — next
                    withAnimation(.easeOut(duration: 0.3)) {
                        dragOffset = CGSize(width: 0, height: -600)
                        cardOpacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        resetCard()
                        viewModel.swipeUp()
                    }
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
    }

    // MARK: - Swipe Indicators

    @ViewBuilder
    private var swipeIndicators: some View {
        // Left indicator (dislike)
        if dragOffset.width < -30 {
            HStack {
                Spacer()
                VStack {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Theme.negative)
                    Text("SKIP")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.negative)
                }
                .padding(.trailing, 40)
                .opacity(min(1, abs(dragOffset.width) / swipeThreshold))
                Spacer().frame(width: 40)
            }
        }

        // Right indicator (buy)
        if dragOffset.width > 30 {
            HStack {
                Spacer().frame(width: 40)
                VStack {
                    Image(systemName: "cart.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Theme.positive)
                    Text("BUY")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.positive)
                }
                .padding(.leading, 40)
                Spacer()
            }
        }
    }
}
