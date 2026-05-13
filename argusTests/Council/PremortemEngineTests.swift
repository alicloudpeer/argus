import XCTest
@testable import argus

/// Faz 1.A.1 testleri: PremortemEngine statik kural motoru.
///
/// API primitive-only (struct mock'a gerek yok); her test bir veya birkaç
/// kuralı izole edip beklenen senaryoyu doğrular. Fallback senaryosu garanti.
final class PremortemEngineTests: XCTestCase {

    // MARK: - Tek kural izolasyonu

    /// Kural 1: Aether < 50 → "Makro" senaryosu.
    func test_lowAether_emitsMakroScenario() {
        let scenarios = PremortemEngine.generate(
            action: .accumulate,
            aetherScore: 35,                 // < 50 → tetikler
            orionScore: 70,
            atlasMarginOfSafety: 0.20,       // pozitif → Atlas tetiklemez
            demeterTotalScore: 60,           // > 40 → tetiklemez
            clusterConcentration: 1          // ≤ 3 → tetiklemez
        )

        XCTAssertTrue(
            scenarios.contains { $0.trigger == "Makro" },
            "Aether 35 < 50 → makro risk senaryosu beklenir"
        )
    }

    /// Aether < 30 → makro severity `.high`.
    func test_veryLowAether_severityIsHigh() {
        let scenarios = PremortemEngine.generate(
            action: .accumulate,
            aetherScore: 20,                 // < 30 → high severity
            orionScore: 70,
            atlasMarginOfSafety: 0.20,
            demeterTotalScore: 60,
            clusterConcentration: 1
        )
        guard let makro = scenarios.first(where: { $0.trigger == "Makro" }) else {
            return XCTFail("Makro senaryosu üretilmeli")
        }
        XCTAssertEqual(makro.severity, .high)
    }

    /// Aether ≥ 50 → makro senaryo tetiklenmez.
    func test_highAether_skipsMakroScenario() {
        let scenarios = PremortemEngine.generate(
            action: .accumulate,
            aetherScore: 75,                 // ≥ 50 → atlanır
            orionScore: 70,
            atlasMarginOfSafety: 0.20,
            demeterTotalScore: 60,
            clusterConcentration: 1
        )
        XCTAssertFalse(
            scenarios.contains { $0.trigger == "Makro" },
            "Aether 75 → makro yok"
        )
    }

    /// Kural 2 (negative MoS): BUY + marginOfSafety < 0 → "Bilanço" senaryosu.
    func test_negativeAtlasMargin_onBuy_emitsBilancoScenario() {
        let scenarios = PremortemEngine.generate(
            action: .aggressiveBuy,
            aetherScore: 75,
            orionScore: 70,
            atlasMarginOfSafety: -0.15,      // negatif → tetikler
            demeterTotalScore: 60,
            clusterConcentration: 1
        )
        XCTAssertTrue(
            scenarios.contains { $0.trigger == "Bilanço" },
            "Atlas marginOfSafety negatif + BUY → bilanço uyarısı"
        )
    }

    /// Kural 2 (nil): BUY + Atlas verisi yok (kripto/FX) → "Bilanço" düşük seviyeli uyarı.
    func test_nilAtlasMargin_onBuy_emitsLowSeverityBilanco() {
        let scenarios = PremortemEngine.generate(
            action: .accumulate,
            aetherScore: 75,
            orionScore: 70,
            atlasMarginOfSafety: nil,        // nil → low severity bilanço
            demeterTotalScore: 60,
            clusterConcentration: 1
        )
        let bilanco = scenarios.first { $0.trigger == "Bilanço" }
        XCTAssertNotNil(bilanco, "nil Atlas + BUY → bilanço yok-veri uyarısı")
        XCTAssertEqual(bilanco?.severity, .low, "Yok-veri durumu low severity")
    }

    /// SAT/AZALT eylemlerinde Atlas zayıf olsa bile bilanço uyarısı verilmez
    /// (zayıf bilanço SAT'a destek verir — uyarı değil).
    func test_negativeAtlasMargin_onSell_doesNotEmitBilancoScenario() {
        let scenarios = PremortemEngine.generate(
            action: .liquidate,
            aetherScore: 75,
            orionScore: 70,
            atlasMarginOfSafety: -0.15,
            demeterTotalScore: 60,
            clusterConcentration: 1
        )
        XCTAssertFalse(
            scenarios.contains { $0.trigger == "Bilanço" },
            "SAT eyleminde negatif Atlas uyarı değil"
        )
    }

    /// Kural 3: BUY + Demeter < 40 → "Sektör" senaryosu.
    func test_lowDemeter_onBuy_emitsSektorScenario() {
        let scenarios = PremortemEngine.generate(
            action: .aggressiveBuy,
            aetherScore: 75,
            orionScore: 70,
            atlasMarginOfSafety: 0.20,
            demeterTotalScore: 30,           // < 40 → tetikler
            clusterConcentration: 1
        )
        XCTAssertTrue(
            scenarios.contains { $0.trigger == "Sektör" },
            "Demeter 30 + BUY → sektör uyarısı"
        )
    }

    /// Kural 4: orion < 50 + cluster > 3 → "Likidite" senaryosu.
    func test_weakOrionAndHighCluster_emitsLikiditeScenario() {
        let scenarios = PremortemEngine.generate(
            action: .accumulate,
            aetherScore: 75,
            orionScore: 40,                  // < 50
            atlasMarginOfSafety: 0.20,
            demeterTotalScore: 60,
            clusterConcentration: 5          // > 3
        )
        XCTAssertTrue(
            scenarios.contains { $0.trigger == "Likidite" },
            "Orion zayıf + cluster yoğun → likidite uyarısı"
        )
    }

    // MARK: - Kapasiteli kurallar (3-limit + fallback)

    /// Hiç kural tetiklenmezse fallback "Genel" senaryosu döner.
    func test_allRulesQuiet_returnsGeneralFallback() {
        let scenarios = PremortemEngine.generate(
            action: .accumulate,
            aetherScore: 75,
            orionScore: 70,
            atlasMarginOfSafety: 0.20,
            demeterTotalScore: 60,
            clusterConcentration: 1
        )
        XCTAssertEqual(scenarios.count, 1)
        XCTAssertEqual(scenarios.first?.trigger, "Genel")
        XCTAssertEqual(scenarios.first?.severity, .low)
    }

    /// Çoklu kural tetiklense bile max 3 senaryo döner.
    func test_multipleRulesTriggered_capsAtThree() {
        let scenarios = PremortemEngine.generate(
            action: .aggressiveBuy,
            aetherScore: 20,                 // makro tetikler
            orionScore: 30,                  // zayıf
            atlasMarginOfSafety: -0.20,      // atlas tetikler
            demeterTotalScore: 20,           // sektör tetikler
            clusterConcentration: 6          // likidite tetikler
        )
        XCTAssertLessThanOrEqual(scenarios.count, 3, "Cap maksimum 3 senaryo")
    }

    /// Boş array hiç dönmez (en az 1 fallback).
    func test_neverReturnsEmpty() {
        // En sessiz girdi
        let scenarios = PremortemEngine.generate(
            action: .neutral,
            aetherScore: 100,
            orionScore: 100,
            atlasMarginOfSafety: 1.0,
            demeterTotalScore: 100,
            clusterConcentration: 0
        )
        XCTAssertGreaterThan(scenarios.count, 0, "En az 1 senaryo (fallback) garanti")
    }
}
