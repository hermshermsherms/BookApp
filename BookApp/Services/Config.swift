import Foundation

/// Configuration management for the BookApp
enum Config {
    
    /// Supabase configuration
    enum Supabase {
        /// Supabase project URL
        static var url: String {
            if let url = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
               !url.contains("YOUR_PROJECT") {
                return url
            }
            
            #if DEBUG
            // Development fallback - you can set this to your development Supabase URL
            return "https://your-dev-project.supabase.co"
            #else
            fatalError("SUPABASE_URL must be configured in Info.plist for production builds")
            #endif
        }
        
        /// Supabase anonymous key (safe for client-side use)
        static var anonKey: String {
            if let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
               !key.contains("YOUR_ANON_KEY") {
                return key
            }
            
            #if DEBUG
            // Development fallback - you can set this to your development anon key
            return "your-dev-anon-key-here"
            #else
            fatalError("SUPABASE_ANON_KEY must be configured in Info.plist for production builds")
            #endif
        }
    }
    
    /// Apple Sign In configuration
    enum Apple {
        /// Services ID for Apple Sign In (should match your Apple Developer Console configuration)
        static var servicesId: String {
            if let servicesId = Bundle.main.object(forInfoDictionaryKey: "APPLE_SERVICES_ID") as? String {
                return servicesId
            }
            
            // Default based on bundle identifier
            if let bundleId = Bundle.main.bundleIdentifier {
                return "\(bundleId).signin"
            }
            
            return "com.bookapp.signin"
        }
    }
    
    /// App configuration
    enum App {
        /// Current app version
        static var version: String {
            return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        }
        
        /// App build number
        static var build: String {
            return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        }
        
        /// App bundle identifier
        static var bundleId: String {
            return Bundle.main.bundleIdentifier ?? "com.bookapp"
        }
        
        /// Is this a debug build?
        static var isDebug: Bool {
            #if DEBUG
            return true
            #else
            return false
            #endif
        }
    }
}

// MARK: - Configuration Validation

extension Config {
    /// Validate that all required configuration is present
    static func validate() throws {
        // Validate Supabase configuration
        let url = Supabase.url
        let key = Supabase.anonKey
        
        guard !url.contains("YOUR_PROJECT") && !url.contains("your-dev-project") else {
            throw ConfigError.missingSupabaseURL
        }
        
        guard !key.contains("YOUR_ANON_KEY") && !key.contains("your-dev-anon-key") else {
            throw ConfigError.missingSupabaseKey
        }
        
        // Validate URLs
        guard URL(string: url) != nil else {
            throw ConfigError.invalidSupabaseURL
        }
    }
}

// MARK: - Configuration Errors

enum ConfigError: LocalizedError {
    case missingSupabaseURL
    case missingSupabaseKey
    case invalidSupabaseURL
    
    var errorDescription: String? {
        switch self {
        case .missingSupabaseURL:
            return "Supabase URL is not configured. Please add SUPABASE_URL to Info.plist or check SUPABASE_SETUP.md"
        case .missingSupabaseKey:
            return "Supabase anonymous key is not configured. Please add SUPABASE_ANON_KEY to Info.plist or check SUPABASE_SETUP.md"
        case .invalidSupabaseURL:
            return "Supabase URL is invalid. Please check your SUPABASE_URL configuration."
        }
    }
}