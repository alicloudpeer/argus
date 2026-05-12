import Foundation

/// Coinbase Exchange public market data adapter. Keyless.
///
/// Endpoints:
///   * Spot:     `https://api.coinbase.com/v2/prices/BTC-USD/spot`
///   * Candles:  `https://api.exchange.coinbase.com/products/BTC-USD/candles?granularity=86400`
///
/// Coverage: Coinbase Exchange'te listelenen tüm pair'ler (BTC-USD,
/// ETH-USD, SOL-USD, AVAX-USD, DOT-USD vb. ~250 pair).
/// Rate limit: public ~10 req/sec/IP.
///
/// Argus rolü:
///   * `.crypto` candle chain'inde Binance'tan SONRA yedek — Binance
///     bazı bölgelerden geo-block olabilir (`binance.com` → `binance.us`),
///     Coinbase US-merkezli olduğu için her zaman erişilebilir.
///   * Spot quote için Finnhub/Yahoo'dan sonra üçüncül.
actor CoinbasePublicProvider {
    static let shared = CoinbasePublicProvider()

    private let consumerBase = URL(string: "https://api.coinbase.com/v2")!
    private let exchangeBase = URL(string: "https://api.exchange.coinbase.com")!
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 12
        self.session = URLSession(configuration: config)
    }

    nonisolated var hasKey: Bool { true }  // keyless

    // MARK: - Spot quote

    func fetchQuote(symbol: String) async throws -> Quote {
        guard let pair = Self.toProduct(symbol) else {
            throw HeimdallCoreError(category: .symbolNotFound, code: 422,
                                    message: "Coinbase cannot map \(symbol)",
                                    bodyPrefix: "")
        }
        let url = consumerBase.appendingPathComponent("/prices/\(pair)/spot")
        let response: SpotResponse = try await get(url: url)
        guard let amount = Double(response.data.amount) else {
            throw HeimdallCoreError(category: .decodeError, code: 422,
                                    message: "Coinbase price not numeric",
                                    bodyPrefix: response.data.amount)
        }
        var quote = Quote(
            c: amount,
            d: 0,            // spot endpoint change vermez
            dp: 0,
            currency: response.data.currency,
            shortName: pair,
            symbol: symbol.uppercased()
        )
        quote.previousClose = amount  // bilinmiyor — spot ile aynı tut
        quote.timestamp = Date()
        return quote
    }

    // MARK: - Candles (OHLC)

    func fetchCandles(symbol: String, timeframe: String = "1d", limit: Int = 300) async throws -> [Candle] {
        guard let pair = Self.toProduct(symbol) else {
            throw HeimdallCoreError(category: .symbolNotFound, code: 422,
                                    message: "Coinbase cannot map \(symbol)",
                                    bodyPrefix: "")
        }
        let granularity = Self.granularity(for: timeframe)
        let url = exchangeBase.appendingPathComponent("/products/\(pair)/candles")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "granularity", value: "\(granularity)")]
        guard let finalURL = components.url else { throw URLError(.badURL) }

        let data = try await getRaw(url: finalURL)
        // Response shape: [[time, low, high, open, close, volume], ...]
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[Double]] else {
            return []
        }
        // Coinbase returns newest first; reverse to ascending date.
        let parsed: [Candle] = rows.compactMap { row in
            guard row.count >= 6 else { return nil }
            return Candle(
                date: Date(timeIntervalSince1970: row[0]),
                open: row[3], high: row[2], low: row[1],
                close: row[4], volume: row[5]
            )
        }
        let sorted = parsed.sorted { $0.date < $1.date }
        if sorted.count > limit { return Array(sorted.suffix(limit)) }
        return sorted
    }

    // MARK: - HTTP

    private func get<T: Decodable>(url: URL) async throws -> T {
        let data = try await getRaw(url: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func getRaw(url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 429 {
            throw HeimdallCoreError(category: .rateLimited, code: 429,
                                    message: "Coinbase rate limited",
                                    bodyPrefix: "")
        }
        if http.statusCode == 404 {
            throw HeimdallCoreError(category: .symbolNotFound, code: 404,
                                    message: "Coinbase 404",
                                    bodyPrefix: "")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse,
                           userInfo: [NSLocalizedDescriptionKey: "Coinbase HTTP \(http.statusCode)"])
        }
        return data
    }

    // MARK: - Mapping

    static func toProduct(_ raw: String) -> String? {
        let upper = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !upper.isEmpty else { return nil }

        // Already in Coinbase format
        if upper.contains("-") {
            return upper
        }
        // Aliases
        let aliases: Set<String> = ["BTC", "ETH", "XRP", "LTC", "SOL", "ADA", "DOGE", "AVAX", "DOT", "BNB", "MATIC"]
        if aliases.contains(upper) {
            return "\(upper)-USD"
        }
        return nil
    }

    private static func granularity(for timeframe: String) -> Int {
        switch timeframe.lowercased() {
        case "1m", "1min":      return 60
        case "5m", "5min":      return 300
        case "15m", "15min":    return 900
        case "1h", "1hour":     return 3600
        case "6h", "6hour":     return 21600
        case "1w", "1week":     return 86400 * 7  // not in supported list; falls back to daily server-side
        default:                return 86400      // 1d
        }
    }

    // MARK: - Decode shapes

    private struct SpotResponse: Decodable {
        let data: SpotData
    }

    private struct SpotData: Decodable {
        let amount: String
        let base: String
        let currency: String
    }
}
