import Foundation

/// Public Binance market data endpoint. No key required, no published
/// rate limit relevant at the request volume the app sends. Used as the
/// canonical source of crypto OHLCV (`BTC-USD`, `ETH-USD`, etc.).
actor BinanceCandleAdapter {
    static let shared = BinanceCandleAdapter()

    private let baseURL = URL(string: "https://api.binance.com/api/v3/klines")!
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    /// Returns historical OHLCV for a crypto symbol expressed in canonical
    /// form (e.g. `BTC-USD`). Translates to Binance USDT pair.
    func fetchCandles(symbol: String, timeframe: String, limit: Int) async throws -> [Candle] {
        guard let pair = Self.toBinancePair(symbol) else { return [] }
        let interval = Self.intervalCode(for: timeframe)

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "symbol", value: pair),
            URLQueryItem(name: "interval", value: interval),
            URLQueryItem(name: "limit", value: "\(min(max(limit, 1), 1000))")
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, response) = try await session.data(for: URLRequest(url: url, timeoutInterval: 15))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Binance HTTP \(code)"])
        }
        let raw = try JSONSerialization.jsonObject(with: data, options: [])
        guard let rows = raw as? [[Any]] else { return [] }
        var out: [Candle] = []
        out.reserveCapacity(rows.count)
        for row in rows {
            guard row.count >= 6 else { continue }
            guard let openTime = row[0] as? Double ?? (row[0] as? Int).map(Double.init) else { continue }
            guard let openStr = row[1] as? String,
                  let highStr = row[2] as? String,
                  let lowStr  = row[3] as? String,
                  let closeStr = row[4] as? String,
                  let volStr   = row[5] as? String else { continue }
            guard let open = Double(openStr),
                  let high = Double(highStr),
                  let low  = Double(lowStr),
                  let close = Double(closeStr),
                  let volume = Double(volStr) else { continue }
            out.append(Candle(
                date: Date(timeIntervalSince1970: openTime / 1000),
                open: open, high: high, low: low, close: close, volume: volume
            ))
        }
        return out
    }

    static func toBinancePair(_ canonical: String) -> String? {
        let upper = canonical.uppercased()
        guard upper.contains("-USD") else { return nil }
        let base = upper.replacingOccurrences(of: "-USD", with: "")
        guard !base.isEmpty else { return nil }
        return "\(base)USDT"
    }

    private static func intervalCode(for timeframe: String) -> String {
        switch timeframe.lowercased() {
        case "1m", "1min":           return "1m"
        case "5m", "5min":           return "5m"
        case "15m", "15min", "15d":  return "15m"
        case "30m", "30min":         return "30m"
        case "1h", "60m", "1s":      return "1h"
        case "4h", "4hour", "4s":    return "4h"
        case "1d", "1day", "1g", "d": return "1d"
        case "1week", "1wk", "1w":   return "1w"
        case "1month", "1mo":        return "1M"
        default:                     return "1d"
        }
    }
}
