import SwiftUI

/// Tab root for the reading buddy.
///
/// Search sits at the top rather than behind a "new conversation" button: the
/// main thing you come here to do is start talking about something. One field
/// covers both titles and authors — the results are split into an Authors
/// section and a Books section, ordered by whichever the query looks like.
struct BuddyView: View {
    @StateObject private var store = ConversationStore.shared
    @StateObject private var library = LibraryStore.shared

    @State private var query = ""
    @State private var results: [Book] = []
    @State private var isSearching = false
    @State private var searchFailed = false
    @State private var searchTask: Task<Void, Never>?
    /// Resolved when a subject is tapped rather than in the destination builder:
    /// `store.conversation(for:)` inserts and saves, and doing that while SwiftUI
    /// is evaluating a body mutates published state mid-update.
    @State private var openedConversation: Conversation?

    private var isSearchConfigured: Bool { Config.GoogleBooks.apiKey != nil }
    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    searchField

                    if trimmedQuery.isEmpty {
                        browseList
                    } else {
                        resultsList
                    }
                }
            }
            .navigationTitle("Reading Buddy")
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

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.muted)

            TextField("Search a book or author", text: $query)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .onChange(of: query) { _ in scheduleSearch() }

            if isSearching {
                ProgressView().controlSize(.small)
            } else if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    searchFailed = false
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(Theme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(11)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Empty query: conversations + library

    @ViewBuilder
    private var browseList: some View {
        if store.conversations.isEmpty && libraryBooks.isEmpty {
            Spacer()
            emptyState
            Spacer()
        } else {
            List {
                if !store.conversations.isEmpty {
                    Section("Your conversations") {
                        ForEach(store.conversations) { conversation in
                            Button {
                                openedConversation = conversation
                            } label: {
                                subjectRow(
                                    subject: conversation.subject,
                                    detail: conversation.lastLine
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            offsets.map { store.conversations[$0] }.forEach(store.delete)
                        }
                    }
                    .listRowBackground(Theme.cardBackground)
                }

                if !libraryBooks.isEmpty {
                    Section("From your library") {
                        ForEach(libraryBooks) { book in
                            Button { open(.book(book)) } label: {
                                subjectRow(
                                    subject: .book(book),
                                    detail: book.authorDisplay
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(Theme.cardBackground)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsList: some View {
        List {
            if !isSearchConfigured {
                Section {
                    notice(
                        "Search needs a Google Books API key",
                        detail: "Set googleBooksAPIKey in Secrets.swift to look up books and authors. Conversations you've already started still work."
                    )
                }
                .listRowBackground(Theme.cardBackground)
            } else if searchFailed {
                Section {
                    notice("Couldn't reach Google Books", detail: "Check your connection and try again.")
                }
                .listRowBackground(Theme.cardBackground)
            }

            // An author-looking query puts people first; a title query puts books
            // first. Both sections are always present when they have content.
            if queryLooksLikeAuthor {
                authorSection
                bookSection
            } else {
                bookSection
                authorSection
            }

            if isSearchConfigured, !isSearching, !searchFailed,
               results.isEmpty, trimmedQuery.count >= 2 {
                Section {
                    notice("No matches for \"\(trimmedQuery)\"", detail: nil)
                }
                .listRowBackground(Theme.cardBackground)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var bookSection: some View {
        if !results.isEmpty {
            Section("Books") {
                ForEach(results) { book in
                    Button { open(.book(book)) } label: {
                        subjectRow(subject: .book(book), detail: book.authorDisplay)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(Theme.cardBackground)
        }
    }

    @ViewBuilder
    private var authorSection: some View {
        let authors = discoveredAuthors
        if !authors.isEmpty {
            Section("Authors") {
                ForEach(authors, id: \.self) { author in
                    Button { open(.author(author)) } label: {
                        subjectRow(subject: .author(author), detail: "Talk about their work")
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(Theme.cardBackground)
        }
    }

    // MARK: - Rows

    private func subjectRow(subject: ChatSubject, detail: String) -> some View {
        HStack(spacing: 12) {
            SubjectThumbnail(
                subject: subject,
                size: subject.kind == .author
                    ? CGSize(width: 38, height: 38)
                    : CGSize(width: 38, height: 55)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(subject.name)
                    .font(Theme.body(15).weight(.semibold))
                    .foregroundColor(Theme.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(detail)
                    .font(Theme.caption(13))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
    }

    private func notice(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Theme.body(14).weight(.semibold))
                .foregroundColor(Theme.primaryText)
            if let detail {
                Text(detail)
                    .font(Theme.caption(13))
                    .foregroundColor(Theme.secondaryText)
            }
        }
        .padding(.vertical, 3)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 42))
                .foregroundColor(Theme.muted)

            Text("Talk about what you're reading")
                .font(Theme.serifTitle(21))
                .foregroundColor(Theme.primaryText)

            Text("Search for a book or an author above, then ask anything — themes, a passage that stuck with you, where to go next.")
                .font(Theme.body(15))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
    }

    // MARK: - Data

    private var libraryBooks: [Book] {
        library.entries.compactMap(\.book)
    }

    /// Google Books has no author entity, so authors are derived from the
    /// volumes that came back — searching a title surfaces its author too,
    /// which is what makes one field cover both.
    private var discoveredAuthors: [String] {
        var seen = Set<String>()
        return results.map(\.primaryAuthor).filter { name in
            !name.isEmpty
                && name != "Unknown Author"
                && seen.insert(name.lowercased()).inserted
        }
        .prefix(6)
        .map { $0 }
    }

    /// True when the query reads like a person's name rather than a title —
    /// i.e. it matches one of the authors that came back.
    private var queryLooksLikeAuthor: Bool {
        let text = trimmedQuery.lowercased()
        guard text.count >= 3 else { return false }
        return discoveredAuthors.contains { $0.lowercased().contains(text) }
    }

    // MARK: - Actions

    private func open(_ subject: ChatSubject) {
        openedConversation = store.conversation(for: subject)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let text = trimmedQuery
        guard text.count >= 2 else {
            results = []
            isSearching = false
            searchFailed = false
            return
        }

        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            isSearching = true
            searchFailed = false
            defer { isSearching = false }

            do {
                // Feed filters off: someone looking up the book in their hand
                // shouldn't be blocked by a missing cover or a short blurb.
                let found = try await GoogleBooksService.shared.searchBooks(
                    query: text,
                    maxResults: 20,
                    applyFeedFilters: false
                )
                guard !Task.isCancelled else { return }

                var seen = Set<String>()
                results = found.filter { seen.insert($0.id).inserted }
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                searchFailed = true
            }
        }
    }
}

/// Small cover/initial badge used in lists and the chat header.
struct SubjectThumbnail: View {
    let subject: ChatSubject
    var size: CGSize = CGSize(width: 40, height: 58)

    var body: some View {
        Group {
            if subject.kind == .author {
                Circle()
                    .fill(Theme.parchment)
                    .overlay {
                        Text(subject.name.prefix(1).uppercased())
                            .font(Theme.serifBold(17))
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
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
