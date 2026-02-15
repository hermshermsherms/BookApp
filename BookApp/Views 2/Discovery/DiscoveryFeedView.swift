import SwiftUI

struct DiscoveryFeedView: View {
    @StateObject private var viewModel = DiscoveryViewModel()
    @State private var currentPage: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

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
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(viewModel.books.enumerated()), id: \.element.id) { index, book in
                                BookCardView(book: book)
                                    .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                                    .background(Color.black)
                                    .clipped()
                                    .id(index)
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
                    }
                    .scrollDisabled(true) // Disable ScrollView's natural scrolling
                    .ignoresSafeArea(.all)
                    .gesture(
                        DragGesture()
                            .onChanged { _ in
                                isDragging = true
                            }
                            .onEnded { value in
                                isDragging = false
                                
                                let threshold: CGFloat = 50 // Minimum distance to trigger page change
                                let verticalMovement = value.translation.height
                                
                                var targetPage = currentPage
                                
                                if verticalMovement < -threshold && currentPage < viewModel.books.count - 1 {
                                    // Swipe up - go to next book
                                    targetPage = currentPage + 1
                                } else if verticalMovement > threshold && currentPage > 0 {
                                    // Swipe down - go to previous book
                                    targetPage = currentPage - 1
                                }
                                
                                // Only move if target page changed
                                if targetPage != currentPage {
                                    currentPage = targetPage
                                    viewModel.updateCurrentIndex(targetPage)
                                    
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                        proxy.scrollTo(targetPage, anchor: .top)
                                    }
                                }
                            }
                    )
                    .onAppear {
                        currentPage = viewModel.currentIndex
                        DispatchQueue.main.async {
                            proxy.scrollTo(currentPage, anchor: .top)
                        }
                    }
                    .onChange(of: viewModel.currentIndex) { newIndex in
                        if newIndex != currentPage {
                            currentPage = newIndex
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                proxy.scrollTo(newIndex, anchor: .top)
                            }
                        }
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        viewModel.showPurchaseSheet = true
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

}
