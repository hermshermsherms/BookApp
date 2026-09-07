import SwiftUI

/// The "Understand" pane: catch-me-up recap, character cards and a plot
/// timeline, each generated on demand and gated behind where the reader is.
struct UnderstandPane: View {
    @ObservedObject var viewModel: BuddyViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !viewModel.hasProgress {
                    CatchMeUpCard(viewModel: viewModel)
                }

                StudyToolCard(
                    viewModel: viewModel,
                    kind: .recap,
                    title: "Catch me up",
                    subtitle: "What's happened so far, up to where you are",
                    systemImage: "arrow.counterclockwise.circle"
                ) {
                    if let recap = viewModel.recap {
                        RecapContent(recap: recap, viewModel: viewModel)
                    }
                }

                StudyToolCard(
                    viewModel: viewModel,
                    kind: .characters,
                    title: "Who's who",
                    subtitle: "The cast you've met, and how they connect",
                    systemImage: "person.2"
                ) {
                    if let characters = viewModel.characters {
                        CharacterList(characters: characters, viewModel: viewModel)
                    }
                }

                StudyToolCard(
                    viewModel: viewModel,
                    kind: .timeline,
                    title: "Plot so far",
                    subtitle: "The beats in order, stopping where you are",
                    systemImage: "chart.line.uptrend.xyaxis"
                ) {
                    if let timeline = viewModel.timeline {
                        TimelineContent(beats: timeline, viewModel: viewModel)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}

/// The "Discuss" pane: seminar-style questions, tapped to open in chat.
struct DiscussPane: View {
    @ObservedObject var viewModel: BuddyViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !viewModel.hasProgress, viewModel.subject.kind == .book {
                    CatchMeUpCard(viewModel: viewModel)
                }

                StudyToolCard(
                    viewModel: viewModel,
                    kind: .starters,
                    title: "Worth arguing about",
                    subtitle: viewModel.subject.kind == .book
                        ? "Questions pitched at where you are"
                        : "Questions about their body of work",
                    systemImage: "quote.opening"
                ) {
                    if let starters = viewModel.starters {
                        VStack(spacing: 10) {
                            ForEach(starters) { starter in
                                StarterCard(starter: starter) {
                                    viewModel.discuss(starter)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}

// MARK: - Tool container

/// One generated section: its header, its generate/refresh controls, and
/// whatever it produced. Keeps the empty, loading, failed, stale and loaded
/// states in one place so the three tools behave identically.
private struct StudyToolCard<Content: View>: View {
    @ObservedObject var viewModel: BuddyViewModel
    let kind: StudyKind
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder var content: Content

    private var isGenerating: Bool { viewModel.isGenerating(kind) }
    private var hasContent: Bool { viewModel.hasContent(kind) }

    /// A recap, cast list or timeline "up to nowhere" is worse than useless, so
    /// these stay locked until the reader has said where they are. Discussion
    /// starters don't: the prompt keeps them inside the book's opening stretch.
    private var isBlockedOnProgress: Bool {
        kind != .starters && !viewModel.hasProgress
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let error = viewModel.error(for: kind) {
                Text(error)
                    .font(Theme.caption(13))
                    .foregroundColor(Theme.negative)
            }

            if isGenerating && !hasContent {
                GeneratingRow(title: title)
            } else if hasContent {
                if viewModel.isStale(kind) { staleNotice }
                content
            } else if viewModel.error(for: kind) == nil {
                Text(isBlockedOnProgress
                     ? "\(subtitle). Tell the buddy where you are first — it can't keep spoilers out otherwise."
                     : subtitle)
                    .font(Theme.caption(13))
                    .foregroundColor(Theme.secondaryText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                .stroke(Theme.parchment, lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.accent)

            Text(title)
                .font(Theme.serifBold(17))
                .foregroundColor(Theme.primaryText)

            Spacer(minLength: 8)

            if isGenerating {
                ProgressView().controlSize(.small)
            } else if hasContent {
                Button { viewModel.loadStudy(kind, force: true) } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Regenerate \(title)")
            } else {
                Button { viewModel.loadStudy(kind) } label: {
                    Text(viewModel.error(for: kind) == nil ? "Generate" : "Try again")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(
                            isBlockedOnProgress ? Theme.muted : Theme.accent
                        ))
                }
                .buttonStyle(.plain)
                .disabled(isBlockedOnProgress)
            }
        }
    }

    private var staleNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .semibold))
            Text("You've moved since this was made.")
                .font(Theme.caption(12))
            Button("Update") { viewModel.loadStudy(kind, force: true) }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundColor(Theme.accent)
            Spacer(minLength: 0)
        }
        .foregroundColor(Theme.secondaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.parchment.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
    }
}

private struct GeneratingRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Text("Working through the book…")
                .font(Theme.caption(13))
                .foregroundColor(Theme.secondaryText)
            Spacer(minLength: 0)
        }
        .accessibilityLabel("Generating \(title)")
    }
}

// MARK: - Progress

/// Shown when the buddy doesn't know where the reader is. Nothing under
/// Understand can be spoiler-safe until this is answered, so it asks first
/// rather than generating something and hedging.
private struct CatchMeUpCard: View {
    @ObservedObject var viewModel: BuddyViewModel
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where are you in it?")
                .font(Theme.serifBold(17))
                .foregroundColor(Theme.primaryText)

