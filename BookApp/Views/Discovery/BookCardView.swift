import SwiftUI

struct BookCardView: View {
    let book: Book

    private var highResImageURL: URL? {
        book.highQualityImageURL
    }

    var body: some View {
        GeometryReader { geometry in
            // Size the cover relative to the screen so it fills more of the card
            // and adapts across devices (was a fixed 200×320).
            let coverWidth = min(geometry.size.width * 0.66, 300)
            let coverHeight = coverWidth * 1.6
            let imageWidth = coverWidth - 10
            let imageHeight = coverHeight - 20

            ZStack {
                // Background
                Theme.background
                    .ignoresSafeArea()
                
                // Card container
                VStack(spacing: 24) {
                    // Small top gap (rather than a full flexible Spacer) so the whole
                    // card sits higher on screen.
                    Spacer().frame(maxHeight: 70)

                    // Book cover - realistic book shape with 3D effect
                    ZStack {
                        // Book spine shadow (back)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.3))
                            .frame(width: coverWidth, height: coverHeight)
                            .offset(x: 8, y: 8)

                        // Book spine (side edge)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.black.opacity(0.6),
                                    Color.black.opacity(0.3)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: coverWidth, height: coverHeight)
                            .offset(x: 4, y: 4)

                        // Main book cover
                        ZStack {
                            // Book background
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Theme.cardBackground)
                                .shadow(color: Color.black.opacity(0.2), radius: 15, x: -3, y: 5)

                            // Cover image
                            CachedAsyncImage(url: highResImageURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: imageWidth, height: imageHeight)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                case .failure:
                                    fallbackCoverBook(width: imageWidth, height: imageHeight)
                                case .empty:
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Theme.parchment)
                                            .frame(width: imageWidth, height: imageHeight)
                                        ProgressView()
                                            .tint(Theme.accent)
                                            .scaleEffect(1.2)
                                    }
                                }
                            }

                            // Subtle book cover shine effect
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.2),
                                    Color.clear,
                                    Color.clear
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .frame(width: imageWidth, height: imageHeight)
                        }
                        .frame(width: coverWidth, height: coverHeight)
                    }
                    
                    // Book info below cover
                    VStack(spacing: 16) {
                        // Title and Author
                        VStack(spacing: 8) {
                            Text(book.title)
                                .font(Theme.serifBold(28))
                                .foregroundColor(Theme.primaryText)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)

                            Text(book.authorDisplay)
                                .font(Theme.body(17))
                                .foregroundColor(Theme.secondaryText)
                        }

                        // Rating + Page count + Category row
                        HStack(spacing: 20) {
                            if book.averageRating != nil {
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.yellow)
                                    Text(book.ratingDisplay)
                                        .font(Theme.body(15).bold())
                                        .foregroundColor(Theme.primaryText)
                                }
                            }

                            if book.pageCount != nil {
                                HStack(spacing: 4) {
                                    Image(systemName: "book.pages")
                                        .font(.system(size: 14))
                                        .foregroundColor(Theme.muted)
                                    Text(book.pageCountDisplay)
                                        .font(Theme.caption(14))
                                        .foregroundColor(Theme.muted)
                                }
                            }

                            HStack(spacing: 4) {
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.accent)
                                Text(book.genreDisplay.uppercased())
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Theme.accent)
                                    .lineLimit(1)
                            }
                        }

                        // Hook / description
                        if let description = book.description, !description.isEmpty {
                            Text(description)
                                .font(Theme.body(15))
                                .foregroundColor(Theme.secondaryText)
                                .lineLimit(4)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, Theme.paddingLarge)
                    
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func fallbackCoverBook(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        Theme.parchment,
                        Theme.parchment.opacity(0.8)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: width, height: height)
            
            VStack(spacing: 16) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 40))
                    .foregroundColor(Theme.muted)
                    .padding(.top, 20)
                
                Spacer()
                
                VStack(spacing: 8) {
                    Text(book.title)
                        .font(Theme.serifBold(14))
                        .foregroundColor(Theme.primaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal, 12)
                    
                    Text(book.authorDisplay)
                        .font(Theme.body(11))
                        .foregroundColor(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 12)
                }
                
                Spacer()
            }
        }
    }
}