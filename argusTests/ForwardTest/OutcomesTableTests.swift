import XCTest
@testable import argus

/// Task 12 (2026-05-12) testleri: Outcomes tablosu + R-multiple disiplini.
///
/// Decision → Trade → **Outcome** zinciri ledger üçüncü katmanı. Bu testler:
/// 1. recordOutcome bütün alanları doğru yazıyor mu (queryOutcome ile round-trip)?
/// 2. calculateRMultiple long pozisyon 4 edge case'i nasıl handle ediyor?
/// 3. queryAllOutcomes since parametresiyle filtreleme yapıyor mu?
///
/// Test izolasyonu — Üretim ArgusLedger SQLite dosyasına yazılır. Her test class-level
/// prefix `TEST_OUTCOMES_` + UUID suffix kullanır. tearDown'da
/// `deleteOpenTrades(symbolPrefix:)` çağrılır — FK CASCADE sayesinde trades silinince
/// outcomes da otomatik silinir; ayrı outcomes cleanup helper'a gerek yok.
final class OutcomesTableTests: XCTestCase {

    /// Bu test sınıfının yazdığı tüm trade satırlarını işaretler.
    /// tearDown bu prefix ile cleanup yapar; outcomes FK CASCADE ile düşer.
    private static let testSymbolPrefix = "TEST_OUTCOMES_"

    override func tearDown() async throws {
        // FK CASCADE — trades silindiğinde outcomes da otomatik silinir.
        // PRAGMA foreign_keys = ON; createSchema() içinde set ediliyor.
        await ArgusLedger.shared.deleteOpenTrades(symbolPrefix: Self.testSymbolPrefix)
        try await super.tearDown()
    }

    // MARK: - recordOutcome + queryOutcome Round-trip

    /// Bir trade aç (ArgusLedger.openTrade), recordOutcome çağır, queryOutcome ile
    /// geri oku, tüm alanları doğrula — sadece row count değil, alan eşleşmeleri.
    func test_recordOutcome_storesAllFields() {
        let symbol = "\(Self.testSymbolPrefix)\(UUID().uuidString)"

        // 1) Önce trade aç — FK referansı için outcomes.trade_id geçerli olmalı.
        let tradeId = ArgusLedger.shared.openTrade(
            symbol: symbol,
            price: 100.0,
            reason: "TEST_OUTCOMES_ROUNDTRIP"
        )

        // 2) Outcome insert.
        let outcomeId = ArgusLedger.shared.recordOutcome(
            tradeId: tradeId,
            realizedPnL: 120.50,
            realizedPnLPct: 12.05,
            holdingMinutes: 1440, // 1 gün
            rMultiple: 2.5,
            exitReason: "TARGET_HIT"
        )

        // 3) Round-trip okuma + alan-bazında doğrulama.
        guard let outcome = ArgusLedger.shared.queryOutcome(forTradeId: tradeId) else {
            XCTFail("queryOutcome trade için outcome döndürmedi tradeId=\(tradeId)")
            return
        }

        XCTAssertEqual(outcome.outcomeId, outcomeId, "outcome_id round-trip")
        XCTAssertEqual(outcome.tradeId, tradeId, "trade_id round-trip")
        XCTAssertEqual(outcome.realizedPnL, 120.50, accuracy: 0.001)
        XCTAssertEqual(outcome.realizedPnLPct, 12.05, accuracy: 0.001)
        XCTAssertEqual(outcome.holdingMinutes, 1440)
        XCTAssertEqual(outcome.rMultiple, 2.5)
        XCTAssertEqual(outcome.exitReason, "TARGET_HIT")
        // MAE/MFE Faz 1'de her zaman nil
        XCTAssertNil(outcome.maePct, "MAE Faz 1'de nil olmalı")
        XCTAssertNil(outcome.mfePct, "MFE Faz 1'de nil olmalı")
    }

    // MARK: - calculateRMultiple Edge Cases

    /// Long pozisyon kâr: entry 100, exit 110, stop 95 → risk=5, pnl=10, R=2.0.
    func test_calculateRMultiple_longProfit() {
        let r = ArgusLedger.calculateRMultiple(
            entryPrice: 100,
            exitPrice: 110,
            initialStop: 95
        )
        XCTAssertNotNil(r)
        XCTAssertEqual(r!, 2.0, accuracy: 0.001, "R = (110-100)/(100-95) = 2.0")
    }

