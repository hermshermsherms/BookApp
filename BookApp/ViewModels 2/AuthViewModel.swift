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
    
    // MARK: - Development Mode
    
    #if DEBUG
    func signInAsDemoUser() {
        print("🔐 Demo User: Starting sign in...")
        isLoading = true
        error = nil
        
        Task {
            print("🔐 Demo User: Calling authService.signInAsDemoUser()")
            authService.signInAsDemoUser()
            await MainActor.run {
                print("🔐 Demo User: Setting isAuthenticated = true")
                self.isAuthenticated = true
                self.isLoading = false
                print("🔐 Demo User: Sign in complete. isAuthenticated = \(self.isAuthenticated)")
            }
        }
    }
    #endif
}
