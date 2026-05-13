import Foundation
import BackgroundTasks

/// Faz 0 Task 3: ArgusValidator gece otomatik tetikleyici.
///
/// Eski Argus'ta `validateMaturedHypotheses` sadece UI butonundan tetiklenebiliyordu
/// (`ArgusScientificDashboardCard.runValidation`). Forward test'in bilimsel omurga
/// olabilmesi için tetikleme **otomatik** olmalı.
///
/// Mekanizma: `BGAppRefreshTask` ile her gece 03:00'da çalış, olgunlaşmış kararları
/// gerçek piyasa fiyatıyla karşılaştır, sonuçları ledger'a yaz. iOS şu sınırları getirir:
/// - Cihaz uygunluğu (şarj, idle, network) sistem tarafından değerlendirilir
/// - Görev başına ~30 saniye CPU bütçesi (App Refresh, yoğun iş yok)
/// - `register` app launch'ta TEK kez çağrılmalı, `scheduleNextRun` her tetikten sonra
///
/// Manual UI tetik korunur (kullanıcı acil görmek istediğinde) — bu scheduler
/// sadece "varsayılan: günde bir" arka plan zincirini sağlar.
@MainActor
final class ArgusValidatorScheduler {
    static let shared = ArgusValidatorScheduler()

    /// Info.plist `BGTaskSchedulerPermittedIdentifiers` ile birebir eşleşmeli.
    static let taskIdentifier = "com.argus.validator.daily"

    /// Hedef tetikleme saati (lokal). iOS bu saati `earliestBeginDate` olarak alır;
    /// gerçek tetikleme cihaz uygunluğuna göre sonrasında olabilir.
    private static let targetHour = 3
    private static let targetMinute = 0

    private init() {}

    // MARK: - Register (app launch)

    /// `BGTaskScheduler`'a görev kimliğini tanıt. App init'inde TEK kez çağrılır.
    /// İkinci kez çağrılırsa iOS uyarı verir ama assertion atmaz.
    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self else { return }
            // weak self gereklidir: BGTaskScheduler handler'ı uzun yaşar; singleton
            // zaten yaşam boyu var ama hijyen için. MainActor sınırlama altında
            // `handleAppRefresh` çağrısı için Task içine al.
            Task { @MainActor in
                self.handleAppRefresh(task: task as! BGAppRefreshTask)
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
    private func nextRunDate() -> Date {
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

    /// Validator'ı çalıştır ve sonuç sayısını döndür. Test'ler ve UI manual tetik
    /// için bu wrapper kullanılabilir — BGTask'ten bağımsız tek geçit.
    @discardableResult
    func runValidation() async -> [ForwardTestResult] {
        await ArgusValidator.shared.validateMaturedHypotheses()
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
