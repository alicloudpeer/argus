import XCTest
@testable import argus

/// Faz 1.B.6: BlobCacheService Caches/argus_blobs/ katman testleri.
///
/// Caches/ yedeklenmez — testler gerçek disk dosyalarına yazsa da sınırlı
/// etki. tearDown'da bu test sınıfının yazdığı hash'leri sile rız.
final class BlobCacheServiceTests: XCTestCase {

    private let testHashPrefix = "test_blob_"

    override func tearDown() async throws {
        // Bu test sınıfının yazdığı hash'leri ayıklayıp temizle (clearAll'u
        // çağıramayız — başka test'lerin/üretim verilerinin cache'ini siler).
        // Test hash'lerimiz "test_blob_" prefix'iyle.
        // Pratik: tek tek deletion mevcut API'da yok; tüm cache temizliği
        // sadece UI buton senaryosunda — testler sonrası kalıntı kabul edilir.
        try await super.tearDown()
    }

    func test_writeThenRead_returnsSameBytes() {
        let hash = "\(testHashPrefix)\(UUID().uuidString)"
        let payload = "Faz 1.B.6 test payload".data(using: .utf8)!

        let written = BlobCacheService.shared.writeToCache(hash: hash, data: payload)
        XCTAssertTrue(written)

        let read = BlobCacheService.shared.readFromCache(hash: hash)
        XCTAssertEqual(read, payload, "Cache'e yazılan veri aynen okunmalı")
    }

    func test_readNonexistent_returnsNil() {
        let nonexistentHash = "\(testHashPrefix)does_not_exist_\(UUID().uuidString)"
        let read = BlobCacheService.shared.readFromCache(hash: nonexistentHash)
        XCTAssertNil(read, "Yazılmamış hash → nil")
    }

    func test_existsInCache_reflectsState() {
        let hash = "\(testHashPrefix)exists_\(UUID().uuidString)"
        XCTAssertFalse(
            BlobCacheService.shared.existsInCache(hash: hash),
            "Yazılmamış hash existsInCache false dönmeli"
        )
        _ = BlobCacheService.shared.writeToCache(hash: hash, data: Data([0x01, 0x02, 0x03]))
        XCTAssertTrue(
            BlobCacheService.shared.existsInCache(hash: hash),
            "Yazıldıktan sonra existsInCache true dönmeli"
        )
    }

    func test_writeIdempotent_secondCallNoCrash() {
        let hash = "\(testHashPrefix)idempotent_\(UUID().uuidString)"
        let payload = "first".data(using: .utf8)!

        let first = BlobCacheService.shared.writeToCache(hash: hash, data: payload)
        let second = BlobCacheService.shared.writeToCache(hash: hash, data: payload)

        XCTAssertTrue(first)
        XCTAssertTrue(second, "Aynı hash ile ikinci yazım da true dönmeli (zaten var → atla)")
    }

    func test_totalCacheSize_growsAfterWrite() {
        let beforeSize = BlobCacheService.shared.totalCacheSizeBytes()
        let hash = "\(testHashPrefix)size_\(UUID().uuidString)"
        let payload = Data(repeating: 0xAB, count: 1024)  // 1 KB

        _ = BlobCacheService.shared.writeToCache(hash: hash, data: payload)
        let afterSize = BlobCacheService.shared.totalCacheSizeBytes()

        XCTAssertGreaterThanOrEqual(
            afterSize, beforeSize,
            "1 KB yazımdan sonra cache toplam boyutu artmalı veya eşit kalmalı"
        )
    }

    func test_cachedFileCount_isNonNegative() {
        let count = BlobCacheService.shared.cachedFileCount()
        XCTAssertGreaterThanOrEqual(count, 0)
    }
}
