import XCTest
@testable import argus

/// Faz 0 Task 7 testleri: PortfolioStore.sell() sonrası Chiron/Council/TradeBrain/Alkindus
/// öğrenme zincirinin tamamlanma garantisi.
///
/// Sorun: Mevcut `sell()` learning chain'i `Task.detached(priority: .background)` ile
/// fire-and-forget çalıştırıyor. sell() döndüğünde chain henüz bitmemiş olabiliyor;
/// test/caller bunu "öğrenme bitti" varsayımıyla okumaya kalktığında flaky veya
/// false-pass davranış görüyor.
///
/// Çözüm: `sellAsync()` async helper döndüğünde `feedLearningSystems(...)` await
/// edilmiş — tüm cascade tamamlanmıştır. Sync `sell()` mevcut davranışını (Task
/// içinde fire-and-forget) korur; UI button tap'leri ve QuoteHandler tick'leri
/// gibi sync caller'lar etkilenmez.
///
/// Observable side-effect olarak `ChironDataLakeService.loadTradeHistory(symbol:)`
/// seçildi — actor JSON dosyasına yazıyor, deterministik okunabiliyor. Bu yöntem
/// (a) mock gerektirmez, (b) PortfolioStore'a UI noise üreten `@Published` alanı
/// eklemez, (c) sync sorgu ile chain tamamlanmasını kanıtlar.
///
/// Test izolasyonu — Üretim ChironDataLake JSON ve ArgusLedger SQLite dosyalarına
/// yazılır; her test özgün UUID'li sembol kullanır, tearDown class-level prefix ile
/// hem JSON dosyalarını siler hem ledger satırlarını temizler. PortfolioStore
/// in-memory state de `resetPortfolio()` ile sıfırlanır.
@MainActor
final class SellLifecycleOrderingTests: XCTestCase {

    /// Bu sınıfın yazdığı tüm test sembollerini işaretler. tearDown bu prefix ile
    /// hem ChironDataLake JSON dosyalarını hem ArgusLedger satırlarını temizler.
    private static let testSymbolPrefix = "TEST_SELL_LIFECYCLE_"

    override func tearDown() async throws {
        // 1) ArgusLedger pollution temizliği (Task 1+2 patterndeki gibi).
        await ArgusLedger.shared.deleteOpenTrades(symbolPrefix: Self.testSymbolPrefix)

        // 2) ChironDataLake JSON dosyalarını sil. Üretim Documents/ChironDataLake/trades/
        //    altında "<symbol>_history.json" dosyaları birikir; testler prefix'li semboller
        //    kullandığı için sadece prefix eşleşen dosyalar silinir.
        let tradesDir = FileManager.default.documentsURL
            .appendingPathComponent("ChironDataLake", isDirectory: true)
            .appendingPathComponent("trades", isDirectory: true)
        if let files = try? FileManager.default.contentsOfDirectory(atPath: tradesDir.path) {
            for file in files where file.hasPrefix(Self.testSymbolPrefix) {
                try? FileManager.default.removeItem(at: tradesDir.appendingPathComponent(file))
            }
        }

        // 3) PortfolioStore in-memory state — buy/sell singleton state'i değiştirir,
        //    sonraki test class'lara taşmasın.
        PortfolioStore.shared.resetPortfolio()
        try await super.tearDown()
    }

    /// sellAsync() döndüğünde ChironDataLake'e trade kaydı yazılmış olmalı.
    /// Bu test sell sonrası HİÇBİR sleep/await yapmadan ChironDataLake'i sorgular;
    /// learning chain async devam ediyorsa count 0 dönüp test PASS olabilirdi
    /// (false negative). Anchor noktası: `await sellAsync(...)` çağrısının kendisi
    /// dönmüş olmalı VE bu noktada chain TAMAMLANMIŞ olmalı.
    func test_sellAsync_blocksUntilLearningChainComplete() async {
        let symbol = "\(Self.testSymbolPrefix)\(UUID().uuidString)"
        PortfolioStore.shared.resetPortfolio()

        guard let trade = PortfolioStore.shared.buy(
            symbol: symbol,
            quantity: 10,
            price: 100.0
        ) else {
            XCTFail("buy() başarısız")
            return
        }

        // sellAsync: state mutation + feedLearningSystems await edilir.
        // Dönüş anında ChironDataLake'e trade kaydı yazılmış olmalı.
        let pnl = await PortfolioStore.shared.sellAsync(
            tradeId: trade.id,
            currentPrice: 110.0,
            reason: "TEST_ASYNC"
        )

        XCTAssertNotNil(pnl, "sellAsync PnL döndürmeli")

        // Anchor: sellAsync döndü → learning chain BİTMİŞ olmalı.
        // ChironDataLake actor JSON'a yazdı, sync olarak okunabilir.
        let history = await ChironDataLakeService.shared.loadTradeHistory(symbol: symbol)
        XCTAssertEqual(
            history.count,
            1,
            "sellAsync sonrası ChironDataLake'te \(symbol) için 1 trade kaydı olmalı (learning chain tamam)"
        )
        XCTAssertEqual(history.first?.symbol, symbol)
        XCTAssertEqual(history.first?.exitPrice, 110.0)
    }

    /// sell() sync döndüğünde state mutation tamamdır (closed trade), ancak
    /// learning chain `Task { }` ile fire-and-forget devam eder. Bu test geriye
    /// dönük uyumu kanıtlar: UI button tap'leri ve sync caller'lar bloklanmaz.
    func test_sellSync_returnsImmediately_andStateIsMutated() {
        let symbol = "\(Self.testSymbolPrefix)SYNC_\(UUID().uuidString)"
        PortfolioStore.shared.resetPortfolio()

        guard let trade = PortfolioStore.shared.buy(
            symbol: symbol,
            quantity: 10,
            price: 100.0
        ) else {
            XCTFail("buy() başarısız")
            return
        }

        // sell() sync döner — geriye dönük uyum kontratı.
        let pnl = PortfolioStore.shared.sell(
            tradeId: trade.id,
            currentPrice: 110.0,
            reason: "TEST_SYNC"
        )

        XCTAssertNotNil(pnl, "sell() PnL döndürmeli")

        // State mutation tamam: trade kapalı, exitPrice set edilmiş.
        let closed = PortfolioStore.shared.trades.first(where: { $0.id == trade.id })
        XCTAssertEqual(closed?.isOpen, false, "sell() sonrası trade kapanmış olmalı")
        XCTAssertEqual(closed?.exitPrice, 110.0, "exitPrice set edilmiş olmalı")

        // Learning chain async devam edebilir — burada test ETMİYORUZ. sync caller
        // (UI button) deterministik öğrenme tamamlanması beklemiyor; sellAsync için.
    }
}
