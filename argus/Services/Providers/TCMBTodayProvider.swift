import Foundation

/// TCMB (Türkiye Cumhuriyet Merkez Bankası) günlük döviz kurları —
/// resmi `today.xml` endpoint'i. Key gerektirmez, kamu kaynağıdır.
///
/// Endpoint: `https://www.tcmb.gov.tr/kurlar/today.xml`
/// Tarihli: `https://www.tcmb.gov.tr/kurlar/YYYYMM/DDMMYYYY.xml`
///
/// Coverage:
///   * Tüm TCMB döviz sepeti (~22 currency) — USD, EUR, GBP, CHF, JPY, ...
///   * Her currency için: ForexBuying/Selling (interbank) + BanknoteBuying/Selling
///   * Tarih: işlem günü 15:30 sonrası açıklanır
///
/// Edge case'ler:
///   * Hafta sonu (Cumartesi/Pazar) → 404; önceki iş gününe fallback
///   * Resmi tatil → 404; en fazla 7 gün geriye dön
///   * Hafta içi gün ortası → bir önceki günün rate'i yayında olabilir
///
/// Argus rolü:
///   * TR FX (USDTRY=X, EURTRY=X) için **resmi referans** — TCMB EVDS key
///     gerektirir, today.xml ise hep keyless. EVDS down olduğunda public
///     fallback olarak `TCMBDataService` zaten kullanıyor; bu provider
///     onu Heimdall chain'ine standalone bağlar.
actor TCMBTodayProvider {
    static let shared = TCMBTodayProvider()

    private let baseURL = URL(string: "https://www.tcmb.gov.tr/kurlar")!
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 2
        config.timeoutIntervalForRequest = 12
        self.session = URLSession(configuration: config)
    }

    nonisolated var hasKey: Bool { true }  // keyless

    // MARK: - Quote

    /// TRY-cinsi quote döner. Yalnız TCMB'de bulunan currency kodları
    /// için çalışır (USDTRY=X, EURTRY=X, GBPTRY=X, ...).
    func fetchQuote(symbol: String) async throws -> Quote {
        guard let pair = Self.parsePair(symbol) else {
            throw HeimdallCoreError(category: .symbolNotFound, code: 422,
                                    message: "TCMB cannot parse \(symbol)",
                                    bodyPrefix: "")
        }
        // TCMB sadece TRY karşılığı yayınlar (foreign → TRY direction).
        guard pair.quote == "TRY" else {
            throw HeimdallCoreError(category: .symbolNotFound, code: 422,
                                    message: "TCMB only publishes TRY rates",
                                    bodyPrefix: "")
        }

        let xml = try await fetchLatestXML()
        guard let rates = Self.parse(xml: xml, currencyCode: pair.base) else {
            throw HeimdallCoreError(category: .emptyPayload, code: 204,
                                    message: "TCMB has no \(pair.base) rate today",
                                    bodyPrefix: "")
        }

        // Argus'un tek "current price" beklediği yere ForexSelling veriyoruz
        // — bu interbank ortalamasına yakın ve çoğu UI için en doğal
        // gösterim. ForexBuying'i `previousClose` slot'una yazmıyoruz
        // çünkü o anlamsal olarak "dünkü kapanış" değil.
        var quote = Quote(
            c: rates.forexSelling,
            d: 0,
            dp: 0,
            currency: "TRY",
            shortName: "\(pair.base)/TRY (TCMB)",
            symbol: symbol.uppercased()
        )
        quote.previousClose = rates.forexBuying      // alış-satış spread için
        quote.timestamp = rates.date
        return quote
    }

    // MARK: - XML fetch with weekend/holiday fallback

    /// `today.xml` 404 dönerse önceki iş gününe geçer. En fazla 7 gün
    /// geriye gider; daha eskisinde gerçek bir veri eksiği vardır.
    private func fetchLatestXML() async throws -> Data {
        // 1. today.xml (çoğu zaman yayında)
        let todayURL = baseURL.appendingPathComponent("today.xml")
        if let data = try await tryFetch(url: todayURL) {
            return data
        }

        // 2. Geriye dönük dene (7 güne kadar)
        let calendar = Calendar(identifier: .gregorian)
        var date = Date()
        for _ in 0..<7 {
            date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
            let url = Self.archivedURL(base: baseURL, date: date)
            if let data = try await tryFetch(url: url) {
                return data
            }
        }
        throw HeimdallCoreError(category: .emptyPayload, code: 404,
                                message: "TCMB no rates in last 7 days",
                                bodyPrefix: "")
    }

    private func tryFetch(url: URL) async throws -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            if http.statusCode == 404 { return nil }
            guard (200..<300).contains(http.statusCode) else { return nil }
            return data
        } catch {
            return nil  // network errors → try next date
        }
    }

    /// `https://www.tcmb.gov.tr/kurlar/202605/11052026.xml`
    private static func archivedURL(base: URL, date: Date) -> URL {
        let calendar = Calendar(identifier: .gregorian)
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let yyyymm = String(format: "%04d%02d", comps.year ?? 1970, comps.month ?? 1)
        let ddmmyyyy = String(format: "%02d%02d%04d",
                              comps.day ?? 1, comps.month ?? 1, comps.year ?? 1970)
        return base
            .appendingPathComponent(yyyymm)
            .appendingPathComponent("\(ddmmyyyy).xml")
    }

    // MARK: - XML parse

    struct CurrencyRates {
        let code: String
        let unit: Int
        let forexBuying: Double
        let forexSelling: Double
        let banknoteBuying: Double?
        let banknoteSelling: Double?
        let date: Date
    }

    /// XMLParser delegate ile lightweight stream parse. Yalnız hedef
    /// `Kod` (örn "USD") için tag içeriklerini topluyor.
    fileprivate static func parse(xml: Data, currencyCode target: String) -> CurrencyRates? {
        let delegate = TCMBXMLParserDelegate(targetCode: target.uppercased())
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        guard parser.parse(), delegate.found else { return nil }

        let unit = Int(delegate.unit) ?? 1
        guard let fb = Double(delegate.forexBuying.replacingOccurrences(of: ",", with: ".")),
              let fs = Double(delegate.forexSelling.replacingOccurrences(of: ",", with: "."))
        else { return nil }

        // TCMB bazı küçük para birimlerini 100 birim üzerinden yayınlar
        // (JPY, KRW gibi). Argus tarafında 1 birim cinsinden gösteriyoruz.
        let factor = unit > 0 ? Double(unit) : 1
        let forexBuying = fb / factor
        let forexSelling = fs / factor
        let banknoteBuying = Double(delegate.banknoteBuying.replacingOccurrences(of: ",", with: ".")).map { $0 / factor }
        let banknoteSelling = Double(delegate.banknoteSelling.replacingOccurrences(of: ",", with: ".")).map { $0 / factor }

        let date = parseDate(delegate.date) ?? Date()

        return CurrencyRates(
            code: target.uppercased(),
            unit: unit,
            forexBuying: forexBuying,
            forexSelling: forexSelling,
            banknoteBuying: banknoteBuying,
            banknoteSelling: banknoteSelling,
            date: date
        )
    }

    // MARK: - Symbol parsing

    struct Pair {
        let base: String
        let quote: String
    }

    /// Yahoo formatı `USDTRY=X` → base=USD, quote=TRY.
    /// TCMB sadece TRY-cinsi yayınladığı için `quote == "TRY"` olmayan
    /// pair'ler `fetchQuote` tarafından reddedilir.
    static func parsePair(_ raw: String) -> Pair? {
        let upper = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !upper.isEmpty else { return nil }

        if upper.hasSuffix("=X"), upper.count == 8 {
            let body = String(upper.dropLast(2))
            let base = String(body.prefix(3))
            let quote = String(body.suffix(3))
            return Pair(base: base, quote: quote)
        }
        return nil
    }

    // MARK: - Date helper

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        f.timeZone = TimeZone(identifier: "Europe/Istanbul")
        f.locale = Locale(identifier: "tr_TR")
        return f
    }()

    private static func parseDate(_ value: String) -> Date? {
        dateFormatter.date(from: value)
    }
}

