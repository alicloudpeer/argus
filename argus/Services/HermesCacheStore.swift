import Foundation

final class HermesCacheStore {
    static let shared = HermesCacheStore()
    
    private var cache: [String: HermesSummary] = [:] // Key: ArticleID
    private let fileName = "HermesCache_v1.json"
    private let queue = DispatchQueue(label: "com.argus.hermes.cache", attributes: .concurrent)
    
    private init() {
        loadCache()
    }
    
    // T3.6: Sentiment alpha yarı-ömrü 1-3 saat — 6 saatlik cache stale veri sorunu yarattığından
    // 30 dakikaya düşürüldü. Per-article LLM özet cache'i (haberin metni değişmediği için
    // article yenilense bile aynı kalır, ama sentiment kararı taze olmalı).
    private let summaryCacheTTL: TimeInterval = 30 * 60 // 30 dk

    func getSummary(for articleId: String) -> HermesSummary? {
        queue.sync {
            guard let summary = cache[articleId] else { return nil }
            if Date().timeIntervalSince(summary.createdAt) > summaryCacheTTL {
                return nil
            }
            return summary
        }
    }

    func getSummaries(for symbol: String) -> [HermesSummary] {
        queue.sync {
            return cache.values.filter { $0.symbol == symbol }.sorted(by: { $0.createdAt > $1.createdAt })
        }
    }
    
    func saveSummaries(_ summaries: [HermesSummary]) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            for summary in summaries {
                self.cache[summary.id] = summary
            }
            self.persist()
        }
    }
    
    private func persist() {
        guard let url = getDocumentsURL() else { return }
        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: url)
        } catch {
            print("HermesCache Save Error: \(error)")
        }
    }
    
    private func loadCache() {
        guard let url = getDocumentsURL() else { return }
        do {
            let data = try Data(contentsOf: url)
            cache = try JSONDecoder().decode([String: HermesSummary].self, from: data)
            cleanupOldEntries()
        } catch {
            // First run or corrupt
            cache = [:]
        }
    }
    
    private func cleanupOldEntries() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            let limit: TimeInterval = 7 * 24 * 60 * 60 // 7 days
            let now = Date()
            
            let originalCount = self.cache.count
            self.cache = self.cache.filter { now.timeIntervalSince($0.value.createdAt) < limit }
            
            if self.cache.count < originalCount {
                self.persist()
                print("🧹 HermesCache: \(originalCount - self.cache.count) eski kayıt temizlendi.")
            }
        }
    }
    
    private func getDocumentsURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName)
    }
}
