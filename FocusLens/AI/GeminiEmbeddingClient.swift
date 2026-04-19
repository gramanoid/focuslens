import Foundation

/// Client for the Google Gemini Embedding API.
/// Uses `gemini-embedding-2-preview` with 768-dimension output for session task embeddings.
final class GeminiEmbeddingClient: Sendable {
    private let apiKey: String
    private let model = "gemini-embedding-2-preview"
    private let dimensions = 768
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Embed a single text string.
    func embed(text: String) async throws -> [Float] {
        guard let url = URL(string: "\(baseURL)/models/\(model):embedContent?key=\(apiKey)") else {
            throw GeminiEmbeddingError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let payload: [String: Any] = [
            "content": [
                "parts": [["text": text]]
            ],
            "taskType": "RETRIEVAL_DOCUMENT",
            "outputDimensionality": dimensions
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiEmbeddingError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw GeminiEmbeddingError.apiError(httpResponse.statusCode, body)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let embeddingObj = json?["embedding"] as? [String: Any]
        let values = embeddingObj?["values"] as? [Double]

        guard let values else {
            throw GeminiEmbeddingError.malformedResponse
        }

        return values.map { Float($0) }
    }

    /// Embed multiple texts in batch. Returns results in order.
    func embedBatch(texts: [String]) async throws -> [[Float]] {
        guard let url = URL(string: "\(baseURL)/models/\(model):batchEmbedContents?key=\(apiKey)") else {
            throw GeminiEmbeddingError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let requests = texts.map { text -> [String: Any] in
            [
                "model": "models/\(model)",
                "content": ["parts": [["text": text]]],
                "taskType": "RETRIEVAL_DOCUMENT",
                "outputDimensionality": dimensions
            ]
        }
        let payload: [String: Any] = ["requests": requests]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiEmbeddingError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw GeminiEmbeddingError.apiError(httpResponse.statusCode, body)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let embeddings = json?["embeddings"] as? [[String: Any]] ?? []

        return embeddings.compactMap { emb -> [Float]? in
            guard let values = emb["values"] as? [Double] else { return nil }
            return values.map { Float($0) }
        }
    }

    /// Compute cosine similarity between two embedding vectors.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        return dotProduct / denominator
    }

    /// Serialize embedding floats to binary Data for SQLite storage.
    static func serialize(_ embedding: [Float]) -> Data {
        embedding.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    /// Deserialize binary Data back to embedding floats.
    static func deserialize(_ data: Data) -> [Float] {
        data.withUnsafeBytes { buffer in
            guard let pointer = buffer.baseAddress?.assumingMemoryBound(to: Float.self) else { return [] }
            let count = buffer.count / MemoryLayout<Float>.size
            return Array(UnsafeBufferPointer(start: pointer, count: count))
        }
    }
}

enum GeminiEmbeddingError: LocalizedError {
    case invalidURL
    case invalidResponse
    case malformedResponse
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid Gemini API URL."
        case .invalidResponse: "Invalid response from Gemini API."
        case .malformedResponse: "Could not parse embedding from Gemini response."
        case .apiError(let code, let body): "Gemini API error HTTP \(code): \(body.prefix(200))"
        }
    }
}
