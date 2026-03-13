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
    
    /// App configuration
    enum App {
        /// Current app version
        static var version: String {
            return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
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