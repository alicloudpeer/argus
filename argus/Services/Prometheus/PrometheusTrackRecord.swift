import Foundation

// MARK: - Prometheus Track Record (T2.23 — Self-aware Prometheus)
// ArgusValidator'ın hesapladığı forward test istatistiklerini Council ve UI için
// hafif, cache'lenmiş bir formda sunar. Sabit %3 Council ağırlığını skill_score
// bazlı dinamik ağırlıkla değiştirmek için ana giriş noktası.
//
// Akış: ArgusValidator.calculateScientificMetrics() → bu actor cache → Council/UI okuyucular.

actor PrometheusTrackRecord {
    static let shared = PrometheusTrackRecord()

    struct Stats: Sendable {
        let directionAccuracy: Double  // 0..1 — son N forward test'te yön doğruluğu
        let magnitudeRMSE: Double      // % — tahmin/gerçek farkının kök ortalama karesi
        let skillScore: Double         // 1 - prom_err/naive_err — >0 ise naive baseline'dan iyi
        let sampleSize: Int
        let updatedAt: Date

        static let empty = Stats(
            directionAccuracy: 0,
            magnitudeRMSE: 0,
            skillScore: 0,
            sampleSize: 0,
            updatedAt: .distantPast
        )

        /// Council'da kullanılan dinamik ağırlık çarpanı.
        /// - Yetersiz veri (<10) → 0 (sadece tabandan kat: 0.03)
        /// - skillScore ≤ 0 → 0 (Prometheus naive'den kötü, ek ağırlık yok)
        /// - skillScore > 0 → clamp(skillScore × 0.07, 0, 0.07)
        var weightBonus: Double {
            guard sampleSize >= 10, skillScore > 0 else { return 0 }
            return max(0, min(0.07, skillScore * 0.07))
        }

        /// İnsan-okur formatında özet — Council reasoning ve UI rozeti için.
        var summaryLine: String {
            guard sampleSize > 0 else { return "Henüz forward test verisi yok" }
            return String(
                format: "Son %d trade: yön %%%.0f doğru, naive'den %@",
                sampleSize,
                directionAccuracy * 100,
                skillScore > 0 ? String(format: "%%%.0f iyi", skillScore * 100)
                               : String(format: "%%%.0f kötü", abs(skillScore) * 100)
            )
        }

        /// Spotlight tetikleyici — track record yeterince iyi mi?
        var isSpotlightCapable: Bool {
            sampleSize >= 10 && skillScore >= 0.30 && directionAccuracy >= 0.55
        }
    }

    private var cached: Stats = .empty
    private let cacheTTL: TimeInterval = 3600 // 1 saat

    // MARK: - Public API

    /// Cache TTL geçtiyse ArgusValidator'dan yeniden çeker. Aksi halde cache döner.
    func getStats() async -> Stats {
        let age = Date().timeIntervalSince(cached.updatedAt)
        if age < cacheTTL { return cached }
        return await refresh()
    }

    /// Hızlı (await olmayan) son cached değer — Council sync path için.
    /// Dikkat: stale olabilir; kritik kararlarda getStats() tercih edilmeli.
    nonisolated(unsafe) private static var lastSnapshot: Stats = .empty
    static func currentSnapshot() -> Stats { lastSnapshot }

    @discardableResult
    func refresh() async -> Stats {
        let scientific = await ArgusValidator.shared.calculateScientificMetrics()
        let stats = Stats(
            directionAccuracy: scientific.prometheusDirectionAccuracy,
            magnitudeRMSE: scientific.prometheusMagnitudeRMSE,
            skillScore: scientific.prometheusSkillScore,
            sampleSize: scientific.prometheusSampleSize,
            updatedAt: Date()
        )
        cached = stats
        PrometheusTrackRecord.lastSnapshot = stats
        return stats
    }

    func invalidate() {
        cached = .empty
        PrometheusTrackRecord.lastSnapshot = .empty
    }
}
