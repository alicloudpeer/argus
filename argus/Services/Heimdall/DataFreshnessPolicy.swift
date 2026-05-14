import Foundation

// MARK: - Data Freshness Policy (T2.01 + T2.02)
// Modül bazlı veri tazelik eşikleri ve bileşik kalite skoru.
// Council kararlarında stale/expired veri için advisory + güven düşürme uygular.

struct DataFreshnessPolicy {

    enum DataType {
        case candle          // Günlük mum verisi
        case fundamentals    // Bilanço / temel veriler
        case quote           // Anlık fiyat kotasyonu
        case news            // Haber akışı
        case macro           // Makro göstergeler (CPI, işsizlik vb.)
    }

    enum Freshness: Comparable {
        case fresh       // Tam güvenilir
        case acceptable  // Kullanılabilir, uyarı yok
        case stale       // Advisory gerektirir
        case expired     // Güven düşürülmeli

        var confidenceMultiplier: Double {
            switch self {
            case .fresh:      return 1.0
            case .acceptable: return 1.0
            case .stale:      return 0.85
            case .expired:    return 0.65
            }
        }
    }

    struct Assessment {
        let dataType: DataType
        let freshness: Freshness
        let ageSeconds: TimeInterval
        let maxAgeSeconds: TimeInterval
    }

    // MARK: - Eşikler (saniye)

    private static func thresholds(for type: DataType) -> (acceptable: TimeInterval, stale: TimeInterval, expired: TimeInterval) {
        switch type {
        case .candle:
            // Günlük mumlar: 1 gün (86400) fresh, 2 gün acceptable, 4 gün stale, 7+ expired
            return (86400 * 2, 86400 * 4, 86400 * 7)
        case .fundamentals:
            // Bilanço: 30 gün acceptable, 90 gün stale, 180+ expired
            return (86400 * 30, 86400 * 90, 86400 * 180)
        case .quote:
            // Anlık fiyat: 15 dk acceptable, 1 saat stale, 4 saat expired
            return (900, 3600, 14400)
        case .news:
            // Haberler: 12 saat acceptable, 2 gün stale, 7+ expired
            return (43200, 86400 * 2, 86400 * 7)
        case .macro:
            // Makro: 7 gün acceptable, 30 gün stale, 90+ expired
            return (86400 * 7, 86400 * 30, 86400 * 90)
        }
    }

    // MARK: - Tek veri tipi değerlendirme

    static func evaluate(type: DataType, lastUpdated: Date?) -> Assessment {
        guard let updated = lastUpdated else {
            return Assessment(dataType: type, freshness: .expired, ageSeconds: .infinity, maxAgeSeconds: 0)
        }

        let age = Date().timeIntervalSince(updated)
        let t = thresholds(for: type)

        let freshness: Freshness
        if age <= t.acceptable {
            freshness = .fresh
        } else if age <= t.stale {
            freshness = .acceptable
        } else if age <= t.expired {
            freshness = .stale
        } else {
            freshness = .expired
        }

        return Assessment(dataType: type, freshness: freshness, ageSeconds: age, maxAgeSeconds: t.expired)
    }

    // MARK: - Bileşik değerlendirme (Council için)

    struct CompositeAssessment {
        let candleFreshness: Assessment
        let fundamentalsFreshness: Assessment?
        let overallConfidenceMultiplier: Double
        let advisoryMessages: [String]
    }

    static func evaluateForCouncil(
        lastCandleDate: Date?,
        financialsLastUpdated: Date?
    ) -> CompositeAssessment {

        let candleAssessment = evaluate(type: .candle, lastUpdated: lastCandleDate)

        let fundAssessment: Assessment?
        if let fundDate = financialsLastUpdated {
            fundAssessment = evaluate(type: .fundamentals, lastUpdated: fundDate)
        } else {
            fundAssessment = nil
        }

        var multiplier = candleAssessment.freshness.confidenceMultiplier
        if let fa = fundAssessment {
            multiplier = min(multiplier, fa.freshness.confidenceMultiplier)
        }

        var messages: [String] = []

        if candleAssessment.freshness >= .stale {
            let days = Int(candleAssessment.ageSeconds / 86400)
            messages.append("Fiyat verisi \(days) gün eski — sinyal güvenilirliği düşük.")
        }

        if let fa = fundAssessment, fa.freshness >= .stale {
            let days = Int(fa.ageSeconds / 86400)
            messages.append("Bilanço verisi \(days) gün eski — temel analiz güncel olmayabilir.")
        }

        return CompositeAssessment(
            candleFreshness: candleAssessment,
            fundamentalsFreshness: fundAssessment,
            overallConfidenceMultiplier: multiplier,
            advisoryMessages: messages
        )
    }
}
