import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @ObservedObject var viewModel: AuthViewModel

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            VStack(spacing: Theme.paddingLarge) {
                Spacer()

                // App icon / branding
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 72))
                    .foregroundColor(Theme.accent)

                VStack(spacing: Theme.paddingSmall) {
                    Text("BookApp")
                        .font(Theme.serifBold(36))
                        .foregroundColor(Theme.primaryText)

                    Text("Discover your next great read")
                        .font(Theme.body(16))
                        .foregroundColor(Theme.secondaryText)
                }

                Spacer()

                VStack(spacing: Theme.paddingMedium) {
                    // Apple Sign In Button
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        viewModel.handleSignIn(result: result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 52)
                    .cornerRadius(Theme.cornerRadiusMedium)
                    .padding(.horizontal, Theme.paddingLarge)
                    
                    // Development mode bypass
                    #if DEBUG
                    Button("Continue as Demo User") {
                        viewModel.signInAsDemoUser()
                    }
                    .font(Theme.body(16))
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, Theme.paddingLarge)
                    #endif
                }

                if viewModel.isLoading {
                    ProgressView()
                        .tint(Theme.accent)
                }

                if let error = viewModel.error {
                    Text(error)
                        .font(Theme.caption())
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()
                    .frame(height: 40)
            }
        }
    }
}
