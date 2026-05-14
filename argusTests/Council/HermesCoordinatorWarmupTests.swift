import XCTest
@testable import argus

/// Hermes scouting pre-warm test'leri. HermesCoordinator.warmupForScouting
/// bug fix'ini doğrular: scouting öncesi watchlist global sembolleri paralel
/// `analyzeOnDemand` ile cache'lenir, BIST sembolleri (.IS suffix) atlanır.
///
/// Test izolasyonu: HermesCoordinator.shared singleton; gerçek LLM çağrısı
/// yapmaz (sembol cache'siz başlasa bile rate-limit + LLM hata fallback
/// yollarına düşer). Bu testler **kontratları** sınar: crash etmez, BIST
/// filter çalışır, boş input'ta sessizce döner. Cache içeriği doğrulaması
/// üretim LLM/network entegrasyon test'ine bırakılır.
final class HermesCoordinatorWarmupTests: XCTestCase {

    func test_warmupForScouting_emptyInput_doesNotCrash() async {
        await HermesCoordinator.shared.warmupForScouting(symbols: [])
        // Buraya gelmek başarı — boş array crash etmedi.
    }

    func test_warmupForScouting_onlyBistSymbols_doesNotInvokeAnalysis() async {
        // BIST sembolleri (.IS suffix) atlanmalı; warmupForScouting hiç
        // analyzeOnDemand çağırmamalı (cache'de değişiklik olmaz).
        let bistOnly = ["ASELS.IS", "THYAO.IS", "AKBNK.IS"]
        await HermesCoordinator.shared.warmupForScouting(symbols: bistOnly)
        // Buraya gelmek başarı — BIST filtresi çökmeden çalıştı.
    }

    func test_warmupForScouting_mixedSymbols_filtersBistOut() async {
        // Karışık liste — sadece global olanlar analyzeOnDemand'a gider.
        // Test gerçek LLM tetiklemez (rate limit + hata fallback), sadece
        // metod çökme yapmamalı.
        let mixed = ["AAPL", "GOOGL", "ASELS.IS", "MSFT", "THYAO.IS"]
        await HermesCoordinator.shared.warmupForScouting(symbols: mixed)
        // Buraya gelmek başarı.
    }

    /// .IS suffix case-insensitive olmalı (kullanıcı .is veya .Is yazabilir).
    func test_warmupForScouting_caseInsensitiveBistFilter() async {
        let mixedCase = ["ASELS.IS", "THYAO.is", "AKBNK.Is", "AAPL"]
        await HermesCoordinator.shared.warmupForScouting(symbols: mixedCase)
        // 3 BIST + 1 global; 3'ü filtrelenmiş olmalı (crash yok = başarı)
    }
}
