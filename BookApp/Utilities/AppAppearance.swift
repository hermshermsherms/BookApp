import SwiftUI
import UIKit

/// Pins the system bars to fixed, opaque backgrounds.
///
/// By default UIKit gives the tab bar a translucent material *and* a separate
/// `scrollEdgeAppearance`, then swaps between the two whenever it decides a
/// contained scroll view has reached its edge. The Discovery feed sits full-bleed
/// under the bar and contains its own scroll views (the metadata strip, the
/// expanded synopsis), so that swap fired constantly while paging. Each swap
/// re-derived the light-mode material before it had sampled the near-black feed
/// behind it, which is what read as the tab bar flashing white and then settling
/// back to dark on every swipe.
///
/// Configuring both appearances identically, with the material removed, means
/// there is nothing left to swap between and nothing to re-sample.
enum AppAppearance {
    static func configure() {
        applyTabBarAppearance()
        applyNavigationBarAppearance()
    }

    private static func applyTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = UIColor(Theme.background)
        appearance.shadowColor = UIColor(Theme.espresso).withAlphaComponent(0.12)

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    private static func applyNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = UIColor(Theme.background)
        appearance.shadowColor = nil

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}
