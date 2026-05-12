import Foundation

/// BtcTurk public market data adapter. Keyless.
///
/// Endpoints:
///   * Ticker: `https://api.btcturk.com/api/v2/ticker?pairSymbol=BTCTRY`
///   * OHLC:   `https://api.btcturk.com/api/v2/ohlc?pairSymbol=BTCTRY&from=...&to=...`
///
/// Coverage: BTC/ETH/XRP/USDT/SOL... × TRY ve USDT pair'leri (~295 pair).
/// Rate limit: ticker 10 req/100ms; ohlc daha katı.
///
/// Argus rolü:
///   * `.crypto` chain'inde ek bir kaynak. Türk kullanıcı için TRY pair
///     native — Binance USDT pair'inden TCMB FX ile çarparak hesaplamak
///     yerine BtcTurk doğrudan TRY veriyor.
///   * Binance geo-block (bazı ABD IP'lerinde) yedek olarak.
actor BtcTurkProvider {
    static let shared = BtcTurkProvider()

    private let baseURL = URL(string: "https://api.btcturk.com/api/v2")!
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 12
        self.session = URLSession(configuration: config)
    }

    nonisolated var hasKey: Bool { true }  // keyless

    // MARK: - Quote

    /// Symbol mapping:
    ///   * "BTC-TRY" → BTCTRY (native TR pair)
    ///   * "BTC-USD" → BTCUSDT (USDT proxy)
    ///   * "BTC"     → BTCTRY (default TR pair)
    func fetchQuote(symbol: String) async throws -> Quote {
        guard let pair = Self.toBtcTurkPair(symbol) else {
            throw HeimdallCoreError(category: .symbolNotFound, code: 422,
                                    message: "BtcTurk cannot map \(symbol)",
                                    bodyPrefix: "")
        }

        let url = baseURL.appendingPathComponent("ticker")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "pairSymbol", value: pair)]
        guard let finalURL = components.url else { throw URLError(.badURL) }

        let response: TickerResponse = try await get(url: finalURL)
        guard let row = response.data?.first else {
            throw HeimdallCoreError(category: .emptyPayload, code: 204,
                                    message: "BtcTurk empty for \(pair)",
                                    bodyPrefix: "")
        }

        let currency = row.denominatorSymbol ?? "TRY"
        var quote = Quote(
            c: row.last,
            d: row.daily,
            dp: row.dailyPercent,
            currency: currency,
            shortName: row.pair,
            symbol: symbol.uppercased()
        )
        quote.previousClose = row.open
        quote.volume = row.volume
        quote.timestamp = Date(timeIntervalSince1970: TimeInterval(row.timestamp / 1000))
        return quote
    }

    // MARK: - Candles (daily OHLC)

    func fetchCandles(symbol: String, days: Int = 90) async throws -> [Candle] {
        guard let pair = Self.toBtcTurkPair(symbol) else {
            throw HeimdallCoreError(category: .symbolNotFound, code: 422,
                                    message: "BtcTurk cannot map \(symbol)",
                                    bodyPrefix: "")
        }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end

        let url = baseURL.appendingPathComponent("ohlc")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "pairSymbol", value: pair),
            URLQueryItem(name: "from", value: "\(Int(start.timeIntervalSince1970))"),
            URLQueryItem(name: "to", value: "\(Int(end.timeIntervalSince1970))")
        ]
        guard let finalURL = components.url else { throw URLError(.badURL) }

        let response: OHLCResponse = try await get(url: finalURL)
        guard let rows = response.data, !rows.isEmpty else { return [] }

        let candles: [Candle] = rows.compactMap { row in
            guard let o = Double(row.open),
                  let h = Double(row.high),
                  let l = Double(row.low),
                  let c = Double(row.close),
                  let v = Double(row.volume) else { return nil }
            return Candle(
                date: Date(timeIntervalSince1970: TimeInterval(row.time / 1000)),
                open: o, high: h, low: l, close: c, volume: v
            )
        }
        return candles.sorted { $0.date < $1.date }
    }

    // MARK: - HTTP

    private func get<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 429 {
            throw HeimdallCoreError(category: .rateLimited, code: 429,
                                    message: "BtcTurk rate limited",
                                    bodyPrefix: "")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse,
                           userInfo: [NSLocalizedDescriptionKey: "BtcTurk HTTP \(http.statusCode)"])
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Symbol mapping

    static func toBtcTurkPair(_ raw: String) -> String? {
        let upper = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !upper.isEmpty else { return nil }

        // Yahoo crypto format: BTC-USD, ETH-USD → BTCUSDT, ETHUSDT (USDT pair)
        if upper.hasSuffix("-USD") {
            return String(upper.dropLast(4)) + "USDT"
        }
        // TR pair format: BTC-TRY → BTCTRY
        if upper.hasSuffix("-TRY") {
            return upper.replacingOccurrences(of: "-", with: "")
        }
        // Alias: "BTC" → BTCTRY (default TR pair)
        let knownCryptos: Set<String> = ["BTC", "ETH", "XRP", "LTC", "SOL", "ADA", "DOGE", "AVAX", "DOT", "USDT", "BNB", "TRX"]
        if knownCryptos.contains(upper) {
            return "\(upper)TRY"
        }
        // Already in BtcTurk format (e.g. BTCUSDT, ETHTRY)?
        if upper.count >= 6 && upper.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return upper
        }
        return nil
    }

    // MARK: - Decode shapes

    private struct TickerResponse: Decodable {
        let data: [Ticker]?
        let success: Bool?
    }

    private struct Ticker: Decodable {
        let pair: String
        let last: Double
        let high: Double
        let low: Double
        let bid: Double?
        let ask: Double?
        let open: Double
        let volume: Double
        let average: Double?
        let daily: Double
        let dailyPercent: Double
        let timestamp: Int64
        let numeratorSymbol: String?
        let denominatorSymbol: String?
    }

    private struct OHLCResponse: Decodable {
        let data: [OHLCRow]?
    }

    private struct OHLCRow: Decodable {
        let pairSymbol: String
        let time: Int64
        let open: String
        let high: String
        let low: String
        let close: String
        let volume: String
    }
}
