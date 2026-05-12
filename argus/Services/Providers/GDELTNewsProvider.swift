import Foundation

/// GDELT DOC 2.0 API news provider. Keyless, Google Jigsaw destekli.
///
/// Endpoint: `https://api.gdeltproject.org/api/v2/doc/doc?query=...&format=json`
///
/// Coverage:
///   * 100+ dil, dünya genelinde web/print/broadcast haber
///   * 3 aylık rolling window
///   * `tone` alanı (-10 .. +10) ile sentiment sinyali
///
/// Rate limit:
///   * Resmi olarak "1 req/5 sec" (HTTP plaintext mesajıyla uyarıyor)
///   * Bu provider içinde self-throttle ile 6 sec arası bırakıyoruz.
///
/// Argus rolü:
///   * `requestNews` chain'inde GoogleNewsRSS'e paralel ikinci kaynak.
///   * BIST sembolleri için `sourcelang:turkish` filtresi.
///   * Hermes sentiment için `tone` alanı kalite veri.
actor GDELTNewsProvider: NewsProvider {
    static let shared = GDELTNewsProvider()

    private let baseURL = URL(string: "https://api.gdeltproject.org/api/v2/doc/doc")!
    private let session: URLSession

    // Self-throttle: GDELT 5 sec ratecap zorluyor → 6 sec güvenli pad.
    private var lastRequestAt: Date = .distantPast
    private let minInterval: TimeInterval = 6.0

    // Per-symbol cache (15 dk TTL — GDELT 3 aylık pencerede zaten
    // yavaş günceleniyor, agresif cache ucuz)
    private var cache: [String: CachedNews] = [:]
    private let cacheTTL: TimeInterval = 900

    private struct CachedNews {
        let articles: [NewsArticle]
        let fetchedAt: Date
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 2
        config.timeoutIntervalForRequest = 12
        self.session = URLSession(configuration: config)
    }

    nonisolated var hasKey: Bool { true }  // keyless

    func fetchNews(symbol: String, limit: Int = 12) async throws -> [NewsArticle] {
        let cacheKey = "\(symbol.uppercased())|\(limit)"
        if let cached = cache[cacheKey],
           -cached.fetchedAt.timeIntervalSinceNow < cacheTTL {
            return cached.articles
        }

        // Self-throttle
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRequestAt)
        if elapsed < minInterval {
            let wait = minInterval - elapsed
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
        lastRequestAt = Date()

        let articles = try await fetchFresh(symbol: symbol, limit: limit)
        cache[cacheKey] = CachedNews(articles: articles, fetchedAt: Date())
        return articles
    }

    // MARK: - Internal

    private func fetchFresh(symbol: String, limit: Int) async throws -> [NewsArticle] {
        let cleaned = symbol.replacingOccurrences(of: ".IS", with: "").uppercased()
        let isBist = symbol.uppercased().hasSuffix(".IS")

        // Query: "TICKER" + opsiyonel dil filtresi
        var queryParts: [String] = ["\"\(cleaned)\""]
        if isBist {
            queryParts.append("sourcelang:turkish")
        }
        let query = queryParts.joined(separator: " ")

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "query",      value: query),
            URLQueryItem(name: "maxrecords", value: "\(min(limit, 50))"),
            URLQueryItem(name: "format",     value: "json"),
            URLQueryItem(name: "sort",       value: "datedesc")
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("Mozilla/5.0 (compatible; ArgusBot/1.0)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        // GDELT returns plain text "Please limit requests..." on rate hit
        if let body = String(data: data, encoding: .utf8),
           body.localizedCaseInsensitiveContains("Please limit requests") {
            throw HeimdallCoreError(category: .rateLimited, code: 429,
                                    message: "GDELT rate limit (5 sec)",
                                    bodyPrefix: String(body.prefix(80)))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse,
                           userInfo: [NSLocalizedDescriptionKey: "GDELT HTTP \(http.statusCode)"])
        }

        let decoded = try JSONDecoder().decode(GDELTResponse.self, from: data)
        let articles = decoded.articles ?? []

        let now = Date()
        return articles.map { row -> NewsArticle in
            let publishedAt = Self.parseSeenDate(row.seendate) ?? now
            return NewsArticle(
                id: row.url,        // URL benzersiz tanımlayıcı
                symbol: symbol,
                source: row.domain ?? "GDELT",
                headline: row.title ?? "",
                summary: nil,       // GDELT'te summary yok; başlık + tone yeterli
                url: row.url,
                publishedAt: publishedAt,
                fetchedAt: now,
                gdeltTone: row.tone  // -10..+10 sentiment hint
            )
        }
    }

    // MARK: - Date parse

    /// GDELT seendate formatı: `YYYYMMDDTHHMMSSZ` (ISO basic).
    private static let seenDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func parseSeenDate(_ value: String?) -> Date? {
        guard let v = value else { return nil }
        return seenDateFormatter.date(from: v)
    }

    // MARK: - Decode shapes

    private struct GDELTResponse: Decodable {
        let articles: [Row]?
    }

    private struct Row: Decodable {
        let url: String
        let title: String?
        let seendate: String?
        let domain: String?
        let language: String?
        let sourcecountry: String?
        let tone: Double?
        let wordcount: Int?
    }
}
