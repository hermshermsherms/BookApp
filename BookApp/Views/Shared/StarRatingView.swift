import SwiftUI
import UIKit

/// Read-only star row. Used anywhere a saved rating is displayed.
struct StarRatingView: View {
    let rating: Int
    var size: CGFloat = 13
    var spacing: CGFloat = 2

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundColor(star <= rating ? .yellow : Theme.muted.opacity(0.35))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rating) out of 5 stars")
    }
}

/// Interactive star picker. Tap a star, or drag across the row, to set a rating.
/// Each new value gives a light haptic tick so rating a book feels physical.
struct StarRatingPicker: View {
    @Binding var rating: Int
    var size: CGFloat = 36
    var spacing: CGFloat = 12

    /// Horizontal distance from the leading edge of one star to the next.
    private var stride: CGFloat { size + spacing }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundColor(star <= rating ? .yellow : Theme.muted.opacity(0.4))
                    .frame(width: size, height: size)
                    .scaleEffect(star == rating ? 1.18 : 1.0)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // `location` is a CGPoint, so `.x` is right here. Note that
                    // `translation` is a CGSize — that one needs .width/.height.
                    setRating(atX: value.location.x)
                }
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: rating)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue("\(rating) out of 5 stars")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(rating + 1, 5)
            case .decrement: rating = max(rating - 1, 1)
            @unknown default: break
            }
        }
    }

    private func setRating(atX x: CGFloat) {
        let star = min(max(Int(x / stride) + 1, 1), 5)
        guard star != rating else { return }
        rating = star
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
