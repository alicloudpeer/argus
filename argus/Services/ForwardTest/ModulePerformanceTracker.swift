import Foundation

// MARK: - Task 11 (2026-05-13): Module Performance Tracker
//
// Yol Haritası §4 Kural 5: "Bir modülün varlık nedeni, yokluğundaki performans
// kaybıdır." Bu actor her Council üyesinin (Orion, Atlas, Aether, Hermes,
// Phoenix, Athena, Demeter, Prometheus, Poseidon) oyunu gerçek trade PnL'iyle
// karşılaştırır ve modül başına hit-rate üretir.
//
// Karşılaştırma kuralları:
// - `buy` + pnl > 0 → correct
// - `buy` + pnl < 0 → incorrect
// - `sell` + pnl < 0 → correct (sell ÖNERİSİ doğruydu; aksiyon = pozisyondan çık)
// - `sell` + pnl > 0 → incorrect
// - `hold` → ne correct ne incorrect (hitRate hesabına girmez, totalVotes++)
// - pnl == 0 → kayıt atlanır (flat trade nötr sinyal)
//
// Sıralama: trade kapanış akışı içinde `closeTrade` → `recordOutcome` →
// `ModulePerformanceTracker.recordTradeOutcome`. PortfolioStore+Trades
// applySellStateMutation içinde structured `Task { }` ile çağrılır.
//
// Persist: `UserDefaults` (basit, in-app, async-safe — actor'ün izole state'i
// her seferinde tek JSON blob olarak diske yazılır). Test izolasyonu için
// `resetForTesting()` mevcut.

actor ModulePerformanceTracker {
    static let shared = ModulePerformanceTracker()

    // MARK: - Stats Model

    struct ModuleStats: Codable, Equatable, Sendable {
        var module: String
        var totalVotes: Int = 0
        var correctVotes: Int = 0
        var incorrectVotes: Int = 0
        var holdVotes: Int = 0
        /// Confidence-ağırlıklı PnL toplam katkısı. Yüksek confidence + doğru oy
        /// → yüksek pozitif değer; yüksek confidence + yanlış oy → yüksek negatif.
        var totalPnLContribution: Double = 0.0

        /// Decisive oyların doğruluk oranı (hold hesaba girmez).
        /// Hiç decisive oy yoksa 0.0 döner.
        var hitRate: Double {
            let decisive = correctVotes + incorrectVotes
            guard decisive > 0 else { return 0.0 }
            return Double(correctVotes) / Double(decisive)
        }
    }

    // MARK: - State

    private var stats: [String: ModuleStats] = [:]
    private let persistKey = "module_performance_stats_v1"

    // MARK: - Init

    init() {
        // Swift 6: actor init is nonisolated; bridge to actor-isolated
        // loadFromDisk() via Task. Brief gap before disk data is loaded is
        // acceptable — all reads are async and will see fresh state.
        Task { await loadFromDisk() }
    }

    // MARK: - Public API

    /// Trade kapanışında çağrılır. PnL == 0 → flat → kayıt atla (nötr sinyal).
    /// PnL > 0 / < 0 → her modülün oyu doğru/yanlış olarak sayılır.
    func recordTradeOutcome(
        decisionId: String,
        actualPnL: Double,
        moduleVotes: [ModuleVoteRecord]
    ) {
        guard actualPnL != 0 else { return }
        let actualUp = actualPnL > 0

        for vote in moduleVotes {
            var s = stats[vote.module] ?? ModuleStats(module: vote.module)
            s.totalVotes += 1
            // Confidence ağırlıklı PnL katkısı — modülün kararlara yön verme
            // gücünün "ne kadar para getirdi/kaybettirdi" özeti.
            s.totalPnLContribution += actualPnL * vote.confidence

            switch vote.action.lowercased() {
            case "buy":
                if actualUp { s.correctVotes += 1 } else { s.incorrectVotes += 1 }
            case "sell":
                if !actualUp { s.correctVotes += 1 } else { s.incorrectVotes += 1 }
            case "hold":
                s.holdVotes += 1
            default:
                // Beklenmeyen action stringi — sayma. ModuleVoteRecord.action
                // canonical "buy"/"sell"/"hold" şartı kaynak tarafında garanti.
                break
            }
            stats[vote.module] = s
        }

        persistToDisk()
    }

    func getStats(module: String) -> ModuleStats {
        stats[module] ?? ModuleStats(module: module)
    }

    func getAllStats() -> [ModuleStats] {
        Array(stats.values).sorted { $0.module < $1.module }
    }

    /// Test izolasyonu. tearDown'da çağrılır → her test sıfır state ile başlar.
    func resetForTesting() {
        stats = [:]
        persistToDisk()
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: persistKey),
              let decoded = try? JSONDecoder().decode([String: ModuleStats].self, from: data) else {
            return
        }
        stats = decoded
    }

    private func persistToDisk() {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        UserDefaults.standard.set(data, forKey: persistKey)
    }
}
