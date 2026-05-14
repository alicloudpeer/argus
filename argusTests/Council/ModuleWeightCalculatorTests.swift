import XCTest
@testable import argus

/// Faz 2.1 testleri: ModuleWeightCalculator pure-function modülatör.
///
/// Pure function olduğu için actor isolation veya tearDown gerekmez —
/// her test bağımsız input/output.
final class ModuleWeightCalculatorTests: XCTestCase {

    // MARK: - Helpers

    private func makeStat(
        module: String,
        correct: Int,
        incorrect: Int,
        hold: Int = 0
    ) -> ModulePerformanceTracker.ModuleStats {
        ModulePerformanceTracker.ModuleStats(
            module: module,
            totalVotes: correct + incorrect + hold,
            correctVotes: correct,
            incorrectVotes: incorrect,
            holdVotes: hold,
            totalPnLContribution: 0
        )
    }

    private let baseline: [String: Double] = [
        "Orion": 0.30,
        "Atlas": 0.20,
        "Aether": 0.20,
        "Hermes": 0.15,
        "Phoenix": 0.15
    ]

    // MARK: - Empty stats → baseline normalize

    /// Hiç stats yoksa baseline aynen (zaten sum=1.0).
    func test_emptyStats_returnsBaselineNormalized() {
        let result = ModuleWeightCalculator.calculate(baseline: baseline, stats: [])

        XCTAssertEqual(result.keys.sorted(), baseline.keys.sorted())
        for (module, weight) in baseline {
            XCTAssertEqual(result[module] ?? 0, weight, accuracy: 0.0001,
                           "Empty stats → \(module) baseline değeri korumalı")
        }
    }

    // MARK: - Boost (strong hit rate)

    /// Decisive ≥ 30 + hit rate ≥ %55 → ağırlık ×1.2 (normalize öncesi).
    /// Normalize sonrası diğer modüllere göre **göreceli olarak** artmış olmalı.
    func test_strongHitRate_boostsWeight() {
        let stats = [
            // Orion: 70% hit rate, 50 decisive
            makeStat(module: "Orion", correct: 35, incorrect: 15)
        ]
        let result = ModuleWeightCalculator.calculate(baseline: baseline, stats: stats)

        // Orion baseline 0.30 × 1.2 = 0.36 (normalize öncesi).
        // Diğer 4 modül × 1.0 → toplam = 0.36 + 0.20 + 0.20 + 0.15 + 0.15 = 1.06
        // Orion / 1.06 = ~0.340 (baseline 0.30'dan büyük olmalı).
        XCTAssertGreaterThan(
            result["Orion"] ?? 0, baseline["Orion"]!,
            "Strong hit rate → normalize sonrası bile Orion baseline'dan büyük"
        )
    }

    // MARK: - Penalty (weak hit rate)

    /// Decisive ≥ 30 + hit rate < %45 → ağırlık ×0.6.
    func test_weakHitRate_penalizesWeight() {
        let stats = [
            // Atlas: 30% hit rate, 50 decisive
            makeStat(module: "Atlas", correct: 15, incorrect: 35)
        ]
        let result = ModuleWeightCalculator.calculate(baseline: baseline, stats: stats)

        // Atlas baseline 0.20 × 0.6 = 0.12. Normalize sonrası göreceli düşmüş.
        XCTAssertLessThan(
            result["Atlas"] ?? 1.0, baseline["Atlas"]!,
            "Weak hit rate → normalize sonrası Atlas baseline'dan küçük"
        )
    }

    // MARK: - Insufficient sample

    /// Decisive < 30 → baseline aynen (modülasyon yok). Yetersiz veri ile
    /// erken ağırlık değişimi olmaz.
    func test_insufficientSample_returnsBaseline() {
        let stats = [
            // Orion: çok yüksek hit rate ama sample küçük
            makeStat(module: "Orion", correct: 9, incorrect: 1)  // %90, decisive=10
        ]
        let result = ModuleWeightCalculator.calculate(baseline: baseline, stats: stats)

        // Decisive=10 < 30 → modülasyon atlandı → baseline aynen normalize.
        for (module, weight) in baseline {
            XCTAssertEqual(result[module] ?? 0, weight, accuracy: 0.0001,
                           "Yetersiz örneklem → \(module) baseline'dan değişmemeli")
        }
    }

    // MARK: - Normalization invariant

    /// Output ağırlıklarının toplamı her durumda 1.0 (normalize garantili).
    func test_resultSumsToOne_emptyStats() {
        let result = ModuleWeightCalculator.calculate(baseline: baseline, stats: [])
        let sum = result.values.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: 0.0001, "Empty stats da normalize sum=1.0")
    }

    func test_resultSumsToOne_mixedStats() {
        let stats = [
            makeStat(module: "Orion", correct: 35, incorrect: 15),    // boost
            makeStat(module: "Atlas", correct: 15, incorrect: 35),    // penalty
            makeStat(module: "Hermes", correct: 25, incorrect: 25)    // arasıt (no change)
        ]
        let result = ModuleWeightCalculator.calculate(baseline: baseline, stats: stats)
        let sum = result.values.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: 0.0001,
                       "Karışık modülasyon sonrası sum=1.0 (normalize çalıştı)")
    }

    // MARK: - Unknown module ignore

    /// Stats'ta baseline'da olmayan modül → ignore (output baseline keys'iyle aynı).
    func test_unknownModuleInStats_isIgnored() {
        let stats = [
            makeStat(module: "GhostModule", correct: 50, incorrect: 0)  // baseline'da yok
        ]
        let result = ModuleWeightCalculator.calculate(baseline: baseline, stats: stats)

        XCTAssertNil(result["GhostModule"],
                     "Bilinmeyen modül output'a sızmamalı")
        XCTAssertEqual(result.keys.sorted(), baseline.keys.sorted())
    }

    // MARK: - Empty baseline

    /// Empty baseline → empty output (defansif).
    func test_emptyBaseline_returnsEmpty() {
        let result = ModuleWeightCalculator.calculate(baseline: [:], stats: [])
        XCTAssertTrue(result.isEmpty)
    }
}
