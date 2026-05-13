import Foundation

/// Faz 1.B.2: ArgusLedger üzerinde sıcak/ılık/soğuk arşiv yuvarlama motoru.
///
/// **Üç katman:**
/// - **sıcak (hot):** Son 90 gün — tam payload, tam detay
/// - **ılık (warm):** 90g – 1y — payload korunur ama erişim seyrek (gelecekte
///   aggregate'e yuvarlanır; ilk versiyon sadece tier flag günceller)
/// - **soğuk (cold):** 1y+ — uzak geçmiş, sorgu nadir (gelecekte aylık özet)
///
/// İlk versiyon sadece tier flag güncelleyici. Aggregate yuvarlama (raw silme,
/// daily/monthly summary insert) sonraki sub-task'larda — DB'yi şişmeden tutmak
/// için tier filtreleme bile yeterli (sorgular WHERE tier='hot' ile sıcak verisi
/// çeker).
///
/// **Idempotent:** Aynı gün iki kez çalışsa state bozulmaz — `fromTier` filtresi
/// nedeniyle aynı satır iki kez güncellenmez.
actor DataTieringEngine {
    static let shared = DataTieringEngine()

    /// Eşik: bu kadar günden eski hot kayıtlar warm'a yuvarlanır.
    static let warmThresholdDays: Int = 90
    /// Eşik: bu kadar günden eski warm kayıtlar cold'a yuvarlanır.
    static let coldThresholdDays: Int = 365

    private init() {}

    /// Migration çıktısı — kaç satır hangi tier'a taşındı.
    struct TierMigrationResult: Equatable {
        var eventsToWarm: Int = 0
        var eventsToCold: Int = 0
        var tradesToWarm: Int = 0
        var tradesToCold: Int = 0
        var outcomesToWarm: Int = 0
        var outcomesToCold: Int = 0

        /// Toplam etkilenen satır — log + telemetri için.
        var totalRowsMoved: Int {
            eventsToWarm + eventsToCold + tradesToWarm + tradesToCold
                + outcomesToWarm + outcomesToCold
        }
    }

    /// Tier migration'ı çalıştır. Gece BGTask veya manuel tetikten çağrılır.
    /// `now` test'ten override edilebilir; üretimde default `Date()`.
    @discardableResult
    func runMigration(now: Date = Date()) -> TierMigrationResult {
        let calendar = Calendar.current
        let warmCutoff = calendar.date(byAdding: .day, value: -Self.warmThresholdDays, to: now) ?? now
        let coldCutoff = calendar.date(byAdding: .day, value: -Self.coldThresholdDays, to: now) ?? now

        var result = TierMigrationResult()

        // Önce cold'a yuvarla (eski warm'ları), sonra warm'a yuvarla (eski hot'ları).
        // Sıra önemli: eğer önce hot→warm yapsaydık, aynı çalıştırmada hot→warm→cold
        // iki step atlanabilirdi. Cold önce → warm'da kalmış eski kayıtlar düşer.

        // EVENTS — event_time_utc kolonu üzerinde
        result.eventsToCold = ArgusLedger.shared.migrateTier(
            table: "events",
            dateColumn: "event_time_utc",
            fromTier: "warm",
            toTier: "cold",
            cutoff: coldCutoff
        )
        result.eventsToWarm = ArgusLedger.shared.migrateTier(
            table: "events",
            dateColumn: "event_time_utc",
            fromTier: "hot",
            toTier: "warm",
            cutoff: warmCutoff
        )

        // TRADES — entry_date kolonu üzerinde
        result.tradesToCold = ArgusLedger.shared.migrateTier(
            table: "trades",
            dateColumn: "entry_date",
            fromTier: "warm",
            toTier: "cold",
            cutoff: coldCutoff
        )
        result.tradesToWarm = ArgusLedger.shared.migrateTier(
            table: "trades",
            dateColumn: "entry_date",
            fromTier: "hot",
            toTier: "warm",
            cutoff: warmCutoff
        )

        // OUTCOMES — closed_at kolonu üzerinde (kapanış zamanı bazlı)
        result.outcomesToCold = ArgusLedger.shared.migrateTier(
            table: "outcomes",
            dateColumn: "closed_at",
            fromTier: "warm",
            toTier: "cold",
            cutoff: coldCutoff
        )
        result.outcomesToWarm = ArgusLedger.shared.migrateTier(
            table: "outcomes",
            dateColumn: "closed_at",
            fromTier: "hot",
            toTier: "warm",
            cutoff: warmCutoff
        )

        ArgusLogger.info(.autopilot, "DataTiering: \(result.totalRowsMoved) satır taşındı (events: warm+\(result.eventsToWarm)/cold+\(result.eventsToCold), trades: warm+\(result.tradesToWarm)/cold+\(result.tradesToCold), outcomes: warm+\(result.outcomesToWarm)/cold+\(result.outcomesToCold))")

        return result
    }

    /// Tablo başına tier dağılımı snapshot. Settings → Veri Defteri ekranı
    /// bu çıktıyı kart olarak gösterir. ArgusLedger.countByTier'ı 3 tablo için
    /// toplar.
    nonisolated func tierSnapshot() -> [String: [String: Int]] {
        return [
            "events": ArgusLedger.shared.countByTier(table: "events"),
            "trades": ArgusLedger.shared.countByTier(table: "trades"),
            "outcomes": ArgusLedger.shared.countByTier(table: "outcomes")
        ]
    }
}
