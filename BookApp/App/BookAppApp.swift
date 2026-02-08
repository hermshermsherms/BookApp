import SwiftUI

@main
struct BookAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light) // Light-only for v1
        }
    }
}
