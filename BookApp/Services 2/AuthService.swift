import AuthenticationServices
import Foundation

/// Manages Apple Sign In authentication with Supabase
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var currentUserId: UUID?
    @Published var displayName: String?
    @Published var isAuthenticated = false

    private let supabaseURL: String
    private let supabaseAnonKey: String
    private let session: URLSession
    private let decoder: JSONDecoder

    private let userIdKey = "bookapp_user_id"
    private let displayNameKey = "bookapp_display_name"
    private let accessTokenKey = "bookapp_access_token"
    private let refreshTokenKey = "bookapp_refresh_token"

    private init() {
        // TODO: Move to environment config before release
        self.supabaseURL = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? "https://YOUR_PROJECT.supabase.co"
        self.supabaseAnonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? "YOUR_ANON_KEY"
        self.session = URLSession.shared
        self.decoder = JSONDecoder()

        restoreSession()
    }

    // MARK: - Session Persistence

    private func restoreSession() {
        if let userIdString = UserDefaults.standard.string(forKey: userIdKey),
           let userId = UUID(uuidString: userIdString),
           let token = UserDefaults.standard.string(forKey: accessTokenKey) {
            self.currentUserId = userId
            self.displayName = UserDefaults.standard.string(forKey: displayNameKey)
            self.isAuthenticated = true
            SupabaseService.shared.setAccessToken(token)
        }
    }

    private func saveSession(userId: UUID, displayName: String?, accessToken: String, refreshToken: String?) {
        UserDefaults.standard.set(userId.uuidString, forKey: userIdKey)
        UserDefaults.standard.set(displayName, forKey: displayNameKey)
        UserDefaults.standard.set(accessToken, forKey: accessTokenKey)
        if let refreshToken = refreshToken {
            UserDefaults.standard.set(refreshToken, forKey: refreshTokenKey)
        }

        self.currentUserId = userId
        self.displayName = displayName
        self.isAuthenticated = true
        SupabaseService.shared.setAccessToken(accessToken)
    }

    private func clearSession() {
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: displayNameKey)
        UserDefaults.standard.removeObject(forKey: accessTokenKey)
        UserDefaults.standard.removeObject(forKey: refreshTokenKey)

        self.currentUserId = nil
        self.displayName = nil
        self.isAuthenticated = false
        SupabaseService.shared.setAccessToken(nil)
    }

    // MARK: - Apple Sign In

    /// Handle the Apple Sign In authorization result
    func handleSignIn(result: Result<ASAuthorization, Error>) async throws {
        switch result {
        case .success(let authorization):
            guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = appleCredential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                throw AuthError.invalidCredential
            }

            // Get display name (only provided on first sign in)
            let name: String?
            if let fullName = appleCredential.fullName {
                let parts = [fullName.givenName, fullName.familyName].compactMap { $0 }
                name = parts.isEmpty ? nil : parts.joined(separator: " ")
            } else {
                name = nil
            }

            // Exchange Apple ID token with Supabase
            let authResponse = try await signInWithSupabase(idToken: identityToken)

            let storedName = name ?? displayName ?? "Reader"
            saveSession(
                userId: authResponse.userId,
                displayName: storedName,
                accessToken: authResponse.accessToken,
                refreshToken: authResponse.refreshToken
            )

        case .failure(let error):
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                throw AuthError.cancelled
            }
            throw AuthError.appleSignInFailed(error.localizedDescription)
        }
    }

    // MARK: - Supabase Auth

    private struct SupabaseAuthResponse: Codable {
        let access_token: String
        let refresh_token: String?
        let user: SupabaseUser
    }

    private struct SupabaseUser: Codable {
        let id: String
    }

    private struct AuthResult {
        let userId: UUID
        let accessToken: String
        let refreshToken: String?
    }

    private func signInWithSupabase(idToken: String) async throws -> AuthResult {
        guard let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=id_token") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "provider": "apple",
            "id_token": idToken,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.supabaseAuthFailed
        }

        let authResponse = try decoder.decode(SupabaseAuthResponse.self, from: data)

        guard let userId = UUID(uuidString: authResponse.user.id) else {
            throw AuthError.invalidUserId
        }

        return AuthResult(
            userId: userId,
            accessToken: authResponse.access_token,
            refreshToken: authResponse.refresh_token
        )
    }

    // MARK: - Sign Out

    func signOut() {
        clearSession()
    }

    // MARK: - Delete Account

    func deleteAccount() async throws {
        guard let userId = currentUserId else {
            throw AuthError.notAuthenticated
        }

        // TODO: Call Supabase edge function to delete user data and auth account
        // For now, just clear local session
        _ = userId
        clearSession()
    }
    
    // MARK: - Development Mode
    
    #if DEBUG
    /// Sign in as a demo user for development testing
    func signInAsDemoUser() {
        print("🔐 AuthService: Demo user sign in called")
        let demoUserId = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
        let demoDisplayName = "Demo User"
        let demoAccessToken = "demo_access_token"
        
        print("🔐 AuthService: Creating demo session with ID: \(demoUserId)")
        saveSession(
            userId: demoUserId,
            displayName: demoDisplayName,
            accessToken: demoAccessToken,
            refreshToken: nil
        )
        print("🔐 AuthService: Demo session saved. isAuthenticated = \(isAuthenticated)")
    }
    #endif
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case invalidCredential
    case cancelled
    case appleSignInFailed(String)
    case invalidURL
    case supabaseAuthFailed
    case invalidUserId
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Invalid Apple Sign In credential."
        case .cancelled:
            return "Sign in was cancelled."
        case .appleSignInFailed(let message):
            return "Apple Sign In failed: \(message)"
        case .invalidURL:
            return "Invalid authentication URL."
        case .supabaseAuthFailed:
            return "Authentication with server failed."
        case .invalidUserId:
            return "Invalid user ID from server."
        case .notAuthenticated:
            return "You must be signed in."
        }
    }
}
