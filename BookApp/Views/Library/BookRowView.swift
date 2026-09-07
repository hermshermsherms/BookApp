import SwiftUI

struct BookRowView: View {
    let userBook: UserBook
    let onStatusChange: (BookStatus) -> Void
    let onDelete: () -> Void
    let onReview: () -> Void

    @ObservedObject private var reviewStore = ReviewStore.shared
    @State private var showStatusPicker = false

    private var review: Review? {
        reviewStore.review(forGoogleBooksId: userBook.googleBooksId)
    }

    var body: some View {
        HStack(spacing: Theme.paddingMedium) {
            // Cover thumbnail
            AsyncImage(url: URL(string: userBook.book?.thumbnailURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 55, height: 82)
                        .cornerRadius(Theme.cornerRadiusSmall)
                case .failure, .empty:
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                        .fill(Theme.parchment)
                        .frame(width: 55, height: 82)
                        .overlay(
                            Image(systemName: "book.closed")
                                .font(.system(size: 18))
                                .foregroundColor(Theme.muted)
                        )
                @unknown default:
                    EmptyView()
                }
            }

            // Book info
            VStack(alignment: .leading, spacing: 4) {
                Text(userBook.book?.title ?? "Unknown Title")
                    .font(Theme.serifBold(16))
                    .foregroundColor(Theme.primaryText)
                    .lineLimit(2)

                Text(userBook.book?.authorDisplay ?? "Unknown Author")
                    .font(Theme.caption(13))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)

                // Finished books show their rating (or an invite to add one);
                // everything else shows its shelf status.
                if userBook.status == .read {
                    ratingFooter
                } else {
                    statusBadge
                }
            }

            Spacer()

            // Status change button
            Button {
                showStatusPicker = true
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 22))
                    .foregroundColor(Theme.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, Theme.paddingMedium)
        .background(Theme.cardBackground)
        .cornerRadius(Theme.cornerRadiusMedium)
        .confirmationDialog("Change Status", isPresented: $showStatusPicker) {
            if userBook.status == .read {
                Button(review == nil ? "Rate & Review" : "Edit Review") {
                    onReview()
                }
            }
            ForEach(BookStatus.allCases, id: \.self) { status in
                if status != userBook.status {
                    Button(status.displayName) {
                        onStatusChange(status)
                    }
                }
            }
            Button("Remove from Library", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Footers

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: userBook.status.iconName)
                .font(.system(size: 11))
            Text(userBook.status.displayName)
                .font(Theme.caption(11))
        }
        .foregroundColor(Theme.accent)
        .padding(.top, 2)
    }

    @ViewBuilder
    private var ratingFooter: some View {
        if let review = review {
            Button(action: onReview) {
                HStack(spacing: 6) {
                    StarRatingView(rating: review.rating, size: 12)

                    if review.hasText {
                        Image(systemName: "text.quote")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.muted)
                    }
                }
                .padding(.top, 2)
            }
            .buttonStyle(.plain)
        } else {
            Button(action: onReview) {
                HStack(spacing: 4) {
                    Image(systemName: "star")
                        .font(.system(size: 11))
                    Text("Rate it")
                        .font(Theme.caption(11))
                }
                .foregroundColor(Theme.accent)
                .padding(.top, 2)
            }
            .buttonStyle(.plain)
        }
    }
}
