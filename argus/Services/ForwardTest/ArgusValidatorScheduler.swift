import Foundation
import BackgroundTasks

/// Faz 0 Task 3: ArgusValidator gece otomatik tetikleyici + açılışta yakala fallback.
///
/// Eski Argus'ta `validateMaturedHypotheses` sadece UI butonundan tetiklenebiliyordu
/// (`ArgusScientificDashboardCard.runValidation`). Forward test'in bilimsel omurga
/// olabilmesi için tetikleme **otomatik** olmalı.
///
/// **İki katmanlı strateji:**
///
/// 1. **Gece BGTask** — `BGAppRefreshTask` her gece 03:00 hedefli. iOS sınırları:
///    - Cihaz uygunluğu (şarj, idle, network) sistem tarafından değerlendirilir
///    - Görev başına ~30 saniye CPU bütçesi (App Refresh, yoğun iş yok)
///    - `register` app launch'ta TEK kez çağrılmalı, `scheduleNextRun` her tetikten sonra
///    - **iOS garanti vermez:** cihaz hiç şarjda olmazsa, kullanıcı Background App Refresh'i
///      kapatmışsa veya app uzun süre açılmamışsa, BGTask hiç tetiklenmeyebilir.
///
/// 2. **Açılışta yakala (runIfStale)** — App her açıldığında `UserDefaults`'taki
///    son çalışma zamanını kontrol eder. 24 saatten geçmişse validator'ı tetikler.
///    Bu sayede iOS BGTask güvenilmezliği telafi edilir: kullanıcı uygulamayı her
///    açtığında en geç 24 saatte bir validation garanti altına alınır.
///
/// Manual UI tetik korunur (kullanıcı acil görmek istediğinde).
@MainActor
final class ArgusValidatorScheduler {
    static let shared = ArgusValidatorScheduler()

    /// Info.plist `BGTaskSchedulerPermittedIdentifiers` ile birebir eşleşmeli.
    /// Apple BGTaskScheduler identifier'ın PRODUCT_BUNDLE_IDENTIFIER ile başlamasını
    /// zorunlu kılar — aksi halde `submit()` her zaman BGTaskSchedulerErrorDomain
    /// error 3 (notPermitted) atar. Bu nedenle prefix `ArgusTeam.argus`.
    static let taskIdentifier = "ArgusTeam.argus.validator.daily"

    /// Hedef tetikleme saati (lokal). iOS bu saati `earliestBeginDate` olarak alır;
    /// gerçek tetikleme cihaz uygunluğuna göre sonrasında olabilir.
    private static let targetHour = 3
    private static let targetMinute = 0

    /// "Açılışta yakala" fallback için son çalışma zamanını saklayan UserDefaults anahtarı.
    /// BGTask başarısız olursa veya cihaz uygun olmazsa, app açılışında bu key okunur,
    /// 24 saatten geçmişse `runIfStale` tetiklenir.
    static let lastRunKey = "argus.validator.lastRunAt"

    /// Açılışta-yakala varsayılan eşiği: 24 saat. Argus normalde günde bir validate
    /// çalıştırmayı hedefliyor; 24 saatten uzun süredir koşmadıysa "bayat" sayılır.
    static let defaultStaleThreshold: TimeInterval = 86_400

    private init() {}

    // MARK: - Last-run persistence (Açılışta yakala fallback)

    /// En son ne zaman validation tamamlandı? `nil` ise hiç çalıştırılmamış demek
    /// (yeni kurulum veya UserDefaults temizliği sonrası).
    var lastRunAt: Date? {
        UserDefaults.standard.object(forKey: Self.lastRunKey) as? Date
    }

