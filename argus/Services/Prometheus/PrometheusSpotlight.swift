import Foundation

// MARK: - Prometheus Spotlight (T2.23)
// Yüksek-güvenli Prometheus tahmini + Council'ın "kararsız" durumu birleştiğinde
// otopilotun gözden kaçırma riskini azaltmak için ayrı bir "dikkat çekici"
// liste tutar. Scan döngüsü sonunda raporlanır, UI badge'le gösterilir.
//
// Tetikleme koşulu (4'ü birden):
//   1) Prometheus.confidence ≥ 80
//   2) |Prometheus.changePercent| ≥ 5.0
//   3) Council action == .neutral (yani sistem "bilmiyorum" diyor)
//   4) PrometheusTrackRecord.isSpotlightCapable (skill ≥ 0.30, sample ≥ 10)

actor PrometheusSpotlight {
    static let shared = PrometheusSpotlight()

    struct Entry: Sendable, Identifiable {
        let id: String  // symbol
        let symbol: String
        let predictedChange: Double
        let confidence: Double
        let direction: Direction
        let recordedAt: Date

        enum Direction: String, Sendable {
            case up, down
            var emoji: String { self == .up ? "🔺" : "🔻" }
        }

        var summary: String {
            String(format: "%@ %@ %.1f%% (güven %.0f%%)",
                   symbol, direction.emoji, predictedChange, confidence)
        }
    }

    private var entries: [String: Entry] = [:]
    private let staleAfter: TimeInterval = 6 * 3600 // 6 saat

    // MARK: - Tetikleme

    /// Council'dan çağrılır — koşullar sağlanıyorsa kaydı ekler/günceller.
    /// Önceki turdan kalan eski kayıtları da temizler.
    func evaluate(
        symbol: String,
        prometheusChange: Double,
        prometheusConfidence: Double,
        councilAction: String,
        trackRecord: PrometheusTrackRecord.Stats
    ) {
        pruneStale()

        let highConfidence = prometheusConfidence >= 80
        let strongChange = abs(prometheusChange) >= 5.0
        let councilNeutral = councilAction.lowercased().contains("neutral")
            || councilAction.lowercased().contains("hold")
        let recordOK = trackRecord.isSpotlightCapable

        guard highConfidence, strongChange, councilNeutral, recordOK else {
            entries.removeValue(forKey: symbol.uppercased())
            return
        }

        let entry = Entry(
            id: symbol.uppercased(),
            symbol: symbol.uppercased(),
            predictedChange: prometheusChange,
            confidence: prometheusConfidence,
            direction: prometheusChange > 0 ? .up : .down,
            recordedAt: Date()
        )
        entries[entry.id] = entry
    }

    // MARK: - Okuma

    /// Aktif spotlight kayıtları, en güçlü ilk olacak şekilde.
    func currentEntries() -> [Entry] {
        pruneStale()
        return entries.values.sorted { abs($0.predictedChange) > abs($1.predictedChange) }
    }

    func count() -> Int {
        pruneStale()
        return entries.count
    }

    func clear() { entries.removeAll() }

    // MARK: - Bakım

    private func pruneStale() {
        let cutoff = Date().addingTimeInterval(-staleAfter)
        entries = entries.filter { $0.value.recordedAt >= cutoff }
    }
}
