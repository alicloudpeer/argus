import Foundation

/// SEC EDGAR (U.S. Securities and Exchange Commission) public data API.
/// Keyless — yalnız `User-Agent` header zorunlu (SEC fair-use kuralı).
///
/// Coverage:
///   * Tüm US public şirketler (10-K, 10-Q, 8-K, Form 4)
///   * XBRL fact'leri: 1993+ tarihçe (recent ~10 yıl en yoğun)
///   * Rate limit: 10 req/sec (resmi)
///
/// Argus rolü:
///   * `.usEquity` fundamentals chain'inde Yahoo'dan **sonra**, FMP'den
///     **önce** — Yahoo'nun limited dataset'inin yerini doldurur,
///     FMP'nin 250/day free quota'sını korur.
///   * Tarihsel revenue/netIncome/cashFlow ham veri — Buffett tarzı
///     analiz ve DCF için SEC'in resmi XBRL serileri en güvenilir.
///
/// Ticker → CIK lookup'ı `company_tickers.json` (~3 MB) ile yapılır;
/// 24h cache ile bellekte ve diskte tutulur.
actor SECEdgarProvider {
    static let shared = SECEdgarProvider()

    private let dataBaseURL = URL(string: "https://data.sec.gov")!
    private let wwwBaseURL  = URL(string: "https://www.sec.gov")!

    /// SEC fair-use kuralı: `User-Agent` zorunlu, gerçek bir kişi/şirket
    /// + email içermeli. Format: "App Name email@domain.com".
    private let userAgent = "Argus iOS argus@argus.app"

    private let session: URLSession

    // Ticker → CIK haritası (10-digit zero-padded string)
    private var tickerToCIK: [String: String] = [:]
    private var tickerMapFetchedAt: Date?
    private let tickerMapTTL: TimeInterval = 86400  // 24h

    // CompanyFacts cache (symbol → parsed FinancialsData + fetched)
    private var factsCache: [String: CachedFacts] = [:]
    private let factsTTL: TimeInterval = 86400  // 24h

    private struct CachedFacts {
        let data: FinancialsData
        let fetchedAt: Date
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: config)
    }

    nonisolated var hasKey: Bool { true }  // keyless

    // MARK: - Fundamentals

    func fetchFundamentals(symbol: String) async throws -> FinancialsData {
        let upper = symbol.uppercased().replacingOccurrences(of: ".US", with: "")
        guard Self.isLikelyUSEquity(upper) else {
            throw HeimdallCoreError(category: .symbolNotFound, code: 422,
                                    message: "SEC EDGAR: \(upper) is not a US equity",
                                    bodyPrefix: "")
        }

        // Cache hit
        if let cached = factsCache[upper],
           -cached.fetchedAt.timeIntervalSinceNow < factsTTL {
            return cached.data
        }

        // 1. ticker → CIK
        guard let cik = try await resolveCIK(ticker: upper) else {
            throw HeimdallCoreError(category: .symbolNotFound, code: 404,
                                    message: "SEC EDGAR: CIK not found for \(upper)",
                                    bodyPrefix: "")
        }

        // 2. fetch companyfacts JSON (~3-5 MB)
        let url = dataBaseURL.appendingPathComponent("/api/xbrl/companyfacts/CIK\(cik).json")
        let data = try await get(url: url)

        // 3. parse XBRL → FinancialsData
        let parsed = Self.parseCompanyFacts(data: data, symbol: upper)
        factsCache[upper] = CachedFacts(data: parsed, fetchedAt: Date())
        return parsed
    }

    // MARK: - Ticker → CIK lookup

    private func resolveCIK(ticker: String) async throws -> String? {
        try await refreshTickerMapIfNeeded()
        return tickerToCIK[ticker.uppercased()]
    }

    private func refreshTickerMapIfNeeded() async throws {
        let now = Date()
        if let fetched = tickerMapFetchedAt,
           now.timeIntervalSince(fetched) < tickerMapTTL,
           !tickerToCIK.isEmpty {
            return
        }
        let url = wwwBaseURL.appendingPathComponent("/files/company_tickers.json")
        let data = try await get(url: url)
        // Response shape: {"0": {"cik_str": 320193, "ticker": "AAPL", "title": "Apple Inc."}, "1": {...}, ...}
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        var map: [String: String] = [:]
        for (_, value) in raw {
            guard let entry = value as? [String: Any],
                  let cikNum = entry["cik_str"] as? Int,
                  let ticker = entry["ticker"] as? String else { continue }
            map[ticker.uppercased()] = String(format: "%010d", cikNum)
        }
        tickerToCIK = map
        tickerMapFetchedAt = now
    }

    // MARK: - HTTP

    private func get(url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("data.sec.gov", forHTTPHeaderField: "Host")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 403 {
            throw HeimdallCoreError(category: .entitlementDenied, code: 403,
                                    message: "SEC EDGAR rejected (User-Agent invalid?)",
                                    bodyPrefix: "")
        }
        if http.statusCode == 429 {
            throw HeimdallCoreError(category: .rateLimited, code: 429,
                                    message: "SEC EDGAR rate-limit (10 r/sec breached)",
                                    bodyPrefix: "")
        }
        if http.statusCode == 404 {
            throw HeimdallCoreError(category: .symbolNotFound, code: 404,
                                    message: "SEC EDGAR 404",
                                    bodyPrefix: "")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse,
                           userInfo: [NSLocalizedDescriptionKey: "SEC HTTP \(http.statusCode)"])
        }
        return data
    }

    // MARK: - Symbol filter

    /// Çok kaba bir filtre — `.IS`, `=X`, `=F`, `^`, `-USD` gibi US-equity
    /// olmayan sembolleri ön elemeden geçer. Hatalı pozitifler olabilir
    /// (her US ticker bu filtreden geçmek zorunda değil), `resolveCIK`
    /// nil dönerse zaten chain bir sonrakine düşer.
    static func isLikelyUSEquity(_ symbol: String) -> Bool {
        let upper = symbol.uppercased()
        if upper.hasSuffix(".IS") { return false }
        if upper.hasSuffix("=X")  { return false }
        if upper.hasSuffix("=F")  { return false }
        if upper.hasPrefix("^")   { return false }
        if upper.contains("-USD") { return false }
        return true
    }

    // MARK: - XBRL parse

    /// SEC companyfacts JSON formatı:
    /// ```
    /// {
    ///   "cik": 320193,
    ///   "entityName": "Apple Inc.",
    ///   "facts": {
    ///     "us-gaap": {
    ///       "Revenues": { "label": "...", "units": { "USD": [ {"start":"...","end":"...","val":...,"form":"10-K","fy":2023,...}, ... ]}},
    ///       "NetIncomeLoss": { ... },
    ///       ...
    ///     }
    ///   }
    /// }
    /// ```
    /// Argus için gerekenleri çıkarıyoruz; her concept için en yeni
    /// 10-K (annual) değerini birincil kabul ediyoruz.
    fileprivate static func parseCompanyFacts(data: Data, symbol: String) -> FinancialsData {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let facts = root["facts"] as? [String: Any],
              let usGaap = facts["us-gaap"] as? [String: Any] else {
            return Self.emptyFinancials(symbol: symbol)
        }

        let totalRevenue       = latestAnnualUSD(usGaap: usGaap, concepts: ["RevenueFromContractWithCustomerExcludingAssessedTax", "Revenues", "SalesRevenueNet"])
        let netIncome          = latestAnnualUSD(usGaap: usGaap, concepts: ["NetIncomeLoss"])
        let totalEquity        = latestAnnualUSD(usGaap: usGaap, concepts: ["StockholdersEquity", "StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest"])
        let operatingIncome    = latestAnnualUSD(usGaap: usGaap, concepts: ["OperatingIncomeLoss"])
        let depreciation       = latestAnnualUSD(usGaap: usGaap, concepts: ["DepreciationDepletionAndAmortization", "DepreciationAndAmortization"])
        let shortTermDebt      = latestAnnualUSD(usGaap: usGaap, concepts: ["ShortTermBorrowings", "LongTermDebtCurrent"])
        let longTermDebt       = latestAnnualUSD(usGaap: usGaap, concepts: ["LongTermDebtNoncurrent", "LongTermDebt"])
        let operatingCashflow  = latestAnnualUSD(usGaap: usGaap, concepts: ["NetCashProvidedByUsedInOperatingActivities"])
        let capEx              = latestAnnualUSD(usGaap: usGaap, concepts: ["PaymentsToAcquirePropertyPlantAndEquipment"])
        let cash               = latestAnnualUSD(usGaap: usGaap, concepts: ["CashAndCashEquivalentsAtCarryingValue", "CashCashEquivalentsRestrictedCashAndRestrictedCashEquivalents"])
        let eps                = latestAnnualUSD(usGaap: usGaap, concepts: ["EarningsPerShareDiluted", "EarningsPerShareBasic"])

        // EBITDA = OperatingIncome + Depreciation (US-GAAP'te direkt yok)
        let ebitda: Double? = {
            guard let op = operatingIncome else { return nil }
            return op + (depreciation ?? 0)
        }()

        let revenueHistory = annualHistoryUSD(usGaap: usGaap, concepts: ["RevenueFromContractWithCustomerExcludingAssessedTax", "Revenues", "SalesRevenueNet"], limit: 8)
        let netIncomeHistory = annualHistoryUSD(usGaap: usGaap, concepts: ["NetIncomeLoss"], limit: 8)

        return FinancialsData(
            symbol: symbol,
            currency: "USD",
            lastUpdated: Date(),
            totalRevenue: totalRevenue,
            netIncome: netIncome,
            totalShareholderEquity: totalEquity,
            marketCap: nil,        // SEC vermez — Yahoo/Alpaca'dan gelir
            revenueHistory: revenueHistory,
            netIncomeHistory: netIncomeHistory,
            ebitda: ebitda,
            shortTermDebt: shortTermDebt,
            longTermDebt: longTermDebt,
            operatingCashflow: operatingCashflow,
            capitalExpenditures: capEx,
            cashAndCashEquivalents: cash,
            peRatio: nil,
            forwardPERatio: nil,
            priceToBook: nil,
            evToEbitda: nil,
            dividendYield: nil,
            earningsPerShare: eps,
            forwardGrowthEstimate: nil,
            targetMeanPrice: nil,
            targetHighPrice: nil,
            targetLowPrice: nil,
            recommendationMean: nil,
            numberOfAnalystOpinions: nil
        )
    }

    private static func emptyFinancials(symbol: String) -> FinancialsData {
        FinancialsData(
            symbol: symbol, currency: "USD", lastUpdated: Date(),
            totalRevenue: nil, netIncome: nil, totalShareholderEquity: nil, marketCap: nil,
            revenueHistory: [], netIncomeHistory: [],
            ebitda: nil, shortTermDebt: nil, longTermDebt: nil,
            operatingCashflow: nil, capitalExpenditures: nil, cashAndCashEquivalents: nil,
            peRatio: nil, forwardPERatio: nil, priceToBook: nil, evToEbitda: nil,
            dividendYield: nil, earningsPerShare: nil, forwardGrowthEstimate: nil,
            targetMeanPrice: nil, targetHighPrice: nil, targetLowPrice: nil,
            recommendationMean: nil, numberOfAnalystOpinions: nil
        )
    }

    /// Birden çok concept ismi denenir; ilk eşleşenin en yeni "form=10-K"
    /// değeri döner. Tüm fact'lerin USD birim varsayılır (Argus US-only).
    private static func latestAnnualUSD(usGaap: [String: Any], concepts: [String]) -> Double? {
        for name in concepts {
            guard let concept = usGaap[name] as? [String: Any],
                  let units = concept["units"] as? [String: Any],
                  let usdArr = units["USD"] as? [[String: Any]] else { continue }

            // 10-K'lar genelde "fy":YYYY,"fp":"FY". En son fy'yi seç.
            let annuals = usdArr.filter { ($0["form"] as? String) == "10-K" && ($0["fp"] as? String) == "FY" }
            if let latest = annuals.max(by: { ($0["fy"] as? Int ?? 0) < ($1["fy"] as? Int ?? 0) }),
               let val = latest["val"] as? Double {
                return val
            } else if let latest = annuals.max(by: { ($0["fy"] as? Int ?? 0) < ($1["fy"] as? Int ?? 0) }),
                      let intVal = latest["val"] as? Int {
                return Double(intVal)
            }
        }
        return nil
    }

    /// Annual USD geçmiş — son N yıl (en yeni → en eski sıralı).
    private static func annualHistoryUSD(usGaap: [String: Any], concepts: [String], limit: Int) -> [Double] {
        for name in concepts {
            guard let concept = usGaap[name] as? [String: Any],
                  let units = concept["units"] as? [String: Any],
                  let usdArr = units["USD"] as? [[String: Any]] else { continue }

            let annuals = usdArr
                .filter { ($0["form"] as? String) == "10-K" && ($0["fp"] as? String) == "FY" }
                .sorted { ($0["fy"] as? Int ?? 0) > ($1["fy"] as? Int ?? 0) }
                .prefix(limit)

            let values: [Double] = annuals.compactMap {
                ($0["val"] as? Double) ?? (($0["val"] as? Int).map(Double.init))
            }
            if !values.isEmpty { return values }
        }
        return []
    }
}