            Text("A chapter or part number if you have one — otherwise the last thing you remember happening. Everything here stops at whatever you say.")
                .font(Theme.caption(13))
                .foregroundColor(Theme.secondaryText)

            HStack(spacing: 8) {
                TextField("e.g. end of chapter 12", text: $draft)
                    .font(Theme.body(14))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(Theme.background)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                    .submitLabel(.done)
                    .onSubmit { save() }

                Button("Save") { save() }
                    .font(.system(size: 13, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(
                        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Theme.muted : Theme.accent
                    ))
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.parchment.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
    }

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.setProgress(trimmed)
        draft = ""
    }
}

// MARK: - Recap

private struct RecapContent: View {
    let recap: Recap
    @ObservedObject var viewModel: BuddyViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !recap.position.isEmpty {
                Label(recap.position, systemImage: "bookmark.fill")
                    .font(Theme.caption(12))
                    .foregroundColor(Theme.secondaryText)
            }

            ForEach(Array(recap.summary.enumerated()), id: \.offset) { entry in
                Text(entry.element)
                    .font(Theme.body(15))
                    .foregroundColor(Theme.primaryText)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }

            if !recap.openThreads.isEmpty {
                NoteGroup(
                    title: "Still open",
                    systemImage: "questionmark.circle",
                    notes: recap.openThreads,
                    viewModel: viewModel
                )
            }

            if !recap.worthRemembering.isEmpty {
                NoteGroup(
                    title: "Worth remembering",
                    systemImage: "pin",
                    notes: recap.worthRemembering,
                    viewModel: viewModel
                )
            }
        }
    }
}

private struct NoteGroup: View {
    let title: String
    let systemImage: String
    let notes: [StudyNote]
    @ObservedObject var viewModel: BuddyViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(Theme.caption(12).weight(.semibold))
                .foregroundColor(Theme.muted)

