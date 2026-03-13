import SwiftUI

struct BookCardView: View {
    let book: Book

    private var highResImageURL: URL? {
        book.highQualityImageURL
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Theme.background
                    .ignoresSafeArea()
                
                // Card container
                VStack(spacing: 24) {
                    Spacer()
                    
                    // Book cover - realistic book shape with 3D effect
                    ZStack {
                        // Book spine shadow (back)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.3))
                            .frame(width: 200, height: 320)
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
                            .frame(width: 200, height: 320)
                            .offset(x: 4, y: 4)
                        
                        // Main book cover
                        ZStack {
                            // Book background
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Theme.cardBackground)
                                .shadow(color: Color.black.opacity(0.2), radius: 15, x: -3, y: 5)
                            
                            // Cover image
                            AsyncImage(url: highResImageURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 190, height: 300)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                case .failure:
                                    fallbackCoverBook()
                                case .empty:
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Theme.parchment)
                                            .frame(width: 190, height: 300)
                                        ProgressView()
                                            .tint(Theme.accent)
                                            .scaleEffect(1.2)
                                    }
                                @unknown default:
                                    fallbackCoverBook()
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
                            .frame(width: 190, height: 300)
                        }
                        .frame(width: 200, height: 320)
                    }
                    
                    // Book info below cover
                    VStack(spacing: 16) {
                        // Genre tag
                        Text(book.genreDisplay.uppercased())
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.accent.opacity(0.1))
                            .cornerRadius(6)
                        
                        // Title and Author
                        VStack(spacing: 8) {
                            Text(book.title)
                                .font(Theme.serifBold(24))
                                .foregroundColor(Theme.primaryText)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            
                            Text(book.authorDisplay)
                                .font(Theme.body(16))
                                .foregroundColor(Theme.secondaryText)
                        }
                        
                        // Rating + Page count row
                        HStack(spacing: 24) {
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
                        }
                        
                        // Hook / description
                        if !book.hook.isEmpty {
                            Text(book.hook)
                                .font(Theme.body(15))
                                .foregroundColor(Theme.secondaryText)
                                .lineLimit(3)
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
    private func fallbackCoverBook() -> some View {
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
                .frame(width: 190, height: 300)
            
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
