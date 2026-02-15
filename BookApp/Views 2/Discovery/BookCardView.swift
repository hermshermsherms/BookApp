import SwiftUI

struct BookCardView: View {
    let book: Book

    private var highResImageURL: URL? {
        // Prioritize large cover URL, fallback to thumbnail
        if let largeCoverURL = book.largeCoverURL {
            return URL(string: largeCoverURL)
        } else if let thumbnailURL = book.thumbnailURL {
            return URL(string: thumbnailURL)
        }
        return nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background — book cover with high-res upfront loading
            AsyncImage(url: highResImageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                        .clipped()
                case .failure:
                    fallbackCover()
                case .empty:
                    ZStack {
                        Color.black
                        ProgressView()
                            .tint(Theme.accent)
                    }
                    .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                @unknown default:
                    fallbackCover()
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
                HStack {
                    Text(book.genreDisplay.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(4)
                    Spacer()
                }

                // Title
                Text(book.title)
                    .font(Theme.serifBold(28))
                    .foregroundColor(.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Author
                Text(book.authorDisplay)
                    .font(Theme.body(16))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

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
                    Spacer()
                }

                // Hook / description snippet
                if !book.hook.isEmpty {
                    Text(book.hook)
                        .font(Theme.body(14))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, max(Theme.paddingLarge, 20)) // Ensure minimum padding
            .padding(.bottom, 120) // Static padding for tab bar + safe area
        }
        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        .clipped() // Ensure no content bleeds outside bounds
        .background(Color.black) // Solid black background
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func fallbackCover() -> some View {
        ZStack {
            Color.black
            VStack(spacing: 12) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.white.opacity(0.6))
                Text(book.title)
                    .font(Theme.serifBold(20))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
    }
}
