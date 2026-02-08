import SwiftUI

enum Theme {
    // MARK: - Colors
    static let cream = Color(red: 0.98, green: 0.96, blue: 0.91)
    static let warmWhite = Color(red: 0.99, green: 0.97, blue: 0.94)
    static let parchment = Color(red: 0.95, green: 0.91, blue: 0.84)
    static let espresso = Color(red: 0.26, green: 0.18, blue: 0.12)
    static let warmBrown = Color(red: 0.44, green: 0.32, blue: 0.22)
    static let terracotta = Color(red: 0.80, green: 0.45, blue: 0.30)
    static let sage = Color(red: 0.55, green: 0.65, blue: 0.50)
    static let dustyRose = Color(red: 0.78, green: 0.55, blue: 0.55)
    static let muted = Color(red: 0.60, green: 0.55, blue: 0.50)

    // MARK: - Semantic Colors
    static let background = cream
    static let cardBackground = warmWhite
    static let primaryText = espresso
    static let secondaryText = warmBrown
    static let accent = terracotta
    static let positive = sage
    static let negative = dustyRose

    // MARK: - Fonts
    static func serifTitle(_ size: CGFloat) -> Font {
        .custom("Georgia", size: size)
    }

    static func serifBold(_ size: CGFloat) -> Font {
        .custom("Georgia-Bold", size: size)
    }

    static func body(_ size: CGFloat = 16) -> Font {
        .system(size: size, design: .default)
    }

    static func caption(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    // MARK: - Spacing
    static let paddingSmall: CGFloat = 8
    static let paddingMedium: CGFloat = 16
    static let paddingLarge: CGFloat = 24

    // MARK: - Corner Radius
    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusMedium: CGFloat = 12
    static let cornerRadiusLarge: CGFloat = 20
}