            ForEach(notes) { note in
                Button { viewModel.discuss(note) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(note.title)
                            .font(Theme.body(14).weight(.semibold))
                            .foregroundColor(Theme.primaryText)
                        Text(note.detail)
                            .font(Theme.caption(13))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Theme.background)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Characters

private struct CharacterList: View {
    let characters: [CharacterProfile]
    @ObservedObject var viewModel: BuddyViewModel

    var body: some View {
        VStack(spacing: 10) {
            ForEach(characters) { character in
                CharacterCard(character: character) {
                    viewModel.discuss(character)
                }
            }
        }
    }
}

private struct CharacterCard: View {
    let character: CharacterProfile
    let onDiscuss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.parchment)
                    .frame(width: 34, height: 34)
                    .overlay {
                        Text(character.name.prefix(1).uppercased())
                            .font(Theme.serifBold(15))
                            .foregroundColor(Theme.accent)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(character.name)
                        .font(Theme.body(15).weight(.semibold))
                        .foregroundColor(Theme.primaryText)
                    Text(character.role)
                        .font(Theme.caption(12))
                        .foregroundColor(Theme.secondaryText)
                }
                Spacer(minLength: 0)
            }

            Text(character.summary)
                .font(Theme.caption(13))
                .foregroundColor(Theme.primaryText)
                .lineSpacing(2)

            if !character.relationships.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(character.relationships, id: \.self) { relationship in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.muted)
                                .padding(.top, 2)
                            Text(relationship)
                                .font(Theme.caption(12))
                                .foregroundColor(Theme.secondaryText)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                if !character.lastSeen.isEmpty {
                    Text(character.lastSeen)
                        .font(Theme.caption(11))
                        .foregroundColor(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(action: onDiscuss) {
                    Label("Discuss", systemImage: "bubble.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
    }
}

// MARK: - Timeline

private struct TimelineContent: View {
    let beats: [TimelineBeat]
    @ObservedObject var viewModel: BuddyViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(beats.enumerated()), id: \.element.id) { entry in
                TimelineRow(
                    beat: entry.element,
                    isFirst: entry.offset == 0,
                    isLast: entry.offset == beats.count - 1
                ) {
                    viewModel.discuss(entry.element)
                }
            }

            // The rail continues past the last beat to show it stops at the
            // reader, not at the end of the book.
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(Theme.parchment)
                            .frame(width: 3, height: 3)
                            .padding(.vertical, 2)
                    }
                }
                .frame(width: 14)

                Text("You're here")
                    .font(Theme.caption(12).weight(.semibold))
                    .foregroundColor(Theme.muted)
                    .padding(.top, -2)
            }
            .padding(.top, 4)
        }
    }
}

private struct TimelineRow: View {
    let beat: TimelineBeat
    let isFirst: Bool
    let isLast: Bool
    let onDiscuss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            rail
            beatContent
        }
    }

    private var rail: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(isFirst ? Color.clear : Theme.parchment)
                .frame(width: 2, height: 6)

            Circle()
                .fill(beat.isTurningPoint ? Theme.accent : Theme.cardBackground)
                .frame(width: 11, height: 11)
                .overlay {
                    Circle().stroke(
                        beat.isTurningPoint ? Theme.accent : Theme.muted,
                        lineWidth: 2
                    )
                }

            Rectangle()
                .fill(isLast ? Color.clear : Theme.parchment)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 14)
    }

    private var beatContent: some View {
        Button(action: onDiscuss) {
            VStack(alignment: .leading, spacing: 3) {
                Text(beat.marker.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(beat.isTurningPoint ? Theme.accent : Theme.muted)

                Text(beat.title)
                    .font(Theme.body(14).weight(.semibold))
                    .foregroundColor(Theme.primaryText)

                Text(beat.detail)
                    .font(Theme.caption(13))
                    .foregroundColor(Theme.secondaryText)
                    .lineSpacing(2)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Discussion

private struct StarterCard: View {
    let starter: DiscussionStarter
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 7) {
                Label(starter.resolvedAngle.rawValue, systemImage: starter.resolvedAngle.iconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.accent)

                Text(starter.question)
                    .font(Theme.body(15))
                    .foregroundColor(Theme.primaryText)
                    .lineSpacing(2)

                Text(starter.why)
                    .font(Theme.caption(12))
                    .foregroundColor(Theme.secondaryText)

                Label("Take this into the chat", systemImage: "arrow.turn.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.muted)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
        }
        .buttonStyle(.plain)
    }
}
