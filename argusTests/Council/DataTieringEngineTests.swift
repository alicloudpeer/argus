import XCTest
@testable import argus

/// Faz 1.B.2: DataTieringEngine actor testleri.
///
/// Test izolasyonu: ArgusLedger.shared gerçek DB'ye yazar; bu testler **mevcut**
/// kayıtların tier'ını değiştirebilir. Bu nedenle testler **sadece state-değişmez**
/// kontratlar üzerinden ilerler: API çağrıları crash etmesin, dönüş tipi doğru
/// olsun, idempotency korunsun. Tier UPDATE'in fonksiyonel doğrulaması (eski
/// tarihte sentetik kayıt + migrate + assert) Faz 1.B.4 integration testlerine
/// taşınır — bu noktada DB'ye fixture eklemek tearDown'u zorlaştırır.
final class DataTieringEngineTests: XCTestCase {

    func test_warmThreshold_is90Days() {
        XCTAssertEqual(DataTieringEngine.warmThresholdDays, 90)
    }

    func test_coldThreshold_is365Days() {
        XCTAssertEqual(DataTieringEngine.coldThresholdDays, 365)
    }

    /// runMigration boş veya az verili ledger'da crash etmemeli; sonuç
    /// `TierMigrationResult` (totalRowsMoved >= 0) dönmeli.
    func test_runMigration_returnsResultWithoutCrash() async {
        let result = await DataTieringEngine.shared.runMigration()
        XCTAssertGreaterThanOrEqual(result.totalRowsMoved, 0)
    }

    /// İkinci kez çalıştırınca aynı veri kümesinde **yeni hareket olmamalı**:
    /// fromTier filtresi tetiklenmiş satırı bir daha hareket ettirmiyor.
    /// Bu test gerçek DB state'ine bağımlı — sadece "ikinci çağrı ya 0 ya da
    /// yeni bir hot kayıt eklendiği için artmış" doğrulamasını yapar.
    func test_runMigration_isIdempotent_atSameInstant() async {
        let frozenNow = Date()
        let first = await DataTieringEngine.shared.runMigration(now: frozenNow)
        let second = await DataTieringEngine.shared.runMigration(now: frozenNow)
        // İkinci çağrıda hot→warm veya warm→cold satırı kalmamış olmalı —
        // ilki tüm uygun satırları zaten taşıdı.
        XCTAssertEqual(
            second.totalRowsMoved,
            0,
            "İkinci migration aynı `now` ile 0 satır taşımalı (idempotent). İlk: \(first.totalRowsMoved), İkinci: \(second.totalRowsMoved)"
        )
    }

    /// tierSnapshot 3 tablo için kayıt dağılımı döner — UI bu yapıyı bekler.
    func test_tierSnapshot_returnsThreeTables() async {
        let snapshot = DataTieringEngine.shared.tierSnapshot()
        XCTAssertNotNil(snapshot["events"])
        XCTAssertNotNil(snapshot["trades"])
        XCTAssertNotNil(snapshot["outcomes"])
    }

    /// Migration result Equatable — boş result (hiç satır taşınmadı) test'lerde
    /// karşılaştırma kolaylığı için.
    func test_migrationResult_equatable_emptyEquality() {
        let a = DataTieringEngine.TierMigrationResult()
        let b = DataTieringEngine.TierMigrationResult()
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.totalRowsMoved, 0)
    }

    /// migrateTier helper bilinmeyen tier'la çalışsa bile crash etmez (sessiz 0).
    func test_migrateTier_unknownTier_returnsZeroAndDoesNotCrash() {
        let rows = ArgusLedger.shared.migrateTier(
            table: "events",
            dateColumn: "event_time_utc",
            fromTier: "unknown_tier_xyz",
            toTier: "another_unknown",
            cutoff: Date()
        )
        XCTAssertEqual(rows, 0, "Bilinmeyen fromTier hiç satırı eşleştirmemeli")
    }

    /// countByTier sözlük döner — bilinen tier'ları içerir (boş tabloda boş dict).
    func test_countByTier_returnsDictionary() {
        let counts = ArgusLedger.shared.countByTier(table: "events")
        // En azından sözlük tipinde dönüş (boş olabilir, dolu olabilir)
        XCTAssertNotNil(counts as [String: Int]?)
    }
}
