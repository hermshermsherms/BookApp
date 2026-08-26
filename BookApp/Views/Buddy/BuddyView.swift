import SwiftUI

/// Tab root for the reading buddy: your ongoing conversations, plus a way to
/// start a new one about a book or an author.
struct BuddyView: View {
    @StateObject private var store = ConversationStore.shared
    @State private var isPickingSubject = false
    /// Resolved in the picker's callback rather than in the destination builder:
    /// `store.conversation(for:)` inserts and saves, and doing that while SwiftUI
    /// is evaluating a body mutates published state mid-update.
    @State private var openedConversation: Conversation?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if store.conversations.isEmpty {
                    emptyState
                } else {
                    conversationList
                }
            }
            .navigationTitle("Reading Buddy")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isPickingSubject = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .tint(Theme.accent)
                    .accessibilityLabel("Start a new conversation")
                }
            }
            .sheet(isPresented: $isPickingSubject) {
                SubjectPickerView { subject in
                    isPickingSubject = false
                    openedConversation = store.conversation(for: subject)
                }
            }
            // `navigationDestination(item:)` is iOS 17; this target is 16, so the
            // freshly picked conversation is pushed via an isPresented binding.
            .navigationDestination(
                isPresented: Binding(
                    get: { openedConversation != nil },
                    set: { if !$0 { openedConversation = nil } }
                )
            ) {
                if let openedConversation {
                    ChatView(conversation: openedConversation)
                }
            }
        }
    }

    private var conversationList: some View {
        List {
            ForEach(store.conversations) { conversation in
                NavigationLink {
                    ChatView(conversation: conversation)
                } label: {
                    row(for: conversation)
                }
                .listRowBackground(Theme.cardBackground)
            }
            .onDelete { offsets in
                offsets.map { store.conversations[$0] }.forEach(store.delete)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func row(for conversation: Conversation) -> some View {
        HStack(spacing: 12) {
            SubjectThumbnail(subject: conversation.subject, size: CGSize(width: 40, height: 58))

            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.subject.name)
                    .font(Theme.serifBold(16))
                    .foregroundColor(Theme.primaryText)
                    .lineLimit(1)

                Text(conversation.lastLine)
                    .font(Theme.caption(13))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44))
                .foregroundColor(Theme.muted)

            Text("Talk about what you're reading")
                .font(Theme.serifTitle(21))
                .foregroundColor(Theme.primaryText)

            Text("Pick a book or an author and ask anything — themes, a passage that stuck with you, where to go next.")
                .font(Theme.body(15))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Button("Start a conversation") { isPickingSubject = true }
                .primaryButtonStyle()
                .padding(.top, 4)
        }
    }
}

/// Small cover/initial badge used in lists.
struct SubjectThumbnail: View {
    let subject: ChatSubject
    var size: CGSize = CGSize(width: 40, height: 58)

    var body: some View {
        Group {
            if subject.kind == .author {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.parchment)
                    .overlay {
                        Text(subject.name.prefix(1).uppercased())
                            .font(Theme.serifBold(18))
                            .foregroundColor(Theme.accent)
                    }
            } else {
                CachedAsyncImage(url: subject.coverURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        RoundedRectangle(cornerRadius: 6).fill(Theme.parchment)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Subject picker

/// Choose what the next conversation is about: a book from your library, a book
/// found by search, or an author.
struct SubjectPickerView: View {
    enum Mode: String, CaseIterable {
        case books = "Books"
        case authors = "Authors"
    }

    let onPick: (ChatSubject) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var library = LibraryStore.shared

    @State private var mode: Mode = .books
    @State private var query = ""
    @State private var results: [Book] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                    searchField

                    List {
                        if mode == .books {
                            bookSections
                        } else {
                            authorSection
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("New conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(Theme.accent)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.muted)
            TextField(
                mode == .books ? "Search by title or author" : "Search for an author",
                text: $query
            )
            .autocorrectionDisabled()
            .onChange(of: query) { _ in scheduleSearch() }

            if isSearching {
                ProgressView().controlSize(.small)
            } else if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(Theme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var bookSections: some View {
        if !libraryBooks.isEmpty && query.isEmpty {
            Section("In your library") {
                ForEach(libraryBooks) { book in
                    Button { onPick(.book(book)) } label: { bookRow(book) }
                        .buttonStyle(.plain)
                }
            }
            .listRowBackground(Theme.cardBackground)
        }

        if !results.isEmpty {
            Section(query.isEmpty ? "Results" : "Search results") {
                ForEach(results) { book in
                    Button { onPick(.book(book)) } label: { bookRow(book) }
                        .buttonStyle(.plain)
                }
            }
            .listRowBackground(Theme.cardBackground)
        }
    }

    @ViewBuilder
    private var authorSection: some View {
        let authors = discoveredAuthors
        if authors.isEmpty {
            Section {
                Text(query.isEmpty
                     ? "Search for an author, or save some books to your library first."
                     : "No authors found.")
                    .font(Theme.body(14))
                    .foregroundColor(Theme.secondaryText)
            }
            .listRowBackground(Theme.cardBackground)
        } else {
            Section("Authors") {
                ForEach(authors, id: \.self) { author in
                    Button {
                        onPick(.author(author))
                    } label: {
                        HStack(spacing: 12) {
                            SubjectThumbnail(
                                subject: .author(author),
                                size: CGSize(width: 34, height: 34)
                            )
                            Text(author)
                                .font(Theme.body(16))
                                .foregroundColor(Theme.primaryText)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(Theme.cardBackground)
        }
    }

    private func bookRow(_ book: Book) -> some View {
        HStack(spacing: 12) {
            SubjectThumbnail(subject: .book(book), size: CGSize(width: 36, height: 52))
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(Theme.body(15).weight(.semibold))
                    .foregroundColor(Theme.primaryText)
                    .lineLimit(2)
                Text(book.authorDisplay)
                    .font(Theme.caption(13))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    // MARK: - Data

    private var libraryBooks: [Book] {
        library.entries.compactMap(\.book)
    }

    /// Authors are derived from search results plus your library, de-duplicated
    /// case-insensitively — Google Books has no author-entity endpoint.
    private var discoveredAuthors: [String] {
        let pool = (results + libraryBooks).map(\.primaryAuthor)
        var seen = Set<String>()
        return pool.filter { name in
            let key = name.lowercased()
            guard !name.isEmpty, name != "Unknown Author", seen.insert(key).inserted else {
                return false
            }
            return query.isEmpty || name.localizedCaseInsensitiveContains(query)
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            results = []
            isSearching = false
            return
        }

        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            isSearching = true
            defer { isSearching = false }

            let found = (try? await GoogleBooksService.shared.searchBooks(query: text)) ?? []
            guard !Task.isCancelled else { return }

            var seen = Set<String>()
            results = found.filter { seen.insert($0.id).inserted }
        }
    }
}
