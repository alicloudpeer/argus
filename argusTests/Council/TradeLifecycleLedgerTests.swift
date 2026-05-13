import XCTest
@testable import argus

/// Faz 0 Task 2 testleri: Decision↔Trade↔Outcome UUID zincirinin kapanış halkası.
///
/// Task 1 didExecute'ı çağrılır hale getirdi (ledger'a açık trade yazımı).
/// Task 2 dönüş UUID'sini Trade.ledgerTradeId'ye yazar ve closeTrade ile
/// satım anında ledger satırını kapatır.
///
/// Test izolasyonu — ArgusLedger.shared gerçek DB'ye yazar; her test
/// `TEST_LIFECYCLE_xxxx` ön ekli unique sembol kullanır.
@MainActor
final class TradeLifecycleLedgerTests: XCTestCase {

    /// didExecute UUID dönmeli; aynı UUID ile closeTrade çağrılınca ledger
    /// satırı kapanmalı — UUID round-trip.
    func test_didExecuteReturnsUUID_andCloseTradeUsesIt() async {
        let symbol = "TEST_LIFECYCLE_\(Int.random(in: 1000...9999))"

        let trade = Trade(
            symbol: symbol,
            entryPrice: 100.0,
            quantity: 10.0,
            entryDate: Date(),
            isOpen: true
        )

        let ledgerId = await ExecutionGovernor.shared.didExecute(
            trade: trade,
            scores: (0, 80.0, 60.0, 0, nil),
            decisionId: UUID().uuidString
        )

        try? await Task.sleep(nanoseconds: 100_000_000)

        let openAfterBuy = await ArgusLedger.shared
            .getOpenTrades()
            .filter { $0.symbol == symbol }
        XCTAssertEqual(
            openAfterBuy.count,
            1,
            "didExecute sonrası ledger'da \(symbol) için 1 açık trade olmalı"
        )

        ArgusLedger.shared.closeTrade(tradeId: ledgerId, exitPrice: 110.0)
        try? await Task.sleep(nanoseconds: 100_000_000)

        let stillOpen = await ArgusLedger.shared
            .getOpenTrades()
            .filter { $0.symbol == symbol }
        XCTAssertEqual(
            stillOpen.count,
            0,
            "closeTrade sonrası \(symbol) için açık trade kalmamalı"
        )
    }

    /// Trade modeline eklenen ledgerTradeId alanı set/get çalışmalı, default nil.
    func test_tradeLedgerTradeIdField_canBeSetAndRead() {
        var trade = Trade(
            symbol: "TEST_FIELD",
            entryPrice: 50.0,
            quantity: 5.0,
            entryDate: Date(),
            isOpen: true
        )

        XCTAssertNil(trade.ledgerTradeId, "Yeni Trade'in ledgerTradeId default'u nil olmalı")

        let ledgerUuid = UUID()
        trade.ledgerTradeId = ledgerUuid

        XCTAssertEqual(trade.ledgerTradeId, ledgerUuid)
    }

    /// PortfolioStore.updateLedgerId varolan trade'i bulup ledgerTradeId atamalı,
    /// bulunamayan id'de false dönmeli.
    func test_updateLedgerId_onExistingTrade_returnsTrueAndStoresUUID() {
        PortfolioStore.shared.resetPortfolio()
        let symbol = "TEST_UPDATE_\(Int.random(in: 1000...9999))"

        guard let trade = PortfolioStore.shared.buy(
            symbol: symbol,
            quantity: 1,
            price: 10.0
        ) else {
            XCTFail("buy() başarısız")
            return
        }

        let ledgerUuid = UUID()
        let result = PortfolioStore.shared.updateLedgerId(
            tradeId: trade.id,
            ledgerId: ledgerUuid
        )

        XCTAssertTrue(result)
        let stored = PortfolioStore.shared.trades.first(where: { $0.id == trade.id })
        XCTAssertEqual(stored?.ledgerTradeId, ledgerUuid)
    }

    func test_updateLedgerId_onMissingTrade_returnsFalse() {
        let result = PortfolioStore.shared.updateLedgerId(
            tradeId: UUID(),
            ledgerId: UUID()
        )
        XCTAssertFalse(result)
    }
}
