import SwiftUI

/// The hands-free conversation: talk, pause, hear an answer, talk again.
///
/// Presented over the chat and driven by the same view model, so anything said
/// here is in the transcript when it's dismissed. The mic never runs while the
/// buddy is talking — one tap hands the turn back — because the recogniser has
/// no echo cancellation and would otherwise transcribe the synthesizer.
struct VoiceModeView: View {
    @StateObject private var session: VoiceConversationViewModel
    /// Observed directly as well as through the session: the level meter and the
    /// live transcript both live on the controller, and the view has to redraw
    /// when they change.
    @ObservedObject private var voice: VoiceController
    @Environment(\.dismiss) private var dismiss

    init(buddy: BuddyViewModel, voice: VoiceController) {
        _voice = ObservedObject(wrappedValue: voice)
        _session = StateObject(
            wrappedValue: VoiceConversationViewModel(buddy: buddy, voice: voice)
        )
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 8)
                orb
                Spacer(minLength: 8)
                captions
                Spacer(minLength: 8)
                controls
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 26)
        }
        .task { await session.start() }
        .onDisappear { session.end() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.cardBackground))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to the chat")

            VStack(alignment: .leading, spacing: 2) {
                Text(session.subject.name)
                    .font(Theme.serifBold(17))
                    .foregroundColor(Theme.primaryText)
                    .lineLimit(1)
                Text("Voice conversation")
                    .font(Theme.caption(12))
                    .foregroundColor(Theme.muted)
            }

            Spacer()

            SubjectThumbnail(subject: session.subject, size: CGSize(width: 32, height: 46))
        }
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Orb

    private var orb: some View {
        VStack(spacing: 18) {
            VoiceOrb(
                level: voice.inputLevel,
                isListening: session.phase == .listening,
                isActive: session.phase == .speaking || session.phase == .thinking
            )

            Text(statusText)
                .font(Theme.caption(14).weight(.semibold))
                .foregroundColor(statusColor)
                .animation(.easeInOut(duration: 0.2), value: statusText)
        }
    }

    private var statusText: String {
        switch session.phase {
        case .starting: return "Getting the mic ready…"
        case .listening: return "Listening"
        case .thinking: return "Thinking"
        case .speaking: return "Talking"
        case .paused: return session.didTimeOut ? "Paused — I stopped listening" : "Paused"
        case .failed: return "Voice mode stopped"
        }
    }

    private var statusColor: Color {
        switch session.phase {
        case .listening, .speaking: return Theme.accent
        case .failed: return Theme.negative
        default: return Theme.muted
        }
    }

    // MARK: - Captions

    @ViewBuilder
    private var captions: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                if case .failed(let message) = session.phase {
                    caption(message, color: Theme.negative, weight: .semibold)
                }

                let heard = session.phase == .listening
                    ? voice.transcript
                    : session.heardText
                if !heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    caption("You: \(heard)", color: Theme.secondaryText, weight: .regular)
                }

                if !session.replyText.isEmpty {
                    caption(session.replyText, color: Theme.primaryText, weight: .regular)
                }

                if session.isIdleAtStart, session.phase == .listening {
                    starters
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 220)
    }

    private func caption(_ text: String, color: Color, weight: Font.Weight) -> some View {
        Text(text)
            .font(Theme.body(16).weight(weight))
            .foregroundColor(color)
            .lineSpacing(3)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var starters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Say something like")
                .font(Theme.caption(12).weight(.semibold))
                .foregroundColor(Theme.muted)

            ForEach(session.prompts, id: \.self) { prompt in
                Button { session.send(prompt) } label: {
                    Text(prompt)
                        .font(Theme.body(14))
                        .foregroundColor(Theme.primaryText)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 34) {
                secondaryButton(
                    icon: "text.bubble",
                    label: "Chat",
                    action: { dismiss() }
                )

                Button {
                    Task { await session.takeTurn() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(primaryButtonColor)
                            .frame(width: 74, height: 74)
                        Image(systemName: primaryButtonIcon)
                            .font(.system(size: 27, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(primaryButtonLabel)

                secondaryButton(
                    icon: "pause.fill",
                    label: "Pause",
                    action: { session.pause() }
                )
                .disabled(session.phase == .paused)
                .opacity(session.phase == .paused ? 0.4 : 1)
            }

            Text(primaryButtonLabel)
                .font(Theme.caption(12))
                .foregroundColor(Theme.muted)
        }
    }

    private func secondaryButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Theme.cardBackground))
                Text(label)
                    .font(Theme.caption(11))
                    .foregroundColor(Theme.muted)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var primaryButtonIcon: String {
        switch session.phase {
        case .listening: return "checkmark"
        case .speaking, .thinking: return "hand.raised.fill"
        default: return "mic.fill"
        }
    }

    private var primaryButtonColor: Color {
        switch session.phase {
        case .speaking, .thinking: return Theme.warmBrown
        case .failed: return Theme.muted
        default: return Theme.accent
        }
    }

    private var primaryButtonLabel: String {
        switch session.phase {
        case .listening: return "Tap when you're done talking"
        case .speaking: return "Tap to jump in"
        case .thinking: return "Tap to stop and talk"
        case .starting: return "Starting"
        case .failed: return "Try again"
        case .paused: return "Tap to talk"
        }
    }
}

// MARK: - Orb

/// One circle doing three jobs: it swells with the mic level while listening,
/// breathes slowly while the buddy is thinking or talking, and sits still
/// otherwise.
private struct VoiceOrb: View {
    let level: Double
    let isListening: Bool
    let isActive: Bool

    private var scale: CGFloat {
        if isListening { return 1 + CGFloat(min(max(level, 0), 1)) * 0.28 }
        // A constant target plus a repeating animation is what makes it breathe:
        // the value changes once, the animation runs forever.
        return isActive ? 1.08 : 1
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(0.16))
                .frame(width: 190, height: 190)
                .scaleEffect(scale)

            Circle()
                .fill(Theme.accent.opacity(0.26))
                .frame(width: 140, height: 140)
                .scaleEffect(1 + (scale - 1) * 0.6)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Theme.terracotta, Theme.dustyRose],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 96, height: 96)

            Image(systemName: isActive ? "waveform" : "mic.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
        }
        .animation(
            isActive
                ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                : .easeOut(duration: 0.12),
            value: scale
        )
        .accessibilityHidden(true)
    }
}
