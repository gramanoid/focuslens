import Foundation

struct LlamaCppClient: Sendable {
    init() {}
}

enum LlamaCppError: LocalizedError {
    case invalidBaseURL
    case nonLocalhostHost
    case requestFailed(Int)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "The llama.cpp server URL is invalid."
        case .nonLocalhostHost:
            "FocusLens only allows localhost requests."
        case .requestFailed(let code):
            "llama.cpp returned HTTP \(code)."
        case .malformedResponse:
            "FocusLens could not decode the llama.cpp response."
        }
    }
}

extension LlamaCppClient {
    func health(baseURL: URL) async -> Bool {
        guard validate(baseURL: baseURL) else { return false }
        guard let url = URL(string: "/health", relativeTo: baseURL) else { return false }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200 ..< 300).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    func classifyImage(
        _ data: Data,
        baseURL: URL,
        frontmostAppName: String,
        frontmostBundleID: String?,
        keystrokeContext: String? = nil
    ) async throws -> ClassificationResult {
        var promptParts = [
            """
            You are classifying a macOS screenshot to build a work activity log.
            The frontmost app reported by the OS is "\(frontmostAppName)".
            Bundle ID: "\(frontmostBundleID ?? "unknown")".
            Use the OS-reported app name exactly — do not invent or OCR a variant.
            The screenshot shows the full screen. Note visible background apps for context, but classify based on the frontmost app.
            CRITICAL: The "task" field must describe the SPECIFIC content visible on screen. Read the page title, tab name, URL, file name, or visible text to determine what the user is actually doing.
            Good examples: "Reading GitHub PR #142 comments", "Composing email to John in Gmail", "Editing auth.ts in VS Code", "Watching YouTube video about React hooks", "Slack conversation in #engineering channel"
            Bad examples: "Browsing the web", "Work session analysis", "User activity on Chrome", "Mixed work activities" — these are too vague and useless.
            If you truly cannot read any specific content, describe what UI elements you see (e.g., "Chrome with multiple tabs open, content not readable").
            """
        ]

        if let keystrokeContext {
            promptParts.append(keystrokeContext)
        }

        promptParts.append("""
        Respond ONLY with valid JSON: {"app": "<app name>", "category": "<coding|writing|browsing|communication|media|design|other>", "task": "<one sentence description>", "confidence": <0.0-1.0>}
        """)

        let prompt = promptParts.joined(separator: "\n")

        let base64Image = data.base64EncodedString()
        let payload = ChatRequest(
            model: "local",
            messages: [
                .init(
                    role: "user",
                    content: [
                        .imageURL("data:image/png;base64,\(base64Image)"),
                        .text(prompt)
                    ]
                )
            ],
            maxTokens: 200,
            stream: false
        )

        let response = try await complete(payload, baseURL: baseURL, timeout: 30)
        let content = response.choices.first?.message.content ?? ""
        return Self.parseClassification(from: content, fallbackApp: frontmostAppName)
    }

    func streamAnalysis(systemPrompt: String, userPrompt: String, baseURL: URL) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let payload = ChatRequest(
                        model: "local",
                        messages: [
                            .init(role: "system", content: [.text(systemPrompt)]),
                            .init(role: "user", content: [.text(userPrompt)])
                        ],
                        maxTokens: 1200,
                        stream: true
                    )

                    var request = try makeRequest(baseURL: baseURL, timeout: 120)
                    request.httpBody = try JSONEncoder().encode(payload)

                    let session = makeSession(timeout: 120)
                    let (bytes, response) = try await session.bytes(for: request)
                    try validateHTTP(response)

                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.hasPrefix("data:") else { continue }
                        let dataString = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                        if dataString == "[DONE]" {
                            break
                        }
                        guard let chunkData = dataString.data(using: .utf8) else { continue }
                        let chunk = try JSONDecoder().decode(StreamChunk.self, from: chunkData)
                        if let token = chunk.choices.first?.delta.content, !token.isEmpty {
                            continuation.yield(token)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func complete(_ payload: ChatRequest, baseURL: URL, timeout: TimeInterval) async throws -> CompletionResponse {
        var request = try makeRequest(baseURL: baseURL, timeout: timeout)
        request.httpBody = try JSONEncoder().encode(payload)
        let session = makeSession(timeout: timeout)
        let (data, response) = try await session.data(for: request)
        try validateHTTP(response)
        do {
            return try JSONDecoder().decode(CompletionResponse.self, from: data)
        } catch {
            throw LlamaCppError.malformedResponse
        }
    }

    private func makeRequest(baseURL: URL, timeout: TimeInterval) throws -> URLRequest {
        guard validate(baseURL: baseURL) else {
            throw LlamaCppError.nonLocalhostHost
        }
        guard let url = URL(string: "/v1/chat/completions", relativeTo: baseURL) else {
            throw LlamaCppError.invalidBaseURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func makeSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        return URLSession(configuration: configuration)
    }

    private func validate(baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "::1"].contains(host)
    }

    private func validateHTTP(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LlamaCppError.malformedResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw LlamaCppError.requestFailed(httpResponse.statusCode)
        }
    }

