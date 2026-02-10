import SwiftUI

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @ObservedObject var authViewModel: AuthViewModel
    @State private var showDeleteConfirmation = false
    @State private var showSignOutConfirmation = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.paddingLarge) {
                    // Avatar + Name
                    VStack(spacing: Theme.paddingMedium) {
                        ZStack {
                            Circle()
                                .fill(Theme.parchment)
                                .frame(width: 90, height: 90)

                            Text(viewModel.displayName.prefix(1).uppercased())
                                .font(Theme.serifBold(36))
                                .foregroundColor(Theme.accent)
                        }

                        Text(viewModel.displayName)
                            .font(Theme.serifBold(24))
                            .foregroundColor(Theme.primaryText)
                    }
                    .padding(.top, Theme.paddingLarge)

                    // Stats
                    HStack(spacing: 0) {
                        statItem(value: viewModel.totalBooks, label: "Books")
                        Divider()
                            .frame(height: 40)
                        statItem(value: viewModel.booksRead, label: "Read")
                        Divider()
                            .frame(height: 40)
                        statItem(value: viewModel.reviewsWritten, label: "Reviews")
                    }
                    .padding(.vertical, Theme.paddingMedium)
                    .background(Theme.cardBackground)
                    .cornerRadius(Theme.cornerRadiusMedium)
                    .padding(.horizontal)

                    // Settings
                    VStack(spacing: 2) {
                        settingsHeader("Account")

                        settingsRow(icon: "rectangle.portrait.and.arrow.right", title: "Sign Out", color: Theme.primaryText) {
                            showSignOutConfirmation = true
                        }

                        settingsRow(icon: "trash", title: "Delete Account", color: Theme.negative) {
                            showDeleteConfirmation = true
                        }
                    }
                    .padding(.horizontal)

                    VStack(spacing: 2) {
                        settingsHeader("About")

                        settingsRow(icon: "info.circle", title: "Version 1.0.0", color: Theme.muted) {}
                            .disabled(true)
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 60)
                }
            }
            .background(Theme.background)
            .navigationTitle("Profile")
            .alert("Sign Out?", isPresented: $showSignOutConfirmation) {
                Button("Sign Out", role: .destructive) {
                    authViewModel.signOut()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You can always sign back in.")
            }
            .alert("Delete Account?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    authViewModel.deleteAccount()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete your account and all your data. This action cannot be undone.")
            }
        }
        .task {
            await viewModel.loadProfile()
        }
    }

    // MARK: - Components

    @ViewBuilder
    private func statItem(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(Theme.serifBold(24))
                .foregroundColor(Theme.primaryText)
            Text(label)
                .font(Theme.caption(12))
                .foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func settingsHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.muted)
            Spacer()
        }
        .padding(.horizontal, Theme.paddingMedium)
        .padding(.top, Theme.paddingMedium)
        .padding(.bottom, Theme.paddingSmall)
    }

    @ViewBuilder
    private func settingsRow(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundColor(color)
                    .frame(width: 24)

                Text(title)
                    .font(Theme.body(16))
                    .foregroundColor(color)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.muted.opacity(0.5))
            }
            .padding(.horizontal, Theme.paddingMedium)
            .padding(.vertical, 14)
            .background(Theme.cardBackground)
        }
        .cornerRadius(Theme.cornerRadiusMedium)
    }
}
