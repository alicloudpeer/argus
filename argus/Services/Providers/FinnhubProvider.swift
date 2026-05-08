import Foundation

/// Finnhub.io REST adapter. Free tier provides 60 req/min and the
/// quote/candle/search/metric endpoints used here. Live tick data lives
/// in `FinnhubLiveStream` (WebSocket).
///
/// The provider gracefully no-ops when no API key is configured so that
/// the rest of the pipeline can still function from snapshot/Stooq data.
actor FinnhubProvider {
    static let shared = FinnhubProvider()

    private let baseURL = URL(string: "https://finnhub.io/api/v1")!
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 6
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    nonisolated var hasKey: Bool { !Secrets.shared.finnhub.isEmpty }

    // MARK: - Quote

    func fetchQuote(symbol: String) async throws -> Quote {
        guard hasKey else {
            throw HeimdallCoreError(category: .authInvalid, code: 401, message: "Finnhub key missing", bodyPrefix: "")
        }
        let mapped = Self.toFinnhubSymbol(symbol)
        let response: QuoteResponse = try await get(path: "quote", params: ["symbol": mapped])
        guard response.c > 0 else {
            throw HeimdallCoreError(category: .emptyPayload, code: 204, message: "Finnhub returned zero price for \(symbol)", bodyPrefix: "")
        }
        var quote = Quote(
            c: response.c,
            d: response.d,
            dp: response.dp,
            currency: "USD",
            shortName: nil,
            symbol: symbol
        )
        quote.previousClose = response.pc
        quote.timestamp = response.t.map { Date(timeIntervalSince1970: $0) } ?? Date()
        return quote
    }

    // MARK: - Candles

    func fetchCandles(symbol: String, timeframe: String, limit: Int) async throws -> [Candle] {
        guard hasKey else {
            throw HeimdallCoreError(category: .authInvalid, code: 401, message: "Finnhub key missing", bodyPrefix: "")
        }
        let mapped = Self.toFinnhubSymbol(symbol)
        let resolution = Self.resolution(for: timeframe)
        let now = Date()
        let span = Self.lookback(forResolution: resolution, limit: limit)
        let from = Int(now.addingTimeInterval(-span).timeIntervalSince1970)
        let to = Int(now.timeIntervalSince1970)

        let response: CandleResponse = try await get(path: "stock/candle", params: [
            "symbol": mapped,
            "resolution": resolution,
            "from": "\(from)",
            "to": "\(to)"
        ])
        guard response.s == "ok",
              let times = response.t, let opens = response.o,
              let highs = response.h, let lows = response.l,
              let closes = response.c else {
            return []
        }
        let volumes = response.v ?? Array(repeating: 0, count: times.count)
        let count = min(times.count, opens.count, highs.count, lows.count, closes.count, volumes.count)
        var out: [Candle] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            out.append(Candle(
                date: Date(timeIntervalSince1970: times[i]),
                open: opens[i], high: highs[i], low: lows[i], close: closes[i],
                volume: volumes[i]
            ))
        }
        if out.count > limit { return Array(out.suffix(limit)) }
        return out
    }

    // MARK: - Symbol search

    func search(query: String) async throws -> [SearchResult] {
        guard hasKey else { return [] }
        let response: SearchResponse = try await get(path: "search", params: ["q": query])
        return response.result.map {
            SearchResult(symbol: $0.symbol, description: $0.description ?? $0.symbol)
        }
    }

    // MARK: - Fundamentals (basic financials)

    func fetchBasicFinancials(symbol: String) async throws -> BasicFinancials {
        guard hasKey else {
            throw HeimdallCoreError(category: .authInvalid, code: 401, message: "Finnhub key missing", bodyPrefix: "")
        }
        let mapped = Self.toFinnhubSymbol(symbol)
        let response: BasicFinancialsResponse = try await get(path: "stock/metric", params: [
            "symbol": mapped,
            "metric": "all"
        ])
        return response.metric
    }

    // MARK: - HTTP

    private func get<T: Decodable>(path: String, params: [String: String]) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var items = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "token", value: Secrets.shared.finnhub))
        components.queryItems = items
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        switch http.statusCode {
        case 200..<300:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw HeimdallCoreError(category: .decodeError, code: http.statusCode, message: "Finnhub decode failed for \(path): \(error.localizedDescription)", bodyPrefix: "")
            }
        case 401, 403:
            throw HeimdallCoreError(category: .authInvalid, code: http.statusCode, message: "Finnhub auth/entitlement \(http.statusCode)", bodyPrefix: "")
        case 429:
            throw HeimdallCoreError(category: .rateLimited, code: 429, message: "Finnhub 429", bodyPrefix: "")
        case 500..<600:
            throw HeimdallCoreError(category: .serverError, code: http.statusCode, message: "Finnhub HTTP \(http.statusCode)", bodyPrefix: "")
        default:
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Finnhub HTTP \(http.statusCode)"])
        }
    }

    // MARK: - Symbol normalization

    static func toFinnhubSymbol(_ raw: String) -> String {
        let upper = raw.uppercased()
        // Finnhub uses BINANCE:BTCUSDT style for crypto, plain SYMBOL for US.
        if upper.contains("-USD") {
            let base = upper.replacingOccurrences(of: "-USD", with: "")
            return "BINANCE:\(base)USDT"
        }
        if upper.hasSuffix("=X") {
            let pair = upper.dropLast(2)
            return "OANDA:\(pair)"
        }
        return upper
    }

    private static func resolution(for timeframe: String) -> String {
        let tf = timeframe.lowercased()
        switch tf {
        case "1m", "1min":           return "1"
        case "5m", "5min":           return "5"
        case "15m", "15min", "15d":  return "15"
        case "30m", "30min":         return "30"
        case "1h", "60m", "1s":      return "60"
        case "4h", "4hour", "4s":    return "60"
        case "1d", "1day", "1g", "d": return "D"
        case "1week", "1wk", "1w":   return "W"
        case "1month", "1mo":        return "M"
        default:                     return "D"
        }
    }

    private static func lookback(forResolution resolution: String, limit: Int) -> TimeInterval {
        let perBar: TimeInterval
        switch resolution {
        case "1":  perBar = 60
        case "5":  perBar = 300
        case "15": perBar = 900
        case "30": perBar = 1800
        case "60": perBar = 3600
        case "D":  perBar = 86_400
        case "W":  perBar = 86_400 * 7
        case "M":  perBar = 86_400 * 30
        default:   perBar = 86_400
        }
        // Pad by 50% to cover non-trading days.
        return perBar * Double(limit) * 1.5
    }

    // MARK: - Decode shapes

    private struct QuoteResponse: Decodable {
        let c: Double
        let d: Double?
        let dp: Double?
        let h: Double?
        let l: Double?
        let o: Double?
        let pc: Double?
        let t: TimeInterval?
    }

    private struct CandleResponse: Decodable {
        let s: String
        let t: [TimeInterval]?
        let o: [Double]?
        let h: [Double]?
        let l: [Double]?
        let c: [Double]?
        let v: [Double]?
    }

    private struct SearchResponse: Decodable {
        let result: [SearchResultRow]
    }

    private struct SearchResultRow: Decodable {
        let symbol: String
        let description: String?
    }

    struct BasicFinancials: Decodable {
        let peTTM: Double?
        let pbAnnual: Double?
        let dividendYieldIndicatedAnnual: Double?
        let epsTTM: Double?
        let revenueTTM: Double?
        let netIncomeAnnual: Double?
        let marketCapitalization: Double?
        let beta: Double?
        let roeTTM: Double?
        let currentRatioAnnual: Double?

        enum CodingKeys: String, CodingKey {
            case peTTM = "peTTM"
            case pbAnnual = "pbAnnual"
            case dividendYieldIndicatedAnnual = "dividendYieldIndicatedAnnual"
            case epsTTM = "epsTTM"
            case revenueTTM = "revenueTTM"
            case netIncomeAnnual = "netIncomeAnnual"
            case marketCapitalization = "marketCapitalization"
            case beta = "beta"
            case roeTTM = "roeTTM"
            case currentRatioAnnual = "currentRatioAnnual"
        }
    }

    private struct BasicFinancialsResponse: Decodable {
        let metric: BasicFinancials
    }

}
