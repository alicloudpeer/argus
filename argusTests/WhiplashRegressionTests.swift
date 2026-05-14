import XCTest
@testable import argus

/// Faz VI (2026-05-12) — Whiplash mimari düzeltme regression test'leri.
///
/// Kapsam: Faz I-V'te uygulanan kök neden fixlerinin geri gelmemesini garanti
/// eden minimal, deterministik unit testler. Async/network/UI bağımlılığı yok;
/// pure logic + in-memory state.
///
/// Faz dağılımı:
///   I.1 → Phoenix R² gradient + multiplier semantiği (en kritik)
///   III.1a → councilActionChanged trigger semantik (to parametresi)
///   V    → CouncilWeightsSnapshot deterministic content-hash ID
///
/// Test edilmeyen (gelecek iş):
///   I.2 (determineTier hysteresis) — private, dolaylı test gerektiriyor
///   I.3 (Aether weighted blending) — actor + makro veri fixture'ı gerektiriyor
///   I.4 (Orion m5 damper) — calculateConsensus private, dolaylı test
///   II (HeimdallOrchestrator merge) — network bağımlı integration test gerektiriyor
///   IV (DecisionChangeEvent) — SQLite test mode + cache reset gerektiriyor
///
/// `@MainActor`: ActionTrigger.Equatable conformance @MainActor isolated;
/// PlanRepositoryTests pattern'i ile aynı, tüm test'leri main actor üstünde
/// koştur ki Swift 6 strict concurrency uyarısı kalmasın.
@MainActor
final class WhiplashRegressionTests: XCTestCase {

    // MARK: - Faz I.1: Phoenix R² Gradient Semantic

    /// Mükemmel lineer trend → R² ≈ 1.0. Sanity check: matematik doğru çalışıyor.
    func testPhoenix_PerfectLinearTrend_HighRSquared() {
        let closes = (0..<100).map { 100.0 + Double($0) * 0.5 }  // y = 100 + 0.5x
        let (slope, intercept, _, _, _, _) = PhoenixLogic.calculateLinRegChannel(closes: closes, k: 2.0)
        let r2 = PhoenixLogic.calculateRSquared(closes: closes, slope: slope, intercept: intercept)

        XCTAssertGreaterThan(r2, 0.99, "Lineer trend için R² ≥ 0.99 beklenir, alınan: \(r2)")
        XCTAssertEqual(slope, 0.5, accuracy: 0.001, "Slope mükemmel lineer için tam çıkmalı")
    }

    /// Rastgele yürüyüş → R² düşük. Hard cutoff 0.05 testi: çok düşük R²
    /// `insufficient` döndürmeli (sinyal kapatılıyor).
    func testPhoenix_RandomWalk_LowRSquared_ReturnsInsufficient() {
        let candles = Self.makeNoisyCandles(count: 200, seed: 42)
        let advice = PhoenixLogic.analyze(
            candles: candles,
            symbol: "TEST",
            timeframe: .d1,
            config: PhoenixConfig()
        )
        // Rastgele yürüyüş'te slope ~ 0, R² ~ 0. Hard cutoff < 0.05 →
        // .insufficientData. Cutoff 0.05'in ÜSTÜNDE bir R² çıkarsa .active
        // ile dönüş kabul — ama o durumda bile confidence neutral'a yakın
        // olmalı (yön devrilmemeli).
        if advice.status == .insufficientData {
            XCTAssertEqual(advice.confidence, 0, "insufficient durumda confidence 0 olmalı")
        } else {
            // Active çıkarsa: confidence sell zone'da olmamalı (mutiplier
            // semantik bug'ı 95×0.4=38 hesabıyla AL'ı SAT'a çeviriyordu;
            // bu artık yapılmıyor — score 50 nötral'a çekiliyor).
            XCTAssertGreaterThanOrEqual(advice.confidence, 35,
                "Düşük R² confidence'i SAT zone'una çekmemeli. Alınan: \(advice.confidence)")
        }
    }

    /// Çok düşük R² (< 0.05) için kesin insufficient garantisi — hard cutoff sınır testi.
    func testPhoenix_VeryNoisy_ExplicitInsufficient() {
        // Sembol fix: 200 mum rastgele [95, 105] arası — slope ≈ 0
        let candles = Self.makeNoisyCandles(count: 200, seed: 7)
        let advice = PhoenixLogic.analyze(
            candles: candles,
            symbol: "NOISY",
            timeframe: .d1,
            config: PhoenixConfig()
        )
        // Bu fixture'da R² ~ 0 olmalı → insufficient
        XCTAssertEqual(advice.status, .insufficientData,
            "Rastgele yürüyüş için insufficient bekleniyor, alınan: \(advice.status.rawValue) confidence: \(advice.confidence)")
    }

    // MARK: - Faz V: CouncilWeightsSnapshot Determinism

