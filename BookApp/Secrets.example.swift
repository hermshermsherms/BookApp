import Foundation

// MARK: - Secrets Template
//
// This is a TEMPLATE and is safe to commit. Do NOT put real keys here.
//
// Setup:
//   1. Copy this file to `Secrets.swift` (same folder):
//        cp BookApp/Secrets.example.swift BookApp/Secrets.swift
//   2. Paste your real key(s) into `Secrets.swift`.
//   3. `Secrets.swift` is gitignored, so your key never gets committed.
//
// `Secrets.swift` is already part of the Xcode target, so once it exists
// the app will pick up your key automatically.

enum Secrets {
    /// Google Books API key.
    /// Create one at https://console.cloud.google.com/apis/credentials
    /// (create/select a project → enable the "Books API" → create an API key).
    static let googleBooksAPIKey = "PASTE_YOUR_GOOGLE_BOOKS_API_KEY_HERE"
}
