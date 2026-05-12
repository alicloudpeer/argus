import Foundation

/// Per-provider rate-limit budget. Şu an `HeimdallNetwork` her provider
/// için hardcoded sliding-window + inflight cap kullanıyor; bu tip
/// kayıt sistemi onun yanında **görünür** kapasiteyi takip eder —
/// kullanıcıya "Alpaca kotamın %X'i doldu" UI rozeti göstermek,
/// `ServiceHealthMonitor` paneline beslemek ve predictive throttle
/// (uzun vadede) için ortak kayıt katmanı.
///
/// 2026-05-11: minimal iskelet — register + record + remaining math.
/// Predictive throttle Faz 2'de eklenecek (mevcut HeimdallNetwork
/// throttling zaten reactive davranıyor).
public struct ProviderQuota: Sendable, Hashable {
    public let provider: String
    public let endpoint: String

    /// Per-minute sliding window (örn. Alpaca 200).
    public let perMinute: Int?
    /// Per-day rolling (örn. FMP free 250/day).
    public let perDay: Int?
    /// Per-month rolling (örn. CoinGecko Demo 10k/month).
    public let perMonth: Int?
    /// Burst capacity — token bucket için (gelecek için ayrılmış).
    public let burstCapacity: Int?

    public init(provider: String, endpoint: String,
                perMinute: Int? = nil, perDay: Int? = nil,
                perMonth: Int? = nil, burstCapacity: Int? = nil) {
        self.provider = provider
        self.endpoint = endpoint
        self.perMinute = perMinute
        self.perDay = perDay
        self.perMonth = perMonth
        self.burstCapacity = burstCapacity
    }

    public var key: String { "\(provider):\(endpoint)" }
}

/// Per-(provider, endpoint) tüketim sayacı.
public struct ProviderUsage: Sendable {
    public var minuteHits: Int = 0
    public var dayHits: Int = 0
    public var monthHits: Int = 0
    public var lastMinuteReset: Date = Date()
    public var lastDayReset: Date = Date()
    public var lastMonthReset: Date = Date()

    public mutating func record() {
        let now = Date()
        rollWindows(now: now)
        minuteHits += 1
        dayHits += 1
        monthHits += 1
    }

    public mutating func rollWindows(now: Date) {
        let cal = Calendar(identifier: .gregorian)
        if now.timeIntervalSince(lastMinuteReset) >= 60 {
            minuteHits = 0
            lastMinuteReset = now
        }
        if !cal.isDate(now, inSameDayAs: lastDayReset) {
            dayHits = 0
            lastDayReset = now
        }
        let nowMonth = cal.component(.month, from: now)
        let prevMonth = cal.component(.month, from: lastMonthReset)
        if nowMonth != prevMonth {
            monthHits = 0
            lastMonthReset = now
        }
    }
}

