import Foundation

/// Tek tek anahtarları doğrulamak için minimal HTTP probe.
///
/// HeimdallProbe yalnızca 3 sağlayıcı için derinlemesine doğrulama yapıyordu
/// (FMP, TwelveData, EODHD). Bu sınıf APIKeyCenterView'daki tüm sağlayıcılar
/// için tek bir noktadan doğrulama sağlar.
///
/// Davranış:
/// - 200 → geçerli.
/// - 401/403 → geçersiz (auth hatası).
/// - 429 → geçerli ama rate-limited (anahtarın aktif olduğu anlamına gelir).
/// - 400 + "Invalid API Key" gibi body sinyali → geçersiz.
/// - Network hatası → belirsiz (`Bağlantı kurulamadı`).
///
/// Sadece format kontrolü olan provider'lar için (GLM, Massive) HTTP yapılmaz,
/// format kuralı geçtiyse "Format doğru" mesajı döner.
enum APIKeyVerifier {

    struct Result {
        let isValid: Bool
        let message: String
        let latencyMs: Int?
    }

    /// APIProvider enum'undaki her bir provider için verifier çağırır.
    static func verify(provider: APIProvider, key: String) async -> Result {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Result(isValid: false, message: "Anahtar boş.", latencyMs: nil)
        }

        // Format kontrolü — bilinen prefix/length kurallarını uygula
        if let formatError = formatCheck(provider: provider, key: trimmed) {
            return Result(isValid: false, message: formatError, latencyMs: nil)
        }

        // Format-only sağlayıcılar
        switch provider {
        case .glm, .massive:
            return Result(isValid: true, message: "Format doğru · otomatik test yok", latencyMs: nil)
        default:
            break
        }

        // HTTP doğrulama
        let request = buildRequest(provider: provider, key: trimmed)
        guard let request else {
            return Result(isValid: false, message: "URL oluşturulamadı.", latencyMs: nil)
        }

        let start = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let latency = Int(Date().timeIntervalSince(start) * 1000)

            guard let http = response as? HTTPURLResponse else {
                return Result(isValid: false, message: "Geçersiz HTTP yanıtı.", latencyMs: latency)
            }

            let body = String(data: data, encoding: .utf8) ?? ""

            return interpretResponse(status: http.statusCode, body: body, latencyMs: latency)

        } catch {
            return Result(
                isValid: false,
                message: "Bağlantı kurulamadı · \(error.localizedDescription)",
                latencyMs: nil
            )
        }
    }

    // MARK: - Format check

    private static func formatCheck(provider: APIProvider, key: String) -> String? {
        switch provider {
        case .groq:
            return key.hasPrefix("gsk_") ? nil : "Groq anahtarları gsk_ ile başlar."
        case .cerebras:
            return key.hasPrefix("csk-") ? nil : "Cerebras anahtarları csk- ile başlar."
        case .gemini:
            return key.hasPrefix("AIza") ? nil : "Gemini anahtarları AIza ile başlar."
        case .deepSeek:
            return key.hasPrefix("sk-") || key.hasPrefix("sk_") ? nil : "DeepSeek anahtarları sk- ile başlar."
        default:
            return nil
        }
    }

    // MARK: - Request builder

    private static func buildRequest(provider: APIProvider, key: String) -> URLRequest? {
        let url: URL?
        var headers: [String: String] = [:]

        switch provider {
        case .finnhub:
            url = URL(string: "https://finnhub.io/api/v1/quote?symbol=AAPL&token=\(key)")
        case .alphaVantage:
            url = URL(string: "https://www.alphavantage.co/query?function=GLOBAL_QUOTE&symbol=IBM&apikey=\(key)")
        case .eodhd:
            url = URL(string: "https://eodhd.com/api/real-time/AAPL.US?api_token=\(key)&fmt=json")
        case .fmp:
            url = URL(string: "https://financialmodelingprep.com/stable/profile?symbol=AAPL&apikey=\(key)")
        case .twelveData:
            url = URL(string: "https://api.twelvedata.com/quote?symbol=AAPL&apikey=\(key)")
        case .tiingo:
            url = URL(string: "https://api.tiingo.com/api/test/?token=\(key)")
        case .marketstack:
            url = URL(string: "https://api.marketstack.com/v1/eod?access_key=\(key)&symbols=AAPL&limit=1")
        case .fred:
            url = URL(string: "https://api.stlouisfed.org/fred/series?series_id=GNPCA&api_key=\(key)&file_type=json")
        case .pinecone:
            url = URL(string: "https://api.pinecone.io/indexes")
            headers["Api-Key"] = key
        case .groq:
            url = URL(string: "https://api.groq.com/openai/v1/models")
            headers["Authorization"] = "Bearer \(key)"
        case .cerebras:
            url = URL(string: "https://api.cerebras.ai/v1/models")
            headers["Authorization"] = "Bearer \(key)"
        case .gemini:
            url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(key)")
        case .deepSeek:
            url = URL(string: "https://api.deepseek.com/v1/models")
            headers["Authorization"] = "Bearer \(key)"
        case .glm, .massive:
            return nil  // Yukarıda format-only olarak handle edildi
        }

        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        for (k, v) in headers { request.addValue(v, forHTTPHeaderField: k) }
        return request
    }

    // MARK: - Response interpretation

    private static func interpretResponse(status: Int, body: String, latencyMs: Int) -> Result {
        // Auth hataları — anahtar geçersiz
        if status == 401 || status == 403 {
            return Result(
                isValid: false,
                message: "Anahtar reddedildi · HTTP \(status)",
                latencyMs: latencyMs
            )
        }

        // Rate limit — anahtar VAR ve aktif
        if status == 429 {
            return Result(
                isValid: true,
                message: "Geçerli · şu an rate limit (429)",
                latencyMs: latencyMs
            )
        }

        // Body içinde hata sinyalleri (200 olsa bile)
        if status == 200 {
            let lower = body.lowercased()
            let invalidSignals = [
                "invalid api key",
                "invalid_api_key",
                "error message",
                "\"error\"",
                "unauthorized",
                "api key not found"
            ]
            for signal in invalidSignals {
                if lower.contains(signal) {
                    return Result(
                        isValid: false,
                        message: "Anahtar reddedildi · yanıt hata içeriyor",
                        latencyMs: latencyMs
                    )
                }
            }

            // Günlük limit aşıldı uyarısı (rate limit benzeri — anahtar geçerli)
            if lower.contains("daily api requests limit") || lower.contains("daily limit") {
                return Result(
                    isValid: true,
                    message: "Geçerli · günlük limit doldu",
                    latencyMs: latencyMs
                )
            }

            return Result(
                isValid: true,
                message: "Doğrulama başarılı · \(latencyMs) ms",
                latencyMs: latencyMs
            )
        }

        // Diğer HTTP hataları — belirsiz, geçersiz say
        return Result(
            isValid: false,
            message: "Beklenmedik yanıt · HTTP \(status)",
            latencyMs: latencyMs
        )
    }
}
