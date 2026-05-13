import XCTest
@testable import argus

/// Task 11 (2026-05-13) testleri: Modül performans karnesi.
///
/// Yol Haritası §4 Kural 5: "Bir modülün varlık nedeni, yokluğundaki performans
/// kaybıdır." Bu testler bu kuralın ölçülebilir olmasını doğrular.
///
/// Test izolasyonu:
/// - `setUp` her test başında `ModulePerformanceTracker.shared.resetForTesting()`
///   ile state'i sıfırlar (UserDefaults persist key wipe).
/// - `tearDown` aynı + ArgusLedger içinde testin yazdığı satırları siler.
/// - Sembol prefix + UUID ile decision_id çakışmasını önler.
final class ModulePerformanceTrackerTests: XCTestCase {

    /// Bu test sınıfının yazdığı tüm ledger satırlarını işaretler.
    /// Decision/event'ler için ek silme yok (events tablosu test-pollution
    /// hassasiyeti düşük: queryModuleVotes spesifik decision_id'yi okur,
    /// başka testlerin kalıntıları interfere etmez).
    private static let testSymbolPrefix = "TEST_MODPERF_"

    override func setUp() async throws {
        try await super.setUp()
        // Test'ler arası isolation: her test sıfır state ile başlasın.
        await ModulePerformanceTracker.shared.resetForTesting()
    }

    override func tearDown() async throws {
        await ArgusLedger.shared.deleteOpenTrades(symbolPrefix: Self.testSymbolPrefix)
        await ModulePerformanceTracker.shared.resetForTesting()
        try await super.tearDown()
    }

    // MARK: - 1) Ledger round-trip: logDecision moduleVotes → queryModuleVotes

    /// `ArgusLedger.logDecision(moduleVotes:)` ile yazılan JSON, `queryModuleVotes`
    /// ile geri okunduğunda alan-bazında eşleşmeli. Sadece count değil — module/
    /// action/confidence değerleri korunduğunu doğrula.
    func test_recordDecisionAndQueryModuleVotes_roundTrip() {
        let decisionId = UUID()
        let symbol = "\(Self.testSymbolPrefix)\(UUID().uuidString)"

        let votes = [
            ModuleVoteRecord(module: "Orion",  action: "buy",  confidence: 0.8),
            ModuleVoteRecord(module: "Atlas",  action: "sell", confidence: 0.6),
            ModuleVoteRecord(module: "Aether", action: "hold", confidence: 0.5)
        ]

        guard let data = try? JSONEncoder().encode(votes),
              let json = String(data: data, encoding: .utf8) else {
            XCTFail("ModuleVoteRecord JSON encode başarısız")
            return
        }

        // logDecision queue.async ile yazıyor — read'den önce tamamlanması için
        // kısa bir senkronizasyon noktası yarat. Aynı queue'da read yapacak
        // herhangi bir sync call (örn. queryModuleVotes kendisi queue.sync) FIFO
        // sırası gereği write'tan sonra çalışır. Yine de explicit flush için
        // expectation kullanmak yerine queryModuleVotes'un kendi queue.sync'i
        // serializasyonu sağlar.
        ArgusLedger.shared.logDecision(
            decisionId: decisionId,
            symbol: symbol,
            action: "AL",
            confidence: 0.75,
            scores: ["Orion": 80.0, "Atlas": 60.0],
            vetoes: [],
            origin: "TEST",
            currentPrice: 100.0,
            moduleVotes: json
        )

        // Write async queue üzerinden gidiyor; queryModuleVotes queue.sync —
        // queue serial olduğu için sync call write tamamlanmasını bekler.
        let retrieved = ArgusLedger.shared.queryModuleVotes(decisionId: decisionId.uuidString)

        XCTAssertEqual(retrieved.count, 3, "3 ModuleVoteRecord round-trip olmalı")

        let orion = retrieved.first { $0.module == "Orion" }
        XCTAssertNotNil(orion)
        XCTAssertEqual(orion?.action, "buy")
        XCTAssertEqual(orion?.confidence ?? -1, 0.8, accuracy: 0.001)

        let atlas = retrieved.first { $0.module == "Atlas" }
        XCTAssertNotNil(atlas)
        XCTAssertEqual(atlas?.action, "sell")
        XCTAssertEqual(atlas?.confidence ?? -1, 0.6, accuracy: 0.001)

        let aether = retrieved.first { $0.module == "Aether" }
        XCTAssertNotNil(aether)
        XCTAssertEqual(aether?.action, "hold")
        XCTAssertEqual(aether?.confidence ?? -1, 0.5, accuracy: 0.001)
    }

    // MARK: - 2) Correct vote accounting (buy + pnl > 0, sell + pnl > 0)

