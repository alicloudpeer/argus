import XCTest
@testable import argus

/// Faz 1.B.1: ArgusLedger schema'da tier kolonu mevcudiyet ve idempotent
/// migration testleri. Yeni DB'lerde CREATE TABLE ile, mevcut DB'lerde ALTER
/// TABLE ile geliyor; her iki durumda da kolon var olmalı.
///
/// Idempotency: ensureConnection birden fazla çağrılırsa migration'lar
/// "duplicate column name" hatası atar — bunlar yutulur. Test bu davranışı
/// dolaylı doğrular: ArgusLedger.shared birinci çağrıda bile kolonu hazır
/// sunar (yeni DB) veya mevcut DB üzerinde ALTER ile ekler.
final class LedgerTierColumnTests: XCTestCase {

    func test_eventsTable_hasTierColumn() {
        let columns = ArgusLedger.shared.columnNames(forTable: "events")
        XCTAssertTrue(
            columns.contains("tier"),
            "events tablosunda tier kolonu olmalı (Faz 1.B.1). Kolonlar: \(columns)"
        )
    }

    func test_tradesTable_hasTierColumn() {
        let columns = ArgusLedger.shared.columnNames(forTable: "trades")
        XCTAssertTrue(
            columns.contains("tier"),
            "trades tablosunda tier kolonu olmalı (Faz 1.B.1). Kolonlar: \(columns)"
        )
    }

    func test_outcomesTable_hasTierColumn() {
        let columns = ArgusLedger.shared.columnNames(forTable: "outcomes")
        XCTAssertTrue(
            columns.contains("tier"),
            "outcomes tablosunda tier kolonu olmalı (Faz 1.B.1). Kolonlar: \(columns)"
        )
    }

    /// columnNames helper'ı yanlış tablo adında boş array döner (crash'lemez,
    /// PRAGMA table_info hata vermez).
    func test_columnNames_unknownTable_returnsEmpty() {
        let columns = ArgusLedger.shared.columnNames(forTable: "this_table_does_not_exist_xyz")
        XCTAssertTrue(
            columns.isEmpty,
            "Bilinmeyen tablo için boş array beklenir, gelen: \(columns)"
        )
    }

    /// Bilinmeyen tablo crash veya throw etmemeli — graceful empty.
    func test_columnNames_doesNotCrashOnAnyInput() {
        _ = ArgusLedger.shared.columnNames(forTable: "")
        _ = ArgusLedger.shared.columnNames(forTable: "events; DROP TABLE trades;--")  // safe: identifier inline
        // Buraya gelmek başarı.
    }
}