    /// Tüm tetikleme yolları (BGTask handler, açılışta yakala, manual UI) bu metodu
    /// runValidation sonrası çağırır — single source of truth for "son ne zaman koştu".
    private func recordRun(at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: Self.lastRunKey)
    }

    // MARK: - Register (app launch)

    /// `BGTaskScheduler`'a görev kimliğini tanıt. App init'inde TEK kez çağrılır.
    /// İkinci kez çağrılırsa iOS uyarı verir ama assertion atmaz.
    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            // Singleton'a [weak self] gerekmez (lifetime app yaşamı boyunca).
            // Runtime'da iOS BGProcessingTask da gönderebilir (örn. identifier
            // çakışması, ileride app refresh dışı bir tipe geçilirse); bu yüzden
            // `as!` yerine guard let — yanlış tip gelirse görevi başarısız işaretle,
            // çökme yerine graceful fail.
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            // MainActor sınırlama altında handleAppRefresh çağrısı için Task içine al.
            Task { @MainActor in
                ArgusValidatorScheduler.shared.handleAppRefresh(task: refreshTask)
            }
        }
    }

    // MARK: - Schedule

    /// Sıradaki run'ı planla. iOS'a "şu tarihten ÖNCE tetikleme" der; sistem
    /// uygun bir an seçer. Cihaz şarjda değilse, network yoksa ertelenebilir.
    func scheduleNextRun() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = nextRunDate()
        do {
            try BGTaskScheduler.shared.submit(request)
            ArgusLogger.info(.autopilot, "Validator BGTask planlandı → \(request.earliestBeginDate.map { "\($0)" } ?? "-")")
        } catch {
            // Simülatörde veya entitlement eksik durumda fail edebilir — fatal değil.
            ArgusLogger.warning(.autopilot, "Validator BGTask submit başarısız: \(error.localizedDescription)")
        }
    }

    /// Lokal saatte bir sonraki 03:00. Şu an 03:00'dan sonraysa yarın 03:00.
    /// `internal` (default) — `@testable import` ile test'lerden çağrılabilir;
    /// public API yüzeyinde değil.
    func nextRunDate() -> Date {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = Self.targetHour
        components.minute = Self.targetMinute

        guard let candidate = calendar.date(from: components) else {
            return now.addingTimeInterval(60 * 60 * 24) // güvenli fallback: 24 saat
        }
        if candidate <= now {
            return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }

    // MARK: - Run (tetikleme + manuel kullanım)

    /// Validator'ı çalıştır ve sonuç sayısını döndür. Test'ler, UI manual tetik
    /// ve BGTask handler'ı için tek geçit. Tamamlanınca `lastRunAt` UserDefaults'a
    /// yazılır — açılışta-yakala fallback bu zamanı bakar.
    @discardableResult
    func runValidation() async -> [ForwardTestResult] {
        let results = await ArgusValidator.shared.validateMaturedHypotheses()
        recordRun()
        return results
    }

    /// **Açılışta yakala** — uygulamanın her açılışında çağrılır. Son çalışma
    /// zamanından `maxAge` saniyeden uzun süre geçtiyse validator tetiklenir;
    /// daha yeniyse atlanır (gereksiz tekrar engellenir).
    ///
    /// Bu metod iOS BGTask güvenilmezliğine karşı gardırop: cihaz hiç şarjda olmadıysa,
    /// kullanıcı Background App Refresh'i kapattıysa, app uzun süre açılmadıysa —
    /// BGTask hiç tetiklenmemiş olabilir. Kullanıcı uygulamayı her açtığında
    /// en geç 24 saatte bir validation garanti altına alınır.
    ///
    /// - Parameter maxAge: "Bayat" eşiği. Varsayılan 24 saat. Test'lerden farklı
    ///   değerle çağrılabilir (örn. 1 saniye → kesin tetikle).
    /// - Returns: Validation tetiklendiyse sonuç array, atlandıysa `nil`.
    @discardableResult
    func runIfStale(maxAge: TimeInterval = ArgusValidatorScheduler.defaultStaleThreshold) async -> [ForwardTestResult]? {
        if let last = lastRunAt, Date().timeIntervalSince(last) < maxAge {
            ArgusLogger.info(.autopilot, "Validator runIfStale: taze (\(Int(Date().timeIntervalSince(last)))s önce), atlandı")
            return nil
        }
        ArgusLogger.info(.autopilot, "Validator runIfStale: bayat, tetikleniyor (last=\(lastRunAt.map { "\($0)" } ?? "hiç"))")
        return await runValidation()
    }

    // MARK: - Handler

    /// iOS tetiklediğinde çalışır. ÖNCE sıradaki run'ı planlar (cron zincirini
    /// kaybetmemek için), SONRA validator'ı koşturur, sonuca göre `setTaskCompleted`.
    private func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleNextRun()

        let operation = Task { @MainActor in
            let results = await runValidation()
            ArgusLogger.info(.autopilot, "Validator: \(results.count) hipotez olgunlaştırıldı")
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            operation.cancel()
            ArgusLogger.warning(.autopilot, "Validator BGTask iOS expiration ile iptal edildi")
        }
    }
}
