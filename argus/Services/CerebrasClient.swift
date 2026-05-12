import Foundation

/// Cerebras Inference Client — kaliteli + idareli kullanım için ayarlandı.
/// Endpoint: api.cerebras.ai/v1/chat/completions, OpenAI-uyumlu.
/// Key: APIKeyStore.shared.cerebrasApiKey (Settings → API Anahtarları).
///
/// HermesLLMService bu client'ı GroqClient üzerinden tercih eder; Cerebras
/// key yoksa veya başarısızsa Gemini/GLM/Groq fallback zinciri devreye girer.
///
/// 2026-05-11 model & idare ayarları:
///   * Primary `gpt-oss-120b` — production, **3000 tok/s**, 120B param.
///     En yüksek throughput → kullanıcı $10 bakiyesini yavaş tüketir.
///     Preview model'lerden (qwen-3-235b, zai-glm-4.7) hem daha hızlı
///     hem daha stabil; production tier kalitesi 120B param ile gayet
///     kaliteli (JSON output + sentiment analysis için fazlasıyla).
///   * Fallback `llama3.1-8b` — production, 8B, 2200 tok/s. Primary 429
///     yerse hafif yedek; çok ucuz token (idareli).
///   * `maxTokens` varsayılan 1024 → **768**. JSON sentiment outputları
///     için yeterli, gereksiz token israfı yok.
///   * 429 sonrası 60 sn cooldown — peşpeşe Cerebras dövmek yerine
///     doğrudan Gemini'ye atla, bakiye korunur.
final class CerebrasClient: @unchecked Sendable {
    static let shared = CerebrasClient()

    private var apiKey: String { APIKeyStore.shared.cerebrasApiKey }

    private let baseURL = "https://api.cerebras.ai/v1/chat/completions"

    /// GPT-OSS 120B — production, 3000 tok/s, en yüksek throughput.
    /// Kaliteli (120B param) + hızlı = bakiyeyi idareli kullanır.
    private let primaryModel = "gpt-oss-120b"

    /// Llama 3.1 8B — production, 2200 tok/s. Primary 429 yerse hafif
    /// yedek; çok ucuz token tüketimi.
    private let fallbackModel = "llama3.1-8b"

    /// İdareli default — JSON sentiment / haber analiz response'ları
    /// için 768 token yeterli. (Önceki 1024 fazla geniş.)
    private let defaultMaxTokens = 768

    // 429 sonrası kısa süreli devre dışı bırakma.
    private let cooldownLock = NSLock()
    private var cooldownUntil: Date?
    private let cooldownDuration: TimeInterval = 60  // 60 sn

    private init() {}

    // MARK: - Response shape (hoisted out of generic function — Swift cannot nest types in generics)

    private struct CerebrasResponse: Decodable {
        let choices: [Choice]
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String }
    }

    // MARK: - Public API (GroqClient ile aynı imza)

    var hasKey: Bool {
        guard !apiKey.isEmpty else { return false }
        // Cooldown aktifse "key yok" gibi davranıp cascade'i hemen
        // Gemini'ye taşı — peşpeşe 429 dövmek kullanıcıyı bekletiyor.
        // `withLock` async-uyumlu pattern (Swift 5.9+).
        return cooldownLock.withLock {
            if let until = cooldownUntil, Date() < until { return false }
            return true
        }
    }

    private func enterCooldown() {
        cooldownLock.withLock {
            cooldownUntil = Date().addingTimeInterval(cooldownDuration)
        }
    }

    func generateJSON<T: Decodable>(messages: [GroqClient.ChatMessage], maxTokens: Int? = nil) async throws -> T {
        let tokens = maxTokens ?? defaultMaxTokens
        do {
            return try await generateJSONWithModel(model: primaryModel, messages: messages, maxTokens: tokens)
        } catch {
            // 429'da fallback çağırmadan döneriz — peşpeşe ödeme yapan
            // model'i dövmenin anlamı yok; cooldown zaten girdi.
            if (error as NSError).code == 429 { throw error }
            print("⚠️ Cerebras Primary (\(primaryModel)) failed: \(error). Trying \(fallbackModel)...")
            return try await generateJSONWithModel(model: fallbackModel, messages: messages, maxTokens: tokens)
        }
    }

    func chat(messages: [GroqClient.ChatMessage], maxTokens: Int? = nil) async throws -> String {
        let tokens = maxTokens ?? defaultMaxTokens
        do {
            return try await chatWithModel(model: primaryModel, messages: messages, maxTokens: tokens)
        } catch {
            if (error as NSError).code == 429 { throw error }
            print("⚠️ Cerebras chat primary failed: \(error). Trying \(fallbackModel)...")
            return try await chatWithModel(model: fallbackModel, messages: messages, maxTokens: tokens)
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
            // 429 alındığında 60 sn cooldown — sıradaki ABBV tıkında
            // Cerebras tekrar denenmesin, doğrudan Gemini'ye atla.
            if http.statusCode == 429 {
                enterCooldown()
            }
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
