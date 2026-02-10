import SwiftUI

struct BookDetailView: View {
    let book: Book
    let onLike: () -> Void
    let onBuy: () -> Void
    let onDislike: () -> Void

    @State private var similarBooks: [Book] = []
    @State private var isLoadingSimilar = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.paddingLarge) {
                    // Cover image
                    HStack {
                        Spacer()
                        AsyncImage(url: URL(string: book.largeCoverURL ?? book.thumbnailURL ?? "")) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 350)
                                    .cornerRadius(Theme.cornerRadiusMedium)
                                    .shadow(color: Theme.espresso.opacity(0.2), radius: 12, y: 8)
                            case .failure, .empty:
                                RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                                    .fill(Theme.parchment)
                                    .frame(width: 200, height: 300)
                                    .overlay(
                                        Image(systemName: "book.closed.fill")
                                            .font(.system(size: 40))
                                            .foregroundColor(Theme.muted)
                                    )
                            @unknown default:
                                EmptyView()
                            }
                        }
                        Spacer()
                    }
                    .padding(.top, Theme.paddingMedium)

                    // Title + Author
                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.title)
                            .font(Theme.serifBold(26))
                            .foregroundColor(Theme.primaryText)

                        Text(book.authorDisplay)
                            .font(Theme.body(17))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .padding(.horizontal)

                    // Metadata pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            if book.averageRating != nil {
                                metadataPill(icon: "star.fill", text: book.ratingDisplay, color: .yellow)
                            }
                            if book.pageCount != nil {
                                metadataPill(icon: "book.pages", text: book.pageCountDisplay, color: Theme.muted)
                            }
                            if let date = book.publishedDate {
                                metadataPill(icon: "calendar", text: date, color: Theme.muted)
                            }
                            if !book.categories.isEmpty {
                                ForEach(book.categories, id: \.self) { category in
                                    metadataPill(icon: "tag", text: category, color: Theme.accent)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Synopsis
                    if let description = book.description {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Synopsis")
                                .font(Theme.serifBold(18))
                                .foregroundColor(Theme.primaryText)

                            Text(description)
                                .font(Theme.body(15))
                                .foregroundColor(Theme.secondaryText)
                                .lineSpacing(4)
                        }
                        .padding(.horizontal)
                    }

                    // Similar Books
                    if !similarBooks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("You Might Also Like")
                                .font(Theme.serifBold(18))
                                .foregroundColor(Theme.primaryText)
                                .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(similarBooks) { similarBook in
                                        VStack(spacing: 6) {
                                            AsyncImage(url: URL(string: similarBook.thumbnailURL ?? "")) { phase in
                                                switch phase {
                                                case .success(let image):
                                                    image
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 90, height: 135)
                                                        .cornerRadius(Theme.cornerRadiusSmall)
                                                case .failure, .empty:
                                                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                                                        .fill(Theme.parchment)
                                                        .frame(width: 90, height: 135)
                                                @unknown default:
                                                    EmptyView()
                                                }
                                            }
                                            Text(similarBook.title)
                                                .font(Theme.caption(11))
                                                .foregroundColor(Theme.primaryText)
                                                .lineLimit(2)
                                                .frame(width: 90)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    } else if isLoadingSimilar {
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(Theme.accent)
                            Spacer()
                        }
                    }

                    // Action Buttons
                    HStack(spacing: 16) {
                        Button(action: onDislike) {
                            VStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 28))
                                Text("Skip")
                                    .font(Theme.caption(12))
                            }
                            .foregroundColor(Theme.negative)
                            .frame(maxWidth: .infinity)
                        }

                        Button(action: onLike) {
                            VStack(spacing: 4) {
                                Image(systemName: "heart.circle.fill")
                                    .font(.system(size: 28))
                                Text("Save")
                                    .font(Theme.caption(12))
                            }
                            .foregroundColor(Theme.accent)
                            .frame(maxWidth: .infinity)
                        }

                        Button(action: onBuy) {
                            VStack(spacing: 4) {
                                Image(systemName: "cart.circle.fill")
                                    .font(.system(size: 28))
                                Text("Buy")
                                    .font(Theme.caption(12))
                            }
                            .foregroundColor(Theme.positive)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, Theme.paddingLarge)
                    .padding(.vertical, Theme.paddingMedium)
                    .background(Theme.cardBackground)
                    .cornerRadius(Theme.cornerRadiusMedium)
                    .padding(.horizontal)

                    Spacer(minLength: 40)
                }
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
            }
        }
        .task {
            await loadSimilarBooks()
        }
    }

    // MARK: - Metadata Pill

    @ViewBuilder
    private func metadataPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(text)
                .font(Theme.caption(12))
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.parchment)
        .cornerRadius(Theme.cornerRadiusSmall)
    }

    // MARK: - Load Similar

    private func loadSimilarBooks() async {
        isLoadingSimilar = true
        do {
            similarBooks = try await GoogleBooksService.shared.fetchSimilarBooks(to: book)
        } catch {
            // Silently fail — similar books are optional
        }
        isLoadingSimilar = false
    }
}
