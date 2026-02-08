import AuthenticationServices
import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var error: String?

    private let authService = AuthService.shared

    init() {
        self.isAuthenticated = authService.isAuthenticated
    }

    // MARK: - Apple Sign In

    func handleSignIn(result: Result<ASAuthorization, Error>) {
        isLoading = true
        error = nil

        Task {
            do {
                try await authService.handleSignIn(result: result)
                self.isAuthenticated = true
            } catch AuthError.cancelled {
                // User cancelled — not an error
            } catch {
                self.error = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    func signOut() {
        authService.signOut()
        isAuthenticated = false
    }

    func deleteAccount() {
        isLoading = true
        Task {
            do {
                try await authService.deleteAccount()
                self.isAuthenticated = false
            } catch {
                self.error = error.localizedDescription
            }
            self.isLoading = false
        }
    }
}
