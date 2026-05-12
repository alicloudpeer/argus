import Foundation

/// Alpaca Market Data API adapter.
/// Free tier (paper key, no KYC) provides:
///   * 200 req/min
///   * IEX real-time feed (US equities)
///   * 5+ years daily/intraday bar history
///   * Multi-symbol snapshot endpoint (1 req → up to ~100 symbols)
///
/// Used as the **HOT tier primary** for `.usEquity` quotes and candles.
/// Stooq batch stays in the WARM tier (180s watchlist refresh), and Yahoo
/// remains the backstop for symbols Alpaca cannot resolve.
///
/// Keys live in APIKeyStore under two custom slots — never hardcoded:
///   * `alpaca_key_id`  — header `APCA-API-KEY-ID`
///   * `alpaca_secret`  — header `APCA-API-SECRET-KEY`
actor AlpacaProvider {
    static let shared = AlpacaProvider()

    private let dataBaseURL = URL(string: "https://data.alpaca.markets")!
    private let session: URLSession

    static let keyIDStoreID = "alpaca_key_id"
    static let secretStoreID = "alpaca_secret"

    private init() {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 8
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    // MARK: - Credentials

    nonisolated var hasKey: Bool {
        keyID != nil && secret != nil
    }

    private nonisolated var keyID: String? {
        APIKeyStore.shared.getCustomValue(for: Self.keyIDStoreID)
    }

    private nonisolated var secret: String? {
        APIKeyStore.shared.getCustomValue(for: Self.secretStoreID)
    }

    // MARK: - Quote (snapshot)

    /// Returns a fully populated `Quote` for a single symbol using the
    /// `/snapshot` endpoint, which bundles latest trade, latest quote and
    /// previous daily bar into one HTTP call.
    func fetchQuote(symbol: String) async throws -> Quote {
        guard let id = keyID, let sec = secret else {
            throw HeimdallCoreError(category: .authInvalid, code: 401,
                                    message: "Alpaca credentials missing",
                                    bodyPrefix: "")
        }
        let upper = symbol.uppercased()
        let response: SnapshotResponse = try await get(
            path: "/v2/stocks/\(upper)/snapshot",
            params: ["feed": "iex"],
            keyID: id, secret: sec
        )
        return Self.makeQuote(from: response, symbol: upper)
    }

    /// Multi-symbol snapshot — up to ~100 symbols per request. Returns a
    /// dictionary keyed by the canonical symbol so callers can pair
    /// results back to their request list (Stooq-style usage).
    func fetchSnapshotBatch(symbols: [String]) async throws -> [String: Quote] {
        guard !symbols.isEmpty else { return [:] }
        guard let id = keyID, let sec = secret else {
            throw HeimdallCoreError(category: .authInvalid, code: 401,
                                    message: "Alpaca credentials missing",
                                    bodyPrefix: "")
        }
        let normalized = symbols.compactMap { Self.normalize($0) }
        guard !normalized.isEmpty else { return [:] }

        // Chunk by 100 just in case URL grows (typical 100 ticker URL ~700 bytes)
        var combined: [String: Quote] = [:]
        for chunk in stride(from: 0, to: normalized.count, by: 100).map({
            Array(normalized[$0..<min($0 + 100, normalized.count)])
        }) {
            let joined = chunk.joined(separator: ",")
            let response: SnapshotsBatchResponse = try await get(
                path: "/v2/stocks/snapshots",
                params: ["symbols": joined, "feed": "iex"],
                keyID: id, secret: sec
            )
            for (sym, snap) in response.snapshots {
                combined[sym] = Self.makeQuote(from: snap, symbol: sym)
            }
        }
        return combined
    }

    // MARK: - Candles (bars)

    func fetchCandles(symbol: String, timeframe: String, limit: Int = 365) async throws -> [Candle] {
        guard let id = keyID, let sec = secret else {
            throw HeimdallCoreError(category: .authInvalid, code: 401,
                                    message: "Alpaca credentials missing",
                                    bodyPrefix: "")
        }
        let upper = symbol.uppercased()
        let tf = Self.timeframe(for: timeframe)
        let start = Self.lookbackISO(for: tf, limit: limit)

        let response: BarsResponse = try await get(
            path: "/v2/stocks/\(upper)/bars",
            params: [
                "timeframe": tf,
                "start": start,
                "limit": "\(limit)",
                "feed": "iex",
                "adjustment": "split"
            ],
            keyID: id, secret: sec
        )
        let bars = response.bars ?? []
        return bars.compactMap { Self.makeCandle(from: $0) }
    }

    // MARK: - HTTP

    private func get<T: Decodable>(
        path: String,
        params: [String: String],
        keyID: String,
        secret: String
    ) async throws -> T {
        let base = dataBaseURL.appendingPathComponent(path)
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        if !params.isEmpty {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(keyID, forHTTPHeaderField: "APCA-API-KEY-ID")
        request.setValue(secret, forHTTPHeaderField: "APCA-API-SECRET-KEY")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            let prefix = String(data: data.prefix(120), encoding: .utf8) ?? ""
            throw HeimdallCoreError(category: .authInvalid, code: http.statusCode,
                                    message: "Alpaca auth failed", bodyPrefix: prefix)
        }
        if http.statusCode == 429 {
            throw HeimdallCoreError(category: .rateLimited, code: 429,
                                    message: "Alpaca rate limited", bodyPrefix: "")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse,
                           userInfo: [NSLocalizedDescriptionKey: "Alpaca HTTP \(http.statusCode)"])
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Mapping helpers

    /// Strips Stooq-style `.US` suffix and rejects symbols Alpaca cannot
    /// resolve (BIST `.IS`, FX `=X`, commodity `=F`, crypto `-USD`).
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasSuffix(".IS") { return nil }      // BIST
        if trimmed.hasSuffix("=X")  { return nil }      // FX
        if trimmed.hasSuffix("=F")  { return nil }      // Commodity
        if trimmed.hasPrefix("^")   { return nil }      // Indices not on Alpaca free
        if trimmed.contains("-USD") { return nil }      // Crypto via Binance
        if trimmed.hasSuffix(".US") { return String(trimmed.dropLast(3)) }
        return trimmed
    }

    private static func makeQuote(from snap: SnapshotResponse, symbol: String) -> Quote {
        // Last price preference: latestTrade.p → latestQuote midpoint → dailyBar.c
        let lastPrice: Double
        if let trade = snap.latestTrade?.p, trade > 0 {
            lastPrice = trade
        } else if let q = snap.latestQuote, q.ap > 0, q.bp > 0 {
            lastPrice = (q.ap + q.bp) / 2.0
        } else if let daily = snap.dailyBar?.c, daily > 0 {
            lastPrice = daily
        } else {
            lastPrice = 0
        }

        let prevClose = snap.prevDailyBar?.c
        let delta: Double? = prevClose.map { lastPrice - $0 }
        let deltaPct: Double?
        if let prev = prevClose, prev > 0 {
            deltaPct = ((lastPrice - prev) / prev) * 100.0
        } else {
            deltaPct = nil
        }

        var quote = Quote(
            c: lastPrice,
            d: delta,
            dp: deltaPct,
            currency: "USD",
            shortName: nil,
            symbol: symbol
        )
        quote.previousClose = prevClose
        quote.volume = snap.dailyBar?.v
        if let isoT = snap.latestTrade?.t ?? snap.latestQuote?.t {
            quote.timestamp = Self.parseISO(isoT)
        } else {
            quote.timestamp = Date()
        }
        return quote
    }

    private static func makeCandle(from bar: BarResponse) -> Candle? {
        guard let date = parseISO(bar.t) else { return nil }
        return Candle(date: date, open: bar.o, high: bar.h, low: bar.l,
                      close: bar.c, volume: bar.v)
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseISO(_ value: String) -> Date? {
        isoFractional.date(from: value) ?? isoBasic.date(from: value)
    }

    /// Maps Argus's heterogeneous timeframe strings to Alpaca's canonical
    /// `<N><Unit>` form (e.g. `"1d"` → `"1Day"`, `"15m"` → `"15Min"`).
    static func timeframe(for argusTF: String) -> String {
        let tf = argusTF.lowercased()
        switch tf {
        case "1m", "1min":                  return "1Min"
        case "5m", "5min":                  return "5Min"
        case "15m", "15min":                return "15Min"
        case "30m", "30min":                return "30Min"
        case "1h", "1hour", "60m":          return "1Hour"
        case "2h", "2hour":                 return "2Hour"
        case "4h", "4hour":                 return "4Hour"
        case "1w", "1week", "1wk":          return "1Week"
        case "1mo", "1month":               return "1Month"
        default:                            return "1Day"
        }
    }

    private static func lookbackISO(for timeframe: String, limit: Int) -> String {
        let perBar: TimeInterval
        switch timeframe {
        case "1Min":   perBar = 60
        case "5Min":   perBar = 300
        case "15Min":  perBar = 900
        case "30Min":  perBar = 1800
        case "1Hour":  perBar = 3600
        case "2Hour":  perBar = 7200
        case "4Hour":  perBar = 14400
        case "1Week":  perBar = 86400 * 7
        case "1Month": perBar = 86400 * 30
        default:       perBar = 86400 // 1Day
        }
        // Pad by 50% to cover weekends/holidays/missing bars.
        let secondsBack = perBar * Double(limit) * 1.5
        let start = Date().addingTimeInterval(-secondsBack)
        return isoBasic.string(from: start)
    }

    // MARK: - Decode shapes

    fileprivate struct SnapshotResponse: Decodable {
        let latestTrade: TradeResponse?
        let latestQuote: LatestQuote?
        let minuteBar: BarResponse?
        let dailyBar: BarResponse?
        let prevDailyBar: BarResponse?
    }

    fileprivate struct SnapshotsBatchResponse: Decodable {
        let snapshots: [String: SnapshotResponse]

        // Alpaca returns a flat top-level object keyed by symbol:
        //   { "AAPL": {...}, "SPY": {...} }
        // No outer wrapper key — decode by iterating dynamic keys.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicKey.self)
            var out: [String: SnapshotResponse] = [:]
            for key in container.allKeys {
                if let snap = try? container.decode(SnapshotResponse.self, forKey: key) {
                    out[key.stringValue] = snap
                }
            }
            self.snapshots = out
        }

        private struct DynamicKey: CodingKey {
            var stringValue: String
            init?(stringValue: String) { self.stringValue = stringValue }
            var intValue: Int? { nil }
            init?(intValue: Int) { return nil }
        }
    }

    fileprivate struct TradeResponse: Decodable {
        let p: Double
        let s: Int?
        let t: String?
    }

    fileprivate struct LatestQuote: Decodable {
        let ap: Double
        let bp: Double
        let as_: Int?
        let bs: Int?
        let t: String?

        enum CodingKeys: String, CodingKey {
            case ap, bp, t
            case as_ = "as"
            case bs
        }
    }

    fileprivate struct BarResponse: Decodable {
        let o: Double
        let h: Double
        let l: Double
        let c: Double
        let v: Double
        let n: Int?
        let vw: Double?
        let t: String
    }

    fileprivate struct BarsResponse: Decodable {
        let bars: [BarResponse]?
        let symbol: String?
        let next_page_token: String?
    }
}
