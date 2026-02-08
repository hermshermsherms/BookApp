// swift-tools-version: 5.9
import PackageDescription

// Note: This Package.swift is for dependency management only.
// Build via the Xcode project targeting iOS 16+.
// SPM `swift build` from CLI won't work for iOS-only SwiftUI
// apps without the full Xcode iOS simulator SDK installed.

let package = Package(
    name: "BookApp",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "BookApp",
            targets: ["BookApp"]
        ),
    ],
    dependencies: [
        // Add in Xcode via File > Add Package Dependencies:
        // Supabase Swift: https://github.com/supabase/supabase-swift (2.x+)
    ],
    targets: [
        .target(
            name: "BookApp",
            path: "BookApp"
        ),
    ]
)
