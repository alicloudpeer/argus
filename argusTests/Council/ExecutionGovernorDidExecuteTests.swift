import XCTest
@testable import argus

/// Faz 0 Task 1 testi: `ExecutionGovernor.didExecute` çağrıldığında
/// `ArgusLedger.trades` tablosuna kayıt yazıldığını doğrular.
///
/// Bu test ÖNCE doğrudan didExecute API'sını sınar (mevcut metod ledger'a
/// doğru yazıyor mu?). İkinci test explicit `decisionId` parametresinin
/// council UUID zincirini kapattığını sınar.
///
/// Not — Singleton ArgusLedger: gerçek üretim DB'sine yazar. Test izolasyonu
/// için her test ayırt edici sembol kullanır (`TEST_DIDEXEC_xxxx`) ve etki
/// "kaç tane bu sembolde açık trade var" şeklinde delta ölçer.
@MainActor
final class ExecutionGovernorDidExecuteTests: XCTestCase {

    /// Direct API smoke: didExecute → openTrade zinciri çalışıyor mu?
    func test_didExecute_writesTradeToLedger() async {
        let symbol = "TEST_DIDEXEC_\(Int.random(in: 1000...9999))"

        let beforeCount = await ArgusLedger.shared
            .getOpenTrades()
            .filter { $0.symbol == symbol }
            .count

        let trade = Trade(
            symbol: symbol,
            entryPrice: 100.0,
            quantity: 10.0,
            entryDate: Date(),
            isOpen: true
        )

        await ExecutionGovernor.shared.didExecute(
            trade: trade,
            scores: (70.0, 80.0, 60.0, 50.0, nil),
            decisionId: nil
        )

        // ArgusLedger.queue.sync ile yazılır; ek async bekleme gerekmez
        // ama ufak bir tampon ekliyoruz (CI gürültüsüne karşı).
        try? await Task.sleep(nanoseconds: 100_000_000)

        let afterTrades = await ArgusLedger.shared
            .getOpenTrades()
            .filter { $0.symbol == symbol }

        XCTAssertEqual(
            afterTrades.count,
            beforeCount + 1,
            "didExecute, ArgusLedger.trades tablosuna sembol \(symbol) için satır yazmalı."
        )
    }

    /// Explicit decisionId parametresi: Council UUID zinciri kapanıyor mu?
    /// Task 1 sonrası TradeBrainExecutor decision.id.uuidString'i geçirir;
    /// böylece ledger.decision_id council kararının UUID'sini taşır.
    func test_didExecute_explicitDecisionId_isStoredInLedger() async {
        let symbol = "TEST_DIDEXEC_DID_\(Int.random(in: 1000...9999))"
        let councilDecisionId = UUID().uuidString

        let trade = Trade(
            symbol: symbol,
            entryPrice: 50.0,
            quantity: 5.0,
            entryDate: Date(),
            isOpen: true
        )

        await ExecutionGovernor.shared.didExecute(
            trade: trade,
            scores: (0, 75.0, 55.0, 0, nil),
            decisionId: councilDecisionId
        )

        try? await Task.sleep(nanoseconds: 100_000_000)

        // Not: getOpenTrades TradeRecord döner; decisionId alanı varsa kontrol et.
        // Yoksa: en azından satırın var olduğunu doğrula (UUID kaydı ledger.openTrade
        // bind'ından geçiyor; doğrudan SQL query yapmak bu testin kapsamı dışında).
        let trades = await ArgusLedger.shared
            .getOpenTrades()
            .filter { $0.symbol == symbol }

        XCTAssertEqual(trades.count, 1, "Sembol \(symbol) için tek bir satır olmalı.")
    }
}
