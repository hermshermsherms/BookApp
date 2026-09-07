import Foundation

/// Generates the buddy's study material: the catch-me-up recap, the character
/// cards, the plot timeline and the discussion starters.
///
/// Each call is a single structured-output request — the API constrains
/// generation to the JSON schema below, so what comes back decodes straight
/// into the card models with no salvage parsing.
actor BuddyStudyService {
    static let shared = BuddyStudyService()

    private let decoder = JSONDecoder()

    private init() {}

    func recap(for conversation: Conversation) async throws -> Recap {
        try await generate(
            system: BuddyPrompt.recapSystem(for: conversation),
            prompt: BuddyPrompt.recapPrompt,
            schema: Schema.recap,
            as: Recap.self
        )
    }

    func characters(for conversation: Conversation) async throws -> [CharacterProfile] {
        try await generate(
            system: BuddyPrompt.charactersSystem(for: conversation),
            prompt: BuddyPrompt.charactersPrompt,
            schema: Schema.characters,
            as: Listed<CharacterProfile>.self
        ).items
    }

    func timeline(for conversation: Conversation) async throws -> [TimelineBeat] {
        try await generate(
            system: BuddyPrompt.timelineSystem(for: conversation),
            prompt: BuddyPrompt.timelinePrompt,
            schema: Schema.timeline,
            as: Listed<TimelineBeat>.self
        ).items
    }

    func starters(for conversation: Conversation) async throws -> [DiscussionStarter] {
        try await generate(
            system: BuddyPrompt.startersSystem(for: conversation),
            prompt: BuddyPrompt.startersPrompt(for: conversation.subject),
            schema: Schema.starters,
            as: Listed<DiscussionStarter>.self
        ).items
    }

    /// Reads a reading position out of something the reader typed in chat, or
    /// returns nil when there isn't one. Deliberately cheap: low effort, a
    /// two-field schema, and only called when the position is still unknown.
    func detectProgress(in message: String, subject: ChatSubject) async throws -> String? {
        let found: DetectedProgress = try await generate(
            system: BuddyPrompt.progressCaptureSystem(for: subject),
            prompt: BuddyPrompt.progressCapturePrompt(message: message),
            schema: Schema.progress,
            as: DetectedProgress.self,
            effort: "low"
        )
        let position = found.position.trimmingCharacters(in: .whitespacesAndNewlines)
        return (found.found && !position.isEmpty) ? position : nil
    }

    // MARK: - Plumbing

    private struct DetectedProgress: Decodable {
        let found: Bool
        let position: String
    }

    /// A JSON schema can't have an array at the top level, so every list payload
    /// arrives under one `items` key and is unwrapped here.
    private struct Listed<Item: Decodable>: Decodable {
        let items: [Item]
    }

    private func generate<Value: Decodable>(
        system: String,
        prompt: String,
        schema: String,
        as type: Value.Type,
        effort: String = "high"
    ) async throws -> Value {
        let data = try await ClaudeService.shared.generateJSON(
            system: system,
            prompt: prompt,
            schemaJSON: schema,
            effort: effort
        )
        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            throw ClaudeError.transport(
                "That came back in a shape the app couldn't read. Try again."
            )
        }
    }

    // MARK: - Schemas
    //
    // Written as JSON literals rather than nested dictionaries: they're easier
    // to read against the model structs, and they stay `Sendable` when handed
    // across to `ClaudeService`.

    private enum Schema {
        static let recap = """
        {
          "type": "object",
          "properties": {
            "position": { "type": "string" },
            "summary": { "type": "array", "items": { "type": "string" } },
            "openThreads": { "type": "array", "items": \(note) },
            "worthRemembering": { "type": "array", "items": \(note) }
          },
          "required": ["position", "summary", "openThreads", "worthRemembering"],
          "additionalProperties": false
        }
        """

        static let characters = list(of: """
        {
          "type": "object",
          "properties": {
            "name": { "type": "string" },
            "role": { "type": "string" },
            "summary": { "type": "string" },
            "relationships": { "type": "array", "items": { "type": "string" } },
            "lastSeen": { "type": "string" }
          },
          "required": ["name", "role", "summary", "relationships", "lastSeen"],
          "additionalProperties": false
        }
        """)

        static let timeline = list(of: """
        {
          "type": "object",
          "properties": {
            "marker": { "type": "string" },
            "title": { "type": "string" },
            "detail": { "type": "string" },
            "isTurningPoint": { "type": "boolean" }
          },
          "required": ["marker", "title", "detail", "isTurningPoint"],
          "additionalProperties": false
        }
        """)

        static let starters = list(of: """
        {
          "type": "object",
          "properties": {
            "question": { "type": "string" },
            "angle": { "type": "string", "enum": [\(angles)] },
            "why": { "type": "string" }
          },
          "required": ["question", "angle", "why"],
          "additionalProperties": false
        }
        """)

        static let progress = """
        {
          "type": "object",
          "properties": {
            "found": { "type": "boolean" },
            "position": { "type": "string" }
          },
          "required": ["found", "position"],
          "additionalProperties": false
        }
        """

        private static let note = """
        {
          "type": "object",
          "properties": {
            "title": { "type": "string" },
            "detail": { "type": "string" }
          },
          "required": ["title", "detail"],
          "additionalProperties": false
        }
        """

        private static let angles = DiscussionStarter.Angle.allCases
            .map { "\"\($0.rawValue)\"" }
            .joined(separator: ", ")

        private static func list(of item: String) -> String {
            """
            {
              "type": "object",
              "properties": {
                "items": { "type": "array", "items": \(item) }
              },
              "required": ["items"],
              "additionalProperties": false
            }
            """
        }
    }
}
