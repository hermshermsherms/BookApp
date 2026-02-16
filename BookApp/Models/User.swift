import Foundation

/// Represents a user in the BookApp system
struct User: Codable, Identifiable {
    let id: UUID
    let appleId: String?
    let displayName: String?
    let onboardingCompleted: Bool
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case appleId = "apple_id"
        case displayName = "display_name"
        case onboardingCompleted = "onboarding_completed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    /// Create a new user for registration
    init(id: UUID, appleId: String?, displayName: String?) {
        self.id = id
        self.appleId = appleId
        self.displayName = displayName
        self.onboardingCompleted = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    /// Display name with fallback
    var effectiveDisplayName: String {
        return displayName ?? "Reader"
    }
    
    /// Whether the user has completed the initial setup
    var needsOnboarding: Bool {
        return !onboardingCompleted
    }
}

/// User profile update request
struct UserProfileUpdate: Codable {
    let displayName: String?
    let onboardingCompleted: Bool?
    
    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case onboardingCompleted = "onboarding_completed"
    }
    
    init(displayName: String? = nil, onboardingCompleted: Bool? = nil) {
        self.displayName = displayName
        self.onboardingCompleted = onboardingCompleted
    }
}