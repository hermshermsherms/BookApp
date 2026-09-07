import SwiftUI
import UIKit

/// Read-only star row, in half-star resolution. Used anywhere a saved rating is
/// displayed.
struct StarRatingView: View {
    let rating: Double
    var size: CGFloat = 13
    var spacing: CGFloat = 2

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: StarRatingView.symbol(for: star, rating: rating))
                    .font(.system(size: size))
                    .foregroundColor(rating >= Double(star) - Review.step ? .yellow : Theme.muted.opacity(0.35))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Review.display(rating)) out of 5 stars")
    }

    /// Full, half, or empty star for the given position.
    static func symbol(for star: Int, rating: Double) -> String {
        if rating >= Double(star) {
            return "star.fill"
        }
        if rating >= Double(star) - Review.step {
            return "star.leadinghalf.filled"
        }
        return "star"
    }
}

/// Interactive star picker in half-star steps. Tap a star's left or right half,
/// or drag across the row. Each new value gives a light haptic tick so rating a
/// book feels physical.
struct StarRatingPicker: View {
    @Binding var rating: Double
    var size: CGFloat = 36
    var spacing: CGFloat = 12

    /// Horizontal distance from the leading edge of one star to the next.
    private var stride: CGFloat { size + spacing }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: StarRatingView.symbol(for: star, rating: rating))
                    .font(.system(size: size))
                    .foregroundColor(rating >= Double(star) - Review.step ? .yellow : Theme.muted.opacity(0.4))
                    .frame(width: size, height: size)
                    .scaleEffect(isNewest(star) ? 1.18 : 1.0)
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
        .accessibilityValue("\(Review.display(rating)) out of 5 stars")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(rating + Review.step, 5)
            case .decrement: rating = max(rating - Review.step, Review.step)
            @unknown default: break
            }
        }
    }

    /// The star the rating currently lands on, which gets the pop of scale.
    private func isNewest(_ star: Int) -> Bool {
        rating > Double(star) - 1 && rating <= Double(star)
    }

    private func setRating(atX x: CGFloat) {
        // Round up so the half a finger is over is the half that fills.
        let raw = (Double(x / stride) / Review.step).rounded(.up) * Review.step
        let stepped = min(max(raw, Review.step), 5)
        guard stepped != rating else { return }
        rating = stepped
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
