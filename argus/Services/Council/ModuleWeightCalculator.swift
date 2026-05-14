import Foundation

/// Faz 2.1: Modül-bazlı dinamik ağırlık modülatörü.
///
/// `ModulePerformanceTracker.ModuleStats` listesi + rejim-bazlı baseline weights
/// dict alır; hit rate ≥ %55 olan modülün ağırlığını ×1.2, < %45 olanı ×0.6 yapar
/// ve toplam 1.0'a normalize ederek döner.
///
/// **Korunan davranış:** Veri yetersiz (decisive vote < 30) modüller için baseline
/// aynen kullanılır. Empty stats → baseline normalize edilmiş (sum=1.0) döner.
/// Yani Faz 1 davranışı (statik switch-case weights) modül karne dolana kadar
/// birebir korunur — sıfır regression riski.
///
/// **Pure function** — no state, actor değil, kolay test edilebilir. Caller
/// (ArgusGrandCouncil.calculateGrandDecision) baseline'i hazırlayıp tek seferde
/// çağırır.
struct ModuleWeightCalculator {

    /// Modülasyon eşiği — bu altında decisive vote → baseline aynen.
    /// İstatistiksel anlamlılık için minimum örnek. Sistem yeni başladığında
    /// modül weight'leri sabit kalır; veri dolunca otomatik dinamikleşir.
    static let minimumDecisiveVotes: Int = 30

    /// Hit rate eşikleri.
    static let strongHitRateThreshold: Double = 0.55  // ≥ → boost
    static let weakHitRateThreshold: Double = 0.45    // < → penalty

    /// Çarpanlar. boost ve penalty kombinasyonu sum'ı bozar — normalize gerekli.
    static let boostMultiplier: Double = 1.2
    static let penaltyMultiplier: Double = 0.6

    /// Baseline weights (rejim-bazlı switch-case'den gelen) + module stats
    /// → modüle edilmiş, **sum=1.0 normalize** edilmiş yeni weights.
    ///
    /// - Parameters:
    ///   - baseline: Mevcut rejim için sabit baseline (örn. `["Orion": 0.28, ...]`).
    ///   - stats: `ModulePerformanceTracker.shared.getAllStats()` çıktısı.
    /// - Returns: Modül adı → normalize edilmiş ağırlık dict. Empty baseline →
    ///   empty dict. Tüm ağırlıklar 0 olursa (savunma) → baseline aynen.
    static func calculate(
        baseline: [String: Double],
        stats: [ModulePerformanceTracker.ModuleStats]
    ) -> [String: Double] {
        guard !baseline.isEmpty else { return [:] }

        // Stats'ları modül adıyla index'le — O(n) erişim için.
        let statsByModule: [String: ModulePerformanceTracker.ModuleStats] =
            Dictionary(stats.map { ($0.module, $0) }, uniquingKeysWith: { first, _ in first })

        // Her baseline modülüne hit rate modülasyonu uygula.
        var modulated: [String: Double] = [:]
        for (module, baseWeight) in baseline {
            modulated[module] = modulatedWeight(
                baseWeight: baseWeight,
                stat: statsByModule[module]
            )
        }

        // Normalize: sum'ı 1.0'a getir. Sıfır savunması — tüm ağırlıklar 0
        // ihtimal düşük ama olursa baseline'i aynen döndür (regresyona düşme).
        let sum = modulated.values.reduce(0, +)
        guard sum > 0 else { return baseline }
        return modulated.mapValues { $0 / sum }
    }

    /// Tek bir modül için modülasyon kararı.
    /// `stat == nil` veya decisive < minimum → baseline aynen.
    /// hit rate ≥ strong → boost; < weak → penalty; arası → 1.0.
    private static func modulatedWeight(
        baseWeight: Double,
        stat: ModulePerformanceTracker.ModuleStats?
    ) -> Double {
        guard let stat = stat else { return baseWeight }
        let decisive = stat.correctVotes + stat.incorrectVotes
        guard decisive >= minimumDecisiveVotes else { return baseWeight }

        let hitRate = stat.hitRate
        let multiplier: Double
        if hitRate >= strongHitRateThreshold {
            multiplier = boostMultiplier
        } else if hitRate < weakHitRateThreshold {
            multiplier = penaltyMultiplier
        } else {
            multiplier = 1.0
        }
        return baseWeight * multiplier
    }
}
