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
/// için her test ayırt edici sembol (`TEST_DIDEXEC_*`) kullanır ve tearDown'da
/// `deleteOpenTrades(symbolPrefix:)` ile satırlar temizlenir; UI sorgularını
/// (getOpenTrades) kirletmez.
final class ExecutionGovernorDidExecuteTests: XCTestCase {

    /// Test prefix — tüm bu test sınıfının yazdığı satırları işaretler.
    /// tearDown bu prefix ile temizlik yapar.
    private static let testSymbolPrefix = "TEST_DIDEXEC_"

    override func tearDown() async throws {
        // Üretim DB pollution önleme: bu sınıfın yazdığı tüm test satırlarını sil.
        // Singleton ArgusLedger gerçek SQLite dosyasına yazıyor; aksi halde
        // her test çalıştırmasında TEST_DIDEXEC_* satırları birikir ve UI
        // queries (getOpenTrades) test kayıtlarını gösterir.
        await ArgusLedger.shared.deleteOpenTrades(symbolPrefix: Self.testSymbolPrefix)
        try await super.tearDown()
    }

    /// Direct API smoke: didExecute → openTrade zinciri çalışıyor mu?
    func test_didExecute_writesTradeToLedger() async {
        let symbol = "\(Self.testSymbolPrefix)\(UUID().uuidString)"

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

        // Ledger'ın serial queue'u sıralı: openTrade `queue.sync` ile yazar,
        // getOpenTrades `queue.async` ile sonra okur — sırayı queue garanti
        // eder, ek `Task.sleep`'e gerek yok.
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
    /// böylece ledger.decision_id council kararının UUID'sini taşır. Burada
    /// sadece satırın varlığı değil, decision_id sütununun gerçekten yazıldığı
    /// da doğrulanır — wiring uçtan uca çalışıyor olmalı.
    func test_didExecute_explicitDecisionId_isStoredInLedger() async {
        let symbol = "\(Self.testSymbolPrefix)DID_\(UUID().uuidString)"
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

        let trades = await ArgusLedger.shared
            .getOpenTrades()
            .filter { $0.symbol == symbol }

        XCTAssertEqual(trades.count, 1, "Sembol \(symbol) için tek bir satır olmalı.")

        // Asıl kontrat: decision_id kolonu council UUID'sini tutuyor mu?
        // Bu assert olmasa test row-count düzeyinde "geçer" görünür ama
        // wiring (decision.id.uuidString → ledger.decision_id) bozulsa yine
        // geçerdi — Task 1'in tam amacı bu zinciri doğrulamak.
        guard let record = trades.first else {
            XCTFail("Sembol \(symbol) için kayıt bulunamadı, decision_id doğrulanamaz.")
            return
        }
        XCTAssertEqual(
            record.decisionId,
            councilDecisionId,
            "ledger.trades.decision_id council UUID'sini taşımalı (Task 1 wiring kontratı)."
        )
    }
}
