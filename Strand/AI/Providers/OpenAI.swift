import Foundation
import StrandAnalytics

struct OpenAIClient: AIProviderClient {

    func send(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        session: URLSession
    ) async throws -> String {
        var wire: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        for m in messages { wire.append(["role": m.role.rawValue, "content": m.content]) }

        // Standard params first (gpt-4 family). Newer/reasoning models reject `temperature` and want
        // `max_completion_tokens`; if the provider 400s about either, retry with the modern shape.
        do {
            return try await chat(key: key, model: model, wire: wire, modernParams: false, session: session)
        } catch let AICoachError.server(code, detail) where code == 400 {
            let d = detail.lowercased()
            if d.contains("max_completion_tokens") || d.contains("max_tokens")
                || d.contains("temperature") || d.contains("unsupported") {
                return try await chat(key: key, model: model, wire: wire, modernParams: true, session: session)
            }
            throw AICoachError.server(code, detail)
        }
    }

    /// K1: Stream via `stream: true`. Same body as `send`, with `stream: true` added. SSE parsing
    /// via `SseDeltas.openAiDelta`. The modern-params retry on 400 is NOT streamed (rare path;
    /// falls back to `send`'s retry). Byte-parity pin in `SseDeltasTests.openAiReassembleMatchesFullReply`.
    func stream(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        session: URLSession,
        onDelta: (String) -> Void
    ) async throws {
        var wire: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        for m in messages { wire.append(["role": m.role.rawValue, "content": m.content]) }

        var body: [String: Any] = ["model": model, "messages": wire, "stream": true]
        body["temperature"] = 0.6
        body["max_tokens"] = 4096

        let req = try request(body, key: key)

        try await performStreamingRequest(req, session: session) { payload in
            if let delta = SseDeltas.openAiDelta(payload) {
                onDelta(delta)
            }
        }
    }

    func fetchModels(key: String, session: URLSession) async throws -> [String] {
        var req = URLRequest(url: AIProvider.openAI.modelsEndpoint)
        req.httpMethod = "GET"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        return parseModels(try await performRequest(req, session: session))
    }

    /// Pure: unwrap the `/models` body into chat-capable ids (gpt*/o*). No network — unit-tested.
    func parseModels(_ json: [String: Any]) -> [String] {
        guard let list = json["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { row in
            guard let id = row["id"] as? String, !id.isEmpty else { return nil }
            return (id.hasPrefix("gpt") || id.hasPrefix("o")) ? id : nil
        }
    }

    /// Fork: one structured-output vision call — `prompt` plus JPEG page images, the reply constrained to
    /// `schema` (OpenAI `json_schema`, strict). Returns the reply's JSON text. Used by the lab-report scan;
    /// modern params only (every vision-capable model accepts `max_completion_tokens`), a long timeout because
    /// a multi-page report can take a minute or more.
    func extractJSON(
        key: String,
        model: String,
        systemPrompt: String,
        prompt: String,
        jpegImages: [Data],
        schemaName: String,
        schema: [String: Any],
        session: URLSession
    ) async throws -> String {
        var content: [[String: Any]] = [["type": "text", "text": prompt]]
        for jpeg in jpegImages {
            content.append(["type": "image_url",
                            "image_url": ["url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())", "detail": "high"]])
        }
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": systemPrompt], ["role": "user", "content": content]],
            "max_completion_tokens": 16384,
            "response_format": ["type": "json_schema",
                                "json_schema": ["name": schemaName, "strict": true, "schema": schema]],
        ]
        var req = try request(body, key: key)
        req.timeoutInterval = 240
        let json = try await performRequest(req, session: session)
        if let refusal = firstMessage(json)?["refusal"] as? String, !refusal.isEmpty {
            throw AICoachError.emptyReply("The model declined: \(refusal)")
        }
        guard let text = replyText(json) else { throw emptyReplyError(json) }
        return text
    }

    // MARK: Private

    private func request(_ body: [String: Any], key: String) throws -> URLRequest {
        var req = URLRequest(url: AIProvider.openAI.endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private func firstMessage(_ json: [String: Any]) -> [String: Any]? {
        ((json["choices"] as? [[String: Any]])?.first)?["message"] as? [String: Any]
    }

    /// The first choice's trimmed, non-empty text, or nil.
    private func replyText(_ json: [String: Any]) -> String? {
        guard let content = (firstMessage(json)?["content"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else { return nil }
        return content
    }

    /// `modernParams`: use `max_completion_tokens`, drop `temperature` — required by reasoning models.
    private func chat(
        key: String,
        model: String,
        wire: [[String: Any]],
        modernParams: Bool,
        session: URLSession
    ) async throws -> String {
        var body: [String: Any] = ["model": model, "messages": wire]
        // #1074: 900 truncated detailed coaching replies mid-sentence; 4096 lets a full multi-section
        // reply complete (a cap, not a target — the system prompt keeps it short). Matches Gemini + Android.
        if modernParams {
            body["max_completion_tokens"] = 4096
        } else {
            body["temperature"] = 0.6
            body["max_tokens"] = 4096
        }

        let json = try await performRequest(try request(body, key: key), session: session)
        guard let content = replyText(json) else {
            throw emptyReplyError(json)   // #1074: surface the provider's real error if the 200 body has one
        }
        return content
    }
}
