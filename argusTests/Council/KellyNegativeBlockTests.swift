import XCTest
@testable import argus

/// Faz 0 Task 9: Negatif Kelly + yeterli örneklem → `positionMultiplier == 0.0`.
///
/// Önceki davranış (`if ef <= 0 { return 0.3 }`) Kelly formülünün matematiksel
/// "kaybedeceksin" emrini bypass ediyordu. Yeni davranış:
/// - Sample < 10 (`.low` confidence) → 0.3 (kalibrasyon, az veri)
/// - Sample ≥ 10 (`.medium`/`.high`) ve Kelly ≤ 0 → 0.0 (matematik bloğu)
final class KellyNegativeBlockTests: XCTestCase {

    private func makeVerdict(symbol: String, regime: String, wasCorrect: Bool, priceChange: Double) -> AlkindusVerdict {
        AlkindusVerdict(
            symbol: symbol,
            action: wasCorrect ? "BUY" : "SELL",
            decisionDate: Date().addingTimeInterval(-7 * 86400),
            evaluationDate: Date(),
            horizon: 7,
            wasCorrect: wasCorrect,
            priceChange: priceChange,
            regime: regime,
            moduleVerdicts: [],
            originalReasoning: ""
        )
    }

    /// 50 verdict, sadece %20 kazanan, ortalama kayıp > ortalama kazanç:
    /// Kelly negatif olmalı; medium/high confidence'ta multiplier = 0.0.
    func test_negativeKelly_withSufficientSample_returnsZero() {
        let verdicts: [AlkindusVerdict] = (0..<50).map { i in
            let wasCorrect = i < 10  // 20% win rate
            return makeVerdict(symbol: "TEST_KELLY", regime: "neutral",
                               wasCorrect: wasCorrect,
                               priceChange: wasCorrect ? 1.5 : -3.0)
        }
        let profile = KellyCriterionSizer.calculate(verdicts: verdicts)

        XCTAssertEqual(profile.sampleSize, 50)
        XCTAssertGreaterThanOrEqual(profile.sampleSize, 10, "Bu testin geçerli olması için ≥10 örnek lazım")
        XCTAssertLessThanOrEqual(profile.kellyFraction, 0.0, "Kelly negatif veya sıfır olmalı (winRate 20%, kazanç < kayıp)")
        XCTAssertEqual(profile.positionMultiplier, 0.0, "Negatif Kelly + yeterli örneklem = 0.0 (sinyal blok)")
    }

    /// 3 verdict (sample < 5), Kelly hesaplanmaz → default low confidence,
    /// kellyFraction 0.25 fallback, multiplier 0.3 (kalibrasyon).
    func test_lowSample_returnsCalibrationMultiplier() {
        let verdicts: [AlkindusVerdict] = (0..<3).map { _ in
            makeVerdict(symbol: "TEST_KELLY_LOW", regime: "neutral",
                        wasCorrect: false, priceChange: -2.0)
        }
        let profile = KellyCriterionSizer.calculate(verdicts: verdicts)

        if case .low = profile.confidence {
            // ✓ low confidence — kalibrasyon
        } else {
            XCTFail("Sample < 5 → low confidence beklenir, gelen: \(profile.confidence)")
        }
        XCTAssertEqual(profile.positionMultiplier, 0.3, accuracy: 0.001,
                       "Düşük örneklem (kalibrasyon dönemi) 0.3 multiplier dönmeli")
    }

    /// Pozitif Kelly + yüksek confidence: multiplier 0.3 ile 2.0 arasında olmalı.
    func test_positiveKelly_returnsScaledMultiplier() {
        let verdicts: [AlkindusVerdict] = (0..<50).map { i in
            let wasCorrect = i < 35  // 70% win rate
            return makeVerdict(symbol: "TEST_KELLY_POS", regime: "neutral",
                               wasCorrect: wasCorrect,
                               priceChange: wasCorrect ? 3.0 : -1.5)
        }
        let profile = KellyCriterionSizer.calculate(verdicts: verdicts)

        XCTAssertGreaterThan(profile.kellyFraction, 0.0, "Pozitif edge olmalı")
        XCTAssertGreaterThanOrEqual(profile.positionMultiplier, 0.3)
        XCTAssertLessThanOrEqual(profile.positionMultiplier, 2.0)
    }
}
