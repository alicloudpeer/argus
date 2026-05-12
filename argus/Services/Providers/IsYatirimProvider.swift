import Foundation

/// İş Yatırım public JSON endpoint adapter. Keyless.
///
/// Endpoint: `https://www.isyatirim.com.tr/_layouts/15/IsYatirim.Website/Common/Data.aspx/HisseTekil`
///   * Query: `hisse={SYMBOL}&startdate=DD-MM-YYYY&enddate=DD-MM-YYYY`
///   * NOT `.json` suffix — sunucu Spring DateTime conversion'a takılır.
///
/// Coverage: 758 BIST hisse, günlük OHLCV + ağırlıklı ortalama fiyat
/// (AOF) + USD/TRY rate + market cap + halka açıklık (HAO).
///
/// Argus rolü:
///   * `.bist` candle chain'inde BorsaPy'den SONRA, Yahoo `.IS`'den ÖNCE.
///     BorsaPy cold-start 30-60s yiyor; İş Yatırım her zaman uyanık
///     (CDN destekli kurumsal endpoint).
///   * `.bist` quote chain'inde sonuncu fallback (günlük close, ama
///     BorsaPy/Yahoo fail edince hayat kurtarıcı).
///
/// **Lisans notu**: ToS net "redistribution yasak" maddesi içeriyor.
/// Kullanıcının kendi cihazında tüketim genel kabul; bir SaaS API
/// olarak yeniden satış yapılamaz. Argus kullanıcı uygulaması olduğu
/// için bu kullanım uyumlu.
actor IsYatirimProvider {
    static let shared = IsYatirimProvider()

    private let baseURL = URL(string: "https://www.isyatirim.com.tr/_layouts/15/IsYatirim.Website/Common/Data.aspx/HisseTekil")!
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    nonisolated var hasKey: Bool { true }  // keyless

    // MARK: - Candles (daily OHLCV)

    /// Returns daily candles for a BIST symbol. `symbol` accepts both
    /// `SASA` and `SASA.IS` formats — `.IS` suffix is stripped.
    func fetchCandles(symbol: String, days: Int = 90) async throws -> [Candle] {
        guard let ticker = Self.toBistTicker(symbol) else {
            throw HeimdallCoreError(category: .symbolNotFound, code: 422,
                                    message: "İş Yatırım: \(symbol) is not a BIST ticker",
                                    bodyPrefix: "")
        }

        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let formatter = Self.dateFormatter
        let startStr = formatter.string(from: start)
        let endStr = formatter.string(from: end)

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "hisse",     value: ticker),
            URLQueryItem(name: "startdate", value: startStr),
            URLQueryItem(name: "enddate",   value: endStr)
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        let response: TekilResponse = try await get(url: url)
        guard response.ok, let rows = response.value else {
            throw HeimdallCoreError(category: .emptyPayload, code: 204,
                                    message: "İş Yatırım empty for \(ticker): \(response.errorDescription ?? "")",
                                    bodyPrefix: "")
        }

        let candles: [Candle] = rows.compactMap { row in
            guard let date = formatter.date(from: row.HGDG_TARIH) else { return nil }
            let open = row.HGDG_AOF ?? row.HGDG_KAPANIS
            // Hacim TRY cinsinden geliyor (HGDG_HACIM). Adetli hacim
            // istersek HG_HACIM kullanılır — Candle.volume için adetli
            // tercih ediyoruz (UI normalize).
            let volume = row.HG_HACIM ?? row.HGDG_HACIM ?? 0
            return Candle(
                date: date,
                open: open,
                high: row.HGDG_MAX,
                low: row.HGDG_MIN,
                close: row.HGDG_KAPANIS,
                volume: volume
            )
        }
        return candles.sorted { $0.date < $1.date }
    }

    // MARK: - Quote (latest from history)

    /// Returns the latest available daily close as a Quote. İş Yatırım'ın
    /// real-time tick endpoint'i yok; günlük kapanış + bir önceki güne
    /// göre değişim hesaplanır. UI için "15-min delayed BIST" zaten
    /// standart, bu da onun kapsamı içinde.
    func fetchQuote(symbol: String) async throws -> Quote {
        let candles = try await fetchCandles(symbol: symbol, days: 7)
        guard let latest = candles.last else {
            throw HeimdallCoreError(category: .emptyPayload, code: 204,
                                    message: "İş Yatırım no recent candle for \(symbol)",
                                    bodyPrefix: "")
        }
        let previous = candles.count >= 2 ? candles[candles.count - 2] : nil
        let prevClose = previous?.close
        let delta = prevClose.map { latest.close - $0 }
        let deltaPct: Double? = {
            guard let prev = prevClose, prev > 0 else { return nil }
            return ((latest.close - prev) / prev) * 100.0
        }()

        var quote = Quote(
            c: latest.close,
            d: delta,
            dp: deltaPct,
            currency: "TRY",
            shortName: nil,
            symbol: symbol.uppercased()
        )
        quote.previousClose = prevClose
        quote.volume = latest.volume
        quote.timestamp = latest.date
        return quote
    }

    // MARK: - HTTP

    private func get<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko)",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("tr-TR,tr;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://www.isyatirim.com.tr/", forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 429 {
            throw HeimdallCoreError(category: .rateLimited, code: 429,
                                    message: "İş Yatırım rate limit",
                                    bodyPrefix: "")
        }
        if http.statusCode == 403 {
            throw HeimdallCoreError(category: .entitlementDenied, code: 403,
                                    message: "İş Yatırım blocked",
                                    bodyPrefix: "")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse,
                           userInfo: [NSLocalizedDescriptionKey: "İş Yatırım HTTP \(http.statusCode)"])
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Mapping

    static func toBistTicker(_ raw: String) -> String? {
        let upper = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !upper.isEmpty else { return nil }
        if upper.hasSuffix(".IS") {
            return String(upper.dropLast(3))
        }
        // SymbolResolver.bistSymbols üyeliğine güvenmiyoruz — endpoint
        // bilinmeyen ticker için zaten `ok:false` döner; chain bir
        // sonrakine düşer. Bu nedenle 3-5 harfli all-letter ise denenir.
        if upper.count >= 3, upper.count <= 6, upper.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return upper
        }
        return nil
    }

    // MARK: - Date helper

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd-MM-yyyy"
        f.timeZone = TimeZone(identifier: "Europe/Istanbul")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Decode shapes

    private struct TekilResponse: Decodable {
        let ok: Bool
        let errorCode: String?
        let errorDescription: String?
        let value: [Row]?
    }

    /// `HGDG_*` alanları İş Yatırım'ın canlı seans (HG = His. Genel
    /// Detay/Günlük) — gün sonunda gerçek kapanışla aynı oluyor.
    /// `HG_*` alanları da paralel ama farklı bir sistemden geliyor.
    private struct Row: Decodable {
        let HGDG_HS_KODU: String
        let HGDG_TARIH: String        // "DD-MM-YYYY"
        let HGDG_KAPANIS: Double
        let HGDG_AOF: Double?         // ağırlıklı ortalama fiyat
        let HGDG_MIN: Double
        let HGDG_MAX: Double
        let HGDG_HACIM: Double?       // TRY cinsinden
        let HG_HACIM: Double?         // adetli
        let DD_DEGER: Double?         // USD/TRY rate
        let PD: Double?               // piyasa değeri TRY
        let PD_USD: Double?           // piyasa değeri USD
    }
}
