import Foundation

/// World Bank Open Data adapter. Keyless. Cross-country macro
/// göstergeleri için kanıtlanmış kaynak.
///
/// Endpoint:
///   `https://api.worldbank.org/v2/country/{ISO2}/indicator/{INDICATOR}?format=json&date=YYYY:YYYY`
///
/// Response heterogen — top-level array iki eleman:
///   `[ { page, pages, per_page, total, ... }, [ {indicator, country, date, value}, ... ] ]`
///
/// Coverage:
///   * 200+ ülke (TR dahil)
///   * Binlerce indikatör (GDP growth, CPI, unemployment, FDI, etc.)
///   * Yıllık veri (annual frequency)
///
/// Argus rolü:
///   * `FredProvider`'a tamamlayıcı — FRED US-merkezli, WB global+TR
///     cross-country karşılaştırma için.
///   * DCF terminal growth rate hesaplaması (10-yıllık GDP growth ort.)
///   * Demeter makro panellerinde TR vs ABD GDP/CPI/unemployment.
actor WorldBankProvider {
    static let shared = WorldBankProvider()

    private let baseURL = URL(string: "https://api.worldbank.org/v2")!
    private let session: URLSession

    // Per-key cache (24h TTL — annual data anyway)
    private var cache: [String: CachedSeries] = [:]
    private let cacheTTL: TimeInterval = 86400

    private struct CachedSeries {
        let observations: [Observation]
        let fetchedAt: Date
    }

    /// (date, value) tuple equivalent
    public struct Observation: Sendable {
        public let year: Int
        public let value: Double
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 3
        config.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: config)
    }

    nonisolated var hasKey: Bool { true }  // keyless

    // MARK: - Public API

    /// `fetchIndicator(country: "TR", indicator: "NY.GDP.MKTP.KD.ZG", years: 10)`
    /// Returns descending-year sorted observations (most recent first).
    public func fetchIndicator(country: String, indicator: String, years: Int = 10) async throws -> [Observation] {
        let cacheKey = "\(country.uppercased())|\(indicator)|\(years)"
        if let cached = cache[cacheKey],
           -cached.fetchedAt.timeIntervalSinceNow < cacheTTL {
            return cached.observations
        }

        let calendar = Calendar(identifier: .gregorian)
        let endYear = calendar.component(.year, from: Date())
        let startYear = endYear - years + 1

        var components = URLComponents(
            url: baseURL.appendingPathComponent("/country/\(country.uppercased())/indicator/\(indicator)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "date",   value: "\(startYear):\(endYear)"),
            URLQueryItem(name: "per_page", value: "\(years + 5)")
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 404 {
            throw HeimdallCoreError(category: .symbolNotFound, code: 404,
                                    message: "WorldBank 404 for \(country)/\(indicator)",
                                    bodyPrefix: "")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse,
                           userInfo: [NSLocalizedDescriptionKey: "WB HTTP \(http.statusCode)"])
        }

        let observations = Self.parseResponse(data: data)
        cache[cacheKey] = CachedSeries(observations: observations, fetchedAt: Date())
        return observations
    }

    /// Convenience: en son tek değer.
    public func fetchLatest(country: String, indicator: String) async throws -> Observation? {
        let obs = try await fetchIndicator(country: country, indicator: indicator, years: 3)
        return obs.first
    }

    /// Convenience: N-yıl ortalama (DCF terminal growth gibi).
    public func fetchMean(country: String, indicator: String, years: Int = 10) async throws -> Double? {
        let obs = try await fetchIndicator(country: country, indicator: indicator, years: years)
        guard !obs.isEmpty else { return nil }
        return obs.map(\.value).reduce(0, +) / Double(obs.count)
    }

    // MARK: - Parse

    /// Response: `[ {meta}, [observations] ]` — JSONSerialization ile
    /// dynamic parse, sadece [1] indeksindeki array'i alıyoruz.
    fileprivate static func parseResponse(data: Data) -> [Observation] {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [Any],
              arr.count >= 2,
              let rows = arr[1] as? [[String: Any]] else {
            return []
        }
        var out: [Observation] = []
        for row in rows {
            guard let dateStr = row["date"] as? String,
                  let year = Int(dateStr),
                  let value = row["value"] as? Double else { continue }
            out.append(Observation(year: year, value: value))
        }
        return out.sorted { $0.year > $1.year }   // descending — most recent first
    }
}

// MARK: - Argus shortcut helpers

extension WorldBankProvider {
    /// Türkiye GDP growth (annual %) — DCF terminal growth için.
    func turkeyGDPGrowth(years: Int = 10) async throws -> [Observation] {
        try await fetchIndicator(country: "TR", indicator: "NY.GDP.MKTP.KD.ZG", years: years)
    }

    /// Türkiye Inflation, CPI (annual %).
    func turkeyCPI(years: Int = 10) async throws -> [Observation] {
        try await fetchIndicator(country: "TR", indicator: "FP.CPI.TOTL.ZG", years: years)
    }

    /// Türkiye Unemployment (% of labor force).
    func turkeyUnemployment(years: Int = 10) async throws -> [Observation] {
        try await fetchIndicator(country: "TR", indicator: "SL.UEM.TOTL.ZS", years: years)
    }
}
