import Foundation

/// Where the reader is inside a conversation: the transcript, the comprehension
/// tools, or the discussion prompts. Chat stays the default — the study tools
/// are something you step into and then bring back into the conversation.
enum BuddyTab: String, CaseIterable, Identifiable {
    case chat
    case understand
    case discuss

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .understand: return "Understand"
        case .discuss: return "Discuss"
        }
    }
}

/// The four things the buddy can generate on demand. Each is fetched, cached
/// and invalidated separately, because they cost a model call apiece and the
/// reader rarely wants all four at once.
enum StudyKind: String, CaseIterable, Identifiable, Codable {
    case recap
    case characters
    case timeline
    case starters

    var id: String { rawValue }

    /// Only makes sense for a book — an author's body of work has no plot to
    /// recap or timeline. Author conversations get discussion starters only.
    var appliesToAuthors: Bool { self == .starters }
}

// MARK: - Payloads

/// "Catch me up": what has happened through the reader's current point.
struct Recap: Codable, Hashable {
    /// The buddy's restatement of where it understands the reader to be. Shown
    /// back so a misread position is obvious before the recap is trusted.
    let position: String
    /// Two to four short paragraphs of story so far.
    let summary: [String]
    /// Questions the book has opened and not yet answered.
    let openThreads: [StudyNote]
    /// Small details that are easy to lose but pay off later.
    let worthRemembering: [StudyNote]
}

struct StudyNote: Codable, Hashable, Identifiable {
    let title: String
    let detail: String

    var id: String { title }
}

/// A spoiler-gated dossier on one character.
struct CharacterProfile: Codable, Hashable, Identifiable {
    let name: String
    /// Short label — "the narrator's brother", "ship's captain".
    let role: String
    let summary: String
    /// One line per relationship, e.g. "Ahab — serves under him, uneasily".
    let relationships: [String]
    /// Where they last turned up, relative to the reader's position.
    let lastSeen: String

    var id: String { name }
}

/// One beat on the plot timeline, up to the reader's current point.
struct TimelineBeat: Codable, Hashable, Identifiable {
    /// Chapter or section pointer, e.g. "Ch. 4" or "Part One, opening".
    let marker: String
    let title: String
    let detail: String
    /// Beats that changed the book's direction get a filled marker.
    let isTurningPoint: Bool

    var id: String { marker + title }
}

/// A seminar-style question to chew on, with the angle it comes from.
struct DiscussionStarter: Codable, Hashable, Identifiable {
    let question: String
    /// One of `Angle`'s raw values — kept as a string because it comes back
    /// from the model and an unknown value shouldn't fail the whole decode.
    let angle: String
    /// Why this question is worth asking of this book, at this point.
    let why: String

    var id: String { question }

    enum Angle: String, CaseIterable {
        case theme = "Theme"
        case character = "Character"
        case craft = "Craft"
        case structure = "Structure"
        case context = "Context"
        case personal = "Personal"

        var iconName: String {
            switch self {
            case .theme: return "lightbulb"
            case .character: return "person.2"
            case .craft: return "pencil.and.outline"
            case .structure: return "square.stack.3d.up"
            case .context: return "globe"
            case .personal: return "heart"
            }
        }
    }

    var resolvedAngle: Angle { Angle(rawValue: angle) ?? .theme }
}

// MARK: - Caching

/// A generated result plus the reader position it was generated for, so the UI
/// can say "this is from before you moved on" instead of quietly going stale.
struct StudyResult<Value: Codable & Hashable>: Codable, Hashable {
    var value: Value
    /// Normalized `progressNote` at generation time.
    var progressSignature: String
    var generatedAt: Date
}

/// Everything generated for one conversation, persisted alongside it.
struct StudyCache: Codable, Hashable {
    var recap: StudyResult<Recap>?
    var characters: StudyResult<[CharacterProfile]>?
    var timeline: StudyResult<[TimelineBeat]>?
    var starters: StudyResult<[DiscussionStarter]>?

    /// Normalized form of a progress note, used as the cache key.
    static func signature(for progressNote: String?) -> String {
        progressNote?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }
}
