import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @State private var selectedTab: BookStatus = .wantToRead
    @State private var showSearch = false
    @State private var showReview: UserBook?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Status tab picker
                Picker("Status", selection: $selectedTab) {
                    ForEach(BookStatus.allCases, id: \.self) { status in
                        Text(status.displayName).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, Theme.paddingSmall)

                // Book list
                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                        .tint(Theme.accent)
                    Spacer()
                } else {
                    let books = booksForTab(selectedTab)

                    if books.isEmpty {
                        Spacer()
                        emptyState(for: selectedTab)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(books) { userBook in
                                    BookRowView(
                                        userBook: userBook,
                                        onStatusChange: { newStatus in
                                            Task { await viewModel.updateStatus(userBook: userBook, newStatus: newStatus) }
                                        },
                                        onDelete: {
                                            Task { await viewModel.deleteBook(userBook) }
                                        }
                                    )
                                    .onTapGesture {
                                        if userBook.status == .read {
                                            showReview = userBook
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, Theme.paddingSmall)
                        }
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 20))
                            .foregroundColor(Theme.accent)
                    }
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            BookSearchView(viewModel: viewModel)
        }
        .sheet(item: $showReview) { userBook in
            ReviewView(userBook: userBook)
        }
        .task {
            await viewModel.fetchLibrary()
        }
        .refreshable {
            await viewModel.fetchLibrary()
        }
    }

    // MARK: - Helpers

    private func booksForTab(_ status: BookStatus) -> [UserBook] {
        switch status {
        case .wantToRead: return viewModel.wantToReadBooks
        case .reading: return viewModel.readingBooks
        case .read: return viewModel.readBooks
        }
    }

    @ViewBuilder
    private func emptyState(for status: BookStatus) -> some View {
        VStack(spacing: 12) {
            Image(systemName: status.iconName)
                .font(.system(size: 40))
                .foregroundColor(Theme.muted.opacity(0.5))

            Text(emptyMessage(for: status))
                .font(Theme.body(15))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)

            if status == .wantToRead {
                Text("Discover books and save them here")
                    .font(Theme.caption())
                    .foregroundColor(Theme.muted)
            }
        }
        .padding()
    }

    private func emptyMessage(for status: BookStatus) -> String {
        switch status {
        case .wantToRead: return "No books on your reading list yet"
        case .reading: return "You're not reading anything right now"
        case .read: return "No books finished yet"
        }
    }
}
