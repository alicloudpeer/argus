import Foundation

// MARK: - Cooldown Registry (T2.22)
// Trade cooldown'larının tek gerçek kaynağı. Daha önce AlertManager, TradeBrainExecutor,
// AgoraExecutionGovernor ve PortfolioRiskManager ayrı ayrı izliyordu — bu duplikasyon
// tutarsız cooldown davranışına yol açabiliyordu.
//
// API cooldown'ları (Cerebras/Gemini 429) ve SymbolBlocklist (6 saatlik data ban)
// bu registry kapsamı dışında — farklı katman, farklı yaşam döngüsü.

actor CooldownRegistry {
    static let shared = CooldownRegistry()

    enum CooldownType: String, Sendable {
        case postTrade       // İşlem sonrası (aynı sembolde tekrar alma/satma engeli)
        case postSell        // Satış sonrası yeniden giriş bekleme süresi
        case minHold         // Minimum pozisyon tutma süresi
    }

    private struct CooldownEntry {
        let type: CooldownType
        let expiresAt: Date
        let reason: String
    }

    private var entries: [String: [CooldownEntry]] = [:]

    // MARK: - Cooldown Başlatma

    func enter(symbol: String, type: CooldownType, duration: TimeInterval, reason: String = "") {
        let entry = CooldownEntry(
            type: type,
            expiresAt: Date().addingTimeInterval(duration),
            reason: reason
        )
        entries[symbol, default: []].append(entry)
        pruneExpired(symbol: symbol)
    }

    // MARK: - Cooldown Sorgulama

    func isInCooldown(_ symbol: String, type: CooldownType? = nil) -> Bool {
        remaining(symbol, type: type) != nil
    }

    func remaining(_ symbol: String, type: CooldownType? = nil) -> TimeInterval? {
        guard let list = entries[symbol] else { return nil }
        let now = Date()
        let active = list.filter { entry in
            entry.expiresAt > now && (type == nil || entry.type == type)
        }
        guard let latest = active.max(by: { $0.expiresAt < $1.expiresAt }) else { return nil }
        return latest.expiresAt.timeIntervalSince(now)
    }

    struct CooldownStatus: Sendable {
        let type: CooldownType
        let remainingSeconds: TimeInterval
        let reason: String
    }

    func allActive(for symbol: String) -> [CooldownStatus] {
        let now = Date()
        pruneExpired(symbol: symbol)
        return (entries[symbol] ?? []).compactMap { entry in
            let rem = entry.expiresAt.timeIntervalSince(now)
            guard rem > 0 else { return nil }
            return CooldownStatus(type: entry.type, remainingSeconds: rem, reason: entry.reason)
        }
    }

    // MARK: - Manuel Temizleme

    func clear(symbol: String, type: CooldownType? = nil) {
        if let type = type {
            entries[symbol]?.removeAll { $0.type == type }
        } else {
            entries.removeValue(forKey: symbol)
        }
    }

    func clearAll() {
        entries.removeAll()
    }

    // MARK: - İç Temizleme

    private func pruneExpired(symbol: String) {
        let now = Date()
        entries[symbol]?.removeAll { $0.expiresAt <= now }
        if entries[symbol]?.isEmpty == true {
            entries.removeValue(forKey: symbol)
        }
    }
}
