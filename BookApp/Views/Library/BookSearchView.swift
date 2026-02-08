import SwiftUI

struct BookSearchView: View {
    @ObservedObject var viewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Theme.muted)

                    TextField("Search by title or author", text: $viewModel.searchQuery)
                        .font(Theme.body(16))
                        .foregroundColor(Theme.primaryText)
                        .autocorrectionDisabled()
                        .onSubmit {
                            Task { await viewModel.searchBooks() }
                        }

                    if !viewModel.searchQuery.isEmpty {
                        Button {
                            viewModel.searchQuery = ""
                            viewModel.searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Theme.muted)
                        }
                    }
                }
                .padding()
                .background(Theme.parchment)
                .cornerRadius(Theme.cornerRadiusMedium)
                .padding()

                // Results
                if viewModel.isSearching {
                    Spacer()
                    ProgressView()
                        .tint(Theme.accent)
                    Spacer()
                } else if viewModel.searchResults.isEmpty && !viewModel.searchQuery.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundColor(Theme.muted)
                        Text("No books found")
                            .font(Theme.body())
                            .foregroundColor(Theme.secondaryText)
                        Text("Try a different title or author name")
                            .font(Theme.caption())
                            .foregroundColor(Theme.muted)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(viewModel.searchResults) { book in
                                searchResultRow(book: book)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Add a Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
            }
        }
    }

    @ViewBuilder
    private func searchResultRow(book: Book) -> some View {
        HStack(spacing: Theme.paddingMedium) {
            AsyncImage(url: URL(string: book.thumbnailURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 75)
                        .cornerRadius(4)
                case .failure, .empty:
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.parchment)
                        .frame(width: 50, height: 75)
                @unknown default:
                    EmptyView()
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(Theme.serifBold(15))
                    .foregroundColor(Theme.primaryText)
                    .lineLimit(2)

                Text(book.authorDisplay)
                    .font(Theme.caption(13))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)

                if let rating = book.averageRating {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f", rating))
                            .font(Theme.caption(11))
                            .foregroundColor(Theme.muted)
                    }
                }
            }

            Spacer()

            // Add button with status picker
            Menu {
                ForEach(BookStatus.allCases, id: \.self) { status in
                    Button {
                        Task { await viewModel.addBookToLibrary(book: book, status: status) }
                    } label: {
                        Label(status.displayName, systemImage: status.iconName)
                    }
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Theme.accent)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, Theme.paddingMedium)
        .background(Theme.cardBackground)
        .cornerRadius(Theme.cornerRadiusMedium)
    }
}
