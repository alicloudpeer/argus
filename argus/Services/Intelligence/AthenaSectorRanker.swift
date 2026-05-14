import Foundation

// MARK: - Athena Sector Ranker (T2.09)
// Athena tek hisseyi izole skorlar — bu actor son N skoru sektör bazında biriktirir
// ve yeni hissenin sektör içinde percentile rank'ini hesaplar.
// "Tech sektöründe momentum açısından üst %20'desin" gibi cross-sectional bilgi üretir.

actor AthenaSectorRanker {
    static let shared = AthenaSectorRanker()

    private struct ScoreEntry {
        let symbol: String
        let factorScore: Double
        let quality: Double
        let momentum: Double
        let recordedAt: Date
    }

    private var bySector: [String: [ScoreEntry]] = [:]
    private let maxPerSector: Int = 50
    private let staleAfter: TimeInterval = 7 * 86400 // 7 gün

    // MARK: - Skor Kaydı

    func record(symbol: String, sector: String?, result: AthenaFactorResult) {
        guard let sectorKey = sector?.lowercased(), !sectorKey.isEmpty else { return }
        let entry = ScoreEntry(
            symbol: symbol.uppercased(),
            factorScore: result.factorScore,
            quality: result.qualityFactorScore,
            momentum: result.momentumFactorScore,
            recordedAt: Date()
        )
        var list = bySector[sectorKey, default: []]
        list.removeAll { $0.symbol == entry.symbol }
        list.append(entry)
        pruneSector(&list)
        bySector[sectorKey] = list
    }

    // MARK: - Percentile Sorgulama

    struct SectorRank: Sendable {
        let sector: String
        let percentile: Double      // 0-100 — bu hissenin sektör içindeki yeri
        let peerCount: Int
        let medianScore: Double
        let isTopQuintile: Bool     // Üst %20
        let isBottomQuintile: Bool  // Alt %20
        let summary: String
    }

    func rank(symbol: String, sector: String?, factorScore: Double) -> SectorRank? {
        guard let sectorKey = sector?.lowercased(), !sectorKey.isEmpty,
              var list = bySector[sectorKey], list.count >= 5 else {
            return nil
        }
        pruneSector(&list)
        bySector[sectorKey] = list

        let scores = list.map { $0.factorScore }.sorted()
        guard !scores.isEmpty else { return nil }

        let below = scores.filter { $0 < factorScore }.count
        let percentile = (Double(below) / Double(scores.count)) * 100

        let median: Double
        if scores.count % 2 == 0 {
            median = (scores[scores.count / 2 - 1] + scores[scores.count / 2]) / 2
        } else {
            median = scores[scores.count / 2]
        }

        let summary: String
        if percentile >= 80 {
            summary = "Sektörde üst %\(Int(100 - percentile)) (örneklem: \(scores.count))"
        } else if percentile <= 20 {
            summary = "Sektörde alt %\(Int(percentile)) (örneklem: \(scores.count))"
        } else {
            summary = "Sektör ortalaması civarında (P\(Int(percentile)), örneklem: \(scores.count))"
        }

        return SectorRank(
            sector: sectorKey,
            percentile: percentile,
            peerCount: scores.count,
            medianScore: median,
            isTopQuintile: percentile >= 80,
            isBottomQuintile: percentile <= 20,
            summary: summary
        )
    }

    // MARK: - Cache Temizleme

    private func pruneSector(_ list: inout [ScoreEntry]) {
        let cutoff = Date().addingTimeInterval(-staleAfter)
        list.removeAll { $0.recordedAt < cutoff }
        if list.count > maxPerSector {
            list = Array(list.suffix(maxPerSector))
        }
    }

    func clear() { bySector.removeAll() }

    // MARK: - Tanılama

    func sectorStats() -> [String: (count: Int, medianScore: Double)] {
        var result: [String: (Int, Double)] = [:]
        for (sector, entries) in bySector {
            let scores = entries.map { $0.factorScore }.sorted()
            guard !scores.isEmpty else { continue }
            let median: Double
            if scores.count % 2 == 0 {
                median = (scores[scores.count / 2 - 1] + scores[scores.count / 2]) / 2
            } else {
                median = scores[scores.count / 2]
            }
            result[sector] = (scores.count, median)
        }
        return result
    }
}
