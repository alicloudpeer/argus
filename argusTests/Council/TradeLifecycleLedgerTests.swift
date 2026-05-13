import XCTest
@testable import argus

/// Faz 0 Task 2 testleri: Decision↔Trade↔Outcome UUID zincirinin kapanış halkası.
///
/// Task 1 didExecute'ı çağrılır hale getirdi (ledger'a açık trade yazımı).
/// Task 2 dönüş UUID'sini Trade.ledgerTradeId'ye yazar ve closeTrade ile
/// satım anında ledger satırını kapatır.
///
/// Test izolasyonu — ArgusLedger.shared gerçek üretim SQLite dosyasına
/// yazar; her test class'a özgü prefix'lerle (`TEST_LIFECYCLE_*`,
/// `TEST_FIELD_*`, `TEST_UPDATE_*`) sembol üretir, tearDown'da bu prefix'li
/// satırlar `deleteOpenTrades(symbolPrefix:)` ile temizlenir (helper status
/// filtrelemez; OPEN+CLOSED siler). PortfolioStore.resetPortfolio() de
/// çağrılır — buy/updateLedgerId testlerinin bıraktığı in-memory state için.
@MainActor
final class TradeLifecycleLedgerTests: XCTestCase {

    // Bu sınıfın yazdığı tüm test satırlarını işaretleyen prefix'ler.
    // tearDown bu prefix'lerle ledger temizliği yapar.
    private static let lifecyclePrefix = "TEST_LIFECYCLE_"
    private static let fieldPrefix = "TEST_FIELD_"
    private static let updatePrefix = "TEST_UPDATE_"

    override func tearDown() async throws {
        // Üretim DB pollution önleme: bu sınıfın yazdığı tüm test satırlarını sil.
        // Singleton ArgusLedger gerçek SQLite dosyasına yazıyor; aksi halde
        // her test çalıştırmasında TEST_LIFECYCLE_/TEST_FIELD_/TEST_UPDATE_
        // satırları birikir ve UI queries test kayıtlarını gösterir.
        // deleteOpenTrades helper'ı status filtrelemez — OPEN+CLOSED siler.
        await ArgusLedger.shared.deleteOpenTrades(symbolPrefix: Self.lifecyclePrefix)
        await ArgusLedger.shared.deleteOpenTrades(symbolPrefix: Self.fieldPrefix)
        await ArgusLedger.shared.deleteOpenTrades(symbolPrefix: Self.updatePrefix)
        // updateLedgerId / buy testleri PortfolioStore singleton state'ini
        // değiştirir; sonraki test class'lara taşmasın diye sıfırla.
        PortfolioStore.shared.resetPortfolio()
        try await super.tearDown()
    }

    /// didExecute UUID dönmeli; aynı UUID ile closeTrade çağrılınca ledger
    /// satırı kapanmalı — UUID round-trip.
    func test_didExecuteReturnsUUID_andCloseTradeUsesIt() async {
        let symbol = "\(Self.lifecyclePrefix)\(UUID().uuidString)"

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
            symbol: "\(Self.fieldPrefix)\(UUID().uuidString)",
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
        let symbol = "\(Self.updatePrefix)\(UUID().uuidString)"

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
