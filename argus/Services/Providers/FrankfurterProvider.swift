import Foundation

/// Frankfurter API adapter — keyless, ECB-backed FX + precious metals.
///
/// Endpoint: `https://api.frankfurter.dev/v2/latest?base=USD&symbols=TRY`
///
/// Coverage:
///   * 171 currencies (TRY 1996-04-16'dan itibaren)
///   * XAU (gold), XAG (silver), XPT (platinum), XPD (palladium) — Troy ounce
///   * Cloudflare server-side cache (24h)
///   * Quota yok, key yok, attribution gönüllü
///
/// Argus rolü:
///   * `.forex` chain'inde Stooq'tan SONRA fallback (Stooq önce çünkü
///     intraday değerleri Frankfurter günlük kapanış veriyor — daha
///     az "fresh" ama bir referans olarak güvenilir).
///   * `.commodity` chain'inde XAU/XAG sembolleri için fallback.
///   * DovizCom'un boşluğunu doldurur — kurum bazlı altın/gümüş için
///     resmi ECB referans fiyatı.
actor FrankfurterProvider {
    static let shared = FrankfurterProvider()

    private let baseURL = URL(string: "https://api.frankfurter.dev/v2")!
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 12
        // Frankfurter has aggressive server-side cache; respect it.
        config.requestCachePolicy = .useProtocolCachePolicy
        self.session = URLSession(configuration: config)
    }

    nonisolated var hasKey: Bool { true }  // keyless

    // MARK: - Quote

    /// Returns the latest USD/TRY (or generic base/quote) rate as a Quote.
    /// Symbol resolution:
    ///   * Yahoo-style `USDTRY=X` → base=USD, quote=TRY
    ///   * Commodity futures `GC=F` (gold) → base=XAU, quote=USD
    ///   * Commodity futures `SI=F` (silver) → base=XAG, quote=USD
    ///   * Direct ISO `EUR`, `XAU` etc. → quote=USD assumed
    func fetchQuote(symbol: String) async throws -> Quote {
        guard let pair = Self.parsePair(symbol) else {
            throw HeimdallCoreError(category: .symbolNotFound, code: 422,
                                    message: "Frankfurter cannot parse \(symbol)",
                                    bodyPrefix: "")
        }
        let response = try await fetchLatest(base: pair.base, quote: pair.quote)
        guard let rate = response.rates[pair.quote] else {
            throw HeimdallCoreError(category: .emptyPayload, code: 204,
                                    message: "Frankfurter has no \(pair.base)/\(pair.quote) rate",
                                    bodyPrefix: "")
        }

        // ECB publishes a single daily reference rate — we treat it as
        // both current price and previousClose for delta math. Real
        // intraday delta requires a second call; cheap callers can rely
        // on Stooq for that. Frankfurter is the resilient anchor.
        var quote = Quote(
            c: rate,
            d: 0,
            dp: 0,
            currency: pair.quote,
            shortName: "\(pair.base)/\(pair.quote)",
            symbol: symbol.uppercased()
        )
        quote.previousClose = rate
        quote.timestamp = Self.parseDate(response.date) ?? Date()
        return quote
    }

    // MARK: - Historical (single rate over time)

    /// Returns a daily series for the given pair between `start` and `end`.
    /// Useful for Frankfurter-as-candle when Yahoo intraday is unavailable.
    func fetchSeries(symbol: String, start: Date, end: Date = Date()) async throws -> [Candle] {
        guard let pair = Self.parsePair(symbol) else { return [] }
        let formatter = Self.iso8601DateOnly
        let startStr = formatter.string(from: start)
        let endStr = formatter.string(from: end)

        var components = URLComponents(url: baseURL.appendingPathComponent("\(startStr)..\(endStr)"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "base", value: pair.base),
            URLQueryItem(name: "symbols", value: pair.quote)
        ]
        guard let url = components.url else { return [] }

        let response: SeriesResponse = try await get(url: url)
        var out: [Candle] = []
        out.reserveCapacity(response.rates.count)
        for (dateStr, rates) in response.rates {
            guard let date = Self.parseDate(dateStr) ?? formatter.date(from: dateStr) else { continue }
            guard let rate = rates[pair.quote] else { continue }
            // Frankfurter daily = single rate. Build OHLC as flat candle.
            out.append(Candle(date: date, open: rate, high: rate, low: rate, close: rate, volume: 0))
        }
        out.sort { $0.date < $1.date }
        return out
    }

    // MARK: - Internal fetch

    private func fetchLatest(base: String, quote: String) async throws -> LatestResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("latest"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "base", value: base),
            URLQueryItem(name: "symbols", value: quote)
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return try await get(url: url)
    }

    private func get<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 404 {
            throw HeimdallCoreError(category: .symbolNotFound, code: 404,
                                    message: "Frankfurter symbol not found",
                                    bodyPrefix: "")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse,
                           userInfo: [NSLocalizedDescriptionKey: "Frankfurter HTTP \(http.statusCode)"])
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Symbol parsing

    struct Pair {
        let base: String
        let quote: String
    }

    /// Parses a heterogeneous symbol input into Frankfurter (base, quote).
    /// Returns nil for symbols Frankfurter cannot resolve (US equities,
    /// BIST, crypto, indices).
    static func parsePair(_ raw: String) -> Pair? {
        let upper = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !upper.isEmpty else { return nil }

        // Yahoo FX format: USDTRY=X → USD/TRY
        if upper.hasSuffix("=X"), upper.count == 8 {
            let body = String(upper.dropLast(2))   // "USDTRY"
            let base = String(body.prefix(3))
            let quote = String(body.suffix(3))
            return Pair(base: base, quote: quote)
        }

        // Commodity futures → XAU/USD or XAG/USD
        if upper.hasSuffix("=F") {
            switch upper {
            case "GC=F": return Pair(base: "XAU", quote: "USD")
            case "SI=F": return Pair(base: "XAG", quote: "USD")
            case "PL=F": return Pair(base: "XPT", quote: "USD")
            case "PA=F": return Pair(base: "XPD", quote: "USD")
            default:     return nil
            }
        }

        // Direct ISO codes (XAU, EUR, TRY) → vs USD by default
        let directMetals: Set<String> = ["XAU", "XAG", "XPT", "XPD"]
        if directMetals.contains(upper) {
            return Pair(base: upper, quote: "USD")
        }

        return nil
    }

    // MARK: - Date helpers

    private static let iso8601DateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func parseDate(_ value: String) -> Date? {
        iso8601DateOnly.date(from: value)
    }

    // MARK: - Decode shapes

    private struct LatestResponse: Decodable {
        let amount: Double
        let base: String
        let date: String
        let rates: [String: Double]
    }

    private struct SeriesResponse: Decodable {
        let amount: Double
        let base: String
        let start_date: String
        let end_date: String
        let rates: [String: [String: Double]]
    }
}
