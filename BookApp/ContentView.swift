import SwiftUI

struct ContentView: View {
    @StateObject private var authViewModel = AuthViewModel()
    @State private var isShowingLaunchScreen = true

    var body: some View {
        ZStack {
            if isShowingLaunchScreen {
                LaunchScreenView()
            } else {
                Group {
                    if authViewModel.isAuthenticated {
                        MainTabView(authViewModel: authViewModel)
                    } else {
                        SignInView(viewModel: authViewModel)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: authViewModel.isAuthenticated)
            }
        }
        .onAppear {
            // Show launch screen for 1.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isShowingLaunchScreen = false
            }
        }
    }
}

struct MainTabView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DiscoveryFeedView()
                .tabItem {
                    Label("Discover", systemImage: "book.fill")
                }
                .tag(0)

            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical.fill")
                }
                .tag(1)

            ProfileView(authViewModel: authViewModel)
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(2)
        }
        .tint(Theme.accent)
    }
}

struct LaunchScreenView: View {    
    var body: some View {
        ZStack {
            // White background
            Color.white.ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Static app logo
                ZStack {
                    // Book base - brown rectangle
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.brown)
                        .frame(width: 120, height: 90)
                    
                    // Book spine - dark line on left
                    Rectangle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 4, height: 90)
                        .offset(x: -50)
                    
                    // Pages - cream rectangle on right
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(white: 0.95))
                        .frame(width: 30, height: 84)
                        .offset(x: 40)
                }
                
                // App name
                Text("BookApp")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.brown)
            }
        }
    }
}
