import SwiftUI

struct BookCardView: View {
    let book: Book

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background — book cover
                AsyncImage(url: URL(string: book.largeCoverURL ?? book.thumbnailURL ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    case .failure:
                        fallbackCover(size: geometry.size)
                    case .empty:
                        ZStack {
                            Theme.parchment
                            ProgressView()
                                .tint(Theme.accent)
                        }
                    @unknown default:
                        fallbackCover(size: geometry.size)
                    }
                }

                // Gradient overlay at bottom for text readability
                LinearGradient(
                    gradient: Gradient(colors: [
                        .clear,
                        Color.black.opacity(0.3),
                        Color.black.opacity(0.7),
                        Color.black.opacity(0.85),
                    ]),
                    startPoint: .center,
                    endPoint: .bottom
                )

                // Book info overlay
                VStack(alignment: .leading, spacing: 8) {
                    // Genre tag
                    Text(book.genreDisplay.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(4)

                    // Title
                    Text(book.title)
                        .font(Theme.serifBold(28))
                        .foregroundColor(.white)
                        .lineLimit(3)

                    // Author
                    Text(book.authorDisplay)
                        .font(Theme.body(16))
                        .foregroundColor(.white.opacity(0.85))

                    // Rating + Page count row
                    HStack(spacing: 16) {
                        if book.averageRating != nil {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(.yellow)
                                Text(book.ratingDisplay)
                                    .font(Theme.body(14).bold())
                                    .foregroundColor(.white)
                            }
                        }

                        if book.pageCount != nil {
                            HStack(spacing: 4) {
                                Image(systemName: "book.pages")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.7))
                                Text(book.pageCountDisplay)
                                    .font(Theme.caption(13))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }

                    // Hook / description snippet
                    if !book.hook.isEmpty {
                        Text(book.hook)
                            .font(Theme.body(14))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(3)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, Theme.paddingLarge)
                .padding(.bottom, 100) // Space for tab bar + gesture area
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func fallbackCover(size: CGSize) -> some View {
        ZStack {
            Theme.parchment
            VStack(spacing: 12) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 48))
                    .foregroundColor(Theme.muted)
                Text(book.title)
                    .font(Theme.serifBold(20))
                    .foregroundColor(Theme.primaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