// MARK: - XMLParser Delegate

/// Tek bir Currency entry'sini hedef alarak stream parse eder. TCMB XML
/// 22-30 currency içeriyor, hepsini decode etmek savurganlık; sadece
/// `targetCode`'a denk gelen tag'leri yakalıyoruz.
private final class TCMBXMLParserDelegate: NSObject, XMLParserDelegate {
    let targetCode: String

    var found = false
    private var inTarget = false
    private var currentElement = ""

    var unit = "1"
    var forexBuying = ""
    var forexSelling = ""
    var banknoteBuying = ""
    var banknoteSelling = ""
    var date = ""

    init(targetCode: String) {
        self.targetCode = targetCode
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName

        if elementName == "Tarih_Date", let tarih = attributeDict["Tarih"] {
            date = tarih
        }
        if elementName == "Currency",
           let kod = attributeDict["Kod"], kod.uppercased() == targetCode {
            inTarget = true
            found = true
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "Currency" {
            inTarget = false
        }
        currentElement = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inTarget else { return }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch currentElement {
        case "Unit":            unit += "" ; unit = trimmed
        case "ForexBuying":     forexBuying += trimmed
        case "ForexSelling":    forexSelling += trimmed
        case "BanknoteBuying":  banknoteBuying += trimmed
        case "BanknoteSelling": banknoteSelling += trimmed
        default: break
        }
    }
}
