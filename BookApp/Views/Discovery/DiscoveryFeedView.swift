import SwiftUI

struct DiscoveryFeedView: View {
    @StateObject private var viewModel = DiscoveryViewModel()
    @State private var currentPage: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    
    // Constants for better maintainability
    private static let swipeThreshold: CGFloat = 80
    private static let screenWidth = UIScreen.main.bounds.width
    private static let screenHeight = UIScreen.main.bounds.height

    var body: some View {
        ZStack {
            Color.black
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
                    ForEach(Array(viewModel.books.enumerated()), id: \.element.id) { index, book in
                        BookCardView(book: book)
                            .frame(width: Self.screenWidth, height: Self.screenHeight)
                            .background(Color.black)
                            .clipped()
                            .offset(y: calculateOffset(for: index))
                            .opacity(calculateOpacity(for: index))
                            .scaleEffect(calculateScale(for: index))
                            .onTapGesture(count: 2) {
                                viewModel.doubleTap()
                            }
                            .onTapGesture(count: 1) {
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
                            isDragging = true
                            // Update drag offset to follow finger
                            dragOffset = value.translation.height
                        }
                        .onEnded { value in
                            let verticalMovement = value.translation.height
                            var targetPage = currentPage
                            
                            if verticalMovement < -Self.swipeThreshold && currentPage < viewModel.books.count - 1 {
                                // Swipe up - go to next book
                                targetPage = currentPage + 1
                            } else if verticalMovement > Self.swipeThreshold && currentPage > 0 {
                                // Swipe down - go to previous book
                                targetPage = currentPage - 1
                            }
                            
                            if targetPage != currentPage {
                                // Page change - animate to new position
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    currentPage = targetPage
                                    dragOffset = 0
                                }
                                viewModel.updateCurrentIndex(targetPage)
                            } else {
                                // No page change - snap back to original position
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                    dragOffset = 0
                                }
                            }
                            
                            // Reset dragging state after animation starts
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isDragging = false
                            }
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
                
                // Pre-load next book image (hidden)
                if let nextBook = viewModel.nextBook,
                   let imageURL = nextBook.highQualityImageURL {
                    AsyncImage(url: imageURL) { _ in
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
                    viewModel.doubleTap()
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

    // MARK: - Helper Methods for Fluid Swipe Animation
    
    private func calculateOffset(for index: Int) -> CGFloat {
        let currentOffset = CGFloat(index - currentPage) * Self.screenHeight
        
        if isDragging {
            // During drag, apply the drag offset only to the current and adjacent cards
            if index == currentPage {
                return currentOffset + dragOffset
            } else if index == currentPage + 1 || index == currentPage - 1 {
                return currentOffset + dragOffset
            }
        }
        
        return currentOffset
    }
    
    private func calculateOpacity(for index: Int) -> Double {
        let distance = abs(index - currentPage)
        
        if distance > 2 {
            return 0.0
        } else if distance > 1 {
            return 0.3
        }
        
        return 1.0
    }
    
    private func calculateScale(for index: Int) -> CGFloat {
        let distance = abs(index - currentPage)
        
        if distance > 2 {
            return 0.8
        } else if distance > 1 {
            return 0.9
        }
        
        return 1.0
    }
}
