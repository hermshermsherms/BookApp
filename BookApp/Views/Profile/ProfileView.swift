import SwiftUI

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @ObservedObject var authViewModel: AuthViewModel

    // The local stores are the source of truth, so the shelf updates the moment
    // a book is finished or a review is saved.
    @ObservedObject private var libraryStore = LibraryStore.shared
    @ObservedObject private var reviewStore = ReviewStore.shared

    @State private var selectedItem: ProfileViewModel.ShelfItem?
    @State private var showDeleteConfirmation = false
    @State private var showSignOutConfirmation = false

    private var shelf: [ProfileViewModel.ShelfItem] {
        viewModel.shelf(books: libraryStore.entries, reviews: reviewStore.reviews)
    }

    private var stats: ProfileViewModel.Stats {
        viewModel.stats(books: libraryStore.entries, reviews: reviewStore.reviews)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.paddingLarge) {
                    header
                    statsCard
                    shelfSection
                    settingsSections

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
        .sheet(item: $selectedItem) { item in
            ShelfBookDetailView(item: item, readerName: viewModel.displayName)
        }
        .onAppear {
            viewModel.refreshDisplayName()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.paddingMedium) {
            ZStack {
                Circle()
                    .fill(Theme.parchment)
                    .frame(width: 90, height: 90)

                Text(viewModel.displayName.prefix(1).uppercased())
                    .font(Theme.serifBold(36))
                    .foregroundColor(Theme.accent)
            }

            VStack(spacing: 4) {
                Text(viewModel.displayName)
                    .font(Theme.serifBold(24))
                    .foregroundColor(Theme.primaryText)

                if stats.booksRead > 0 {
                    Text(readerTagline)
                        .font(Theme.caption(13))
                        .foregroundColor(Theme.muted)
                }
            }
        }
        .padding(.top, Theme.paddingLarge)
    }

    /// A light touch of personality under the name, based on the shelf.
    private var readerTagline: String {
        let count = stats.booksRead
        let books = count == 1 ? "book" : "books"
        if let average = stats.averageRating {
            return "\(count) \(books) read · \(String(format: "%.1f", average)) ★ average"
        }
        return "\(count) \(books) read"
    }

    // MARK: - Stats

    private var statsCard: some View {
        HStack(spacing: 0) {
            statItem(value: "\(stats.booksRead)", label: "Read")
            Divider()
                .frame(height: 40)
            statItem(value: "\(stats.reviewsWritten)", label: "Reviews")
            Divider()
                .frame(height: 40)
            statItem(value: "\(stats.totalBooks)", label: "Library")
        }
        .padding(.vertical, Theme.paddingMedium)
        .background(Theme.cardBackground)
        .cornerRadius(Theme.cornerRadiusMedium)
        .padding(.horizontal)
    }

    // MARK: - Read Shelf

    private var shelfSection: some View {
        VStack(alignment: .leading, spacing: Theme.paddingMedium) {
            HStack {
                Text("Read Shelf")
                    .font(Theme.serifBold(20))
                    .foregroundColor(Theme.primaryText)

                Spacer()

                if shelf.count > 1 {
                    Menu {
                        Picker("Sort", selection: $viewModel.sort) {
                            ForEach(ProfileViewModel.ShelfSort.allCases) { sort in
                                Label(sort.displayName, systemImage: sort.iconName).tag(sort)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(viewModel.sort.displayName)
                                .font(Theme.caption(13))
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(Theme.accent)
                    }
                }
            }
            .padding(.horizontal)

            if shelf.isEmpty {
                shelfEmptyState
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Theme.paddingMedium), count: 3),
                    spacing: Theme.paddingLarge
                ) {
                    ForEach(shelf) { item in
                        Button {
                            selectedItem = item
                        } label: {
                            ShelfCoverView(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var shelfEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "books.vertical")
                .font(.system(size: 34))
                .foregroundColor(Theme.muted.opacity(0.5))

            Text("Your shelf is empty")
                .font(Theme.body(15))
                .foregroundColor(Theme.secondaryText)

            Text("Mark a book as Read in your Library and it lands here, ready to rate.")
                .font(Theme.caption(13))
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.paddingLarge)
        }
        .padding(.vertical, Theme.paddingLarge)
        .frame(maxWidth: .infinity)
        .background(Theme.cardBackground)
        .cornerRadius(Theme.cornerRadiusMedium)
        .padding(.horizontal)
    }

    // MARK: - Settings

    private var settingsSections: some View {
        VStack(spacing: Theme.paddingLarge) {
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
        }
    }

    // MARK: - Components

    @ViewBuilder
    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
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
