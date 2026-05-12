import Foundation

/// Stooq.com adapter. Free, keyless quote snapshots — used by the warm
/// tier to refresh the entire watchlist with a single CSV round-trip.
/// Stooq's historical candle endpoint was gated behind a captcha-bound
/// API key in May 2026, so candle fetching is no longer routed here;
/// Yahoo is the primary daily/intraday source.
/// US/global equities, FX majors, commodities and indices are supported.
/// BIST symbols are not (BorsaPy covers them).
actor StooqProvider {
    static let shared = StooqProvider()

    private let snapshotBase = URL(string: "https://stooq.com/q/l/")!

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

    // MARK: - Symbol mapping

    /// Canonical symbol form used by the rest of the codebase translated
    /// to Stooq's notation. Returns nil for symbols Stooq does not cover
    /// so the caller can route them elsewhere (e.g. BIST -> BorsaPy).
    static func toStooqSymbol(_ raw: String) -> SymbolMapping? {
        let upper = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !upper.isEmpty else { return nil }

        // BIST is not on Stooq.
        if upper.hasSuffix(".IS") { return nil }

        // Index aliases. Symbols returning N/D on Stooq (VIX, TNX,
        // Russell) are omitted so they fall through to Yahoo backstop.
        let indexMap: [String: String] = [
            "^GSPC": "^spx",
            "^IXIC": "^ndq",
            "^DJI":  "^dji",
            "^FTSE": "^ftm",
            "^N225": "^nkx",
            "DX-Y.NYB": "dx.f"
        ]
        if let m = indexMap[upper] { return SymbolMapping(canonical: upper, stooq: m) }

        // FX pairs: Yahoo uses USDTRY=X, Stooq uses usdtry.
        if upper.hasSuffix("=X") {
            let pair = upper.dropLast(2).lowercased()
            return SymbolMapping(canonical: upper, stooq: pair)
        }

        // Commodities: GC=F (gold), CL=F (crude), etc.
        // Brent (BZ=F) returns N/D on Stooq — routed to Yahoo.
        if upper.hasSuffix("=F") {
            let map: [String: String] = [
                "GC=F": "gc.f", "SI=F": "si.f", "HG=F": "hg.f",
                "CL=F": "cl.f", "NG=F": "ng.f"
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

    private static func inferCurrency(canonical: String) -> String {
        let upper = canonical.uppercased()
        if upper.hasSuffix(".IS") { return "TRY" }
        if upper.contains("-USD") { return "USD" }
        if upper.hasSuffix("=X")  { return "USD" }
        if upper.hasSuffix("=F")  { return "USD" }
        return "USD"
    }
}