    static func parseClassification(from content: String, fallbackApp: String? = nil) -> ClassificationResult {
        guard let jsonBlock = extractJSONBlock(from: content) else {
            return fallbackResult(from: content, fallbackApp: fallbackApp)
        }

        do {
            let envelope = try JSONDecoder().decode(ClassificationEnvelope.self, from: Data(jsonBlock.utf8))
            return ClassificationResult(
                app: envelope.app.trimmingCharacters(in: .whitespacesAndNewlines),
                category: ActivityCategory(rawValue: envelope.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .other,
                task: envelope.task.trimmingCharacters(in: .whitespacesAndNewlines),
                confidence: max(0, min(1, envelope.confidence)),
                rawResponse: content
            )
        } catch {
            return fallbackResult(from: content, fallbackApp: fallbackApp)
        }
    }

    /// When the model returns unparseable text, salvage what we can instead of showing "Unknown 0%".
    private static func fallbackResult(from content: String, fallbackApp: String?) -> ClassificationResult {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Use the raw response as the task description (truncated), with the OS-reported app name
        let task = trimmed.isEmpty ? "Model returned empty response" : String(trimmed.prefix(120))
        return ClassificationResult(
            app: fallbackApp ?? "Unknown",
            category: .other,
            task: task,
            confidence: 0.3,
            rawResponse: content
        )
    }

    static func extractJSONBlock(from content: String) -> String? {
        let normalized = content.replacingOccurrences(of: "```json", with: "```")
        if let fencedRange = normalized.range(of: "```"),
           let fenceEndRange = normalized.range(of: "```", range: fencedRange.upperBound..<normalized.endIndex) {
            let fencedBody = normalized[fencedRange.upperBound..<fenceEndRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let object = firstJSONObject(in: fencedBody) {
                return object
            }
        }

        return firstJSONObject(in: normalized)
    }

    private static func firstJSONObject(in text: String) -> String? {
        var depth = 0
        var startIndex: String.Index?
        var isInsideString = false
        var isEscaping = false

        for index in text.indices {
            let character = text[index]

            if isEscaping {
                isEscaping = false
                continue
            }

            if character == "\\" {
                isEscaping = isInsideString
                continue
            }

            if character == "\"" {
                isInsideString.toggle()
                continue
            }

            guard !isInsideString else { continue }

            if character == "{" {
                if depth == 0 {
                    startIndex = index
                }
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0, let startIndex {
                    return String(text[startIndex...index])
                }
                if depth < 0 {
                    depth = 0
                    startIndex = nil
                }
            }
        }

        return nil
    }
}

private struct ClassificationEnvelope: Decodable {
    var app: String
    var category: String
    var task: String
    var confidence: Double
}

private struct ChatRequest: Encodable {
    var model: String
    var messages: [ChatMessage]
    var maxTokens: Int
    var stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct ChatMessage: Encodable {
    var role: String
    var content: [ChatContent]
}

private enum ChatContent: Encodable {
    case imageURL(String)
    case text(String)

    enum CodingKeys: String, CodingKey {
        case type
        case imageURL = "image_url"
        case text
        case url
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .imageURL(let url):
            try container.encode("image_url", forKey: .type)
            try container.encode(["url": url], forKey: .imageURL)
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        }
    }
}

private struct CompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String?
        }

        var message: Message
    }

    var choices: [Choice]
}

private struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            var content: String?
        }

        var delta: Delta
    }

    var choices: [Choice]
}
