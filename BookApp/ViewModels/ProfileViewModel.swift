import SwiftUI

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var displayName: String = ""
    @Published var booksRead: Int = 0
    @Published var reviewsWritten: Int = 0
    @Published var totalBooks: Int = 0
    @Published var isLoading = false
    @Published var error: String?

    private let supabaseService = SupabaseService.shared

    func loadProfile() async {
        guard let userId = AuthService.shared.currentUserId else { return }

        displayName = AuthService.shared.displayName ?? "Reader"
        isLoading = true

        do {
            let stats = try await supabaseService.fetchUserStats(userId: userId)
            booksRead = stats.booksRead
            reviewsWritten = stats.reviewsWritten
            totalBooks = stats.totalBooks
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
