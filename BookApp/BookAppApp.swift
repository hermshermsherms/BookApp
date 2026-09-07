import SwiftUI

@main
struct BookAppApp: App {
    init() {
        AppAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light) // Light-only for v1
        }
    }
}