    /// Long pozisyon zarar: entry 100, exit 92, stop 95 → risk=5, pnl=-8, R=-1.6.
    /// Stop'a çarpsaydı R=-1.0 olurdu; aşağı geçtiyse stop slippage göstergesi.
    func test_calculateRMultiple_longLoss() {
        let r = ArgusLedger.calculateRMultiple(
            entryPrice: 100,
            exitPrice: 92,
            initialStop: 95
        )
        XCTAssertNotNil(r)
        XCTAssertEqual(r!, -1.6, accuracy: 0.001, "R = (92-100)/(100-95) = -1.6")
    }

    /// Stop yoksa R hesaplanamaz — Van Tharp tanımı gereği "risk birimi" yok.
    func test_calculateRMultiple_noStop_returnsNil() {
        let r = ArgusLedger.calculateRMultiple(
            entryPrice: 100,
            exitPrice: 110,
            initialStop: nil
        )
        XCTAssertNil(r, "Stop yoksa R undefined")
    }

    /// Stop entry'nin ÜSTÜNDEYSE long pozisyon için geçersiz (negatif risk).
    /// Short pozisyon Faz 2'ye bırakıldı — fonksiyon long varsayar.
    func test_calculateRMultiple_invalidStop_returnsNil() {
        let r = ArgusLedger.calculateRMultiple(
            entryPrice: 100,
            exitPrice: 110,
            initialStop: 105 // Stop entry'nin üstünde — long pozisyon için invalid
        )
        XCTAssertNil(r, "Stop > entry long için invalid (negatif risk)")
    }

    // MARK: - queryAllOutcomes Filtering

    /// since parametresi: outcome'lar closed_at'e göre filtrelenmeli.
    /// Test: 2 outcome ekle (timestamp ledger tarafından "now" set edilir);
    /// (a) since=.distantPast tüm outcome'ları döner,
    /// (b) since=now+1s hiçbirini döndürmemeli (test'in yazdıkları geçmişte kalmış olur).
    func test_queryAllOutcomes_filtersBySince() {
        let symbol1 = "\(Self.testSymbolPrefix)A_\(UUID().uuidString)"
        let symbol2 = "\(Self.testSymbolPrefix)B_\(UUID().uuidString)"

        let trade1 = ArgusLedger.shared.openTrade(symbol: symbol1, price: 50, reason: "TEST_QUERY_A")
        let trade2 = ArgusLedger.shared.openTrade(symbol: symbol2, price: 75, reason: "TEST_QUERY_B")

        ArgusLedger.shared.recordOutcome(
            tradeId: trade1,
            realizedPnL: 10.0, realizedPnLPct: 5.0,
            holdingMinutes: 60, rMultiple: 1.5, exitReason: "TEST"
        )
        ArgusLedger.shared.recordOutcome(
            tradeId: trade2,
            realizedPnL: -5.0, realizedPnLPct: -2.5,
            holdingMinutes: 30, rMultiple: -0.75, exitReason: "TEST"
        )

        // (a) Tüm outcome'lar — distantPast since.
        // Concurrent test class'lar kendi prefix'leriyle yazdığı için bu test'in
        // outcome'larını trade_id ile filtrele (closed_at penceresi içinde başka
        // outcome'lar olabilir, bu test sadece kendi yazdıklarını kontrol etmeli).
        let allOutcomes = ArgusLedger.shared.queryAllOutcomes(since: .distantPast)
        let myOutcomes = allOutcomes.filter { $0.tradeId == trade1 || $0.tradeId == trade2 }
        XCTAssertEqual(myOutcomes.count, 2, "Bu test'in yazdığı 2 outcome distantPast since ile dönmeli")

        // (b) Gelecekte bir since — bu test'in yazdığı outcome'lar dahil olmamalı.
        let future = Date().addingTimeInterval(60) // 1 dakika sonra
        let futureOutcomes = ArgusLedger.shared
            .queryAllOutcomes(since: future)
            .filter { $0.tradeId == trade1 || $0.tradeId == trade2 }
        XCTAssertEqual(futureOutcomes.count, 0, "Future since ile bu test'in outcome'ları dönmemeli")
    }
}
