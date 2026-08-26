import Foundation

enum ClaudeError: LocalizedError {
    case missingAPIKey
    case http(status: Int, message: String)
    case refused(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No Anthropic API key configured. Add ANTHROPIC_API_KEY to Secrets.swift."
        case .http(let status, let message):
            return "Claude API error \(status): \(message)"
        case .refused(let category):
            return "Claude declined to answer that one\(category.isEmpty ? "" : " (\(category))"). Try rephrasing."
        case .transport(let message):
            return message
        }
    }
}

/// Streaming client for the Claude Messages API.
///
/// Swift has no official Anthropic SDK, so this talks raw HTTP to
/// `POST /v1/messages` with `stream: true` and parses the Server-Sent Events
/// itself. Streaming matters here for feel — replies start appearing in the
/// chat immediately instead of after a multi-second pause.
actor ClaudeService {
    static let shared = ClaudeService()

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-opus-5"
    private let apiVersion = "2023-06-01"

    /// Opt-in server-side fallback: if a safety classifier declines the request,
    /// the API re-runs it on a fallback model inside the same call rather than
    /// returning nothing. Routed by category, so there is no model list to keep.
    private let fallbackBeta = "server-side-fallback-2026-07-01"

    private init() {}

    /// Streams the assistant's reply as it is generated. Each yielded value is
    /// an incremental chunk of text to append, not the full message.
    func streamReply(
        system: String,
        history: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.stream(system: system, history: history) { chunk in
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func stream(
        system: String,
        history: [ChatMessage],
        onChunk: @Sendable (String) -> Void
    ) async throws {
        guard let apiKey = Config.Anthropic.apiKey else {
            throw ClaudeError.missingAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "stream": true,
            "system": system,
            "messages": history.map { ["role": $0.role.rawValue, "content": $0.text] },
            // Adaptive thinking is on by default for this model; `medium` effort
            // keeps replies conversational and quick rather than essay-length.
            // Raise to "high" if you want deeper literary analysis per turn.
            "thinking": ["type": "adaptive"],
            "output_config": ["effort": "medium"],
            "fallbacks": "default"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            // The body is the error JSON; drain it so the message is useful.
            var raw = Data()
            for try await byte in bytes { raw.append(byte) }
            throw ClaudeError.http(status: http.statusCode, message: Self.errorMessage(from: raw))
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty, payload != "[DONE]",
                  let data = payload.data(using: .utf8),
                  let event = try? JSONDecoder().decode(StreamEvent.self, from: data) else {
                continue
            }

            switch event.type {
            case "content_block_delta":
                // Thinking blocks also arrive as deltas; only text is displayed.
                if event.delta?.type == "text_delta", let text = event.delta?.text {
                    onChunk(text)
                }
            case "message_delta":
                if event.delta?.stopReason == "refusal" {
                    throw ClaudeError.refused(event.delta?.stopDetails?.category ?? "")
                }
            case "error":
                throw ClaudeError.transport(event.error?.message ?? "The stream failed.")
            default:
                break
            }
        }
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return String(data: data, encoding: .utf8) ?? "Unknown error"
        }
        return message
    }

    // MARK: - Wire types

    private struct StreamEvent: Decodable {
        let type: String
        let delta: Delta?
        let error: APIError?

        struct Delta: Decodable {
            let type: String?
            let text: String?
            let stopReason: String?
            let stopDetails: StopDetails?

            enum CodingKeys: String, CodingKey {
                case type, text
                case stopReason = "stop_reason"
                case stopDetails = "stop_details"
            }
        }

        struct StopDetails: Decodable {
            let category: String?
        }

        struct APIError: Decodable {
            let type: String?
            let message: String?
        }
    }
}
