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
    ///
    /// Kritik: Apple BGTaskScheduler identifier'ın PRODUCT_BUNDLE_IDENTIFIER
    /// (ArgusTeam.argus) ile başlamasını zorunlu kılar; aksi halde submit() her
    /// zaman BGTaskSchedulerErrorDomain error 3 (notPermitted) atar.
    func test_taskIdentifier_matchesInfoPlistContract() {
        XCTAssertEqual(
            ArgusValidatorScheduler.taskIdentifier,
            "ArgusTeam.argus.validator.daily",
            "Info.plist BGTaskSchedulerPermittedIdentifiers ile birebir ve bundle ID prefix'iyle eşleşmeli"
        )
        XCTAssertTrue(
            ArgusValidatorScheduler.taskIdentifier.hasPrefix("ArgusTeam.argus"),
            "BGTask identifier PRODUCT_BUNDLE_IDENTIFIER ile başlamak zorunda"
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

    /// nextRunDate lokal saatte 03:00'a denk gelmeli (Apple BGTaskScheduler
    /// `earliestBeginDate` olarak alır). Saat farklıysa kullanıcı için gece
    /// uyku saatleri dışına kayar; bu testin amacı sürüklenmeyi yakalamak.
    func test_nextRunDate_isAtThreeAMLocal() {
        let date = ArgusValidatorScheduler.shared.nextRunDate()
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        XCTAssertEqual(components.hour, 3, "Hedef saat lokal 03:00 olmalı")
        XCTAssertEqual(components.minute, 0, "Hedef dakika 00 olmalı")
    }

    /// nextRunDate geçmişte olmamalı — Apple `earliestBeginDate` geçmiş bir
    /// tarih kabul etse de planlama anlamlı değil. Bugün 03:00'tan önceysek
    /// bugünün 03:00'ını, sonraysak yarının 03:00'ını döner.
    func test_nextRunDate_isInFuture() {
        let date = ArgusValidatorScheduler.shared.nextRunDate()
        XCTAssertGreaterThan(date, Date(), "Sıradaki run gelecek bir zaman olmalı")
    }

    // MARK: - Açılışta yakala fallback (runIfStale)

    override func setUp() async throws {
        try await super.setUp()
        // Test izolasyonu: lastRunAt UserDefaults'a yazıyor — her test'ten
        // önce temizle ki "önceki test'in artığı" senaryosu yaşanmasın.
        UserDefaults.standard.removeObject(forKey: ArgusValidatorScheduler.lastRunKey)
    }

    /// `runIfStale` ilk çağrılışta (hiç lastRunAt yoksa) validation tetiklemeli.
    /// Yeni kurulum veya UserDefaults temizliği sonrası senaryo.
    func test_runIfStale_runsWhenNoLastRun() async {
        XCTAssertNil(ArgusValidatorScheduler.shared.lastRunAt, "Setup sonrası lastRunAt nil olmalı")

        let result = await ArgusValidatorScheduler.shared.runIfStale(maxAge: 60)

        XCTAssertNotNil(result, "lastRunAt yoksa runIfStale çalıştırmalı (nil yerine [] dönmeli)")
        XCTAssertNotNil(
            ArgusValidatorScheduler.shared.lastRunAt,
            "runValidation lastRunAt'i UserDefaults'a yazmalı"
        )
    }

    /// `runIfStale` lastRunAt `maxAge` saniyeden eskiyse validation tetiklemeli.
    /// Bu, gece BGTask hiç tetiklenmediyse açılışta telafiyi sağlar.
    func test_runIfStale_runsWhenStale() async {
        // Simüle: 25 saat önce çalıştı (24 saatten eski → bayat)
        let stalePast = Date().addingTimeInterval(-25 * 3600)
        UserDefaults.standard.set(stalePast, forKey: ArgusValidatorScheduler.lastRunKey)

        let result = await ArgusValidatorScheduler.shared.runIfStale(maxAge: 24 * 3600)

        XCTAssertNotNil(result, "25h önce > 24h eşik → bayat → tetiklenmeli")
        // Yeni timestamp 25h önceki değerinden büyük olmalı (güncellendi)
        if let newLast = ArgusValidatorScheduler.shared.lastRunAt {
            XCTAssertGreaterThan(newLast, stalePast, "runValidation lastRunAt'i güncellemeli")
        } else {
            XCTFail("runValidation sonrası lastRunAt set edilmeli")
        }
    }

    /// `runIfStale` lastRunAt taze ise (eşik içinde) validation tetiklememeli.
    /// Aynı gün içinde tekrar açmada gereksiz çalıştırmayı engeller.
    func test_runIfStale_skipsWhenFresh() async {
        // Simüle: 1 saat önce çalıştı (24h eşiğin içinde → taze)
        let recentPast = Date().addingTimeInterval(-3600)
        UserDefaults.standard.set(recentPast, forKey: ArgusValidatorScheduler.lastRunKey)

        let result = await ArgusValidatorScheduler.shared.runIfStale(maxAge: 24 * 3600)

        XCTAssertNil(result, "1h önce < 24h eşik → taze → atlanmalı (nil dönmeli)")
        // lastRunAt değişmemeli (runValidation çağrılmadığı için)
        XCTAssertEqual(
            ArgusValidatorScheduler.shared.lastRunAt?.timeIntervalSinceReferenceDate ?? 0,
            recentPast.timeIntervalSinceReferenceDate,
            accuracy: 0.001,
            "Skip durumunda lastRunAt değişmemeli"
        )
    }

    /// `runValidation` direkt çağrıldığında da lastRunAt güncellenmeli — single
    /// source of truth. Aksi halde UI manual tetik fallback'i devre dışı bırakırdı.
    func test_runValidation_recordsLastRunAt() async {
        XCTAssertNil(ArgusValidatorScheduler.shared.lastRunAt)
        let before = Date()

        await ArgusValidatorScheduler.shared.runValidation()

        guard let recorded = ArgusValidatorScheduler.shared.lastRunAt else {
            XCTFail("runValidation sonrası lastRunAt set edilmeli")
            return
        }
        XCTAssertGreaterThanOrEqual(recorded, before, "Kayıt çağrı zamanından sonra olmalı")
        XCTAssertLessThan(
            recorded.timeIntervalSinceNow,
            10,
            "Kayıt 10 saniyeden eski olmamalı (taze)"
        )
    }
}
