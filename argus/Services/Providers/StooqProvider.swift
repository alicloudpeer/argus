import Foundation

/// Stooq.com adapter. Free, keyless, no published rate limit.
/// Two main entry points:
///   * `fetchSnapshotBatch` returns the latest OHLCV row for hundreds of
///     tickers in one CSV request. Used by the warm tier to refresh the
///     entire watchlist with a single round-trip.
///   * `fetchDailyCandles` returns historical daily/weekly/monthly bars
///     in CSV form. Used as the canonical source of long-running
///     OHLCV history.
/// US/global equities, FX majors, commodities, indices and a subset of
/// crypto are supported. BIST symbols are not (BorsaPy covers them).
actor StooqProvider {
    static let shared = StooqProvider()

    private let snapshotBase = URL(string: "https://stooq.com/q/l/")!
    private let candlesBase  = URL(string: "https://stooq.com/q/d/l/")!

    private init() {}

    // MARK: - Snapshot batch

    /// Returns the most recent quote for each symbol. Stooq accepts a
    /// space-separated symbol list (URL-encoded as `+`). The free feed
    /// is 15 minute delayed for US equities and end-of-day for many
    /// other instruments. Empty rows in the CSV are skipped silently.
    /// Symbols are chunked at `chunkSize` to stay below proxy URL
    /// length caps (~2 KB on many CDNs); chunks run in parallel.
    func fetchSnapshotBatch(symbols: [String]) async throws -> [String: Quote] {
        guard !symbols.isEmpty else { return [:] }

        let normalized = symbols.compactMap { Self.toStooqSymbol($0) }
        guard !normalized.isEmpty else { return [:] }

        let chunks = stride(from: 0, to: normalized.count, by: Self.chunkSize).map {
            Array(normalized[$0..<min($0 + Self.chunkSize, normalized.count)])
        }

        return await withTaskGroup(of: [String: Quote].self) { group in
            for chunk in chunks {
                group.addTask { [chunk] in
                    (try? await Self.fetchChunk(chunk)) ?? [:]
                }
            }
            var combined: [String: Quote] = [:]
            for await partial in group {
                for (key, value) in partial { combined[key] = value }
            }
            return combined
        }
    }

    private static let chunkSize = 80

    private static func fetchChunk(_ normalized: [SymbolMapping]) async throws -> [String: Quote] {
        // Stooq's snapshot endpoint wants symbols joined with literal
        // `+` (its decoder reads the URL raw, so `URLComponents`'s
        // percent-encoding mangles the list). Build the query string
        // by hand to keep the `+` separators intact.
        let joined = normalized.map(\.stooq).joined(separator: "+")
        let raw = "https://stooq.com/q/l/?s=\(joined)&f=sd2t2ohlcv&h&e=csv"
        guard let finalURL = URL(string: raw) else { return [:] }

        let data = try await fetch(url: finalURL, timeout: 15)
        return parseSnapshotCSV(data: data, symbolMap: normalized)
    }

    // MARK: - Daily candles

    /// Returns historical OHLCV for the requested symbol. Stooq exposes
    /// `i` for interval (`d` daily, `w` weekly, `m` monthly).
    func fetchDailyCandles(symbol: String, limit: Int = 365, interval: Interval = .daily) async throws -> [Candle] {
        guard let mapped = Self.toStooqSymbol(symbol) else { return [] }

        var components = URLComponents(url: candlesBase, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "s", value: mapped.stooq),
            URLQueryItem(name: "i", value: interval.rawValue)
        ]
        guard let url = components.url else { return [] }

        let data = try await Self.fetch(url: url, timeout: 20)
        let candles = Self.parseCandlesCSV(data: data)
        if candles.count > limit {
            return Array(candles.suffix(limit))
        }
        return candles
    }

    enum Interval: String {
        case daily   = "d"
        case weekly  = "w"
        case monthly = "m"
    }

    // MARK: - Symbol mapping

    /// Canonical symbol form used by the rest of the codebase translated
    /// to Stooq's notation. Returns nil for symbols Stooq does not cover
    /// so the caller can route them elsewhere (e.g. BIST -> BorsaPy).
    static func toStooqSymbol(_ raw: String) -> SymbolMapping? {
        let upper = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !upper.isEmpty else { return nil }

        // BIST is not on Stooq.
        if upper.hasSuffix(".IS") { return nil }

        // Index aliases.
        let indexMap: [String: String] = [
            "^GSPC": "^spx",
            "^IXIC": "^ndq",
            "^DJI":  "^dji",
            "^RUT":  "^rut",
            "^VIX":  "^vix",
            "^FTSE": "^ftm",
            "^N225": "^nkx",
            "^TNX":  "^tnx",
            "DX-Y.NYB": "^dxy"
        ]
        if let m = indexMap[upper] { return SymbolMapping(canonical: upper, stooq: m) }

        // FX pairs: Yahoo uses USDTRY=X, Stooq uses usdtry.
        if upper.hasSuffix("=X") {
            let pair = upper.dropLast(2).lowercased()
            return SymbolMapping(canonical: upper, stooq: pair)
        }

        // Commodities: GC=F (gold), CL=F (crude), etc.
        if upper.hasSuffix("=F") {
            let map: [String: String] = [
                "GC=F": "gc.f", "SI=F": "si.f", "HG=F": "hg.f",
                "CL=F": "cl.f", "BZ=F": "bz.f", "NG=F": "ng.f"
            ]
            if let m = map[upper] { return SymbolMapping(canonical: upper, stooq: m) }
            return nil
        }

        // Crypto: BTC-USD -> btcusd.
        if upper.contains("-USD") {
            let pair = upper.replacingOccurrences(of: "-", with: "").lowercased()
            return SymbolMapping(canonical: upper, stooq: pair)
        }

        // US equity default: append `.us`.
        return SymbolMapping(canonical: upper, stooq: "\(upper.lowercased()).us")
    }

    struct SymbolMapping: Sendable {
        let canonical: String
        let stooq: String
    }

    // MARK: - HTTP

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 8
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private static func fetch(url: URL, timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Stooq HTTP \(code)"])
        }
        return data
    }

    // MARK: - CSV parsing

    private static func parseSnapshotCSV(data: Data, symbolMap: [SymbolMapping]) -> [String: Quote] {
        guard let text = String(data: data, encoding: .utf8) else { return [:] }
        let lookup = Dictionary(uniqueKeysWithValues: symbolMap.map { ($0.stooq.uppercased(), $0.canonical) })

        var quotes: [String: Quote] = [:]
        let lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        guard lines.count > 1 else { return [:] }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]

        for raw in lines.dropFirst() {
            let cols = raw.split(separator: ",", omittingEmptySubsequences: false).map { String($0) }
            guard cols.count >= 8 else { continue }

            let stooqSymbol = cols[0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !stooqSymbol.isEmpty, stooqSymbol != "N/D" else { continue }
            guard let canonical = lookup[stooqSymbol] else { continue }

            let close = Double(cols[6]) ?? 0
            guard close > 0 else { continue }
            let open  = Double(cols[3]) ?? close
            let volume = Double(cols[7]) ?? 0

            var quote = Quote(
                c: close,
                d: nil,
                dp: nil,
                currency: inferCurrency(canonical: canonical),
                shortName: nil,
                symbol: canonical
            )
            quote.previousClose = open > 0 ? open : nil
            if let prev = quote.previousClose, prev > 0 {
                quote.d = close - prev
                quote.dp = (quote.d! / prev) * 100
            }
            quote.volume = volume
            if !cols[1].isEmpty {
                quote.timestamp = formatter.date(from: cols[1]) ?? Date()
            } else {
                quote.timestamp = Date()
            }
            quotes[canonical] = quote
        }
        return quotes
    }

    private static func parseCandlesCSV(data: Data) -> [Candle] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        guard lines.count > 1 else { return [] }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var out: [Candle] = []
        for raw in lines.dropFirst() {
            let cols = raw.split(separator: ",", omittingEmptySubsequences: false).map { String($0) }
            guard cols.count >= 6 else { continue }
            guard let date = formatter.date(from: cols[0]) else { continue }
            guard let open = Double(cols[1]),
                  let high = Double(cols[2]),
                  let low  = Double(cols[3]),
                  let close = Double(cols[4]) else { continue }
            let volume = Double(cols[5]) ?? 0
            out.append(Candle(date: date, open: open, high: high, low: low, close: close, volume: volume))
        }
        return out
    }

    private static func inferCurrency(canonical: String) -> String {
        let upper = canonical.uppercased()
        if upper.hasSuffix(".IS") { return "TRY" }
        if upper.contains("-USD") { return "USD" }
        if upper.hasSuffix("=X")  { return "USD" }
        if upper.hasSuffix("=F")  { return "USD" }
        return "USD"
    }
}