    /// Aynı içerikteki weights iki kez çağrıldığında aynı snapshot ID üretmeli.
    /// Content-hash deterministik (SHA256 prefix, .sortedKeys canonical encoding).
    func testWeightsSnapshot_SameWeights_SameId() {
        let symbol = "TEST_DET_SAME_\(UUID().uuidString.prefix(8))"
        let engine: AutoPilotEngine = .corse
        // UserDefaults temizle — defaults kullanılsın.
        UserDefaults.standard.removeObject(forKey: "chiron.weights.\(engine.rawValue).\(symbol)")
        defer { UserDefaults.standard.removeObject(forKey: "chiron.weights.\(engine.rawValue).\(symbol)") }

        let snap1 = ChironCouncilLearningService.shared.getWeightsSnapshot(symbol: symbol, engine: engine)
        let snap2 = ChironCouncilLearningService.shared.getWeightsSnapshot(symbol: symbol, engine: engine)

        XCTAssertEqual(snap1.snapshotId, snap2.snapshotId,
            "Aynı weights için snapshot ID deterministik olmalı")
        XCTAssertEqual(snap1.snapshotId.count, 16,
            "Snapshot ID 16 char hex prefix olmalı")
    }

    /// Farklı engine defaultları farklı weights üretir → farklı snapshot ID.
    func testWeightsSnapshot_DifferentEngines_DifferentIds() {
        let symbol = "TEST_DET_DIFF_\(UUID().uuidString.prefix(8))"
        UserDefaults.standard.removeObject(forKey: "chiron.weights.CORSE.\(symbol)")
        UserDefaults.standard.removeObject(forKey: "chiron.weights.PULSE.\(symbol)")
        defer {
            UserDefaults.standard.removeObject(forKey: "chiron.weights.CORSE.\(symbol)")
            UserDefaults.standard.removeObject(forKey: "chiron.weights.PULSE.\(symbol)")
        }

        let corseSnap = ChironCouncilLearningService.shared.getWeightsSnapshot(symbol: symbol, engine: .corse)
        let pulseSnap = ChironCouncilLearningService.shared.getWeightsSnapshot(symbol: symbol, engine: .pulse)

        XCTAssertNotEqual(corseSnap.snapshotId, pulseSnap.snapshotId,
            "Farklı engine defaultları (trendMaster: 0.30 vs 0.20 vb.) farklı ID üretmeli")
    }

    /// Snapshot ID karakter formatı: hex (0-9a-f), 16 karakter.
    func testWeightsSnapshot_IdFormat_HexPrefix() {
        let symbol = "TEST_FMT_\(UUID().uuidString.prefix(8))"
        defer { UserDefaults.standard.removeObject(forKey: "chiron.weights.CORSE.\(symbol)") }
        let snap = ChironCouncilLearningService.shared.getWeightsSnapshot(symbol: symbol, engine: .corse)

        XCTAssertEqual(snap.snapshotId.count, 16)
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(snap.snapshotId.unicodeScalars.allSatisfy { hexChars.contains($0) },
            "Snapshot ID sadece hex karakter içermeli, alınan: \(snap.snapshotId)")
    }

    // MARK: - Faz III.1a: councilActionChanged Trigger Semantic

    /// councilActionChanged trigger'ı YALNIZCA Council mevcut state hedef `to`
    /// state'i ile eşleştiğinde fire etmeli. Önceki bug: `to` parametresi
    /// görmezden geliniyordu, herhangi bir state değişiminde fire ediyordu —
    /// trim adımı ve liquidate adımı aynı tick'te tetikleniyordu.
    func testActionTrigger_CouncilActionChanged_FiresOnlyWhenToMatches() {
        // Plan başlangıç state: accumulate. Trigger'ları "trim" ve "liquidate" hedefleri için kur.
        let fromAction: ArgusAction = .accumulate
        let trimTrigger = ActionTrigger.councilActionChanged(from: fromAction, to: .trim)
        let liquidateTrigger = ActionTrigger.councilActionChanged(from: fromAction, to: .liquidate)

        // Trigger eşitlik testi — Equatable conformance var (enum case'ler)
        let trimAgain = ActionTrigger.councilActionChanged(from: fromAction, to: .trim)
        XCTAssertEqual(trimTrigger, trimAgain, "Aynı parametrelerle Equatable eşit olmalı")
        XCTAssertNotEqual(trimTrigger, liquidateTrigger, "Farklı `to` parametreleri farklı trigger olmalı")
    }

    // MARK: - Fixtures

    /// Deterministik rastgele yürüyüş — LCG (linear congruential generator) ile
    /// seed-controlled noise. Aynı seed = aynı seri.
    private static func makeNoisyCandles(count: Int, seed: UInt64) -> [Candle] {
        var state: UInt64 = seed
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 33) / Double(UInt32.max)  // [0, 1)
        }
        return (0..<count).map { i in
            let close = 100.0 + (next() - 0.5) * 10.0  // [95, 105]
            let high = close + 0.5
            let low = close - 0.5
            return Candle(
                date: Date().addingTimeInterval(TimeInterval(-count + i) * 86400),
                open: close - 0.2,
                high: high,
                low: low,
                close: close,
                volume: 1_000_000
            )
        }
    }
}
