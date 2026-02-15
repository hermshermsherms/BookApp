import SwiftUI

struct HighQualityBookImageView: View {
    let book: Book
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat = 0
    
    @State private var currentImageState: ImageState = .loading
    @State private var imageTask: Task<Void, Never>?
    
    enum ImageState {
        case loading
        case highRes(Image)
        case lowRes(Image)
        case stylized
    }
    
    var body: some View {
        Group {
            switch currentImageState {
            case .loading:
                loadingView
            case .highRes(let image), .lowRes(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .cornerRadius(cornerRadius)
                    .clipped()
            case .stylized:
                stylizedFallback
            }
        }
        .frame(width: width, height: height)
        .onAppear {
            loadImage()
        }
        .onDisappear {
            imageTask?.cancel()
        }
        .id(book.id + (book.largeCoverURL ?? book.thumbnailURL ?? ""))
    }
    
    private var loadingView: some View {
        ZStack {
            Color.black.opacity(0.1)
            ProgressView()
                .tint(Theme.accent)
                .scaleEffect(0.8)
        }
        .frame(width: width, height: height)
        .cornerRadius(cornerRadius)
    }
    
    private var stylizedFallback: some View {
        ZStack {
            // Genre-based gradient background
            genreGradient
            
            VStack(spacing: 12) {
                // Genre icon
                Image(systemName: genreIcon)
                    .font(.system(size: min(width, height) * 0.15))
                    .foregroundColor(.white)
                
                // Title
                Text(book.title)
                    .font(Theme.serifBold(min(width * 0.08, 18)))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 8)
                
                // Author
                Text(book.authorDisplay)
                    .font(Theme.body(min(width * 0.06, 14)))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
            }
        }
        .frame(width: width, height: height)
        .cornerRadius(cornerRadius)
    }
    
    private var genreGradient: some View {
        let colors = genreColors
        return LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var genreColors: [Color] {
        let genre = book.genreDisplay.lowercased()
        switch genre {
        case let g where g.contains("fiction"):
            return [Color.blue.opacity(0.8), Color.purple.opacity(0.8)]
        case let g where g.contains("romance"):
            return [Color.pink.opacity(0.8), Color.red.opacity(0.8)]
        case let g where g.contains("mystery") || g.contains("thriller"):
            return [Color.black, Color.gray.opacity(0.8)]
        case let g where g.contains("science"):
            return [Color.cyan.opacity(0.8), Color.blue.opacity(0.8)]
        case let g where g.contains("fantasy"):
            return [Color.purple.opacity(0.8), Color.indigo.opacity(0.8)]
        case let g where g.contains("biography") || g.contains("history"):
            return [Color.brown.opacity(0.8), Color.orange.opacity(0.8)]
        case let g where g.contains("self") || g.contains("help"):
            return [Color.green.opacity(0.8), Color.mint.opacity(0.8)]
        default:
            return [Theme.accent.opacity(0.6), Theme.accent.opacity(0.4)]
        }
    }
    
    private var genreIcon: String {
        let genre = book.genreDisplay.lowercased()
        switch genre {
        case let g where g.contains("fiction"):
            return "book.fill"
        case let g where g.contains("romance"):
            return "heart.fill"
        case let g where g.contains("mystery") || g.contains("thriller"):
            return "magnifyingglass"
        case let g where g.contains("science"):
            return "atom"
        case let g where g.contains("fantasy"):
            return "sparkles"
        case let g where g.contains("biography") || g.contains("history"):
            return "person.fill"
        case let g where g.contains("self") || g.contains("help"):
            return "lightbulb.fill"
        default:
            return "book.closed.fill"
        }
    }
    
    private func loadImage() {
        imageTask?.cancel()
        imageTask = Task {
            // Try high-res first
            if let highResURL = book.largeCoverURL,
               let url = URL(string: highResURL),
               !Task.isCancelled {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let uiImage = UIImage(data: data), !Task.isCancelled {
                        await MainActor.run {
                            currentImageState = .highRes(Image(uiImage: uiImage))
                        }
                        return
                    }
                } catch {
                    // High-res failed, try low-res
                }
            }
            
            // Try thumbnail/low-res
            if let thumbnailURL = book.thumbnailURL,
               let url = URL(string: thumbnailURL),
               !Task.isCancelled {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let uiImage = UIImage(data: data), !Task.isCancelled {
                        await MainActor.run {
                            currentImageState = .lowRes(Image(uiImage: uiImage))
                        }
                        return
                    }
                } catch {
                    // Low-res also failed
                }
            }
            
            // Both failed, show stylized fallback
            if !Task.isCancelled {
                await MainActor.run {
                    currentImageState = .stylized
                }
            }
        }
    }
}