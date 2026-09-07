import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel: BuddyViewModel
    @StateObject private var voice = VoiceController()

    @State private var isEditingProgress = false
    @State private var progressDraft = ""
    @State private var isInVoiceMode = false

    init(conversation: Conversation) {
        _viewModel = StateObject(wrappedValue: BuddyViewModel(conversation: conversation))
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                transcriptList
                composer
            }
        }
        .navigationTitle(viewModel.subject.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Where are you in it?", isPresented: $isEditingProgress) {
            TextField("e.g. halfway, or chapter 12", text: $progressDraft)
            Button("Save") { viewModel.setProgress(progressDraft) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The buddy keeps spoilers behind wherever you are.")
        }
        .onChange(of: voice.transcript) { newValue in
            // Live dictation feeds the composer so it can still be edited. In
            // voice mode the same controller is listening, but that transcript
            // belongs to the call, not to the composer.
            if voice.isListening, !isInVoiceMode { viewModel.draft = newValue }
        }
        .fullScreenCover(isPresented: $isInVoiceMode) {
            // Same view model and same audio controller, so the spoken turns land
            // in this transcript and only one thing ever owns the microphone.
            VoiceModeView(buddy: viewModel, voice: voice)
        }
        .onChange(of: viewModel.lastCompletedReply) { reply in
            // Voice mode does its own speaking, sentence by sentence.
            guard let reply, voice.speakRepliesAloud, !isInVoiceMode else { return }
            voice.speak(reply)
            viewModel.lastCompletedReply = nil
        }
        .onDisappear {
            voice.stopListening()
            voice.stopSpeaking()
            viewModel.cancel()
        }
    }

    // MARK: - Transcript

    private var transcriptList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    header

                    if viewModel.messages.isEmpty {
                        openers
                    }

                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if viewModel.isStreaming {
                        ThinkingIndicator()
                            .id(Self.streamAnchor)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .onChange(of: viewModel.messages.last?.text) { _ in
                scrollToEnd(proxy)
            }
            .onChange(of: viewModel.messages.count) { _ in
                scrollToEnd(proxy)
            }
            .onChange(of: viewModel.isStreaming) { _ in
                scrollToEnd(proxy)
            }
        }
    }

    private static let streamAnchor = "stream-anchor"

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        let target: AnyHashable? = viewModel.isStreaming
            ? Self.streamAnchor
            : viewModel.messages.last?.id
        guard let target else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            SubjectThumbnail(subject: viewModel.subject, size: CGSize(width: 46, height: 66))

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.subject.name)
                    .font(Theme.serifBold(18))
                    .foregroundColor(Theme.primaryText)
                Text(viewModel.subject.subtitle)
                    .font(Theme.caption(13))
                    .foregroundColor(Theme.secondaryText)

                Button {
                    progressDraft = viewModel.conversation.progressNote ?? ""
                    isEditingProgress = true
                } label: {
                    Label(
                        viewModel.conversation.progressNote.map { "You're at: \($0)" }
                            ?? "Set where you are",
                        systemImage: "bookmark"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.bottom, 6)
    }

    private var openers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try asking")
                .font(Theme.caption(12).weight(.semibold))
                .foregroundColor(Theme.muted)

            ForEach(viewModel.suggestedOpeners, id: \.self) { opener in
                Button { viewModel.send(opener) } label: {
                    Text(opener)
                        .font(Theme.body(14))
                        .foregroundColor(Theme.primaryText)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                                .stroke(Theme.parchment, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 6) {
            if voice.isListening {
                Label("Listening…", systemImage: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }

            HStack(spacing: 10) {
                micButton

                TextField("Ask about this book…", text: $viewModel.draft, axis: .vertical)
                    .font(Theme.body(15))
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                sendButton
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            .padding(.top, 4)
        }
        .background(Theme.background)
    }

    private var micButton: some View {
        Button {
            Task { @MainActor in
                if voice.isListening {
                    voice.stopListening()
                } else {
                    await voice.startListening()
                }
            }
        } label: {
            Image(systemName: voice.isListening ? "stop.circle.fill" : "mic.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(voice.isListening ? Theme.negative : Theme.secondaryText)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isStreaming)
        .accessibilityLabel(voice.isListening ? "Stop dictating" : "Dictate a question")
    }

    private var sendButton: some View {
        Button {
            if voice.isListening { voice.stopListening() }
            if viewModel.isStreaming { viewModel.cancel() } else { viewModel.send() }
        } label: {
            Image(systemName: viewModel.isStreaming ? "stop.fill" : "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(
                        viewModel.isStreaming || viewModel.canSend ? Theme.accent : Theme.muted
                    )
                )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSend && !viewModel.isStreaming)
        .accessibilityLabel(viewModel.isStreaming ? "Stop" : "Send")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                voice.stopListening()
                voice.stopSpeaking()
                isInVoiceMode = true
            } label: {
                Image(systemName: "waveform.circle.fill")
            }
            .tint(Theme.accent)
            .accessibilityLabel("Start a voice conversation")
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                voice.speakRepliesAloud.toggle()
                if !voice.speakRepliesAloud { voice.stopSpeaking() }
            } label: {
                Image(systemName: voice.speakRepliesAloud
                      ? "speaker.wave.2.fill"
                      : "speaker.slash.fill")
            }
            .tint(voice.speakRepliesAloud ? Theme.accent : Theme.muted)
            .accessibilityLabel(voice.speakRepliesAloud ? "Stop reading replies aloud" : "Read replies aloud")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil || voice.errorMessage != nil },
            set: { presented in
                if !presented {
                    viewModel.errorMessage = nil
                    voice.errorMessage = nil
                }
            }
        )
    }
}

// MARK: - Pieces

private struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 44) }

            Text(message.text)
                .font(Theme.body(15))
                .foregroundColor(isUser ? .white : Theme.primaryText)
                .lineSpacing(2)
                .textSelection(.enabled)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(isUser ? Theme.accent : Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if !isUser { Spacer(minLength: 44) }
        }
    }
}

private struct ThinkingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.muted)
                    .frame(width: 6, height: 6)
                    .opacity(isAnimating ? 1 : 0.3)
                    .scaleEffect(isAnimating ? 1 : 0.6)
                    // Staggered delays give the three dots their travelling pulse.
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.18),
                        value: isAnimating
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear { isAnimating = true }
        .accessibilityLabel("Thinking")
    }
}
