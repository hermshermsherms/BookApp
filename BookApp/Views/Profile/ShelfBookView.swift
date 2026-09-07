import SwiftUI

/// A single cover on the profile's read shelf: the jacket, its star rating, and
/// a marker when there's a written review behind it.
struct ShelfCoverView: View {
    let item: ProfileViewModel.ShelfItem

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: URL(string: item.book?.thumbnailURL ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Rectangle()
                            .fill(Theme.parchment)
                            .overlay(
                                Text(item.title)
                                    .font(Theme.serifBold(11))
                                    .foregroundColor(Theme.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(4)
                                    .padding(6)
                            )
                    }
                }
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipped()
                .cornerRadius(Theme.cornerRadiusSmall)
                .shadow(color: Theme.espresso.opacity(0.18), radius: 4, x: 0, y: 3)

                if item.review?.hasText == true {
                    Image(systemName: "text.quote")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Theme.cardBackground)
                        .padding(5)
                        .background(Circle().fill(Theme.accent))
                        .padding(5)
                }
            }

            if item.rating > 0 {
                StarRatingView(rating: item.rating, size: 10, spacing: 1)
            } else {
                Text("Unrated")
                    .font(Theme.caption(10))
                    .foregroundColor(Theme.muted.opacity(0.7))
            }
        }
    }
}

/// The read-only view of a shelf entry — what a visitor to the profile sees.
struct ShelfBookDetailView: View {
    let item: ProfileViewModel.ShelfItem
    let readerName: String

    @Environment(\.dismiss) private var dismiss
    @State private var showEditReview = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.paddingLarge) {
                    AsyncImage(url: URL(string: item.book?.largeCoverURL ?? item.book?.thumbnailURL ?? "")) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        default:
                            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                                .fill(Theme.parchment)
                        }
                    }
                    .frame(height: 220)
                    .cornerRadius(Theme.cornerRadiusSmall)
                    .shadow(color: Theme.espresso.opacity(0.2), radius: 8, x: 0, y: 5)
                    .padding(.top, Theme.paddingLarge)

                    VStack(spacing: 6) {
                        Text(item.title)
                            .font(Theme.serifBold(22))
                            .foregroundColor(Theme.primaryText)
                            .multilineTextAlignment(.center)

                        Text(item.book?.authorDisplay ?? "Unknown Author")
                            .font(Theme.body(15))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .padding(.horizontal)

                    if let review = item.review {
                        reviewCard(review)
                    } else {
                        unratedCard
                    }

                    Spacer(minLength: 40)
                }
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(item.review == nil ? "Rate" : "Edit") {
                        showEditReview = true
                    }
                    .foregroundColor(Theme.accent)
                }
            }
            .sheet(isPresented: $showEditReview) {
                ReviewView(userBook: item.userBook)
            }
        }
    }

    // MARK: - Cards

    private func reviewCard(_ review: Review) -> some View {
        VStack(alignment: .leading, spacing: Theme.paddingMedium) {
            VStack(alignment: .leading, spacing: 8) {
                StarRatingView(rating: review.rating, size: 20, spacing: 4)

                Text(review.ratingLabel)
                    .font(Theme.body(15))
                    .foregroundColor(Theme.accent)
            }

            if review.hasText, let text = review.reviewText {
                Divider()

                Text(text)
                    .font(Theme.body(15))
                    .foregroundColor(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("\(readerName) reviewed this \(review.updatedAt.relativeString)")
                .font(Theme.caption(12))
                .foregroundColor(Theme.muted)
        }
        .padding(Theme.paddingMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .cornerRadius(Theme.cornerRadiusMedium)
        .padding(.horizontal)
    }

    private var unratedCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "star")
                .font(.system(size: 28))
                .foregroundColor(Theme.muted.opacity(0.5))

            Text("No rating yet")
                .font(Theme.body(15))
                .foregroundColor(Theme.secondaryText)

            Button("Rate & Review") {
                showEditReview = true
            }
            .font(Theme.body(15).bold())
            .foregroundColor(Theme.accent)
        }
        .padding(Theme.paddingLarge)
        .frame(maxWidth: .infinity)
        .background(Theme.cardBackground)
        .cornerRadius(Theme.cornerRadiusMedium)
        .padding(.horizontal)
    }
}
