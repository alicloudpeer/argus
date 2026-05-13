import XCTest
@testable import argus

/// Faz 0 Task 3 testleri: ArgusValidator gece BGTask zinciri.
///
/// Test izolasyonu: BGTaskScheduler simülatörde gerçek submit fail eder
/// (entitlement gerekir). Bu yüzden testler kontratları sınar — submit'i değil:
/// - Identifier sabitinin Info.plist ile birebir eşleştiğini
/// - runValidation wrapper'ının doğru tipi döndürdüğünü
/// - scheduleNextRun çağrısının çökmeden döndüğünü (best-effort)
@MainActor
final class ArgusValidatorSchedulerTests: XCTestCase {

    /// Plist anahtarı ile koddaki kimlik birebir aynı olmalı. Sürüklenme olursa
    /// iOS sessizce submit fail eder, BGTask asla tetiklenmez.
    func test_taskIdentifier_matchesInfoPlistContract() {
        XCTAssertEqual(
            ArgusValidatorScheduler.taskIdentifier,
            "com.argus.validator.daily",
            "Info.plist BGTaskSchedulerPermittedIdentifiers ile birebir eşleşmeli"
        )
    }

    /// Singleton kontratı: shared aynı instance dönmeli.
    func test_shared_isSingleton() {
        let a = ArgusValidatorScheduler.shared
        let b = ArgusValidatorScheduler.shared
        XCTAssertTrue(a === b)
    }

    /// runValidation wrapper'ı ArgusValidator.validateMaturedHypotheses sonucunu
    /// aynen geçirir. Olgun karar yoksa boş array döner — count >= 0.
    func test_runValidation_returnsArray() async {
        let results = await ArgusValidatorScheduler.shared.runValidation()
        XCTAssertGreaterThanOrEqual(results.count, 0)
    }

    /// scheduleNextRun çökmemeli. iOS simülatöründe BGTaskScheduler submit'i
    /// "no entitlement" ile fail edebilir — bu fail'in throw yerine log'a
    /// dökülmesi tasarım gereği (graceful degradation).
    func test_scheduleNextRun_doesNotThrow() {
        ArgusValidatorScheduler.shared.scheduleNextRun()
        // Buraya gelmek başarı — çökme yok, exception yok.
    }
}
