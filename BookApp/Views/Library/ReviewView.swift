import SwiftUI
import UIKit

/// Rate a finished book and write a review. Saves to the local `ReviewStore`,
/// the same on-device source of truth the Library uses.
struct ReviewView: View {
    let userBook: UserBook

    @State private var rating: Double = 0
    @State private var reviewText: String = ""
    @State private var existingReview: Review?
    @State private var showDeleteConfirmation = false

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEditorFocused: Bool

    private let reviewStore = ReviewStore.shared

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.paddingLarge) {
                    bookHeader

                    Divider()
                        .padding(.horizontal)

                    ratingSection

                    reviewSection

                    saveSection

                    Spacer(minLength: 40)
                }
            }
            .background(Theme.background)
            .navigationTitle(existingReview == nil ? "Rate It" : "Your Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isEditorFocused = false }
                }
            }
            .onAppear(perform: loadExistingReview)
            .confirmationDialog(
                "Delete this review?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Review", role: .destructive, action: deleteReview)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your rating and review text will be removed from your profile.")
            }
        }
    }

    // MARK: - Sections

    private var bookHeader: some View {
        HStack(spacing: Theme.paddingMedium) {
            AsyncImage(url: URL(string: userBook.book?.thumbnailURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 70, height: 105)
                        .cornerRadius(Theme.cornerRadiusSmall)
                default:
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                        .fill(Theme.parchment)
                        .frame(width: 70, height: 105)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(userBook.book?.title ?? "Unknown")
                    .font(Theme.serifBold(20))
                    .foregroundColor(Theme.primaryText)
                    .lineLimit(3)

                Text(userBook.book?.authorDisplay ?? "")
                    .font(Theme.body(14))
                    .foregroundColor(Theme.secondaryText)
            }
        }
        .padding(.horizontal)
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Rating")
                .font(Theme.serifBold(18))
                .foregroundColor(Theme.primaryText)

            StarRatingPicker(rating: $rating)
        }
        .padding(.horizontal)
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your Review")
                    .font(Theme.serifBold(18))
                    .foregroundColor(Theme.primaryText)

                Spacer()

                Text("Optional")
                    .font(Theme.caption(12))
                    .foregroundColor(Theme.muted)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $reviewText)
                    .frame(minHeight: 150)
                    .padding(Theme.paddingSmall)
                    .background(Theme.parchment)
                    .cornerRadius(Theme.cornerRadiusMedium)
                    .font(Theme.body(15))
                    .foregroundColor(Theme.primaryText)
                    .scrollContentBackground(.hidden)
                    .focused($isEditorFocused)

                if reviewText.isEmpty {
                    Text("What stuck with you?")
                        .font(Theme.body(15))
                        .foregroundColor(Theme.muted.opacity(0.7))
                        .padding(.horizontal, Theme.paddingSmall + 5)
                        .padding(.vertical, Theme.paddingSmall + 8)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(.horizontal)
    }

    private var saveSection: some View {
        VStack(spacing: Theme.paddingMedium) {
            Button(action: saveReview) {
                Text(existingReview != nil ? "Update Review" : "Save Review")
                    .frame(maxWidth: .infinity)
                    .primaryButtonStyle()
                    .opacity(rating == 0 ? 0.5 : 1)
            }
            .disabled(rating == 0)

            if existingReview != nil {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Text("Delete Review")
                        .font(Theme.body(15))
                        .foregroundColor(Theme.negative)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Actions

    private func loadExistingReview() {
        guard let review = reviewStore.review(forGoogleBooksId: userBook.googleBooksId) else { return }
        existingReview = review
        rating = review.rating
        reviewText = review.reviewText ?? ""
    }

    private func saveReview() {
        guard rating > 0 else { return }
        reviewStore.upsert(
            userId: userBook.userId,
            googleBooksId: userBook.googleBooksId,
            rating: rating,
            reviewText: reviewText
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func deleteReview() {
        reviewStore.remove(googleBooksId: userBook.googleBooksId)
        dismiss()
    }
}
