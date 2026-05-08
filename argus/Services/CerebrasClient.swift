import Foundation

/// Cerebras Inference Client — Qwen 3 235B Instruct çağrıları için.
/// 1M token/gün ücretsiz, ~1400 token/sn, OpenAI-uyumlu API.
/// Endpoint: api.cerebras.ai/v1/chat/completions
/// Key: APIKeyStore.shared.cerebrasApiKey (Settings → API Anahtarları'ndan girilir).
///
/// HermesLLMService bu client'ı GroqClient üzerinden tercih eder; Cerebras
/// key yoksa veya başarısızsa Gemini/GLM/Groq fallback zinciri devreye girer.
final class CerebrasClient: Sendable {
    static let shared = CerebrasClient()

    private var apiKey: String { APIKeyStore.shared.cerebrasApiKey }

    private let baseURL = "https://api.cerebras.ai/v1/chat/completions"

    /// Qwen 3 235B Instruct — Cerebras'ın asıl modeli, 1400 tok/sn, 64K context.
    private let primaryModel = "qwen-3-235b-a22b-instruct-2507"

    /// Daha hafif fallback — primary 429 yerse veya bağlam küçükse.
    private let fallbackModel = "qwen-3-32b"

    private init() {}

    // MARK: - Response shape (hoisted out of generic function — Swift cannot nest types in generics)

    private struct CerebrasResponse: Decodable {
        let choices: [Choice]
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String }
    }

    // MARK: - Public API (GroqClient ile aynı imza)

    var hasKey: Bool {
        !apiKey.isEmpty
    }

    func generateJSON<T: Decodable>(messages: [GroqClient.ChatMessage], maxTokens: Int = 1024) async throws -> T {
        do {
            return try await generateJSONWithModel(model: primaryModel, messages: messages, maxTokens: maxTokens)
        } catch {
            print("⚠️ Cerebras Primary (\(primaryModel)) failed: \(error). Trying \(fallbackModel)...")
            return try await generateJSONWithModel(model: fallbackModel, messages: messages, maxTokens: maxTokens)
        }
    }

    func chat(messages: [GroqClient.ChatMessage], maxTokens: Int = 1024) async throws -> String {
        do {
            return try await chatWithModel(model: primaryModel, messages: messages, maxTokens: maxTokens)
        } catch {
            print("⚠️ Cerebras chat primary failed: \(error). Trying \(fallbackModel)...")
            return try await chatWithModel(model: fallbackModel, messages: messages, maxTokens: maxTokens)
        }
    }

    // MARK: - Private

    private func generateJSONWithModel<T: Decodable>(model: String, messages: [GroqClient.ChatMessage], maxTokens: Int) async throws -> T {
        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "response_format": ["type": "json_object"],
            "max_tokens": maxTokens,
            "temperature": 0.3
        ]

        let data = try await performRequest(body: body)

        let wrapper = try JSONDecoder().decode(CerebrasResponse.self, from: data)
        guard let content = wrapper.choices.first?.message.content else {
            throw URLError(.cannotParseResponse)
        }

        let cleanJson = cleanJsonString(content)
        guard let jsonData = cleanJson.data(using: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        return try JSONDecoder().decode(T.self, from: jsonData)
    }

    private func chatWithModel(model: String, messages: [GroqClient.ChatMessage], maxTokens: Int) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "max_tokens": maxTokens,
            "temperature": 0.7
        ]

        let data = try await performRequest(body: body)

        let wrapper = try JSONDecoder().decode(CerebrasResponse.self, from: data)
        return wrapper.choices.first?.message.content ?? ""
    }

    private func performRequest(body: [String: Any]) async throws -> Data {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "CerebrasClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Cerebras API key not configured"])
        }
        guard let url = URL(string: baseURL) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let errStr = String(data: data, encoding: .utf8) ?? ""
            print("❌ Cerebras API \(http.statusCode): \(errStr)")
            throw NSError(
                domain: "CerebrasClient",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Cerebras \(http.statusCode): \(errStr)"]
            )
        }

        return data
    }

    private func cleanJsonString(_ text: String) -> String {
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.contains("```") {
            let parts = clean.components(separatedBy: "```")
            if parts.count >= 3 {
                clean = parts[1]
                if clean.hasPrefix("json") {
                    clean = String(clean.dropFirst(4))
                }
            }
        }
        if let firstBrace = clean.firstIndex(of: "{"),
           let lastBrace = clean.lastIndex(of: "}"),
           firstBrace <= lastBrace {
            clean = String(clean[firstBrace...lastBrace])
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
