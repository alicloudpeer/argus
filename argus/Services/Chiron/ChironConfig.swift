import Foundation

/// Static Configuration for Chiron Risk Governor.
///
/// Faz 0 Task 6 (2026-05-13): "paper-tuned" gevşemeler dürüst kalibrasyona
/// geri çekildi. Yol Haritası §6.6: "Bu, 'gerçek paraya geçilirse' değil,
/// 'şu an dürüst olmak için' yapılır." Paper trading öğrenme verisi de
/// kalibrasyona dayalı parametrelerle toplanmalı — aksi takdirde forward
/// test'in çıktıları "gerçek paraya geçildiğinde değişir" şartlı kalır.
struct RiskBudgetConfig: Sendable {
    // Risk Limits
    // 2026-05-13 hijyen: paper-tuned 30 → 10 (eski/dürüst değer)
    nonisolated static let maxPositions: Int = 10           // Max concurrent positions

    // Cluster Limits
    // 2026-05-13 hijyen: paper-tuned 100 → 5 (sektör konsantrasyonu kontrolü)
    nonisolated static let maxConcentrationPerCluster: Int = 5

    // Time Limits
    // 2026-05-13 hijyen: paper-tuned 5dk → 30dk (overtrading'i engelle)
    nonisolated static let cooldownMinutes: Double = 30     // Min minutes between trades on same symbol

    // Regime thresholds (Aether) — 2026-05-13 paper-tuned geri çekildi
    // Paper: deepRiskOff 15, riskOff 25 (geniş öğrenme alanı)
    // Dürüst: deepRiskOff 25, riskOff 40 (rejim eşikleri Aether ölçüm bantlarıyla hizalı)
    nonisolated static let deepRiskOffMaxScore: Double = 25
    nonisolated static let riskOffMaxScore: Double = 40

    // Forced unwind settings
    nonisolated static let deepRiskOffTrimPercent: Double = 50
    nonisolated static let riskOffTrimPercent: Double = 25

    // Dynamic Risk Ceiling
    // Aether >= 70 (Boğa)   -> 10R rahat ama sınırlı
    // Aether >= 55 (Nötr)   ->  6R temkinli
    // Aether >= 40 (Dikkat) ->  3R çok küçük
    // Aether >= 25 (Kötü)   ->  1.5R minimal
    // Aether  < 25 (Çöküş)  ->  0R yeni giriş yok (hard-stop)
    //
    // 2026-05-13 hijyen: paper-tuned 2x ve 1R çöküş entry'si geri çekildi.
    // Eski: 10/6/3/1.5/0 (gerçek para kalibrasyonu, dürüst değerler)
    nonisolated static func dynamicMaxRiskR(aetherScore: Double) -> Double {
        if aetherScore >= 70 { return 10.0 }   // Boğa
        if aetherScore >= 55 { return 6.0 }    // Nötr
        if aetherScore >= 40 { return 3.0 }    // Dikkat
        if aetherScore >= 25 { return 1.5 }    // Kötü
        return 0.0                             // Çöküş: hard-stop, yeni giriş yok
    }
}