/// Tek noktadan provider kotalarını kaydet ve runtime tüketimini takip
/// et. Şu an mevcut sliding-window kontrolünü değiştirmiyor — yalnız
/// `ServiceHealthMonitor` ve UI için **görünür** veri sağlıyor.
actor ProviderQuotaRegistry {
    public static let shared = ProviderQuotaRegistry()

    private var quotas: [String: ProviderQuota] = [:]
    private var usages: [String: ProviderUsage] = [:]

    private init() {
        registerDefaults()
    }

    /// Argus'ta aktif provider'ların bilinen sınırları. Provider initleri
    /// daha sonra `register` çağırarak kendi sınırlarını ezebilir veya
    /// daha hassas endpoint-spesifik kayıt yapabilir.
    private func registerDefaults() {
        let defaults: [ProviderQuota] = [
            // Alpaca: paper free, 200 r/min
            ProviderQuota(provider: "alpaca",      endpoint: "quote",  perMinute: 200),
            ProviderQuota(provider: "alpaca",      endpoint: "candle", perMinute: 200),

            // Stooq: belgelenmemiş ama anonim günlük hit limit var
            // (gözlem: birkaç bin batch quote sonrası 429 değil "Exceeded
            //  the daily hits limit" CSV cevabı).
            ProviderQuota(provider: "stooq",       endpoint: "quote",  perMinute: 600, perDay: 5000),

            // Yahoo: dökümante limit yok; HeimdallNetwork 300 r/min + 4
            // inflight cap tuningi var. Burası onunla aynı sayıyı
            // temsili tutar.
            ProviderQuota(provider: "yahoo",       endpoint: "quote",  perMinute: 300),
            ProviderQuota(provider: "yahoo",       endpoint: "candle", perMinute: 300),

            // Finnhub: free 60 r/min
            ProviderQuota(provider: "finnhub",     endpoint: "quote",  perMinute: 60),
            ProviderQuota(provider: "finnhub",     endpoint: "candle", perMinute: 60),

            // Binance: public 6000 weight/min, klines weight 2-5
            ProviderQuota(provider: "binance",     endpoint: "candle", perMinute: 1200),

            // FMP: free 30 r/min + 250 req/day (gerçek darboğaz)
            ProviderQuota(provider: "fmp",         endpoint: "quote",  perMinute: 30, perDay: 250),
            ProviderQuota(provider: "fmp",         endpoint: "fundamentals", perMinute: 30, perDay: 250),

            // FRED: 120 r/min
            ProviderQuota(provider: "fred",        endpoint: "series", perMinute: 120),

            // Frankfurter: quota yok, ECB referansı (gönüllü 30 r/min self-cap)
            ProviderQuota(provider: "frankfurter", endpoint: "fx",     perMinute: 30),

            // TCMB Today: kamu, dökümante limit yok (gönüllü 15 r/min)
            ProviderQuota(provider: "tcmb_today",  endpoint: "fx",     perMinute: 15),

            // Google News RSS: dökümante limit yok (gönüllü 60 r/min,
            // cache zaten 5dk TTL ile daraltıyor)
            ProviderQuota(provider: "googlenews",  endpoint: "rss",    perMinute: 60),
        ]
        for quota in defaults {
            quotas[quota.key] = quota
            usages[quota.key] = ProviderUsage()
        }
    }

    public func register(_ quota: ProviderQuota) {
        quotas[quota.key] = quota
        if usages[quota.key] == nil {
            usages[quota.key] = ProviderUsage()
        }
    }

    public func recordHit(provider: String, endpoint: String) {
        let key = "\(provider):\(endpoint)"
        var usage = usages[key] ?? ProviderUsage()
        usage.record()
        usages[key] = usage
    }

    /// Geriye [(provider, endpoint, used%, perMinute, perDay)] döner —
    /// UI'ya feed edilmek üzere.
    public func snapshot() -> [ProviderQuotaSnapshot] {
        var out: [ProviderQuotaSnapshot] = []
        out.reserveCapacity(quotas.count)
        let now = Date()
        for (key, quota) in quotas {
            var usage = usages[key] ?? ProviderUsage()
            usage.rollWindows(now: now)
            let minutePct: Double? = quota.perMinute.map {
                Double(usage.minuteHits) / Double($0) * 100.0
            }
            let dayPct: Double? = quota.perDay.map {
                Double(usage.dayHits) / Double($0) * 100.0
            }
            out.append(ProviderQuotaSnapshot(
                provider: quota.provider,
                endpoint: quota.endpoint,
                minuteHits: usage.minuteHits,
                minuteLimit: quota.perMinute,
                minutePct: minutePct,
                dayHits: usage.dayHits,
                dayLimit: quota.perDay,
                dayPct: dayPct
            ))
        }
        return out.sorted { $0.provider < $1.provider }
    }

    /// Predictive throttle için yardımcı: dakikalık tüketim %80'i aşmış mı?
    /// (Şu an çağıran yok — Faz 2'de `HeimdallNetwork.runRequest` öncesinde
    /// kontrol etmek için hazır.)
    public func isNearLimit(provider: String, endpoint: String, threshold: Double = 0.8) -> Bool {
        let key = "\(provider):\(endpoint)"
        guard let quota = quotas[key], let perMin = quota.perMinute else { return false }
        var usage = usages[key] ?? ProviderUsage()
        usage.rollWindows(now: Date())
        let pct = Double(usage.minuteHits) / Double(perMin)
        return pct >= threshold
    }
}

public struct ProviderQuotaSnapshot: Sendable {
    public let provider: String
    public let endpoint: String
    public let minuteHits: Int
    public let minuteLimit: Int?
    public let minutePct: Double?
    public let dayHits: Int
    public let dayLimit: Int?
    public let dayPct: Double?
}
