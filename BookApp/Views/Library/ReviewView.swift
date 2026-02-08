import SwiftUI

struct ReviewView: View {
    let userBook: UserBook
    @State private var rating: Int = 0
    @State private var reviewText: String = ""
    @State private var existingReview: Review?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var error: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.paddingLarge) {
                    // Book header
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

                    Divider()
                        .padding(.horizontal)

                    // Star Rating
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your Rating")
                            .font(Theme.serifBold(18))
                            .foregroundColor(Theme.primaryText)

                        HStack(spacing: 12) {
                            ForEach(1...5, id: \.self) { star in
                                Button {
                                    withAnimation(.spring(response: 0.2)) {
                                        rating = star
                                    }
                                } label: {
                                    Image(systemName: star <= rating ? "star.fill" : "star")
                                        .font(.system(size: 36))
                                        .foregroundColor(star <= rating ? .yellow : Theme.muted.opacity(0.4))
                                }
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Review Text
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your Review")
                            .font(Theme.serifBold(18))
                            .foregroundColor(Theme.primaryText)

                        TextEditor(text: $reviewText)
                            .frame(minHeight: 150)
                            .padding(Theme.paddingSmall)
                            .background(Theme.parchment)
                            .cornerRadius(Theme.cornerRadiusMedium)
                            .font(Theme.body(15))
                            .foregroundColor(Theme.primaryText)
                            .scrollContentBackground(.hidden)
                    }
                    .padding(.horizontal)

                    // Error
                    if let error = error {
                        Text(error)
                            .font(Theme.caption())
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }

                    // Save Button
                    Button {
                        Task { await saveReview() }
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(existingReview != nil ? "Update Review" : "Save Review")
                        }
                        .frame(maxWidth: .infinity)
                        .primaryButtonStyle()
                    }
                    .disabled(rating == 0 || isSaving)
                    .padding(.horizontal)

                    // Delete Review (if editing)
                    if existingReview != nil {
                        Button(role: .destructive) {
                            Task { await deleteReview() }
                        } label: {
                            Text("Delete Review")
                                .font(Theme.body(15))
                                .foregroundColor(Theme.negative)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
            }
            .background(Theme.background)
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
            }
            .task {
                await loadExistingReview()
            }
        }
    }

    // MARK: - Load Existing

    private func loadExistingReview() async {
        guard let userId = AuthService.shared.currentUserId else { return }
        isLoading = true

        do {
            if let review = try await SupabaseService.shared.fetchReview(
                userId: userId,
                googleBooksId: userBook.googleBooksId
            ) {
                existingReview = review
                rating = review.rating
                reviewText = review.reviewText ?? ""
            }
        } catch {
            // No existing review — that's fine
        }

        isLoading = false
    }

    // MARK: - Save

    private func saveReview() async {
        guard let userId = AuthService.shared.currentUserId, rating > 0 else { return }

        isSaving = true
        error = nil

        do {
            let review = try await SupabaseService.shared.upsertReview(
                userId: userId,
                googleBooksId: userBook.googleBooksId,
                rating: rating,
                reviewText: reviewText.isEmpty ? nil : reviewText
            )
            existingReview = review
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }

    // MARK: - Delete

    private func deleteReview() async {
        guard let review = existingReview else { return }

        do {
            try await SupabaseService.shared.deleteReview(reviewId: review.id)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