    /// Pozitif PnL'de `buy` oyu → correct, `sell` oyu → incorrect.
    /// Aynı pnl her iki modüle de uygulanır; biri kazanır biri kaybeder.
    func test_modulePerformance_correctVote_incrementsCounter() async {
        let votes = [
            ModuleVoteRecord(module: "Orion", action: "buy",  confidence: 0.8),
            ModuleVoteRecord(module: "Atlas", action: "sell", confidence: 0.6)
        ]

        await ModulePerformanceTracker.shared.recordTradeOutcome(
            decisionId: UUID().uuidString,
            actualPnL: 100.0,
            moduleVotes: votes
        )

        // Orion: buy + pnl>0 → correct
        let orionStats = await ModulePerformanceTracker.shared.getStats(module: "Orion")
        XCTAssertEqual(orionStats.totalVotes, 1)
        XCTAssertEqual(orionStats.correctVotes, 1)
        XCTAssertEqual(orionStats.incorrectVotes, 0)
        XCTAssertEqual(orionStats.holdVotes, 0)
        XCTAssertEqual(orionStats.hitRate, 1.0, accuracy: 0.001, "Orion %100 doğru")
        // PnL contribution = 100 * 0.8 = 80
        XCTAssertEqual(orionStats.totalPnLContribution, 80.0, accuracy: 0.001)

        // Atlas: sell + pnl>0 → incorrect
        let atlasStats = await ModulePerformanceTracker.shared.getStats(module: "Atlas")
        XCTAssertEqual(atlasStats.totalVotes, 1)
        XCTAssertEqual(atlasStats.correctVotes, 0)
        XCTAssertEqual(atlasStats.incorrectVotes, 1)
        XCTAssertEqual(atlasStats.hitRate, 0.0, accuracy: 0.001, "Atlas %0 doğru")
        // PnL contribution = 100 * 0.6 = 60 (pozitif çünkü PnL pozitif, action yanlış olsa da)
        XCTAssertEqual(atlasStats.totalPnLContribution, 60.0, accuracy: 0.001)
    }

    // MARK: - 3) Hold votes — accuracy hesabına girmez

    /// `hold` oyları totalVotes'u arttırır ama correct/incorrect'i değiştirmez.
    /// hitRate = correct / (correct + incorrect); decisive yoksa 0.0.
    func test_modulePerformance_holdVote_doesNotAffectAccuracy() async {
        let votes = [ModuleVoteRecord(module: "Aether", action: "hold", confidence: 0.5)]

        await ModulePerformanceTracker.shared.recordTradeOutcome(
            decisionId: UUID().uuidString,
            actualPnL: 50.0,
            moduleVotes: votes
        )

        let stats = await ModulePerformanceTracker.shared.getStats(module: "Aether")
        XCTAssertEqual(stats.totalVotes, 1)
        XCTAssertEqual(stats.holdVotes, 1)
        XCTAssertEqual(stats.correctVotes, 0)
        XCTAssertEqual(stats.incorrectVotes, 0)
        XCTAssertEqual(stats.hitRate, 0.0, "Decisive oy yok → hitRate 0 (NaN değil)")
        // PnL katkısı yine işlenir (confidence ağırlıklı): 50 * 0.5 = 25
        XCTAssertEqual(stats.totalPnLContribution, 25.0, accuracy: 0.001)
    }

    // MARK: - 4) Flat PnL — kayıt atla

    /// PnL = 0 (flat trade) → record skip. Nötr sinyal, modül istatistiklerine
    /// gürültü eklemez. totalVotes bile artmamalı.
    func test_modulePerformance_pnlZero_skipsRecord() async {
        let votes = [ModuleVoteRecord(module: "Orion", action: "buy", confidence: 0.8)]

        await ModulePerformanceTracker.shared.recordTradeOutcome(
            decisionId: UUID().uuidString,
            actualPnL: 0.0,
            moduleVotes: votes
        )

        let stats = await ModulePerformanceTracker.shared.getStats(module: "Orion")
        XCTAssertEqual(stats.totalVotes, 0, "Flat trade kayıt atlanmalı")
        XCTAssertEqual(stats.correctVotes, 0)
        XCTAssertEqual(stats.incorrectVotes, 0)
        XCTAssertEqual(stats.holdVotes, 0)
        XCTAssertEqual(stats.totalPnLContribution, 0.0)
    }

    // MARK: - 5) Negatif PnL — sell doğru, buy yanlış

    /// Negatif PnL'de `sell` oyu → correct, `buy` oyu → incorrect.
    /// Symetri kontrolü: test 2'nin tersi senaryo.
    func test_modulePerformance_negativePnL_invertsCorrectness() async {
        let votes = [
            ModuleVoteRecord(module: "Hermes",  action: "sell", confidence: 0.9),
            ModuleVoteRecord(module: "Phoenix", action: "buy",  confidence: 0.4)
        ]

        await ModulePerformanceTracker.shared.recordTradeOutcome(
            decisionId: UUID().uuidString,
            actualPnL: -50.0,
            moduleVotes: votes
        )

        let hermes = await ModulePerformanceTracker.shared.getStats(module: "Hermes")
        XCTAssertEqual(hermes.correctVotes, 1, "sell + pnl<0 → correct")
        XCTAssertEqual(hermes.incorrectVotes, 0)

        let phoenix = await ModulePerformanceTracker.shared.getStats(module: "Phoenix")
        XCTAssertEqual(phoenix.correctVotes, 0)
        XCTAssertEqual(phoenix.incorrectVotes, 1, "buy + pnl<0 → incorrect")
    }
}
